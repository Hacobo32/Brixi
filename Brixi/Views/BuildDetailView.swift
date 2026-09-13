//
// BuildDetailView.swift
//
// The needed-parts checklist for one set: fetches the set's part list on
// first open (via RebrickableClient), then persists found/not-found
// progress locally as pieces get located in the bin. Manual +/- for now --
// wiring this to live camera recognition is the next slice, not this one.
//

import SwiftUI

struct BuildDetailView: View {
  @StateObject var viewModel: BuildDetailViewModel

  var body: some View {
    Group {
      if let build = viewModel.build {
        List {
          Section {
            ProgressView(value: Double(build.totalFound), total: Double(max(build.totalNeeded, 1)))
            Text("\(build.totalFound) of \(build.totalNeeded) parts found")
              .font(.caption)
              .foregroundStyle(.secondary)
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
    .navigationTitle(viewModel.setName)
    .onAppear { viewModel.loadIfNeeded() }
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
