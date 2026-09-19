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

  // The default is built inside the initializer body, not as a default
  // parameter value -- a default parameter value calling a @MainActor
  // initializer isn't treated as isolated the same way a stored property
  // or in-body call is, and errors as "main actor-isolated initializer in
  // a synchronous nonisolated context".
  init(cameraController: CameraCaptureController? = nil) {
    self.cameraController = cameraController ?? CameraCaptureController()
  }

  func captureOneFrame() async throws -> Data {
    try await cameraController.captureOnePhoto()
  }
}
