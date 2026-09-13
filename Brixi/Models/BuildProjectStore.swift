//
// BuildProjectStore.swift
//
// Persists the user's in-progress builds as JSON on disk -- small, simple
// data (a handful of builds, each at most a few hundred part lines) that
// doesn't need SQLite. Kept separate from CatalogDatabase, which is
// read-only bundled reference data, not user state.
//

import Foundation

@MainActor
final class BuildProjectStore: ObservableObject {
  @Published private(set) var builds: [BuildProject]

  private let fileURL: URL

  init(fileURL: URL? = nil) {
    let url = fileURL ?? Self.defaultFileURL()
    self.fileURL = url
    self.builds = Self.load(from: url)
  }

  private static func defaultFileURL() -> URL {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("builds.json")
  }

  private static func load(from url: URL) -> [BuildProject] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([BuildProject].self, from: data)) ?? []
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(builds) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  func build(setNum: String) -> BuildProject? {
    builds.first { $0.setNum == setNum }
  }

  func upsert(_ build: BuildProject) {
    if let index = builds.firstIndex(where: { $0.setNum == build.setNum }) {
      builds[index] = build
    } else {
      builds.append(build)
    }
    save()
  }

  func remove(setNum: String) {
    builds.removeAll { $0.setNum == setNum }
    save()
  }

  /// Adjusts how many of one part have been found, clamped to [0, needed].
  func markFound(setNum: String, partId: String, delta: Int) {
    guard let buildIndex = builds.firstIndex(where: { $0.setNum == setNum }) else { return }
    guard let partIndex = builds[buildIndex].parts.firstIndex(where: { $0.id == partId }) else { return }
    let part = builds[buildIndex].parts[partIndex]
    let newValue = max(0, min(part.quantityNeeded, part.quantityFound + delta))
    builds[buildIndex].parts[partIndex].quantityFound = newValue
    save()
  }
}
