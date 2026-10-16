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
  /// Confident enough to trust silently -- deliberately higher than
  /// RecognitionService.defaultConfidenceThreshold (0.7), which only
  /// gates whether an outcome counts as "recognized" at all. A piece can
  /// clear 0.7 and still be the wrong shape: a small Road Sign Clip-on
  /// 2x2 piece (gold diamond print) was misread as a Tile 1x1 with
  /// Groove and cleared 0.7, live. Color can't backstop that kind of
  /// error -- it was the wrong shape, not the wrong color of the right
  /// one -- so the fix is asking rather than trusting in this band, not
  /// leaning on a signal already shown to be unreliable.
  /// No rigorous derivation behind this exact number; a reasonable
  /// starting point given what's been seen in testing so far, not a
  /// tuned optimum.
  private static let autoFindConfidenceThreshold = 0.85

  /// Outcome of one "Scan for Parts" attempt, checked against this build's
  /// needed-parts list.
  enum ScanResult {
    /// A high-confidence item-ID match (see autoFindConfidenceThreshold),
    /// recorded automatically. Color is not part of this gate -- see
    /// docs/pile-mode-spec.md §4.4 and matchNeededParts(for:):
    /// Brickognize's predicted color is far less reliable than its item
    /// identification (confirmed empirically -- see the Phase 0 testing
    /// notes), so requiring it to match before trusting an otherwise-
    /// confident recognition meant almost nothing ever auto-found, even
    /// when the identification was correct.
    case autoFound(NeededPart)
    /// Any of: the item-match confidence cleared RecognitionService's base
    /// threshold but not autoFindConfidenceThreshold (confirmed live: a
    /// small Road Sign piece misread as a Tile 1x1 cleared the base 0.7
    /// gate but was simply wrong -- color wouldn't have caught that
    /// either, since it was the wrong shape, not the wrong color of the
    /// right shape); the matched part shape is needed in more than one
    /// color and color is the only (weak) signal that can tell them
    /// apart; or the outcome itself was low-confidence. Needs a human
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
  /// Set after every capture when the "Save Captures" debug toggle
  /// (Settings) is on -- see CaptureDiagnostics. nil the rest of the time.
  @Published private(set) var lastCaptureDiagnostics: CaptureDiagnosticsInfo?

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
  private let partIDResolver: PartIDResolver

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
    self.partIDResolver = PartIDResolver(client: client)
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
        lastCaptureDiagnostics = await CaptureDiagnostics.record(imageData, source: .glasses)
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
      lastCaptureDiagnostics = await CaptureDiagnostics.record(imageData, source: .phone)
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
      scanResult = await evaluate(outcome)
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

  private func evaluate(_ outcome: RecognitionOutcome) async -> ScanResult {
    switch outcome {
    case .recognized(let piece):
      // .sticker, not just .part: Brickognize classifies a printed/decorated
      // piece's own part number under .sticker (e.g. a tile with a sticker
      // design), and RecognitionService.resolve already treats the two the
      // same for catalog lookup. Gating on .part alone routed every
      // genuinely-needed decorated piece straight to "not in set" without
      // ever checking the needed-parts list.
      guard piece.item.type == .part || piece.item.type == .sticker else {
        return .notInSet(recognizedName: piece.item.name)
      }
      let matches = await matchNeededParts(for: piece.item)
      guard let firstMatch = matches.first else {
        return .notInSet(recognizedName: piece.item.name)
      }
      guard matches.count == 1 else {
        // This part shape is needed in more than one color -- color is
        // the only signal that can tell them apart, so ask rather than
        // silently pick one, even though the prediction itself is weak.
        // Prefer whichever color variant the prediction actually landed
        // on, if it landed on one of the ones this build needs at all.
        let bestGuess = matches.first { $0.colorId == piece.colorId } ?? firstMatch
        return .needsConfirmation(bestGuess, recognizedName: piece.item.name)
      }
      guard piece.confidence >= Self.autoFindConfidenceThreshold else {
        // Still a "recognized" outcome (cleared RecognitionService's base
        // gate), just not confident enough to trust without a look --
        // this band is where real misidentifications on small/decorated
        // pieces showed up in testing.
        return .needsConfirmation(firstMatch, recognizedName: piece.item.name)
      }
      markFound(firstMatch, delta: 1)
      return .autoFound(firstMatch)

    case .lowConfidence(let candidates):
      for candidate in candidates where candidate.type == .part || candidate.type == .sticker {
        let matches = await matchNeededParts(for: candidate)
        if let match = matches.first {
          return .needsConfirmation(match, recognizedName: candidate.name)
        }
      }
      return .notRecognized

    case .notFound:
      return .notRecognized
    }
  }

  /// Matches a recognized item against this build's needed-parts list.
  /// Tries each of PartIDResolver's ID candidates (raw ID, shape-stripped
  /// base ID, live Rebrickable lookup -- see PartIDResolver, per
  /// docs/pile-mode-spec.md §6) against the catalog's part family in
  /// order, and returns every needed-parts row the first matching
  /// candidate hits -- more than one means this part shape is needed in
  /// multiple colors, which the caller uses to decide whether color needs
  /// asking about.
  private func matchNeededParts(for item: BrickognizeItem) async -> [NeededPart] {
    guard let catalog, let build else { return [] }
    for candidate in await partIDResolver.candidates(for: item) {
      let family = catalog.partFamily(partNum: candidate)
      let matches = build.parts.filter { family.contains($0.partNum) }
      if !matches.isEmpty {
        return matches
      }
    }
    return []
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
          ?? catalog?.elementImageURL(partNum: entry.part.partNum)
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
