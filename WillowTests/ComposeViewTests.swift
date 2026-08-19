//
//  ComposeViewTests.swift
//  WillowTests
//

import Testing
@testable import Willow

struct ComposeViewTests {

    @Test func emptyTextLeavesFullLimit() {
        #expect(ComposeView.remainingCharacters(for: "") == ComposeView.maxLength)
    }

    @Test func plainASCIICountsOnePerCharacter() {
        #expect(ComposeView.remainingCharacters(for: "hello", limit: 10) == 5)
    }

    @Test func multiScalarEmojiCountsAsOneGrapheme() {
        // A family emoji (man, woman, girl, boy ZWJ sequence) is four Unicode
        // scalars but one grapheme cluster — and one character against the
        // 300-limit, matching what Bluesky actually counts.
        let family = "👨‍👩‍👧‍👦"
        #expect(ComposeView.remainingCharacters(for: family, limit: 10) == 9)
    }

    @Test func combiningMarkCountsAsOneGrapheme() {
        // "e" + U+0301 COMBINING ACUTE ACCENT renders as "é" — one grapheme.
        let combining = "e\u{0301}"
        #expect(ComposeView.remainingCharacters(for: combining, limit: 10) == 9)
    }

    @Test func overLimitIsNegative() {
        let text = String(repeating: "a", count: 305)
        #expect(ComposeView.remainingCharacters(for: text) == -5)
    }
}
