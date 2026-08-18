//
//  TimelinePost.swift
//  Willow
//

import Foundation

/// A single post as Willow renders it in the timeline.
///
/// This is a UI-facing domain model, deliberately decoupled from ATProtoKit's
/// lexicon types so the views and view state never depend on the SDK's shapes.
/// The mapping from lexicon types lives in `ATProtoClient`.
struct TimelinePost: Identifiable, Sendable, Hashable {

    /// The post's AT URI — stable and unique, used as list identity.
    let id: String
    /// The post's CID, needed alongside the URI to like or repost it.
    let cid: String
    let authorDisplayName: String?
    let authorHandle: String
    let authorAvatarURL: URL?
    let text: String
    let createdAt: Date

    /// Embedded content (images, external card, quote), if any.
    let embed: PostEmbed?

    // Interaction state. Counts and the viewer's own like/repost record URIs
    // are `var` so the UI can update them optimistically.
    let replyCount: Int
    var repostCount: Int
    var likeCount: Int

    /// The viewer's like record URI, non-nil when they've liked this post.
    var likeURI: String?
    /// The viewer's repost record URI, non-nil when they've reposted this post.
    var repostURI: String?

    var isLiked: Bool { likeURI != nil }
    var isReposted: Bool { repostURI != nil }

    /// The name to show, falling back to the handle when no display name is set.
    var displayName: String {
        if let authorDisplayName, !authorDisplayName.isEmpty { return authorDisplayName }
        return authorHandle
    }

    /// A shareable bsky.app web link, derived from the handle and the AT URI's
    /// record key (the final path component).
    var webURL: URL? {
        guard let rkey = id.split(separator: "/").last else { return nil }
        return URL(string: "https://bsky.app/profile/\(authorHandle)/post/\(rkey)")
    }
}
