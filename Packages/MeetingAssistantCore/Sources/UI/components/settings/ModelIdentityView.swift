import MeetingAssistantCoreCommon
import SwiftUI

/// Brand avatar plus model title and optional subtitle, shared by every surface that shows a model.
struct ModelIdentityView: View {
    enum Size {
        /// List rows: 28pt avatar with host badge.
        case row
        /// Dense lists and summaries: 20pt avatar, no badge.
        case compact
        /// Menus, table cells, popovers: 16pt avatar, title inherits the font.
        case inline

        var avatarSize: CGFloat {
            switch self {
            case .row: 28
            case .compact: 20
            case .inline: 16
            }
        }

        var glyphSize: CGFloat {
            switch self {
            case .row: 18
            case .compact: 13
            case .inline: 10
            }
        }

        var spacing: CGFloat {
            switch self {
            case .row: 12
            case .compact: 8
            case .inline: 6
            }
        }

        var titleFont: Font? {
            switch self {
            case .row: .body.weight(.medium)
            case .compact: .callout
            case .inline: nil
            }
        }

        var showsHostBadge: Bool {
            self == .row
        }
    }

    let title: String
    var subtitle: String?
    let brand: ModelBrand?
    var host: ModelBrand?
    let fallbackSymbolName: String
    var size: Size = .row

    var body: some View {
        HStack(alignment: .center, spacing: size.spacing) {
            BrandAvatar(
                brand: brand,
                badgeBrand: size.showsHostBadge ? host : nil,
                fallbackSymbolName: fallbackSymbolName,
                size: size.avatarSize,
                glyphSize: size.glyphSize
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(size.titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle, size != .inline {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

#Preview("Model identity sizes") {
    VStack(alignment: .leading, spacing: 16) {
        ModelIdentityView(
            title: "Whisper Large v3 Turbo",
            subtitle: "Groq · Cloud",
            brand: .openai,
            host: .groq,
            fallbackSymbolName: "bolt"
        )
        ModelIdentityView(title: "Scribe v2", subtitle: "ElevenLabs", brand: .elevenLabs, fallbackSymbolName: "waveform", size: .compact)
        ModelIdentityView(title: "Parakeet", brand: .nvidia, fallbackSymbolName: "internaldrive", size: .inline)
    }
    .padding()
}
