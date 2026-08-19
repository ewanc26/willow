//
//  ThreadService.swift
//  Willow
//

import Foundation

/// A post in context: its parent (if a reply), the post itself, and its
/// direct replies. Deep nested reply trees are flattened to one level —
/// enough for a basic thread view without becoming a full recursive tree UI.
struct ThreadPage: Sendable {
    let parent: TimelinePost?
    let post: TimelinePost
    let replies: [TimelinePost]
}

/// Abstraction over reading a post's thread, kept separate from the SDK so
/// views depend only on domain types.
protocol ThreadService: AnyObject, Sendable {

    /// Fetches the thread containing the post at `uri`.
    func thread(forPostURI uri: String) async throws -> ThreadPage
}
