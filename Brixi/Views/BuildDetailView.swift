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
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Switch Build", action: onSwitchBuild)
          }
        }
        .onAppear { viewModel.loadIfNeeded() }
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
}
