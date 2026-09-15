import AppKit
import SwiftUI

struct AppIconView: View {
    let bundleIdentifier: String?
    let fallbackSystemName: String
    let size: CGFloat
    let cornerRadius: CGFloat

    init(
        bundleIdentifier: String?,
        fallbackSystemName: String = "questionmark.circle",
        size: CGFloat = 16,
        cornerRadius: CGFloat = 4
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.fallbackSystemName = fallbackSystemName
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        if let icon = iconImage {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: size * 0.85, weight: .regular))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }

    private var iconImage: NSImage? {
        guard let bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}

#Preview {
    HStack(spacing: 16) {
        AppIconView(bundleIdentifier: "com.apple.Safari", size: 24, cornerRadius: 6)
        AppIconView(bundleIdentifier: nil, fallbackSystemName: "questionmark.circle", size: 24, cornerRadius: 6)
    }
    .padding()
}
