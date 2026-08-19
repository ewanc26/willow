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

final class ATProtoClient: AuthService, TimelineService, InteractionService {

    private let persistence: SessionPersistence

    /// Live session state. All are `nil` until signed in or restored.
    private var configuration: ATProtocolConfiguration?
    private var atProtoKit: ATProtoKit?
    /// The write-path helper (like/repost/createRecord), built from `atProtoKit`.
    private var bluesky: ATProtoBluesky?

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

        let atProtoKit = await ATProtoKit(sessionConfiguration: configuration)
        self.configuration = configuration
        self.atProtoKit = atProtoKit
        self.bluesky = ATProtoBluesky(atProtoKitInstance: atProtoKit)
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
        self.bluesky = ATProtoBluesky(atProtoKitInstance: atProtoKit)
        persistence.save(keychainID: keychainID, pdsURL: pdsURL, account: account)
        Log.auth.notice("Signed in as \(account.handle, privacy: .public) (\(account.did, privacy: .public))")
        return account
    }

    func signOut() async {
        Log.auth.info("Signing out.")
        persistence.clear()
        configuration = nil
        atProtoKit = nil
        bluesky = nil
    }

    // MARK: - InteractionService

    func like(uri: String, cid: String) async throws -> String {
        guard let bluesky else { throw AuthError.notSignedIn }
        let subject = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let record = try await bluesky.createLikeRecord(subject)
        Log.timeline.info("Liked \(uri, privacy: .public)")
        return record.recordURI
    }

    func unlike(likeURI: String) async throws {
        guard let bluesky else { throw AuthError.notSignedIn }
        try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
        Log.timeline.info("Unliked \(likeURI, privacy: .public)")
    }

    func repost(uri: String, cid: String) async throws -> String {
        guard let bluesky else { throw AuthError.notSignedIn }
        let subject = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let record = try await bluesky.createRepostRecord(subject)
        Log.timeline.info("Reposted \(uri, privacy: .public)")
        return record.recordURI
    }

    func removeRepost(repostURI: String) async throws {
        guard let bluesky else { throw AuthError.notSignedIn }
        try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
        Log.timeline.info("Removed repost \(repostURI, privacy: .public)")
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
    private nonisolated static func makePost(from item: AppBskyLexicon.Feed.FeedViewPostDefinition) -> TimelinePost {
        let post = item.post
        let record = post.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)

        return TimelinePost(
            id: post.uri,
            cid: post.cid,
            authorDisplayName: post.author.displayName,
            authorHandle: post.author.actorHandle,
            authorAvatarURL: post.author.avatarImageURL,
            text: record?.text ?? "",
            createdAt: record?.createdAt ?? post.indexedAt,
            embed: post.embed.flatMap(makeEmbed(from:)),
            replyCount: post.replyCount ?? 0,
            repostCount: post.repostCount ?? 0,
            likeCount: post.likeCount ?? 0,
            likeURI: post.viewer?.likeURI,
            repostURI: post.viewer?.repostURI
        )
    }

    // MARK: - Embed mapping

    private nonisolated static func makeEmbed(from embed: AppBskyLexicon.Feed.PostViewDefinition.EmbedUnion) -> PostEmbed? {
        switch embed {
        case .embedImagesView(let view):
            return .images(view.images.map(makeImage(from:)))

        case .embedExternalView(let view):
            return makeExternal(from: view.external).map(PostEmbed.external)

        case .embedRecordView(let view):
            return makeQuote(from: view.record).map(PostEmbed.quote)

        case .embedRecordWithMediaView(let view):
            guard let quote = makeQuote(from: view.record.record) else {
                return makeMedia(from: view.media).map { $0.asEmbed }
            }
            guard let media = makeMedia(from: view.media) else {
                return .quote(quote)
            }
            return .quoteWithMedia(quote, media: media)

        default:
            // Video, gallery, and any future/unknown embed types.
            return nil
        }
    }

    private nonisolated static func makeImage(from image: AppBskyLexicon.Embed.ImagesDefinition.ViewImage) -> EmbedImage {
        var ratio: Double?
        if let aspect = image.aspectRatio, aspect.height > 0 {
            ratio = Double(aspect.width) / Double(aspect.height)
        }
        return EmbedImage(
            thumbnailURL: image.thumbnailImageURL,
            fullSizeURL: image.fullSizeImageURL,
            altText: image.altText,
            aspectRatio: ratio
        )
    }

    private nonisolated static func makeExternal(from external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> EmbedExternal? {
        guard let url = URL(string: external.uri) else { return nil }
        return EmbedExternal(
            url: url,
            title: external.title,
            description: external.description,
            thumbnailURL: external.thumbnailImageURL
        )
    }

    /// Resolves the `media` half of a `recordWithMedia` embed.
    private nonisolated static func makeMedia(from media: AppBskyLexicon.Embed.RecordWithMediaDefinition.View.MediaUnion) -> EmbedMedia? {
        switch media {
        case .embedImagesView(let view):
            return .images(view.images.map(makeImage(from:)))
        case .embedExternalView(let view):
            return makeExternal(from: view.external).map(EmbedMedia.external)
        default:
            return nil
        }
    }

    /// Resolves a quoted record, distinguishing a viewable post from an
    /// unavailable one (blocked, deleted, detached).
    private nonisolated static func makeQuote(from record: AppBskyLexicon.Embed.RecordDefinition.View.RecordViewUnion) -> QuotedPost? {
        switch record {
        case .viewRecord(let viewRecord):
            let postRecord = viewRecord.value.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
            return QuotedPost(
                id: viewRecord.uri,
                authorDisplayName: viewRecord.author.displayName,
                authorHandle: viewRecord.author.actorHandle,
                authorAvatarURL: viewRecord.author.avatarImageURL,
                text: postRecord?.text ?? ""
            )
        default:
            return nil
        }
    }
}

private extension EmbedMedia {
    /// A standalone media embed, used when a `recordWithMedia`'s record half is
    /// unavailable but its media is still worth showing.
    nonisolated var asEmbed: PostEmbed {
        switch self {
        case .images(let images): .images(images)
        case .external(let external): .external(external)
        }
    }
}
