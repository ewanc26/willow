//
//  LoginView.swift
//  Willow
//

import SwiftUI

/// Sign-in screen. Collects a handle, an app password, and an optional custom
/// PDS host, then hands off to `SessionStore`.
struct LoginView: View {

    @Environment(SessionStore.self) private var session

    @State private var identifier = ""
    @State private var appPassword = ""
    @State private var pdsURLString = "https://bsky.social"
    @State private var showAppPasswordForm = false

    private var pdsURL: URL? {
        let trimmed = pdsURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" else { return nil }
        return url
    }

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !appPassword.isEmpty
            && pdsURL != nil
            && !session.isSigningIn
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Willow")
                    .font(.largeTitle.bold())
                Text("Sign in to Bluesky")
                    .foregroundStyle(.secondary)
            }

            if let error = session.signInError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if showAppPasswordForm {
                appPasswordForm
            } else {
                oauthForm
            }

            Button(showAppPasswordForm ? "Use OAuth instead" : "Sign in with an app password instead") {
                showAppPasswordForm.toggle()
                session.clearSignInError()
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 420)
    }

    // MARK: - OAuth

    private var oauthForm: some View {
        VStack(spacing: 12) {
            TextField("PDS host", text: $pdsURLString)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button(action: submitOAuth) {
                if session.isSigningIn {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with Bluesky")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pdsURL == nil || session.isSigningIn)
        }
    }

    private func submitOAuth() {
        guard let pdsURL else { return }
        Task { await session.signInWithOAuth(pdsURL: pdsURL) }
    }

    // MARK: - App password

    private var appPasswordForm: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                TextField("Handle (you.bsky.social)", text: $identifier)
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()

                SecureField("App password", text: $appPassword)
                    .textContentType(.password)

                TextField("PDS host", text: $pdsURLString)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
            }
            .textFieldStyle(.roundedBorder)

            Text("Use an app password from Bluesky Settings → App Passwords — not your main account password.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: submitAppPassword) {
                if session.isSigningIn {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
        }
    }

    private func submitAppPassword() {
        guard let pdsURL else { return }
        Task {
            await session.signIn(
                identifier: identifier,
                appPassword: appPassword,
                pdsURL: pdsURL
            )
        }
    }
}
