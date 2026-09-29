import RealityKit
import simd

/// System pinch manipulation; no app-owned hand tracking or joint processing.
@MainActor
final class TelephoneHandset {
    private weak var entity: Entity?
    private var restingTransform = Transform()
    private var cord: TelephoneCord?

    func attach(to scene: Entity) -> Bool {
        detach()
        guard let handset = scene.findEntity(named: "AstraTelephoneHandset"),
              let coordinateSpace = handset.parent,
              let originalCord = scene.findEntity(named: "Red_U_Shaped_Coiled_Handset_Cord") else {
            return false
        }
        do {
            cord = try TelephoneCord(handset: handset, original: originalCord, coordinateSpace: coordinateSpace)
        } catch {
            return false
        }
        let bounds = handset.visualBounds(recursive: true, relativeTo: handset)
        let shape = ShapeResource.generateBox(size: simd_max(bounds.extents, SIMD3(repeating: 0.001)))
            .offsetBy(translation: bounds.center)
        handset.components.set(InputTargetComponent(allowedInputTypes: .all))
        handset.components.set(CollisionComponent(shapes: [shape]))
        handset.components.set(HoverEffectComponent())
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .reset
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = .zero
        handset.components.set(manipulation)
        if let cord { handset.components.set(TelephoneCordComponent(cord: cord)) }
        restingTransform = handset.transform
        entity = handset
        return true
    }

    func restore() {
        entity?.stopAllAnimations(recursive: false)
        entity?.transform = restingTransform
        cord?.update()
    }

    func owns(_ candidate: Entity) -> Bool {
        candidate === entity
    }

    func detach() {
        cord?.detach()
        cord = nil
        guard let entity else { return }
        entity.components.remove(TelephoneCordComponent.self)
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        self.entity = nil
    }
}
