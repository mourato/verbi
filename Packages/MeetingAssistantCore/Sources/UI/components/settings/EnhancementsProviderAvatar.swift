import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Squircle avatar showing a brand logo, an optional host badge, or an SF Symbol fallback.
struct BrandAvatar: View {
    let brand: ModelBrand?
    let badgeBrand: ModelBrand?
    let fallbackSymbolName: String
    let size: CGFloat
    let glyphSize: CGFloat

    init(
        brand: ModelBrand?,
        badgeBrand: ModelBrand? = nil,
        fallbackSymbolName: String,
        size: CGFloat = 40,
        glyphSize: CGFloat = 22
    ) {
        self.brand = brand
        self.badgeBrand = badgeBrand
        self.fallbackSymbolName = fallbackSymbolName
        self.size = size
        self.glyphSize = glyphSize
    }

    var body: some View {
        tile(brand: brand, size: size, glyphSize: glyphSize)
            .overlay(alignment: .bottomTrailing) {
                if let badgeBrand, badgeBrand != brand {
                    let badgeSize = (size * 0.5).rounded()
                    tile(brand: badgeBrand, size: badgeSize, glyphSize: (badgeSize * 0.6).rounded())
                        .overlay(
                            RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous)
                                .strokeBorder(AppDesignSystem.Colors.settingsCardBackground, lineWidth: 1.5)
                        )
                        .offset(x: badgeSize * 0.3, y: badgeSize * 0.3)
                }
            }
            .accessibilityHidden(true)
    }

    private func tile(brand: ModelBrand?, size: CGFloat, glyphSize: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)

        return ZStack {
            shape
                .fill(brand?.logoBackgroundColor ?? AppDesignSystem.Colors.subtleFill2)
                .overlay(
                    shape.strokeBorder(AppDesignSystem.Colors.separator.opacity(0.18), lineWidth: 0.5)
                )

            if let brand, let logoImage = Self.logoImage(named: brand.logoAssetName) {
                if let tint = brand.logoTintColor {
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
                Image(systemName: fallbackSymbolName)
                    .font(.system(size: min(CGFloat(16), glyphSize), weight: .semibold))
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    private static func logoImage(named logoAssetName: String) -> Image? {
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
        BrandAvatar(
            brand: provider.brand,
            fallbackSymbolName: resolvedSymbolName,
            size: size,
            glyphSize: glyphSize
        )
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
}

#Preview("Brand avatars") {
    HStack(spacing: 16) {
        BrandAvatar(brand: .nvidia, fallbackSymbolName: "internaldrive", size: 28, glyphSize: 18)
        BrandAvatar(brand: .openai, badgeBrand: .groq, fallbackSymbolName: "bolt", size: 28, glyphSize: 18)
        BrandAvatar(brand: .elevenLabs, fallbackSymbolName: "waveform", size: 28, glyphSize: 18)
        EnhancementsProviderAvatar(provider: .anthropic)
        EnhancementsProviderAvatar(provider: .custom, customIconName: "sparkles")
    }
    .padding()
}
