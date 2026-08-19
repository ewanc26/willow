//
//  ProfileView.swift
//  Willow
//

import SwiftUI

/// A basic profile screen: avatar, name, handle, bio, and follower/following/
/// post counts. Deliberately doesn't include the actor's own post feed —
/// that's a reasonable next step, not a "basic" requirement, and would
/// duplicate a fair amount of TimelineView's paging logic to do well.
struct ProfileView: View {

    @Environment(SessionStore.self) private var session

    let actor: String

    @State private var profile: Profile?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        content
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let profile {
            ScrollView {
                VStack(spacing: 12) {
                    AsyncImage(url: profile.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())

                    VStack(spacing: 2) {
                        Text(profile.name)
                            .font(.title2.bold())
                        Text("@\(profile.handle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 24) {
                        stat("Posts", profile.postCount)
                        stat("Followers", profile.followerCount)
                        stat("Following", profile.followingCount)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
        } else if isLoading {
            ProgressView("Loading profile…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView {
                Label("Couldn't load this profile", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    private func stat(_ label: String, _ count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            profile = try await session.profileService.profile(forActor: actor)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
