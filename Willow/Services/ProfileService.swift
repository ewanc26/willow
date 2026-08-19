//
//  ProfileService.swift
//  Willow
//

import Foundation

/// Abstraction over fetching an actor's profile, kept separate from the SDK
/// so views depend only on domain types.
protocol ProfileService: AnyObject, Sendable {

    /// Fetches the profile for a DID or handle.
    func profile(forActor actor: String) async throws -> Profile
}
