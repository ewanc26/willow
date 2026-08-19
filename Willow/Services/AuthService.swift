//
//  AuthService.swift
//  Willow
//

import Foundation

/// Abstraction over how Willow signs in and restores sessions.
///
/// Willow supports two sign-in paths: an **app password** (ATProtoKit's
/// stable, fully-wired API) and **OAuth** (the AT Protocol's recommended
/// flow, implemented by hand in `Services/OAuth/` since ATProtoKit doesn't
/// ship an OAuth client). This protocol exists so either backend can be
/// selected without touching the UI or session-management layers.
///
/// - Important: An OAuth-signed-in `Account` is real — the DID, handle, and
///   DPoP-bound tokens all come from a completed authorization-code exchange
///   — but `TimelineService`/`InteractionService` calls will currently fail
///   for it. Those go through ATProtoKit's `SessionConfiguration`, which
///   signs requests with a plain Bearer header; OAuth's DPoP-bound tokens
///   need every request proof-signed, which ATProtoKit doesn't yet support.
///   See `Services/OAuth/OAuthClient.swift` for the full explanation and
///   `ATProtoClient.signInWithOAuth` for where that gap surfaces.
protocol AuthService: AnyObject, Sendable {

    /// Attempts to restore a previously persisted session.
    ///
    /// Returns `nil` when there is nothing to restore; throws when a restore was
    /// attempted (credentials existed) but failed, so the caller can surface it.
    func restoreSession() async throws -> Account?

    /// Signs in with an identifier (handle or DID) and an app password against
    /// the given PDS.
    func signIn(identifier: String, appPassword: String, pdsURL: URL) async throws -> Account

    /// Signs in via the AT Protocol OAuth flow: PAR, browser-based user
    /// consent, and a DPoP-signed code exchange. See the type-level note above
    /// for what this does and doesn't wire up yet.
    func signInWithOAuth(pdsURL: URL) async throws -> Account

    /// Clears the local session. Best-effort; never throws.
    func signOut() async
}

/// User-facing authentication failures.
enum AuthError: LocalizedError {
    case missingCredentials
    case invalidPDSURL
    case notSignedIn
    case failed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Enter your handle and an app password."
        case .invalidPDSURL:
            return "That PDS URL doesn't look valid."
        case .notSignedIn:
            return "You're not signed in."
        case .failed(let underlying):
            return underlying
        }
    }
}
