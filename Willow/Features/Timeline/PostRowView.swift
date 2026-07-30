//
//  PostRowView.swift
//  Willow
//

import SwiftUI

/// Renders a single timeline post: avatar, author line, text, and timestamp.
struct PostRowView: View {

    let post: TimelinePost

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
            }
        }
        .padding(.vertical, 4)
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
