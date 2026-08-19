//
//  NotificationService.swift
//  Willow
//

import Foundation

/// One page of notification results, plus the cursor for the next page.
struct NotificationPage: Sendable {
    let notifications: [AppNotification]
    let cursor: String?
}

/// Abstraction over reading and acknowledging notifications, kept separate
/// from the SDK so views depend only on domain types.
protocol NotificationService: AnyObject, Sendable {

    /// Fetches a page of notifications. Pass the previous page's `cursor` to
    /// page forward, or `nil` for the newest page.
    func listNotifications(cursor: String?) async throws -> NotificationPage

    /// Marks all notifications up to now as seen.
    func markNotificationsSeen() async throws
}
