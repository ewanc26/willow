//
//  DPoPKeyStore.swift
//  Willow
//

import Foundation
import CryptoKit
import Security

/// Owns the P-256 keypair used to sign DPoP proofs (RFC 9449), one per OAuth
/// session, persisted in the Keychain so proofs survive relaunch and stay bound
/// to the tokens they were issued for.
///
/// This is deliberately separate from ATProtoKit's `AppleSecureKeychain` (which
/// only stores access/refresh tokens and a password) — DPoP needs a raw signing
/// key, not a token string.
final class DPoPKeyStore: Sendable {

    private let account: String
    private let service = "uk.ewancroft.Willow.dpop"

    /// - Parameter identifier: Scopes the key to one OAuth session, mirroring
    ///   the `keychainID` pattern `SessionPersistence` already uses for
    ///   app-password sessions.
    init(identifier: UUID) {
        self.account = identifier.uuidString
    }

    /// Returns the session's DPoP key, generating and persisting a new one on
    /// first use.
    func key() throws -> P256.Signing.PrivateKey {
        if let existing = try load() { return existing }
        let generated = P256.Signing.PrivateKey()
        try save(generated)
        return generated
    }

    /// Deletes the key. Call this alongside clearing the rest of an OAuth
    /// session so a signed-out account can't leave a stray key behind.
    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func load() throws -> P256.Signing.PrivateKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeValue(forKey: kSecReturnData as String)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try P256.Signing.PrivateKey(rawRepresentation: data)
        case errSecItemNotFound:
            return nil
        default:
            throw DPoPError.keychain(status)
        }
    }

    private func save(_ key: P256.Signing.PrivateKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw DPoPError.keychain(status) }
    }
}

enum DPoPError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "DPoP keychain error (\(status))."
        }
    }
}
