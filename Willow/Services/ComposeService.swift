//
//  ComposeService.swift
//  Willow
//

import Foundation

/// Creates a new post record.
///
/// Kept separate from `InteractionService`, like the other service
/// boundaries — this is the write path for original content rather than
/// reactions to existing posts.
protocol ComposeService: AnyObject, Sendable {

    /// Creates a post with the given text. Link/mention/hashtag facets are
    /// derived from the text automatically by the underlying SDK; callers
    /// don't need to compute byte offsets themselves. Returns the new
    /// record's AT URI.
    func createPost(text: String) async throws -> String
}
