import RealityKit
import SwiftUI
import simd

/// Assembly interaction inspired by Apple's ManipulatingModelsWithRealityKit sample.
@MainActor
@Observable
final class ModelAssembly {
    private(set) var isExpanded = false
    private(set) var partsAreUnlocked = false
    private(set) var isAnimating = false
    private(set) var partCount = 0
    var canExpand: Bool { partCount > 1 }

    @ObservationIgnored private var parts: [Part] = []
    @ObservationIgnored private weak var root: Entity?
    @ObservationIgnored private var animationTask: Task<Void, Never>?

    private struct Part {
        let entity: Entity
        let original: Transform
        let bounds: BoundingBox
    }

    func prepare(root: Entity, asset: Entity) {
        clear()
        self.root = root
        // Skip USD wrapper nodes and branches that contain only lights/materials.
        var candidate = asset
        while true {
            let visible = candidate.children.filter { Self.containsGeometry($0) }
            if visible.count > 1 {
                parts = visible.map {
                    Part(entity: $0, original: $0.transform,
                         bounds: $0.visualBounds(recursive: true, relativeTo: candidate))
                }
                break
            }
            guard let child = visible.first, candidate.components[ModelComponent.self] == nil else { break }
            candidate = child
        }
        partCount = parts.count
        configureInput()
    }

    private static func containsGeometry(_ entity: Entity) -> Bool {
        entity.components[ModelComponent.self] != nil || entity.children.contains { containsGeometry($0) }
    }

    func toggleParts() {
        guard canExpand, !isAnimating else { return }
        partsAreUnlocked.toggle()
        configureInput()
    }

    func toggleExpansion() {
        guard canExpand, !isAnimating else { return }
        isExpanded.toggle()
        partsAreUnlocked = isExpanded
        let targets = isExpanded ? expandedTransforms() : parts.map(\.original)
        isAnimating = true
        configureInput()
        for (part, target) in zip(parts, targets) {
            part.entity.move(to: target, relativeTo: part.entity.parent,
                             duration: 0.35, timingFunction: .easeInOut)
        }
        animationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self else { return }
            self.isAnimating = false
            self.configureInput()
        }
    }

    /// Layout uses cached assembled bounds, so repeated expand/collapse never accumulates drift.
    private func expandedTransforms() -> [Transform] {
        let volumes = parts.map { max(0.000001, $0.bounds.extents.x * $0.bounds.extents.y * $0.bounds.extents.z) }
        let total = volumes.reduce(0, +)
        let mean = zip(parts, volumes).reduce(SIMD3<Float>.zero) { $0 + $1.0.bounds.center * $1.1 } / total
        let variance = zip(parts, volumes).reduce(SIMD3<Float>.zero) {
            let delta = $1.0.bounds.center - mean
            return $0 + delta * delta * $1.1 / total
        }
        let axis = variance.z > variance.x && variance.z > variance.y ? 2 : (variance.y > variance.x ? 1 : 0)
        let indices = parts.indices.sorted {
            let a = parts[$0].bounds.center[axis], b = parts[$1].bounds.center[axis]
            return a == b ? $0 < $1 : a < b
        }
        guard let first = indices.first, let parent = parts[first].entity.parent else { return [] }
        var unit = SIMD3<Float>.zero
        unit[axis] = 1
        // Two-centimetre spacing in the current scene, independent of USD unit scale.
        let gap = 0.02 / max(0.000001, simd_length(parent.convert(direction: unit, to: nil)))
        let width = parts.reduce(Float.zero) { $0 + $1.bounds.extents[axis] } + gap * Float(parts.count - 1)
        let low = parts.map { $0.bounds.min[axis] }.min() ?? 0
        let high = parts.map { $0.bounds.max[axis] }.max() ?? 0
        var cursor = (low + high - width) / 2
        var result = parts.map(\.original)
        for index in indices {
            result[index].translation[axis] += cursor - parts[index].bounds.min[axis]
            cursor += parts[index].bounds.extents[axis] + gap
        }
        return result
    }

    private func removeInput(_ entity: Entity) {
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(HoverEffectComponent.self)
    }

    private func enableInput(_ entity: Entity) {
        let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
        let shape = ShapeResource.generateBox(size: simd_max(bounds.extents, SIMD3(repeating: 0.0001)))
            .offsetBy(translation: bounds.center)
        ManipulationComponent.configureEntity(entity, collisionShapes: [shape])
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .stay
        entity.components.set(manipulation)
    }

    private func configureInput() {
        guard let root else { return }
        removeInput(root)
        parts.forEach { removeInput($0.entity) }
        guard !isAnimating else { return }
        if partsAreUnlocked {
            parts.forEach { enableInput($0.entity) }
        } else {
            // Rebuild the whole-model hit box after any part movement or explosion.
            enableInput(root)
        }
    }

    func owns(_ entity: Entity) -> Bool {
        entity === root || parts.contains { $0.entity === entity }
    }

    func clampScale(of entity: Entity) {
        guard let part = parts.first(where: { $0.entity === entity }) else { return }
        let baseline = part.original.scale.x
        guard abs(baseline) > 0.000001 else { return }
        let factor = min(3, max(0.25, entity.scale.x / baseline))
        entity.scale = part.original.scale * factor
    }

    func restore() {
        animationTask?.cancel()
        for part in parts {
            part.entity.stopAllAnimations(recursive: false)
            part.entity.transform = part.original
        }
        isExpanded = false
        partsAreUnlocked = false
        isAnimating = false
        configureInput()
    }

    func clear() {
        animationTask?.cancel()
        animationTask = nil
        parts.forEach { $0.entity.stopAllAnimations(recursive: false) }
        parts.removeAll()
        root = nil
        partCount = 0
        isExpanded = false
        partsAreUnlocked = false
        isAnimating = false
    }
}
