//
//  OAuthPostMapping.swift
//  Willow
//

import Foundation

/// Maps raw `app.bsky.feed.getTimeline` JSON into Willow's domain
/// `TimelinePost`, mirroring `ATProtoClient`'s ATProtoKit-based mapping —
/// the OAuth path doesn't go through ATProtoKit's lexicon decoding (see
/// `AuthService.swift`), so this works from plain JSON dictionaries instead.
enum OAuthPostMapping {

    static func makePost(from json: [String: Any]) -> TimelinePost? {
        guard
            let uri = json["uri"] as? String,
            let cid = json["cid"] as? String,
            let author = json["author"] as? [String: Any],
            let handle = author["handle"] as? String
        else { return nil }

        let record = json["record"] as? [String: Any]
        let text = record?["text"] as? String ?? ""
        let createdAt = (record?["createdAt"] as? String).flatMap(parseDate)
            ?? (json["indexedAt"] as? String).flatMap(parseDate)
            ?? Date()
        let viewer = json["viewer"] as? [String: Any]

        return TimelinePost(
            id: uri,
            cid: cid,
            authorDisplayName: author["displayName"] as? String,
            authorHandle: handle,
            authorAvatarURL: (author["avatar"] as? String).flatMap(URL.init(string:)),
            text: text,
            createdAt: createdAt,
            embed: (json["embed"] as? [String: Any]).flatMap(makeEmbed),
            replyCount: json["replyCount"] as? Int ?? 0,
            repostCount: json["repostCount"] as? Int ?? 0,
            likeCount: json["likeCount"] as? Int ?? 0,
            likeURI: viewer?["like"] as? String,
            repostURI: viewer?["repost"] as? String
        )
    }

    // MARK: - Embed mapping

    private static func makeEmbed(_ json: [String: Any]) -> PostEmbed? {
        guard let type = json["$type"] as? String else { return nil }
        switch type {
        case "app.bsky.embed.images#view":
            let images = (json["images"] as? [[String: Any]] ?? []).compactMap(makeImage)
            return images.isEmpty ? nil : .images(images)

        case "app.bsky.embed.external#view":
            guard let external = json["external"] as? [String: Any] else { return nil }
            return makeExternal(external).map(PostEmbed.external)

        case "app.bsky.embed.record#view":
            guard let record = json["record"] as? [String: Any] else { return nil }
            return makeQuote(record).map(PostEmbed.quote)

        case "app.bsky.embed.recordWithMedia#view":
            guard
                let recordField = json["record"] as? [String: Any],
                let innerRecord = recordField["record"] as? [String: Any]
            else { return nil }
            let quote = makeQuote(innerRecord)
            let media = (json["media"] as? [String: Any]).flatMap(makeMedia)
            switch (quote, media) {
            case let (.some(quote), .some(media)): return .quoteWithMedia(quote, media: media)
            case let (.some(quote), nil): return .quote(quote)
            case let (nil, .some(.images(images))): return .images(images)
            case let (nil, .some(.external(external))): return .external(external)
            case (nil, nil): return nil
            }

        default:
            // Video, gallery, and any future/unknown embed types.
            return nil
        }
    }

    private static func makeImage(_ json: [String: Any]) -> EmbedImage? {
        guard
            let thumbString = json["thumb"] as? String, let thumbnailURL = URL(string: thumbString),
            let fullString = json["fullsize"] as? String, let fullSizeURL = URL(string: fullString)
        else { return nil }

        var ratio: Double?
        if let aspect = json["aspectRatio"] as? [String: Any],
           let width = (aspect["width"] as? NSNumber)?.doubleValue,
           let height = (aspect["height"] as? NSNumber)?.doubleValue,
           height > 0 {
            ratio = width / height
        }

        return EmbedImage(
            thumbnailURL: thumbnailURL,
            fullSizeURL: fullSizeURL,
            altText: json["alt"] as? String ?? "",
            aspectRatio: ratio
        )
    }

    private static func makeExternal(_ json: [String: Any]) -> EmbedExternal? {
        guard let uriString = json["uri"] as? String, let url = URL(string: uriString) else { return nil }
        return EmbedExternal(
            url: url,
            title: json["title"] as? String ?? "",
            description: json["description"] as? String ?? "",
            thumbnailURL: (json["thumb"] as? String).flatMap(URL.init(string:))
        )
    }

    private static func makeMedia(_ json: [String: Any]) -> EmbedMedia? {
        guard let type = json["$type"] as? String else { return nil }
        switch type {
        case "app.bsky.embed.images#view":
            let images = (json["images"] as? [[String: Any]] ?? []).compactMap(makeImage)
            return images.isEmpty ? nil : .images(images)
        case "app.bsky.embed.external#view":
            guard let external = json["external"] as? [String: Any] else { return nil }
            return makeExternal(external).map(EmbedMedia.external)
        default:
            return nil
        }
    }

    /// Resolves a quoted record, distinguishing a viewable post
    /// (`app.bsky.embed.record#viewRecord`) from an unavailable one (not
    /// found, blocked, detached) or a non-post record — Willow only renders
    /// the former today, same as the ATProtoKit-based mapping.
    private static func makeQuote(_ json: [String: Any]) -> QuotedPost? {
        guard
            json["$type"] as? String == "app.bsky.embed.record#viewRecord",
            let uri = json["uri"] as? String,
            let author = json["author"] as? [String: Any],
            let handle = author["handle"] as? String
        else { return nil }

        let value = json["value"] as? [String: Any]
        return QuotedPost(
            id: uri,
            authorDisplayName: author["displayName"] as? String,
            authorHandle: handle,
            authorAvatarURL: (author["avatar"] as? String).flatMap(URL.init(string:)),
            text: value?["text"] as? String ?? ""
        )
    }

    // MARK: - Dates

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: string) ?? iso8601.date(from: string)
    }
}
