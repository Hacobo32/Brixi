//
// BrickognizeClient.swift
//
// Networking layer for the Brickognize LEGO part recognition API
// (https://api.brickognize.com). No API key: the free tier is a public,
// unauthenticated endpoint rate-limited to 5 requests/second per IP.
//

import Foundation

enum BrickognizeError: Error, LocalizedError {
  case invalidResponse
  case rateLimited
  case httpError(statusCode: Int)
  case decodingFailed

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Brickognize returned an unexpected response."
    case .rateLimited:
      return "Too many requests to Brickognize — slow down and try again."
    case .httpError(let statusCode):
      return "Brickognize request failed (HTTP \(statusCode))."
    case .decodingFailed:
      return "Couldn't parse the Brickognize response."
    }
  }
}

protocol BrickognizeClientProtocol {
  func identifyPart(imageData: Data) async throws -> BrickognizePrediction
}

final class BrickognizeClient: BrickognizeClientProtocol {
  private static let endpoint = URL(string: "https://api.brickognize.com/predict/parts/?predict_color=true")!
  private static let requestTimeout: TimeInterval = 60

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func identifyPart(imageData: Data) async throws -> BrickognizePrediction {
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = Self.requestTimeout

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.multipartBody(boundary: boundary, imageData: imageData)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BrickognizeError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
      if httpResponse.statusCode == 429 {
        throw BrickognizeError.rateLimited
      }
      throw BrickognizeError.httpError(statusCode: httpResponse.statusCode)
    }

    do {
      return try JSONDecoder().decode(BrickognizePrediction.self, from: data)
    } catch {
      throw BrickognizeError.decodingFailed
    }
  }

  // Brickognize expects the image under the form field name "query_image".
  private static func multipartBody(boundary: String, imageData: Data) -> Data {
    var body = Data()
    func append(_ string: String) {
      body.append(Data(string.utf8))
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"query_image\"; filename=\"query_image.jpg\"\r\n")
    append("Content-Type: image/jpeg\r\n\r\n")
    body.append(imageData)
    append("\r\n")
    append("--\(boundary)--\r\n")
    return body
  }
}
