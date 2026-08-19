//
//  NotificationRowView.swift
//  Willow
//

import SwiftUI

/// Renders a single notification: avatar, author, reason, and timestamp.
///
/// Deliberately one row per notification — the official app groups consecutive
/// likes/reposts on the same post ("Alice and 3 others liked your post") but
/// that grouping is left as a follow-up; see `AppNotification`'s doc comment.
struct NotificationRowView: View {

    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    avatar

                    Text(notification.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(notification.indexedAt, format: .relative(presentation: .numeric))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(reasonText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .opacity(notification.isRead ? 0.6 : 1)
    }

    private var icon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .frame(width: 20)
            .padding(.top, 4)
    }

    private var avatar: some View {
        AsyncImage(url: notification.authorAvatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
    }

    private var iconName: String {
        switch notification.reason {
        case .like: "heart.fill"
        case .repost: "arrow.2.squarepath"
        case .follow: "person.fill.badge.plus"
        case .mention: "at"
        case .reply: "bubble.left.fill"
        case .quote: "quote.opening"
        case .other: "bell.fill"
        }
    }

    private var iconColor: Color {
        switch notification.reason {
        case .like: .red
        case .repost: .green
        case .follow: .blue
        case .mention, .reply, .quote, .other: .accentColor
        }
    }

    private var reasonText: String {
        switch notification.reason {
        case .like: "liked your post"
        case .repost: "reposted your post"
        case .follow: "followed you"
        case .mention: "mentioned you"
        case .reply: "replied to your post"
        case .quote: "quoted your post"
        case .other(let raw): raw
        }
    }
}
