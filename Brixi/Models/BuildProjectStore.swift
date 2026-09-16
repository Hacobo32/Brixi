//
// BuildProjectStore.swift
//
// Persists the user's in-progress builds as JSON on disk -- small, simple
// data (a handful of builds, each at most a few hundred part lines) that
// doesn't need SQLite. Kept separate from CatalogDatabase, which is
// read-only bundled reference data, not user state.
//
// Also owns which single build is "active" -- the one the app opens
// straight into and the one "Scan for Parts" checks against. Switching
// active builds never loses anything: every build's progress stays in
// `builds` regardless of which one (if any) is active.
//

import Foundation

private struct BuildLibrary: Codable {
  var builds: [BuildProject]
  var activeSet: SetSelection?
}

@MainActor
final class BuildProjectStore: ObservableObject {
  @Published private(set) var builds: [BuildProject]
  @Published private(set) var activeSet: SetSelection?

  private let fileURL: URL

  init(fileURL: URL? = nil) {
    let url = fileURL ?? Self.defaultFileURL()
    self.fileURL = url
    let library = Self.load(from: url)
    self.builds = library.builds
    self.activeSet = library.activeSet
  }

  private static func defaultFileURL() -> URL {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("builds.json")
  }

  private static func load(from url: URL) -> BuildLibrary {
    guard let data = try? Data(contentsOf: url) else { return BuildLibrary(builds: [], activeSet: nil) }
    if let library = try? JSONDecoder().decode(BuildLibrary.self, from: data) {
      return library
    }
    // Back-compat: earlier versions of this app persisted a bare
    // [BuildProject] array, with no notion of an active build yet.
    if let builds = try? JSONDecoder().decode([BuildProject].self, from: data) {
      return BuildLibrary(builds: builds, activeSet: nil)
    }
    return BuildLibrary(builds: [], activeSet: nil)
  }

  private func save() {
    let library = BuildLibrary(builds: builds, activeSet: activeSet)
    guard let data = try? JSONEncoder().encode(library) else { return }
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
    if activeSet?.setNum == setNum {
      activeSet = nil
    }
    save()
  }

  /// Makes `selection` the active build (or clears it, passing nil). Every
  /// other build's progress is untouched -- this only moves the pointer.
  func setActive(_ selection: SetSelection?) {
    activeSet = selection
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
