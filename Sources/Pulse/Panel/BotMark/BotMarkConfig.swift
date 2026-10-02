// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The per-frame configuration the engine reads, assembled the way the web
/// component assembles it: the state's own table first, then the caller's
/// overrides.
struct BotMarkConfig {
    var shape = "blob"
    var expressionPool: [Int] = [0, 8]
    var expressionCadence: (Double, Double) = (9000, 16000)
    var blinkCadence: (Double, Double)? = (6000, 14000)

    var tempo = 1.0
    var motionScale = 1.0
    /// Multipliers on the **rotation** and the **squash**, for the moods that
    /// have to be noticed at ring size.
    ///
    /// Upstream amplitudes are tuned for a bot at 96pt and up; at 25pt a state
    /// like `working` rocks about a degree and rises a point, which is
    /// invisible. Neither of these touches translation: a body turning or
    /// pumping stays inside its canvas, where a bigger bob runs straight out
    /// of the margin the viewBox has for it.
    ///
    /// **Squash is the one that carries it.** The rotation spring runs at 5Hz
    /// against a signal at 1.6, so it is a low-pass filter — measured, a 2.4×
    /// target took the swing from 1.1° only to 2.6°, and more would tilt the
    /// body over rather than wobble it. The squash spring runs at 10 and
    /// follows the same rhythm, so the same exaggeration lands.
    var rotationScale = 1.0

    /// Amplifies how far the body departs from its resting height, not the
    /// height itself: 1 leaves the upstream's 2% pump alone, 5 makes it 10%.
    var squashScale = 1.0
    var gazeScale = 1.0
    var eyeOpen = 1.0
    var eyeScale = 1.0
    var headX = 0.0
    var headY = 0.0
    var headRotation = 0.0
    var scaleX = 1.0
    var scaleY = 1.0

    var pointer = false
    var flipX = false
    /// A standing horizontal lean on the eyes, added to the autonomous gaze
    /// rather than replacing it — so the mark still glances around, from a
    /// head that is turned. In the upstream's units, where its own gaze swings
    /// ±15 and the pointer reaches ±22.
    var gazeBias = 0.0
    /// Which one-shot effect this state morphs into. Nil is the plain
    /// character.
    var morph: String?
    /// Particles are a thumbnail's first casualty upstream; same here.
    var particlesEnabled = true
    /// The canvas width in points. Upstream widens the viewBox for a morph
    /// only on small canvases, where the effect would otherwise be clipped.
    var viewWidth = 96.0

    /// `--fg` upstream: the body. Default is the upstream near-black.
    var color = Color(red: 0.043, green: 0.043, blue: 0.043)
    /// `--bg` upstream: the eyes.
    var eyeColor = Color.white
    var badgeColor = Color(red: 0.114, green: 0.608, blue: 0.941)
    var badgeScale = 1.0

    static func forState(_ state: BotMarkStateInfo, shape: String = "blob") -> BotMarkConfig {
        var config = BotMarkConfig()
        config.shape = shape
        config.expressionPool = state.expressionPool
        config.expressionCadence = state.expressionCadence
        config.blinkCadence = state.blinkCadence
        config.morph = state.morph
        return config
    }
}
