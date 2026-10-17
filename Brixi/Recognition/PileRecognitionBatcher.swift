//
// PileRecognitionBatcher.swift
//
// Pile mode's "name pieces" step (docs/pile-mode-spec.md §4.3): recognizes
// one crop at a time against Brickognize, paced to stay under its 5
// req/s-per-IP limit, with a session-scoped result cache and a single
// retry before giving up on a crop. Pacing and progress live in the
// caller's own loop (see PileSegmentationTestViewModel.recognizeCrops())
// rather than behind a closure here, so a MainActor caller can update
// published progress state between calls without crossing an actor
// boundary through an un-isolated closure.
//

import CryptoKit
import Foundation

final class PileRecognitionBatcher {
  private let client: BrickognizeClient
  private let minInterval: Duration
  private let clock = ContinuousClock()
  private var lastRequestStart: ContinuousClock.Instant?
  private var cache: [String: BrickognizeSearchResult] = [:]
  /// Set on every failed attempt (overwritten, not accumulated) so a
  /// caller can report *something* concrete when every crop in a batch
  /// comes back nil -- "it failed" alone isn't diagnosable.
  private(set) var lastErrorDescription: String?

  init(client: BrickognizeClient = BrickognizeClient(), requestsPerSecond: Double = 4) {
    self.client = client
    self.minInterval = .seconds(1.0 / requestsPerSecond)
  }

  /// A session cache hit returns immediately (no network call, no pacing
  /// delay). Otherwise waits out the rate limit before calling, retries
  /// once on failure, and gives up (nil) rather than failing the whole
  /// batch -- matches the spec's ~15% expected junk-crop rate, where some
  /// crops are never going to resolve to anything.
  func recognize(crop: Data) async -> BrickognizeSearchResult? {
    let hash = cropHash(crop)
    if let cached = cache[hash] { return cached }

    if let lastRequestStart {
      let elapsed = clock.now - lastRequestStart
      if elapsed < minInterval {
        try? await Task.sleep(for: minInterval - elapsed)
      }
    }
    lastRequestStart = clock.now

    for attempt in 0..<2 {
      do {
        let result = try await client.predictParts(imageData: crop, predictColor: true, topK: 50)
        cache[hash] = result
        return result
      } catch {
        lastErrorDescription = error.localizedDescription
        if attempt == 0 { continue }
      }
    }
    return nil
  }

  private func cropHash(_ data: Data) -> String {
    SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
  }
}
