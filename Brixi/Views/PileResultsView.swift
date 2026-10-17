//
// PileResultsView.swift
//
// Pile mode's "output" step (docs/pile-mode-spec.md §4.5): the captured
// photo with boxes on found (solid) and maybe (dashed) pieces, a
// found/maybe/missing list below, tap-to-highlight between the two, and a
// short spoken summary (§7: audio output only, no voice input in v1).
//
// Not a DEBUG-only view -- this is the real product screen pile mode will
// present once it's wired into BuildDetailView (§11, Milestone 6). The
// pile segmentation debug screen presents it today, against whatever
// build is currently active, so it can be validated on real captures
// before that wiring exists.
//

import AVFoundation
import SwiftUI

struct PileResultsView: View {
  let setName: String
  let image: CGImage
  /// Same length and order as `classifications` -- paired rather than
  /// zipped at call sites so a caller with raw PileSegmenter.DetectedPiece
  /// + PileMatchClassification arrays can pass them straight through.
  let pieces: [PileSegmenter.DetectedPiece]
  let classifications: [PileMatchClassification]
  let tally: PileMatcher.Tally

  @Environment(\.dismiss) private var dismiss
  @State private var highlightedPartId: String?
  // @State, not a plain `let` -- its storage needs to persist for this
  // view's identity lifetime, independent of body re-evaluations (e.g.
  // from tapping a row), or the synthesizer can be deallocated mid-
  // utterance and cut the speech off partway through.
  @State private var speaker = AVSpeechSynthesizer()

  private var foundTotal: Int { tally.found.reduce(0) { $0 + $1.count } }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          overlayImage
          Text("Scanned against: \(setName)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
          List {
            if !tally.found.isEmpty {
              Section("Found (\(foundTotal))") {
                ForEach(tally.found, id: \.part.id) { entry in
                  partRow(entry.part, quantity: entry.count, tappable: true)
                }
              }
            }
            if !tally.maybe.isEmpty {
              Section("Maybe (\(tally.maybe.count))") {
                ForEach(tally.maybe) { part in
                  partRow(part, quantity: 1, tappable: true)
                }
              }
            }
            if !tally.missing.isEmpty {
              Section("Still Missing (\(tally.missing.count))") {
                ForEach(tally.missing) { part in
                  partRow(part, quantity: part.quantityNeeded - part.quantityFound, tappable: false)
                }
              }
            }
          }
          // A List already scrolls internally; inside this screen's own
          // ScrollView it just needs enough height to show a few rows
          // without the page becoming one scroll-within-a-scroll.
          .frame(minHeight: 420)
          .scrollDisabled(true)
        }
        .padding(.top)
      }
      .navigationTitle("Pile Scan Results")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .onAppear { speakSummary() }
  }

  // MARK: - Image overlay

  private var overlayImage: some View {
    let imageSize = CGSize(width: image.width, height: image.height)
    return GeometryReader { geo in
      let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
      let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

      ZStack(alignment: .topLeading) {
        Image(decorative: image, scale: 1)
          .resizable()
          .frame(width: displaySize.width, height: displaySize.height)

        ForEach(Array(pieces.indices), id: \.self) { index in
          if let part = classifications[index].neededPart {
            pieceBox(pieces[index].rect, classification: classifications[index], part: part, scale: scale)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .aspectRatio(imageSize.width / imageSize.height, contentMode: .fit)
    .frame(maxHeight: 400)
  }

  private func pieceBox(_ rect: CGRect, classification: PileMatchClassification, part: NeededPart, scale: Double) -> some View {
    let isMaybe = { if case .maybe = classification { return true } else { return false } }()
    let isHighlighted = highlightedPartId == part.id
    return Rectangle()
      .strokeBorder(
        isHighlighted ? Color.blue : (isMaybe ? Color.yellow : Color.green),
        style: StrokeStyle(lineWidth: isHighlighted ? 3 : 2, dash: isMaybe ? [5, 4] : [])
      )
      .frame(width: rect.width * scale, height: rect.height * scale)
      .offset(x: rect.minX * scale, y: rect.minY * scale)
  }

  // MARK: - List rows

  private func partRow(_ part: NeededPart, quantity: Int, tappable: Bool) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(part.name)
          .font(.body)
        Text("\(part.colorName) · \(quantity)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if highlightedPartId == part.id {
        Image(systemName: "viewfinder")
          .foregroundStyle(.blue)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard tappable else { return }
      highlightedPartId = highlightedPartId == part.id ? nil : part.id
    }
  }

  // MARK: - Voice (§7: output only)

  /// Short, per the spec -- a running count rather than reading every
  /// part name (the worked example's "Top left: 2 by 6 tan plate..."
  /// positional detail needs real layout analysis this doesn't attempt).
  private func speakSummary() {
    guard foundTotal > 0 else { return }
    let text = "Found \(foundTotal) piece\(foundTotal == 1 ? "" : "s") from your set."
    speaker.speak(AVSpeechUtterance(string: text))
  }
}
