// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// A robot's colour as plain sRGB components, so its hue can be compared with
/// its neighbours' and its lightness checked against the panel.
struct RobotInk: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }

    /// `#RRGGBB`, as `RingTint` stores a colour; nil for anything else.
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = brightness - c
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// 0..<1 round the wheel.
    var hue: Double {
        let high = max(red, green, blue), low = min(red, green, blue), span = high - low
        guard span > 0 else { return 0 }
        let sector: Double = if high == red {
            ((green - blue) / span).truncatingRemainder(dividingBy: 6)
        } else if high == green {
            (blue - red) / span + 2
        } else {
            (red - green) / span + 4
        }
        let hue = sector / 6
        return hue < 0 ? hue + 1 : hue
    }

    var saturation: Double {
        let high = max(red, green, blue)
        return high > 0 ? (high - min(red, green, blue)) / high : 0
    }

    /// Whether it has a hue worth keeping apart from. A grey or a white has
    /// none, and is far from nothing on the wheel.
    var hasHue: Bool { saturation >= 0.15 }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func mixed(with other: RobotInk, by t: Double) -> RobotInk {
        RobotInk(red: red + (other.red - red) * t,
                 green: green + (other.green - green) * t,
                 blue: blue + (other.blue - blue) * t)
    }

    /// The least change that makes it stand 3:1 off the panel — towards
    /// white on the dark panel, towards black on the light one — so a dark
    /// brand stays visible on a black disc and a pale one on a light disc.
    /// Already legible, it is returned as it is.
    func legible(onDark dark: Bool) -> RobotInk {
        let target = dark ? RobotInk(red: 1, green: 1, blue: 1) : RobotInk(red: 0, green: 0, blue: 0)
        // The panel: black, or `PanelLight.fill`'s grey 0.97.
        let panel = dark ? 0.0 : RobotInk(red: 0.97, green: 0.97, blue: 0.97).luminance
        func contrast(_ ink: RobotInk) -> Double {
            let a = ink.luminance, b = panel
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        guard contrast(self) < Self.minimumContrast else { return self }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if contrast(mixed(with: target, by: mid)) < Self.minimumContrast { low = mid } else { high = mid }
        }
        return mixed(with: target, by: high)
    }

    static let minimumContrast = 3.0
}

extension Provider {
    /// The product's own colour, as `0xRRGGBB`, for the robot in its ring and
    /// nowhere else: the ring's colour means usage. Nil for a product whose
    /// mark is black and white — the robot then takes a colour from
    /// `RobotAutomatic.wheel`.
    var brandColour: UInt32? {
        if let profile { return profile.brandColour }
        switch handWritten {
        case .claudeCode: return 0xD97757
        case .deepSeek: return 0x4D6BFE
        case .volcengine: return 0x1664FF
        case .minimax: return 0xE8483F
        case .antigravity: return 0x4285F4
        case .glmCoding: return 0x3A7BF7
        case .kimiCode: return 0x7AA5FF
        // Xiaomi's own orange: MiMo is the parent brand's.
        case .xiaomiMiMo: return 0xFF6900
        // The blue end of its gradient.
        case .sub2api: return 0x3875F6
        case .qoder: return 0x2ADB5C
        case .stepFun: return 0x0160FF
        // Black and white marks. New API's gradient has no colour of its own
        // at either end.
        case .codex, .kiro, .cursor, .openCodeGo, .ollamaCloud, .zai, .copilot, .grok, .grokBot,
             .commandCode, .devin, .newAPI, .v2ex, .pulseExtension, nil:
            return nil
        }
    }
}

extension RobotAutomatic {
    /// The usage colours' hues on the dark panel (`Color.pulseGood`,
    /// `pulseCaution`, `pulseWarning`, `pulseExhausted` in UsageTint.swift).
    static let usageHues: [Double] = [(0.00, 0.90, 0.55), (1.00, 0.76, 0.15), (1.00, 0.31, 0.26), (0.85, 0.09, 0.13)]
        .map { RobotInk(red: $0.0, green: $0.1, blue: $0.2).hue }

    /// How far a wheel colour keeps from each usage colour's hue. Green's and
    /// amber's are wider: a yellow-green or a teal robot inside a green ring
    /// reads as part of the gauge (seen in rendered rails), and green is what
    /// most rings show most of the time.
    static let usageClearances: [Double] = [66.0 / 360, 50.0 / 360, 35.0 / 360, 35.0 / 360]

    /// Pulse's own colours for a robot whose product has none: hues a
    /// twenty-fourth of the wheel apart, **less those near green, amber and
    /// red** (`usageClearances`). Those mean how much of a limit is gone on this panel, and a
    /// robot Pulse coloured that way would read as a status nobody reported.
    /// A product's own colour is its own and is not held to this.
    /// What is left is the blue-to-magenta side of the wheel.
    static let wheel: [RobotInk] = (0..<24).map { Double($0) / 24 }
        .filter { hue in zip(usageHues, usageClearances).allSatisfy { hueDistance(hue, $0) >= $1 } }
        .map { RobotInk(hue: $0, saturation: 0.6, brightness: 0.95) }

    /// Round the wheel, 0...0.5.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    /// One colour per robot, in rail order.
    ///
    /// - A colour somebody chose comes first and is fixed.
    /// - Then the product's own colour, also fixed.
    /// - Every other robot takes a wheel colour not yet on the panel, as far
    ///   in hue as it can get from its neighbours and from every other colour
    ///   on the panel, a neighbour counting double: next to each other, two
    ///   close hues are what the eye compares.
    ///
    /// `chosen` says which colours were picked by hand, which are never
    /// adjusted for legibility (`RingTint`'s rule for a chosen colour).
    static func inks(for providers: [Provider], custom: [RobotInk?]) -> [(ink: RobotInk, chosen: Bool)] {
        let fixed: [RobotInk?] = providers.indices.map { index in
            custom[index] ?? providers[index].brandColour.map(RobotInk.init(rgb:))
        }
        var result = fixed
        var used = Set<Int>()

        func distance(_ hue: Double, _ others: [RobotInk?]) -> Double {
            let hues = others.compactMap { $0 }.filter(\.hasHue).map(\.hue)
            guard !hues.isEmpty else { return 1 }
            return hues.map { hueDistance(hue, $0) }.min() ?? 1
        }

        for index in result.indices where result[index] == nil {
            let neighbours = [index > 0 ? result[index - 1] : nil,
                              index + 1 < result.count ? result[index + 1] : nil]
            let free = wheel.indices.filter { !used.contains($0) }
            let candidates = free.isEmpty ? Array(wheel.indices) : free
            func score(_ i: Int) -> (Double, Double) {
                let near = distance(wheel[i].hue, neighbours)
                let all = distance(wheel[i].hue, result)
                return (min(near, all * 2), near)
            }
            let best = candidates.max { a, b in
                let scoreA = score(a), scoreB = score(b)
                // `max` keeps the last of equals; prefer the lower index.
                return scoreA < scoreB || (scoreA == scoreB && a > b)
            } ?? 0
            used.insert(best)
            result[index] = wheel[best]
        }

        return result.indices.map { (result[$0] ?? wheel[0], custom[$0] != nil) }
    }
}
