import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ScreenVideoControls: View {
    @Bindable var video: ScreenVideoPlayer
    @State private var isChoosingVideo = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("屏幕视频", systemImage: "play.rectangle")
                .font(.headline)
            Text("模型键盘：左侧主键区播放/暂停，右侧数字键区开关投影。拆解时停用。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(video.hasVideo ? "更换视频" : "选择本地视频", systemImage: "folder") {
                isChoosingVideo = true
            }
            .disabled(!video.isAvailable || isImporting)
            PhotosPicker(selection: $selectedVideo, matching: .videos, preferredItemEncoding: .automatic) {
                Label("从相册选择视频", systemImage: "photo.on.rectangle")
            }
            .disabled(!video.isAvailable || isImporting)
            Toggle(isOn: Binding(
                get: { video.isProjectorEnabled },
                set: { video.setProjectorEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("墙面视频投影", systemImage: video.isProjectorEnabled ? "light.max" : "light.min")
                    Text(video.isProjectorAvailable
                         ? video.projector.status
                         : "需要 visionOS 27 及支持 Apple6 的设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!video.isProjectorAvailable)
            if video.isProjectorAvailable {
                Button(video.isTestingProjection ? "结束投影测试" : "测试墙面投影", systemImage: "checkerboard.rectangle") {
                    video.toggleProjectionTest()
                }
            }
            Text(video.modelInputStatus)
                .font(.caption).foregroundStyle(.secondary)
            if isImporting { ProgressView("正在从相册导入视频…") }
            if video.isLoading { ProgressView("正在准备视频…") }
            if video.hasVideo {
                Text(video.fileName).font(.caption).lineLimit(1)
                HStack {
                    Button(video.isPlaying ? "暂停" : "播放",
                           systemImage: video.isPlaying ? "pause.fill" : "play.fill") {
                        video.togglePlayback()
                    }
                    .disabled(video.isLoading)
                    Toggle("静音", isOn: $video.isMuted).toggleStyle(.button)
                    Button("恢复原屏幕") { video.stop() }
                        .disabled(isImporting)
                }
            }
            if let error = video.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: selectedVideo) {
            guard let selectedVideo else { return }
            isImporting = true
            video.errorMessage = nil
            defer {
                isImporting = false
                self.selectedVideo = nil
            }
            do {
                guard let imported = try await selectedVideo.loadTransferable(type: ImportedVideo.self) else {
                    if !Task.isCancelled { video.errorMessage = "无法导入此视频，请选择其他视频。" }
                    return
                }
                guard !Task.isCancelled, video.isAvailable else { return }
                video.open(imported)
            } catch {
                if !Task.isCancelled {
                    video.errorMessage = "相册视频导入失败：\(error.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $isChoosingVideo, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { video.open(url) }
            case .failure(let error):
                video.errorMessage = error.localizedDescription
            }
        }
    }
}
