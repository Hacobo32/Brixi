//
// SetPickerViewModel.swift
//
// Local search over the bundled `sets` table -- no network needed, since
// sets/themes/etc. are all bundled (see CatalogDatabase).
//

import Foundation

@MainActor
final class SetPickerViewModel: ObservableObject {
  @Published var query: String = "" {
    didSet { search() }
  }
  @Published private(set) var results: [CatalogSet] = []

  private let catalog: CatalogDatabase?

  init(catalog: CatalogDatabase?) {
    self.catalog = catalog
  }

  private func search() {
    guard let catalog, query.trimmingCharacters(in: .whitespaces).count >= 2 else {
      results = []
      return
    }
    results = catalog.searchSets(matching: query, limit: 25)
  }
}
