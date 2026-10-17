//
// BlurDetector.swift
//
// Pile mode's "pick sharpest" step (docs/pile-mode-spec.md §4.1): scores
// a frame's focus via the variance of its Laplacian over a grayscale,
// downscaled copy -- a sharp image has well-defined edges, so the
// Laplacian (a second-derivative edge operator) swings widely across the
// frame; a blurred image's edges are smeared, so the Laplacian stays
// close to zero everywhere and the variance collapses. Downscaling first
// keeps scoring fast and keeps scores comparable across frames of
// slightly different source resolution.
//

import CoreGraphics
import Foundation

enum BlurDetector {
  /// Higher is sharper. Returns nil only if the image couldn't be decoded.
  static func sharpnessScore(of imageData: Data) -> Double? {
    guard let image = ImageDecoding.orientedCGImage(from: imageData) else { return nil }
    guard let gray = grayscaleBytes(of: image, maxDimension: 480) else { return nil }
    return laplacianVariance(gray.pixels, width: gray.width, height: gray.height)
  }

  /// Scores every frame and returns the sharpest, e.g. to pick the keeper
  /// from a capture burst. Nil only if none of the frames could be scored.
  static func sharpest(of frames: [Data]) -> (data: Data, score: Double)? {
    frames.compactMap { data in sharpnessScore(of: data).map { (data, $0) } }
      .max { $0.score < $1.score }
  }

  private static func grayscaleBytes(
    of image: CGImage,
    maxDimension: Int
  ) -> (pixels: [UInt8], width: Int, height: Int)? {
    let longestSide = max(image.width, image.height)
    guard longestSide > 0 else { return nil }
    let scale = min(1.0, Double(maxDimension) / Double(longestSide))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))

    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (pixels, width, height)
  }

  private static func laplacianVariance(_ pixels: [UInt8], width: Int, height: Int) -> Double {
    guard width > 2, height > 2 else { return 0 }
    var values: [Double] = []
    values.reserveCapacity((width - 2) * (height - 2))
    pixels.withUnsafeBufferPointer { src in
      for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
          let center = Double(src[y * width + x])
          let up = Double(src[(y - 1) * width + x])
          let down = Double(src[(y + 1) * width + x])
          let left = Double(src[y * width + x - 1])
          let right = Double(src[y * width + x + 1])
          values.append(up + down + left + right - 4 * center)
        }
      }
    }
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return variance
  }
}
