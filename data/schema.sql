-- Brixi local catalog schema.
--
-- Mirrors the subset of Rebrickable's catalog that gets bundled/synced
-- locally (see docs/rebrickable-brickognize-feasibility.md). `inventory_parts`
-- is deliberately NOT part of this schema -- it's fetched per-set, on
-- demand, rather than stored locally (see that doc for why).
--
-- Built from these Rebrickable CSV exports: themes, colors,
-- part_categories, parts, part_relationships, elements, sets, minifigs,
-- inventories, inventory_sets, inventory_minifigs.

PRAGMA foreign_keys = ON;

CREATE TABLE themes (
  id        INTEGER PRIMARY KEY,
  name      TEXT NOT NULL,
  parent_id INTEGER REFERENCES themes(id)
);
CREATE INDEX idx_themes_parent_id ON themes(parent_id);

CREATE TABLE colors (
  id       INTEGER PRIMARY KEY,
  name     TEXT NOT NULL,
  rgb      TEXT NOT NULL,
  is_trans INTEGER NOT NULL CHECK (is_trans IN (0, 1))
);

CREATE TABLE part_categories (
  id   INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE parts (
  part_num      TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  part_cat_id   INTEGER REFERENCES part_categories(id),
  part_material TEXT
);
CREATE INDEX idx_parts_part_cat_id ON parts(part_cat_id);

-- rel_type: 'P' = print/pattern variant, 'R' = alternate/interchangeable
-- mold. Used to collapse near-duplicate part numbers (e.g. for matching a
-- Brickognize result back to a base part family).
CREATE TABLE part_relationships (
  rel_type        TEXT NOT NULL,
  child_part_num  TEXT NOT NULL,
  parent_part_num TEXT NOT NULL,
  PRIMARY KEY (rel_type, child_part_num, parent_part_num)
);
CREATE INDEX idx_part_relationships_child ON part_relationships(child_part_num);
CREATE INDEX idx_part_relationships_parent ON part_relationships(parent_part_num);

-- The part_num+color_id -> element_id join. Used to resolve a part+color's
-- photo (cdn.rebrickable.com/media/parts/elements/{element_id}.jpg) without
-- storing a URL per row anywhere else.
CREATE TABLE elements (
  element_id INTEGER PRIMARY KEY,
  part_num   TEXT NOT NULL REFERENCES parts(part_num),
  color_id   INTEGER NOT NULL REFERENCES colors(id),
  design_id  TEXT
);
CREATE INDEX idx_elements_part_color ON elements(part_num, color_id);

CREATE TABLE sets (
  set_num   TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  year      INTEGER,
  theme_id  INTEGER REFERENCES themes(id),
  num_parts INTEGER,
  img_url   TEXT
);
CREATE INDEX idx_sets_theme_id ON sets(theme_id);

CREATE TABLE minifigs (
  fig_num   TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  num_parts INTEGER,
  img_url   TEXT
);

-- set_num is polymorphic: most rows reference sets(set_num), but a
-- confirmed subset (one per row in `minifigs`) instead holds a minifig's
-- fig_num -- minifigs get their own decomposable inventory the same way
-- sets do. No FK constraint here since it can't target either table
-- conditionally; resolve by trying `sets` first, then `minifigs`.
CREATE TABLE inventories (
  id      INTEGER PRIMARY KEY,
  version INTEGER NOT NULL,
  set_num TEXT NOT NULL
);
CREATE INDEX idx_inventories_set_num ON inventories(set_num);

CREATE TABLE inventory_sets (
  inventory_id INTEGER NOT NULL REFERENCES inventories(id),
  set_num      TEXT NOT NULL REFERENCES sets(set_num),
  quantity     INTEGER NOT NULL,
  PRIMARY KEY (inventory_id, set_num)
);

CREATE TABLE inventory_minifigs (
  inventory_id INTEGER NOT NULL REFERENCES inventories(id),
  fig_num      TEXT NOT NULL REFERENCES minifigs(fig_num),
  quantity     INTEGER NOT NULL,
  PRIMARY KEY (inventory_id, fig_num)
);
