//
// CatalogDatabase.swift
//
// Read-only access to the bundled Rebrickable-derived local catalog.
// The database file is built by data/build_catalog_db.py from
// Rebrickable's CSV exports -- see data/schema.sql for the table layout
// and docs/rebrickable-brickognize-feasibility.md for why this data is
// bundled locally rather than fetched live.

import Foundation
import SQLite3

struct CatalogSet {
  let setNum: String
  let name: String
  let year: Int?
  let themeId: Int?
  let numParts: Int?
  let imgURL: URL?
}

struct CatalogPart {
  let partNum: String
  let name: String
  let partCatId: Int?
  let partMaterial: String?
}

struct CatalogMinifig {
  let figNum: String
  let name: String
  let numParts: Int?
  let imgURL: URL?
}

enum CatalogDatabaseError: Error {
  case bundleResourceNotFound
  case openFailed(String)
}

final class CatalogDatabase {
  private let db: OpaquePointer

  init() throws {
    guard let path = Bundle.main.path(forResource: "brixi_catalog", ofType: "sqlite") else {
      throw CatalogDatabaseError.bundleResourceNotFound
    }
    var handle: OpaquePointer?
    // The bundled catalog is never written to at runtime.
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
      throw CatalogDatabaseError.openFailed(message)
    }
    self.db = handle
  }

  deinit {
    sqlite3_close(db)
  }

  func set(setNum: String) -> CatalogSet? {
    let sql = "SELECT set_num, name, year, theme_id, num_parts, img_url FROM sets WHERE set_num = ? LIMIT 1"
    return query(sql, bindings: [.text(setNum)]) { stmt in
      CatalogSet(
        setNum: columnText(stmt, 0) ?? setNum,
        name: columnText(stmt, 1) ?? "",
        year: columnOptionalInt(stmt, 2),
        themeId: columnOptionalInt(stmt, 3),
        numParts: columnOptionalInt(stmt, 4),
        imgURL: columnText(stmt, 5).flatMap(URL.init(string:))
      )
    }.first
  }

  func part(partNum: String) -> CatalogPart? {
    let sql = "SELECT part_num, name, part_cat_id, part_material FROM parts WHERE part_num = ? LIMIT 1"
    return query(sql, bindings: [.text(partNum)]) { stmt in
      CatalogPart(
        partNum: columnText(stmt, 0) ?? partNum,
        name: columnText(stmt, 1) ?? "",
        partCatId: columnOptionalInt(stmt, 2),
        partMaterial: columnText(stmt, 3)
      )
    }.first
  }

  func minifig(figNum: String) -> CatalogMinifig? {
    let sql = "SELECT fig_num, name, num_parts, img_url FROM minifigs WHERE fig_num = ? LIMIT 1"
    return query(sql, bindings: [.text(figNum)]) { stmt in
      CatalogMinifig(
        figNum: columnText(stmt, 0) ?? figNum,
        name: columnText(stmt, 1) ?? "",
        numParts: columnOptionalInt(stmt, 2),
        imgURL: columnText(stmt, 3).flatMap(URL.init(string:))
      )
    }.first
  }

  func themeName(themeId: Int) -> String? {
    let sql = "SELECT name FROM themes WHERE id = ? LIMIT 1"
    return query(sql, bindings: [.int(themeId)]) { stmt in columnText(stmt, 0) ?? "" }.first
  }

  /// Resolves a part+color to its Rebrickable "element" photo URL via the
  /// elements join, instead of storing a URL per part/color/set row
  /// anywhere -- see data/schema.sql.
  func elementImageURL(partNum: String, colorId: Int) -> URL? {
    let sql = "SELECT element_id FROM elements WHERE part_num = ? AND color_id = ? LIMIT 1"
    guard let elementId = query(sql, bindings: [.text(partNum), .int(colorId)], map: { stmt in
      Int(sqlite3_column_int64(stmt, 0))
    }).first else {
      return nil
    }
    return URL(string: "https://cdn.rebrickable.com/media/parts/elements/\(elementId).jpg")
  }

  // MARK: - Query plumbing

  private enum Binding {
    case text(String)
    case int(Int)
  }

  private func query<T>(_ sql: String, bindings: [Binding], map: (OpaquePointer) -> T) -> [T] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      return []
    }
    defer { sqlite3_finalize(statement) }

    for (index, binding) in bindings.enumerated() {
      let position = Int32(index + 1)
      switch binding {
      case .text(let value):
        sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
      case .int(let value):
        sqlite3_bind_int(statement, position, Int32(value))
      }
    }

    var results: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(map(statement))
    }
    return results
  }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
  guard let cString = sqlite3_column_text(statement, index) else { return nil }
  return String(cString: cString)
}

private func columnOptionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
  if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
  return Int(sqlite3_column_int64(statement, index))
}
