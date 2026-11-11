// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The pane whose subject is every agent's spending added up: the switch that
/// turns reading on, the recap buttons, and `TokenSpendView` over what
/// `SpendPaneModel` has read.
struct TokenSpendPane: View {
    let settings: AppSettings
    @Bindable var model: SpendPaneModel
    /// Opens the recap window on a period.
    let openRecap: @MainActor (Recap.Period) -> Void
    let scroll: ScrollViewProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Token spend")) {
                SettingsRow(
                    String.localized("Read local usage records"),
                    subtitle: String.localized("When enabled, scans local records and exports."),
                    symbol: "doc.text.magnifyingglass"
                ) {
                    Toggle(String.localized("Read local usage records"), isOn: Binding(
                        get: { settings.readsTokenSpend },
                        set: { settings.readsTokenSpend = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if settings.readsTokenSpend, model.isScanningSpend, let progress = model.spendProgress {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Reading \(progress.agent.displayName)…"), symbol: "hourglass") {
                        Text(verbatim: "\(progress.index + 1)/\(progress.total)")
                            .monospacedDigit()
                    }
                }
                if settings.readsTokenSpend {
                    SettingsRowDivider()
                    SettingsRow(
                        String.localized("Estimate all Claude products"),
                        subtitle: String.localized("Adds an estimate for chats, Cowork and other Claude products, from Claude Code's share of this week's usage as Anthropic reports it.")
                    ) {
                        Toggle(String.localized("Estimate all Claude products"), isOn: Binding(
                            get: { settings.estimatesAllClaudeProducts },
                            set: { settings.estimatesAllClaudeProducts = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        String.localized("Usage recaps"),
                        subtitle: String.localized("Shareable cards for a day, a week, a month or a year, from this Mac's records."),
                        symbol: "rectangle.stack"
                    ) {
                        // One way in. The window switches between day, week,
                        // month and year itself; a button for each period
                        // here was four buttons saying what its own control
                        // already says.
                        Button(String.localized("Open")) { openRecap(recapPeriod) }
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            if settings.readsTokenSpend {
                TokenSpendView(
                    summary: model.spend,
                    focus: $model.spendFocus,
                    focused: model.focusedSpend,
                    modelFocus: $model.selectedModel,
                    modelSummary: model.modelSpend,
                    noRecords: model.spendNoRecords,
                    hasReadLimitations: model.spendHasReadLimitations,
                    claudeShare: settings.estimatesAllClaudeProducts ? ClaudeProductShare.stored() : nil,
                    span: Binding(
                        get: { settings.spendSpan },
                        set: { settings.spendSpan = $0 }
                    ),
                    customDays: Binding(
                        get: { settings.spendCustomDays },
                        set: { settings.spendCustomDays = $0 }
                    ),
                    activity: model.spendActivity,
                    activityView: Binding(
                        get: { settings.spendActivityView },
                        set: { settings.spendActivityView = $0 }
                    ),
                    isLoading: model.isScanningSpend,
                    isSummarizing: model.summaryIsPending,
                    refresh: { model.spendRescan += 1 }
                )
            }
        }
        // A model opened under one agent means nothing under another,
        // so changing the agent drops back out of the model.
        .onChange(of: model.spendFocus) { _, _ in model.selectedModel = nil }
        .onChange(of: model.selectedModel) { old, new in
            // Entering the detail drops the reader to the top, or they
            // land in the middle of it when the model row was well down
            // the page. Returning puts them back at the model list.
            if new != nil {
                scroll.scrollTo("heading", anchor: .top)
            } else if old != nil {
                scroll.scrollTo("models", anchor: .top)
            }
        }
    }

    /// The period the recap button opens, which is the one the window would
    /// open on by itself (`RecapPeriods.defaultMonth`).
    private var recapPeriod: Recap.Period {
        RecapPeriods.defaultMonth(earliest: RecapPeriods.earliest(in: model.spendLedgers))
    }

}
