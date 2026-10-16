//
// PileSegmenter.swift
//
// Pile mode's "find pieces" step (docs/pile-mode-spec.md §4.2, v1: color
// separation, no ML). A direct, step-for-step port of the Python
// prototype already validated against real toolkit-captured pile photos
// during Phase 0 testing -- same HSV masking, morphology, connected
// components, and filtering, so the crop counts/quality already seen on
// real photos should carry over.
//
// Assumes pieces are spread on a plain, single-color mat that contrasts
// with the bricks (blue/teal tested).
//

import CoreGraphics
import CoreImage
import Foundation

enum PileSegmenter {
  struct DetectedPiece {
    /// Padded bounding box in the result image's pixel coordinates,
    /// clamped to the image bounds.
    let rect: CGRect
  }

  struct Result {
    /// Orientation-corrected (EXIF-applied) base image -- `pieces`'
    /// rects are in this image's coordinate space, not the raw JPEG's.
    let image: CGImage
    let pieces: [DetectedPiece]
  }

  /// Runs the full find-pieces pipeline against a captured photo's raw
  /// JPEG data. Returns nil only if the image itself couldn't be
  /// decoded -- an image with zero detected pieces is still a valid
  /// (empty) result.
  static func detectPieces(in imageData: Data) -> Result? {
    guard let image = orientedCGImage(from: imageData) else { return nil }
    let pieces = detectPieces(in: image)
    return Result(image: image, pieces: pieces)
  }

  static func crop(_ piece: DetectedPiece, from image: CGImage) -> CGImage? {
    image.cropping(to: piece.rect)
  }

  // MARK: - Pipeline

  private static func detectPieces(in image: CGImage) -> [DetectedPiece] {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0, let rgba = rgbaBytes(of: image) else { return [] }

    let (hue, sat) = hsv(fromRGBA: rgba, width: width, height: height)
    let matHue = dominantHue(hue: hue, width: width, height: height)

    var notMat = [UInt8](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
      let h = Int(hue[i])
      let dist = min(abs(h - matHue), 256 - abs(h - matHue))
      notMat[i] = (dist > 22 || sat[i] < 40) ? 1 : 0
    }

    var mask = binaryOpen(notMat, width: width, height: height, iterations: 4)
    mask = binaryClose(mask, width: width, height: height, iterations: 4)
    mask = fillHoles(mask, width: width, height: height)

    let components = connectedComponents(mask, width: width, height: height)

    // Scales with image size; 1500px^2 is the base case for a
    // 1440x1080 frame, matching the Python prototype.
    let minArea = max(1500, Int(1500.0 * Double(width * height) / (1440.0 * 1080.0)))

    var results: [DetectedPiece] = []
    for component in components {
      guard component.area >= minArea else { continue }
      let box = component.boundingBox
      let touchesBorder = box.minX == 0 || box.minY == 0 || box.maxX == width || box.maxY == height
      guard !touchesBorder else { continue }

      let boxWidth = box.maxX - box.minX
      let boxHeight = box.maxY - box.minY
      let bboxArea = boxWidth * boxHeight
      guard bboxArea > 0 else { continue }
      let fillRatio = Double(component.area) / Double(bboxArea)
      guard fillRatio >= 0.2 else { continue }

      let longestSide = max(boxWidth, boxHeight)
      guard Double(longestSide) < 0.4 * Double(width) else { continue }

      let padding = Int(0.35 * Double(longestSide)) + 10
      let x0 = max(0, box.minX - padding)
      let y0 = max(0, box.minY - padding)
      let x1 = min(width, box.maxX + padding)
      let y1 = min(height, box.maxY + padding)
      results.append(DetectedPiece(rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)))
    }
    return results
  }

  // MARK: - Decode + orientation

  /// Applies the JPEG's EXIF orientation before any pixel access, so
  /// mask/crop coordinates match what a viewer (and Brickognize) would
  /// actually see -- matches the Python prototype's
  /// `ImageOps.exif_transpose`.
  private static func orientedCGImage(from data: Data) -> CGImage? {
    guard let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
    return CIContext().createCGImage(ciImage, from: ciImage.extent)
  }

  private static func rgbaBytes(of image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &bytes,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }

  // MARK: - HSV (0-255 scale, matching the OpenCV-style convention the
  // Python prototype used -- not Swift/UIKit's 0-1 HSB)

  private static func hsv(fromRGBA rgba: [UInt8], width: Int, height: Int) -> (hue: [UInt8], sat: [UInt8]) {
    let count = width * height
    var hue = [UInt8](repeating: 0, count: count)
    var sat = [UInt8](repeating: 0, count: count)
    rgba.withUnsafeBufferPointer { buf in
      for i in 0..<count {
        let r = Double(buf[i * 4]) / 255.0
        let g = Double(buf[i * 4 + 1]) / 255.0
        let b = Double(buf[i * 4 + 2]) / 255.0
        let maxc = max(r, g, b)
        let minc = min(r, g, b)
        let delta = maxc - minc
        let s = maxc == 0 ? 0 : delta / maxc
        var h = 0.0
        if delta != 0 {
          if maxc == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
          } else if maxc == g {
            h = (b - r) / delta + 2
          } else {
            h = (r - g) / delta + 4
          }
          h /= 6
          if h < 0 { h += 1 }
        }
        hue[i] = UInt8(clamping: Int((h * 255).rounded()))
        sat[i] = UInt8(clamping: Int((s * 255).rounded()))
      }
    }
    return (hue, sat)
  }

  private static func dominantHue(hue: [UInt8], width: Int, height: Int) -> Int {
    let y0 = Int(Double(height) * 0.35)
    let y1 = Int(Double(height) * 0.65)
    let x0 = Int(Double(width) * 0.35)
    let x1 = Int(Double(width) * 0.65)
    var counts = [Int](repeating: 0, count: 256)
    for y in y0..<y1 {
      for x in x0..<x1 {
        counts[Int(hue[y * width + x])] += 1
      }
    }
    var bestHue = 0
    var bestCount = -1
    for (h, c) in counts.enumerated() where c > bestCount {
      bestHue = h
      bestCount = c
    }
    return bestHue
  }

  // MARK: - Morphology (full 3x3 neighborhood, out-of-bounds treated as
  // background -- matches scipy's default border_value=0)

  private static func erode(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height)
    mask.withUnsafeBufferPointer { src in
      for y in 0..<height {
        for x in 0..<width {
          var allSet = true
          loop: for dy in -1...1 {
            for dx in -1...1 {
              let ny = y + dy, nx = x + dx
              if ny < 0 || ny >= height || nx < 0 || nx >= width || src[ny * width + nx] == 0 {
                allSet = false
                break loop
              }
            }
          }
          result[y * width + x] = allSet ? 1 : 0
        }
      }
    }
    return result
  }

  private static func dilate(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height)
    mask.withUnsafeBufferPointer { src in
      for y in 0..<height {
        for x in 0..<width {
          var anySet = false
          loop: for dy in -1...1 {
            for dx in -1...1 {
              let ny = y + dy, nx = x + dx
              if ny >= 0, ny < height, nx >= 0, nx < width, src[ny * width + nx] == 1 {
                anySet = true
                break loop
              }
            }
          }
          result[y * width + x] = anySet ? 1 : 0
        }
      }
    }
    return result
  }

  private static func binaryOpen(_ mask: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
    var result = mask
    for _ in 0..<iterations { result = erode(result, width: width, height: height) }
    for _ in 0..<iterations { result = dilate(result, width: width, height: height) }
    return result
  }

  private static func binaryClose(_ mask: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
    var result = mask
    for _ in 0..<iterations { result = dilate(result, width: width, height: height) }
    for _ in 0..<iterations { result = erode(result, width: width, height: height) }
    return result
  }

  // MARK: - Fill holes

  /// Background pixels not reachable from the image border via 4-
  /// connected flood fill over the background are enclosed holes --
  /// filled in. Matches scipy's binary_fill_holes.
  private static func fillHoles(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
    var reachable = [UInt8](repeating: 0, count: width * height)
    var stack: [Int] = []
    stack.reserveCapacity(width + height)

    func tryPush(_ x: Int, _ y: Int) {
      guard x >= 0, x < width, y >= 0, y < height else { return }
      let idx = y * width + x
      guard mask[idx] == 0, reachable[idx] == 0 else { return }
      reachable[idx] = 1
      stack.append(idx)
    }

    for x in 0..<width {
      tryPush(x, 0)
      tryPush(x, height - 1)
    }
    for y in 0..<height {
      tryPush(0, y)
      tryPush(width - 1, y)
    }

    while let idx = stack.popLast() {
      let x = idx % width
      let y = idx / width
      tryPush(x - 1, y)
      tryPush(x + 1, y)
      tryPush(x, y - 1)
      tryPush(x, y + 1)
    }

    var filled = mask
    for i in 0..<(width * height) where mask[i] == 0 && reachable[i] == 0 {
      filled[i] = 1
    }
    return filled
  }

  // MARK: - Connected components (4-connectivity, matching scipy's
  // default structure for ndimage.label in 2D)

  private struct ComponentResult {
    let area: Int
    let boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int) // maxX/maxY exclusive
  }

  private static func connectedComponents(_ mask: [UInt8], width: Int, height: Int) -> [ComponentResult] {
    var visited = [UInt8](repeating: 0, count: width * height)
    var results: [ComponentResult] = []
    var stack: [Int] = []

    for start in 0..<(width * height) where mask[start] == 1 && visited[start] == 0 {
      var area = 0
      var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
      visited[start] = 1
      stack.append(start)

      while let idx = stack.popLast() {
        let x = idx % width
        let y = idx / width
        area += 1
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)

        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
          let nx = x + dx, ny = y + dy
          guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
          let nIdx = ny * width + nx
          guard mask[nIdx] == 1, visited[nIdx] == 0 else { continue }
          visited[nIdx] = 1
          stack.append(nIdx)
        }
      }

      results.append(ComponentResult(area: area, boundingBox: (minX, minY, maxX + 1, maxY + 1)))
    }
    return results
  }
}
