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
  /// Tries PartIDResolver's local candidates (raw ID, shape-stripped base
  /// ID) against the catalog's part family in order, no network -- returns
  /// every needed-parts row the first matching candidate hits, more than
  /// one meaning this part shape is needed in multiple colors (the caller
  /// uses that to decide whether color needs consulting).
  static func matchLocal(
    _ item: BrickognizeItem,
    in parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) -> [NeededPart] {
    for candidate in resolver.localCandidates(for: item) {
      let found = matches(forPartNum: candidate, in: parts, catalog: catalog)
      if !found.isEmpty {
        return found
      }
    }
    return []
  }

  /// A live Rebrickable lookup for `item`, independent of whether local
  /// candidates were already tried -- callers that want "local, then live
  /// only if local came up empty" should check `matchLocal` first
  /// themselves (PileMatcher.classify caps this to once per crop rather
  /// than once per ranked item -- see its own doc comment).
  static func matchLive(
    _ item: BrickognizeItem,
    in parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> [NeededPart] {
    guard let resolved = await resolver.liveLookup(for: item) else { return [] }
    return matches(forPartNum: resolved, in: parts, catalog: catalog)
  }

  /// `matchLocal`, falling back to `matchLive` only if that came up empty
  /// -- single-piece mode's one-item-per-scan shape, where an extra round
  /// trip on a miss is cheap. Pile mode uses `matchLocal`/`matchLive`
  /// directly instead, to cap live lookups per crop (see PileMatcher).
  static func match(
    _ item: BrickognizeItem,
    in parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> [NeededPart] {
    let local = matchLocal(item, in: parts, catalog: catalog, resolver: resolver)
    if !local.isEmpty { return local }
    return await matchLive(item, in: parts, catalog: catalog, resolver: resolver)
  }

  private static func matches(forPartNum partNum: String, in parts: [NeededPart], catalog: CatalogDatabase) -> [NeededPart] {
    let family = catalog.partFamily(partNum: partNum)
    return parts.filter { family.contains($0.partNum) }
  }
}
