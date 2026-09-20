import SwiftUI

/// One row in Recent Projects: thumbnail, name, duration and when it was last touched.
struct ProjectCard: View {
    let project: SubtitleProject

    var body: some View {
        HStack(spacing: 14) {
            ThumbnailImage(url: project.thumbnailURL)
                .frame(width: 92, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text(TimecodeFormatter.duration(project.duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(.black.opacity(0.55))
                        }
                        .padding(5)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(TimecodeFormatter.relative(project.updatedAt).capitalizedFirst)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)

                HStack(spacing: 6) {
                    Text(project.language.displayName)
                    if project.hasSubtitles {
                        Text("· \(project.subtitles.count) subtitles")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(12)
        .background {
            AppTheme.cardShape(AppTheme.controlRadius)
                .fill(AppTheme.elevatedSurface)
        }
        .overlay {
            AppTheme.cardShape(AppTheme.controlRadius)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        }
    }
}

private extension String {
    /// "2 hours ago" -> "2 hours ago"; "yesterday" -> "Yesterday".
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + String(dropFirst())
    }
}

#Preview {
    ProjectCard(project: .sample)
        .padding()
        .appBackground()
        .preferredColorScheme(.dark)
}
