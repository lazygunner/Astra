import Metal
import RealityKit
import simd
import UIKit

/// Updates during manipulation AND the system's return animation.
struct TelephoneCordComponent: Component {
    let cord: TelephoneCord
}

struct TelephoneCordSystem: System {
    static let query = EntityQuery(where: .has(TelephoneCordComponent.self))
    init(scene: RealityKit.Scene) {}
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[TelephoneCordComponent.self]?.cord.update()
        }
    }
}

@MainActor
final class TelephoneCord {
    private weak var handset: Entity?
    private weak var coordinateSpace: Entity?
    private weak var originalCord: Entity?
    private let model = ModelEntity()
    private let mesh: LowLevelMesh
    private let indexCount: Int
    private var previousEnd: SIMD3<Float>?
    private var previousLead: SIMD3<Float>?

    init(handset: Entity, original: Entity, coordinateSpace: Entity) throws {
        self.handset = handset
        self.coordinateSpace = coordinateSpace
        originalCord = original
        let indices = TelephoneCordGeometry.indices
        indexCount = indices.count
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: (TelephoneCordGeometry.segments + 1) * TelephoneCordGeometry.sides,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<TelephoneCordGeometry.Vertex>.offset(of: \.position)!),
                .init(semantic: .normal, format: .float3, offset: MemoryLayout<TelephoneCordGeometry.Vertex>.offset(of: \.normal)!)
            ],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<TelephoneCordGeometry.Vertex>.stride)],
            indexCapacity: indices.count
        )
        mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { bytes in
            let buffer = bytes.bindMemory(to: UInt32.self)
            for (i, index) in indices.enumerated() { buffer[i] = index }
        }
        update()
        let resource = try MeshResource(from: mesh)
        let materials = original.components[ModelComponent.self]?.materials
            ?? [SimpleMaterial(color: .red, roughness: 0.4, isMetallic: false)]
        model.model = ModelComponent(mesh: resource, materials: materials)
        model.name = "AstraFlexibleTelephoneCord"
        coordinateSpace.addChild(model)
        original.isEnabled = false
    }

    func update() {
        guard let handset, let coordinateSpace else { return }
        let end = handset.convert(position: TelephoneCordGeometry.handsetPort, to: coordinateSpace)
        let lead = handset.convert(direction: TelephoneCordGeometry.lead, to: coordinateSpace)
        guard end != previousEnd || lead != previousLead else { return }
        let vertices = TelephoneCordGeometry.vertices(end: end, endLead: lead)
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = -lower
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let buffer = bytes.bindMemory(to: TelephoneCordGeometry.Vertex.self)
            for (i, vertex) in vertices.enumerated() {
                buffer[i] = vertex
                lower = simd_min(lower, vertex.position)
                upper = simd_max(upper, vertex.position)
            }
        }
        mesh.parts.replaceAll([.init(indexCount: indexCount, bounds: BoundingBox(min: lower, max: upper))])
        previousEnd = end
        previousLead = lead
    }

    func detach() {
        model.removeFromParent()
        originalCord?.isEnabled = true
    }
}
