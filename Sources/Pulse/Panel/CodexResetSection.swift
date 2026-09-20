import SwiftUI

struct CodexResetSection: View {
    let event: CodexResetFeed.Event

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * PanelMetrics.scale) {
            Divider()
            Text(verbatim: event.title)
                .fontWeight(.semibold)
            if let schedule = event.schedule {
                Text(verbatim: schedule.label)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: DetailCardLayout.footnoteFontSize, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
