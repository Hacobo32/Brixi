//
// PhoneCameraFrameSource.swift
//
// Live phone-camera capture, so Brixi works fully with just an iPhone --
// no glasses required (the phone-first product decision). Owns the
// AVCaptureSession directly so a live preview (CameraPreviewView) can bind
// to it; captureOneFrame() satisfies FrameSource the same way
// GlassesFrameSource does, so the rest of the app doesn't care which
// source is active.
//

// AVFoundation predates Swift's Sendable annotations; @preconcurrency treats
// its unmarked types (AVCaptureSession, AVCapturePhotoOutput, etc.) as
// implicitly safe across the closures below, instead of warning on every
// capture of them.
@preconcurrency import AVFoundation
import Foundation
import os

enum PhoneCameraError: Error, LocalizedError {
  case permissionDenied
  case configurationFailed
  case captureFailed(String)

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "Camera access was denied."
    case .configurationFailed:
      return "Couldn't set up the camera."
    case .captureFailed(let message):
      return "Couldn't capture a photo: \(message)"
    }
  }
}

final class PhoneCameraFrameSource: NSObject, FrameSource, @unchecked Sendable {
  /// Bound to a preview layer by CameraPreviewView. AVCaptureSession is
  /// internally thread-safe for this kind of read/bind usage; all
  /// configuration and start/stop calls happen on sessionQueue below, per
  /// Apple's guidance to keep session control off the main thread.
  let session = AVCaptureSession()

  private let photoOutput = AVCapturePhotoOutput()
  private let sessionQueue = DispatchQueue(label: "com.brixi.phonecamera.session")

  private struct State {
    var isConfigured = false
    var pendingCapture: CheckedContinuation<Data, Error>?
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

  func start() async throws {
    try await ensurePermission()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      sessionQueue.async { [self] in
        do {
          let needsConfiguration = state.withLock { !$0.isConfigured }
          if needsConfiguration {
            try configureSession()
            state.withLock { $0.isConfigured = true }
          }
          if !session.isRunning {
            session.startRunning()
          }
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stop() {
    sessionQueue.async { [session] in
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  /// Bounded so a capture that never gets a delegate callback (no photo,
  /// no error -- seen live: the UI hung indefinitely with no feedback)
  /// fails with a real error instead of hanging forever. The abandoned
  /// continuation, if the delegate does eventually fire for it, resumes
  /// harmlessly into nothing -- safe, not a second resume of anything
  /// still being awaited.
  func captureOneFrame() async throws -> Data {
    try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
          self.state.withLock { $0.pendingCapture = continuation }
          self.sessionQueue.async { [photoOutput = self.photoOutput] in
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
          }
        }
      }
      group.addTask {
        try await Task.sleep(for: .seconds(8))
        throw PhoneCameraError.captureFailed("Timed out waiting for the camera.")
      }
      defer { group.cancelAll() }
      return try await group.next()!
    }
  }

  /// Captures `count` stills in quick succession (docs/pile-mode-spec.md
  /// §4.1: "take 3 frames about 150 ms apart"), so BlurDetector.sharpest
  /// can pick the least shaky one. Calls are sequential -- there's only
  /// ever one in-flight capture slot -- which is fine since each await
  /// already waits for the previous photo to finish processing before
  /// triggering the next.
  func captureBurst(count: Int = 3, intervalMs: UInt64 = 150) async throws -> [Data] {
    var frames: [Data] = []
    for index in 0..<count {
      frames.append(try await captureOneFrame())
      if index < count - 1 {
        try await Task.sleep(for: .milliseconds(intervalMs))
      }
    }
    return frames
  }

  // MARK: - Permission

  private func ensurePermission() async throws {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return
    case .notDetermined:
      guard await AVCaptureDevice.requestAccess(for: .video) else {
        throw PhoneCameraError.permissionDenied
      }
    default:
      throw PhoneCameraError.permissionDenied
    }
  }

  // MARK: - Session setup

  private func configureSession() throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    session.sessionPreset = .photo

    guard
      let device = Self.preferredCameraDevice(),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      throw PhoneCameraError.configurationFailed
    }
    session.addInput(input)

    guard session.canAddOutput(photoOutput) else {
      throw PhoneCameraError.configurationFailed
    }
    session.addOutput(photoOutput)
  }

  /// Back camera, then front, then whatever the system reports as the
  /// default video device regardless of type -- the Simulator's own
  /// camera (via the Mac's webcam passthrough) doesn't self-report as
  /// .builtInWideAngleCamera the way a real device's cameras do, so the
  /// specific-type lookups alone return nil there.
  private static func preferredCameraDevice() -> AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
      ?? AVCaptureDevice.default(for: .video)
  }
}

extension PhoneCameraFrameSource: AVCapturePhotoCaptureDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    let continuation = state.withLock { state -> CheckedContinuation<Data, Error>? in
      let pending = state.pendingCapture
      state.pendingCapture = nil
      return pending
    }

    if let error {
      continuation?.resume(throwing: PhoneCameraError.captureFailed(error.localizedDescription))
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      continuation?.resume(throwing: PhoneCameraError.captureFailed("No image data."))
      return
    }
    continuation?.resume(returning: data)
  }
}
