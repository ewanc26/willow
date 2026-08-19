//
//  ThreadView.swift
//  Willow
//

import SwiftUI

/// A post in context: its parent (if any), the post itself, and its direct
/// replies. Basic and flat — no recursive nested-reply tree, consistent with
/// Willow staying a basic client rather than matching every official-app
/// thread-rendering nuance.
struct ThreadView: View {

    @Environment(SessionStore.self) private var session

    let postURI: String
    /// Shares the presenting `TimelineView`'s navigation path so tapping an
    /// author here pushes onto the same stack, rather than each screen
    /// managing its own — kept as a binding instead of a bigger navigation
    /// abstraction, since two screens sharing one path is "just enough" here.
    @Binding var path: NavigationPath

    @State private var page: ThreadPage?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        content
            .navigationTitle("Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let page {
            List {
                if let parent = page.parent {
                    Section("Replying to") {
                        row(for: parent)
                    }
                }

                Section {
                    row(for: page.post)
                }

                if !page.replies.isEmpty {
                    Section("Replies") {
                        ForEach(page.replies) { reply in
                            PostRowView(
                                post: reply,
                                onToggleLike: { Task { await toggleLike(on: reply) } },
                                onToggleRepost: { Task { await toggleRepost(on: reply) } },
                                onTapPost: { path.append(ThreadDestination(postURI: reply.id)) },
                                onTapAuthor: { path.append(ProfileDestination(actor: reply.authorHandle)) }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        } else if isLoading {
            ProgressView("Loading thread…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView {
                Label("Couldn't load this post", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    /// Every row simply re-fetches the whole thread after a like/repost
    /// toggle rather than patching local state in three places — the thread
    /// is a small, single-page view, so the round trip is cheap and this
    /// keeps the view's state trivially correct.
    private func row(for post: TimelinePost) -> some View {
        PostRowView(
            post: post,
            onToggleLike: { Task { await toggleLike(on: post) } },
            onToggleRepost: { Task { await toggleRepost(on: post) } },
            onTapAuthor: { path.append(ProfileDestination(actor: post.authorHandle)) }
        )
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            page = try await session.threadService.thread(forPostURI: postURI)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleLike(on post: TimelinePost) async {
        do {
            if let likeURI = post.likeURI {
                try await session.interactionService.unlike(likeURI: likeURI)
            } else {
                _ = try await session.interactionService.like(uri: post.id, cid: post.cid)
            }
            await load()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleRepost(on post: TimelinePost) async {
        do {
            if let repostURI = post.repostURI {
                try await session.interactionService.removeRepost(repostURI: repostURI)
            } else {
                _ = try await session.interactionService.repost(uri: post.id, cid: post.cid)
            }
            await load()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
