//
// SetPickerView.swift
//
// Where you choose which single build is active: search the bundled
// catalog for a new set, or resume one already in "My Builds". Selecting
// either just reports the choice upward via onSelectSet -- the caller
// (BrixiApp, either as the app root or as a "Switch Build" sheet) is the
// one that actually makes it the active build.
//

import SwiftUI

struct SetSelection: Hashable, Codable {
  let setNum: String
  let name: String
  let imageURL: URL?
}

struct SetPickerView: View {
  @ObservedObject var viewModel: SetPickerViewModel
  @ObservedObject var store: BuildProjectStore
  let onConnectGlasses: () -> Void
  let onSelectSet: (SetSelection) -> Void

  var body: some View {
    NavigationStack {
      List {
        if !store.builds.isEmpty {
          Section("My Builds") {
            ForEach(store.builds) { build in
              Button {
                onSelectSet(SetSelection(setNum: build.setNum, name: build.setName, imageURL: build.setImageURL))
              } label: {
                buildRow(build)
              }
              .buttonStyle(.plain)
            }
          }
        }

        Section("Find a Set") {
          ForEach(viewModel.results, id: \.setNum) { set in
            Button {
              onSelectSet(SetSelection(setNum: set.setNum, name: set.name, imageURL: set.imgURL))
            } label: {
              setRow(set)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .searchable(text: $viewModel.query, prompt: "Set number or name")
      .navigationTitle("Brixi")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            onConnectGlasses()
          } label: {
            Image(systemName: "eyeglasses")
          }
        }
      }
    }
  }

  private func buildRow(_ build: BuildProject) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(build.setName)
        .font(.headline)
      Text("\(build.setNum) · \(build.totalFound)/\(build.totalNeeded) parts found")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(.primary)
  }

  private func setRow(_ set: CatalogSet) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(set.name)
        .font(.headline)
      Text(set.setNum)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(.primary)
  }
}
