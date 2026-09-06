//
// RecognitionTestViewModel.swift
//
// Lets RecognitionService be exercised with a still photo from the debug
// menu, independent of the camera pipeline (which isn't wired up yet).
// Once frames are streaming from MWDATCamera, this same service drives
// the live "hold piece steady -> identify -> speak" flow.
//

#if DEBUG

import Foundation
import SwiftUI

@MainActor
final class RecognitionTestViewModel: ObservableObject {
  @Published var selectedImageData: Data?
  @Published var isLoading = false
  @Published var outcome: RecognitionOutcome?
  @Published var errorMessage: String?

  private let service: RecognitionService?

  init() {
    do {
      self.service = RecognitionService(catalog: try CatalogDatabase())
    } catch {
      self.service = nil
      self.errorMessage = "Couldn't open the local catalog: \(error.localizedDescription)"
    }
  }

  func selectImage(_ data: Data) {
    selectedImageData = data
    outcome = nil
    errorMessage = nil
  }

  func identify() {
    guard let imageData = selectedImageData else { return }
    guard let service else { return }
    isLoading = true
    errorMessage = nil
    outcome = nil

    Task {
      do {
        outcome = try await service.recognize(imageData: imageData)
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}

#endif
