//
// ImageDecoding.swift
//
// Shared JPEG-decode-with-EXIF-orientation helper, used by both
// PileSegmenter and BlurDetector so pixel coordinates (and crop/variance
// math) match what a viewer -- and Brickognize -- would actually see,
// regardless of how the capturing device rotated the sensor data.
//

import CoreGraphics
import CoreImage
import Foundation

enum ImageDecoding {
  static func orientedCGImage(from data: Data) -> CGImage? {
    guard let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
    return CIContext().createCGImage(ciImage, from: ciImage.extent)
  }
}
