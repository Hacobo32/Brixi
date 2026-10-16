//
// CaptureDiagnostics.swift
//
// Phase 0 of pile mode (see docs/pile-mode-spec.md): before building
// anything else, confirm the glasses' actual still-capture resolution
// through the DAT toolkit. A field report suggested the live stream caps
// out at 360x640, which would be useless for pile mode, but capturePhoto()
// stills may be much larger -- this is how we find out, instead of
// guessing.
//
// When the "Save Captures" debug toggle is on (Settings), every photo this
// app captures -- glasses or phone, single-piece or (later) pile mode --
// is written to Photos exactly as captured, with no recompression, and its
// real pixel dimensions/byte size are logged and surfaced on screen.
//

import Foundation
import ImageIO
import Photos
import os

enum CaptureSource: String {
  case glasses
  case phone
}

struct CaptureDiagnosticsInfo: Equatable {
  let source: CaptureSource
  let pixelWidth: Int
  let pixelHeight: Int
  let byteCount: Int

  var summary: String {
    let kilobytes = byteCount / 1024
    return "\(source.rawValue): \(pixelWidth)×\(pixelHeight), \(kilobytes) KB"
  }
}

@MainActor
enum CaptureDiagnostics {
  /// Shared with the "Save Captures" toggle in Settings via @AppStorage on
  /// the same key -- reading it here doesn't need its own binding.
  private static let enabledKey = "com.brixi.debug.saveCaptures"

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: enabledKey)
  }

  /// No-ops and returns nil when the toggle is off, so every capture path
  /// can call this unconditionally without its own enabled-check.
  static func record(_ data: Data, source: CaptureSource) async -> CaptureDiagnosticsInfo? {
    guard isEnabled else { return nil }

    guard
      let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else {
      NSLog("[Brixi] Save Captures: couldn't read image properties for a \(source.rawValue) capture")
      return nil
    }

    let info = CaptureDiagnosticsInfo(source: source, pixelWidth: width, pixelHeight: height, byteCount: data.count)
    NSLog("[Brixi] Capture (\(source.rawValue)): \(width)x\(height), \(data.count) bytes")

    await save(data)
    return info
  }

  /// Writes the exact captured bytes as a new Photos asset -- no
  /// re-encoding, so the saved file's resolution/quality is whatever the
  /// capture pipeline actually produced, not whatever UIImage/JPEG
  /// round-tripping would produce.
  private static func save(_ data: Data) async {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      NSLog("[Brixi] Save Captures: Photos permission not granted (\(status.rawValue))")
      return
    }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
      }
    } catch {
      NSLog("[Brixi] Save Captures: failed to save -- \(error.localizedDescription)")
    }
  }
}
