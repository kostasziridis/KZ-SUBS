import SwiftUI

/// A colour that can be stored in a project file.
///
/// SwiftUI's `Color` is not `Codable`, and a project has to survive a relaunch, so
/// styles keep their own sRGB components.
struct CaptionColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    func withOpacity(_ value: Double) -> CaptionColor {
        CaptionColor(red: red, green: green, blue: blue, opacity: value)
    }

    static let white = CaptionColor(red: 1, green: 1, blue: 1)
    static let black = CaptionColor(red: 0, green: 0, blue: 0)
    static let shadow = CaptionColor(red: 0, green: 0, blue: 0, opacity: 0.85)
    static let yellow = CaptionColor(red: 1, green: 0.84, blue: 0.04)
    static let mint = CaptionColor(red: 0.29, green: 0.95, blue: 0.68)
    static let hotPink = CaptionColor(red: 1, green: 0.19, blue: 0.53)
    static let blue = CaptionColor(red: 0.039, green: 0.518, blue: 1)
    static let red = CaptionColor(red: 1, green: 0.23, blue: 0.19)
    static let orange = CaptionColor(red: 1, green: 0.58, blue: 0)

    /// The swatches offered wherever a colour is picked.
    static let palette: [CaptionColor] = [
        .white, .yellow, .orange, .red, .hotPink, .mint, .blue, .black
    ]
}
