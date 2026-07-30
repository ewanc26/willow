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
        guard let stored = persistence.stored else { return nil }

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
            persistence.clear()
            throw AuthError.failed(underlying: error.localizedDescription)
        }

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
        let keychainID = UUID()
        let keychain = AppleSecureKeychain(identifier: keychainID)
        let configuration = ATProtocolConfiguration(
            pdsURL: pdsURL.absoluteString,
            keychainProtocol: keychain
        )

        do {
            try await configuration.authenticate(with: handle, password: password)
        } catch {
            throw AuthError.failed(underlying: error.localizedDescription)
        }

        let atProtoKit = await ATProtoKit(sessionConfiguration: configuration)

        guard let session = try await atProtoKit.getUserSession() else {
            throw AuthError.failed(underlying: "Signed in, but no session was returned.")
        }

        let account = Account(did: session.sessionDID, handle: session.handle)
        self.configuration = configuration
        self.atProtoKit = atProtoKit
        persistence.save(keychainID: keychainID, pdsURL: pdsURL, account: account)
        return account
    }

    func signOut() async {
        persistence.clear()
        configuration = nil
        atProtoKit = nil
    }

    // MARK: - TimelineService

    func homeTimeline(cursor: String?) async throws -> TimelinePage {
        guard let atProtoKit else { throw AuthError.notSignedIn }

        let output = try await atProtoKit.getTimeline(cursor: cursor)
        let posts = output.feed.map(Self.makePost(from:))
        return TimelinePage(posts: posts, cursor: output.cursor)
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
