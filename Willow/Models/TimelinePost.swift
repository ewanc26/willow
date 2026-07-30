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
    let authorDisplayName: String?
    let authorHandle: String
    let authorAvatarURL: URL?
    let text: String
    let createdAt: Date

    /// Embedded content (images, external card, quote), if any.
    let embed: PostEmbed?

    /// The name to show, falling back to the handle when no display name is set.
    var displayName: String {
        if let authorDisplayName, !authorDisplayName.isEmpty { return authorDisplayName }
        return authorHandle
    }
}
