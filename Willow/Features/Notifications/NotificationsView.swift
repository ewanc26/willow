//
//  NotificationsView.swift
//  Willow
//

import SwiftUI

/// Notifications, paged the same way `TimelineView` pages the home timeline.
///
/// Not grouped: the official app collapses consecutive likes/reposts on the
/// same post into one row ("Alice and 3 others liked your post"). That's a
/// real convention worth adopting but is left as a follow-up rather than
/// attempted here — grouping changes list identity/paging in ways that
/// deserved its own pass rather than folding into this first cut.
struct NotificationsView: View {

    @Environment(SessionStore.self) private var session

    @State private var notifications: [AppNotification] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasLoadedOnce = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if notifications.isEmpty {
            if isLoading {
                ProgressView("Loading notifications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                emptyState(
                    title: "Couldn't load notifications",
                    message: loadError,
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                emptyState(
                    title: "Nothing here yet",
                    message: "Likes, reposts, replies, and follows will appear here.",
                    systemImage: "bell"
                )
            }
        } else {
            List {
                ForEach(notifications) { notification in
                    NotificationRowView(notification: notification)
                        .onAppear { loadMoreIfNeeded(currentItem: notification) }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
        }
    }

    private func emptyState(title: String, message: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await refresh() } }
        }
    }

    // MARK: - Loading

    private func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let page = try await session.notificationService.listNotifications(cursor: nil)
            notifications = page.notifications
            cursor = page.cursor
            try? await session.notificationService.markNotificationsSeen()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(currentItem: AppNotification) {
        guard
            !isLoading,
            let cursor,
            currentItem.id == notifications.last?.id
        else { return }

        Task { await loadNextPage(after: cursor) }
    }

    private func loadNextPage(after cursor: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await session.notificationService.listNotifications(cursor: cursor)
            let existing = Set(notifications.map(\.id))
            notifications.append(contentsOf: page.notifications.filter { !existing.contains($0.id) })
            self.cursor = page.cursor
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
