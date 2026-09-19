//
// FrameSource.swift
//
// Abstracts "get one photo" away from where it came from, so
// RecognitionService and everything downstream stays unaware of whether a
// frame arrived from the phone's own camera or from glasses -- per the
// phone-first product decision: Brixi must work fully with just an iPhone,
// with glasses as an additional input path, not a dependency. See
// docs/rebrickable-brickognize-feasibility.md.
//

import Foundation

protocol FrameSource {
  func captureOneFrame() async throws -> Data
}

/// Adapts the existing glasses capture pipeline (session -> stream ->
/// capture, verified end to end via Mock Device Kit) to FrameSource,
/// without changing its behavior at all.
@MainActor
final class GlassesFrameSource: FrameSource {
  private let cameraController: CameraCaptureController

  init(cameraController: CameraCaptureController = CameraCaptureController()) {
    self.cameraController = cameraController
  }

  func captureOneFrame() async throws -> Data {
    try await cameraController.captureOnePhoto()
  }
}
