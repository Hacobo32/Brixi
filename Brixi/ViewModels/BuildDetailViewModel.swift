//
// BuildDetailViewModel.swift
//
// Fetches (or loads cached) needed-parts data for one set and exposes it as
// a checklist backed by BuildProjectStore. The live Rebrickable fetch only
// ever runs once per set -- after that, the user's found/not-found progress
// lives entirely in BuildProjectStore, not refetched.
//

import Foundation

@MainActor
final class BuildDetailViewModel: ObservableObject {
  /// Outcome of one "Scan for Parts" attempt, checked against this build's
  /// needed-parts list.
  enum ScanResult {
    /// A confident match on both part family and exact color -- recorded
    /// automatically.
    case autoFound(NeededPart)
    /// A match on part family, but the predicted color didn't match (color
    /// prediction is the weaker signal -- see the empirical testing
    /// findings) or the item-match confidence itself was low. Needs a human
    /// yes/no.
    case needsConfirmation(NeededPart, recognizedName: String)
    /// Recognized something, but it isn't on this set's needed-parts list.
    case notInSet(recognizedName: String)
    /// Nothing recognizable in the frame at all.
    case notRecognized
  }

  @Published private(set) var build: BuildProject?
  @Published var isLoading = false
  @Published var isScanning = false
  @Published var errorMessage: String?
  @Published var scanResult: ScanResult?

  let setName: String

  /// Owned here (not just constructed on demand) so PhoneCameraCaptureView
  /// can bind its live preview to the same session this view model will
  /// capture from.
  let phoneCameraSource = PhoneCameraFrameSource()

  private let setNum: String
  private let setImageURL: URL?
  private let store: BuildProjectStore
  private let client: RebrickableClient?
  private let catalog: CatalogDatabase?
  private let glassesFrameSource = GlassesFrameSource()
  private let recognitionService: RecognitionService?

  init(
    setNum: String,
    setName: String,
    setImageURL: URL?,
    store: BuildProjectStore,
    client: RebrickableClient?,
    catalog: CatalogDatabase?
  ) {
    self.setNum = setNum
    self.setName = setName
    self.setImageURL = setImageURL
    self.store = store
    self.client = client
    self.catalog = catalog
    self.recognitionService = catalog.map { RecognitionService(catalog: $0) }
    self.build = store.build(setNum: setNum)
  }

  func loadIfNeeded() {
    guard build == nil else { return }
    guard let client else {
      errorMessage = "No Rebrickable API key configured -- can't fetch this set's parts."
      return
    }

    isLoading = true
    errorMessage = nil
    Task {
      do {
        let entries = try await client.fetchParts(setNum: setNum)
        let parts = Self.aggregate(entries, catalog: catalog)
        let newBuild = BuildProject(setNum: setNum, setName: setName, setImageURL: setImageURL, parts: parts)
        store.upsert(newBuild)
        build = newBuild
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  func markFound(_ part: NeededPart, delta: Int) {
    store.markFound(setNum: setNum, partId: part.id, delta: delta)
    build = store.build(setNum: setNum)
  }

  /// Captures one photo from the glasses (or a Mock Device Kit feed) and
  /// runs it through the shared recognition/match path. Glasses are an
  /// additional path alongside the phone camera, not a requirement -- see
  /// handlePhoneCameraCapture(_:) for the phone-first default.
  func scanWithGlasses() {
    isScanning = true
    errorMessage = nil
    scanResult = nil
    Task {
      do {
        let imageData = try await glassesFrameSource.captureOneFrame()
        await runRecognition(on: imageData)
      } catch {
        errorMessage = error.localizedDescription
      }
      isScanning = false
    }
  }

  /// Called by PhoneCameraCaptureView once it has a captured frame -- that
  /// view owns the live preview/shutter UI, so by the time this runs the
  /// frame already exists; this just runs it through the same
  /// recognition/match path scanWithGlasses() uses.
  func handlePhoneCameraCapture(_ imageData: Data) {
    isScanning = true
    errorMessage = nil
    scanResult = nil
    Task {
      await runRecognition(on: imageData)
      isScanning = false
    }
  }

  private func runRecognition(on imageData: Data) async {
    guard let recognitionService else {
      errorMessage = "Recognition isn't available -- the local catalog failed to load."
      return
    }
    do {
      let outcome = try await recognitionService.recognize(imageData: imageData)
      scanResult = evaluate(outcome)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func confirmScanResult() {
    guard case .needsConfirmation(let part, _) = scanResult else { return }
    markFound(part, delta: 1)
    scanResult = nil
  }

  func dismissScanResult() {
    scanResult = nil
  }

  private func evaluate(_ outcome: RecognitionOutcome) -> ScanResult {
    switch outcome {
    case .recognized(let piece):
      guard piece.item.type == .part, let match = matchNeededPart(partNum: piece.item.id) else {
        return .notInSet(recognizedName: piece.item.name)
      }
      guard piece.colorId == match.colorId else {
        return .needsConfirmation(match, recognizedName: piece.item.name)
      }
      markFound(match, delta: 1)
      return .autoFound(match)

    case .lowConfidence(let candidates):
      for candidate in candidates where candidate.type == .part {
        if let match = matchNeededPart(partNum: candidate.id) {
          return .needsConfirmation(match, recognizedName: candidate.name)
        }
      }
      return .notRecognized

    case .notFound:
      return .notRecognized
    }
  }

  /// Matches by part family (see CatalogDatabase.partFamily), not exact
  /// SKU -- a recognized print/mold variant should still hit the needed
  /// line for its base part.
  private func matchNeededPart(partNum: String) -> NeededPart? {
    guard let catalog, let build else { return nil }
    let family = catalog.partFamily(partNum: partNum)
    return build.parts.first { family.contains($0.partNum) }
  }

  /// Collapses Rebrickable's per-line-item response into one entry per
  /// part+color, excluding spares from the quantity needed to actually
  /// complete the set.
  private static func aggregate(_ entries: [RebrickablePartEntry], catalog: CatalogDatabase?) -> [NeededPart] {
    var byKey: [String: NeededPart] = [:]
    for entry in entries where !entry.isSpare {
      let key = "\(entry.part.partNum)-\(entry.color.id)"
      if let existing = byKey[key] {
        byKey[key] = NeededPart(
          partNum: existing.partNum,
          colorId: existing.colorId,
          name: existing.name,
          colorName: existing.colorName,
          imageURL: existing.imageURL,
          quantityNeeded: existing.quantityNeeded + entry.quantity,
          quantityFound: 0
        )
      } else {
        let imageURL = catalog?.elementImageURL(partNum: entry.part.partNum, colorId: entry.color.id)
          ?? entry.part.partImgURL
        byKey[key] = NeededPart(
          partNum: entry.part.partNum,
          colorId: entry.color.id,
          name: entry.part.name,
          colorName: entry.color.name,
          imageURL: imageURL,
          quantityNeeded: entry.quantity,
          quantityFound: 0
        )
      }
    }
    return byKey.values.sorted { $0.name < $1.name }
  }
}
