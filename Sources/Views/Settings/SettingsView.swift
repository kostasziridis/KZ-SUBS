import SwiftUI

/// Privacy, storage and version. Nothing technical, nothing to configure wrongly.
struct SettingsView: View {

    @State private var showsAcknowledgements = false

    @Environment(\.dismiss) private var dismiss
    @State private var usedBytes: Int64?
    @State private var isClearing = false
    @State private var modelChoice: ModelManager.Choice = ModelManager.choice

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PrivacyCard()

                    accuracyCard

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
        .sheet(isPresented: $showsAcknowledgements) { acknowledgements }
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

    /// Lets the user trade speed for accuracy. Every option is multilingual, so Greek
    /// keeps working whichever they pick.
    private var accuracyCard: some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Subtitle accuracy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("A more accurate model takes longer and downloads once.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                ForEach(ModelManager.Choice.allCases) { choice in
                    Button {
                        guard choice != modelChoice else { return }
                        modelChoice = choice
                        ModelManager.choice = choice
                        Task { await refreshStorage() }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: choice == modelChoice ? "largecircle.fill.circle" : "circle")
                                .font(.body)
                                .foregroundStyle(choice == modelChoice ? AppTheme.accent : AppTheme.tertiaryText)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(choice.displayName)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(choice.approximateSize)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }
                                Text(choice.detail)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if modelChoice != .balanced {
                    Label(
                        "Switching downloads a new model the next time you make subtitles.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
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

                Divider().overlay(AppTheme.hairline)

                // Required by the licence the Greek dictionary is used under, and
                // right in any case: it is someone else's work.
                Button {
                    showsAcknowledgements = true
                } label: {
                    HStack {
                        Text("Acknowledgements")
                            .font(.footnote)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .tint(AppTheme.accent)
            }
        }
    }

    private var acknowledgements: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Greek spelling dictionary")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(Self.greekDictionaryNotice)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .appBackground()
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsAcknowledgements = false }
                        .tint(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Left in English on purpose: it names a licence and its authors.
    private static let greekDictionaryNotice = """
        el_GR 0.9 by Steve Stavropoulos, based on earlier work by Evripidis Papakostas,         with contributions from Γιώργος Γέγος and Nick Demou.

        Used under the Mozilla Public License 1.1. The dictionary is tri-licensed         MPL 1.1 / GPL 2.0 / LGPL 2.1. Source: http://elspell.math.upatras.gr
        """

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
