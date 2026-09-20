import SwiftUI

/// The swatch row, with the system colour picker on the end.
///
/// The presets cover the colours people reach for; the picker is there for the brand
/// colour that is not on the list.
struct CaptionColorPalette: View {

    @Binding var selection: CaptionColor
    var supportsOpacity: Bool = false
    /// Applied to a preset before it is used, so a background swatch can be softened.
    var transform: (CaptionColor) -> CaptionColor = { $0 }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(CaptionColor.palette.enumerated()), id: \.offset) { _, colour in
                let resolved = transform(colour)

                Button {
                    selection = resolved
                } label: {
                    Circle()
                        .fill(colour.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().strokeBorder(
                                matches(resolved) ? AppTheme.accent : Color.white.opacity(0.25),
                                lineWidth: matches(resolved) ? 3 : 1
                            )
                        }
                }
                .buttonStyle(.plain)
            }

            ColorPicker(
                "Custom colour",
                selection: Binding(
                    get: { selection.color },
                    set: { selection = CaptionColor($0) }
                ),
                supportsOpacity: supportsOpacity
            )
            .labelsHidden()
            .frame(width: 30, height: 30)
        }
    }

    /// Compared on components rather than identity, since a picked colour is rebuilt
    /// from numbers each time.
    private func matches(_ colour: CaptionColor) -> Bool {
        abs(colour.red - selection.red) < 0.01
            && abs(colour.green - selection.green) < 0.01
            && abs(colour.blue - selection.blue) < 0.01
    }
}
