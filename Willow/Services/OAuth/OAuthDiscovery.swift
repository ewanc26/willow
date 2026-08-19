//
//  OAuthDiscovery.swift
//  Willow
//

import Foundation

/// The authorization/token/PAR endpoints for one AT Protocol OAuth flow,
/// resolved from a handle or PDS URL rather than hardcoded — every PDS can, in
/// principle, point at its own authorization server.
struct OAuthServerMetadata: Sendable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let pushedAuthorizationRequestEndpoint: URL
}

enum OAuthDiscoveryError: LocalizedError {
    case invalidPDSURL
    case missingField(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPDSURL: return "That PDS URL doesn't look valid."
        case .missingField(let field): return "The authorization server's metadata is missing \(field)."
        case .httpError(let code): return "Discovery request failed (HTTP \(code))."
        }
    }
}

/// Resolves an authorization server for a PDS, per
/// https://atproto.com/specs/oauth#authorization-server-discovery.
enum OAuthDiscovery {

    /// Given the PDS a user is signing into, finds and parses its
    /// authorization server's OAuth metadata.
    ///
    /// This is a two-hop resolution: the PDS publishes which authorization
    /// server protects it (`oauth-protected-resource`), and that server
    /// separately publishes its own endpoints (`oauth-authorization-server`).
    /// For Bluesky's own PDSes today the two coincide, but a client shouldn't
    /// assume that.
    static func resolveAuthorizationServer(forPDS pdsURL: URL) async throws -> OAuthServerMetadata {
        let authServerIssuer = try await resolveProtectedResourceIssuer(pdsURL: pdsURL)
        return try await fetchAuthorizationServerMetadata(issuer: authServerIssuer)
    }

    private static func resolveProtectedResourceIssuer(pdsURL: URL) async throws -> URL {
        let metadataURL = pdsURL.appending(path: ".well-known/oauth-protected-resource")
        let json = try await fetchJSON(metadataURL)
        guard let issuerString = json["authorization_servers"] as? [String], let first = issuerString.first,
              let issuer = URL(string: first) else {
            throw OAuthDiscoveryError.missingField("authorization_servers")
        }
        return issuer
    }

    private static func fetchAuthorizationServerMetadata(issuer: URL) async throws -> OAuthServerMetadata {
        let metadataURL = issuer.appending(path: ".well-known/oauth-authorization-server")
        let json = try await fetchJSON(metadataURL)

        func requireURL(_ key: String) throws -> URL {
            guard let string = json[key] as? String, let url = URL(string: string) else {
                throw OAuthDiscoveryError.missingField(key)
            }
            return url
        }

        return OAuthServerMetadata(
            issuer: (json["issuer"] as? String) ?? issuer.absoluteString,
            authorizationEndpoint: try requireURL("authorization_endpoint"),
            tokenEndpoint: try requireURL("token_endpoint"),
            pushedAuthorizationRequestEndpoint: try requireURL("pushed_authorization_request_endpoint")
        )
    }

    private static func fetchJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OAuthDiscoveryError.httpError(code)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthDiscoveryError.missingField("(unparseable response body)")
        }
        return json
    }
}
