//
// BrickognizeTestView.swift
//
// Debug screen: pick a photo of a LEGO piece and run it through Brickognize,
// so the API client can be verified before the camera capture pipeline
// exists.
//

#if DEBUG

import PhotosUI
import SwiftUI

struct BrickognizeTestView: View {
  @ObservedObject var viewModel: BrickognizeTestViewModel
  @State private var photosPickerItem: PhotosPickerItem?

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 16) {
          if let imageData = viewModel.selectedImageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 240)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            Text("Pick a photo of a single LEGO piece to test identification.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          PhotosPicker("Choose Photo", selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { newItem in
              Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                  viewModel.selectImage(data)
                }
              }
            }

          MockDeviceKitButton(
            "Identify Part",
            disabled: viewModel.selectedImageData == nil || viewModel.isLoading
          ) {
            viewModel.identify()
          }

          if viewModel.isLoading {
            ProgressView()
          }

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
          }

          if let result = viewModel.result {
            resultView(for: result)
          }

          Spacer()
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Brickognize Test")
    }
  }

  @ViewBuilder
  private func resultView(for result: PartIdentificationResult) -> some View {
    switch result {
    case .confidentMatch(let item):
      itemCard(item, label: "Match")
    case .uncertainMatches(let items) where items.isEmpty:
      Text("No match found.")
        .foregroundStyle(.secondary)
    case .uncertainMatches(let items):
      VStack(alignment: .leading, spacing: 8) {
        Text("Not sure — top candidates:")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        ForEach(items) { item in
          itemCard(item, label: nil)
        }
      }
    case .noMatch:
      Text("No match found.")
        .foregroundStyle(.secondary)
    }
  }

  private func itemCard(_ item: BrickognizeItem, label: String?) -> some View {
    CardView {
      VStack(alignment: .leading, spacing: 4) {
        if let label {
          Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(item.name)
          .font(.headline)
        Text("\(item.id) · score \(String(format: "%.2f", item.score))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

#endif
