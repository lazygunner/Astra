import Foundation

/// Standalone persistence checks; run with swiftc and Astra/VideoPresets.swift.
@main
struct VideoPresetsChecks {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("presets")
        let source = root.appendingPathComponent("source.mov")
        let bytes = Data("fixture-video-bytes".utf8)
        try bytes.write(to: source)
        let store = VideoPresets(directory: directory)
        precondition(store.entries.count == 5 && store.url(for: 0) == nil)
        try await store.configure(0, source: source, name: "First")
        let firstURL = store.url(for: 0)!
        let copied = try Data(contentsOf: firstURL)
        precondition(copied == bytes && firstURL != source)
        try await store.configure(4, source: source, name: "Fifth")
        try await store.configure(0, source: source, name: "Replacement")
        precondition(FileManager.default.fileExists(atPath: firstURL.path), "Do not delete a video an active player may be reading")
        do {
            try await store.configure(2, source: root.appendingPathComponent("missing.mov"), name: "Missing")
            preconditionFailure("Missing source must fail")
        } catch { precondition(store.entries[2].file == nil) }
        let reloaded = VideoPresets(directory: directory)
        precondition(reloaded.entries[0].name == "Replacement")
        precondition(reloaded.entries[4].name == "Fifth")
        precondition(reloaded.url(for: 0) != nil && reloaded.url(for: 4) != nil)
        precondition(!FileManager.default.fileExists(atPath: firstURL.path), "Reclaim old revisions at next launch")
        precondition(reloaded.url(for: -1) == nil && reloaded.url(for: 5) == nil)
        print("PASS: five slots, copy, replace, failed import, persistence, safe cleanup")
    }
}
