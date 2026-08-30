import SwiftUI

/// A titled group of settings rows, drawn as one rounded card.
///
/// This is the shape the whole settings window is built from: a small caption
/// above a card, and inside the card a stack of rows divided by hairlines.
struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(.background)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

/// One line inside a `SettingsGroup`: a label on the left, its control on the
/// right, and an optional explanation underneath the label.
struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }
}

enum SettingsLayout {
    /// A ceiling for the controls on the right of a row, not a fixed size.
    ///
    /// A macOS `Picker` sizes itself to its longest option and cannot be made
    /// to fill a frame, so this caps how wide one may get — a menu holding
    /// "Weekly limit · GPT-5.3-Codex-Spark" truncates instead of towering over
    /// its neighbours, and the full text is still there when it opens. Pair it
    /// with `alignment: .trailing`: a `Picker` centres itself in whatever
    /// frame it's given, which would leave it short of the row's edge while a
    /// plain `Button` reaches it.
    static let controlWidth: CGFloat = 180
}

/// Hairline between rows. Inset to match the rows' own padding, the way
/// macOS's grouped lists do it.
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}
