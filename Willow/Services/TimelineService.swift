//
//  TimelineService.swift
//  Willow
//

import Foundation

/// One page of timeline results, plus the cursor for the next page.
struct TimelinePage: Sendable {
    let posts: [TimelinePost]
    let cursor: String?
}

/// Abstraction over reading the home timeline, kept separate from the SDK so
/// views depend only on domain types.
protocol TimelineService: AnyObject, Sendable {

    /// Fetches a page of the home timeline. Pass the previous page's `cursor`
    /// to page forward, or `nil` for the newest page.
    func homeTimeline(cursor: String?) async throws -> TimelinePage
}
