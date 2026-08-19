//
//  OAuthXRPCClient.swift
//  Willow
//

import Foundation
import CryptoKit

/// DPoP-authenticated XRPC calls against the PDS (resource server) for an
/// OAuth-signed-in session — the transport ATProtoKit doesn't provide (see
/// `AuthService.swift`). Handles the `DPoP-Nonce` retry the same way
/// `OAuthClient.swift` does for the authorization server, plus refreshing an
/// expired access token via the token endpoint before retrying once more.
enum OAuthXRPCClient {

    enum XRPCError: LocalizedError {
        case http(Int, String)
        case invalidResponse
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let message): return "Request failed (HTTP \(code)): \(message)"
            case .invalidResponse: return "The server returned an unexpected response."
            case .refreshFailed(let detail): return "Couldn't refresh sign-in: \(detail)"
            }
        }
    }

    /// Performs one DPoP-authenticated XRPC request under `tokens.pdsURL`,
    /// transparently retrying on a `use_dpop_nonce` challenge and refreshing
    /// the access token once on an `invalid_token` rejection. Returns the
    /// decoded JSON body and the tokens to keep going forward — callers must
    /// persist these if they differ from what was passed in, since a nonce or
    /// a refresh may have changed them.
    static func request(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        tokens: OAuthTokens,
        dpopKey: P256.Signing.PrivateKey
    ) async throws -> (json: [String: Any], tokens: OAuthTokens) {
        var tokens = tokens
        var didRefresh = false

        for _ in 0..<3 {
            var components = URLComponents(
                url: tokens.pdsURL.appending(path: "xrpc/\(path)"),
                resolvingAgainstBaseURL: false
            )
            if !query.isEmpty {
                components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            }
            guard let url = components?.url else { throw XRPCError.invalidResponse }

            var request = URLRequest(url: url)
            request.httpMethod = method
            if let body {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let proof = try DPoPProof.makeProof(
                method: method,
                url: url,
                key: dpopKey,
                nonce: tokens.resourceServerNonce,
                accessToken: tokens.accessToken
            )
            request.setValue(proof, forHTTPHeaderField: "DPoP")
            request.setValue("DPoP \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if let newNonce = http?.value(forHTTPHeaderField: "DPoP-Nonce") {
                tokens.resourceServerNonce = newNonce
            }

            if let code = http?.statusCode, (200...299).contains(code) {
                guard !data.isEmpty else { return ([:], tokens) }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw XRPCError.invalidResponse
                }
                return (json, tokens)
            }

            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorCode = errorBody?["error"] as? String

            if errorCode == "use_dpop_nonce", tokens.resourceServerNonce != nil {
                continue // retry immediately with the nonce just captured above
            }
            if http?.statusCode == 401, !didRefresh {
                tokens = try await refresh(tokens: tokens, dpopKey: dpopKey)
                didRefresh = true
                continue
            }

            let message = (errorBody?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "unknown error"
            throw XRPCError.http(http?.statusCode ?? -1, message)
        }
        throw XRPCError.http(-1, "Exhausted retries.")
    }

    // MARK: - Token refresh

    private static func refresh(tokens: OAuthTokens, dpopKey: P256.Signing.PrivateKey) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw XRPCError.refreshFailed("No refresh token available.")
        }
        let parameters: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthClientMetadata.clientID.absoluteString
        ]
        let allowed = CharacterSet.urlQueryAllowed.subtracting(.init(charactersIn: "+&="))
        let body = parameters
            .map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .sorted()
            .joined(separator: "&")

        var nonce = tokens.authServerNonce
        for attempt in 0..<2 {
            let proof = try DPoPProof.makeProof(method: "POST", url: tokens.authServer.tokenEndpoint, key: dpopKey, nonce: nonce)
            var request = URLRequest(url: tokens.authServer.tokenEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(proof, forHTTPHeaderField: "DPoP")
            request.httpBody = Data(body.utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let returnedNonce = http?.value(forHTTPHeaderField: "DPoP-Nonce")
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if http?.statusCode == 200, let accessToken = json?["access_token"] as? String {
                return OAuthTokens(
                    accessToken: accessToken,
                    refreshToken: (json?["refresh_token"] as? String) ?? tokens.refreshToken,
                    expiresIn: (json?["expires_in"] as? NSNumber)?.doubleValue ?? 3600,
                    subjectDID: tokens.subjectDID,
                    pdsURL: tokens.pdsURL,
                    authServer: tokens.authServer,
                    dpopKeyIdentifier: tokens.dpopKeyIdentifier,
                    authServerNonce: returnedNonce ?? nonce,
                    resourceServerNonce: tokens.resourceServerNonce
                )
            }

            if attempt == 0, let returnedNonce, (json?["error"] as? String) == "use_dpop_nonce" {
                nonce = returnedNonce
                continue
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http?.statusCode ?? -1)"
            throw XRPCError.refreshFailed(message)
        }
        throw XRPCError.refreshFailed("Exhausted DPoP nonce retries.")
    }

    // MARK: - AT URI parsing

    /// Splits an `at://did/collection/rkey` record URI into its parts, needed
    /// to build `com.atproto.repo.deleteRecord` calls (unlike/un-repost) —
    /// ATProtoKit's `deleteRecord(.recordURI(atURI:))` does this internally,
    /// but the OAuth path doesn't go through ATProtoKit.
    static func parseRecordURI(_ uri: String) -> (repo: String, collection: String, rkey: String)? {
        guard uri.hasPrefix("at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return (String(parts[0]), String(parts[1]), String(parts[2]))
    }
}
