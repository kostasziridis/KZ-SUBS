import SwiftUI

/// Goes through every suspect word in the whole video, one decision at a time.
struct SpellReviewView: View {

    @Environment(\.dismiss) private var dismiss

    @Bindable var model: SpellReviewViewModel
    /// Counted rather than flagged, so repeating the same action feels the same each
    /// time - a Bool would only fire on the change to true.
    @State private var corrections = 0
    @State private var keeps = 0
    /// Applies a correction to the project. Returns nothing: the caller owns the
    /// subtitles and this view only says what to change.
    var onCorrect: (SpellFinding, String) -> Void
    /// Moves the player to the subtitle a finding is in, so it can be heard.
    var onGoTo: (SpellFinding) -> Void

    var body: some View {
        NavigationStack {
            content
                .appBackground()
                .navigationTitle("Check spelling")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(AppTheme.accent)
                    }
                }
        }
        .preferredColorScheme(.dark)
        // A correction is a small success; keeping a word is just a choice.
        .sensoryFeedback(.success, trigger: corrections)
        .sensoryFeedback(.selection, trigger: keeps)
    }

    @ViewBuilder
    private var content: some View {
        if model.showsProgress {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(AppTheme.accent)
                Text("Checking every subtitle…")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.findings.isEmpty, model.hasChecked {
            allClear
        } else {
            list
        }
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.accent)
            Text("Every word is in the dictionary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("It cannot tell you whether the right word was used — only that each one exists.")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("\(model.count) words to look at")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(model.findings) { finding in
                    card(finding)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func card(_ finding: SpellFinding) -> some View {
        GlassCard(radius: AppTheme.controlRadius, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(finding.word)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .underline(true, pattern: .dot, color: .orange)

                    Spacer(minLength: 0)

                    Button {
                        onGoTo(finding)
                    } label: {
                        Label("\(finding.segmentNumber)", systemImage: "play.circle")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Go to subtitle \(finding.segmentNumber)"))
                    .tint(AppTheme.accent)
                    .foregroundStyle(AppTheme.accent)
                }

                // The word alone is not enough to judge it by.
                Text(finding.context)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)

                if finding.suggestions.isEmpty {
                    Text("No suggestions — edit it in the subtitle if it is wrong.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    FlowRow(spacing: 8) {
                        ForEach(finding.suggestions, id: \.self) { suggestion in
                            Button {
                                onCorrect(finding, suggestion)
                                model.remove(finding)
                                corrections += 1
                            } label: {
                                Text(suggestion)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background { Capsule().fill(AppTheme.accent.opacity(0.16)) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    model.keep(finding)
                    keeps += 1
                } label: {
                    Label("Keep as it is", systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}
