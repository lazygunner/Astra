import SwiftUI
import RealityKit
import simd

/// The wrapper owns user transforms; the asset's authored transforms remain intact.
@MainActor
@Observable
final class ModelPlacement {
    let assembly = ModelAssembly()
    @ObservationIgnored private var activeManipulations: Set<Entity.ID> = []
    var isLoading = false
    var errorMessage: String?
    var isReady = false
    var isManipulating = false
    var scale: Float = 1
    @ObservationIgnored let root = Entity()
    @ObservationIgnored private var generation = UUID()
    private let initialPosition = SIMD3<Float>(0, 1.1, -1.5)

    func load() async {
        let request = UUID()
        generation = request
        isLoading = true
        isReady = false
        errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            guard let url = Bundle.main.url(forResource: "YVR_600C_VisionPro", withExtension: "usdz") else {
                throw LoadError.missingAsset
            }
            let asset = try await Entity(contentsOf: url)
            guard generation == request, !Task.isCancelled else { return }
            let bounds = asset.visualBounds(relativeTo: nil)
            let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            guard longest.isFinite, longest > 0 else { throw LoadError.invalidBounds }
            let normalized = Entity()
            normalized.addChild(asset)
            // Centre the pivot and normalize the largest dimension to 60 cm.
            asset.position -= bounds.center
            normalized.scale = SIMD3(repeating: 0.6 / longest)
            root.children.removeAll()
            root.addChild(normalized)
            assembly.prepare(root: root, asset: asset)
            reset()
            isReady = true
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            errorMessage = "模型加载失败：\(error.localizedDescription)"
        }
    }

    func reset() {
        assembly.restore()
        root.transform = Transform(scale: .one, rotation: simd_quatf(), translation: initialPosition)
        scale = 1
    }

    func setScale(_ value: Float) {
        scale = min(3, max(0.25, value))
        root.scale = SIMD3(repeating: scale)
    }

    func syncScale() { setScale(root.scale.x) }

    func rotate(degrees: Float) {
        root.orientation = simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0]) * root.orientation
    }

    func moveHeight(_ amount: Float) { root.position.y += amount }

    func manipulationBegan(_ entity: Entity) {
        guard assembly.owns(entity) else { return }
        activeManipulations.insert(entity.id)
        isManipulating = !activeManipulations.isEmpty
    }

    func manipulationUpdated(_ entity: Entity) {
        if entity === root { syncScale() }
        else { assembly.clampScale(of: entity) }
    }

    func manipulationEnded(_ entity: Entity) {
        manipulationUpdated(entity)
        activeManipulations.remove(entity.id)
        isManipulating = !activeManipulations.isEmpty
    }

    func unload() {
        assembly.clear()
        activeManipulations.removeAll()
        generation = UUID()
        root.removeFromParent()
        root.children.removeAll()
        isLoading = false
        isReady = false
        isManipulating = false
    }

    private enum LoadError: LocalizedError {
        case missingAsset, invalidBounds
        var errorDescription: String? {
            switch self {
            case .missingAsset: "应用中未找到 YVR_600C_VisionPro.usdz。"
            case .invalidBounds: "模型没有有效的几何尺寸。"
            }
        }
    }
}
