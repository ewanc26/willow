//
//  OAuthTokenStore.swift
//  Willow
//

import Foundation
import Security

/// Keychain storage for OAuth access/refresh tokens, keyed by the same
/// `dpopKeyIdentifier` as the DPoP signing key so the two are always looked up
/// and torn down together.
///
/// Separate from ATProtoKit's `AppleSecureKeychain` — that type is shaped
/// around the app-password flow (access/refresh token + password), not the
/// DPoP-bound token pair OAuth produces.
struct OAuthTokenStore: Sendable {

    private let account: String
    private let service = "uk.ewancroft.Willow.oauth-tokens"

    init(identifier: UUID) {
        self.account = identifier.uuidString
    }

    struct StoredTokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let subjectDID: String
        let pdsURL: URL
        let authServerIssuer: String
        let authorizationEndpoint: URL
        let tokenEndpoint: URL
        let pushedAuthorizationRequestEndpoint: URL
    }

    func save(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw DPoPError.keychain(status) }
    }

    func load() throws -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(StoredTokens.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw DPoPError.keychain(status)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
