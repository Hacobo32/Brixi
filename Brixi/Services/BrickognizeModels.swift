//
// BrickognizeModels.swift
//
// Decodable models for the Brickognize `/predict/parts/?predict_color=true`
// response. Field names/types verified against real API responses logged by
// https://github.com/rainman19121979/HB-Sort (see BRICKOGNIZE_API.md there) —
// notably bounding_box coordinates are doubles, and `colors` is only
// populated when predict_color=true.
//

import Foundation

struct BrickognizePrediction: Decodable {
  let listingId: String?
  let boundingBox: BrickognizeBoundingBox?
  let items: [BrickognizeItem]
  let colors: [BrickognizeColor]?

  enum CodingKeys: String, CodingKey {
    case listingId = "listing_id"
    case boundingBox = "bounding_box"
    case items
    case colors
  }
}

struct BrickognizeBoundingBox: Decodable {
  let left: Double
  let upper: Double
  let right: Double
  let lower: Double
  let imageWidth: Double
  let imageHeight: Double
  let score: Double

  enum CodingKeys: String, CodingKey {
    case left, upper, right, lower
    case imageWidth = "image_width"
    case imageHeight = "image_height"
    case score
  }
}

// Sorted descending by score in the API response; items.first is the top match.
struct BrickognizeItem: Decodable, Identifiable {
  let id: String
  let name: String
  let imgUrl: String?
  let externalSites: [BrickognizeExternalSite]
  let category: String?
  let type: String
  let score: Double

  enum CodingKeys: String, CodingKey {
    case id, name
    case imgUrl = "img_url"
    case externalSites = "external_sites"
    case category, type, score
  }
}

struct BrickognizeExternalSite: Decodable {
  let name: String
  let url: String
}

struct BrickognizeColor: Decodable, Identifiable {
  let id: String
  let name: String
  let score: Double
}
