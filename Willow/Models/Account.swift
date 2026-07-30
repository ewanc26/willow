//
//  Account.swift
//  Willow
//

import Foundation

/// The signed-in user. Identified by DID (stable, canonical) with the handle
/// kept alongside for display. Per AGENTS.md, DIDs identify repositories while
/// handles are mutable, so DID is the source of truth for identity.
struct Account: Sendable, Hashable {
    let did: String
    let handle: String
}
