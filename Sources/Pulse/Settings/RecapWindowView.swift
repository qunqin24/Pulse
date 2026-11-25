// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The recap window: the deck one card at a time on the left, and on the
/// right the period, the price, the privacy switch and the ways out.
///
/// The cards are drawn live, scaled down from their 1080 × 1920 points; what
/// is exported is the same view rendered at full size (`RecapExport`). The
/// window itself follows the system's light or dark — only the cards are paper.
struct RecapWindowView: View {
    @Bindable var model: RecapWindowModel
    let settings: AppSettings
    /// Takes the person to the Token spend pane, where reading is switched on.
    let openTokenSpend: () -> Void

    @State private var priceText = ""
    @FocusState private var priceFocused: Bool
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @State private var isExporting = false
    /// The share button's own view, which the system's share sheet anchors to.
    @State private var shareAnchor = ViewBox()

    var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            sidebar
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.background)
        }
        .frame(minWidth: 780, minHeight: 620)
        // Copy and money follow the language and the currency without a
        // relaunch, and nothing observes a function call — see
        // `Docs/development.md`.
        .id("\(settings.language.rawValue)-\(settings.moneyIdentity)")
        .onAppear { priceText = RecapPrice.text(settings.recapMonthlyPrice) }
        .onChange(of: settings.readsTokenSpend) { model.start() }
        .onChange(of: settings.recapMonthlyPrice) { priceText = RecapPrice.text(settings.recapMonthlyPrice) }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        switch model.phase {
        case .needsReading:
            message(
                symbol: "chart.bar",
                title: String.localized("The recap needs Token spend"),
                detail: String.localized("Turn on Token spend reading to build it."),
                action: (String.localized("Open Token spend"), openTokenSpend)
            )
        case .loading:
            loading
        case .failed:
            message(
                symbol: "exclamationmark.triangle",
                title: String.localized("The records could not be read."),
                detail: nil,
                action: (String.localized("Retry"), { model.start() })
            )
        case .ready:
            if let deck = model.deck, !deck.cards.isEmpty {
                viewer(deck)
            } else if model.isBuilding {
                ProgressView().controlSize(.small)
            } else {
                message(
                    symbol: "tray",
                    title: String.localized("No records for \(model.period.title)"),
                    detail: String.localized("Nothing in this Mac's usage records falls in this period."),
                    action: nil
                )
            }
        }
    }

    private func message(
        symbol: String, title: String, detail: String?, action: (title: String, run: () -> Void)?
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action.title, action: action.run)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 340)
        .padding(24)
    }

    /// The read, honestly: which store it is on and how far through the list,
    /// and how long the first one can take. A bar only once there is a number
    /// to put on it.
    private var loading: some View {
        VStack(spacing: 10) {
            if let progress = model.readProgress {
                ProgressView(value: Double(progress.index), total: Double(max(progress.total, 1)))
                    .frame(width: 220)
                Text(localized: "Reading \(progress.agent)…")
                    .font(.system(size: 13))
                Text(verbatim: "\(progress.index + 1)/\(progress.total)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
                Text(localized: "Reading…")
                    .font(.system(size: 13))
            }
            Text(localized: "The first read of a long history can take a minute or two.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .padding(.top, 4)
        }
        .padding(24)
    }

    /// One card, scaled to fit, with the way to the one before and after.
    private func viewer(_ deck: RecapDeck) -> some View {
        let current = model.currentCard(in: deck)
        let index = deck.cards.firstIndex(of: current) ?? 0
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                pagerButton("chevron.left", label: String.localized("Previous page"), enabled: index > 0) {
                    model.step(-1, in: deck)
                }

                GeometryReader { geometry in
                    let size = RecapRenderer.cardSize
                    let scale = max(min(geometry.size.width / size.width, geometry.size.height / size.height), 0.05)
                    RecapCardView(deck: deck, card: current)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                pagerButton("chevron.right", label: String.localized("Next page"), enabled: index < deck.cards.count - 1) {
                    model.step(1, in: deck)
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(deck.cards, id: \.self) { card in
                        Circle()
                            .fill(card == current ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .onTapGesture { model.card = card }
                    }
                }
                // The count printed on the cards themselves: the poster is not
                // one of the numbered stories, so it is named instead.
                Text(verbatim: deck.page(of: current).map { "\($0.number) / \($0.count)" } ?? String.localized("Overview"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
    }

    private func pagerButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            section(String.localized("Period")) {
                Picker("", selection: Binding(
                    get: { model.kind },
                    set: { model.selectKind($0) }
                )) {
                    Text(localized: "Day").tag(Recap.Period.Kind.day)
                    Text(localized: "Week").tag(Recap.Period.Kind.week)
                    Text(localized: "Month").tag(Recap.Period.Kind.month)
                    Text(localized: "Year").tag(Recap.Period.Kind.year)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(String.localized("Period"))

                // The list, and a step either way beside it: a year of days
                // is a long menu to scroll for the one before.
                HStack(spacing: 4) {
                    Picker("", selection: Binding(
                        get: { model.period },
                        set: { model.select($0) }
                    )) {
                        ForEach(model.offered, id: \.self) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(String.localized("Period"))

                    periodStepButton("chevron.left", label: String.localized("Earlier"), direction: -1)
                    periodStepButton("chevron.right", label: String.localized("Later"), direction: 1)
                }
            }

            section(String.localized("Monthly price")) {
                HStack(spacing: 6) {
                    Text(verbatim: "$")
                        .foregroundStyle(.secondary)
                    // As wide as the largest price it takes ("10,000.00"),
                    // not the column: a full-width field put "200" a column
                    // away from its "$".
                    TextField("", text: $priceText)
                        .textFieldStyle(.roundedBorder)
                        .focused($priceFocused)
                        .onSubmit { commitPrice() }
                        .onChange(of: priceFocused) { if !priceFocused { commitPrice() } }
                        .accessibilityLabel(String.localized("Monthly price"))
                        .frame(width: 96)
                    Spacer(minLength: 0)
                }
                Text(localized: "Only used for the payback card. Leave it empty to leave that card out.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(String.localized("Privacy")) {
                Toggle(isOn: Binding(
                    get: { settings.recapHidesProjects },
                    set: { settings.recapHidesProjects = $0 }
                )) {
                    Text(localized: "Hide project names")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            exportSection
        }
        .padding(18)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Four buttons of one width, whatever the language makes of their labels.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    exportButton(String.localized("Save image")) { run { await save(all: false) } }
                    exportButton(String.localized("Save all")) { run { await save(all: true) } }
                }
                GridRow {
                    exportButton(String.localized("Copy image")) { copy() }
                    exportButton(String.localized("Share image")) { share() }
                        .background(ViewAnchor(box: shareAnchor))
                }
            }
        }
        .disabled(!hasDeck || isExporting)
    }

    private func exportButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }

    private var hasDeck: Bool { model.deck.map { !$0.cards.isEmpty } ?? false }

    private func periodStepButton(_ symbol: String, label: String, direction: Int) -> some View {
        Button { model.stepPeriod(direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .disabled(model.neighbour(direction) == nil)
        .help(label)
        .accessibilityLabel(label)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    // MARK: - Actions

    /// Takes what is in the field: nothing clears the price, a positive amount
    /// sets it, and anything else goes back to what was kept.
    private func commitPrice() {
        switch RecapPrice.entry(priceText) {
        case .none:
            settings.recapMonthlyPrice = nil
            priceText = ""
        case .amount(let amount):
            settings.recapMonthlyPrice = amount
            priceText = RecapPrice.text(amount)
        case .refused:
            priceText = RecapPrice.text(settings.recapMonthlyPrice)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        isExporting = true
        Task {
            await work()
            isExporting = false
        }
    }

    /// The deck as it stands after the price field has been taken: typing a
    /// price and pressing a button straight away must export the payback card.
    private func exportableDeck() -> RecapDeck? {
        commitPrice()
        return model.deck.flatMap { $0.cards.isEmpty ? nil : $0 }
    }

    private func save(all: Bool) async {
        guard let deck = exportableDeck() else { return }
        let window = shareAnchor.view?.window
        let outcome = all
            ? await RecapExport.saveAll(deck, from: window)
            : await RecapExport.save(model.currentCard(in: deck), of: deck, from: window)
        show(outcome)
    }

    private func copy() {
        guard let deck = exportableDeck() else { return }
        show(RecapExport.copy(model.currentCard(in: deck), of: deck))
    }

    private func share() {
        guard let deck = exportableDeck(), let anchor = shareAnchor.view else { return }
        show(RecapExport.share(model.currentCard(in: deck), of: deck, from: anchor))
    }

    /// A line under the buttons for a moment: what happened, if the system did
    /// not already say so itself.
    private func show(_ outcome: RecapExport.Outcome) {
        let text: String? = switch outcome {
        case .saved: .localized("Saved")
        case .copied: .localized("Copied")
        case .failed: .localized("Couldn't make the image.")
        case .presented, .cancelled: nil
        }
        noteTask?.cancel()
        withAnimation { note = text }
        guard text != nil else { return }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { note = nil }
        }
    }
}

/// A view reference the SwiftUI side can hand to AppKit: the share sheet needs
/// a view to anchor to, and a save panel a window to hang from.
final class ViewBox {
    weak var view: NSView?
}

private struct ViewAnchor: NSViewRepresentable {
    let box: ViewBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

#if DEBUG
#Preview("Recap window") {
    RecapWindowView(
        model: .preview(
            settings: AppSettings(), phase: .ready, period: .month(year: 2026, month: 9),
            recap: RecapSamples.month(), earliest: nil
        ),
        settings: AppSettings(),
        openTokenSpend: {}
    )
    .frame(width: 900, height: 780)
}

#Preview("Recap window · reading off") {
    RecapWindowView(
        model: .preview(settings: AppSettings(), phase: .needsReading, period: .month(year: 2026, month: 9)),
        settings: AppSettings(),
        openTokenSpend: {}
    )
    .frame(width: 900, height: 780)
}
#endif
