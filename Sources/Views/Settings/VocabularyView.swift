import SwiftUI

/// Words to teach the app before it listens.
///
/// The one place in the app that improves a transcription before it happens rather
/// than after: a name written here is a name that comes out spelled right, instead of
/// one corrected in every video.
struct VocabularyView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var store = VocabularyStore.shared
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                entryField
                list
            }
            .appBackground()
            .navigationTitle("Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Adding

    private var entryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Names the app would otherwise guess at — people, places, brands, anything it has not heard before.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 10) {
                TextField("Add a word", text: $draft)
                    .font(.body)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isTyping)
                    .onSubmit(commit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.elevatedSurface)
                    }

                Button("Add", action: commit)
                    .font(.footnote.weight(.semibold))
                    .tint(AppTheme.accent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || store.isFull)
            }

            if store.isFull {
                Text("That is as many as the app can use at once. Remove one to add another.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Used the next time you make subtitles. Words near the top count most.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(20)
    }

    private func commit() {
        guard store.add(draft) else { return }
        draft = ""
        isTyping = true
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        if store.terms.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text("No words yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.terms, id: \.self) { term in
                    Text(term)
                        .font(.body)
                        .foregroundStyle(.white)
                        .listRowBackground(AppTheme.elevatedSurface)
                }
                .onDelete { store.remove(atOffsets: $0) }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }
}

#if DEBUG
#Preview {
    VocabularyView()
}
#endif
