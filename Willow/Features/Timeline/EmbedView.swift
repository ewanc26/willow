//
//  EmbedView.swift
//  Willow
//

import SwiftUI

/// Renders a post's embedded content. Dispatches on the embed kind, mirroring
/// how the official client stacks media above a quoted record for
/// `recordWithMedia`.
struct EmbedView: View {

    let embed: PostEmbed

    var body: some View {
        switch embed {
        case .images(let images):
            ImagesEmbedView(images: images)

        case .external(let external):
            ExternalEmbedView(external: external)

        case .quote(let quote):
            QuoteEmbedView(quote: quote)

        case .quoteWithMedia(let quote, let media):
            VStack(alignment: .leading, spacing: 8) {
                MediaEmbedView(media: media)
                QuoteEmbedView(quote: quote)
            }

        case .unavailable(let reason):
            UnavailableEmbedView(reason: reason)
        }
    }
}

/// The media half of a `recordWithMedia` embed.
private struct MediaEmbedView: View {
    let media: EmbedMedia

    var body: some View {
        switch media {
        case .images(let images): ImagesEmbedView(images: images)
        case .external(let external): ExternalEmbedView(external: external)
        }
    }
}

// MARK: - Images

struct ImagesEmbedView: View {
    let images: [EmbedImage]

    private let cornerRadius: CGFloat = 12

    var body: some View {
        if images.count == 1, let image = images.first {
            // Single image keeps its own aspect ratio (clamped so very tall
            // images don't dominate the row).
            RemoteImage(url: image.fullSizeURL)
                .aspectRatio(image.aspectRatio ?? (4.0 / 3.0), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityLabel(image.altText.isEmpty ? "Image" : image.altText)
        } else {
            // Two to four images in a square grid.
            LazyVGrid(columns: [GridItem(spacing: 4), GridItem(spacing: 4)], spacing: 4) {
                ForEach(images.prefix(4)) { image in
                    RemoteImage(url: image.thumbnailURL)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(image.altText.isEmpty ? "Image" : image.altText)
                }
            }
        }
    }
}

// MARK: - External link card

struct ExternalEmbedView: View {
    let external: EmbedExternal

    var body: some View {
        Link(destination: external.url) {
            VStack(alignment: .leading, spacing: 0) {
                if let thumbnailURL = external.thumbnailURL {
                    RemoteImage(url: thumbnailURL)
                        .aspectRatio(1.91, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(external.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(external.title.isEmpty ? external.url.absoluteString : external.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if !external.description.isEmpty {
                        Text(external.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quote

struct QuoteEmbedView: View {
    let quote: QuotedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RemoteImage(url: quote.authorAvatarURL)
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())

                Text(quote.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(quote.authorHandle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !quote.text.isEmpty {
                Text(quote.text)
                    .font(.subheadline)
                    .lineLimit(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}

// MARK: - Unavailable

private struct UnavailableEmbedView: View {
    let reason: String

    var body: some View {
        Text(reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}

// MARK: - Shared remote image

/// A thin `AsyncImage` wrapper with a neutral placeholder, used across embeds.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
            case .empty:
                Rectangle().fill(.quaternary).overlay(ProgressView())
            case .failure:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            @unknown default:
                Rectangle().fill(.quaternary)
            }
        }
    }
}
