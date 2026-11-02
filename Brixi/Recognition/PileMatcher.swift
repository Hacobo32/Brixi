//
// PileMatcher.swift
//
// Pile mode's "check against the set list" step (docs/pile-mode-spec.md
// §4.4): classifies one crop's Brickognize result as found / maybe /
// ignore against a build's needed-parts list, and tallies a whole batch
// of classifications into found/missing counts.
//

import Foundation

enum PileMatchClassification {
  /// The top item is a set part at score >= 0.75 -- confident enough to
  /// count automatically.
  case found(NeededPart)
  /// A set part appears within the top 3 items at score >= 0.50, but
  /// didn't clear "found" -- worth showing, not worth counting yet.
  case maybe(NeededPart)
  /// Nothing in the top 3 resolves to a part this build needs (or the
  /// crop didn't recognize at all). Stay silent on these, per §4.4 --
  /// junk crops are expected and shouldn't be announced.
  case ignore
}

enum PileMatcher {
  /// Classifies one crop. Walks the top 3 ranked items (if any): "found"
  /// requires the very top item itself to be a confident set-part match,
  /// not just the first match somewhere in the top 3 (that's "maybe").
  /// `predict_color` breaks ties when the matched shape is needed in more
  /// than one color -- same tie-break BuildDetailViewModel.evaluate() uses
  /// for single-piece mode.
  ///
  /// Matching is local-only (no network) for every ranked item, with at
  /// most **one** live Rebrickable lookup per crop -- on the top item,
  /// and only if its local candidates didn't already match. This is what
  /// catches §6's printed/variant-ID mismatch case (Brickognize's ID
  /// disagreeing with Rebrickable's for the item that's actually the
  /// real match), without paying a network round trip per ranked item on
  /// every crop that simply isn't part of this build -- most crops in a
  /// real pile. Previously each of up to 3 ranked items could trigger its
  /// own live lookup (and the top item could trigger two, once here and
  /// again from the "maybe" loop below re-checking it), which was the
  /// dominant cost behind a pile scan's classify step still taking ~70s
  /// after the first fix removed the *unconditional* lookup -- see
  /// docs/pile-mode-spec.md §11. Items 2-3 no longer get a live lookup at
  /// all: "maybe" isn't auto-counted, so the lower recall on an exotic
  /// variant there is an acceptable trade for not scaling network calls
  /// with how cluttered the pile is.
  static func classify(
    _ result: BrickognizeSearchResult,
    against parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> PileMatchClassification {
    let rankedItems = Array(result.items.prefix(3))
    guard !rankedItems.isEmpty else { return .ignore }
    let topColorId = result.colors?.first.flatMap { Int($0.id) }

    func pick(_ matches: [NeededPart]) -> NeededPart? {
      guard let firstMatch = matches.first else { return nil }
      return matches.first { $0.colorId == topColorId } ?? firstMatch
    }

    var topMatches: [NeededPart] = []
    if let topItem = rankedItems.first, topItem.type == .part || topItem.type == .sticker {
      topMatches = NeededPartMatcher.matchLocal(topItem, in: parts, catalog: catalog, resolver: resolver)
      if topMatches.isEmpty {
        topMatches = await NeededPartMatcher.matchLive(topItem, in: parts, catalog: catalog, resolver: resolver)
      }
      if topItem.score >= 0.75, let match = pick(topMatches) {
        return .found(match)
      }
      if topItem.score >= 0.50, let match = pick(topMatches) {
        return .maybe(match)
      }
    }

    for item in rankedItems.dropFirst() where item.score >= 0.50 && (item.type == .part || item.type == .sticker) {
      if let match = pick(NeededPartMatcher.matchLocal(item, in: parts, catalog: catalog, resolver: resolver)) {
        return .maybe(match)
      }
    }

    return .ignore
  }

  struct Tally {
    /// One entry per distinct part/color this batch found, with how many
    /// crops matched it -- shaped for the results screen's "Found" list
    /// directly, rather than a count dict callers would have to re-join
    /// back to a NeededPart themselves.
    let found: [(part: NeededPart, count: Int)]
    let maybe: [NeededPart]
    let missing: [NeededPart]
  }

  /// Rolls up a batch of per-crop classifications against the full
  /// needed-parts list: how many of each were found, which matched parts
  /// are only "maybe," and which needed parts got no match at all (§4.4:
  /// "track what's still missing").
  static func tally(_ classifications: [PileMatchClassification], against parts: [NeededPart]) -> Tally {
    var foundCounts: [String: Int] = [:]
    var foundParts: [String: NeededPart] = [:]
    var maybe: [NeededPart] = []

    for classification in classifications {
      switch classification {
      case .found(let part):
        foundCounts[part.id, default: 0] += 1
        foundParts[part.id] = part
      case .maybe(let part):
        maybe.append(part)
      case .ignore:
        continue
      }
    }

    let found = foundCounts.compactMap { id, count in foundParts[id].map { (part: $0, count: count) } }
    let missing = parts.filter { part in
      let alreadyFound = min(foundCounts[part.id] ?? 0, part.quantityNeeded)
      return alreadyFound + part.quantityFound < part.quantityNeeded
    }

    return Tally(found: found, maybe: maybe, missing: missing)
  }
}

extension PileMatchClassification {
  /// The matched NeededPart, regardless of whether it was a confident
  /// "found" or a weaker "maybe" -- convenient for UI that treats both
  /// cases similarly (e.g. drawing a box). nil for `.ignore`.
  var neededPart: NeededPart? {
    switch self {
    case .found(let part), .maybe(let part):
      return part
    case .ignore:
      return nil
    }
  }
}
