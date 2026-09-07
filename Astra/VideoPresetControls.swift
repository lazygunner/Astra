import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoPresetControls: View {
    @Bindable var video: ScreenVideoPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("数字键视频").font(.title2.bold())
            Text("配置后，用食指轻戳模型屏幕下方的 1–5 数字键，即可切换视频。视频保存在应用内，重启后仍可使用。")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("显示按键触碰区域", isOn: $video.showModelInputRegions)
                .font(.caption)
            Text(video.modelInputStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(video.presets.entries) { entry in
                VideoPresetRow(video: video, entry: entry)
                if entry.id < 4 { Divider() }
            }
            if let error = video.errorMessage ?? video.presets.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct VideoPresetRow: View {
    @Bindable var video: ScreenVideoPlayer
    let entry: VideoPresets.Entry
    @State private var choosingFile = false
    @State private var choosingPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Text("\(entry.id + 1)")
                    .font(.title2.monospacedDigit().bold())
                    .frame(width: 44, height: 44)
                    .background(video.activePreset == entry.id ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.headline).lineLimit(1)
                    Text(importing ? "正在保存视频…" : video.activePreset == entry.id ? "当前已选" : entry.file == nil ? "等待配置" : "已保存到应用")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if importing { ProgressView() }
                else {
                    Button { _ = video.playPreset(entry.id) } label: {
                        Image(systemName: "play.fill")
                    }
                    .accessibilityLabel("播放视频 \(entry.id + 1)")
                    .disabled(!video.isAvailable || entry.file == nil)
                    Menu {
                        Button("从文件选择", systemImage: "folder") { choosingFile = true }
                        Button("从相册选择", systemImage: "photo.on.rectangle") {
                            error = nil
                            choosingPhotos = true
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("配置视频 \(entry.id + 1)")
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        // Present from the persistent window row, not the Menu's transient
        // presentation window, which disappears as the menu action completes.
        .photosPicker(isPresented: $choosingPhotos, selection: $photo,
                      matching: .videos, preferredItemEncoding: .automatic)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url):
                importing = true
                Task {
                    defer { importing = false }
                    do {
                        try await video.presets.configure(entry.id, source: url, name: url.lastPathComponent)
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            importing = true
            defer { importing = false; self.photo = nil }
            do {
                guard let imported = try await photo.loadTransferable(type: ImportedVideo.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                try await video.presets.configure(entry.id, source: imported.url, name: "相册视频 · \(entry.id + 1)")
                withExtendedLifetime(imported) {}
                error = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
