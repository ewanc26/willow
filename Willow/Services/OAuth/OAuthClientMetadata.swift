//
//  OAuthClientMetadata.swift
//  Willow
//

import Foundation

/// Willow's AT Protocol OAuth client identity (https://atproto.com/specs/oauth#clients).
///
/// `clientID` must resolve to an HTTPS URL that serves the exact JSON
/// `metadataDocument` describes, with `Content-Type: application/json` — the
/// authorization server fetches it during PAR to learn the redirect URIs,
/// scopes, and DPoP requirement it should honor. **Willow has no web backend
/// yet, so nothing is hosted there today**; this is the known gap referenced
/// in the OAuth PR description. Until `https://willow.ewancroft.uk/oauth/client-metadata.json`
/// (or wherever this ends up living) actually serves this document, PAR
/// requests will fail at the authorization server with an unresolvable
/// `client_id`. Swap `clientID`/`redirectURI` for the real values once hosted.
enum OAuthClientMetadata {

    static let clientID = URL(string: "https://willow.ewancroft.uk/oauth/client-metadata.json")!

    /// A custom URL scheme, not the client_id's `https` host — the AT Protocol
    /// OAuth profile permits this for native/public clients (see "Native
    /// clients" at https://atproto.com/specs/oauth#clients), and it avoids
    /// needing associated-domains/universal-link infrastructure just to catch
    /// a redirect. Must be registered as a URL type in Info.plist and match
    /// what `ASWebAuthenticationSession` is told to listen for.
    static let redirectURI = URL(string: "uk.ewancroft.willow://oauth/callback")!
    static let callbackURLScheme = "uk.ewancroft.willow"

    /// The document `clientID` must serve verbatim.
    static var metadataDocument: [String: Any] {
        [
            "client_id": clientID.absoluteString,
            "client_name": "Willow",
            "client_uri": "https://willow.ewancroft.uk",
            "redirect_uris": [redirectURI.absoluteString],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": "atproto transition:generic",
            "application_type": "native",
            "token_endpoint_auth_method": "none",
            "dpop_bound_access_tokens": true
        ]
    }
}
