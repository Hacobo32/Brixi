//
// PartIDResolver.swift
//
// Reconciles Brickognize's BrickLink-style part IDs with Rebrickable's own
// ID scheme, per docs/pile-mode-spec.md §6. The two sources disagree,
// especially for printed/stickered/mould variants -- Brickognize answered
// "30562pb059" for a piece that genuinely was in set 76157, and the
// needed-parts list (sourced from Rebrickable) scored it "not in set"
// because nothing in the catalog's part_relationships table happened to
// link that exact print variant back to its base part. Reproduced live,
// twice, before this existed.
//
// Fallback order, cheapest/most-certain first -- and tried in that order,
// not computed all at once, so the live lookup (step 3) only ever runs
// when steps 1-2 come up empty:
// 1. The raw ID as Brickognize returned it -- the common case, and the
//    one CatalogDatabase.partFamily already resolves correctly via
//    part_relationships when the two sources happen to agree.
// 2. A shape-level match: strip print (`pb…`), pattern (`pr…`), and
//    assembly (`c01`, `c02`, …) suffixes to compare base mold numbers.
//    No network needed -- matches the spec's own worked examples
//    (`30562pb059` -> `30562`, `2429c01` -> `2429`).
// 3. A live Rebrickable lookup by BrickLink ID, cached locally so the
//    same ID is never looked up twice in a session.
//
// Brickognize's `external_sites` field (the spec's own first preference)
// is deliberately not implemented here -- its JSON shape isn't verifiable
// from this environment (api.brickognize.com is unreachable), and
// guessing at an unverified field risks silently never firing. Steps 2
// and 3 already cover every case seen in testing so far.

import Foundation

actor PartIDResolver {
  private let client: RebrickableClient?
  private var cache: [String: String?] = [:]

  init(client: RebrickableClient?) {
    self.client = client
  }

  /// The raw ID and shape-stripped base ID -- no network, instant. Callers
  /// try each against the catalog in order and stop at the first real
  /// match, falling back to `liveLookup(for:)` only if neither hits --
  /// covers the common case (§6: "the one CatalogDatabase.partFamily
  /// already resolves correctly... when the two sources happen to agree")
  /// without ever touching the network for it. Previously this and the
  /// live lookup were combined into one array, built eagerly -- meaning
  /// every crop paid for a live Rebrickable round trip even when the raw
  /// ID already matched, which was the real cost behind pile mode's
  /// end-to-end scan time coming in well over the §5 target (a 68s scan
  /// against a ~19s budget for capture + recognition alone).
  nonisolated func localCandidates(for item: BrickognizeItem) -> [String] {
    var seen = Set<String>()
    var results: [String] = []
    func add(_ id: String?) {
      guard let id, !id.isEmpty, seen.insert(id).inserted else { return }
      results.append(id)
    }

    add(item.id)
    add(Self.baseID(item.id))

    return results
  }

  /// A live Rebrickable lookup by BrickLink ID, cached locally so the same
  /// ID is never looked up twice in a session -- only worth calling once
  /// `localCandidates(for:)` has already failed to match anything.
  func liveLookup(for item: BrickognizeItem) async -> String? {
    await lookup(bricklinkID: item.id)
  }

  private func lookup(bricklinkID: String) async -> String? {
    if let cached = cache[bricklinkID] {
      return cached
    }
    guard let client else {
      cache[bricklinkID] = .some(nil)
      return nil
    }
    let resolved = await client.lookupPartNum(bricklinkID: bricklinkID)
    cache[bricklinkID] = .some(resolved)
    return resolved
  }

  /// Strips a trailing assembly suffix (`c01`, `c02`, …) then a trailing
  /// print/pattern suffix (`pb…`, `pr…`). Leaves single-letter mould
  /// variant suffixes (e.g. the `b` in `4460b`) untouched -- those denote
  /// a genuinely different mould, not just a decoration, and collapsing
  /// them would be over-matching rather than fixing a naming mismatch.
  static func baseID(_ id: String) -> String {
    var result = id
    if let range = result.range(of: #"c\d+$"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    if let range = result.range(of: #"p[br]\d+$"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    return result
  }
}
