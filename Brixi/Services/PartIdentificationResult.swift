//
// PartIdentificationResult.swift
//
// Applies Brixi's confidence-threshold policy (PROJECT_CONTEXT.md §3 step 5)
// to a raw Brickognize prediction: top score >= 0.7 announces the top match,
// otherwise the top 2-3 candidates are offered instead of a single guess.
//

import Foundation

enum PartIdentificationResult {
  case confidentMatch(BrickognizeItem)
  case uncertainMatches([BrickognizeItem])
  case noMatch

  static let confidenceThreshold = 0.7
  static let maxCandidates = 3

  init(prediction: BrickognizePrediction, confidenceThreshold: Double = PartIdentificationResult.confidenceThreshold) {
    // items[] is already sorted descending by score by the API.
    guard let top = prediction.items.first else {
      self = .noMatch
      return
    }

    if top.score >= confidenceThreshold {
      self = .confidentMatch(top)
    } else {
      self = .uncertainMatches(Array(prediction.items.prefix(Self.maxCandidates)))
    }
  }
}
