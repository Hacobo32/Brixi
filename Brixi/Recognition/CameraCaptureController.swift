//
// CameraCaptureController.swift
//
// Wraps the DAT SDK's session -> camera -> stream -> capture lifecycle
// behind a single async call, so recognition callers don't need to manage
// DeviceSession/Stream state themselves. Modeled directly on Meta's own
// CameraAccess sample app (facebook/meta-wearables-dat-ios,
// samples/CameraAccess/CameraAccess/ViewModels/CameraViewModel.swift) and
// its bundled camera-streaming skill guide -- not guessed.
//
// Each call is a self-contained single-shot capture: start a session,
// start a camera stream, capture one photo, tear everything down again.
// Recognition only needs one frame at a time, not a persistent live
// preview, so there's no reason to hold a session open between captures.

import Foundation
import MWDATCamera
import MWDATCore
import os

enum CameraCaptureError: Error, LocalizedError {
  case sessionFailed(String)
  case streamFailed(String)
  case permissionDenied
  case captureFailed

  var errorDescription: String? {
    switch self {
    case .sessionFailed(let message):
      return "Couldn't connect to glasses: \(message)"
    case .streamFailed(let message):
      return "Couldn't start the camera: \(message)"
    case .permissionDenied:
      return "Camera permission was denied."
    case .captureFailed:
      return "Couldn't capture a photo. Try again."
    }
  }
}

@MainActor
final class CameraCaptureController {
  private let wearables: WearablesInterface

  init(wearables: WearablesInterface = Wearables.shared) {
    self.wearables = wearables
  }

  func captureOnePhoto() async throws -> Data {
    let session: DeviceSession
    do {
      let selector = AutoDeviceSelector(wearables: wearables)
      session = try wearables.createSession(deviceSelector: selector)
      try session.start()
    } catch {
      throw CameraCaptureError.sessionFailed(error.localizedDescription)
    }
    defer { session.stop() }

    try await waitForSessionStarted(session)
    try await ensureCameraPermission()

    // Codec/resolution/frame rate as the SDK's own documentation presents
    // them for a standard capture -- lower settings trade spatial detail
    // for less Bluetooth compression artifacting; worth tuning against
    // real recognition accuracy once tested.
    let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 24)
    guard let camera = try session.addCamera(config: config) else {
      throw CameraCaptureError.streamFailed("Session wasn't ready for a camera.")
    }
    defer { camera.stop() }

    let stream = camera.stream
    try await waitForStreaming(stream)
    return try await capturePhoto(from: stream)
  }

  // MARK: - Session

  private func waitForSessionStarted(_ session: DeviceSession) async throws {
    for await state in session.stateStream() {
      if state == .started { return }
      if state == .stopped {
        throw CameraCaptureError.sessionFailed("Session ended before it started.")
      }
    }
  }

  // MARK: - Permission

  private func ensureCameraPermission() async throws {
    if try await wearables.checkPermissionStatus(.camera) == .granted { return }
    guard try await wearables.requestPermission(.camera) == .granted else {
      throw CameraCaptureError.permissionDenied
    }
  }

  // MARK: - Stream

  private func waitForStreaming(_ stream: MWDATCamera.Stream) async throws {
    let bag = ListenerTokenBag()
    let didResume = OSAllocatedUnfairLock(initialState: false)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stream.statePublisher.listen { state in
        switch state {
        case .streaming:
          let shouldResume = didResume.withLock { resumed in
            guard !resumed else { return false }
            resumed = true
            return true
          }
          guard shouldResume else { return }
          bag.clear()
          continuation.resume()
        case .stopped:
          let shouldResume = didResume.withLock { resumed in
            guard !resumed else { return false }
            resumed = true
            return true
          }
          guard shouldResume else { return }
          bag.clear()
          continuation.resume(throwing: CameraCaptureError.streamFailed("Stream stopped before it started."))
        default:
          break
        }
      }.store(in: bag)
      stream.start()
    }
  }

  private func capturePhoto(from stream: MWDATCamera.Stream) async throws -> Data {
    let bag = ListenerTokenBag()
    let didResume = OSAllocatedUnfairLock(initialState: false)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      stream.photoDataPublisher.listen { photoData in
        let shouldResume = didResume.withLock { resumed in
          guard !resumed else { return false }
          resumed = true
          return true
        }
        guard shouldResume else { return }
        bag.clear()
        continuation.resume(returning: photoData.data)
      }.store(in: bag)

      guard stream.capturePhoto(format: .jpeg) else {
        let shouldResume = didResume.withLock { resumed in
          guard !resumed else { return false }
          resumed = true
          return true
        }
        if shouldResume {
          continuation.resume(throwing: CameraCaptureError.captureFailed)
        }
        return
      }
    }
  }
}
