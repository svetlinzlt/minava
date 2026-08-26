import Foundation
@testable import MinavaCore

enum Fixtures {
    /// The repository root, found by walking up from this file.
    ///
    /// The tests read the real files in `clinical/` on purpose. A test that reads a copy
    /// proves the copy is consistent, which is not the thing worth proving.
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }()

    static func data(at relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    static func json(at relativePath: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try data(at: relativePath))
        return object as? [String: Any] ?? [:]
    }

    /// A plan with the filler numbers used in the mockups: 4 in, 2 hold, 6 out, five times.
    /// They have no clinical standing and exist only so the tests have something to run on.
    static func plan(
        entry: Double = 0.6,
        inhale: Double = 4,
        holdIn: Double? = 2,
        exhale: Double = 6,
        cycles: Int = 5,
        firstCycleFactor: Double? = nil,
        exit: Double = 4,
        tempo: (min: Double, max: Double)? = nil
    ) -> BreathingPlan {
        var phases: [BreathingPlan.Phase] = [
            BreathingPlan.Phase(type: .inhale, duration: inhale, hapticIntensity: .rising)
        ]
        if let holdIn {
            phases.append(BreathingPlan.Phase(type: .holdIn, duration: holdIn,
                                              hapticIntensity: .steady))
        }
        phases.append(BreathingPlan.Phase(type: .exhale, duration: exhale,
                                          hapticIntensity: .falling))

        return BreathingPlan(
            entry: BreathingPlan.Entry(duration: entry),
            cycle: BreathingPlan.Cycle(phases: phases),
            repeat: BreathingPlan.Repeat(cycles: cycles, firstCycleFactor: firstCycleFactor),
            exit: BreathingPlan.Exit(duration: exit),
            userTempo: tempo.map { BreathingPlan.UserTempo(min: $0.min, max: $0.max) })
    }
}
