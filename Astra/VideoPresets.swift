import Foundation
import Observation

@MainActor
@Observable
final class VideoPresets {
    struct Entry: Codable, Identifiable {
        let id: Int
        var name: String
        var file: String?
    }
    private(set) var entries: [Entry] = (0..<5).map { Entry(id: $0, name: "未配置", file: nil) }
    var errorMessage: String?
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("VideoPresets", isDirectory: true)) {
        self.directory = directory
        let manifest = directory.appendingPathComponent("presets.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            do {
                let saved = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: manifest))
                guard saved.count == 5, saved.map(\.id) == Array(0..<5) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                entries = saved
                // Nothing is playing at store initialization. Reclaim prior
                // revisions now, not while a player might still be reading them.
                let retained = Set(saved.compactMap(\.file) + ["presets.json"])
                if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                    for file in files where !retained.contains(file.lastPathComponent) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            } catch { errorMessage = "视频配置读取失败：\(error.localizedDescription)" }
        }
    }

    func url(for index: Int) -> URL? {
        guard entries.indices.contains(index), let file = entries[index].file else { return nil }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func configure(_ index: Int, source: URL, name: String) async throws {
        guard entries.indices.contains(index) else { return }
        let directory = directory
        let destination = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
        // Copy outside the main actor; the Photos temporary file remains retained
        // by the caller until this copy completes. Save only a local relative path.
        try await Task.detached {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
        do {
            try Task.checkCancellation()
            var updated = entries
            updated[index] = Entry(id: index, name: name, file: destination.lastPathComponent)
            try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("presets.json"), options: .atomic)
            entries = updated
            errorMessage = nil
            // Keep replaced files during this session: AVPlayer may still be
            // reading one. They can be removed when the app next launches.
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
