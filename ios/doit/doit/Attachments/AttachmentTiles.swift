import SwiftUI

/// Shared visual treatment for an attachment thumbnail tile with a small
/// circular `x` button overlaid in the top-right corner. Used both for
/// pending (in-memory) and remote (server-stored) images.
struct AttachmentTile<Thumbnail: View>: View {
    static var size: CGFloat { 64 }

    let thumbnail: Thumbnail
    let onRemove: () -> Void
    let onTap: (() -> Void)?

    init(
        @ViewBuilder thumbnail: () -> Thumbnail,
        onRemove: @escaping () -> Void,
        onTap: (() -> Void)? = nil
    ) {
        self.thumbnail = thumbnail()
        self.onRemove = onRemove
        self.onTap = onTap
    }

    var body: some View {
        // Reserve enough top + trailing space for the X button to live fully
        // inside the tile's bounds, so the parent ScrollView doesn't clip
        // the corner badge.
        ZStack(alignment: .topTrailing) {
            Button {
                onTap?()
            } label: {
                thumbnail
                    .frame(width: Self.size, height: Self.size)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            .padding(.top, 11)
            .padding(.trailing, 11)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.78), in: Circle())
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image")
        }
        .frame(
            width: Self.size + 11,
            height: Self.size + 11,
            alignment: .topLeading
        )
    }
}

/// A tile rendering a `UIImage` we have in memory — used by the New Task
/// sheet before the todo (and therefore the upload) exists.
struct PendingAttachmentTile: View {
    let image: UIImage
    let onRemove: () -> Void
    let onTap: (() -> Void)?

    var body: some View {
        AttachmentTile(
            thumbnail: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            },
            onRemove: onRemove,
            onTap: onTap
        )
    }
}

/// A tile rendering a server-stored attachment via `AsyncImage` against a
/// short-lived signed URL. The URL is fetched once and cached on the parent
/// view; when it expires the parent re-fetches.
struct RemoteAttachmentTile: View {
    let signedURL: URL?
    let onRemove: () -> Void
    let onTap: (() -> Void)?

    var body: some View {
        AttachmentTile(
            thumbnail: {
                Group {
                    if let signedURL {
                        AsyncImage(url: signedURL) { phase in
                            switch phase {
                            case .empty:
                                placeholder
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                placeholder
                            @unknown default:
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
            },
            onRemove: onRemove,
            onTap: onTap
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
