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

Open item, not yet confirmed: whether a `fig_num` can itself anchor an
`inventories` row (i.e. whether a minifig has its own decomposable parts
list the same way a set does). Worth a quick local check
(`grep fig- inventories.csv`) before assuming either way.

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
- **Backend: not needed for v1.** The repo currently has zero backend
  code — just the Meta Wearables DAT pairing scaffold. Default to calling
  Rebrickable's live API directly from the client with your own API key for
  anything not bundled. Graduate to a thin backend (sync job + proxy/cache)
  only once usage scales past what a single client-side API key comfortably
  supports, or attribution/licensing needs centralizing.

### Open item: licensing

Rebrickable's data has historically been non-commercial / attribution-required by default, with commercial use requiring contacting them directly for a license. **Not verified live in this session** (egress to rebrickable.com is blocked in this sandbox) — confirm current terms with Rebrickable before any commercial launch. This is a business decision independent of the technical approach above.

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

## Summary

| layer | source | access pattern | status |
|---|---|---|---|
| Catalog (sets/parts/minifigs/colors/etc.) | Rebrickable | bulk CSV sync, bundled locally | schema + scale confirmed |
| Per-set part list | Rebrickable | live fetch per set, on demand | scale confirmed (median 5, max 1,566 rows) |
| Camera → identity | Brickognize | live call, direct from client | API + roadmap + rate limits confirmed with maintainer |

No third-party catalog aggregator or alternative recognition service adds
value over this combination. Remaining gates before commercial launch, not
technical ones: confirm Rebrickable's current commercial licensing terms,
and read Brickognize's terms of service
(`https://brickognize.com/terms-of-service/`, not yet reviewed) for any
constraints on shipping it inside a commercial app.

## Next steps (not yet started)

- Confirm whether minifigs decompose into their own part lists in the
  Rebrickable data.
- Review Rebrickable and Brickognize terms of service for commercial use.
- Design the actual SQLite schema and sync job for the bundled tables.
- Prototype the camera → Brickognize → local catalog lookup loop.
