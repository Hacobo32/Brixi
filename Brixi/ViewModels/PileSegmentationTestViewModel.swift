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
import UIKit

@MainActor
final class PileSegmentationTestViewModel: ObservableObject {
  @Published var selectedImageData: Data?
  @Published var isProcessing = false
  @Published var result: PileSegmenter.Result?
  /// One thumbnail per `result.pieces`, same order -- lets the debug
  /// screen show what's actually inside each detected box instead of
  /// just its outline, which is the only way to tell overlapping-but-
  /// separate boxes apart from one piece's mask having fractured into
  /// several.
  @Published var cropThumbnails: [UIImage] = []
  /// Laplacian-variance sharpness score for each frame in the last burst,
  /// same order as captured -- lets the debug screen show which frame got
  /// picked and by how much, so the "don't scan, coach the user" blur
  /// threshold (docs/pile-mode-spec.md §4.1) can eventually be tuned
  /// against real numbers instead of guessed.
  @Published var burstScores: [Double] = []
  @Published var pickedBurstIndex: Int?
  @Published var errorMessage: String?

  private let cameraController = CameraCaptureController()
  private let phoneCameraSource = PhoneCameraFrameSource()

  func selectImage(_ data: Data) {
    selectedImageData = data
    result = nil
    cropThumbnails = []
    burstScores = []
    pickedBurstIndex = nil
    errorMessage = nil
  }

  func detect() {
    guard let data = selectedImageData else { return }
    isProcessing = true
    errorMessage = nil
    result = nil
    cropThumbnails = []
    burstScores = []
    pickedBurstIndex = nil
    Task { await finishDetection(on: data) }
  }

  /// Bursts 3 frames from the glasses (or a Mock Device Kit feed), picks
  /// the sharpest, and runs it through segmentation -- the live-camera
  /// counterpart to picking a photo from the library, same pattern as
  /// RecognitionTestViewModel.captureFromGlasses() but exercising §4.1's
  /// burst + pick-sharpest step instead of a single shot.
  func captureBurstFromGlasses() {
    beginCapture()
    Task {
      do {
        let frames = try await cameraController.captureBurst()
        await finishBurst(frames)
      } catch {
        errorMessage = error.localizedDescription
        isProcessing = false
      }
    }
  }

  /// Same burst + pick-sharpest flow, from the phone's own camera -- no
  /// live preview, matching the glasses path's blind-capture pattern.
  /// Phone is pile mode's primary device (§1), so this needs its own
  /// real-device validation independent of the glasses path.
  func captureBurstFromPhone() {
    beginCapture()
    Task {
      do {
        try await phoneCameraSource.start()
        defer { phoneCameraSource.stop() }
        // Lets auto-exposure/focus settle before the burst fires, since
        // there's no preview to frame against ahead of time.
        try await Task.sleep(for: .milliseconds(400))
        let frames = try await phoneCameraSource.captureBurst()
        await finishBurst(frames)
      } catch {
        errorMessage = error.localizedDescription
        isProcessing = false
      }
    }
  }

  private func beginCapture() {
    isProcessing = true
    errorMessage = nil
    result = nil
    cropThumbnails = []
    burstScores = []
    pickedBurstIndex = nil
  }

  private func finishBurst(_ frames: [Data]) async {
    let scores = await Task.detached(priority: .userInitiated) {
      frames.map { BlurDetector.sharpnessScore(of: $0) ?? 0 }
    }.value
    burstScores = scores
    guard let bestIndex = scores.indices.max(by: { scores[$0] < scores[$1] }) else {
      errorMessage = "Couldn't process burst frames."
      isProcessing = false
      return
    }
    pickedBurstIndex = bestIndex
    let data = frames[bestIndex]
    selectedImageData = data
    await finishDetection(on: data)
  }

  /// Segmentation is CPU-bound and synchronous; runs off the main actor
  /// so the UI (spinner) stays responsive while it works.
  private func finishDetection(on data: Data) async {
    let detected = await Task.detached(priority: .userInitiated) {
      PileSegmenter.detectPieces(in: data)
    }.value
    if let detected {
      result = detected
      cropThumbnails = await Task.detached(priority: .userInitiated) {
        detected.pieces.compactMap { piece in
          PileSegmenter.crop(piece, from: detected.image).map { UIImage(cgImage: $0) }
        }
      }.value
    } else {
      errorMessage = "Couldn't process that image."
    }
    isProcessing = false
  }
}

#endif
