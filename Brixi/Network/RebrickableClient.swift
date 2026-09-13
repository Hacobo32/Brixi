//
// RebrickableClient.swift
//
// Live client for Rebrickable's REST API -- specifically the per-set parts
// endpoint, the one table deliberately not bundled locally (see
// docs/rebrickable-brickognize-feasibility.md, Part 1). Auth and endpoint
// shape confirmed against Rebrickable's own API docs (rebrickable.com/api/),
// not guessed.
//

import Foundation

struct RebrickablePartEntry: Decodable {
  let part: Part
  let color: Color
  let quantity: Int
  let isSpare: Bool

  struct Part: Decodable {
    let partNum: String
    let name: String
    let partImgURL: URL?

    enum CodingKeys: String, CodingKey {
      case partNum = "part_num"
      case name
      case partImgURL = "part_img_url"
    }
  }

  struct Color: Decodable {
    let id: Int
    let name: String
  }

  enum CodingKeys: String, CodingKey {
    case part
    case color
    case quantity
    case isSpare = "is_spare"
  }
}

private struct RebrickablePartsPage: Decodable {
  let next: String?
  let results: [RebrickablePartEntry]
}

enum RebrickableClientError: Error, LocalizedError {
  case missingAPIKey
  case invalidResponse
  case httpError(Int)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "No Rebrickable API key configured."
    case .invalidResponse:
      return "Rebrickable sent back something unexpected."
    case .httpError(let code):
      return "Rebrickable returned an error (status \(code))."
    }
  }
}

final class RebrickableClient {
  private let apiKey: String
  private let session: URLSession

  init(apiKey: String, session: URLSession = .shared) {
    self.apiKey = apiKey
    self.session = session
  }

  /// Reads the key from Info.plist's `RebrickableAPIKey`, populated at build
  /// time from Brixi/Config/Secrets.xcconfig (gitignored -- see
  /// Brixi/Config/Secrets.example.xcconfig for the format). Returns nil if no
  /// key is configured, so callers can degrade gracefully instead of crashing.
  static func fromInfoPlist(session: URLSession = .shared) -> RebrickableClient? {
    guard
      let key = Bundle.main.object(forInfoDictionaryKey: "RebrickableAPIKey") as? String,
      !key.isEmpty
    else {
      return nil
    }
    return RebrickableClient(apiKey: key, session: session)
  }

  /// Fetches every part line for a set (including spares -- callers decide
  /// whether to count those), following pagination. `setNum` must include
  /// Rebrickable's version suffix, e.g. "76342-1".
  func fetchParts(setNum: String) async throws -> [RebrickablePartEntry] {
    var all: [RebrickablePartEntry] = []
    var next: String? = "https://rebrickable.com/api/v3/lego/sets/\(setNum)/parts/?page_size=1000"

    while let urlString = next {
      guard let url = URL(string: urlString) else { throw RebrickableClientError.invalidResponse }
      var request = URLRequest(url: url)
      request.setValue("key \(apiKey)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw RebrickableClientError.invalidResponse
      }
      guard (200...299).contains(http.statusCode) else {
        throw RebrickableClientError.httpError(http.statusCode)
      }

      let page = try JSONDecoder().decode(RebrickablePartsPage.self, from: data)
      all.append(contentsOf: page.results)
      next = page.next
    }

    return all
  }
}
