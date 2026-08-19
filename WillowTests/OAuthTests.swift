//
//  OAuthTests.swift
//  WillowTests
//

import Testing
import Foundation
import CryptoKit
@testable import Willow

struct OAuthTests {

    // MARK: - PKCE

    @Test func codeVerifierIsWithinRFCLengthBounds() {
        let verifier = PKCE.generateCodeVerifier()
        #expect(verifier.count >= 43 && verifier.count <= 128)
    }

    @Test func codeVerifierIsURLSafe() {
        let verifier = PKCE.generateCodeVerifier()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(verifier.unicodeScalars.allSatisfy(allowed.contains))
    }

    @Test func codeVerifiersAreNotReused() {
        let a = PKCE.generateCodeVerifier()
        let b = PKCE.generateCodeVerifier()
        #expect(a != b)
    }

    @Test func codeChallengeIsDeterministicSHA256() {
        // RFC 7636 Appendix B's worked example.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCE.codeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    // MARK: - DPoP proof

    @Test func dpopProofHasThreeBase64URLSegments() throws {
        let key = P256.Signing.PrivateKey()
        let proof = try DPoPProof.makeProof(
            method: "post",
            url: URL(string: "https://pds.example/xrpc/com.atproto.server.createSession")!,
            key: key
        )
        let segments = proof.split(separator: ".")
        #expect(segments.count == 3)
        #expect(segments.allSatisfy { !$0.contains("+") && !$0.contains("/") && !$0.contains("=") })
    }

    @Test func dpopProofHeaderDeclaresES256AndEmbedsPublicKey() throws {
        let key = P256.Signing.PrivateKey()
        let proof = try DPoPProof.makeProof(
            method: "GET",
            url: URL(string: "https://pds.example/xrpc/app.bsky.feed.getTimeline")!,
            key: key
        )
        let header = try decodeJOSESegment(proof.split(separator: ".")[0])
        #expect(header["typ"] as? String == "dpop+jwt")
        #expect(header["alg"] as? String == "ES256")
        let jwk = try #require(header["jwk"] as? [String: Any])
        #expect(jwk["kty"] as? String == "EC")
        #expect(jwk["crv"] as? String == "P-256")
        #expect((jwk["x"] as? String)?.isEmpty == false)
        #expect((jwk["y"] as? String)?.isEmpty == false)
    }

    @Test func dpopProofPayloadNormalizesMethodAndStripsFragment() throws {
        let key = P256.Signing.PrivateKey()
        let url = URL(string: "https://pds.example/xrpc/foo?x=1#ignored")!
        let proof = try DPoPProof.makeProof(method: "post", url: url, key: key, nonce: "server-nonce")
        let payload = try decodeJOSESegment(proof.split(separator: ".")[1])
        #expect(payload["htm"] as? String == "POST")
        #expect(payload["htu"] as? String == "https://pds.example/xrpc/foo?x=1")
        #expect(payload["nonce"] as? String == "server-nonce")
        #expect(payload["jti"] != nil)
        #expect(payload["iat"] != nil)
    }

    @Test func dpopProofSignatureVerifiesAgainstItsOwnEmbeddedKey() throws {
        let key = P256.Signing.PrivateKey()
        let proof = try DPoPProof.makeProof(
            method: "GET",
            url: URL(string: "https://pds.example/xrpc/app.bsky.actor.getProfile")!,
            key: key
        )
        let segments = proof.split(separator: ".").map(String.init)
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signatureData = try #require(base64URLDecode(segments[2]))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        #expect(key.publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test func dpopProofIncludesAccessTokenHashWhenProvided() throws {
        let key = P256.Signing.PrivateKey()
        let accessToken = "some-access-token"
        let proof = try DPoPProof.makeProof(
            method: "GET",
            url: URL(string: "https://pds.example/xrpc/app.bsky.feed.getTimeline")!,
            key: key,
            accessToken: accessToken
        )
        let payload = try decodeJOSESegment(proof.split(separator: ".")[1])
        let expectedHash = PKCE.base64URLEncode(Data(SHA256.hash(data: Data(accessToken.utf8))))
        #expect(payload["ath"] as? String == expectedHash)
    }

    // MARK: - Client metadata

    @Test func clientMetadataDeclaresDPoPBindingAndNativeApp() {
        let metadata = OAuthClientMetadata.metadataDocument
        #expect(metadata["token_endpoint_auth_method"] as? String == "none")
        #expect(metadata["dpop_bound_access_tokens"] as? Bool == true)
        #expect(metadata["application_type"] as? String == "native")
        #expect(metadata["client_id"] as? String == OAuthClientMetadata.clientID.absoluteString)
        let redirectURIs = try? #require(metadata["redirect_uris"] as? [String])
        #expect(redirectURIs == [OAuthClientMetadata.redirectURI.absoluteString])
    }

    @Test func clientMetadataIsValidJSON() throws {
        let data = try JSONSerialization.data(withJSONObject: OAuthClientMetadata.metadataDocument)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["client_name"] as? String == "Willow")
    }

    // MARK: - Helpers

    private func decodeJOSESegment(_ segment: Substring) throws -> [String: Any] {
        let data = try #require(base64URLDecode(String(segment)))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
