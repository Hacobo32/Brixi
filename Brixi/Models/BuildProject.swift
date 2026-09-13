//
// BuildProject.swift
//
// A set the user is trying to rebuild from a mixed bin of parts: its
// needed-parts list plus how many of each have been found so far. This is
// the user's own in-progress state for one specific rebuild, not the
// Rebrickable catalog itself (see CatalogDatabase for that).
//

import Foundation

struct NeededPart: Identifiable, Codable, Equatable {
  let partNum: String
  let colorId: Int
  let name: String
  let colorName: String
  let imageURL: URL?
  let quantityNeeded: Int
  var quantityFound: Int

  var id: String { "\(partNum)-\(colorId)" }
  var isComplete: Bool { quantityFound >= quantityNeeded }
}

struct BuildProject: Identifiable, Codable {
  let setNum: String
  let setName: String
  let setImageURL: URL?
  var parts: [NeededPart]

  var id: String { setNum }

  var totalNeeded: Int { parts.reduce(0) { $0 + $1.quantityNeeded } }
  var totalFound: Int { parts.reduce(0) { $0 + min($1.quantityFound, $1.quantityNeeded) } }
  var isComplete: Bool { parts.allSatisfy(\.isComplete) }
}
