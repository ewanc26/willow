//
//  PKCE.swift
//  Willow
//

import Foundation
import CryptoKit

/// RFC 7636 Proof Key for Code Exchange, using the S256 method required by the
/// AT Protocol OAuth profile (https://atproto.com/specs/oauth#requirements-for-clients).
enum PKCE {

    /// A random, high-entropy code verifier: 32 random bytes, base64url-encoded
    /// (43 characters, well within the 43–128 character range RFC 7636 requires).
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return base64URLEncode(Data(bytes))
    }

    /// The S256 code challenge for a verifier: `BASE64URL(SHA256(verifier))`.
    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
