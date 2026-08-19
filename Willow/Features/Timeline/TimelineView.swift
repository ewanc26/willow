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
    @State private var isComposePresented = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Home")
                .navigationDestination(for: ThreadDestination.self) { destination in
                    ThreadView(postURI: destination.postURI, path: $path)
                }
                .navigationDestination(for: ProfileDestination.self) { destination in
                    ProfileView(actor: destination.actor)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                path.append(ProfileDestination(actor: account.did))
                            } label: {
                                Label("@\(account.handle)", systemImage: "person.crop.circle")
                            }
                            Button("Sign Out", role: .destructive) {
                                Task { await session.signOut() }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isComposePresented = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New Post")
                    }
                }
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await refresh()
        }
        .sheet(isPresented: $isComposePresented) {
            ComposeView(onPosted: { Task { await refresh() } })
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
                    PostRowView(
                        post: post,
                        onToggleLike: { Task { await toggleLike(on: post) } },
                        onToggleRepost: { Task { await toggleRepost(on: post) } },
                        onTapPost: { path.append(ThreadDestination(postURI: post.id)) },
                        onTapAuthor: { path.append(ProfileDestination(actor: post.authorHandle)) }
                    )
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

    // MARK: - Interactions

    /// Applies the like/repost toggle optimistically, then reconciles with the
    /// server; on failure the change is rolled back so the UI never shows a
    /// state the server didn't actually record.
    private func toggleLike(on post: TimelinePost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        if let likeURI = posts[index].likeURI {
            posts[index].likeURI = nil
            posts[index].likeCount = max(0, posts[index].likeCount - 1)
            do {
                try await session.interactionService.unlike(likeURI: likeURI)
            } catch {
                posts[index].likeURI = likeURI
                posts[index].likeCount += 1
            }
        } else {
            posts[index].likeURI = "" // placeholder so a rapid second tap can't double-fire
            posts[index].likeCount += 1
            do {
                posts[index].likeURI = try await session.interactionService.like(uri: post.id, cid: post.cid)
            } catch {
                posts[index].likeURI = nil
                posts[index].likeCount = max(0, posts[index].likeCount - 1)
            }
        }
    }

    private func toggleRepost(on post: TimelinePost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        if let repostURI = posts[index].repostURI {
            posts[index].repostURI = nil
            posts[index].repostCount = max(0, posts[index].repostCount - 1)
            do {
                try await session.interactionService.removeRepost(repostURI: repostURI)
            } catch {
                posts[index].repostURI = repostURI
                posts[index].repostCount += 1
            }
        } else {
            posts[index].repostURI = ""
            posts[index].repostCount += 1
            do {
                posts[index].repostURI = try await session.interactionService.repost(uri: post.id, cid: post.cid)
            } catch {
                posts[index].repostURI = nil
                posts[index].repostCount = max(0, posts[index].repostCount - 1)
            }
        }
    }
}

/// Navigation-path values for the two destinations reachable from a post
/// row: its thread, and its author's profile. `Hashable` is all
/// `navigationDestination(for:)` needs — no reason for a heavier type.
struct ThreadDestination: Hashable {
    let postURI: String
}

struct ProfileDestination: Hashable {
    let actor: String
}
