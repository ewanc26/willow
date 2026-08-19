//
//  AppNotification.swift
//  Willow
//

import Foundation

/// A single notification as Willow renders it.
///
/// Named `AppNotification` (not `Notification`) to avoid colliding with
/// Foundation's `Notification`. Deliberately not grouped (the official app
/// groups consecutive likes/reposts on the same post into one row) — that's
/// a real gap, left as a follow-up rather than attempted here; see
/// `NotificationsView`'s doc comment.
struct AppNotification: Identifiable, Sendable, Hashable {

    enum Reason: Sendable, Hashable {
        case like
        case repost
        case follow
        case mention
        case reply
        case quote
        case other(String)
    }

    /// The notification's AT URI — stable and unique, used as list identity.
    let id: String
    let reason: Reason
    let authorDisplayName: String?
    let authorHandle: String
    let authorAvatarURL: URL?
    /// The URI of the post/record this notification is about, if any (e.g.
    /// the post that was liked or replied to).
    let reasonSubjectURI: String?
    let isRead: Bool
    let indexedAt: Date

    var displayName: String {
        if let authorDisplayName, !authorDisplayName.isEmpty { return authorDisplayName }
        return authorHandle
    }
}
