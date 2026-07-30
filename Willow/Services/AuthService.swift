//
//  AuthService.swift
//  Willow
//

import Foundation

/// Abstraction over how Willow signs in and restores sessions.
///
/// Willow currently authenticates with an **app password** — the only method
/// ATProtoKit's stable API supports today. This protocol exists so a future
/// OAuth backend can replace the implementation without touching the UI or
/// session-management layers. See AGENTS.md for the auth roadmap.
protocol AuthService: AnyObject, Sendable {

    /// Attempts to restore a previously persisted session.
    ///
    /// Returns `nil` when there is nothing to restore; throws when a restore was
    /// attempted (credentials existed) but failed, so the caller can surface it.
    func restoreSession() async throws -> Account?

    /// Signs in with an identifier (handle or DID) and an app password against
    /// the given PDS.
    func signIn(identifier: String, appPassword: String, pdsURL: URL) async throws -> Account

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
