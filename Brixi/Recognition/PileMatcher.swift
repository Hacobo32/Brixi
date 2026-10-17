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
  static func classify(
    _ result: BrickognizeSearchResult,
    against parts: [NeededPart],
    catalog: CatalogDatabase,
    resolver: PartIDResolver
  ) async -> PileMatchClassification {
    let rankedItems = Array(result.items.prefix(3))
    guard !rankedItems.isEmpty else { return .ignore }
    let topColorId = result.colors?.first.flatMap { Int($0.id) }

    if let topItem = rankedItems.first,
       topItem.type == .part || topItem.type == .sticker,
       topItem.score >= 0.75 {
      let matches = await NeededPartMatcher.match(topItem, in: parts, catalog: catalog, resolver: resolver)
      if let firstMatch = matches.first {
        return .found(matches.first { $0.colorId == topColorId } ?? firstMatch)
      }
    }

    for item in rankedItems where item.score >= 0.50 && (item.type == .part || item.type == .sticker) {
      let matches = await NeededPartMatcher.match(item, in: parts, catalog: catalog, resolver: resolver)
      if let firstMatch = matches.first {
        return .maybe(matches.first { $0.colorId == topColorId } ?? firstMatch)
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
