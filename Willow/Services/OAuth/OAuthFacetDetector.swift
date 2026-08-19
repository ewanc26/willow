//
//  OAuthFacetDetector.swift
//  Willow
//

import Foundation

/// Hand-rolled rich-text facet detection for the OAuth compose path.
///
/// ATProtoKit's `ATFacetParser` does this for app-password sessions via
/// `ATProtoBluesky.createPostRecord`, but it's internal to the SDK and the
/// OAuth path never touches ATProtoKit (see `ATProtoClient.createPost`). This
/// covers the same three facet types Bluesky's own clients detect from plain
/// text: mentions, links, and hashtags.
///
/// Byte offsets, not character offsets: `index.byteStart`/`byteEnd` in a
/// `app.bsky.richtext.facet` are **UTF-8 byte offsets** into the post text
/// (see AGENTS.md's "UTF-8 byte offsets for rich-text facets" note). A
/// `Range<String.Index>` from `NSRegularExpression`/`Range(_:in:)` is a
/// Unicode-scalar-based range, not a byte range, so every match's start/end
/// must go through `text.utf8.distance(from:to:)` against `text.startIndex`
/// before it's usable in the wire format.
enum OAuthFacetDetector {

    struct DetectedFacet {
        enum Kind {
            case mention(handle: String)
            case link(uri: String)
            case tag(String)
        }
        let byteStart: Int
        let byteEnd: Int
        let kind: Kind
    }

    private static let mentionPattern = try! NSRegularExpression(
        pattern: #"(?<![\w@.])@([a-zA-Z0-9][a-zA-Z0-9-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9-]*)+)"#
    )
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s]+[^\s.,;:!?'")\]]"#
    )
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"(?<![\w#])#([^\s#]+)"#
    )

    /// Detects mention/link/tag facets in `text`, in left-to-right order,
    /// with byte offsets already converted for the wire format. Pure and
    /// synchronous — mention handles are returned undetected (resolution to
    /// a DID requires a network call, done separately by the caller).
    static func detect(in text: String) -> [DetectedFacet] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var facets: [(range: Range<String.Index>, kind: DetectedFacet.Kind)] = []

        mentionPattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let full = Range(match.range, in: text), let handleRange = Range(match.range(at: 1), in: text) else { return }
            facets.append((full, .mention(handle: String(text[handleRange]))))
        }
        linkPattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let full = Range(match.range, in: text) else { return }
            facets.append((full, .link(uri: String(text[full]))))
        }
        tagPattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let full = Range(match.range, in: text), let tagRange = Range(match.range(at: 1), in: text) else { return }
            facets.append((full, .tag(String(text[tagRange]))))
        }

        facets.sort { $0.range.lowerBound < $1.range.lowerBound }

        return facets.map { entry in
            let byteStart = text.utf8.distance(from: text.startIndex, to: entry.range.lowerBound)
            let byteEnd = text.utf8.distance(from: text.startIndex, to: entry.range.upperBound)
            return DetectedFacet(byteStart: byteStart, byteEnd: byteEnd, kind: entry.kind)
        }
    }

    /// Builds the wire-format `facets` array for a `createRecord` body,
    /// resolving each mention's handle to a DID. A mention that fails to
    /// resolve (deleted/typo'd handle) is dropped rather than failing the
    /// whole post — the same tolerance a mis-typed `@handle` gets when it's
    /// just left as plain, unlinked text.
    static func buildFacetsJSON(
        for text: String,
        resolveHandle: (String) async -> String?
    ) async -> [[String: Any]] {
        var result: [[String: Any]] = []
        for facet in detect(in: text) {
            let feature: [String: Any]?
            switch facet.kind {
            case .mention(let handle):
                guard let did = await resolveHandle(handle) else { continue }
                feature = ["$type": "app.bsky.richtext.facet#mention", "did": did]
            case .link(let uri):
                feature = ["$type": "app.bsky.richtext.facet#link", "uri": uri]
            case .tag(let tag):
                feature = ["$type": "app.bsky.richtext.facet#tag", "tag": tag]
            }
            guard let feature else { continue }
            result.append([
                "index": ["byteStart": facet.byteStart, "byteEnd": facet.byteEnd],
                "features": [feature]
            ])
        }
        return result
    }
}
