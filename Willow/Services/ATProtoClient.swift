//
//  ATProtoClient.swift
//  Willow
//
//  The single point of contact with ATProtoKit. Everything SDK-specific lives
//  here; the rest of Willow speaks only in domain types (`Account`,
//  `TimelinePost`, `TimelinePage`). Keeping protocol-shaped code behind this
//  boundary is a deliberate constraint from AGENTS.md — it keeps the app
//  testable and lets the auth backend (e.g. OAuth later) change in one place.
//

import Foundation
import os
import ATProtoKit

final class ATProtoClient: AuthService, TimelineService {

    private let persistence: SessionPersistence

    /// Live session state. Both are `nil` until signed in or restored.
    private var configuration: ATProtocolConfiguration?
    private var atProtoKit: ATProtoKit?

    init(persistence: SessionPersistence = SessionPersistence()) {
        self.persistence = persistence
    }

    // MARK: - AuthService

    func restoreSession() async throws -> Account? {
        guard let stored = persistence.stored else {
            Log.auth.debug("No persisted session to restore.")
            return nil
        }

        Log.auth.info("Restoring session for \(stored.account.handle, privacy: .public) at \(stored.pdsURL.absoluteString, privacy: .public)")

        let keychain = AppleSecureKeychain(identifier: stored.keychainID)
        let configuration = ATProtocolConfiguration(
            pdsURL: stored.pdsURL.absoluteString,
            keychainProtocol: keychain
        )

        do {
            // Refreshes using the refresh token already in the Keychain under
            // this identifier — no stored password needed.
            try await configuration.refreshSession()
        } catch {
            // The stored refresh token is missing or invalid; force a fresh
            // sign-in rather than leaving a half-restored session.
            Log.auth.error("Session restore failed, clearing: \(error.localizedDescription, privacy: .public)")
            persistence.clear()
            throw AuthError.failed(underlying: error.localizedDescription)
        }

        Log.auth.notice("Session restored for \(stored.account.handle, privacy: .public)")

        self.configuration = configuration
        self.atProtoKit = await ATProtoKit(sessionConfiguration: configuration)
        return stored.account
    }

    func signIn(identifier: String, appPassword: String, pdsURL: URL) async throws -> Account {
        let handle = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !password.isEmpty else { throw AuthError.missingCredentials }

        // A fresh keychain identifier scopes this account's tokens; we persist
        // the identifier (not the tokens) so the session can be restored later.
        Log.auth.info("Signing in \(handle, privacy: .public) at \(pdsURL.absoluteString, privacy: .public)")

        let keychainID = UUID()
        let keychain = AppleSecureKeychain(identifier: keychainID)
        let configuration = ATProtocolConfiguration(
            pdsURL: pdsURL.absoluteString,
            keychainProtocol: keychain
        )

        do {
            try await configuration.authenticate(with: handle, password: password)
        } catch {
            Log.auth.error("Authentication failed for \(handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AuthError.failed(underlying: error.localizedDescription)
        }

        let atProtoKit = await ATProtoKit(sessionConfiguration: configuration)

        guard let session = try await atProtoKit.getUserSession() else {
            Log.auth.error("Authenticated but no session was returned for \(handle, privacy: .public)")
            throw AuthError.failed(underlying: "Signed in, but no session was returned.")
        }

        let account = Account(did: session.sessionDID, handle: session.handle)
        self.configuration = configuration
        self.atProtoKit = atProtoKit
        persistence.save(keychainID: keychainID, pdsURL: pdsURL, account: account)
        Log.auth.notice("Signed in as \(account.handle, privacy: .public) (\(account.did, privacy: .public))")
        return account
    }

    func signOut() async {
        Log.auth.info("Signing out.")
        persistence.clear()
        configuration = nil
        atProtoKit = nil
    }

    // MARK: - TimelineService

    func homeTimeline(cursor: String?) async throws -> TimelinePage {
        guard let atProtoKit else { throw AuthError.notSignedIn }

        do {
            let output = try await atProtoKit.getTimeline(cursor: cursor)
            let posts = output.feed.map(Self.makePost(from:))
            Log.timeline.info("Loaded \(posts.count) posts (paging: \(cursor != nil, privacy: .public), nextCursor: \(output.cursor != nil, privacy: .public))")
            return TimelinePage(posts: posts, cursor: output.cursor)
        } catch {
            Log.timeline.error("Timeline fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Mapping

    /// Maps a lexicon feed item into Willow's domain `TimelinePost`. The post
    /// record arrives as an `UnknownType`; we ask it for the concrete
    /// `PostRecord` to read the text and authored timestamp.
    private static func makePost(from item: AppBskyLexicon.Feed.FeedViewPostDefinition) -> TimelinePost {
        let post = item.post
        let record = post.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)

        return TimelinePost(
            id: post.uri,
            authorDisplayName: post.author.displayName,
            authorHandle: post.author.actorHandle,
            authorAvatarURL: post.author.avatarImageURL,
            text: record?.text ?? "",
            createdAt: record?.createdAt ?? post.indexedAt
        )
    }
}
