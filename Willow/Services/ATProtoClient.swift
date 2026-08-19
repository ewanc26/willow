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
import CryptoKit

final class ATProtoClient: AuthService, TimelineService, InteractionService {

    private let persistence: SessionPersistence

    /// Live session state. All are `nil` until signed in or restored.
    private var configuration: ATProtocolConfiguration?
    private var atProtoKit: ATProtoKit?
    /// The write-path helper (like/repost/createRecord), built from `atProtoKit`.
    private var bluesky: ATProtoBluesky?

    /// Set once an OAuth sign-in completes. `atProtoKit`/`bluesky` stay `nil`
    /// in that case — see `signInWithOAuth` — so any `TimelineService`/
    /// `InteractionService` call correctly throws `.notSignedIn` rather than
    /// silently using stale or absent credentials.
    private var oauthTokens: OAuthTokens?

    init(persistence: SessionPersistence = SessionPersistence()) {
        self.persistence = persistence
    }

    // MARK: - AuthService

    func restoreSession() async throws -> Account? {
        guard let stored = persistence.stored else {
            Log.auth.debug("No persisted session to restore.")
            return nil
        }

        if stored.isOAuth {
            return try restoreOAuthSession(stored)
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

    /// Restores an OAuth session's DID/handle from its persisted token store.
    ///
    /// This does not refresh or validate the access token against the
    /// authorization server (there's no request pipeline to use it with yet —
    /// see the type doc on `AuthService`), so a restored OAuth account may be
    /// signed in only in the sense that Willow remembers who it is.
    private func restoreOAuthSession(_ stored: SessionPersistence.Stored) throws -> Account? {
        let store = OAuthTokenStore(identifier: stored.keychainID)
        guard let tokens = try store.load() else {
            Log.auth.debug("OAuth session pointer existed but its tokens are gone; clearing.")
            persistence.clear()
            return nil
        }
        self.oauthTokens = OAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresIn: 0,
            subjectDID: tokens.subjectDID,
            pdsURL: tokens.pdsURL,
            authServer: OAuthServerMetadata(
                issuer: tokens.authServerIssuer,
                authorizationEndpoint: tokens.authorizationEndpoint,
                tokenEndpoint: tokens.tokenEndpoint,
                pushedAuthorizationRequestEndpoint: tokens.pushedAuthorizationRequestEndpoint
            ),
            dpopKeyIdentifier: stored.keychainID,
            authServerNonce: nil
        )
        Log.auth.notice("Restored OAuth session for \(stored.account.handle, privacy: .public)")
        return stored.account
    }

    /// Runs the AT Protocol OAuth flow and persists the resulting tokens.
    ///
    /// The returned `Account` is genuine — its DID comes straight from the
    /// token response's `sub` claim — but see the `AuthService` doc comment:
    /// nothing built on top of `atProtoKit`/`bluesky` works for it yet.
    func signInWithOAuth(pdsURL: URL) async throws -> Account {
        Log.auth.info("Starting OAuth sign-in at \(pdsURL.absoluteString, privacy: .public)")

        let client = OAuthClient()
        let tokens = try await client.signIn(pdsURL: pdsURL)
        self.oauthTokens = tokens

        let handle = await Self.resolveHandle(did: tokens.subjectDID, pdsURL: pdsURL)
        let account = Account(did: tokens.subjectDID, handle: handle ?? tokens.subjectDID)

        let store = OAuthTokenStore(identifier: tokens.dpopKeyIdentifier)
        try store.save(OAuthTokenStore.StoredTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            subjectDID: tokens.subjectDID,
            pdsURL: tokens.pdsURL,
            authServerIssuer: tokens.authServer.issuer,
            authorizationEndpoint: tokens.authServer.authorizationEndpoint,
            tokenEndpoint: tokens.authServer.tokenEndpoint,
            pushedAuthorizationRequestEndpoint: tokens.authServer.pushedAuthorizationRequestEndpoint
        ))
        persistence.save(keychainID: tokens.dpopKeyIdentifier, pdsURL: pdsURL, account: account, isOAuth: true)

        Log.auth.notice("OAuth sign-in complete for \(account.did, privacy: .public)")
        return account
    }

    /// Best-effort handle lookup for the OAuth account-creation display name —
    /// `com.atproto.repo.describeRepo` is an unauthenticated, public read, so
    /// this needs no DPoP proof. A failure here just leaves the handle showing
    /// as the DID; it's cosmetic, not a sign-in failure.
    private static func resolveHandle(did: String, pdsURL: URL) async -> String? {
        var components = URLComponents(url: pdsURL.appending(path: "xrpc/com.atproto.repo.describeRepo"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "repo", value: did)]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["handle"] as? String
        } catch {
            return nil
        }
    }

    func signOut() async {
        Log.auth.info("Signing out.")
        if let stored = persistence.stored, stored.isOAuth {
            OAuthTokenStore(identifier: stored.keychainID).delete()
            DPoPKeyStore(identifier: stored.keychainID).delete()
        }
        persistence.clear()
        configuration = nil
        atProtoKit = nil
        bluesky = nil
        oauthTokens = nil
    }

    // MARK: - InteractionService

    func like(uri: String, cid: String) async throws -> String {
        if oauthTokens != nil {
            return try await withOAuthTokens { tokens, dpopKey in
                let record: [String: Any] = [
                    "$type": "app.bsky.feed.like",
                    "subject": ["uri": uri, "cid": cid],
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ]
                let body: [String: Any] = [
                    "repo": tokens.subjectDID,
                    "collection": "app.bsky.feed.like",
                    "record": record
                ]
                let (json, updated) = try await OAuthXRPCClient.request(
                    method: "POST", path: "com.atproto.repo.createRecord", body: body, tokens: tokens, dpopKey: dpopKey
                )
                guard let recordURI = json["uri"] as? String else { throw OAuthXRPCClient.XRPCError.invalidResponse }
                Log.timeline.info("Liked \(uri, privacy: .public) via OAuth")
                return (recordURI, updated)
            }
        }
        guard let bluesky else { throw AuthError.notSignedIn }
        let subject = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let record = try await bluesky.createLikeRecord(subject)
        Log.timeline.info("Liked \(uri, privacy: .public)")
        return record.recordURI
    }

    func unlike(likeURI: String) async throws {
        if oauthTokens != nil {
            try await withOAuthTokens { tokens, dpopKey -> (Void, OAuthTokens) in
                let updated = try await Self.deleteRecord(likeURI, tokens: tokens, dpopKey: dpopKey)
                Log.timeline.info("Unliked \(likeURI, privacy: .public) via OAuth")
                return ((), updated)
            }
            return
        }
        guard let bluesky else { throw AuthError.notSignedIn }
        try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
        Log.timeline.info("Unliked \(likeURI, privacy: .public)")
    }

    func repost(uri: String, cid: String) async throws -> String {
        if oauthTokens != nil {
            return try await withOAuthTokens { tokens, dpopKey in
                let record: [String: Any] = [
                    "$type": "app.bsky.feed.repost",
                    "subject": ["uri": uri, "cid": cid],
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ]
                let body: [String: Any] = [
                    "repo": tokens.subjectDID,
                    "collection": "app.bsky.feed.repost",
                    "record": record
                ]
                let (json, updated) = try await OAuthXRPCClient.request(
                    method: "POST", path: "com.atproto.repo.createRecord", body: body, tokens: tokens, dpopKey: dpopKey
                )
                guard let recordURI = json["uri"] as? String else { throw OAuthXRPCClient.XRPCError.invalidResponse }
                Log.timeline.info("Reposted \(uri, privacy: .public) via OAuth")
                return (recordURI, updated)
            }
        }
        guard let bluesky else { throw AuthError.notSignedIn }
        let subject = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let record = try await bluesky.createRepostRecord(subject)
        Log.timeline.info("Reposted \(uri, privacy: .public)")
        return record.recordURI
    }

    func removeRepost(repostURI: String) async throws {
        if oauthTokens != nil {
            try await withOAuthTokens { tokens, dpopKey -> (Void, OAuthTokens) in
                let updated = try await Self.deleteRecord(repostURI, tokens: tokens, dpopKey: dpopKey)
                Log.timeline.info("Removed repost \(repostURI, privacy: .public) via OAuth")
                return ((), updated)
            }
            return
        }
        guard let bluesky else { throw AuthError.notSignedIn }
        try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
        Log.timeline.info("Removed repost \(repostURI, privacy: .public)")
    }

    private static func deleteRecord(_ recordURI: String, tokens: OAuthTokens, dpopKey: P256.Signing.PrivateKey) async throws -> OAuthTokens {
        guard let parsed = OAuthXRPCClient.parseRecordURI(recordURI) else {
            throw OAuthXRPCClient.XRPCError.invalidResponse
        }
        let body: [String: Any] = ["repo": parsed.repo, "collection": parsed.collection, "rkey": parsed.rkey]
        let (_, updated) = try await OAuthXRPCClient.request(
            method: "POST", path: "com.atproto.repo.deleteRecord", body: body, tokens: tokens, dpopKey: dpopKey
        )
        return updated
    }

    // MARK: - TimelineService

    func homeTimeline(cursor: String?) async throws -> TimelinePage {
        if oauthTokens != nil {
            return try await withOAuthTokens { tokens, dpopKey in
                var query: [String: String] = [:]
                if let cursor { query["cursor"] = cursor }
                let (json, updated) = try await OAuthXRPCClient.request(
                    method: "GET", path: "app.bsky.feed.getTimeline", query: query, tokens: tokens, dpopKey: dpopKey
                )
                let feed = json["feed"] as? [[String: Any]] ?? []
                let posts = feed.compactMap { ($0["post"] as? [String: Any]).flatMap(OAuthPostMapping.makePost) }
                let page = TimelinePage(posts: posts, cursor: json["cursor"] as? String)
                Log.timeline.info("Loaded \(posts.count) posts via OAuth (paging: \(cursor != nil, privacy: .public))")
                return (page, updated)
            }
        }
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

    // MARK: - OAuth request plumbing

    /// Runs `body` against the current OAuth session's tokens and DPoP key,
    /// then persists any nonce learned or token refreshed along the way —
    /// centralized here so every OAuth-backed protocol method above gets that
    /// bookkeeping for free instead of repeating it.
    private func withOAuthTokens<T>(
        _ body: (OAuthTokens, P256.Signing.PrivateKey) async throws -> (T, OAuthTokens)
    ) async throws -> T {
        guard let tokens = oauthTokens else { throw AuthError.notSignedIn }
        let dpopKey = try DPoPKeyStore(identifier: tokens.dpopKeyIdentifier).key()
        let (result, updated) = try await body(tokens, dpopKey)
        oauthTokens = updated
        if updated.accessToken != tokens.accessToken || updated.refreshToken != tokens.refreshToken {
            try? OAuthTokenStore(identifier: updated.dpopKeyIdentifier).save(OAuthTokenStore.StoredTokens(
                accessToken: updated.accessToken,
                refreshToken: updated.refreshToken,
                subjectDID: updated.subjectDID,
                pdsURL: updated.pdsURL,
                authServerIssuer: updated.authServer.issuer,
                authorizationEndpoint: updated.authServer.authorizationEndpoint,
                tokenEndpoint: updated.authServer.tokenEndpoint,
                pushedAuthorizationRequestEndpoint: updated.authServer.pushedAuthorizationRequestEndpoint
            ))
        }
        return result
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
