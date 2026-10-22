import AppKit

extension FloatingRecordingIndicatorViewUtilities {
    static func promptIconImage(
        symbolName: String,
        size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> NSImage {
        let fallbackName = "doc.text"
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: promptIconSize(for: size), weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

        let rawImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil)
            ?? NSImage()
        let configured = rawImage.withSymbolConfiguration(symbolConfig) ?? rawImage
        configured.isTemplate = false
        return configured
    }

    static func languageFlagImage(
        _ emoji: String,
        size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> NSImage {
        emojiImage(emoji, pointSize: languageFlagPointSize(for: size))
    }

    private static func promptIconSize(for _: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        14
    }

    private static func languageFlagPointSize(for _: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        13
    }

    private static func emojiImage(_ emoji: String, pointSize: CGFloat) -> NSImage {
        let imageSize = NSSize(width: 24, height: 24)
        let image = NSImage(size: imageSize)
        image.lockFocus()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize),
            .paragraphStyle: paragraphStyle
        ]

        let attributed = NSAttributedString(string: emoji, attributes: attributes)
        let drawRect = NSRect(
            x: 0,
            y: (imageSize.height - pointSize) / 2,
            width: imageSize.width * 1.06,
            height: pointSize * 1.06
        )
        attributed.draw(in: drawRect)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
