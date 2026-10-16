//
// PileSegmentationTestView.swift
//
// Debug screen: pick (or capture) a pile photo and run it through
// PileSegmenter, drawing a box over every detected piece -- the visual
// equivalent of the Python prototype's annotated overview images from
// Phase 0 testing, now runnable on-device against real captures.
//

#if DEBUG

import PhotosUI
import SwiftUI

struct PileSegmentationTestView: View {
  @ObservedObject var viewModel: PileSegmentationTestViewModel
  @State private var photosPickerItem: PhotosPickerItem?

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 16) {
          if let result = viewModel.result {
            overlayImage(result)
            Text("\(result.pieces.count) piece\(result.pieces.count == 1 ? "" : "s") detected")
              .font(.headline)
          } else if let imageData = viewModel.selectedImageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 300)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            Text("Pick or capture a pile photo to test segmentation.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          PhotosPicker("Choose Photo", selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
              Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                  viewModel.selectImage(data)
                }
              }
            }

          MockDeviceKitButton(
            "Detect Pieces",
            disabled: viewModel.selectedImageData == nil || viewModel.isProcessing
          ) {
            viewModel.detect()
          }

          MockDeviceKitButton(
            "Capture from Glasses",
            style: .primary,
            disabled: viewModel.isProcessing
          ) {
            viewModel.captureFromGlasses()
          }

          if viewModel.isProcessing {
            ProgressView()
          }

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
          }

          Spacer()
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Pile Segmentation Test")
    }
  }

  private func overlayImage(_ result: PileSegmenter.Result) -> some View {
    let imageSize = CGSize(width: result.image.width, height: result.image.height)
    return GeometryReader { geo in
      let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
      let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

      ZStack(alignment: .topLeading) {
        Image(decorative: result.image, scale: 1)
          .resizable()
          .frame(width: displaySize.width, height: displaySize.height)

        ForEach(Array(result.pieces.enumerated()), id: \.offset) { _, piece in
          Rectangle()
            .stroke(.red, lineWidth: 2)
            .frame(width: piece.rect.width * scale, height: piece.rect.height * scale)
            .offset(x: piece.rect.minX * scale, y: piece.rect.minY * scale)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .aspectRatio(imageSize.width / imageSize.height, contentMode: .fit)
    .frame(maxHeight: 400)
  }
}

#endif
