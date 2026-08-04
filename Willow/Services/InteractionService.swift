//
//  InteractionService.swift
//  Willow
//

import Foundation

/// Write actions on posts (the viewer's own like/repost records).
///
/// Each create returns the new record's AT URI, which the caller stores so it
/// can later undo the action. Kept separate from the SDK behind this protocol,
/// like the other service boundaries.
protocol InteractionService: AnyObject, Sendable {

    /// Likes the post identified by `uri` + `cid`. Returns the like record URI.
    func like(uri: String, cid: String) async throws -> String

    /// Removes a like, given the like record URI returned by `like`.
    func unlike(likeURI: String) async throws

    /// Reposts the post identified by `uri` + `cid`. Returns the repost record URI.
    func repost(uri: String, cid: String) async throws -> String

    /// Removes a repost, given the repost record URI returned by `repost`.
    func removeRepost(repostURI: String) async throws
}
