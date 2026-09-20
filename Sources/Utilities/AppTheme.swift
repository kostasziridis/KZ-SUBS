import SwiftUI

/// The visual language of the app in one place: near-black surfaces, a single blue
/// accent, generous corner radii.
enum AppTheme {

    // MARK: - Colour

    /// Near-black, not pure black: it keeps translucent materials readable.
    static let background = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let elevatedSurface = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color.accentColor
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.4)

    // MARK: - Shape

    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 16
    static let tileRadius: CGFloat = 14

    static func cardShape(_ radius: CGFloat = cardRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// A rounded, faintly translucent card - the app's standard container.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = AppTheme.cardRadius
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                AppTheme.cardShape(radius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        AppTheme.cardShape(radius)
                            .fill(AppTheme.elevatedSurface)
                    }
            }
            .overlay {
                AppTheme.cardShape(radius)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    /// The primary action appearance, applied to any label.
    ///
    /// Lives as a modifier rather than only a `ButtonStyle` because `PhotosPicker`
    /// is not a `Button` and cannot take one.
    func primaryActionAppearance(pressed: Bool = false) -> some View {
        self
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .fill(AppTheme.accent)
            }
            .opacity(pressed ? 0.75 : 1)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }
}

/// The app's primary action button: full width, accent filled.
///
/// A custom `ButtonStyle` gets no dimming from `.disabled` for free, so it reads the
/// environment itself - otherwise a disabled button looks fully tappable.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .primaryActionAppearance(pressed: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.18), value: isEnabled)
    }
}

/// The quieter companion to `PrimaryButtonStyle`.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                            .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension View {
    /// The app-wide backdrop.
    func appBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }
}
