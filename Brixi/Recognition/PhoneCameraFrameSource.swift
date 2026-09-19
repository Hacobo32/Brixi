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

import AVFoundation
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

  func captureOneFrame() async throws -> Data {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      state.withLock { $0.pendingCapture = continuation }
      sessionQueue.async { [photoOutput, self] in
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
      }
    }
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

    // Falls back to the front camera when there's no back one -- the
    // Simulator only exposes a front-facing camera (via the Mac's own
    // webcam passthrough), the same constraint we hit testing Mock Device
    // Kit's camera feed earlier.
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
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
}

extension PhoneCameraFrameSource: AVCapturePhotoOutputDelegate {
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
