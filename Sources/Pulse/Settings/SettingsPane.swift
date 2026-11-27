// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Provider.Billing {
    /// What the sidebar and the chooser head each group with.
    var sectionTitle: String {
        switch self {
        case .subscription: .localized("Subscriptions")
        case .api: .localized("API and pay-as-you-go")
        }
    }
}

enum SettingsPane: Hashable {
    /// The panel's own settings, split by what they are about. They were one
    /// "General" pane of thirty-odd rows until that was too long to find
    /// anything in.
    case appearance
    case rings
    case placement
    /// Pulse as an app: launch, menu bar, shortcuts, language.
    case general
    case notifications
    case network
    /// Features still being tuned, off until switched on.
    case experimental
    case account(AccountKey)
    /// Every agent's spending added up — a pane whose subject is not a
    /// provider, which is why it sits outside the accounts rather than inside
    /// one of them.
    case spend
    case about
    case integrations
    /// Where extensions live and which were found. Each one found is an
    /// `.account` of its own; this is the list.
    case extensions

    /// The sidebar's fixed rows, section by section. `panel` and
    /// `application` sit above the accounts; `trailing` below them.
    static let panel: [SettingsPane] = [.appearance, .rings, .placement]
    static let application: [SettingsPane] = [.general, .notifications, .network, .experimental]
    static let trailing: [SettingsPane] = [.integrations, .about]

    var title: String {
        switch self {
        case .appearance: .localized("Appearance")
        case .rings: .localized("Rings and figures")
        case .placement: .localized("Position and behavior")
        case .general: .localized("General")
        case .notifications: .localized("Notifications")
        case .network: .localized("Network and refresh")
        case .experimental: .localized("Experimental")
        // Not "Usage history", which is what a provider's own card is called.
        // Two panes with one name is two places to look for one thing.
        case .spend: .localized("Token spend")
        // Brand names, left as they are in every language.
        // A fallback: the view titles these from the account's own label.
        case .account(let account): account.provider.displayName
        case .about: .localized("About")
        case .integrations: .localized("Developer integrations")
        case .extensions: .localized("Manage extensions")
        }
    }

    /// Only meaningful for the panes drawn with an SF Symbol; provider panes
    /// use the provider's own mark instead.
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .rings: "circle.dashed"
        case .placement: "rectangle.righthalf.inset.filled"
        case .general: "slider.horizontal.3"
        case .notifications: "bell"
        case .network: "network"
        case .experimental: "flask"
        case .spend: "chart.bar"
        case .account: "square.stack.3d.up"
        case .about: "info.circle"
        case .integrations: "terminal"
        case .extensions: "puzzlepiece.extension"
        }
    }

    /// The names of the settings on the pane, so the sidebar's search finds
    /// the pane a setting is on. Only the panes whose rows are fixed; an
    /// account is found by its name.
    var searchTerms: [String] {
        switch self {
        case .appearance:
            [.localized("Size"), .localized("Spacing"), .localized("Round ends"), .localized("Progress bars"),
             .localized("Panel colour"), .localized("Liquid Glass"), .localized("Transparency"), .localized("Ring activity animation")]
        case .rings:
            [.localized("Percentages at the side"), .localized("Percentages across"), .localized("Figures beside the rings"),
             .localized("Figure above the ring"), .localized("Show what's left"),
             .localized("Second limit inside the ring"), .localized("Time until reset"),
             .localized("Time ring direction"), .localized("Turn red at"), .localized("Alert colour when docked")]
        case .placement:
            [.localized("Show floating panel"), .localized("Hide in full screen"),
             .localized("Hide until pointed at"), .localized("Position"),
             .localized("Snap to screen edges"), .localized("Follow the active display"), .localized("Order")]
        case .general:
            [.localized("Open at login"), .localized("Hide menu bar icon"), .localized("Shortcuts"),
             .localized("Interface language")]
        case .notifications:
            [.localized("Warn at"), .localized("When a limit comes back"), .localized("When a reading stops arriving"),
             .localized("When a service is down"), .localized("When a recap is ready")]
        case .network:
            [.localized("Check every"), .localized("Proxy")]
        case .extensions:
            [.localized("Extensions"), .localized("Look again")]
        case .experimental:
            [.localized("Liquid docking")]
        case .account, .spend, .about, .integrations:
            []
        }
    }
}

extension SettingsPane {
    /// The pane's name. An account's is the user's own label, which the pane
    /// itself cannot reach — two subscriptions to the same plan are told apart
    /// by nothing else.
    func title(in settings: AppSettings) -> String {
        if case .account(let account) = self { return settings.label(for: account) }
        return title
    }
}
