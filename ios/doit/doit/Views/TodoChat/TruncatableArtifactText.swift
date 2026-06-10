import SwiftUI
import UIKit

enum ArtifactCardLayout {
    static let contentPadding: CGFloat = 18
    static let verticalSectionPadding: CGFloat = 16

    static func playTapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Collapsible body copy for task-header artifact cards. Long emails,
/// transcripts, captions, and calendar metadata start truncated with a
/// single "Show more" affordance instead of stretching the detail header.
struct TruncatableArtifactText: View {
    let text: String
    var lineLimit: Int = 4
    var font: Font = .system(size: 15, weight: .regular, design: .rounded)
    var foregroundStyle: Color = .secondary

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if isTruncatable {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var isTruncatable: Bool {
        let lines = text.components(separatedBy: .newlines)
        if lines.count > lineLimit { return true }
        // Rough width estimate for rounded 15pt body copy on phone screens.
        return text.count > lineLimit * 40
    }
}

/// One expand/collapse control for artifact cards whose metadata is split
/// across several labeled rows (calendar invites, etc.).
struct ArtifactTruncatableSection<Content: View>: View {
    let isTruncatable: Bool
    @ViewBuilder var content: (_ isExpanded: Bool) -> Content

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content(isExpanded)

            if isTruncatable {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Link artifact glyph: bundled connection logo when we have one, otherwise
/// a host favicon, then a generic link symbol.
struct LinkArtifactIcon: View {
    let provider: String?
    let url: URL?

    var body: some View {
        Group {
            if let slug = bundledSlug {
                ConnectionLogo(slug: slug)
            } else if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        genericLinkIcon
                    case .empty:
                        genericLinkIcon
                            .opacity(0.45)
                    @unknown default:
                        genericLinkIcon
                    }
                }
            } else {
                genericLinkIcon
            }
        }
    }

    private var bundledSlug: String? {
        guard let slug = provider?.trimmingCharacters(in: .whitespacesAndNewlines),
              !slug.isEmpty,
              UIImage(named: slug) != nil else {
            return nil
        }
        return slug
    }

    private var faviconURL: URL? {
        guard let host = url?.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    private var genericLinkIcon: some View {
        Image(systemName: "link")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

/// Soft circular backing for the leading provider / kind glyph on artifact cards.
struct ArtifactCardLeadingIcon<Icon: View>: View {
    var glyphSize: CGFloat = 16
    var circleSize: CGFloat = 32
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        icon()
            .frame(width: glyphSize, height: glyphSize)
            .frame(width: circleSize, height: circleSize, alignment: .center)
            .background(
                Circle()
                    .fill(Color.primary.opacity(0.06))
            )
    }
}
