//
//  WillowApp.swift
//  Willow
//
//  Created by Ewan Croft on 30/07/2026.
//

import SwiftUI

@main
struct WillowApp: App {

    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .task { await session.bootstrap() }
        }
    }
}
