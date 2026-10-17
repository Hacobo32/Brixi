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
    /// Keyed by NeededPart.id ("\(partNum)-\(colorId)"), counting how many
    /// crops this batch classified as "found" for that part/color --
    /// capped at quantityNeeded by the caller before persisting, same as
    /// single-piece mode's markFound.
    let foundCounts: [String: Int]
    let maybeParts: [NeededPart]
    let missing: [NeededPart]
  }

  /// Rolls up a batch of per-crop classifications against the full
  /// needed-parts list: how many of each were found, which matched parts
  /// are only "maybe," and which needed parts got no match at all (§4.4:
  /// "track what's still missing").
  static func tally(_ classifications: [PileMatchClassification], against parts: [NeededPart]) -> Tally {
    var foundCounts: [String: Int] = [:]
    var maybeParts: [NeededPart] = []
    var foundOrMaybeIds = Set<String>()

    for classification in classifications {
      switch classification {
      case .found(let part):
        foundCounts[part.id, default: 0] += 1
        foundOrMaybeIds.insert(part.id)
      case .maybe(let part):
        maybeParts.append(part)
        foundOrMaybeIds.insert(part.id)
      case .ignore:
        continue
      }
    }

    let missing = parts.filter { part in
      let alreadyFound = min(foundCounts[part.id] ?? 0, part.quantityNeeded)
      return alreadyFound + part.quantityFound < part.quantityNeeded
    }

    return Tally(foundCounts: foundCounts, maybeParts: maybeParts, missing: missing)
  }
}
