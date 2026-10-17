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
            if !viewModel.burstScores.isEmpty {
              burstScoreRow(viewModel.burstScores, picked: viewModel.pickedBurstIndex)
            }
            if !viewModel.cropThumbnails.isEmpty {
              cropStrip(viewModel.cropThumbnails, results: viewModel.recognitionResults)
              MockDeviceKitButton(
                "Recognize All Crops",
                disabled: viewModel.isRecognizing || viewModel.isProcessing
              ) {
                viewModel.recognizeCrops()
              }
              if let progress = viewModel.recognitionProgress {
                Text("Checking \(progress.completed) of \(progress.total)…")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
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
            "Capture Burst (Glasses)",
            style: .primary,
            disabled: viewModel.isProcessing
          ) {
            viewModel.captureBurstFromGlasses()
          }

          MockDeviceKitButton(
            "Capture Burst (Phone)",
            style: .primary,
            disabled: viewModel.isProcessing
          ) {
            viewModel.captureBurstFromPhone()
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

        ForEach(Array(result.pieces.enumerated()), id: \.offset) { index, piece in
          Rectangle()
            .stroke(.red, lineWidth: 2)
            .frame(width: piece.rect.width * scale, height: piece.rect.height * scale)
            .overlay(alignment: .topLeading) {
              // Matches the crop strip's numbering below, so an
              // overlapping cluster here can be cross-checked against
              // what each individual crop actually contains.
              Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(2)
                .background(.red)
            }
            .offset(x: piece.rect.minX * scale, y: piece.rect.minY * scale)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .aspectRatio(imageSize.width / imageSize.height, contentMode: .fit)
    .frame(maxHeight: 400)
  }

  /// One sharpness score per burst frame, with the picked (sharpest)
  /// frame highlighted -- the diagnostic needed to eventually tune §4.1's
  /// "don't scan, coach the user" blur-reject threshold against real
  /// numbers instead of a guess.
  private func burstScoreRow(_ scores: [Double], picked: Int?) -> some View {
    HStack(spacing: 8) {
      Text("Burst sharpness:")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
        Text(String(format: "%.0f", score))
          .font(.caption.monospacedDigit())
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(index == picked ? Color.green.opacity(0.3) : Color(.systemGray5))
          .clipShape(Capsule())
      }
    }
  }

  /// Shows what's actually inside each detected box, numbered to match
  /// the overlay -- the only way to tell "two separate, correctly-boxed
  /// pieces whose generous padding happens to overlap" apart from "one
  /// piece's mask fractured into several boxes" (both look identical in
  /// the overlay alone). Once `recognizeCrops()` has run, each thumbnail
  /// also shows Brickognize's top guess and score, so §4.3's name-pieces
  /// step can be checked against real crops rather than guessed at.
  private func cropStrip(_ thumbnails: [UIImage], results: [BrickognizeSearchResult?]) -> some View {
    ScrollView(.horizontal, showsIndicators: true) {
      LazyHStack(alignment: .top, spacing: 8) {
        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumbnail in
          VStack(spacing: 4) {
            Image(uiImage: thumbnail)
              .resizable()
              .scaledToFit()
              .frame(width: 80, height: 80)
              .background(Color(.systemGray5))
              .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("\(index + 1)")
              .font(.caption2)
              .foregroundStyle(.secondary)
            if index < results.count, let topItem = results[index]?.items.first {
              Text(topItem.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
              Text(String(format: "%.2f", topItem.score))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
          .frame(width: 80)
        }
      }
      .padding(.horizontal, 4)
    }
  }
}

#endif
