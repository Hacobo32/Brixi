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
  @ObservedObject var wearablesViewModel: WearablesViewModel
  let onConnectGlasses: () -> Void
  let onSelectSet: (SetSelection) -> Void
  let onOpenSettings: () -> Void

  @State private var pendingRemoval: BuildProject?

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
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  pendingRemoval = build
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
              .contextMenu {
                Button(role: .destructive) {
                  pendingRemoval = build
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
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
            // Reflects connection status at a glance, per the punch-list ask
            // -- green once glasses are actually active, not just registered.
            Image(systemName: "eyeglasses")
              .foregroundStyle(wearablesViewModel.hasActiveDevice ? .green : .primary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            onOpenSettings()
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .confirmationDialog(
        "Remove this build?",
        isPresented: Binding(
          get: { pendingRemoval != nil },
          set: { isPresented in if !isPresented { pendingRemoval = nil } }
        ),
        presenting: pendingRemoval
      ) { build in
        Button("Remove", role: .destructive) {
          store.moveToHistory(setNum: build.setNum)
          pendingRemoval = nil
        }
        Button("Cancel", role: .cancel) {}
      } message: { build in
        Text("\"\(build.setName)\" moves to Build History. You can restore it later.")
      }
    }
  }

  private func buildRow(_ build: BuildProject) -> some View {
    HStack(spacing: 12) {
      setThumbnail(build.setImageURL)
      VStack(alignment: .leading, spacing: 4) {
        Text(build.setName)
          .font(.headline)
        Text("\(build.setNum) · \(build.totalFound)/\(build.totalNeeded) parts found")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.primary)
  }

  private func setRow(_ set: CatalogSet) -> some View {
    HStack(spacing: 12) {
      setThumbnail(set.imgURL)
      VStack(alignment: .leading, spacing: 4) {
        Text(set.name)
          .font(.headline)
        Text(set.setNum)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.primary)
  }

  /// A small box-art thumbnail so sets with similar names are easy to tell
  /// apart at a glance, instead of relying on the set number alone.
  private func setThumbnail(_ url: URL?) -> some View {
    AsyncImage(url: url) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(.systemGray5))
      }
    }
    .frame(width: 44, height: 44)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
