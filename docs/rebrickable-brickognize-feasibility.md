# Data & Recognition Feasibility: Rebrickable + Brickognize

Status: research complete, no implementation yet. Written up on the
`claude/rebrickable-api-feasibility-4d3krq` branch.

## Question

Brixi pairs an iOS app with Meta Ray-Ban smart glasses to identify LEGO
pieces hands-free while sorting a bin (one piece at a time from the live
camera feed, not a whole pile photographed on a table like existing apps).
That requires two things: a catalog of LEGO parts/sets/minifigs to look
data up in, and a way to turn a camera frame into "this is part X." This
doc covers feasibility for both, and whether building directly against
official sources beats going through a third-party aggregator.

**Verdict: yes, feasible, build directly on both official sources.** No
third-party catalog API adds anything Rebrickable doesn't already provide
for free, and Brickognize (an independent, actively maintained recognition
API) plugs into Rebrickable's ID scheme with no translation layer needed.

## Part 1: Catalog data — Rebrickable

Rebrickable offers the same catalog two ways: downloadable bulk CSV dumps
(refreshed periodically, no rate limit, what we analyzed here) and a live
REST API (api key, historically ~1 req/sec) for anything not in the static
dump. These aren't competing options — they're the same source used for
different access patterns.

### Schema reviewed (11 of 12 tables, ~340K rows / ~15MB as CSV)

| table | rows | role |
|---|---:|---|
| `sets` | 28,166 | `set_num` PK, name, year, `theme_id`, num_parts, img_url |
| `themes` | 496 | `id` PK, name, `parent_id` self-reference |
| `minifigs` | 17,162 | `fig_num` PK, name, num_parts, img_url |
| `parts` | 64,357 | `part_num` PK, name, `part_cat_id`, material |
| `part_categories` | 76 | `id` PK, name (includes category 58 = Stickers) |
| `colors` | 275 | `id` PK, name, rgb, is_trans |
| `elements` | 113,854 | `element_id` PK → `(part_num, color_id, design_id)` — the join that resolves part+color images without storing a URL per row |
| `part_relationships` | 37,243 | `(rel_type, child_part_num, parent_part_num)` — collapses print/mold variants; `P` = print/pattern variant, `R` = alternate/interchangeable mold |
| `inventories` | 47,263 | `id` PK, version, `set_num` — one row per set's inventory version |
| `inventory_sets` | 5,213 | sets that contain other sets |
| `inventory_minifigs` | 25,740 | which minifigs a set's inventory contains |

**Resolved:** minifigs do have their own decomposable parts list, the same
way a set does. `inventories.set_num` is polymorphic -- most rows hold a
real `set_num`, but a subset (exactly 17,162 rows, matching `minifigs.csv`
row for row) instead hold a `fig_num` (confirmed: inventory `48649` has
`set_num = "fig-000001"`, which is "Toy Store Employee" in `minifigs.csv`).
Discovered by building the schema with a strict FK from
`inventories.set_num` to `sets.set_num` and seeing exactly 17,162 violations
-- the schema in `data/schema.sql` reflects this as an unconstrained column
with a comment, not a hard FK, since SQLite can't express a conditional
reference to either table.

### The big table: `inventory_parts` (not bundled)

1,551,673 rows / 132MB — larger than all 11 other tables combined.
Confirmed schema: `inventory_id, part_num, color_id, quantity, is_spare,
img_url`.

- Distribution of parts-per-set: min 1, median 5, mean 39.9, max 1,566.
  Heavily right-skewed — half of all sets have 5 or fewer line items.
- The `img_url` column is the single biggest contributor to file size
  (~100 chars/row) and is redundant: most rows resolve to
  `.../parts/elements/{element_id}.jpg`, which is exactly the
  `part_num + color_id → element_id` join already in `elements.csv`.
  Dropping this column and resolving images via that join cuts the
  effective data size roughly in half, with a fallback to an LDraw-rendered
  placeholder for parts with no photographed element.
- Because even the largest single set's part list (~1,566 rows) is a
  trivial payload, there's no benefit to bundling this table ahead of time.
  **Fetch it per-set, on demand**, whether from Rebrickable's live API or a
  synced backend slice.

### Architecture

- **Bundle locally** (seed SQLite shipped in the app, refreshed
  periodically): `sets`, `themes`, `minifigs`, `parts`, `part_categories`,
  `colors`, `elements`, `part_relationships`, `inventories`,
  `inventory_sets`, `inventory_minifigs`. ~15MB raw, smaller once indexed.
- **Fetch per-set, live:** `inventory_parts`, resolving images through the
  local `elements` join instead of storing per-row URLs.
- **Schema and build script exist:** `data/schema.sql` (DDL for the 11
  bundled tables) and `data/build_catalog_db.py` (loads a directory of
  Rebrickable CSVs into a SQLite file matching that schema). Validated
  end-to-end against the real CSVs -- all 11 tables load with row counts
  matching the source files exactly, and `PRAGMA foreign_key_check` comes
  back clean. Output is ~27MB for the current dataset. Not yet wired into
  the Xcode app target or scheduled for periodic refresh -- this is the
  one-shot build tool, not a running sync job yet.
- **Backend: not needed for v1.** The repo currently has zero backend
  code — just the Meta Wearables DAT pairing scaffold. Default to calling
  Rebrickable's live API directly from the client with your own API key for
  anything not bundled. Graduate to a thin backend (sync job + proxy/cache)
  only once usage scales past what a single client-side API key comfortably
  supports, or attribution/licensing needs centralizing.

### Licensing — reviewed, permissive

Checked against `rebrickable.com/terms/` and `rebrickable.com/downloads/`
(via search-engine-extracted excerpts, since direct fetch of the site is
blocked in this sandbox -- worth a firsthand skim, but the phrasing reads
as verbatim quotes, not paraphrase):

- **CSV database downloads:** usable for **any purpose, including
  commercial**, provided you acknowledge Rebrickable as your data source.
  Automated re-downloading is fine at up to once/day; scraping the actual
  website pages (separate from the CSV dumps) is explicitly banned.
- **Live API:** same — any purpose including commercial, attribution
  "highly appreciated" (a request, not a hard requirement).
- This is more permissive than initially assumed (a stricter
  non-commercial default was the working assumption prior to review).
  Practical takeaway: credit Rebrickable somewhere in the app (e.g. an
  About/Credits screen) and this gate is closed.

## Part 2: Camera recognition — Brickognize

Confirmed camera-based recognition is a planned feature, not optional — it's
the core interaction loop ("point at a piece while sorting a bin"), so this
is arguably higher-risk than the catalog work above, not an afterthought.

### What it is

Independent recognition API (not affiliated with LEGO or Rebrickable),
identifies LEGO parts/sets/minifigs/stickers from photos. Built and run by
one developer, Piotr Rybak. Confirmed directly via the OpenAPI spec
(`https://api.brickognize.com/openapi.json`) and direct email correspondence
with the maintainer (see below) — not secondhand summaries.

### API shape (from the OpenAPI spec)

- `POST /predict/`, `/predict/parts/`, `/predict/sets/`, `/predict/figs/` —
  multipart form, one or more `query_image` files (multiple angles improve
  accuracy). Tunable via `top_k_items`, `min_similarity_items`, and for
  parts `predict_color` + `top_k_colors`/`min_similarity_colors`.
- `GET /health/` — public uptime check.
- `POST /feedback/`, `/feedback/color/` — report whether a prediction was
  correct, keyed to the response's `listing_id`.
- Response includes a **bounding box** (pixel coordinates + confidence) —
  not just "what," but "where in the frame," which maps directly onto an
  AR-style overlay in the glasses' field of view.
- **No authentication in the spec** — no API key, no bearer token.

### The key integration finding: IDs match Rebrickable's exactly

A returned part is `{id: "3001", name: "Brick 2 x 4", type: "part", ...}` —
`3001` is a real Rebrickable `part_num`. A returned color is `{id: "4",
name: "Red"}` — `4` is Rebrickable's actual color ID. **No ID-mapping layer
needed** — a Brickognize result joins straight into the local
Rebrickable-derived `parts`/`colors`/`sets`/`minifigs` tables from Part 1 by
primary key. The `sticker` type Brickognize returns (not modeled explicitly
in Part 1) resolves the same way, via `part_categories.id = 58` (Stickers).

### Roadmap and rate limits — confirmed directly with the maintainer

All `/predict/` endpoints are marked `"deprecated": true` and tagged
`search (legacy)` in the spec, with a note that a replacement is coming.
Emailed Piotr Rybak directly (Aug 25–26, 2026) rather than guess at the
implication:

- The legacy tag reflects a **paid v2 in development to cover costs**, not
  a project winding down. No exact date, but "at least a few months" out.
- **At least a further multi-month grace period** to migrate once v2 ships.
- **Current API: free, no usage quota, 5 requests/second per IP.** Confirmed
  fine for "one recognition call every few seconds" during a sorting
  session.
- Images sent to the API **may be stored and used to improve the
  recognition model** — worth disclosing in Brixi's own privacy policy,
  especially given a live glasses camera feed can incidentally capture more
  than the target piece (surroundings, bystanders). Consider cropping
  tightly to the recognized item before sending, if the flow allows it.

### Architecture consequence

The 5 req/sec limit is **per IP address**. Routing recognition calls through
a shared backend would pool every user's traffic onto one IP and create a
self-inflicted bottleneck. **Call Brickognize directly from the iOS
client**, not proxied through any backend — each user's device gets its own
independent rate budget, which scales per-user for free. (This is
independent of the Part 1 decision to optionally add a backend later for
the catalog/`inventory_parts` sync — the two concerns don't need the same
answer.)

## Appendix: empirical testing against the live API (Sept 2026)

Manual testing against the live `/predict/parts/` endpoint with real LEGO
pieces, to validate the recognition assumption before further build-out.
Small, informal sample (~20 LEGO photos) — sufficient to see a qualitative
pattern, not a statistically rigorous benchmark.

### Method notes

- HEIC (the default iPhone photo format) is **not accepted** — the API
  returns `{"message":"Unsupported file format: application/octet-stream"}`.
  Converting to JPEG (`sips -s format jpeg`) before upload is a required
  pipeline step, not optional.
- Photo orientation was checked and confirmed correct (not sideways) after
  conversion — ruled out as a confound in the results below.
- Two separate confidence signals matter: `bounding_box.score` (confidence
  something was localized in the frame) and `items[].score` (confidence in
  the specific part-ID match). The default `min_similarity_items=0.5`
  filters out low-confidence item matches entirely — re-running with
  `min_similarity_items=0` surfaces what the model saw underneath a filtered
  "no items found" response.

### Results

| scenario | bounding_box score | top item match | item score | verdict |
|---|---:|---|---:|---|
| single distinctive piece (web-effect weapon) | 0.78 | Weapon Web Effect (36083) | 0.89 | correct (confirmed) |
| single distinctive piece (energy burst shield) | 0.79 | Power Burst Shield (35032e) | 0.86 | plausible, strong |
| cluttered pile, dominant feature missed | 0.65 | Large Figure Armor Chest (27167) | 0.86 | incorrect — confident but wrong |
| single decorated minifig torso | 0.85–0.90 | various decorated torsos (wrong exact print) | 0.26–0.38 | category correct, exact SKU wrong |
| cluttered Bionicle/Hero Factory pile | 0.77–0.85 | Bionicle / Hero Factory / Energy Effect parts | 0.22–0.30 | category correct, exact SKU wrong |
| small accessory in a pile | 0.72 | Minifigure Utensil candidates | 0.31–0.47 | category correct, exact SKU unconfirmed |
| ~15 unrelated non-LEGO images (photos, wallpapers) | 0.0 | none | 0.0 | correct rejection — no false positives |

### Key findings

1. **Object localization is reliable, even in cluttered multi-piece
   scenes.** High `bounding_box.score` values showed up consistently,
   including on frames with a dozen-plus overlapping pieces. This is not
   the bottleneck.
2. **Exact-SKU classification is reliable for distinctive, simple-shaped,
   single-material pieces** (weapon accessories, energy-effect pieces,
   wedges) — these produced a single confident (>0.85) top match that
   matched the photographed piece.
3. **Exact-SKU classification is unreliable for richly decorated/printed
   pieces and niche constraction-theme parts** (minifig torsos with unique
   prints, Bionicle/Hero Factory parts). In these cases the model correctly
   identifies the *category* (it knows it's looking at a decorated torso,
   or a Bionicle part) but spreads confidence thinly (0.2–0.4) across
   several plausible neighbors instead of landing on one clear, correct
   answer. This tracks with the earlier `part_relationships.csv` finding
   that the catalog contains large numbers of near-identical print/mold
   variants.
4. **No false positives on genuinely non-LEGO images** — random photos and
   wallpapers correctly returned empty results, at the default threshold.
5. **Run-to-run stability isn't perfect on color variants.** Two identical
   repeat calls on the same file once returned two different (but
   same-name) color-suffixed part IDs with an otherwise near-identical
   score — the model can be ambiguous among close color variants of the
   same physical mold.

### Implication for Brixi's design

- Treat "found a piece" and "identified exactly which piece" as two
  separate, independently-reliable-or-not product moments. The former
  supports a confident bounding-box/AR overlay; the latter does not,
  uniformly.
- Plain, common pieces — the bulk of a typical sorting bin — look like a
  reasonable bet for silent, hands-free auto-identification.
- Decorated minifig parts and niche/constraction pieces need a fallback:
  surface the top few candidates (`top_k_items`) for the user to
  confirm/pick, rather than trusting a single top match.
- When joining a Brickognize result to the local Rebrickable-derived
  catalog, resolve to the base part family rather than trusting an exact
  color-suffixed variant ID, given the observed run-to-run instability.
- A larger, structured trial under real bin-sorting conditions (not a
  one-off manual sample) is worth running before committing to a specific
  auto-ID-vs-confirm-shortlist UX split.

### Brickognize terms of service — reviewed, gap identified

Checked against `brickognize.com/terms-of-service/` (same caveat as above
-- excerpts via search, not a direct fetch):

- The published terms are generic templated website-terms boilerplate:
  non-affiliation with LEGO/BrickLink/BrickOwl/Rebrickable/Brickset, no
  accuracy guarantees, standard liability disclaimers, and terms can
  change without notice. It's written about "materials on the website,"
  **not about API usage rights specifically** -- it doesn't explicitly
  address embedding the recognition API inside a third-party commercial
  app either way.
- The more specific, more useful signal is the direct maintainer
  correspondence above: free, no quota, 5 req/sec/IP, with a paid tier
  coming "to cover costs" -- which implies he's fine with real usage
  today, informally. That's a friendly email, not a binding commercial-use
  grant.
- **Recommendation:** current footing is fine to keep building on for a
  prototype. Before a real launch, send a short explicit follow-up to
  Piotr Rybak asking whether shipping this inside a commercial app is
  acceptable -- a direct yes is worth more than inferring it from generic
  boilerplate that wasn't written with this use case in mind.

## Summary

| layer | source | access pattern | status |
|---|---|---|---|
| Catalog (sets/parts/minifigs/colors/etc.) | Rebrickable | bulk CSV sync, bundled locally | schema + scale confirmed |
| Per-set part list | Rebrickable | live fetch per set, on demand | scale confirmed (median 5, max 1,566 rows) |
| Camera → identity | Brickognize | live call, direct from client | API + roadmap + rate limits confirmed with maintainer |

No third-party catalog aggregator or alternative recognition service adds
value over this combination. Licensing terms for both sources have been
reviewed (see above) -- Rebrickable is fully clear for commercial use with
attribution; Brickognize is fine informally but wants an explicit
maintainer sign-off before a real commercial launch.

## Next steps

Done:
- Prototyped the camera → Brickognize recognition step directly against
  the live API (see empirical testing appendix above). Category-level
  recognition validated; exact-SKU recognition validated only for a
  subset of piece types.
- Confirmed minifigs decompose into their own part lists (see above).
- Built and validated `data/schema.sql` + `data/build_catalog_db.py` for
  the bundled catalog tables.
- Bundled the built SQLite catalog into the Xcode app target
  (`Brixi/Data/brixi_catalog.sqlite`) with a Swift read-only accessor
  (`Brixi/Data/CatalogDatabase.swift`).
- Wired recognition to the catalog: `Brixi/Recognition/BrickognizeClient.swift`
  calls the live API, `Brixi/Recognition/RecognitionService.swift` applies
  the 0.7 confidence gate from the empirical testing and resolves matches
  against `CatalogDatabase`.
- Reviewed Rebrickable and Brickognize terms of service (see above).
  Rebrickable is clear for commercial use with attribution; Brickognize
  needs an explicit maintainer sign-off before a real launch, informal
  footing is fine for now.

Not yet started:
- Confirm the app actually builds in Xcode. Blocked on hardware: the
  project's format requires Xcode 16, which needs macOS Sonoma+, which
  isn't available on the current dev machine (2015 MacBook Air, capped at
  Monterey). Waiting on a new Mac to arrive.
- Add a scheduled refresh job for the bundled catalog rather than the
  current manual one-shot build script.
- Design the "confirm from a shortlist" UX for decorated/niche pieces,
  as a fallback to silent auto-identification.
- Build the actual camera-capture call site -- nothing in the app yet
  calls `RecognitionService.recognize(imageData:)`; that depends on how
  images come from the Meta DAT camera feed, which hasn't been scoped.
- Run a larger, structured recognition trial under real bin-sorting
  conditions (ideally through the actual glasses camera pipeline, not a
  phone photo) to get a real accuracy number before committing to the
  auto-ID-vs-confirm-shortlist split.
- Follow up with Piotr Rybak for an explicit commercial-use sign-off
  before any real launch.
