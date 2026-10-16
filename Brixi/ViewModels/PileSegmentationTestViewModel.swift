//
// PileSegmentationTestViewModel.swift
//
// Debug screen for pile mode's Milestone 1 (docs/pile-mode-spec.md §4.2,
// §11): exercises PileSegmenter against a real photo and shows what it
// finds, independent of Brickognize -- so segmentation quality can be
// checked on-device, on real captures, before anything is built on top
// of it.
//

#if DEBUG

import Foundation
import SwiftUI

@MainActor
final class PileSegmentationTestViewModel: ObservableObject {
  @Published var selectedImageData: Data?
  @Published var isProcessing = false
  @Published var result: PileSegmenter.Result?
  @Published var errorMessage: String?

  private let cameraController = CameraCaptureController()

  func selectImage(_ data: Data) {
    selectedImageData = data
    result = nil
    errorMessage = nil
  }

  func detect() {
    guard let data = selectedImageData else { return }
    isProcessing = true
    errorMessage = nil
    result = nil
    Task { await finishDetection(on: data) }
  }

  /// Captures one photo from the glasses (or a Mock Device Kit feed) and
  /// runs it straight through segmentation -- the live-camera counterpart
  /// to picking a photo from the library, same pattern as
  /// RecognitionTestViewModel.captureFromGlasses().
  func captureFromGlasses() {
    isProcessing = true
    errorMessage = nil
    result = nil
    Task {
      do {
        let imageData = try await cameraController.captureOnePhoto()
        selectedImageData = imageData
        await finishDetection(on: imageData)
      } catch {
        errorMessage = error.localizedDescription
        isProcessing = false
      }
    }
  }

  /// Segmentation is CPU-bound and synchronous; runs off the main actor
  /// so the UI (spinner) stays responsive while it works.
  private func finishDetection(on data: Data) async {
    let detected = await Task.detached(priority: .userInitiated) {
      PileSegmenter.detectPieces(in: data)
    }.value
    if let detected {
      result = detected
    } else {
      errorMessage = "Couldn't process that image."
    }
    isProcessing = false
  }
}

#endif
