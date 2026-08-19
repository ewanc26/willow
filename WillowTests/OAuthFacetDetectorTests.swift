//
//  OAuthFacetDetectorTests.swift
//  WillowTests
//

import Testing
import Foundation
@testable import Willow

struct OAuthFacetDetectorTests {

    @Test func noFacetsInPlainText() {
        let facets = OAuthFacetDetector.detect(in: "just some plain text, nothing special")
        #expect(facets.isEmpty)
    }

    @Test func detectsALink() {
        let text = "check this out: https://example.com/path"
        let facets = OAuthFacetDetector.detect(in: text)
        #expect(facets.count == 1)
        guard case .link(let uri) = facets[0].kind else { Issue.record("expected a link facet"); return }
        #expect(uri == "https://example.com/path")
        let expectedStart = text.utf8.distance(from: text.startIndex, to: text.range(of: "https://")!.lowerBound)
        #expect(facets[0].byteStart == expectedStart)
        #expect(facets[0].byteEnd == text.utf8.count)
    }

    @Test func detectsAHashtag() {
        let facets = OAuthFacetDetector.detect(in: "loving #bluesky today")
        #expect(facets.count == 1)
        guard case .tag(let tag) = facets[0].kind else { Issue.record("expected a tag facet"); return }
        #expect(tag == "bluesky")
    }

    @Test func detectsAMentionHandleWithoutResolvingIt() {
        let facets = OAuthFacetDetector.detect(in: "hey @alice.bsky.social nice post")
        #expect(facets.count == 1)
        guard case .mention(let handle) = facets[0].kind else { Issue.record("expected a mention facet"); return }
        #expect(handle == "alice.bsky.social")
    }

    /// The core correctness requirement: byte offsets, not character/scalar
    /// offsets, so a multi-byte-UTF-8 prefix must shift them correctly.
    @Test func byteOffsetsAccountForMultiByteUTF8Prefix() {
        let text = "café ☕️ #bluesky"
        let facets = OAuthFacetDetector.detect(in: text)
        #expect(facets.count == 1)
        guard case .tag = facets[0].kind else { Issue.record("expected a tag facet"); return }

        // "café ☕️ " is 4 ASCII chars + 'é' (2 UTF-8 bytes) + space (1) +
        // the coffee emoji with variation selector (7 bytes) + space (1)
        // = 4 + 2 + 1 + 7 + 1 = 15 bytes before the '#'.
        let prefix = "café ☕️ "
        #expect(facets[0].byteStart == prefix.utf8.count)
        #expect(facets[0].byteEnd == text.utf8.count)
    }

    @Test func detectsMultipleFacetsInOrder() {
        let text = "@bob.bsky.social check https://example.com #cool"
        let facets = OAuthFacetDetector.detect(in: text)
        #expect(facets.count == 3)
        guard case .mention = facets[0].kind else { Issue.record("expected mention first"); return }
        guard case .link = facets[1].kind else { Issue.record("expected link second"); return }
        guard case .tag = facets[2].kind else { Issue.record("expected tag third"); return }
        // Ranges must not overlap and must be strictly increasing.
        #expect(facets[0].byteEnd <= facets[1].byteStart)
        #expect(facets[1].byteEnd <= facets[2].byteStart)
    }

    @Test func buildFacetsJSONDropsUnresolvableMentions() async {
        let json = await OAuthFacetDetector.buildFacetsJSON(for: "hi @nobody.example and #ok") { _ in nil }
        // The mention resolver always returns nil, so only the tag survives.
        #expect(json.count == 1)
        let features = json[0]["features"] as? [[String: Any]]
        #expect(features?.first?["$type"] as? String == "app.bsky.richtext.facet#tag")
    }

    @Test func buildFacetsJSONResolvesMentionToDID() async {
        let json = await OAuthFacetDetector.buildFacetsJSON(for: "hi @alice.bsky.social") { handle in
            handle == "alice.bsky.social" ? "did:plc:abc123" : nil
        }
        #expect(json.count == 1)
        let features = json[0]["features"] as? [[String: Any]]
        #expect(features?.first?["$type"] as? String == "app.bsky.richtext.facet#mention")
        #expect(features?.first?["did"] as? String == "did:plc:abc123")
    }
}
