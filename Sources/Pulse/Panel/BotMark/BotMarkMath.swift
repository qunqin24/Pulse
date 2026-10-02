// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A single spring-damper value, integrated at a fixed step.
///
/// Every bit of the mark's motion is one of these: the bob, the squash, the
/// eyelid, the gaze. Nothing is a keyframe, so a state arriving half-way
/// through another one carries on from wherever the motion actually was.
struct BotMarkSpring {
    var value: Double
    var velocity: Double = 0
    var target: Double

    init(_ value: Double) {
        self.value = value
        self.target = value
    }

    /// `frequency` is how eager it is; `damping` 1 is critical, below 1
    /// overshoots and settles.
    mutating func step(frequency: Double, damping: Double, delta: Double) {
        velocity += (-2 * damping * frequency * velocity
                     - frequency * frequency * (value - target)) * delta
        value += velocity * delta
        if !value.isFinite || !velocity.isFinite {
            value = target
            velocity = 0
        }
    }
}

/// The mark's own arithmetic, ported from the upstream `math.js`.
///
/// **A namespace rather than free functions.** Names like `clamp`, `mix` and
/// `random` are exactly the ones a later file in this app would want for
/// something else, and a module-wide `random(_:_:)` that quietly shadows
/// nothing today is a collision waiting for the next patch.
enum BotMath {
    /// The physics substep. Frame time is divided into steps no longer than
    /// this, so the springs behave the same at 30fps as at 120.
    static let fixedStep = 1.0 / 120.0

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }

    static func random(_ low: Double, _ high: Double) -> Double {
        low >= high ? low : Double.random(in: low..<high)
    }

    static func cubicInOut(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }

    static func cubicOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    static func backOut(_ value: Double) -> Double {
        1 + 2.70158 * pow(value - 1, 3) + 1.70158 * pow(value - 1, 2)
    }

    static func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    /// JavaScript's `((value % 1) + 1) % 1`: always in `0..<1`, where Swift's
    /// own remainder keeps the sign of the dividend.
    static func unitRemainder(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }
}
