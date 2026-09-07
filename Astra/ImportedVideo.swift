import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Photos owns the source URL only during the transfer callback. Keep our own file
/// for AVPlayer's asynchronous reads, and remove it when playback releases it.
nonisolated final class ImportedVideo: Transferable, Sendable {
    let url: URL

    init(url: URL) { self.url = url }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AstraPhotoVideos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let suffix = received.file.pathExtension
            let destination = directory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(suffix.isEmpty ? "mov" : suffix)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedVideo(url: destination)
        }
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
