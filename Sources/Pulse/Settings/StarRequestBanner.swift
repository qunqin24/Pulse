// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The star request, once, at the top of the settings window
/// (`StarRequest`). Drawn like a settings group so it reads as part of the
/// window rather than as something laid over it.
struct StarRequestBanner: View {
    /// Hides the banner; the request is already spent.
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 15))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text(localized: "You have used Pulse for two weeks. If Pulse has been useful, a star on GitHub helps other people find it.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(String.localized("Star on GitHub")) {
                NSWorkspace.shared.open(StarRequest.repository)
                dismiss()
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(String.localized("Close"))
            .accessibilityLabel(String.localized("Close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.background)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

#Preview("Star request") {
    StarRequestBanner {}
        .padding(24)
        .frame(width: 680)
}
