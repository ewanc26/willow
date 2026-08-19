//
//  SessionPersistence.swift
//  Willow
//

import Foundation

/// Persists the *non-secret* pointers needed to restore a session on the next
/// launch.
///
/// The actual tokens live in the Keychain, managed by ATProtoKit under a
/// keychain identifier (a `UUID`). Here we only remember which identifier to
/// reopen, the PDS URL, and display metadata. Nothing secret is ever written to
/// `UserDefaults` — see AGENTS.md: tokens belong in the Keychain only.
struct SessionPersistence: Sendable {

    private enum Key {
        static let keychainID = "willow.session.keychainID"
        static let pdsURL = "willow.session.pdsURL"
        static let did = "willow.session.did"
        static let handle = "willow.session.handle"
        static let isOAuth = "willow.session.isOAuth"
    }

    /// Everything needed to reopen a persisted session.
    struct Stored: Sendable {
        let keychainID: UUID
        let pdsURL: URL
        let account: Account
        /// `true` when `keychainID` names an `OAuthTokenStore`/`DPoPKeyStore`
        /// pair rather than an `AppleSecureKeychain` app-password session.
        let isOAuth: Bool
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var stored: Stored? {
        guard
            let idString = defaults.string(forKey: Key.keychainID),
            let keychainID = UUID(uuidString: idString),
            let pdsString = defaults.string(forKey: Key.pdsURL),
            let pdsURL = URL(string: pdsString),
            let did = defaults.string(forKey: Key.did),
            let handle = defaults.string(forKey: Key.handle)
        else { return nil }

        return Stored(
            keychainID: keychainID,
            pdsURL: pdsURL,
            account: Account(did: did, handle: handle),
            isOAuth: defaults.bool(forKey: Key.isOAuth)
        )
    }

    func save(keychainID: UUID, pdsURL: URL, account: Account, isOAuth: Bool = false) {
        defaults.set(keychainID.uuidString, forKey: Key.keychainID)
        defaults.set(pdsURL.absoluteString, forKey: Key.pdsURL)
        defaults.set(account.did, forKey: Key.did)
        defaults.set(account.handle, forKey: Key.handle)
        defaults.set(isOAuth, forKey: Key.isOAuth)
    }

    func clear() {
        [Key.keychainID, Key.pdsURL, Key.did, Key.handle, Key.isOAuth]
            .forEach(defaults.removeObject(forKey:))
    }
}
