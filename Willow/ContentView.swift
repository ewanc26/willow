//
//  ContentView.swift
//  Willow
//
//  Created by Ewan Croft on 30/07/2026.
//

import SwiftUI

/// Root view. Routes between launch, sign-in, and the signed-in timeline based
/// on the shared `SessionStore`.
struct ContentView: View {

    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.phase {
        case .launching:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .signedOut:
            LoginView()

        case .signedIn(let account):
            TimelineView(account: account)
        }
    }
}
