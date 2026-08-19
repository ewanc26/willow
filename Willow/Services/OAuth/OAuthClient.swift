//
//  OAuthClient.swift
//  Willow
//

import Foundation
import CryptoKit
import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The tokens an OAuth flow produces: DPoP-bound, so they're useless without
/// the private key they were minted for — `dpopKeyIdentifier` names the
/// `DPoPKeyStore` entry holding it.
struct OAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    /// The DID this session authenticates as, from the token response's `sub`.
    let subjectDID: String
    let pdsURL: URL
    let authServer: OAuthServerMetadata
    let dpopKeyIdentifier: UUID
    /// The authorization server's most recent DPoP nonce, needed to keep
    /// signing token-endpoint requests (e.g. on refresh) without an extra
    /// round trip to learn it again.
    let authServerNonce: String?
    /// The resource server's (PDS) most recent DPoP nonce — a separate nonce
    /// space from `authServerNonce`, learned the first time a resource
    /// request is made. See `OAuthXRPCClient`.
    var resourceServerNonce: String? = nil
}

enum OAuthError: LocalizedError {
    case invalidHandleOrPDS
    case userCancelled
    case missingCallbackCode
    case parFailed(String)
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHandleOrPDS: return "That handle or PDS host doesn't look valid."
        case .userCancelled: return "Sign-in was cancelled."
        case .missingCallbackCode: return "The authorization server didn't return a code."
        case .parFailed(let detail): return "Couldn't start sign-in: \(detail)"
        case .tokenExchangeFailed(let detail): return "Couldn't complete sign-in: \(detail)"
        }
    }
}

/// Drives the AT Protocol OAuth authorization-code flow end to end: PAR,
/// browser-based consent, and the code-for-tokens exchange — all DPoP-signed
/// per https://atproto.com/specs/oauth.
///
/// This produces valid, DPoP-bound `OAuthTokens`. Willow's
/// `TimelineService`/`InteractionService` calls don't go through ATProtoKit
/// for an OAuth-signed-in account — its `SessionConfiguration` only speaks
/// plain Bearer auth — but through `OAuthXRPCClient`, a small DPoP-aware XRPC
/// transport built for exactly this. See `ATProtoClient`'s OAuth branch of
/// each protocol method.
@MainActor
final class OAuthClient: NSObject {

    /// Runs the full flow for signing in to `pdsURL`, returning once the user
    /// has completed (or cancelled) the browser consent step and the resulting
    /// code has been exchanged for tokens.
    func signIn(pdsURL: URL) async throws -> OAuthTokens {
        let authServer = try await OAuthDiscovery.resolveAuthorizationServer(forPDS: pdsURL)

        let sessionID = UUID()
        let keyStore = DPoPKeyStore(identifier: sessionID)
        let dpopKey = try keyStore.key()

        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let state = PKCE.generateCodeVerifier()

        let (requestURI, parNonce) = try await pushAuthorizationRequest(
            authServer: authServer,
            dpopKey: dpopKey,
            codeChallenge: challenge,
            state: state
        )

        let callbackURL = try await presentConsent(authServer: authServer, requestURI: requestURI)
        let (code, returnedState) = try parseCallback(callbackURL)
        guard returnedState == state else {
            throw OAuthError.tokenExchangeFailed("The authorization response's state didn't match — discarding it.")
        }

        let (tokens, tokenNonce) = try await exchangeCode(
            code: code,
            verifier: verifier,
            authServer: authServer,
            dpopKey: dpopKey,
            initialNonce: parNonce
        )

        return OAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn,
            subjectDID: tokens.subjectDID,
            pdsURL: pdsURL,
            authServer: authServer,
            dpopKeyIdentifier: sessionID,
            authServerNonce: tokenNonce
        )
    }

    // MARK: - Pushed Authorization Request

    /// POSTs the authorization parameters to the PAR endpoint up front (rather
    /// than putting them in the browser URL), per
    /// https://atproto.com/specs/oauth#authorization-request — this is what
    /// keeps the actual request parameters (scope, PKCE challenge, DPoP
    /// binding) out of a URL a user could screenshot or a proxy could log.
    ///
    /// DPoP proofs to a fresh endpoint are expected to be rejected once with a
    /// `use_dpop_nonce` error carrying the nonce to retry with; that first
    /// rejection is the normal path here, not a failure.
    private func pushAuthorizationRequest(
        authServer: OAuthServerMetadata,
        dpopKey: P256.Signing.PrivateKey,
        codeChallenge: String,
        state: String
    ) async throws -> (requestURI: String, nonce: String?) {
        let parameters: [String: String] = [
            "client_id": OAuthClientMetadata.clientID.absoluteString,
            "redirect_uri": OAuthClientMetadata.redirectURI.absoluteString,
            "response_type": "code",
            "scope": "atproto transition:generic",
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "state": state
        ]
        let body = formEncode(parameters)

        var nonce: String?
        for attempt in 0..<2 {
            let proof = try DPoPProof.makeProof(
                method: "POST",
                url: authServer.pushedAuthorizationRequestEndpoint,
                key: dpopKey,
                nonce: nonce
            )

            var request = URLRequest(url: authServer.pushedAuthorizationRequestEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(proof, forHTTPHeaderField: "DPoP")
            request.httpBody = Data(body.utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let returnedNonce = http?.value(forHTTPHeaderField: "DPoP-Nonce")

            if http?.statusCode == 201, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let requestURI = json["request_uri"] as? String {
                return (requestURI, returnedNonce ?? nonce)
            }

            // A `use_dpop_nonce` error on the first attempt is the expected
            // handshake; retry once with the server's nonce. Anything else, or
            // a second failure, is a real error.
            if attempt == 0, let returnedNonce, isDPoPNonceError(data) {
                nonce = returnedNonce
                continue
            }

            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http?.statusCode ?? -1)"
            throw OAuthError.parFailed(message)
        }
        throw OAuthError.parFailed("Exhausted DPoP nonce retries.")
    }

    private func isDPoPNonceError(_ body: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        return (json["error"] as? String) == "use_dpop_nonce"
    }

    // MARK: - Browser consent

    private func presentConsent(authServer: OAuthServerMetadata, requestURI: String) async throws -> URL {
        var components = URLComponents(url: authServer.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthClientMetadata.clientID.absoluteString),
            URLQueryItem(name: "request_uri", value: requestURI)
        ]
        guard let authorizeURL = components?.url else {
            throw OAuthError.parFailed("Couldn't build the authorization URL.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: OAuthClientMetadata.callbackURLScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.userCancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.missingCallbackCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: OAuthError.parFailed("Couldn't present the sign-in browser."))
            }
        }
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCallbackCode
        }
        return (code, items.first(where: { $0.name == "state" })?.value)
    }

    // MARK: - Token exchange

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
        let subjectDID: String
    }

    private func exchangeCode(
        code: String,
        verifier: String,
        authServer: OAuthServerMetadata,
        dpopKey: P256.Signing.PrivateKey,
        initialNonce: String?
    ) async throws -> (TokenResponse, String?) {
        let parameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthClientMetadata.redirectURI.absoluteString,
            "client_id": OAuthClientMetadata.clientID.absoluteString,
            "code_verifier": verifier
        ]
        let body = formEncode(parameters)

        var nonce = initialNonce
        for attempt in 0..<2 {
            let proof = try DPoPProof.makeProof(
                method: "POST",
                url: authServer.tokenEndpoint,
                key: dpopKey,
                nonce: nonce
            )

            var request = URLRequest(url: authServer.tokenEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(proof, forHTTPHeaderField: "DPoP")
            request.httpBody = Data(body.utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let returnedNonce = http?.value(forHTTPHeaderField: "DPoP-Nonce")

            if http?.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                guard
                    let accessToken = json["access_token"] as? String,
                    let subjectDID = json["sub"] as? String
                else {
                    throw OAuthError.tokenExchangeFailed("The token response was missing required fields.")
                }
                let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
                let response = TokenResponse(
                    accessToken: accessToken,
                    refreshToken: json["refresh_token"] as? String,
                    expiresIn: expiresIn,
                    subjectDID: subjectDID
                )
                return (response, returnedNonce ?? nonce)
            }

            if attempt == 0, let returnedNonce, isDPoPNonceError(data) {
                nonce = returnedNonce
                continue
            }

            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http?.statusCode ?? -1)"
            throw OAuthError.tokenExchangeFailed(message)
        }
        throw OAuthError.tokenExchangeFailed("Exhausted DPoP nonce retries.")
    }

    private func formEncode(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                let allowed = CharacterSet.urlQueryAllowed.subtracting(.init(charactersIn: "+&="))
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .sorted()
            .joined(separator: "&")
    }
}

extension OAuthClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
