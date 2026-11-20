import CoreGraphics

public enum SettingsFormLayoutPolicy {
    public static let defaultOuterGutter: CGFloat = SettingsContentSurface.horizontalGutter

    public static func contentWidth(
        availableWidth: CGFloat,
        outerGutter: CGFloat = defaultOuterGutter
    ) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        return max(0, availableWidth - (max(0, outerGutter) * 2))
    }
}
