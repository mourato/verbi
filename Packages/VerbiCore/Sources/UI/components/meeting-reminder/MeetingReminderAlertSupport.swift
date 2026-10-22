import AppKit
import SwiftUI

enum MeetingReminderAlertMetrics {
    static let outerPadding: CGFloat = 56
    static let cardMaxWidth: CGFloat = 880
    static let cardCornerRadius: CGFloat = 32
    static let cardPaddingVertical: CGFloat = 48
    static let cardPaddingHorizontal: CGFloat = 56
    static let columnSpacing: CGFloat = 56
    static let leftColumnSpacing: CGFloat = 18
    static let rightColumnSpacing: CGFloat = 14
    static let primaryCornerRadius: CGFloat = 16
    static let secondaryCornerRadius: CGFloat = 14
    static let snoozeDropdownWidth: CGFloat = 240
}

enum MeetingReminderAlertState {
    case upcoming
    case imminent
    case live
    case late

    static func compute(now: Date, start: Date) -> MeetingReminderAlertState {
        let interval = start.timeIntervalSince(now)
        if interval > 60 {
            return .upcoming
        }
        if interval > 0 {
            return .imminent
        }
        if interval > -300 {
            return .live
        }
        return .late
    }

    var dotKind: DotKind {
        switch self {
        case .upcoming, .imminent: .none
        case .live: .live
        case .late: .urgent
        }
    }

    enum DotKind {
        case none
        case live
        case urgent
    }

    func statusSuffix(now: Date, start: Date) -> String {
        let interval = start.timeIntervalSince(now)
        let absMinutes = max(0, Int(abs(interval) / 60))
        switch self {
        case .upcoming:
            return "meeting_reminder.overlay.status.in_minutes".localized(with: absMinutes)
        case .imminent:
            let seconds = max(0, Int(interval))
            if seconds > 5 {
                return "meeting_reminder.overlay.status.in_seconds".localized(with: seconds)
            }
            return "meeting_reminder.overlay.status.any_moment".localized
        case .live:
            if absMinutes == 0 {
                return "meeting_reminder.overlay.status.started_just_now".localized
            }
            return "meeting_reminder.overlay.status.started_minutes_ago".localized(with: absMinutes)
        case .late:
            return "meeting_reminder.overlay.status.you_are_late".localized(with: absMinutes)
        }
    }
}

struct MeetingReminderMeshBackdrop: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [
        Color(red: 0.79, green: 0.48, blue: 0.23),
        Color(red: 0.42, green: 0.29, blue: 0.54),
        Color(red: 0.23, green: 0.35, blue: 0.54)
    ]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                Color(red: 0.047, green: 0.047, blue: 0.063)

                meshBlob(color: colors[0], size: max(width, height) * 0.85)
                    .position(
                        x: animate ? width * 0.30 : width * 0.40,
                        y: animate ? height * 0.35 : height * 0.45
                    )
                    .animation(.easeInOut(duration: 22).repeatForever(autoreverses: true), value: animate)

                meshBlob(color: colors[1], size: max(width, height) * 0.75)
                    .position(
                        x: animate ? width * 0.70 : width * 0.60,
                        y: animate ? height * 0.65 : height * 0.55
                    )
                    .animation(.easeInOut(duration: 28).repeatForever(autoreverses: true), value: animate)

                meshBlob(color: colors[2], size: max(width, height) * 0.55, opacity: 0.7)
                    .position(
                        x: animate ? width * 0.45 : width * 0.55,
                        y: animate ? height * 0.50 : height * 0.45
                    )
                    .animation(.easeInOut(duration: 32).repeatForever(autoreverses: true), value: animate)
            }
            .compositingGroup()
            .onAppear {
                if !reduceMotion {
                    animate = true
                }
            }
        }
    }

    private func meshBlob(color: Color, size: CGFloat, opacity: Double = 0.85) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: color.opacity(opacity), location: 0),
                        .init(color: color.opacity(0), location: 0.65)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 60)
    }
}

struct MeetingReminderPulsingDot: View {
    let color: Color
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if !reduceMotion {
                    Circle()
                        .stroke(color.opacity(0.6), lineWidth: 2)
                        .scaleEffect(pulse ? 2.5 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)
                }
            }
            .onAppear {
                if !reduceMotion {
                    pulse = true
                }
            }
    }
}

struct MeetingReminderAvatarStack: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                MeetingReminderAvatar(initials: Self.initials(from: name), hue: Self.hue(for: name), fullName: name)
            }
        }
    }

    static func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "?"
        }
        let source: String = if trimmed.contains("@") {
            trimmed.split(separator: "@").first.map(String.init) ?? trimmed
        } else {
            trimmed
        }
        let parts = source.split(whereSeparator: { " ._-".contains($0) }).prefix(2)
        return String(parts.compactMap(\.first)).uppercased()
    }

    static func hue(for name: String) -> Double {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Double(hash % 360)
    }
}

private struct MeetingReminderAvatar: View {
    let initials: String
    let hue: Double
    let fullName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hue: hue / 360, saturation: 0.5, brightness: 0.55))
            Text(initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay {
            Circle()
                .stroke(Color(red: 0.078, green: 0.078, blue: 0.086), lineWidth: 2)
        }
        .accessibilityLabel(fullName)
    }
}

extension View {
    @ViewBuilder
    func meetingReminderClickCursor() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.link)
        } else {
            onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }
}
