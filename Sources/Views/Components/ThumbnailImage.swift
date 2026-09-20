import SwiftUI

/// Loads a thumbnail from disk without blocking the main thread, and fades it in.
struct ThumbnailImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(AppTheme.elevatedSurface)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        // Read bytes off the main thread; decoding a small JPEG on main is cheap.
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value

        guard let data, let loaded = UIImage(data: data) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = loaded
        }
    }
}
