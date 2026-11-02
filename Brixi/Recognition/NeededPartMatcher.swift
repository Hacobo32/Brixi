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
  /// base ID, then -- only if neither of those matched -- a live
  /// Rebrickable lookup) against the catalog's part family in order, and
  /// returns every needed-parts row the first matching candidate hits --
  /// more than one means this part shape is needed in multiple colors,
  /// which the caller uses to decide whether color needs consulting.
  static func match(
    _ item: BrickognizeItem,
    in parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> [NeededPart] {
    func matches(forPartNum partNum: String) -> [NeededPart] {
      let family = catalog.partFamily(partNum: partNum)
      return parts.filter { family.contains($0.partNum) }
    }

    for candidate in resolver.localCandidates(for: item) {
      let found = matches(forPartNum: candidate)
      if !found.isEmpty {
        return found
      }
    }

    guard let resolved = await resolver.liveLookup(for: item) else { return [] }
    return matches(forPartNum: resolved)
  }
}
