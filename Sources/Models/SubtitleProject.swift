import Foundation
import CoreGraphics

/// A saved piece of work: one video plus its subtitles, language and styling.
///
/// File locations are persisted as *names*, not absolute paths. iOS gives an app a
/// new container path after some updates and restores, so an archived absolute URL
/// goes stale; resolving the name against the current container keeps projects alive.
struct SubtitleProject: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date

    var name: String
    var videoURL: URL
    var thumbnailURL: URL?

    var duration: TimeInterval
    var pixelSize: CGSize

    var language: AppLanguage
    var subtitles: [SubtitleSegment]
    var captionStyle: CaptionStyle

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String,
        videoURL: URL,
        thumbnailURL: URL? = nil,
        duration: TimeInterval,
        pixelSize: CGSize,
        language: AppLanguage = .automatic,
        subtitles: [SubtitleSegment] = [],
        captionStyle: CaptionStyle = .default
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.pixelSize = pixelSize
        self.language = language
        self.subtitles = subtitles
        self.captionStyle = captionStyle
    }

    init(asset: VideoAsset, language: AppLanguage = .automatic) {
        self.init(
            name: (asset.filename as NSString).deletingPathExtension,
            videoURL: asset.url,
            thumbnailURL: asset.thumbnailURL,
            duration: asset.duration,
            pixelSize: asset.pixelSize,
            language: language
        )
    }

    /// True once subtitles exist for this project.
    var hasSubtitles: Bool { !subtitles.isEmpty }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, name
        case videoFileName, thumbnailFileName
        case duration, width, height
        case language, subtitles, captionStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        name = try c.decode(String.self, forKey: .name)

        let videoFileName = try c.decode(String.self, forKey: .videoFileName)
        videoURL = StorageManager.videosDirectory.appendingPathComponent(videoFileName)

        if let thumbName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName) {
            thumbnailURL = StorageManager.thumbnailsDirectory.appendingPathComponent(thumbName)
        } else {
            thumbnailURL = nil
        }

        duration = try c.decode(TimeInterval.self, forKey: .duration)
        pixelSize = CGSize(
            width: try c.decode(Double.self, forKey: .width),
            height: try c.decode(Double.self, forKey: .height)
        )
        language = try c.decode(AppLanguage.self, forKey: .language)
        subtitles = try c.decode([SubtitleSegment].self, forKey: .subtitles)
        captionStyle = try c.decode(CaptionStyle.self, forKey: .captionStyle)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(name, forKey: .name)
        try c.encode(videoURL.lastPathComponent, forKey: .videoFileName)
        try c.encodeIfPresent(thumbnailURL?.lastPathComponent, forKey: .thumbnailFileName)
        try c.encode(duration, forKey: .duration)
        try c.encode(Double(pixelSize.width), forKey: .width)
        try c.encode(Double(pixelSize.height), forKey: .height)
        try c.encode(language, forKey: .language)
        try c.encode(subtitles, forKey: .subtitles)
        try c.encode(captionStyle, forKey: .captionStyle)
    }
}
