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
- **Burst:** take 3 frames about 150 ms apart. Score each with the variance of the Laplacian on a grayscale downscale (vImage / Accelerate). Keep the sharpest.
- **Blur reject:** if even the best frame is below a threshold (tune from test photos), don't scan. Coach the user instead: "Hold still and lean in a little."
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
   - area ≥ ~1500 px (scale this with image size),
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

Future (not v1): replace this with a trained one-class "brick" detector (Core ML). See the licensing rules in §8.

### 4.3 Name pieces (Brickognize)
- `POST https://api.brickognize.com/predict/parts/?predict_color=true&top_k_items=50`, one crop per request, multipart field `query_image`.
- **Rate limit: 5 req/s per IP.** Throttle to about 4 req/s with a small concurrency queue. A 40-piece pile takes about 10 s; show progress ("Checking 12 of 40…").
- Retry once on network error. Skip the crop on a second failure.
- Cache results by crop hash for the session.
- Note: `/predict/parts/` is marked "legacy" in Brickognize's OpenAPI. Keep it behind one small client so we can swap endpoints.

### 4.4 Check against the set list
- Load the set inventory for the selected build (existing Rebrickable data).
- For each crop, walk the top-50 items. A crop **matches** a set part if any returned ID resolves to a set part (see §6).
- Classify each crop:
  - **Found:** the top item is a set part and its score is ≥ 0.75.
  - **Maybe:** a set part appears at rank ≤ 3 with a score ≥ 0.50.
  - **Ignore:** anything else. Stay silent on these; never announce non-set guesses.
- Use `predict_color` to tie-break when the set has the same part in multiple colours. Treat colour as a hint, not a hard filter: warm room light shifted tan toward orange in phone tests.
- Count found pieces against the set's required quantities, and track what's still missing.

### 4.5 Output
- **Screen:** the captured photo with boxes drawn on found pieces (and dashed boxes on "maybe" pieces), labelled with the part name. Below that, a list: found / maybe / still missing.
- **Voice:** short. "Found 6 pieces from your set. Top left: 2 by 6 tan plate…" Read the found pieces only. Offer "Say 'next' for more" only if voice input exists (§7).
- "Where is part X?": tapping a part in the missing/found list highlights its box.

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

- Upgrade DAT SDK **0.9.0 → 1.0** (read the changelog first).
- **Audio choice (Jake to decide):**
  - **Output only (recommended for v1):** speak through A2DP and don't use the mic or HFP. This avoids the HFP bug below entirely, and speech quality is better.
  - **With voice commands:** configure and start HFP **before** starting the camera stream, wait for the route to settle, then start the stream. Keep HFP on across sessions. (Meta docs: starting the stream before HFP is ready "can cause the audio route to fail silently"; HFP and A2DP are mutually exclusive.)
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

- **Phase 0 result:** toolkit still resolution (gates glasses pile mode).
- **Audio decision:** voice commands yes/no (§7).
- **Batched email to Piotr (Brickognize), not yet sent:**
  1. Is multi-object detection coming in the new (non-legacy) API?
  2. Recommended crop padding and minimum crop size?
  3. Commercial use in a paid/freemium App Store app?
  4. Volume pricing and rate limits for pile mode (many calls per scan)?
  5. Image storage/retention, for our privacy notice.

## 11. Suggested build order

1. Phase 0 diagnostics → Jake sends 3–4 photos → re-test in chat.
2. SDK 1.0 upgrade + audio rules (§7).
3. Part ID matching (§6). Unit-test it with `15210pb069`, `30562pb059`, `4460bpb002`, `2429c01`.
4. Phone pile mode end to end (§4) with a debug screen that shows the crops.
5. Glasses pile mode: burst, blur check, coaching.
6. Acceptance run (§5) with the same 4-pile layout.
