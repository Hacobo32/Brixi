//
// NeededPartMatcher.swift
//
// Resolves a Brickognize item against a build's needed-parts list, shared
// by single-piece mode (BuildDetailViewModel) and pile mode (PileMatcher)
// so both go through the exact same BrickLink<->Rebrickable reconciliation
// (docs/pile-mode-spec.md §6) instead of two copies that could drift.
//

import Foundation

enum NeededPartMatcher {
  /// Tries each of PartIDResolver's ID candidates (raw ID, shape-stripped
  /// base ID, live Rebrickable lookup) against the catalog's part family
  /// in order, and returns every needed-parts row the first matching
  /// candidate hits -- more than one means this part shape is needed in
  /// multiple colors, which the caller uses to decide whether color needs
  /// consulting.
  static func match(
    _ item: BrickognizeItem,
    in parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> [NeededPart] {
    for candidate in await resolver.candidates(for: item) {
      let family = catalog.partFamily(partNum: candidate)
      let matches = parts.filter { family.contains($0.partNum) }
      if !matches.isEmpty {
        return matches
      }
    }
    return []
  }
}
