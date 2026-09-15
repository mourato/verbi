import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — avatar state is covered by the provider integration preview.

public struct EnhancementsProviderAvatar: View {
    let provider: AIProvider
    let customIconName: String?
    let size: CGFloat
    let glyphSize: CGFloat

    public init(
        provider: AIProvider,
        customIconName: String? = nil,
        size: CGFloat = 40,
        glyphSize: CGFloat = 22
    ) {
        self.provider = provider
        self.customIconName = customIconName
        self.size = size
        self.glyphSize = glyphSize
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .fill(provider.logoBackgroundColor)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .strokeBorder(AppDesignSystem.Colors.separator.opacity(0.18), lineWidth: 1)
                )

            if let logoImage {
                if let tint = provider.logoTintColor {
                    logoImage
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                        .frame(width: glyphSize, height: glyphSize)
                } else {
                    logoImage
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: glyphSize, height: glyphSize)
                }
            } else {
                Image(systemName: resolvedSymbolName)
                    .font(.system(size: min(CGFloat(16), glyphSize), weight: .semibold))
                    .foregroundStyle(AppDesignSystem.Colors.accent)
            }
        }
    }

    private var resolvedSymbolName: String {
        guard provider == .custom,
              let customIconName
        else {
            return provider.icon
        }

        let trimmedCustomIconName = customIconName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCustomIconName.isEmpty else {
            return provider.icon
        }

        return trimmedCustomIconName
    }

    private var logoImage: Image? {
        guard let logoAssetName = provider.logoAssetName else {
            return nil
        }

        let logoURL = Bundle.module.url(forResource: logoAssetName, withExtension: "png")
            ?? Bundle.module.url(
                forResource: logoAssetName,
                withExtension: "png",
                subdirectory: "ProviderLogos"
            )

        guard let logoURL,
              let nsImage = NSImage(contentsOf: logoURL)
        else {
            return nil
        }

        return Image(nsImage: nsImage)
    }
}
