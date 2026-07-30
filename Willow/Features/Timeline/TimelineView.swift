//
//  TimelineView.swift
//  Willow
//

import SwiftUI

/// The signed-in home timeline: a reverse-chronological feed with pull-to-refresh
/// and incremental paging.
struct TimelineView: View {

    @Environment(SessionStore.self) private var session

    let account: Account

    @State private var posts: [TimelinePost] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasLoadedOnce = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Text("@\(account.handle)")
                            Button("Sign Out", role: .destructive) {
                                Task { await session.signOut() }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if posts.isEmpty {
            if isLoading {
                ProgressView("Loading timeline…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                emptyState(
                    title: "Couldn't load your timeline",
                    message: loadError,
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                emptyState(
                    title: "Nothing here yet",
                    message: "Posts from accounts you follow will appear here.",
                    systemImage: "leaf"
                )
            }
        } else {
            List {
                ForEach(posts) { post in
                    PostRowView(post: post)
                        .onAppear { loadMoreIfNeeded(currentItem: post) }
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
            let page = try await session.timelineService.homeTimeline(cursor: nil)
            posts = page.posts
            cursor = page.cursor
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(currentItem: TimelinePost) {
        guard
            !isLoading,
            let cursor,
            currentItem.id == posts.last?.id
        else { return }

        Task { await loadNextPage(after: cursor) }
    }

    private func loadNextPage(after cursor: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await session.timelineService.homeTimeline(cursor: cursor)
            // Guard against duplicates if the same page arrives twice.
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: page.posts.filter { !existing.contains($0.id) })
            self.cursor = page.cursor
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
