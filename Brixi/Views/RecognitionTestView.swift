//
// RecognitionTestView.swift
//
// Debug screen: pick a photo of a LEGO piece and run it through
// RecognitionService, so the Brickognize-to-catalog pipeline can be
// verified before the camera capture pipeline exists.
//

#if DEBUG

import PhotosUI
import SwiftUI

struct RecognitionTestView: View {
  @ObservedObject var viewModel: RecognitionTestViewModel
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

          if let outcome = viewModel.outcome {
            outcomeView(for: outcome)
          }

          Spacer()
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Recognition Test")
    }
  }

  @ViewBuilder
  private func outcomeView(for outcome: RecognitionOutcome) -> some View {
    switch outcome {
    case .recognized(let piece):
      pieceCard(piece, label: "Match")
    case .lowConfidence(let candidates) where candidates.isEmpty:
      Text("No match found.")
        .foregroundStyle(.secondary)
    case .lowConfidence(let candidates):
      VStack(alignment: .leading, spacing: 8) {
        Text("Not sure — top candidates:")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        ForEach(candidates.prefix(3), id: \.id) { item in
          itemCard(item)
        }
      }
    case .notFound:
      Text("No match found.")
        .foregroundStyle(.secondary)
    }
  }

  private func pieceCard(_ piece: RecognizedPiece, label: String) -> some View {
    CardView {
      HStack(alignment: .top, spacing: 12) {
        if let imageURL = piece.imageURL {
          AsyncImage(url: imageURL) { image in
            image.resizable().scaledToFit()
          } placeholder: {
            ProgressView()
          }
          .frame(width: 56, height: 56)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(displayName(for: piece))
            .font(.headline)
          Text("\(piece.item.id) · score \(String(format: "%.2f", piece.confidence))")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let colorName = piece.colorName {
            Text(colorName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func itemCard(_ item: BrickognizeItem) -> some View {
    CardView {
      VStack(alignment: .leading, spacing: 4) {
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

  // Prefer the resolved local-catalog name over Brickognize's own name,
  // since the catalog is the authoritative Rebrickable data source.
  private func displayName(for piece: RecognizedPiece) -> String {
    piece.catalogPart?.name
      ?? piece.catalogSet?.name
      ?? piece.catalogMinifig?.name
      ?? piece.item.name
  }
}

#endif
