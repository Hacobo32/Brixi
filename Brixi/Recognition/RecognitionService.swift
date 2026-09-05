//
// RecognitionService.swift
//
// Combines a Brickognize recognition call with the local catalog:
// resolves a matched item's id/color against CatalogDatabase, and applies
// the confidence gate from the empirical testing round (see
// docs/rebrickable-brickognize-feasibility.md) -- distinctive, plain
// pieces get a confident single match; decorated/niche pieces spread
// confidence thin across several near neighbors and shouldn't be
// auto-identified.

import Foundation

struct RecognizedPiece {
  let item: BrickognizeItem
  let confidence: Double
  let catalogPart: CatalogPart?
  let catalogSet: CatalogSet?
  let catalogMinifig: CatalogMinifig?
  let colorName: String?
  let imageURL: URL?
}

enum RecognitionOutcome {
  /// Top match cleared the confidence threshold -- safe to auto-display.
  case recognized(RecognizedPiece)
  /// Something was localized, but no candidate was confident enough to
  /// trust alone -- surface these for the user to pick from instead.
  case lowConfidence(candidates: [BrickognizeItem])
  /// Nothing recognizable found in the frame at all.
  case notFound
}

final class RecognitionService {
  /// Empirically, distinctive single-color pieces cleared ~0.85+ while
  /// decorated/niche pieces topped out around 0.2-0.4 with no clear
  /// winner -- 0.7 sits well clear of that gap.
  static let defaultConfidenceThreshold = 0.7

  private let client: BrickognizeClient
  private let catalog: CatalogDatabase
  private let confidenceThreshold: Double

  init(client: BrickognizeClient = BrickognizeClient(), catalog: CatalogDatabase, confidenceThreshold: Double = RecognitionService.defaultConfidenceThreshold) {
    self.client = client
    self.catalog = catalog
    self.confidenceThreshold = confidenceThreshold
  }

  func recognize(imageData: Data) async throws -> RecognitionOutcome {
    let result = try await client.predictParts(imageData: imageData, predictColor: true)

    guard let topItem = result.items.first else {
      return .notFound
    }
    guard topItem.score >= confidenceThreshold else {
      return .lowConfidence(candidates: result.items)
    }

    return .recognized(resolve(topItem, colors: result.colors))
  }

  private func resolve(_ item: BrickognizeItem, colors: [BrickognizeColor]?) -> RecognizedPiece {
    var catalogPart: CatalogPart?
    var catalogSet: CatalogSet?
    var catalogMinifig: CatalogMinifig?

    switch item.type {
    case .part, .sticker:
      catalogPart = catalog.part(partNum: item.id)
    case .set:
      catalogSet = catalog.set(setNum: item.id)
    case .fig:
      catalogMinifig = catalog.minifig(figNum: item.id)
    }

    let topColor = colors?.first
    let colorId = topColor.flatMap { Int($0.id) }
    let resolvedColorName = colorId.flatMap(catalog.colorName(colorId:)) ?? topColor?.name

    // Prefer the local catalog's element photo (resolved via the
    // part+color join) over Brickognize's own thumbnail when a color
    // match is available.
    var imageURL = item.imgURL
    if let colorId, let partNum = catalogPart?.partNum,
       let resolvedImageURL = catalog.elementImageURL(partNum: partNum, colorId: colorId) {
      imageURL = resolvedImageURL
    }

    return RecognizedPiece(
      item: item,
      confidence: item.score,
      catalogPart: catalogPart,
      catalogSet: catalogSet,
      catalogMinifig: catalogMinifig,
      colorName: resolvedColorName,
      imageURL: imageURL
    )
  }
}
