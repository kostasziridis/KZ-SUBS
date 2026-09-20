import SwiftUI

/// The single privacy line the app shows. No jargon, no model names.
struct PrivacyBadge: View {
    var text: String = "On-device • Nothing leaves your iPhone"

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .labelStyle(.titleAndIcon)
    }
}

/// The fuller privacy statement, used where there is room to explain.
struct PrivacyCard: View {
    var body: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Processed entirely on this iPhone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Your video and audio never leave this device.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PrivacyBadge()
        PrivacyCard()
    }
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
