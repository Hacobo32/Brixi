//
// BuildDetailViewModel.swift
//
// Fetches (or loads cached) needed-parts data for one set and exposes it as
// a checklist backed by BuildProjectStore. The live Rebrickable fetch only
// ever runs once per set -- after that, the user's found/not-found progress
// lives entirely in BuildProjectStore, not refetched.
//

import Foundation

@MainActor
final class BuildDetailViewModel: ObservableObject {
  @Published private(set) var build: BuildProject?
  @Published var isLoading = false
  @Published var errorMessage: String?

  let setName: String

  private let setNum: String
  private let setImageURL: URL?
  private let store: BuildProjectStore
  private let client: RebrickableClient?
  private let catalog: CatalogDatabase?

  init(
    setNum: String,
    setName: String,
    setImageURL: URL?,
    store: BuildProjectStore,
    client: RebrickableClient?,
    catalog: CatalogDatabase?
  ) {
    self.setNum = setNum
    self.setName = setName
    self.setImageURL = setImageURL
    self.store = store
    self.client = client
    self.catalog = catalog
    self.build = store.build(setNum: setNum)
  }

  func loadIfNeeded() {
    guard build == nil else { return }
    guard let client else {
      errorMessage = "No Rebrickable API key configured -- can't fetch this set's parts."
      return
    }

    isLoading = true
    errorMessage = nil
    Task {
      do {
        let entries = try await client.fetchParts(setNum: setNum)
        let parts = Self.aggregate(entries, catalog: catalog)
        let newBuild = BuildProject(setNum: setNum, setName: setName, setImageURL: setImageURL, parts: parts)
        store.upsert(newBuild)
        build = newBuild
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  func markFound(_ part: NeededPart, delta: Int) {
    store.markFound(setNum: setNum, partId: part.id, delta: delta)
    build = store.build(setNum: setNum)
  }

  /// Collapses Rebrickable's per-line-item response into one entry per
  /// part+color, excluding spares from the quantity needed to actually
  /// complete the set.
  private static func aggregate(_ entries: [RebrickablePartEntry], catalog: CatalogDatabase?) -> [NeededPart] {
    var byKey: [String: NeededPart] = [:]
    for entry in entries where !entry.isSpare {
      let key = "\(entry.part.partNum)-\(entry.color.id)"
      if let existing = byKey[key] {
        byKey[key] = NeededPart(
          partNum: existing.partNum,
          colorId: existing.colorId,
          name: existing.name,
          colorName: existing.colorName,
          imageURL: existing.imageURL,
          quantityNeeded: existing.quantityNeeded + entry.quantity,
          quantityFound: 0
        )
      } else {
        let imageURL = catalog?.elementImageURL(partNum: entry.part.partNum, colorId: entry.color.id)
          ?? entry.part.partImgURL
        byKey[key] = NeededPart(
          partNum: entry.part.partNum,
          colorId: entry.color.id,
          name: entry.part.name,
          colorName: entry.color.name,
          imageURL: imageURL,
          quantityNeeded: entry.quantity,
          quantityFound: 0
        )
      }
    }
    return byKey.values.sorted { $0.name < $1.name }
  }
}
