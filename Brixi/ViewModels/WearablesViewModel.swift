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
  @Published var showError = false
  @Published var errorMessage = ""

  private var registrationTask: Task<Void, Never>?
  private var sessionTask: Task<Void, Never>?
  private var deviceSession: DeviceSession?
  private let wearables: WearablesInterface

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.registrationState = wearables.registrationState

    registrationTask = Task {
      for await state in wearables.registrationStateStream() {
        self.registrationState = state
      }
    }
  }

  deinit {
    registrationTask?.cancel()
    sessionTask?.cancel()
  }

  // MARK: - Registration

  func connectGlasses() {
    guard registrationState != .registering else { return }
    Task {
      do {
        try await wearables.startRegistration()
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  func disconnectGlasses() {
    Task {
      do {
        try await wearables.startUnregistration()
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  // MARK: - Connection lifecycle

  func startSession() {
    guard deviceSession == nil else { return }
    do {
      let selector = AutoDeviceSelector(wearables: wearables)
      let session = try wearables.createSession(deviceSelector: selector)
      try session.start()
      deviceSession = session

      sessionTask = Task {
        for await state in session.stateStream() {
          self.sessionState = state
          if state == .stopped {
            self.deviceSession = nil
          }
        }
      }
    } catch {
      showError(error.localizedDescription)
    }
  }

  func stopSession() {
    deviceSession?.stop()
  }

  // MARK: - Errors

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func dismissError() {
    showError = false
  }
}
