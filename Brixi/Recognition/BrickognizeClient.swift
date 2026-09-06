//
// BrickognizeClient.swift
//
// Minimal client for the live Brickognize recognition API
// (https://api.brickognize.com), confirmed against its OpenAPI spec and
// direct correspondence with its maintainer -- see
// docs/rebrickable-brickognize-feasibility.md. No API key: the current
// /predict/ endpoints are unauthenticated, rate-limited to 5 req/sec per
// IP (hence calling this directly from the client, never proxied through
// a shared backend).

import Foundation

struct BrickognizeSearchResult: Decodable {
  // Optional defensively: every response we've seen includes both, but
  // neither is documented as required in the OpenAPI spec.
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
    case left, upper, right, lower, score
    case imageWidth = "image_width"
    case imageHeight = "image_height"
  }
}

enum BrickognizeItemType: String, Decodable {
  case part, set, fig, sticker
}

struct BrickognizeItem: Decodable {
  // This is a Rebrickable part_num / set_num / fig_num, depending on
  // `type` -- Brickognize's IDs map directly onto Rebrickable's, with no
  // translation needed.
  let id: String
  let name: String
  let imgURL: URL?
  let category: String?
  let type: BrickognizeItemType
  let score: Double

  enum CodingKeys: String, CodingKey {
    case id, name, category, type, score
    case imgURL = "img_url"
  }
}

struct BrickognizeColor: Decodable {
  // A Rebrickable colors.id, as a string.
  let id: String
  let name: String
  let score: Double
}

final class BrickognizeClient {
  enum ClientError: Error, LocalizedError {
    case invalidResponse
    case rateLimited
    case httpError(status: Int, body: String)
    case decodingFailed

    var errorDescription: String? {
      switch self {
      case .invalidResponse:
        return "Brickognize returned an unexpected response."
      case .rateLimited:
        // Confirmed with the maintainer: 5 requests/second per IP, no
        // usage quota -- see docs/rebrickable-brickognize-feasibility.md.
        return "Too many requests to Brickognize -- slow down and try again."
      case .httpError(let status, _):
        return "Brickognize request failed (HTTP \(status))."
      case .decodingFailed:
        return "Couldn't parse the Brickognize response."
      }
    }
  }

  private let baseURL = URL(string: "https://api.brickognize.com")!
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// Identifies a LEGO part from a single image. `predictColor` also asks
  /// for color candidates in the response's `colors` field.
  func predictParts(imageData: Data, fileName: String = "capture.jpg", predictColor: Bool = true) async throws -> BrickognizeSearchResult {
    var components = URLComponents(url: baseURL.appendingPathComponent("predict/parts/"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "predict_color", value: predictColor ? "true" : "false")]
    guard let url = components.url else { throw ClientError.invalidResponse }

    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = multipartBody(imageData: imageData, fileName: fileName, boundary: boundary)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 429 {
        throw ClientError.rateLimited
      }
      throw ClientError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }
    do {
      return try JSONDecoder().decode(BrickognizeSearchResult.self, from: data)
    } catch {
      throw ClientError.decodingFailed
    }
  }

  private func multipartBody(imageData: Data, fileName: String, boundary: String) -> Data {
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"query_image\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    return body
  }
}
