//
// BuildDetailView.swift
//
// The needed-parts checklist for one set: fetches the set's part list on
// first open (via RebrickableClient), then persists found/not-found
// progress locally as pieces get located in the bin. Scanning works with
// just the phone camera (the phone-first product decision) -- glasses are
// a second, additional path via the same recognition/match pipeline, not a
// requirement.
//

import SwiftUI

struct BuildDetailView: View {
  @StateObject var viewModel: BuildDetailViewModel
  let onSwitchBuild: () -> Void

  @State private var showPhoneCamera = false

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(viewModel.setName)
        // Inline, with a wrapping principal title -- the large title truncated
        // long set names (e.g. "Wonder Woman vs. Cheet…") against the trailing
        // "Switch Build" button, with no way to read the rest.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Text(viewModel.setName)
              .font(.headline)
              .lineLimit(2)
              .multilineTextAlignment(.center)
              .minimumScaleFactor(0.8)
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Switch Build", action: onSwitchBuild)
          }
        }
        #if DEBUG
        // Reserves room below the last row for DebugMenuView's floating
        // buttons (see its own comment), which otherwise sat on top of the
        // Stepper +/- controls for the final rows in Needed Parts.
        .safeAreaInset(edge: .bottom) {
          Color.clear.frame(height: 140)
        }
        #endif
        .fullScreenCover(isPresented: $showPhoneCamera) {
          PhoneCameraCaptureView(
            frameSource: viewModel.phoneCameraSource,
            onCapture: { data in
              showPhoneCamera = false
              viewModel.handlePhoneCameraCapture(data)
            },
            onCancel: { showPhoneCamera = false }
          )
        }
    }
    // Attached to the NavigationStack itself, not to `content` -- `content`
    // can resolve to an empty view before the first load finishes, and
    // .onAppear on a view that resolves empty may never fire, which left
    // this screen permanently blank with no way to start the fetch or even
    // reach "Switch Build". The NavigationStack always has real presence,
    // so this is reliable regardless of what `content` currently shows.
    .onAppear { viewModel.loadIfNeeded() }
  }

  @ViewBuilder
  private var content: some View {
    Group {
      if let build = viewModel.build {
        List {
          if let scanResult = viewModel.scanResult {
            Section {
              scanResultBanner(scanResult)
            }
          }

          #if DEBUG
          if let diagnostics = viewModel.lastCaptureDiagnostics {
            Section {
              Text("📷 \(diagnostics.summary)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
          }
          #endif

          Section {
            ProgressView(value: Double(build.totalFound), total: Double(max(build.totalNeeded, 1)))
            Text("\(build.totalFound) of \(build.totalNeeded) parts found")
              .font(.caption)
              .foregroundStyle(.secondary)

            Button {
              showPhoneCamera = true
            } label: {
              Label("Scan with Phone Camera", systemImage: "camera")
            }
            .disabled(viewModel.isScanning)

            Button {
              viewModel.scanWithGlasses()
            } label: {
              if viewModel.isScanning {
                HStack {
                  ProgressView()
                  Text("Scanning…")
                }
              } else {
                Label("Scan with Glasses", systemImage: "eyeglasses")
              }
            }
            .disabled(viewModel.isScanning)

            if let errorMessage = viewModel.errorMessage {
              Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
            }
          }

          Section("Needed Parts") {
            ForEach(build.parts) { part in
              partRow(part)
            }
          }
        }
      } else if viewModel.isLoading {
        ProgressView("Fetching parts from Rebrickable…")
      } else if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .padding()
      } else {
        // Startup state, before loadIfNeeded()'s result (success, error, or
        // still-loading) has landed. Never leave this branch missing --
        // see the .onAppear comment above for what happens when it's gone.
        ProgressView()
      }
    }
  }

  @ViewBuilder
  private func scanResultBanner(_ result: BuildDetailViewModel.ScanResult) -> some View {
    switch result {
    case .autoFound(let part):
      Label("Found: \(part.name) (\(part.colorName))", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .onTapGesture { viewModel.dismissScanResult() }

    case .needsConfirmation(let part, let recognizedName):
      VStack(alignment: .leading, spacing: 8) {
        Text("Looks like **\(recognizedName)** — is this your \(part.name) (\(part.colorName))?")
        HStack {
          Button("Yes, mark found") { viewModel.confirmScanResult() }
          Button("No", role: .cancel) { viewModel.dismissScanResult() }
        }
      }

    case .notInSet(let recognizedName):
      Text("\(recognizedName) isn't part of this set.")
        .foregroundStyle(.secondary)
        .onTapGesture { viewModel.dismissScanResult() }

    case .notRecognized:
      Text("Couldn't identify that piece. Try again with better lighting.")
        .foregroundStyle(.secondary)
        .onTapGesture { viewModel.dismissScanResult() }
    }
  }

  private func partRow(_ part: NeededPart) -> some View {
    HStack {
      partThumbnail(part.imageURL)
      VStack(alignment: .leading, spacing: 4) {
        Text(part.name)
          .font(.body)
          .strikethrough(part.isComplete)
          .foregroundStyle(part.isComplete ? .secondary : .primary)
        Text("\(part.colorName) · \(part.quantityFound)/\(part.quantityNeeded)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Stepper(
        "",
        value: Binding(
          get: { part.quantityFound },
          set: { newValue in
            viewModel.markFound(part, delta: newValue - part.quantityFound)
          }
        ),
        in: 0...part.quantityNeeded
      )
      .labelsHidden()
    }
  }

  private func partThumbnail(_ url: URL?) -> some View {
    AsyncImage(url: url) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFit()
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
          // Distinguishes "no photo available" (every part in NeededPart's
          // fallback chain came up empty) from an image still loading.
          Image(systemName: "cube")
            .foregroundStyle(.secondary)
            .font(.caption)
        }
      }
    }
    .frame(width: 44, height: 44)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
