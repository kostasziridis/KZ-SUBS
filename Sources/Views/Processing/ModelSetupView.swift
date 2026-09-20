import SwiftUI

/// Explains the one-time setup before anything is downloaded.
///
/// Shown only when no model is on the device yet: dropping a several-hundred-megabyte
/// download on someone with no warning is not acceptable, and the fact that it happens
/// once is the part that makes it reasonable.
struct ModelSetupView: View {

    @Environment(AppRouter.self) private var router

    let asset: VideoAsset
    let language: AppLanguage

    @State private var choice: ModelManager.Choice = ModelManager.choice

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                choices
                privacyCard
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("One-time setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.accent)

            Text("Download the speech model")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Subtitles are made on your iPhone, so the model that understands speech has to live here too. You only do this once.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var choices: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose how accurate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                ForEach(ModelManager.Choice.allCases) { option in
                    Button {
                        choice = option
                        ModelManager.choice = option
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: option == choice ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(option == choice ? AppTheme.accent : AppTheme.tertiaryText)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(option.displayName)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(option.approximateSize)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }
                                Text(option.detail)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(AppTheme.hairline)

                Label("Setup takes \(choice.estimatedSetupTime) on Wi-Fi", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var privacyCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "wifi.slash")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Then it works offline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("After this download your videos never need the internet again, and never leave this iPhone.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                router.push(.processing(asset: asset, language: language))
            } label: {
                Label("Download and continue", systemImage: "arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                router.popToRoot()
            } label: {
                Text("Not now")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ModelSetupView(asset: .sample, language: .greek)
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
#endif
