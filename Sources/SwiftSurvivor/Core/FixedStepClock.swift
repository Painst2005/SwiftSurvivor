import Foundation

/// Deterministic clock shared by future SDL gameplay loops.
/// Rendering may run at any refresh rate while simulation advances in fixed steps.
struct FixedStepClock {
    let fixedDelta: Double
    let maxFrameDelta: Double
    let maxStepsPerFrame: Int
    private(set) var accumulator: Double = 0
    private(set) var realTime: Double = 0
    private(set) var gameTime: Double = 0
    private(set) var timeScale: Double = 1

    init(fixedDelta: Double = 1.0 / 60.0, maxFrameDelta: Double = 0.25, maxStepsPerFrame: Int = 8) {
        self.fixedDelta = fixedDelta
        self.maxFrameDelta = maxFrameDelta
        self.maxStepsPerFrame = maxStepsPerFrame
    }

    mutating func setTimeScale(_ scale: Double) {
        timeScale = min(4, max(0, scale))
    }

    mutating func advance(realDelta: Double, update: (Double) -> Void) {
        let clamped = min(max(0, realDelta), maxFrameDelta)
        realTime += clamped
        accumulator += clamped * timeScale
        var steps = 0
        while accumulator >= fixedDelta && steps < maxStepsPerFrame {
            update(fixedDelta)
            accumulator -= fixedDelta
            gameTime += fixedDelta
            steps += 1
        }
        // A window stall must never trigger an unbounded catch-up spiral.
        if steps == maxStepsPerFrame && accumulator > fixedDelta {
            accumulator = fixedDelta
        }
    }

    var interpolationAlpha: Double { accumulator / fixedDelta }
}
