/// A contact is one press, regardless of the number of hand tracking updates.
/// Require an empty gap before allowing a new press, including sliding to a neighbour.
struct ButtonContactGate {
    private(set) var held: String?

    mutating func update(candidate: String?, stillInsideHeld: Bool) -> String? {
        if held != nil {
            if candidate == nil && !stillInsideHeld { held = nil }
            return nil
        }
        held = candidate
        return candidate
    }
}
