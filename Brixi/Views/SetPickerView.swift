//
// SetPickerView.swift
//
// Entry point for the "find parts for a set" flow: search the bundled
// catalog for a set (by number or name), or jump back into a build already
// in progress.
//

import SwiftUI

struct SetSelection: Hashable {
  let setNum: String
  let name: String
  let imageURL: URL?
}

struct SetPickerView: View {
  @ObservedObject var viewModel: SetPickerViewModel
  @ObservedObject var store: BuildProjectStore
  let client: RebrickableClient?
  let catalog: CatalogDatabase?
  let onConnectGlasses: () -> Void

  var body: some View {
    NavigationStack {
      List {
        if !store.builds.isEmpty {
          Section("My Builds") {
            ForEach(store.builds) { build in
              NavigationLink(value: SetSelection(setNum: build.setNum, name: build.setName, imageURL: build.setImageURL)) {
                buildRow(build)
              }
            }
          }
        }

        Section("Find a Set") {
          ForEach(viewModel.results, id: \.setNum) { set in
            NavigationLink(value: SetSelection(setNum: set.setNum, name: set.name, imageURL: set.imgURL)) {
              setRow(set)
            }
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
      .navigationDestination(for: SetSelection.self) { selection in
        BuildDetailView(
          viewModel: BuildDetailViewModel(
            setNum: selection.setNum,
            setName: selection.name,
            setImageURL: selection.imageURL,
            store: store,
            client: client,
            catalog: catalog
          )
        )
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
  }

  private func setRow(_ set: CatalogSet) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(set.name)
        .font(.headline)
      Text(set.setNum)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
