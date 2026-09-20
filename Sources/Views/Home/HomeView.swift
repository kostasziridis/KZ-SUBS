import PhotosUI
import SwiftUI

/// The entry point: start a new video, or return to recent work.
struct HomeView: View {

    @Environment(AppState.self) private var appState
    @State private var model = HomeViewModel()
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroCard
                    recentProjects
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .appBackground()
            .navigationTitle("Subtitles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.white)
                }
            }
            .navigationDestination(item: $model.importedAsset) { asset in
                VideoImportView(asset: asset)
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
            .overlay {
                if model.isImporting {
                    importingOverlay
                }
            }
            .alert(
                model.error?.errorDescription ?? "Something went wrong",
                isPresented: Binding(
                    get: { model.error != nil },
                    set: { if !$0 { model.error = nil } }
                ),
                presenting: model.error
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { error in
                Text(error.recoverySuggestion ?? "")
            }
            .onChange(of: model.pickerItem) { _, newValue in
                model.handlePickerSelection(newValue)
            }
        }
        .tint(AppTheme.accent)
    }

    // MARK: - Hero

    private var heroCard: some View {
        GlassCard(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Create subtitles")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Generate captions privately on your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                PhotosPicker(
                    selection: $model.pickerItem,
                    matching: .videos,
                    preferredItemEncoding: .current,
                    photoLibrary: .shared()
                ) {
                    Label("Choose Video", systemImage: "video.badge.plus")
                        .primaryActionAppearance()
                }
                .disabled(model.isImporting)

                PrivacyBadge()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Recent

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Projects")
                .font(.headline)
                .foregroundStyle(.white)

            if appState.isLoadingProjects {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if appState.projects.isEmpty {
                emptyProjects
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(appState.projects) { project in
                        ProjectCard(project: project)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await appState.delete(project) }
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private var emptyProjects: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(AppTheme.tertiaryText)

            Text("No projects yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text("Videos you caption will appear here.")
                .font(.footnote)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background {
            AppTheme.cardShape(AppTheme.controlRadius)
                .fill(AppTheme.elevatedSurface.opacity(0.5))
        }
    }

    // MARK: - Importing

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Adding video…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(30)
            .background {
                AppTheme.cardShape(AppTheme.controlRadius)
                    .fill(.ultraThinMaterial)
            }
        }
        .transition(.opacity)
    }
}

#Preview("Empty") {
    HomeView()
        .environment(AppState.previewEmpty)
        .preferredColorScheme(.dark)
}

#Preview("With projects") {
    HomeView()
        .environment(AppState.previewPopulated)
        .preferredColorScheme(.dark)
}
