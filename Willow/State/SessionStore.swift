//
//  SessionStore.swift
//  Willow
//

import Foundation
import Observation

/// App-wide authentication state. Drives which root view is shown and owns the
/// client used for authenticated requests.
///
/// MainActor-isolated (the project default) so views can read `phase` directly.
@Observable
@MainActor
final class SessionStore {

    /// Where the app is in its auth lifecycle.
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn(Account)
    }

    private(set) var phase: Phase = .launching

    /// Non-nil while a sign-in attempt is being surfaced to the user.
    private(set) var signInError: String?
    private(set) var isSigningIn = false

    /// The concrete client, exposed to feature views through its protocols.
    let client: ATProtoClient

    init(client: ATProtoClient? = nil) {
        self.client = client ?? ATProtoClient()
    }

    var timelineService: TimelineService { client }
    var interactionService: InteractionService { client }
    var notificationService: NotificationService { client }
    var composeService: ComposeService { client }
    var threadService: ThreadService { client }
    var profileService: ProfileService { client }

    /// Called once at launch to restore any persisted session.
    func bootstrap() async {
        do {
            if let account = try await client.restoreSession() {
                phase = .signedIn(account)
            } else {
                phase = .signedOut
            }
        } catch {
            // Restore failed (e.g. expired refresh token); land on sign-in.
            phase = .signedOut
        }
    }

    func signIn(identifier: String, appPassword: String, pdsURL: URL) async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            let account = try await client.signIn(
                identifier: identifier,
                appPassword: appPassword,
                pdsURL: pdsURL
            )
            phase = .signedIn(account)
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signInWithOAuth(pdsURL: URL) async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            let account = try await client.signInWithOAuth(pdsURL: pdsURL)
            phase = .signedIn(account)
        } catch OAuthError.userCancelled {
            // User dismissed the sign-in browser; not an error worth showing.
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Clears a stale sign-in error, e.g. when the user switches between the
    /// OAuth and app-password forms.
    func clearSignInError() {
        signInError = nil
    }

    func signOut() async {
        await client.signOut()
        signInError = nil
        phase = .signedOut
    }
}
