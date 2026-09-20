import SwiftUI

/// A small key/value chip used for duration, resolution and similar facts.
struct InfoPill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(AppTheme.elevatedSurface)
        }
    }
}
