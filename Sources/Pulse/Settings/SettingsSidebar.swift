// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The source list: the panes in sections, then every account, narrowed by the
/// search the shell holds.
///
/// The shell sets the column's width and the search field on this view rather
/// than here: both are properties of the split view's sidebar column.
struct SettingsSidebar: View {
    let settings: AppSettings
    @Bindable var navigation: SettingsNavigation
    /// Narrows the sidebar. Sixteen providers plus every added account is a
    /// list that scrolls on any window worth opening. Held by the shell so a
    /// language change, which rebuilds the split view, does not clear it.
    let search: String

    var body: some View {
        List(selection: $navigation.pane) {
            if SettingsPane.panel.contains(where: matches) || matches(.spend) {
                Section(String.localized("Panel")) {
                    ForEach(SettingsPane.panel.filter(matches), id: \.self) { row($0) }
                    // Above the accounts, not below them. Eighteen
                    // provider rows is more than a sidebar shows at once,
                    // and a pane whose whole subject is "all of them
                    // together" was landing under the fold — reachable
                    // only by scrolling past the thing it summarises.
                    if matches(.spend) { row(.spend) }
                }
            }

            // Above the accounts for the same reason Token spend is: under
            // twenty-odd provider rows these were below the fold, and they
            // are the panes a person opens Settings for.
            if SettingsPane.application.contains(where: matches) {
                Section(String.localized("Application")) {
                    ForEach(SettingsPane.application.filter(matches), id: \.self) { row($0) }
                }
            }

            // What is switched on, first and together: with seventy-odd
            // providers, the handful somebody actually uses were a scroll
            // through the alphabet away. Rail order, both kinds.
            let enabled = matchingProviderAccounts.filter(settings.isEnabled)
            if !enabled.isEmpty {
                Section(String.localized("Enabled")) {
                    ForEach(enabled) { account in
                        row(.account(account))
                    }
                }
            }

            // The rest, subscriptions and API accounts apart, each in rail
            // order: a sidebar that disagreed with the thing it configures
            // is its own small confusion. An enabled account is not listed
            // again — two rows with one selection tag highlight together.
            // See `Provider.Billing`.
            ForEach(Provider.Billing.allCases, id: \.self) { billing in
                let accounts = matchingProviderAccounts.filter {
                    $0.provider.billing == billing && !settings.isEnabled($0)
                }
                if !accounts.isEmpty {
                    Section(billing.sectionTitle) {
                        ForEach(accounts) { account in
                            row(.account(account))
                        }
                    }
                }
            }

            // Apart from the accounts, as programs somebody added rather
            // than services Pulse ships: the list says which is which
            // before any pane is opened.
            if matches(.extensions) || !matchingExtensionAccounts.isEmpty {
                Section(String.localized("Extensions")) {
                    if matches(.extensions) { row(.extensions) }
                    ForEach(matchingExtensionAccounts) { account in
                        row(.account(account))
                    }
                }
            }

            // Rarely visited, so below the accounts: out of the way of the
            // panes above, and still one scroll away.
            if SettingsPane.trailing.contains(where: matches) {
                Section {
                    ForEach(SettingsPane.trailing.filter(matches), id: \.self) { row($0) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if isSearching, matchingAccounts.isEmpty,
               !(SettingsPane.panel + [.spend, .extensions] + SettingsPane.application + SettingsPane.trailing).contains(where: matches) {
                Text(localized: "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the sidebar is being narrowed to, or nothing.
    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !query.isEmpty }

    /// Accounts whose name the search matches, in rail order.
    ///
    /// Matched against the provider's name **as well as** the user's label, not
    /// instead of it. A second Claude subscription called "工作" is still a
    /// Claude Code account, and typing the product name is the obvious way to
    /// look for it — `title(_:)` alone would only know the label.
    private var matchingAccounts: [AccountKey] {
        guard isSearching else { return settings.orderedAccounts }
        return settings.orderedAccounts.filter {
            matches(title(.account($0))) || matches($0.provider.displayName)
        }
    }

    private var matchingProviderAccounts: [AccountKey] {
        matchingAccounts.filter { $0.provider != .pulseExtension }
    }

    private var matchingExtensionAccounts: [AccountKey] {
        matchingAccounts.filter { $0.provider == .pulseExtension }
    }

    /// By the pane's name, or by the name of any setting on it: with the
    /// panel's settings spread over several panes, "proxy" has to find the
    /// one proxy is on rather than nothing.
    private func matches(_ pane: SettingsPane) -> Bool {
        guard isSearching else { return true }
        return matches(title(pane)) || pane.searchTerms.contains(where: matches)
    }

    /// Case- and accent-insensitive, and localized: `localizedStandardContains`
    /// is what Finder searches with, so "z.ai" finds Z.ai and a stray accent
    /// doesn't lose a row.
    private func matches(_ text: String) -> Bool {
        text.localizedStandardContains(query)
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(title(pane))
        } icon: {
            switch pane {
            case .account(let account):
                LobeIconView(provider: account.provider, size: 14,
                             iconData: settings.pulseExtension(for: account)?.iconData)
            default:
                Image(systemName: pane.symbol)
            }
        }
        .labelStyle(SidebarRowLabelStyle())
        .tag(pane)
    }

    private func title(_ pane: SettingsPane) -> String {
        pane.title(in: settings)
    }
}

/// A sidebar row whose icon is the text's colour (black, white in dark
/// mode), not the accent colour a source list tints its icons with: two
/// dozen blue marks down the list read as links rather than as places.
///
/// Laid out here rather than recoloured. A `foregroundStyle` on the icon does
/// not reach past the sidebar's own label style, and `listItemTint` held only
/// for the rows on screen when the window opened — rows scrolled into view
/// later were blue again.
private struct SidebarRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Measured against the system's row: icon centred 12pt in, title
        // 30pt in, so the text starts where it did before.
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(.primary)
                .frame(width: 24)
            configuration.title
        }
    }
}
