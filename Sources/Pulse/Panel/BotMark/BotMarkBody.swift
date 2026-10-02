// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The body a mark wears.
///
/// The upstream carries eighteen of these, all sampled to the same 96-point
/// ring so any one blends into any other. Which one a ring uses is the
/// reader's choice and nothing else's: it is not a reading, and it is not
/// dealt out — **every mark is round until somebody changes it**, because a
/// rail whose shapes were assigned by the app would be saying something with
/// them, and there is nothing to say.
///
/// A raw-value enum rather than the bare strings the engine takes, so a
/// stored choice that no longer exists falls back rather than drawing nothing.
enum BotMarkBody: String, CaseIterable, Identifiable, Sendable {
    case blob
    case pebble
    case bean
    case egg
    case squircle
    case tablet
    case capsule
    case cylinder
    case hex
    case gem
    case crystal
    case wedge
    case shield
    case dome
    case arch
    case cloud
    case teardrop
    case leaf

    static let `default` = BotMarkBody.blob

    var id: String { rawValue }

    /// The id the engine's shape table is keyed by.
    var shape: String { rawValue }

    /// The name in the settings picker. Localized like the other settings
    /// enums, and rendered with `Text(body.title)`.
    var title: String {
        switch self {
        case .blob: .localized("Blob")
        case .pebble: .localized("Pebble")
        case .bean: .localized("Bean")
        case .egg: .localized("Egg")
        case .squircle: .localized("Squircle")
        case .tablet: .localized("Tablet")
        case .capsule: .localized("Capsule")
        case .cylinder: .localized("Cylinder")
        case .hex: .localized("Hexagon")
        case .gem: .localized("Gem")
        case .crystal: .localized("Crystal")
        case .wedge: .localized("Wedge")
        case .shield: .localized("Shield")
        case .dome: .localized("Dome")
        case .arch: .localized("Arch")
        case .cloud: .localized("Cloud")
        case .teardrop: .localized("Teardrop")
        case .leaf: .localized("Leaf")
        }
    }
}
