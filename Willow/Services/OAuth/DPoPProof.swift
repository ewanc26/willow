//
//  DPoPProof.swift
//  Willow
//

import Foundation
import CryptoKit

/// Builds RFC 9449 DPoP proof JWTs: a short-lived, per-request token bound to
/// the session's P-256 key, presented alongside (and cryptographically tying
/// the client to) every OAuth-authenticated request.
enum DPoPProof {

    /// - Parameters:
    ///   - method: The HTTP method of the request this proof accompanies.
    ///   - url: The request's target URL, without a fragment (per RFC 9449 §4.2).
    ///   - key: The session's DPoP signing key.
    ///   - nonce: The `DPoP-Nonce` most recently returned by the server, if any.
    ///     The authorization server and PDS both mint their own nonces; the
    ///     first request to each is expected to be rejected with one, which the
    ///     caller must retry with the nonce attached here.
    ///   - accessToken: When presenting this proof alongside a bearer-style
    ///     Authorization header (i.e. resource requests, not the token
    ///     endpoint), its SHA-256 hash goes in the `ath` claim so the proof and
    ///     the token can't be mixed and matched.
    static func makeProof(
        method: String,
        url: URL,
        key: P256.Signing.PrivateKey,
        nonce: String? = nil,
        accessToken: String? = nil
    ) throws -> String {
        let header = JOSEHeader(jwk: JWK(publicKey: key.publicKey))
        let headerJSON = try encode(header)

        var payload = DPoPClaims(
            htm: method.uppercased(),
            htu: strippingFragment(url),
            iat: Int(Date().timeIntervalSince1970),
            jti: UUID().uuidString,
            nonce: nonce,
            ath: nil
        )
        if let accessToken {
            let hash = SHA256.hash(data: Data(accessToken.utf8))
            payload.ath = PKCE.base64URLEncode(Data(hash))
        }
        let payloadJSON = try encode(payload)

        let signingInput = "\(headerJSON).\(payloadJSON)"
        let signature = try key.signature(for: Data(signingInput.utf8))
        let signatureEncoded = PKCE.base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(signatureEncoded)"
    }

    private static func strippingFragment(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return PKCE.base64URLEncode(try encoder.encode(value))
    }
}

private struct JOSEHeader: Encodable {
    let typ = "dpop+jwt"
    let alg = "ES256"
    let jwk: JWK
}

/// The public half of an ES256 key, as a JSON Web Key — embedded in every DPoP
/// proof so the server can verify the signature without a prior registration
/// step.
private struct JWK: Encodable {
    let kty = "EC"
    let crv = "P-256"
    let x: String
    let y: String

    init(publicKey: P256.Signing.PublicKey) {
        // `x963Representation` is `0x04 || x (32 bytes) || y (32 bytes)` for an
        // uncompressed P-256 point.
        let raw = publicKey.x963Representation
        let coordinateLength = (raw.count - 1) / 2
        let xBytes = raw.dropFirst().prefix(coordinateLength)
        let yBytes = raw.dropFirst(1 + coordinateLength)
        self.x = PKCE.base64URLEncode(Data(xBytes))
        self.y = PKCE.base64URLEncode(Data(yBytes))
    }
}

private struct DPoPClaims: Encodable {
    let htm: String
    let htu: String
    let iat: Int
    let jti: String
    let nonce: String?
    var ath: String?
}
