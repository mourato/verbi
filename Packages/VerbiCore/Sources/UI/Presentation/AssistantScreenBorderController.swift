import AppKit
import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class AssistantScreenBorderController {
    private var borderWindow: NSWindow?
    private let settingsStore: AppSettingsStore
    private var hideTask: Task<Void, Never>?

    public private(set) var isVisible = false

    private enum Constants {
        static let animationDuration: TimeInterval = 0.2
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public init(settingsStore: AppSettingsStore = .shared) {
        self.settingsStore = settingsStore
    }

    deinit {
        hideTask?.cancel()
        hideTask = nil
        borderWindow = nil
    }

    public func show() {
        guard !isVisible else { return }

        if isRunningTests {
            isVisible = true
            return
        }

        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame

        let window = makeOrReuseWindow(frame: screenFrame)

        let borderColor = Color(settingsStore.assistantBorderColor.nsColor)
        let borderStyle = settingsStore.assistantBorderStyle
        let borderWidth = max(CGFloat(settingsStore.assistantBorderWidth), 1)
        let glowRadius = max(CGFloat(settingsStore.assistantGlowSize), 0)

        let borderView = AssistantScreenBorderView(
            borderWidth: borderWidth,
            glowRadius: glowRadius,
            borderColor: borderColor,
            style: borderStyle
        )
        window.contentView = NSHostingView(rootView: borderView)

        if isRunningTests || prefersReducedMotion {
            window.alphaValue = 1
            window.orderFront(nil)
        } else {
            window.alphaValue = 0
            window.orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.animationDuration
                window.animator().alphaValue = 1
            }
        }

        isVisible = true
    }

    public func hide() {
        guard let window = borderWindow else { return }

        hideTask?.cancel()
        hideTask = nil

        if !isVisible || isRunningTests || prefersReducedMotion {
            window.orderOut(nil)
            window.alphaValue = 1
            isVisible = false
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.animationDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                window?.orderOut(nil)
                window?.alphaValue = 1
                self?.hideTask = nil
            }
        }

        isVisible = false
    }

    private func makeOrReuseWindow(frame: NSRect) -> NSWindow {
        if let borderWindow {
            borderWindow.setFrame(frame, display: false)
            return borderWindow
        }

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        borderWindow = window
        return window
    }
}

private struct AssistantScreenBorderView: View {
    let borderWidth: CGFloat
    let glowRadius: CGFloat
    let borderColor: Color
    let style: AssistantBorderStyle

    private var shouldPrintChanges: Bool {
        ProcessInfo.processInfo.environment["MA_SWIFTUI_PRINT_CHANGES"] == "1"
    }

    var body: some View {
        #if DEBUG
            if shouldPrintChanges {
                Self._printChanges()
            }
        #endif
        return GeometryReader { geometry in
            switch style {
            case .stroke:
                strokeBorder(size: geometry.size)
            case .glow:
                glowBorder(size: geometry.size)
            }
        }
        .ignoresSafeArea()
    }

    private func strokeBorder(size: CGSize) -> some View {
        Rectangle()
            .stroke(borderColor, lineWidth: borderWidth)
            .frame(width: size.width, height: size.height)
    }

    private func glowBorder(size: CGSize) -> some View {
        let effectiveGlow = max(glowRadius, 0)
        let spreadStep = max(effectiveGlow / 4, 1.5)
        let blurStep = max(effectiveGlow / 6, 1)

        let glowStack = ZStack {
            ForEach(0 ..< 3, id: \.self) { layer in
                Rectangle()
                    .stroke(
                        borderColor.opacity(0.6 - Double(layer) * 0.15),
                        lineWidth: borderWidth + CGFloat(layer) * spreadStep
                    )
                    .blur(radius: CGFloat(layer) * blurStep + 2)
            }

            Rectangle()
                .stroke(borderColor, lineWidth: borderWidth / 2)
                .blur(radius: min(max(effectiveGlow / 8, 1), 8))
        }

        return glowStack.frame(width: size.width, height: size.height)
    }
}

#Preview("Assistant Border Stroke") {
    AssistantScreenBorderView(
        borderWidth: 10,
        glowRadius: 20,
        borderColor: .orange,
        style: .stroke
    )
    .frame(width: 500, height: 320)
    .background(Color.black.opacity(0.85))
}

#Preview("Assistant Border Glow") {
    AssistantScreenBorderView(
        borderWidth: 10,
        glowRadius: 20,
        borderColor: .green,
        style: .glow
    )
    .frame(width: 500, height: 320)
    .background(Color.black.opacity(0.85))
}
