//
// WearablesViewModel.swift
//
// Owns the two smallest DAT SDK concerns an integration needs first:
// - Registration: pairing this app with Meta AI so it becomes a permitted integration.
// - Connection lifecycle: creating a DeviceSession and observing its state
//   (idle/starting/started/paused/stopping/stopped) once registered.
//
// Camera/display capabilities are deliberately out of scope here — see
// /connect-api and /add-device-sensors style follow-ups once this slice is verified.
//

import Combine
import MWDATCore
import SwiftUI

// Uses Combine's ObservableObject rather than the iOS 17-only @Observable
// macro, since this project's deployment target is iOS 16.0.
@MainActor
final class WearablesViewModel: ObservableObject {
  @Published var registrationState: RegistrationState
  @Published var sessionState: DeviceSessionState?
  @Published var hasActiveDevice: Bool = false
  @Published var showError = false
  @Published var errorMessage = ""
  /// Rolling log of connection-relevant events, newest first, for the
  /// Settings screen's glasses diagnostics -- not full SDK logging, just
  /// enough to see what happened in what order when something goes wrong.
  @Published private(set) var eventLog: [String] = []

  private var registrationTask: Task<Void, Never>?
  private var sessionTask: Task<Void, Never>?
  private var deviceMonitorTask: Task<Void, Never>?
  private var deviceSession: DeviceSession?
  private let wearables: WearablesInterface
  // Held for the view model's lifetime and subscribed to immediately below --
  // AutoDeviceSelector only resolves an active device for a selector that's
  // actually being observed, so a fresh, never-subscribed instance created
  // right before createSession() sees no eligible device even once one exists.
  private let deviceSelector: AutoDeviceSelector

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.registrationState = wearables.registrationState
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)

    registrationTask = Task {
      for await state in wearables.registrationStateStream() {
        self.registrationState = state
        self.log("Registration: \(state)")
      }
    }

    deviceMonitorTask = Task {
      for await deviceId in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = deviceId != nil
        self.log(deviceId != nil ? "Device active" : "No active device")
      }
    }
  }

  deinit {
    registrationTask?.cancel()
    sessionTask?.cancel()
    deviceMonitorTask?.cancel()
  }

  // MARK: - Registration

  func connectGlasses() {
    guard registrationState != .registering else { return }
    log("Connect Glasses tapped")
    Task {
      do {
        try await wearables.startRegistration()
      } catch {
        log("startRegistration failed: \(error.localizedDescription)")
        showError(error.localizedDescription)
      }
    }
  }

  func disconnectGlasses() {
    log("Disconnect Glasses tapped")
    Task {
      do {
        try await wearables.startUnregistration()
      } catch {
        log("startUnregistration failed: \(error.localizedDescription)")
        showError(error.localizedDescription)
      }
    }
  }

  /// Unregisters, then re-registers from a clean slate -- a stronger reset
  /// than Connect/Disconnect separately, for when registration looks stuck
  /// (e.g. bounces to Meta AI and back with no visible change).
  func resetRegistration() {
    log("Reset Registration tapped")
    Task {
      do {
        if registrationState == .registered {
          try await wearables.startUnregistration()
        }
        try await wearables.startRegistration()
      } catch {
        log("Reset Registration failed: \(error.localizedDescription)")
        showError(error.localizedDescription)
      }
    }
  }

  /// The single "try to fix it" action: register if not registered yet,
  /// otherwise (re)start the device session.
  func reconnect() {
    log("Reconnect tapped")
    if registrationState == .registered {
      startSession()
    } else {
      connectGlasses()
    }
  }

  // MARK: - URL handling

  /// Completes the registration/permission round-trip after Meta AI redirects
  /// back into this app via its URL scheme. Previously called directly as
  /// `try? await Wearables.shared.handleUrl(url)` from BrixiApp's `onOpenURL`
  /// -- the `try?` silently dropped any failure, so a round-trip that didn't
  /// actually complete (e.g. an unsupported device) looked to the user like
  /// nothing happened at all, with no error shown anywhere.
  func handleUrl(_ url: URL) {
    log("Opened by URL from Meta AI")
    Task {
      do {
        _ = try await wearables.handleUrl(url)
        log("handleUrl completed")
      } catch {
        log("handleUrl failed: \(error.localizedDescription)")
        showError(error.localizedDescription)
      }
    }
  }

  // MARK: - Connection lifecycle

  func startSession() {
    guard deviceSession == nil else { return }
    log("Starting session")
    do {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      try session.start()
      deviceSession = session

      sessionTask = Task {
        for await state in session.stateStream() {
          self.sessionState = state
          self.log("Session: \(state)")
          if state == .stopped {
            self.deviceSession = nil
          }
        }
      }
    } catch {
      log("startSession failed: \(error.localizedDescription)")
      showError(error.localizedDescription)
    }
  }

  func stopSession() {
    log("Stopping session")
    deviceSession?.stop()
  }

  // MARK: - Permissions

  /// Where the DAT camera grant stands, as a tri-state: DAT's own
  /// `PermissionStatus` only has `.granted`/`.denied`, with no
  /// not-determined -- but `checkPermissionStatus` also throws when there's
  /// no connected device to read the grant off of, and that throw means
  /// "unknown", not "denied". Folding it into `.denied` would show a
  /// disconnected-but-otherwise-fine setup as if camera access had been
  /// refused.
  enum CameraAccess {
    case unknown
    case granted
    case denied
  }

  func checkCameraAccess() async -> CameraAccess {
    do {
      let status = try await wearables.checkPermissionStatus(.camera)
      return status == .granted ? .granted : .denied
    } catch {
      return .unknown
    }
  }

  // MARK: - Camera stream test

  @Published private(set) var isTestingStream = false
  @Published private(set) var streamTestResult: String?

  /// Exercises the full session → camera → stream pipeline for one photo --
  /// the same path "Scan with Glasses" uses -- so the health check surfaces
  /// the same specific failure reason a real scan would hit.
  func testCameraStream() async {
    isTestingStream = true
    streamTestResult = nil
    log("Testing camera stream")
    defer { isTestingStream = false }
    do {
      _ = try await CameraCaptureController(wearables: wearables).captureOnePhoto()
      streamTestResult = "Camera stream works — captured a test photo."
      log("Camera stream test succeeded")
    } catch {
      streamTestResult = error.localizedDescription
      log("Camera stream test failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Errors

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func dismissError() {
    showError = false
  }

  // MARK: - Diagnostics

  private func log(_ message: String) {
    let timestamp = Date().formatted(date: .omitted, time: .standard)
    eventLog.insert("\(timestamp)  \(message)", at: 0)
    if eventLog.count > 50 {
      eventLog.removeLast()
    }
  }
}
