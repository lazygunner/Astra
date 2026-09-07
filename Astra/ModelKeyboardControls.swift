import AVFoundation
import OSLog
import RealityKit
import SwiftUI

private let keyboardInputLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.darkstring.Astra",
    category: "KeyboardInput"
)

/// Invisible input regions over the existing keyboard; no new visible geometry.
struct KeyboardActionComponent: Component {
    enum Action: String { case playback, projection }
    var action: Action
    var preset: Int? = nil
}
@MainActor
final class ModelKeyboardControls {
    private var regions: [Entity] = []
    private let audio = ButtonAudio()
    private var lastTap = Date.distantPast
    private weak var video: ScreenVideoPlayer?

    private var regionSizes: [Entity.ID: SIMD3<Float>] = [:]

    private func configureRegion(_ region: Entity, size: SIMD3<Float>, label: String) {
        // Match viewshine's native entities: an input target and a solid collider.
        region.components.set(InputTargetComponent(allowedInputTypes: .all))
        region.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        var accessibility = AccessibilityComponent()
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        accessibility.isAccessibilityElement = true
        region.components.set(accessibility)
        regionSizes[region.id] = size
    }

    func setDebugVisible(_ visible: Bool) {
        for region in regions {
            guard let size = regionSizes[region.id] else { continue }
            if visible {
                region.components.set(ModelComponent(
                    mesh: .generateBox(size: size),
                    materials: [SimpleMaterial(color: .cyan.withAlphaComponent(0.35), isMetallic: false)]
                ))
            } else {
                region.components.remove(ModelComponent.self)
            }
        }
    }

    /// Log every system target before routing, including hits on the housing.
    /// Resolve descendants as viewshine's authored button containers can contain meshes.
    func handleTap(on hit: Entity) {
        keyboardInputLogger.notice("System tap target=\(hit.name, privacy: .public)")
        var candidate: Entity? = hit
        while let entity = candidate {
            if regions.contains(where: { $0 === entity }) {
                if let video { activate(entity, video: video) }
                return
            }
            candidate = entity.parent
        }
        if video?.showModelInputRegions == true {
            video?.modelInputStatus = "点击命中非按键：\(hit.name)"
        }
    }

    func attach(to asset: Entity, video: ScreenVideoPlayer) {
        detach()
        self.video = video
        keyboardInputLogger.info("Attaching keyboard tap regions to asset=\(asset.name, privacy: .public)")
        guard let keyboard = asset.findEntity(named: "Cube_032") else {
            keyboardInputLogger.error("Keyboard entity Cube_032 not found; no tap regions attached")
            video.modelInputStatus = "未找到模型键盘，请重新放置模型。"
            return
        }
        // This asset's keyboard is a thin XY slab in its authored Z-up space.
        let bounds = keyboard.visualBounds(relativeTo: keyboard)
        let split = bounds.min.x + bounds.extents.x * 0.77
        addRegion(.playback, keyboard: keyboard, bounds: bounds, lowX: bounds.min.x, highX: split - 0.006)
        addRegion(.projection, keyboard: keyboard, bounds: bounds, lowX: split + 0.006, highX: bounds.max.x)
        if let labels = asset.findEntity(named: "Engraved_key_1") {
            // Measured from the five engraved digits in the bundled USDZ.
            // Mesh coordinates are Z-up; the front face is along negative Y.
            let centers: [Float] = [0.02255, 0.05232, 0.08205, 0.11180, 0.14157]
            for (index, x) in centers.enumerated() {
                let region = Entity()
                region.name = "AstraVideoPreset_\(index + 1)"
                region.position = [x, -0.198, 0.265]
                region.components.set(KeyboardActionComponent(action: .playback, preset: index))
                configureRegion(region, size: [0.025, 0.016, 0.022], label: "视频 \(index + 1)")
                labels.addChild(region)
                regions.append(region)
            }
        }
        let urls = ["key-play", "key-pause", "key-project-on", "key-project-off", "key-unavailable"].compactMap {
            Bundle.main.url(forResource: $0, withExtension: "wav")
        }
        Task { await audio.load(urls) }
        setDebugVisible(video.showModelInputRegions)
        keyboardInputLogger.notice("Attached tap regions count=\(self.regions.count, privacy: .public)")
    }

    private func addRegion(_ action: KeyboardActionComponent.Action, keyboard: Entity,
                           bounds: BoundingBox, lowX: Float, highX: Float) {
        let region = Entity()
        region.name = "AstraKeyboard_\(action.rawValue)"
        region.position = [(lowX + highX) / 2, bounds.center.y, bounds.max.z + 0.004]
        region.components.set(KeyboardActionComponent(action: action))
        configureRegion(region, size: [highX - lowX, bounds.extents.y, 0.012],
                        label: action == .playback ? "播放或暂停视频" : "开启或停止投影")
        keyboard.addChild(region)
        regions.append(region)
    }

    func setEnabled(_ enabled: Bool) {
        keyboardInputLogger.info("Setting tap regions enabled=\(enabled, privacy: .public), count=\(self.regions.count, privacy: .public)")
        regions.forEach { $0.isEnabled = enabled }
        video?.modelInputStatus = regions.isEmpty
            ? "没有可点击的模型按键。"
            : enabled ? "模型按键已就绪：用食指轻戳按键表面。"
                      : "模型拆解或调整中，按键暂时停用。"
    }

    private func activate(_ entity: Entity, video: ScreenVideoPlayer) {
        guard regions.contains(where: { $0 === entity }), entity.isEnabledInHierarchy,
              let action = entity.components[KeyboardActionComponent.self]?.action,
              Date().timeIntervalSince(lastTap) > 0.25 else {
            keyboardInputLogger.debug("Activation rejected by region/enabled/action/debounce guard")
            return
        }
        lastTap = Date()
        let keyName: String
        if let index = entity.components[KeyboardActionComponent.self]?.preset {
            keyName = "数字键 \(index + 1)"
        } else {
            keyName = action == .playback ? "播放/暂停键" : "投影键"
        }
        video.modelInputStatus = "已收到点击：\(keyName)"
        video.recordModelAction("已收到点击：\(keyName)")
        if let index = entity.components[KeyboardActionComponent.self]?.preset {
            let success = video.playPreset(index)
            playSound(success ? "key-play" : "key-unavailable")
            return
        }
        guard video.hasVideo, !video.isLoading else {
            video.errorMessage = video.isLoading ? "视频正在加载，请稍候。" : "请先选择视频，再使用键盘控制。"
            playSound("key-unavailable")
            return
        }
        video.errorMessage = nil
        switch action {
        case .playback:
            video.togglePlayback()
            playSound(video.isPlaying ? "key-play" : "key-pause")
        case .projection:
            guard video.isProjectorAvailable else {
                video.errorMessage = "当前设备无法使用墙面投影。"
                playSound("key-unavailable")
                return
            }
            video.setProjectorEnabled(!video.isProjectorEnabled)
            playSound(video.isProjectorEnabled ? "key-project-on" : "key-project-off")
        }
    }

    private func playSound(_ name: String) {
        Task { await audio.play(name) }
    }

    func detach() {
        keyboardInputLogger.info("Detaching tap regions count=\(self.regions.count, privacy: .public)")
        regions.forEach { $0.removeFromParent() }
        regions.removeAll()
        regionSizes.removeAll()
        video?.modelInputStatus = "放置模型后，用食指轻戳按键表面。"
        video = nil
        Task { await audio.stop() }
        lastTap = .distantPast
    }
}
