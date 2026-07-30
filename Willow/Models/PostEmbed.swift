//
//  PostEmbed.swift
//  Willow
//

import Foundation

/// A post's embedded content, as Willow renders it. A UI-facing domain model
/// decoupled from ATProtoKit's `app.bsky.embed.*` view lexicons; the mapping
/// lives in `ATProtoClient`.
///
/// Mirrors the shapes the official client handles: media (images/external),
/// quoted records, and the combination of a quote with media.
enum PostEmbed: Sendable, Hashable {
    case images([EmbedImage])
    case external(EmbedExternal)
    case quote(QuotedPost)
    /// A quoted post accompanied by its own media (`recordWithMedia`). The
    /// associated embed is always `.images` or `.external`.
    case quoteWithMedia(QuotedPost, media: EmbedMedia)
    /// A referenced record that can't be shown (not found, blocked, detached),
    /// or an embed type Willow doesn't render yet. The string is a short reason.
    case unavailable(String)
}

/// The subset of embeds that can appear as the "media" half of a
/// `recordWithMedia` embed.
enum EmbedMedia: Sendable, Hashable {
    case images([EmbedImage])
    case external(EmbedExternal)
}

struct EmbedImage: Sendable, Hashable, Identifiable {
    /// The full-size URL string — stable and unique within a post.
    var id: String { fullSizeURL.absoluteString }
    let thumbnailURL: URL
    let fullSizeURL: URL
    let altText: String
    /// width / height, when the server provided an aspect ratio.
    let aspectRatio: Double?
}

struct EmbedExternal: Sendable, Hashable {
    let url: URL
    let title: String
    let description: String
    let thumbnailURL: URL?

    /// Host shown as the card's source line, e.g. "github.com".
    var domain: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}

struct QuotedPost: Sendable, Hashable, Identifiable {
    /// The quoted post's AT URI.
    let id: String
    let authorDisplayName: String?
    let authorHandle: String
    let authorAvatarURL: URL?
    let text: String

    var displayName: String {
        if let authorDisplayName, !authorDisplayName.isEmpty { return authorDisplayName }
        return authorHandle
    }
}
