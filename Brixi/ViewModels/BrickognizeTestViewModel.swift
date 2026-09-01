//
// BrickognizeTestViewModel.swift
//
// Lets the Brickognize client be exercised with a still photo from the
// debug menu, independent of the camera pipeline (which isn't wired up
// yet). Once frames are streaming from MWDATCamera, this same client
// drives the live "hold piece steady -> identify -> speak" flow.
//

#if DEBUG

import Foundation
import SwiftUI

@MainActor
final class BrickognizeTestViewModel: ObservableObject {
  @Published var selectedImageData: Data?
  @Published var isLoading = false
  @Published var result: PartIdentificationResult?
  @Published var errorMessage: String?

  private let client: BrickognizeClientProtocol

  init(client: BrickognizeClientProtocol = BrickognizeClient()) {
    self.client = client
  }

  func selectImage(_ data: Data) {
    selectedImageData = data
    result = nil
    errorMessage = nil
  }

  func identify() {
    guard let imageData = selectedImageData else { return }
    isLoading = true
    errorMessage = nil
    result = nil

    Task {
      do {
        let prediction = try await client.identifyPart(imageData: imageData)
        result = PartIdentificationResult(prediction: prediction)
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}

#endif
