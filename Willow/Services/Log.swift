//
//  Log.swift
//  Willow
//

import os

/// Central `os.Logger` categories for Willow.
///
/// Logs go to the unified logging system, so they can be read with, e.g.:
///   `log show --predicate 'subsystem == "uk.ewancroft.Willow"' --last 5m`
/// or streamed live with `log stream --predicate 'subsystem == "uk.ewancroft.Willow"'`.
///
/// Only non-secret values (handles, DIDs, PDS URLs, error descriptions) are ever
/// logged, and only those are marked `.public`. Passwords and tokens must never
/// be passed to a logger. See AGENTS.md.
enum Log {
    nonisolated static let auth = Logger(subsystem: "uk.ewancroft.Willow", category: "auth")
    nonisolated static let timeline = Logger(subsystem: "uk.ewancroft.Willow", category: "timeline")
}
