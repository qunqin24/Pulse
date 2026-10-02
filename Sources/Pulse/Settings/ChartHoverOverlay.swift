// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Immediate inspection for the Settings charts. The whole plot is a target,
/// including the space above a short bar and the gaps between bars.
///
/// This belongs to the activating Settings window, not the non-key rail panel.
/// The caller supplies the actual bar centres so capped and uncapped bars pick
/// the same datum they draw, without a second copy of their spacing rules.
struct ChartHoverOverlay: View {
    struct Sample: Equatable {
        let x: CGFloat
        let title: String
        let tokens: Int
    }

    let samples: [Sample]
    @State private var hoveredIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear

                if let index = hoveredIndex, samples.indices.contains(index) {
                    let sample = samples[index]

                    Group {
                        Rectangle()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 1)
                            .offset(x: sample.x - 0.5)

                        Circle()
                            .fill(.tint)
                            .frame(width: 4, height: 4)
                            .position(x: sample.x, y: max(proxy.size.height - 2, 2))

                        TooltipPlacement(anchorX: sample.x) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sample.title)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(String.localized("\(TokenCount.short(sample.tokens)) tokens"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: .rect(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        }
                    }
                    // A tooltip must not become a new hover target under the
                    // pointer, or interfere with scrolling the containing pane.
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .onContinuousHover { phase in
                let index: Int?
                switch phase {
                case .active(let location):
                    index = selection(at: location, in: proxy.size)
                case .ended:
                    index = nil
                }
                // Moving within a column need not redraw or move its tooltip.
                if hoveredIndex != index { hoveredIndex = index }
            }
        }
        .accessibilityHidden(true)
        .onChange(of: samples) { _, _ in hoveredIndex = nil }
        .onDisappear { hoveredIndex = nil }
    }

    private func selection(at point: CGPoint, in size: CGSize) -> Int? {
        guard size.width > 0, size.height > 0,
              point.x >= 0, point.x <= size.width,
              point.y >= 0, point.y <= size.height else { return nil }
        return samples.indices.min {
            abs(samples[$0].x - point.x) < abs(samples[$1].x - point.x)
        }
    }

    /// Fit the label beside the selected column, flip at the right edge, and
    /// clamp inside the plot. A Layout measures the real localized text rather
    /// than guessing a width or writing measurement back into view state.
    /// Keeping it inside the plot also avoids the Settings card's clipping.
    private struct TooltipPlacement: Layout {
        let anchorX: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let tooltip = subviews.first else { return }
            let size = tooltip.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let gap: CGFloat = 10
            let preferredX = anchorX + gap + size.width <= bounds.width
                ? anchorX + gap
                : anchorX - gap - size.width
            let x = min(max(preferredX, 0), max(bounds.width - size.width, 0))
            tooltip.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
        }
    }
}
