import AVFoundation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class ScreenVideoPlayer {
    let presets = VideoPresets()
    private(set) var activePreset: Int?
    var showModelInputRegions = false
    var modelInputStatus = "放置模型后，用食指轻戳按键表面。"
    private(set) var lastModelAction = "等待模型按键操作"

    @discardableResult
    func playPreset(_ index: Int) -> Bool {
        guard isAvailable else {
            errorMessage = "请先放置模型。"
            return false
        }
        guard let url = presets.url(for: index) else {
            errorMessage = "请先在窗口配置第 \(index + 1) 路视频。"
            lastModelAction = "视频 \(index + 1) 未配置"
            return false
        }
        open(url)
        activePreset = index
        fileName = presets.entries[index].name
        lastModelAction = "已选择视频 \(index + 1)"
        return true
    }

    func recordModelAction(_ text: String) { lastModelAction = text }

    private(set) var isAvailable = false
    private(set) var hasVideo = false
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var fileName = ""
    private(set) var isProjectorAvailable = false
    var isProjectorEnabled = true
    var errorMessage: String?
    var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    @ObservationIgnored private let player = AVPlayer()
    let projector = ProjectorController()
    private(set) var isTestingProjection = false

    func toggleProjectionTest() {
        isTestingProjection.toggle()
        if isTestingProjection {
            isProjectorEnabled = true
            projector.showTestPattern()
        } else if let item = player.currentItem, hasVideo {
            projector.start(item: item)
        } else {
            projector.stopProjection()
        }
    }
    @ObservationIgnored private weak var screen: Entity?
    @ObservationIgnored private var original: ModelComponent?
    @ObservationIgnored private var videoMesh: MeshResource?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var importedVideo: ImportedVideo?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var requestID = UUID()

    func attach(to asset: Entity) {
        detach()
        screen = asset.findEntity(named: "Display___convex_glass___image_bearing_surface")
        original = screen?.components[ModelComponent.self]
        projector.attach(to: asset)
        isProjectorAvailable = projector.isAvailable
        isAvailable = original != nil
        if !isAvailable { errorMessage = "未找到可播放视频的屏幕网格。" }
    }

    /// Build a separate mesh so stopping video restores the untouched authored material and UVs.
    /// The video is mapped with a `cover`-style UV transform: it keeps its aspect ratio,
    /// fills the screen, and crops equally from the two sides of the overflowing axis.
    private func makeVideoMesh(from mesh: MeshResource, videoAspectRatio: Float) throws -> MeshResource {
        var contents = mesh.contents
        let coordinates = contents.models.flatMap { model in
            model.parts.flatMap { part in part.textureCoordinates.map { Array($0) } ?? [] }
        }
        guard let first = coordinates.first else { throw VideoError.missingUV }
        let low = coordinates.reduce(first) { simd_min($0, $1) }
        let high = coordinates.reduce(first) { simd_max($0, $1) }
        let extent = high - low
        guard extent.x > 0.000001, extent.y > 0.000001 else { throw VideoError.missingUV }

        let positions = contents.models.flatMap { model in
            model.parts.flatMap { part in part.positions.map { $0 } }
        }
        guard let firstPosition = positions.first else { throw VideoError.missingGeometry }
        let positionLow = positions.dropFirst().reduce(firstPosition) { simd_min($0, $1) }
        let positionHigh = positions.dropFirst().reduce(firstPosition) { simd_max($0, $1) }
        let positionExtent = positionHigh - positionLow
        // The USDZ asset is authored Z-up, so the screen spans X/Z. Keep a fallback
        // for meshes imported with a different up axis.
        let screenWidth = positionExtent.x
        let screenHeight = positionExtent.z > 0.000001 ? positionExtent.z : positionExtent.y
        guard screenWidth > 0.000001, screenHeight > 0.000001 else {
            throw VideoError.missingGeometry
        }
        let screenAspectRatio = screenWidth / screenHeight
        let cropScale: SIMD2<Float>
        if videoAspectRatio > screenAspectRatio {
            cropScale = [screenAspectRatio / videoAspectRatio, 1]
        } else {
            cropScale = [1, videoAspectRatio / screenAspectRatio]
        }
        let cropOffset = (SIMD2<Float>(repeating: 1) - cropScale) / 2

        contents.models = MeshModelCollection(contents.models.map { model in
            var model = model
            model.parts = MeshPartCollection(model.parts.map { part in
                var part = part
                if let uv = part.textureCoordinates {
                    part.textureCoordinates = MeshBuffers.TextureCoordinates(uv.map { coordinate in
                        let normalized = (coordinate - low) / extent
                        return normalized * cropScale + cropOffset
                    })
                }
                part.materialIndex = 0
                return part
            })
            return model
        })
        return try MeshResource.generate(from: contents)
    }

    func open(_ video: ImportedVideo) {
        open(video.url)
        if hasVideo {
            importedVideo = video
            fileName = "相册视频"
        }
    }

    func open(_ url: URL) {
        guard original != nil else { return }
        stop()
        let request = UUID()
        requestID = request
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let item = AVPlayerItem(url: url)
        projector.prepare(item: item)
        fileName = url.lastPathComponent
        isLoading = true
        hasVideo = true
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request else { return }
                switch status {
                case .readyToPlay:
                    do {
                        let size = item.presentationSize
                        guard size.width > 0, size.height > 0 else {
                            throw VideoError.invalidVideoSize
                        }
                        guard let originalMesh = self.original?.mesh else {
                            throw VideoError.missingGeometry
                        }
                        self.videoMesh = try self.makeVideoMesh(
                            from: originalMesh,
                            videoAspectRatio: Float(size.width / size.height)
                        )
                        guard let videoMesh = self.videoMesh else {
                            throw VideoError.missingUV
                        }
                        self.screen?.components.set(
                            ModelComponent(mesh: videoMesh, materials: [VideoMaterial(avPlayer: self.player)])
                        )
                        if self.isProjectorEnabled && !self.isTestingProjection {
                            self.projector.start(item: item)
                        }
                        self.isLoading = false
                        self.player.play()
                        self.isPlaying = true
                    } catch {
                        self.stop()
                        self.errorMessage = error.localizedDescription
                    }
                case .failed:
                    self.stop()
                    self.errorMessage = message ?? "无法播放此视频，请选择兼容的视频文件。"
                default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request else { return }
                self.isPlaying = false
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request else { return }
                self.stop()
                self.errorMessage = "视频播放中断，请重新选择视频。"
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func togglePlayback() {
        guard hasVideo, !isLoading else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if let item = player.currentItem, item.duration.isNumeric,
               CMTimeCompare(item.currentTime(), item.duration) >= 0 {
                player.seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    func setProjectorEnabled(_ enabled: Bool) {
        isProjectorEnabled = enabled
        isTestingProjection = false
        if !enabled { projector.stopProjection() }
        guard let item = player.currentItem, hasVideo else { return }
        if enabled {
            projector.start(item: item)
        } else {
            projector.stopProjection()
        }
    }

    func stop() {
        requestID = UUID()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
        projector.stopVideo()
        isTestingProjection = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        importedVideo = nil
        if let original { screen?.components.set(original) }
        activePreset = nil
        hasVideo = false
        isPlaying = false
        isLoading = false
        fileName = ""
        errorMessage = nil
    }

    func detach() {
        stop()
        projector.detach()
        isProjectorAvailable = false
        screen = nil
        original = nil
        videoMesh = nil
        isAvailable = false
    }

    private enum VideoError: LocalizedError {
        case missingUV, missingGeometry, invalidVideoSize
        var errorDescription: String? {
            switch self {
            case .missingUV: "屏幕缺少有效的纹理坐标，无法映射视频。"
            case .missingGeometry: "屏幕缺少有效的几何尺寸，无法计算视频裁剪范围。"
            case .invalidVideoSize: "无法读取视频的画面尺寸。"
            }
        }
    }
}
