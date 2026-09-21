import SwiftUI

/// How subtitles are drawn over the video.
///
/// Deliberately independent of the transcription data: the same segments can be
/// restyled endlessly without touching timings or text.
struct CaptionStyle: Codable, Equatable, Hashable {

    // MARK: - Choices

    enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
        /// White bold text with a hard shadow. The safe default over any footage.
        case classic
        /// White bold text on a black rounded slab.
        case boxed
        /// Oversized heavy text, the look short-form video uses.
        case bold
        /// Word-by-word recolouring, timed to the speech.
        case karaoke
        /// A filled box travelling behind each word as it is spoken.
        case spotlight
        /// Small, light, unobtrusive.
        case minimal

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classic: return String(localized: "Classic")
            case .boxed: return String(localized: "Boxed")
            case .bold: return String(localized: "Bold")
            case .karaoke: return String(localized: "Karaoke")
            case .spotlight: return String(localized: "Spotlight")
            case .minimal: return String(localized: "Minimal")
            }
        }
    }

    enum FontDesign: String, Codable, CaseIterable, Identifiable, Sendable {
        case standard, rounded, serif, monospaced

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .standard: return String(localized: "Standard")
            case .rounded: return String(localized: "Rounded")
            case .serif: return String(localized: "Serif")
            case .monospaced: return String(localized: "Mono")
            }
        }

        var design: Font.Design {
            switch self {
            case .standard: return .default
            case .rounded: return .rounded
            case .serif: return .serif
            case .monospaced: return .monospaced
            }
        }
    }

    enum Weight: String, Codable, CaseIterable, Identifiable, Sendable {
        case regular, medium, semibold, bold, heavy, black

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .regular: return String(localized: "Regular")
            case .medium: return String(localized: "Medium")
            case .semibold: return String(localized: "Semibold")
            case .bold: return String(localized: "Bold weight")
            case .heavy: return String(localized: "Heavy")
            case .black: return String(localized: "Black")
            }
        }

        var fontWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }
    }

    /// What sits behind the text so it stays readable over the footage.
    enum Background: String, Codable, CaseIterable, Identifiable, Sendable {
        case shadow, block, roundedBlock, none

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .shadow: return String(localized: "Shadow")
            case .block: return String(localized: "Block")
            case .roundedBlock: return String(localized: "Rounded")
            case .none: return String(localized: "None")
            }
        }
    }

    /// What marks the word currently being spoken.
    enum SpokenWordEffect: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        /// Recolours the word.
        case colour
        /// Puts a filled box behind it, the look short-form video uses.
        case box

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: return String(localized: "Off")
            case .colour: return String(localized: "Colour")
            case .box: return String(localized: "Box")
            }
        }
    }

    enum TextAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
        case leading, center, trailing

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .leading: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .trailing: return "text.alignright"
            }
        }

        var swiftUI: SwiftUI.TextAlignment {
            switch self {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }

        var frameAlignment: Alignment {
            switch self {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }
    }

    // MARK: - Properties

    var preset: Preset
    var fontDesign: FontDesign
    var weight: Weight
    /// Font size against a 1080-point-tall reference frame, so the same style looks
    /// identical in a small preview and in a 4K export.
    var referenceFontSize: Double
    var textColor: CaptionColor
    /// The colour the currently spoken word takes when karaoke is on.
    var highlightColor: CaptionColor
    var background: Background
    var backgroundColor: CaptionColor
    /// Where the caption's centre sits, 0...1 across the frame.
    var horizontalPosition: Double
    /// Where the caption's centre sits, 0 = top, 1 = bottom.
    var verticalPosition: Double
    var alignment: TextAlignment
    var isUppercased: Bool
    /// Karaoke-style highlighting. Needs word timings; falls back to plain text without.
    var spokenWordEffect: SpokenWordEffect
    /// Fill behind the spoken word when the effect is `.box`.
    var spokenWordBackgroundColor: CaptionColor
    /// At most this many words on screen at once. Nil keeps whole lines.
    var maxWordsOnScreen: Int?

    var highlightsSpokenWord: Bool { spokenWordEffect != .none }

    // MARK: - Presets

    static let `default` = CaptionStyle.preset(.classic)

    static func preset(_ preset: Preset) -> CaptionStyle {
        // Capitals are never forced by a preset: it is a choice the user makes.
        switch preset {
        case .classic:
            return CaptionStyle(
                preset: .classic, fontDesign: .standard, weight: .bold,
                referenceFontSize: 56, textColor: .white, highlightColor: .yellow,
                background: .shadow, backgroundColor: .shadow,
                verticalPosition: 0.86, alignment: .center,
                isUppercased: false, spokenWordEffect: .none, spokenWordBackgroundColor: .blue, maxWordsOnScreen: nil
            )
        case .boxed:
            return CaptionStyle(
                preset: .boxed, fontDesign: .standard, weight: .bold,
                referenceFontSize: 54, textColor: .white, highlightColor: .yellow,
                background: .roundedBlock, backgroundColor: .black.withOpacity(0.72),
                verticalPosition: 0.86, alignment: .center,
                isUppercased: false, spokenWordEffect: .none, spokenWordBackgroundColor: .blue, maxWordsOnScreen: nil
            )
        case .bold:
            return CaptionStyle(
                preset: .bold, fontDesign: .rounded, weight: .black,
                referenceFontSize: 82, textColor: .white, highlightColor: .yellow,
                background: .shadow, backgroundColor: .shadow,
                verticalPosition: 0.72, alignment: .center,
                isUppercased: false, spokenWordEffect: .none, spokenWordBackgroundColor: .blue, maxWordsOnScreen: nil
            )
        case .karaoke:
            return CaptionStyle(
                preset: .karaoke, fontDesign: .rounded, weight: .black,
                referenceFontSize: 78, textColor: .white, highlightColor: .mint,
                background: .shadow, backgroundColor: .shadow,
                verticalPosition: 0.72, alignment: .center,
                isUppercased: false, spokenWordEffect: .colour, spokenWordBackgroundColor: .mint, maxWordsOnScreen: nil
            )
        case .spotlight:
            return CaptionStyle(
                preset: .spotlight, fontDesign: .rounded, weight: .black,
                referenceFontSize: 78, textColor: .white, highlightColor: .white,
                background: .shadow, backgroundColor: .shadow,
                verticalPosition: 0.72, alignment: .center,
                isUppercased: false, spokenWordEffect: .box, spokenWordBackgroundColor: .hotPink, maxWordsOnScreen: 4
            )
        case .minimal:
            return CaptionStyle(
                preset: .minimal, fontDesign: .standard, weight: .medium,
                referenceFontSize: 44, textColor: .white, highlightColor: .white,
                background: .none, backgroundColor: .black.withOpacity(0),
                verticalPosition: 0.9, alignment: .center,
                isUppercased: false, spokenWordEffect: .none, spokenWordBackgroundColor: .blue, maxWordsOnScreen: nil
            )
        }
    }

    /// Scales `referenceFontSize` to whatever frame the captions are drawn in.
    func fontSize(forFrameHeight height: Double) -> Double {
        guard height > 0 else { return referenceFontSize }
        return referenceFontSize * (height / 1080.0)
    }

    // MARK: - Codable

    /// Decoded field by field with fallbacks so a project saved by an earlier build,
    /// which knew fewer options, still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let preset = (try? c.decode(Preset.self, forKey: .preset)) ?? .classic
        let fallback = CaptionStyle.preset(preset)

        self.preset = preset
        fontDesign = (try? c.decode(FontDesign.self, forKey: .fontDesign)) ?? fallback.fontDesign
        weight = (try? c.decode(Weight.self, forKey: .weight)) ?? fallback.weight
        referenceFontSize = (try? c.decode(Double.self, forKey: .referenceFontSize)) ?? fallback.referenceFontSize
        textColor = (try? c.decode(CaptionColor.self, forKey: .textColor)) ?? fallback.textColor
        highlightColor = (try? c.decode(CaptionColor.self, forKey: .highlightColor)) ?? fallback.highlightColor
        background = (try? c.decode(Background.self, forKey: .background)) ?? fallback.background
        backgroundColor = (try? c.decode(CaptionColor.self, forKey: .backgroundColor)) ?? fallback.backgroundColor
        verticalPosition = (try? c.decode(Double.self, forKey: .verticalPosition)) ?? fallback.verticalPosition
        horizontalPosition = (try? c.decode(Double.self, forKey: .horizontalPosition)) ?? fallback.horizontalPosition
        alignment = (try? c.decode(TextAlignment.self, forKey: .alignment)) ?? fallback.alignment
        isUppercased = (try? c.decode(Bool.self, forKey: .isUppercased)) ?? fallback.isUppercased
        spokenWordBackgroundColor = (try? c.decode(CaptionColor.self, forKey: .spokenWordBackgroundColor))
            ?? fallback.spokenWordBackgroundColor
        maxWordsOnScreen = try? c.decodeIfPresent(Int.self, forKey: .maxWordsOnScreen)

        if let effect = try? c.decode(SpokenWordEffect.self, forKey: .spokenWordEffect) {
            spokenWordEffect = effect
        } else {
            // Projects from before the box option stored a plain on/off flag.
            let legacy = (try? c.decode(Bool.self, forKey: .highlightsSpokenWord)) ?? false
            spokenWordEffect = legacy ? .colour : fallback.spokenWordEffect
        }
    }

    /// Written explicitly because `CodingKeys` carries a legacy key with no property
    /// behind it, which stops the compiler synthesising this.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset, forKey: .preset)
        try c.encode(fontDesign, forKey: .fontDesign)
        try c.encode(weight, forKey: .weight)
        try c.encode(referenceFontSize, forKey: .referenceFontSize)
        try c.encode(textColor, forKey: .textColor)
        try c.encode(highlightColor, forKey: .highlightColor)
        try c.encode(background, forKey: .background)
        try c.encode(backgroundColor, forKey: .backgroundColor)
        try c.encode(verticalPosition, forKey: .verticalPosition)
        try c.encode(horizontalPosition, forKey: .horizontalPosition)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(isUppercased, forKey: .isUppercased)
        try c.encode(spokenWordEffect, forKey: .spokenWordEffect)
        try c.encode(spokenWordBackgroundColor, forKey: .spokenWordBackgroundColor)
        try c.encodeIfPresent(maxWordsOnScreen, forKey: .maxWordsOnScreen)
    }

    private enum CodingKeys: String, CodingKey {
        case preset, fontDesign, weight, referenceFontSize, textColor, highlightColor
        case background, backgroundColor, verticalPosition, horizontalPosition, alignment, isUppercased
        case spokenWordEffect, spokenWordBackgroundColor, maxWordsOnScreen
        /// Read for backward compatibility only; no longer written.
        case highlightsSpokenWord
    }

    init(
        preset: Preset, fontDesign: FontDesign, weight: Weight, referenceFontSize: Double,
        textColor: CaptionColor, highlightColor: CaptionColor, background: Background,
        backgroundColor: CaptionColor, verticalPosition: Double, alignment: TextAlignment,
        horizontalPosition: Double = 0.5,
        isUppercased: Bool, spokenWordEffect: SpokenWordEffect, spokenWordBackgroundColor: CaptionColor,
        maxWordsOnScreen: Int? = nil
    ) {
        self.preset = preset
        self.fontDesign = fontDesign
        self.weight = weight
        self.referenceFontSize = referenceFontSize
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.background = background
        self.backgroundColor = backgroundColor
        self.verticalPosition = verticalPosition
        self.horizontalPosition = horizontalPosition
        self.alignment = alignment
        self.isUppercased = isUppercased
        self.spokenWordEffect = spokenWordEffect
        self.spokenWordBackgroundColor = spokenWordBackgroundColor
        self.maxWordsOnScreen = maxWordsOnScreen
    }
}
