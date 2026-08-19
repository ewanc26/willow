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
/// - Note: An OAuth-signed-in `Account`'s `TimelineService`/`InteractionService`
///   calls route through `Services/OAuth/OAuthXRPCClient.swift` rather than
///   ATProtoKit — ATProtoKit's `SessionConfiguration` only signs requests
///   with a plain Bearer header, but OAuth's tokens are DPoP-bound and need
///   every request proof-signed. `OAuthXRPCClient` does that, plus the
///   `DPoP-Nonce` retry and access-token refresh both endpoints need.
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
