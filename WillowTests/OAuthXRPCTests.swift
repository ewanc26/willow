//
//  OAuthXRPCTests.swift
//  WillowTests
//

import Testing
import Foundation
@testable import Willow

struct OAuthXRPCTests {

    // MARK: - AT URI parsing

    @Test func parseRecordURISplitsRepoCollectionAndRkey() {
        let parsed = OAuthXRPCClient.parseRecordURI("at://did:plc:abc123/app.bsky.feed.like/3jzfcijpj2z2a")
        #expect(parsed?.repo == "did:plc:abc123")
        #expect(parsed?.collection == "app.bsky.feed.like")
        #expect(parsed?.rkey == "3jzfcijpj2z2a")
    }

    @Test func parseRecordURIRejectsNonATURIs() {
        #expect(OAuthXRPCClient.parseRecordURI("https://example.com/not/an/at-uri") == nil)
    }

    @Test func parseRecordURIRejectsWrongSegmentCount() {
        #expect(OAuthXRPCClient.parseRecordURI("at://did:plc:abc123/app.bsky.feed.like") == nil)
    }

    // MARK: - Post mapping

    @Test func makePostReadsCoreFieldsAndCounts() {
        let json: [String: Any] = [
            "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
            "cid": "bafyabc",
            "author": ["did": "did:plc:abc", "handle": "alice.test", "displayName": "Alice"],
            "record": ["text": "hello", "createdAt": "2026-01-01T00:00:00.000Z"],
            "replyCount": 2,
            "repostCount": 3,
            "likeCount": 4,
            "viewer": ["like": "at://did:plc:abc/app.bsky.feed.like/1", "repost": "at://did:plc:abc/app.bsky.feed.repost/1"]
        ]
        let post = OAuthPostMapping.makePost(from: json)
        #expect(post?.id == "at://did:plc:abc/app.bsky.feed.post/xyz")
        #expect(post?.cid == "bafyabc")
        #expect(post?.authorHandle == "alice.test")
        #expect(post?.authorDisplayName == "Alice")
        #expect(post?.text == "hello")
        #expect(post?.replyCount == 2)
        #expect(post?.repostCount == 3)
        #expect(post?.likeCount == 4)
        #expect(post?.isLiked == true)
        #expect(post?.isReposted == true)
    }

    @Test func makePostReturnsNilWithoutRequiredFields() {
        #expect(OAuthPostMapping.makePost(from: ["cid": "bafyabc"]) == nil)
    }

    @Test func makePostDefaultsMissingCountsToZeroAndNoViewerState() {
        let json: [String: Any] = [
            "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
            "cid": "bafyabc",
            "author": ["did": "did:plc:abc", "handle": "alice.test"],
            "record": ["text": "hi", "createdAt": "2026-01-01T00:00:00.000Z"]
        ]
        let post = OAuthPostMapping.makePost(from: json)
        #expect(post?.replyCount == 0)
        #expect(post?.isLiked == false)
        #expect(post?.isReposted == false)
    }

    @Test func makePostParsesImageEmbed() {
        let json: [String: Any] = [
            "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
            "cid": "bafyabc",
            "author": ["did": "did:plc:abc", "handle": "alice.test"],
            "record": ["text": "look", "createdAt": "2026-01-01T00:00:00.000Z"],
            "embed": [
                "$type": "app.bsky.embed.images#view",
                "images": [
                    ["thumb": "https://example.com/thumb.jpg", "fullsize": "https://example.com/full.jpg", "alt": "a cat"]
                ]
            ]
        ]
        let post = OAuthPostMapping.makePost(from: json)
        guard case .images(let images) = post?.embed else {
            Issue.record("Expected an image embed")
            return
        }
        #expect(images.first?.altText == "a cat")
        #expect(images.first?.fullSizeURL.absoluteString == "https://example.com/full.jpg")
    }

    @Test func makePostParsesQuoteEmbed() {
        let json: [String: Any] = [
            "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
            "cid": "bafyabc",
            "author": ["did": "did:plc:abc", "handle": "alice.test"],
            "record": ["text": "quoting", "createdAt": "2026-01-01T00:00:00.000Z"],
            "embed": [
                "$type": "app.bsky.embed.record#view",
                "record": [
                    "$type": "app.bsky.embed.record#viewRecord",
                    "uri": "at://did:plc:def/app.bsky.feed.post/abc",
                    "author": ["did": "did:plc:def", "handle": "bob.test"],
                    "value": ["text": "original"]
                ]
            ]
        ]
        let post = OAuthPostMapping.makePost(from: json)
        guard case .quote(let quoted) = post?.embed else {
            Issue.record("Expected a quote embed")
            return
        }
        #expect(quoted.authorHandle == "bob.test")
        #expect(quoted.text == "original")
    }

    @Test func makePostIgnoresUnknownEmbedTypes() {
        let json: [String: Any] = [
            "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
            "cid": "bafyabc",
            "author": ["did": "did:plc:abc", "handle": "alice.test"],
            "record": ["text": "video?", "createdAt": "2026-01-01T00:00:00.000Z"],
            "embed": ["$type": "app.bsky.embed.video#view"]
        ]
        let post = OAuthPostMapping.makePost(from: json)
        #expect(post?.embed == nil)
    }
}
