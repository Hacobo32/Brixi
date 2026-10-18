# Brixi — Pile Mode Spec (handoff to Claude Code)

_Date: 2026-10-15 · Status: approved to build, Phase 0 first · Owner: Jake_

## 1. What we're building

**Goal:** the user spreads a layer of loose bricks on a plain mat, takes one photo, and Brixi says which pieces from the set they're building are in that photo, and where.

This replaces "one piece at a time" as the main way to use the app. Single-piece scanning stays as it is.

**Pipeline (three new stages after capture):**

```
Capture (burst) → Pick sharpest → FIND each piece (crop) → NAME each crop (Brickognize) → CHECK against set list → Show + speak results
```

**Device decision:** build pile mode once and run it from either device.
- **Phone:** the reliable default.
- **Glasses:** supported, with "lean in, hold still" coaching, an automatic burst, and a blur check.

## 2. Evidence (test results, Oct 13–15)

We tested set 76157 (Wonder Woman vs Cheetah) on a blue mat, with pieces spread out and not touching. Photos were cut into pieces automatically and each cut-out was sent to `POST /predict/parts/`.

| | Glasses, standing height | Glasses, leaning in, still | Phone |
|---|---|---|---|
| Cut-outs | 116 | 132 | 99 |
| Brickognize returned an answer | 96% | 100% | 98% |
| Top score ≥ 0.80 | 58% | 69% | 89% |
| Top guess is a set part (shape-level match) | 55% | 61% | 67% |
| Hand spot check, correct | ~60% | (n/a) | ~92% (22/24) |

Not every piece in the test piles was from the set, so the "set part" row is a floor, not an accuracy score.

**Key findings:**
1. **Brickognize names pile cut-outs well.** The core idea is validated.
2. **Distance and stillness matter on glasses.** At standing height, a gold-printed 2×2 tile was confidently misread 7 times as `54200 Slope 30 1×1×2/3`. That part is *also in the set*, so the app would have said "found" for the wrong piece. Leaning in removed this error completely.
3. **Lighting decides printed and dark parts.** Printed tiles in shadow look like flat squares and get misread. In good light they're named correctly.
4. **Blur kills results.** One of the 8 "leaning in" shots was blurry. Hence the burst and sharpest-frame pick.
5. **The part-number mismatch is real** (see §6). Brickognize returns BrickLink-style IDs. Our set lists come from Rebrickable. Brickognize literally answered `30562pb059 … Set 76157` and our matcher scored it as not in the set.
6. **All test photos came from the Meta AI app, not the toolkit.** We have NOT confirmed that toolkit captures are large enough. That's Phase 0.

## 3. Phase 0 — Capture diagnostics (do this FIRST, it gates the rest)

**Why:** a field report on Gen 3 + DAT SDK 1.0 (firmware 129) shows the live stream at only **360×640 @ 24fps**. That's far too small for pile mode. We need the actual resolution of `capturePhoto` stills through the toolkit.

Build:
- [ ] Hidden developer toggle in Settings: **"Save captures"**.
- [ ] When on, every photo captured through the glasses (and the phone camera in pile mode) is saved to Photos (or Files) at **full original resolution**, with no recompression.
- [ ] Right after capture, show an on-screen overlay with the pixel dimensions, file size, and source (glasses-toolkit / phone).
- [ ] Log the same to the console.

**Gate:** Jake takes 3–4 pile photos through Brixi and sends them to Claude chat. They get re-run through the same scoring test.
- If toolkit stills are roughly ≥ 1500 px on the short side, proceed with glasses pile mode as specced.
- If they're much smaller, make pile mode phone-only for v1 and keep glasses for single-piece mode.

## 4. Phase 1 — Pile scan flow

### 4.1 Capture
- **Burst:** take 3 frames about 150 ms apart. Score each with the variance of the Laplacian on a grayscale downscale (vImage / Accelerate). Keep the sharpest. -- Done: `BlurDetector.swift` (hand-rolled, not vImage -- consistent with `PileSegmenter`'s approach, see note below). `CameraCaptureController.captureBurst()` and `PhoneCameraFrameSource.captureBurst()` both fire 3 stills ~150ms apart from a single session; wired into the pile segmentation debug screen ("Capture Burst (Glasses)" / "Capture Burst (Phone)"), which now shows each frame's score with the picked one highlighted.
- **Blur reject:** if even the best frame is below a threshold (tune from test photos), don't scan. Coach the user instead: "Hold still and lean in a little." -- **Not yet thresholded.** No real sharp-vs-blurry score data exists yet; the debug screen surfaces raw scores so the threshold can be tuned from real captures (shaky vs. steady) before this gets wired into the actual scan flow.
- **Glasses coaching** (spoken + on screen): "Lean in so the mat fills your view. Hold still." Run the burst only after a short countdown.
- **Lighting hint:** if the mean brightness of the mat region is low, say "Try more light — printed pieces need it."
- Use still capture (`capturePhoto`), **never video frames**, for pile mode.

### 4.2 Find pieces (v1: colour separation, no ML)
v1 assumes pieces are spread on a **plain, single-colour mat that contrasts with the bricks** (blue/teal tested).

Algorithm (this worked on 9 phone + 18 glasses photos):
1. Convert to HSV. Estimate the mat's colour as the dominant hue in the central region.
2. Mask "not mat": hue distance > ~22 (on a 0–255 scale) **or** low saturation.
3. Morphological open, then close (about 4 iterations each), then fill holes.
4. Connected components. Keep a component if:
   - area ≥ ~800 px (scale this with image size) -- lowered from 1500 after a real miss: see the note below.
   - it does **not** touch the image border,
   - fill ratio (area / bounding-box area) ≥ 0.2,
   - its longest side is < ~40% of image width. This drops the tray, couch, hands, and whole-scene blobs.
5. Pad each box by 35% of its longest side plus 10 px. Crop from the **full-resolution** frame.

Known failure modes:
- Glare spots on the mat
- Shadows merging neighbouring pieces
- The mat's cut-out handle hole
- Pieces cut off at the frame edge

Coach the user to avoid these: no touching pieces, avoid glare, keep the mat edges in view. Expect about 15% junk crops; the matcher tolerates them because junk rarely matches a set part.

**Milestone 1 validated** (`PileSegmenter.swift`, ported from the Python prototype, tested via a DEBUG-only "Pile Segmentation Test" screen that overlays numbered boxes and shows each crop). On a real on-device photo with pieces spread apart, 10+ of ~14 detected pieces were clean, correctly-cropped single boxes. The one remaining failure cluster was pieces genuinely touching in the pile (confirmed by inspecting the actual crop contents, not just box outlines) -- exactly the limitation already called out above, not a porting bug. A secondary, benign effect: a long piece lying at a diagonal gets an oversized axis-aligned bounding box (it has to span the full diagonal extent), inflating overlap with neighbors without being a real detection error.

**Real miss found during Milestone 6 testing: thin/branching pieces vanish entirely.** A Plant, Leaves 6x5 (dark green, in a real pile, with clear gaps around it -- not a touching-pieces case) never got a box at all. Confirmed via single-piece mode that Brickognize recognizes it instantly and confidently in isolation (auto-found), so the miss was in segmentation, not recognition. Reproduced the exact pipeline in Python against the real capture: the piece's thin, radiating-branch silhouette produces a "not mat" mask that's already fragmented by antialiasing at its branch edges before any morphology even runs (biggest raw fragment ~2900px with fill ratio 0.25, surrounded by dozens of 1-50px specks) -- 4 erosion iterations in the open step (sized to separate touching solid pieces, not to survive a piece whose own shape is inherently thin) then erodes what little mass it has down to ~250-650px, well under the 1500px minimum.

First attempt: reduce the open step to 3 iterations. Verified in Python against that photo -- rescued the plant (1583px, barely over 1500) without changing the other 5 detections. Shipped it, then a *second* real capture of the same piece failed again: the margin was only ~5%, too thin to survive normal photo-to-photo variation (lighting, exposure, exact pixel alignment) -- a difference easily explained by small, unavoidable discrepancies between this Python verification harness and the real Swift implementation it mirrors, let alone a genuinely different photo. Checked whether *fewer* iterations gave more room: no -- less erosion grows the piece's raw area back but drops its fill ratio below 0.2 instead (more of its naturally sparse branch structure survives), so iteration count alone cannot give this piece comfortable margin on both filters at once, in either direction.

**Fixed properly:** reverted the iteration change (back to 4/4, the original validated setting) and lowered the area floor from 1500px to 800px instead. Confirmed in Python against *both* real captures: the plant's biggest surviving fragment lands at 1051px and 1261px respectively -- comfortable 1.3-1.6x margin in both, not a photo-specific fluke -- and lowering the floor all the way to 600px admits no new junk components in either photo, so 800px has real headroom to spare. This also doesn't touch the morphology iterations at all, so the touching-pieces limitation (two solid pieces in true contact have no thin bridge for erosion to exploit, regardless of iteration count) is unaffected either way.

Future (not v1): replace this with a trained one-class "brick" detector (Core ML). See the licensing rules in §8.

### 4.3 Name pieces (Brickognize)
- `POST https://api.brickognize.com/predict/parts/?predict_color=true&top_k_items=50`, one crop per request, multipart field `query_image`.
- **Rate limit: 5 req/s per IP.** Throttle to about 4 req/s with a small concurrency queue. A 40-piece pile takes about 10 s; show progress ("Checking 12 of 40…").
- Retry once on network error. Skip the crop on a second failure.
- Cache results by crop hash for the session.
- Note: `/predict/parts/` is marked "legacy" in Brickognize's OpenAPI. Keep it behind one small client so we can swap endpoints.

**Done** -- `PileRecognitionBatcher.swift`: one crop at a time (a paced sequential loop already hits the ~10s/40-piece target at 4 req/s, without a separate concurrency pool's rate-limit risk), session-scoped cache keyed by a SHA-256 crop hash, one retry before giving up on a crop. `BrickognizeClient.predictParts` grew a `topK` param so pile mode can ask for `top_k_items=50` while single-piece mode keeps the server default. Wired into the debug screen ("Recognize All Crops"), which shows each crop's top guess + score and a "Checking N of M…" progress line. **Validated on-device** against a real 19-piece pile: every crop returned a plausible top guess, scores clustering 0.75-0.90 (e.g. the mesh/grille piece correctly came back "Plate, Modified 8x8 Lattice," the cylinder rod as "Support 1x6 Solid Pillar"). An earlier run looked like a total failure (every crop blank, "Checking N of N" stuck on screen) -- that was a debug-screen bug (progress never cleared) compounded by testing a pre-fix build, not a Brickognize or pacing problem; see the two small follow-up commits after this milestone's main one.

### 4.4 Check against the set list
- Load the set inventory for the selected build (existing Rebrickable data).
- For each crop, walk the top-50 items. A crop **matches** a set part if any returned ID resolves to a set part (see §6).
- Classify each crop:
  - **Found:** the top item is a set part and its score is ≥ 0.75.
  - **Maybe:** a set part appears at rank ≤ 3 with a score ≥ 0.50.
  - **Ignore:** anything else. Stay silent on these; never announce non-set guesses.
- Use `predict_color` to tie-break when the set has the same part in multiple colours. Treat colour as a hint, not a hard filter: warm room light shifted tan toward orange in phone tests.
- Count found pieces against the set's required quantities, and track what's still missing.

**Done** -- `PileMatcher.swift`: classifies one crop exactly as above (found requires the *top* item specifically at ≥0.75; maybe is any of the top 3 at ≥0.50), walking up to 3 ranked items only (the rest of the returned top-50 isn't needed once rank 3 is past, since scores only decrease from there). Color ties broken the same way single-piece mode already does. `tally(_:against:)` rolls a batch of classifications into found counts, maybe parts, and a missing list -- "missing" also accounts for quantities already found in a prior single-piece scan (`NeededPart.quantityFound`), not just this one pile scan. The BrickLink<->Rebrickable ID matching itself (§6) was already shared logic; factored the match-against-needed-parts step out of `BuildDetailViewModel` into `NeededPartMatcher.swift` so both modes use the identical path rather than two copies. Wired into the debug screen: each crop thumbnail gets a Found/Maybe badge, with a one-line summary ("N found, N maybe, N still missing") underneath, matched against whatever build is currently active (`BuildProjectStore.activeSet`) -- pile mode doesn't have its own set picker yet (that's Milestone 6).

### 4.5 Output
- **Screen:** the captured photo with boxes drawn on found pieces (and dashed boxes on "maybe" pieces), labelled with the part name. Below that, a list: found / maybe / still missing.
- **Voice:** short. "Found 6 pieces from your set. Top left: 2 by 6 tan plate…" Read the found pieces only. Offer "Say 'next' for more" only if voice input exists (§7).
- "Where is part X?": tapping a part in the missing/found list highlights its box.

**Done** -- `PileResultsView.swift`: solid green boxes on found pieces, dashed yellow on maybe, nothing on ignored (no box drawn at all, not just unlabeled -- matches "stay silent" from §4.4). Found/Maybe/Still Missing sections below, tapping a Found or Maybe row highlights its box in blue (a missing part has no box to highlight, so those rows aren't tappable). Voice is a short running count ("Found 6 pieces from your set") rather than the worked example's positional detail ("Top left: ...") -- that needs real on-screen layout analysis this doesn't attempt, and "short" was the explicit requirement; per-part detail can be added later without changing the screen's shape. Not yet wired into BuildDetailView as a real entry point (§11, Milestone 6) -- the pile segmentation debug screen presents it today (a "View Results" button, once a batch is matched) against whatever build is active, which is enough to validate the screen on real on-device data before that wiring exists.

## 5. Acceptance targets (re-use the test harness)

Use the same 4-pile test layout (blue mat, 12–25 pieces each, including gold-printed 2×2 road-sign tiles and small round 1×1 plates):

| Metric | Phone | Glasses (lean in) |
|---|---|---|
| Crops with an answer | ≥ 95% | ≥ 95% |
| Top score ≥ 0.80 | ≥ 85% | ≥ 65% |
| **False "Found"** (wrong part announced as found) | **≤ 2%** | **≤ 3%** |
| Junk crops (not a piece) | ≤ 15% | ≤ 15% |
| End-to-end scan time, 25 pieces | ≤ 12 s | ≤ 15 s |

The false "Found" rate is the most important number. The user trusts a "found" call.

## 6. Part ID matching (BrickLink vs Rebrickable): must fix

Brickognize item IDs are BrickLink-style. Rebrickable sometimes uses different IDs, especially for printed parts, stickered parts, and mould variants. Examples from our test:
- `15210pb069` (Road Sign 2×2 with gold pattern, 26 in the set): scored "not in set"
- `30562pb059` (Cylinder Quarter with TV-screen stickers, named "Set 76157" by Brickognize): scored "not in set"

Matching order:
1. If the Brickognize item's `external_sites` contains a Rebrickable URL, use the Rebrickable part ID from it.
2. Otherwise, look up the BrickLink ID with Rebrickable's API (`/api/v3/lego/parts/?bricklink_id=…`) and cache the result locally.
3. Otherwise, fall back to a **shape-level match**: strip print/sticker suffixes (`pb…`, `pr…`) and `c01` assembly suffixes from both sides and compare base IDs.

Re-scoring our test data at shape level against BrickLink's inventory raised set matches on glasses from 55% to 61% and on phone from 58% to 67%.

## 7. Glasses session and audio rules (from the field report + Meta docs)

- Upgrade DAT SDK **0.9.0 → 1.0** -- done (bumped to 1.0.1, the current latest; changelog checked line by line, nothing it renamed/removed is used in this codebase).
- **Audio choice -- decided: output only.** Speak through A2DP; no mic, no HFP, no voice commands in v1. This sidesteps the HFP bug below entirely (nothing here ever configures or releases HFP), gets better speech quality, and avoids the Gen 3 "device unavailable" failure mode since that's specifically triggered by releasing/re-setting-up HFP. Voice commands are deferred, not ruled out -- revisit if/when there's a real need for voice input, at which point the HFP sequencing rule below still applies.
  - Deferred for later (not applicable to v1): with voice commands, configure and start HFP **before** starting the camera stream, wait for the route to settle, then start the stream. Keep HFP on across sessions. (Meta docs: starting the stream before HFP is ready "can cause the audio route to fail silently"; HFP and A2DP are mutually exclusive.)
- **Known Gen 3 failure (field report, unconfirmed by Meta):** releasing and re-setting up HFP can cause "device unavailable" for about 7 minutes while the glasses still report connected. Only power-cycling the glasses clears it.
  - Settings → Glasses troubleshooting: after 2 consecutive "device unavailable" errors, stop retrying and tell the user: "Turn your glasses off and on again."
- This may also explain the earlier "can't link glasses / stream fails" issue, if mic and stream were starting at the same time.

## 8. Licensing guardrails (shipped code)

Brixi will be commercial (freemium), so:
- ✅ OK to ship: Apple Vision / Core ML, our own colour-separation finder, our own photos, the CC BY Gdańsk detection dataset (with attribution), and Apache/MIT-licensed models.
- ❌ Do NOT ship:
  - Ultralytics YOLO code or weights (AGPL-3.0 unless we buy an enterprise license)
  - LegoSorter weights or code (no license)
  - CC BY-NC datasets (e.g. the Gdańsk single-brick photo sets)
  - CC BY-SA synthetic sets (B200)
- Any of the above is fine for private experiments on the Mac.

## 9. Business notes that affect the build

- Pile mode is the planned **Pro feature**: single-piece stays free, pile scans are capped for free users (Brickit caps free users at 3 scans/day). Pile mode is what multiplies Brickognize calls, so the cap also protects API cost.
- Optional later: a "buy missing pieces" link (BrickLink / Brick Owl) for parts still missing after a scan.

## 10. Open items

- ~~**Phase 0 result:** toolkit still resolution (gates glasses pile mode).~~ Resolved: 1440x1080 (1080px short side) on all 5 captures tested -- below the 1500px target but not drastically, and recognition accuracy on real toolkit-resolution crops held up well (90%+ confident matches, ~100% correct item IDs by eye across 20 samples). Proceeding with glasses pile mode as specced rather than falling back to phone-only.
- ~~**Audio decision:** voice commands yes/no (§7).~~ Resolved: output only. No HFP, no voice commands in v1.
- **Batched email to Piotr (Brickognize), not yet sent:**
  1. Is multi-object detection coming in the new (non-legacy) API?
  2. Recommended crop padding and minimum crop size?
  3. Commercial use in a paid/freemium App Store app?
  4. Volume pricing and rate limits for pile mode (many calls per scan)?
  5. Image storage/retention, for our privacy notice.
- **UI polish, deferred (explicitly "not for now"):**
  - Better icons for the four scan buttons (Scan a Piece/Pile × Phone/Glasses) -- currently generic SF Symbols (`camera`, `eyeglasses`, `square.grid.3x3`, `square.grid.3x3.fill`), not purpose-made.
  - Nicer spoken voice for pile results -- currently `AVSpeechSynthesizer`'s plain system default; Jake confirmed it works but isn't a fan of the voice itself.

## 11. Suggested build order

1. ~~Phase 0 diagnostics → Jake sends 3–4 photos → re-test in chat.~~ Done -- see §10.
2. ~~SDK 1.0 upgrade + audio rules (§7).~~ Done -- see §7, §10.
3. ~~Part ID matching (§6). Unit-test it with `15210pb069`, `30562pb059`, `4460bpb002`, `2429c01`.~~ Done -- `PartIDResolver.swift`, stripping logic verified against all four worked examples; live-confirmed on real scans of both the Road Sign (`15210pb069`) and Cylinder Quarter (`30562pb059`) pieces.
4. Phone pile mode end to end (§4) with a debug screen that shows the crops.
   - ~~Find pieces (§4.2), validated against real on-device captures.~~ Done -- see §4.2's own note. Clean single-box-per-piece results once pieces have real gaps between them; touching pieces still merge into one box, matching the spec's own known limitation (§4.2's "no touching pieces" coaching note), not a bug in the port.
   - ~~Capture: burst + sharpest-frame pick (§4.1).~~ Done -- see §4.1's own note. Blur-reject threshold still open, pending real tuning data.
   - ~~Name pieces (§4.3, batched Brickognize).~~ Done and validated on-device -- see §4.3's own note.
   - ~~Check against set list (§4.4).~~ Done and validated on-device -- see §4.4's own note. 6 found / 0 maybe / 111 still missing on a 14-piece pile against set 76157, with no obvious false "Found" (a 0.91-confidence "Brick 2x2 Corner" correctly got no badge at all, since it isn't in this set's inventory).
   - ~~Output UI (§4.5).~~ Done and validated on-device -- see §4.5's own note. Box overlay, found list, and tap-to-highlight (tapping a row turns its box blue, with a viewfinder icon next to the row) all confirmed working against a real 15-piece pile.
5. Glasses pile mode: burst, blur check, coaching. (Burst capture itself already shared between phone and glasses as of §4.1 -- this item is now mainly the spoken coaching + countdown + lighting hint.)
6. ~~Wire pile mode into BuildDetailView as a real entry point.~~ Done -- "Scan a Pile (Phone)" / "Scan a Pile (Glasses)" buttons on the build screen, with a coaching caption ("Spread pieces out on a plain mat with gaps between them"), a live "Checking N of M..." progress row, and PileResultsView presented on completion. Found counts are persisted (BuildProjectStore, capped at each part's remaining quantityNeeded) as soon as the scan finishes, before the results sheet is even shown, so progress isn't lost if it's dismissed without reading. Replaces the DEBUG-only debug-screen workaround as pile mode's real path -- the debug screen stays, for segmentation-only troubleshooting independent of a real build. Needs an on-device run to confirm the end-to-end flow (not just its individual pieces, already validated separately) and that persisted quantities actually show up in the Needed Parts list afterward.
7. Acceptance run (§5) with the same 4-pile layout.

**Not in the original plan, surfaced by live single-piece testing along the way** (both apply to pile mode too, since it reuses this same matching path):
- Auto-find no longer hard-gates on Brickognize's predicted color (confirmed ~5% accurate against ~90%+ item-ID accuracy on 20 real pile crops) -- color is now only consulted to disambiguate when a part shape is needed in more than one color. See `BuildDetailViewModel.evaluate()`.
- A second, higher confidence threshold (0.85, separate from `RecognitionService`'s base 0.7 "is this recognized at all" gate) controls whether a match is trusted silently vs. asking for a yes/no -- added after a real misidentification (a Road Sign piece read as a Tile 1x1) cleared 0.7 but was simply wrong, a case color couldn't have caught either.
