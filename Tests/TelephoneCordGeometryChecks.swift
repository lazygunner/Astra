import Foundation
import simd

@main
struct TelephoneCordGeometryChecks {
    static func main() {
        typealias Cord = TelephoneCordGeometry
        let indices = Cord.indices
        let poses: [(SIMD3<Float>, SIMD3<Float>)] = [
            (Cord.restingPort, Cord.lead),
            (Cord.restingPort + [0, 0, 0.8], Cord.lead),
            (Cord.restingPort + [-0.6, 0.2, 0.4], -Cord.lead),
            (Cord.restingPort + [0, 0, -0.7], [0.1, 0, 0]),
            (Cord.basePort, .zero)
        ]
        for (end, lead) in poses {
            let points = Cord.centers(end: end, endLead: lead)
            precondition(points.first == Cord.basePort, "Base socket must stay fixed")
            precondition(points.last == end, "Handset socket must follow exactly")
            let vertices = Cord.vertices(end: end, endLead: lead)
            precondition(indices.count == Cord.segments * Cord.sides * 6)
            precondition(indices.allSatisfy { Int($0) < vertices.count })
            for (i, vertex) in vertices.enumerated() {
                precondition(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
                precondition(abs(simd_length(vertex.normal) - 1) < 0.0001)
                precondition(abs(simd_distance(vertex.position, points[i / Cord.sides]) - Cord.wireRadius) < 0.00001,
                             "Stretching must preserve wire thickness")
            }
        }
        let rest = Cord.vertices(end: Cord.restingPort, endLead: Cord.lead)
        _ = Cord.vertices(end: Cord.restingPort + [0, 0, 1], endLead: Cord.lead)
        let returned = Cord.vertices(end: Cord.restingPort, endLead: Cord.lead)
        precondition(zip(rest, returned).allSatisfy { $0.position == $1.position && $0.normal == $1.normal }, "Return must not accumulate drift")
        let begin = Date()
        for step in 0..<90 {
            _ = Cord.vertices(end: Cord.restingPort + [0, 0, Float(step) / 90], endLead: Cord.lead)
        }
        print("PASS: fixed/following sockets, rotation, coincident endpoints, topology, finite unit normals, constant wire thickness, drift-free return")
        print("Geometry generation: \(Date().timeIntervalSince(begin) / 90 * 1000) ms/frame on this Mac (not headset profiling)")
    }
}
