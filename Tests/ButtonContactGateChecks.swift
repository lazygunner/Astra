@main
struct ButtonContactGateChecks {
    static func main() {
        var gate = ButtonContactGate()
        precondition(gate.update(candidate: "1", stillInsideHeld: false) == "1")
        for _ in 0..<100 {
            precondition(gate.update(candidate: "1", stillInsideHeld: true) == nil)
        }
        precondition(gate.update(candidate: nil, stillInsideHeld: true) == nil)
        precondition(gate.update(candidate: "1", stillInsideHeld: true) == nil)
        precondition(gate.update(candidate: "2", stillInsideHeld: false) == nil)
        precondition(gate.update(candidate: nil, stillInsideHeld: false) == nil)
        precondition(gate.held == nil)
        precondition(gate.update(candidate: "2", stillInsideHeld: false) == "2")
        print("PASS: one action per contact, jitter margin, sliding suppression, release/repress")
    }
}
