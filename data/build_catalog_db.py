#!/usr/bin/env python3
"""Build the Brixi local catalog SQLite database from Rebrickable CSV exports.

Usage:
    python3 build_catalog_db.py <csv_dir> [output.sqlite]

<csv_dir> must contain these Rebrickable CSV files (as downloaded from
rebrickable.com/downloads): themes.csv, colors.csv, part_categories.csv,
parts.csv, part_relationships.csv, elements.csv, sets.csv, minifigs.csv,
inventories.csv, inventory_sets.csv, inventory_minifigs.csv.

inventory_parts.csv is intentionally ignored -- it's fetched per-set, on
demand, rather than bundled locally (see
docs/rebrickable-brickognize-feasibility.md).

Output defaults to brixi_catalog.sqlite in the current directory.
"""

import csv
import sqlite3
import sys
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent / "schema.sql"


def to_int(value):
    return int(value) if value not in (None, "") else None


def to_bool_int(value):
    return 1 if value.strip().lower() == "true" else 0


def load_csv(csv_dir, filename):
    path = csv_dir / filename
    if not path.exists():
        sys.exit(f"Missing required file: {path}")
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_themes(conn, csv_dir):
    rows = load_csv(csv_dir, "themes.csv")
    conn.executemany(
        "INSERT INTO themes (id, name, parent_id) VALUES (?, ?, ?)",
        [(to_int(r["id"]), r["name"], to_int(r["parent_id"])) for r in rows],
    )
    return len(rows)


def load_colors(conn, csv_dir):
    rows = load_csv(csv_dir, "colors.csv")
    conn.executemany(
        "INSERT INTO colors (id, name, rgb, is_trans) VALUES (?, ?, ?, ?)",
        [(to_int(r["id"]), r["name"], r["rgb"], to_bool_int(r["is_trans"])) for r in rows],
    )
    return len(rows)


def load_part_categories(conn, csv_dir):
    rows = load_csv(csv_dir, "part_categories.csv")
    conn.executemany(
        "INSERT INTO part_categories (id, name) VALUES (?, ?)",
        [(to_int(r["id"]), r["name"]) for r in rows],
    )
    return len(rows)


def load_parts(conn, csv_dir):
    rows = load_csv(csv_dir, "parts.csv")
    conn.executemany(
        "INSERT INTO parts (part_num, name, part_cat_id, part_material) VALUES (?, ?, ?, ?)",
        [(r["part_num"], r["name"], to_int(r["part_cat_id"]), r["part_material"] or None) for r in rows],
    )
    return len(rows)


def load_part_relationships(conn, csv_dir):
    rows = load_csv(csv_dir, "part_relationships.csv")
    conn.executemany(
        "INSERT INTO part_relationships (rel_type, child_part_num, parent_part_num) VALUES (?, ?, ?)",
        [(r["rel_type"], r["child_part_num"], r["parent_part_num"]) for r in rows],
    )
    return len(rows)


def load_elements(conn, csv_dir):
    rows = load_csv(csv_dir, "elements.csv")
    conn.executemany(
        "INSERT INTO elements (element_id, part_num, color_id, design_id) VALUES (?, ?, ?, ?)",
        [(to_int(r["element_id"]), r["part_num"], to_int(r["color_id"]), r["design_id"] or None) for r in rows],
    )
    return len(rows)


def load_sets(conn, csv_dir):
    rows = load_csv(csv_dir, "sets.csv")
    conn.executemany(
        "INSERT INTO sets (set_num, name, year, theme_id, num_parts, img_url) VALUES (?, ?, ?, ?, ?, ?)",
        [(r["set_num"], r["name"], to_int(r["year"]), to_int(r["theme_id"]), to_int(r["num_parts"]), r["img_url"] or None) for r in rows],
    )
    return len(rows)


def load_minifigs(conn, csv_dir):
    rows = load_csv(csv_dir, "minifigs.csv")
    conn.executemany(
        "INSERT INTO minifigs (fig_num, name, num_parts, img_url) VALUES (?, ?, ?, ?)",
        [(r["fig_num"], r["name"], to_int(r["num_parts"]), r["img_url"] or None) for r in rows],
    )
    return len(rows)


def load_inventories(conn, csv_dir):
    rows = load_csv(csv_dir, "inventories.csv")
    conn.executemany(
        "INSERT INTO inventories (id, version, set_num) VALUES (?, ?, ?)",
        [(to_int(r["id"]), to_int(r["version"]), r["set_num"]) for r in rows],
    )
    return len(rows)


def load_inventory_sets(conn, csv_dir):
    rows = load_csv(csv_dir, "inventory_sets.csv")
    conn.executemany(
        "INSERT INTO inventory_sets (inventory_id, set_num, quantity) VALUES (?, ?, ?)",
        [(to_int(r["inventory_id"]), r["set_num"], to_int(r["quantity"])) for r in rows],
    )
    return len(rows)


def load_inventory_minifigs(conn, csv_dir):
    rows = load_csv(csv_dir, "inventory_minifigs.csv")
    conn.executemany(
        "INSERT INTO inventory_minifigs (inventory_id, fig_num, quantity) VALUES (?, ?, ?)",
        [(to_int(r["inventory_id"]), r["fig_num"], to_int(r["quantity"])) for r in rows],
    )
    return len(rows)


# Order matters: parents must load before children referencing them via FK.
LOADERS = [
    ("themes", load_themes),
    ("colors", load_colors),
    ("part_categories", load_part_categories),
    ("parts", load_parts),
    ("part_relationships", load_part_relationships),
    ("elements", load_elements),
    ("sets", load_sets),
    ("minifigs", load_minifigs),
    ("inventories", load_inventories),
    ("inventory_sets", load_inventory_sets),
    ("inventory_minifigs", load_inventory_minifigs),
]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    csv_dir = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("brixi_catalog.sqlite")

    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(out_path)
    conn.executescript(SCHEMA_PATH.read_text())

    # Foreign keys are enforced at query time by the app; disable checking
    # during bulk load since self-referencing tables (themes) and
    # cross-references can land in an order that violates them mid-load
    # even though the finished dataset is consistent.
    conn.execute("PRAGMA foreign_keys = OFF")
    with conn:
        for table_name, loader in LOADERS:
            count = loader(conn, csv_dir)
            print(f"{table_name}: {count} rows")

    violations = conn.execute("PRAGMA foreign_key_check").fetchall()
    if violations:
        print(f"\nWARNING: {len(violations)} foreign key violations found:")
        for v in violations[:20]:
            print(f"  {v}")
    conn.execute("PRAGMA foreign_keys = ON")

    conn.close()
    print(f"\nWrote {out_path} ({out_path.stat().st_size / 1_000_000:.1f} MB)")


if __name__ == "__main__":
    main()
