import simd

/// A fixed-turn spring around a bowed centreline, in the asset's Z-up coordinates.
enum TelephoneCordGeometry {
    static let segments = 384
    static let sides = 8
    static let turns: Float = 28
    static let wireRadius: Float = 0.0015
    static let basePort = SIMD3<Float>(0.780, 0.065, 0.8945)
    static let restingPort = SIMD3<Float>(0.786, 0.2165, 0.9775)
    static let handsetPort = restingPort - SIMD3<Float>(0.925, 0.184, 1.006)
    static let lead = SIMD3<Float>(-0.16, -0.07, -0.07)

    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    static var indices: [UInt32] {
        (0..<segments).flatMap { ring in
            (0..<sides).flatMap { side -> [UInt32] in
                let a = UInt32(ring * sides + side)
                let b = UInt32(ring * sides + (side + 1) % sides)
                let c = a + UInt32(sides)
                let d = b + UInt32(sides)
                return [a, b, c, b, d, c]
            }
        }
    }

    static func centers(end: SIMD3<Float>, endLead: SIMD3<Float>) -> [SIMD3<Float>] {
        let distance = simd_distance(basePort, end)
        let slack = min(1, simd_distance(basePort, restingPort) / max(distance, 0.001))
        let p1 = basePort + SIMD3<Float>(-0.16, -0.12, -0.065) * slack
        let p2 = end + endLead * slack
        // As the span grows, coil pitch increases and coil diameter contracts.
        let radius: Float = 0.0055 * sqrt(slack)
        var result: [SIMD3<Float>] = []
        var frame = SIMD3<Float>(0, 0, 1)
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let u = 1 - t
            let center = basePort * (u * u * u) + p1 * (3 * u * u * t)
                + p2 * (3 * u * t * t) + end * (t * t * t)
            let first = (p1 - basePort) * (3 * u * u)
            let second = (p2 - p1) * (6 * u * t)
            let third = (end - p2) * (3 * t * t)
            let derivative = first + second + third
            let tangent = normalized(derivative, fallback: [0, 1, 0])
            frame = perpendicular(to: tangent, previous: frame)
            let binormal = simd_cross(tangent, frame)
            // Straight leads meet both sockets exactly, with no offset from the coil.
            let edge = min(1, min(t, u) / 0.06)
            let envelope = edge * edge * (3 - 2 * edge)
            let phase = t * turns * 2 * Float.pi
            result.append(center + radius * envelope * (cos(phase) * frame + sin(phase) * binormal))
        }
        result[0] = basePort
        result[segments] = end
        return result
    }

    static func vertices(end: SIMD3<Float>, endLead: SIMD3<Float>) -> [Vertex] {
        let points = centers(end: end, endLead: endLead)
        var vertices: [Vertex] = []
        vertices.reserveCapacity((segments + 1) * sides)
        var frame = SIMD3<Float>(0, 0, 1)
        for i in points.indices {
            let tangent = normalized(points[min(i + 1, segments)] - points[max(0, i - 1)], fallback: [0, 1, 0])
            frame = perpendicular(to: tangent, previous: frame)
            let binormal = simd_cross(tangent, frame)
            for side in 0..<sides {
                let angle = Float(side) / Float(sides) * 2 * Float.pi
                let normal = cos(angle) * frame + sin(angle) * binormal
                vertices.append(Vertex(position: points[i] + wireRadius * normal, normal: normal))
            }
        }
        return vertices
    }

    private static func normalized(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        simd_length_squared(value) > 0.00000001 ? simd_normalize(value) : fallback
    }

    private static func perpendicular(to tangent: SIMD3<Float>, previous: SIMD3<Float>) -> SIMD3<Float> {
        let projected = previous - simd_dot(previous, tangent) * tangent
        if simd_length_squared(projected) > 0.000001 { return simd_normalize(projected) }
        let axis: SIMD3<Float> = abs(tangent.z) < 0.9 ? [0, 0, 1] : [0, 1, 0]
        return simd_normalize(simd_cross(tangent, axis))
    }
}
