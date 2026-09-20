import SwiftUI

/// Privacy, storage and version. Nothing technical, nothing to configure wrongly.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var usedBytes: Int64?
    @State private var isClearing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PrivacyCard()

                    storageCard

                    aboutCard

                    #if DEBUG
                    developerCard
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .appBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
            .task { await refreshStorage() }
        }
        .preferredColorScheme(.dark)
    }

    private var storageCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Storage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack {
                    Text("Used by KZ-SUBS")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    if let usedBytes {
                        Text(FileHelpers.formattedSize(usedBytes))
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .foregroundStyle(.white)
                    } else {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                }

                Divider().overlay(AppTheme.hairline)

                Button {
                    Task { await clearTemporaryFiles() }
                } label: {
                    HStack {
                        Label("Clear temporary files", systemImage: "trash")
                            .font(.footnote.weight(.medium))
                        Spacer()
                        if isClearing {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .tint(AppTheme.accent)
                .disabled(isClearing)

                Text("Your imported videos and projects are kept. Only working files are removed.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    private var aboutCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack {
                    Text("Version")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(Self.versionString)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white)
                }

                Text("No account. No cloud. No analytics.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    #if DEBUG
    /// Development only: a way to exercise the speech engine on a real device against
    /// a clip whose words we already know.
    private var developerCard: some View {
        NavigationLink {
            SpeechCheckView()
        } label: {
            GlassCard(radius: AppTheme.controlRadius, padding: 18) {
                HStack {
                    Label("Speech check", systemImage: "waveform.badge.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }
    #endif

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshStorage() async {
        let bytes = await Task.detached(priority: .utility) {
            StorageManager.usedBytes()
        }.value
        usedBytes = bytes
    }

    private func clearTemporaryFiles() async {
        isClearing = true
        await Task.detached(priority: .utility) {
            StorageManager.clearWorkingDirectory()
        }.value
        isClearing = false
        await refreshStorage()
    }
}

#Preview {
    SettingsView()
}
