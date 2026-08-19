//
//  Profile.swift
//  Willow
//

import Foundation

/// An actor's profile, as Willow renders it.
///
/// Deliberately decoupled from ATProtoKit's lexicon types, same as
/// `TimelinePost` — the mapping lives in `ATProtoClient`.
struct Profile: Identifiable, Sendable, Hashable {

    /// The actor's DID — stable identity, used as list/navigation identity.
    let did: String
    let handle: String
    let displayName: String?
    let avatarURL: URL?
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let postCount: Int

    var id: String { did }

    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return handle
    }
}
