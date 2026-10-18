//
// BurstFrameSelector.swift
//
// Picks the keeper from a capture burst (docs/pile-mode-spec.md §4.1).
// Plain sharpness (BlurDetector) isn't enough on its own: it measures
// edge contrast, with no idea what the edges belong to, so a perfectly
// sharp frame pointed at the wrong thing entirely (the user's head
// turned away from the mat mid-burst) can out-score a slightly blurred
// frame correctly aimed at the pile -- confirmed live, when a frame
// pointed at a TV/phone scored higher than a blurry-but-correctly-aimed
// pile photo purely on contrast.
//
// Fix: before ranking by sharpness, group frames by whether their
// central region plausibly shows the same thing (same dominant hue,
// the same signal PileSegmenter itself uses to find the mat). If most
// of the burst agrees on what it's looking at, rank sharpness only
// within that consensus group, so a wrong-scene frame can't win just
// by being sharp. If the whole burst disagrees (no two frames close
// enough to call a consensus), there's no reliable signal to prefer one
// over another on these grounds, so nothing is excluded.
//

import Foundation

enum BurstFrameSelector {
  static func pickBest(from frames: [Data]) -> Data? {
    let hues = frames.map { PileSegmenter.centralDominantHue(in: $0) }

    var buckets: [(hue: Int, frames: [Data])] = []
    for (frame, hue) in zip(frames, hues) {
      guard let hue else { continue }
      if let index = buckets.firstIndex(where: { hueDistance($0.hue, hue) <= 20 }) {
        buckets[index].frames.append(frame)
      } else {
        buckets.append((hue: hue, frames: [frame]))
      }
    }

    let consensus = buckets.max { $0.frames.count < $1.frames.count }
    let candidates = (consensus?.frames.count ?? 0) >= 2 ? consensus!.frames : frames

    return BlurDetector.sharpest(of: candidates)?.data
  }

  private static func hueDistance(_ a: Int, _ b: Int) -> Int {
    min(abs(a - b), 256 - abs(a - b))
  }
}
