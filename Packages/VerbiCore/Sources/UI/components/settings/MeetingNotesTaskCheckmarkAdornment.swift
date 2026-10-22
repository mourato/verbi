import AppKit

enum MeetingNotesTaskMarkerState: Int {
    case unchecked = 0
    case checked = 1
}

enum MeetingNotesTaskCheckmarkAdornment {
    static func draw(in rect: NSRect, state: MeetingNotesTaskMarkerState, accentColor: NSColor) {
        let lineWidth = max(1.6, round(rect.width * 0.13))
        let cornerRadius = max(3, rect.width * 0.3)
        let frameRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let framePath = NSBezierPath(roundedRect: frameRect, xRadius: cornerRadius, yRadius: cornerRadius)
        framePath.lineWidth = lineWidth
        accentColor.setStroke()
        framePath.stroke()

        guard state == .checked else { return }

        let innerInset = max(2.5, round(rect.width * 0.25))
        let innerRect = frameRect.insetBy(dx: innerInset, dy: innerInset)
        let innerCornerRadius = max(2, innerRect.width * 0.28)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerCornerRadius, yRadius: innerCornerRadius)
        accentColor.withAlphaComponent(0.28).setFill()
        innerPath.fill()
    }
}
