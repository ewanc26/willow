//
//  PostRowView.swift
//  Willow
//

import SwiftUI

/// Renders a single timeline post: avatar, author line, text, timestamp, and
/// like/repost actions.
struct PostRowView: View {

    let post: TimelinePost
    /// Called after a successful like/unlike or repost/un-repost so the caller
    /// can update its stored copy of the post (optimistic UI lives one level up,
    /// in `TimelineView`, since this view only holds a value-type snapshot).
    var onToggleLike: () -> Void = {}
    var onToggleRepost: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                authorLine

                if !post.text.isEmpty {
                    Text(post.text)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if let embed = post.embed {
                    EmbedView(embed: embed)
                        .padding(.top, 2)
                }

                interactionBar
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var interactionBar: some View {
        HStack(spacing: 20) {
            Label("\(post.replyCount)", systemImage: "bubble.right")
                .foregroundStyle(.secondary)

            Button(action: onToggleRepost) {
                Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
            }
            .foregroundStyle(post.isReposted ? .green : .secondary)

            Button(action: onToggleLike) {
                Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
            }
            .foregroundStyle(post.isLiked ? .red : .secondary)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private var avatar: some View {
        AsyncImage(url: post.authorAvatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var authorLine: some View {
        HStack(spacing: 4) {
            Text(post.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text("@\(post.authorHandle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(post.createdAt, format: .relative(presentation: .numeric))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
