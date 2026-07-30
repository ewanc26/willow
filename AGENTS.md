# AGENTS.md

Guidance for agents working on Willow, a native SwiftUI **Bluesky / AT Protocol** client targeting iOS and macOS from one shared codebase.

Read this in full before making changes. Where it conflicts with what the code actually does, the code wins — update this file to match reality rather than letting it drift.

## Status — read first

The repository is still the **initial Xcode SwiftData template**: a `WillowApp` entry point, a placeholder `ContentView` listing `Item` records (a `@Model` with a single `timestamp`), and the default test targets. **None of the Bluesky functionality exists yet.** Treat `Item.swift` and the list UI in `ContentView.swift` as scaffolding to be replaced, not as an established pattern to imitate. A successful build proves the template compiles — nothing about login, feeds, or posting works or has been verified.

## Repository map

- `Willow/WillowApp.swift` — `@main` `App`, constructs the shared SwiftData `ModelContainer`. Currently registers only `Item`.
- `Willow/ContentView.swift` — root view. Uses `#if os(macOS)` / `#if os(iOS)` to branch a `NavigationSplitView` (macOS) vs plain content (iOS); this inline-branching pattern is how cross-platform divergence should be handled.
- `Willow/Item.swift` — placeholder SwiftData model.
- `Willow/Willow.entitlements` — enables CloudKit and push (`aps-environment`). These are template defaults; confirm they are actually needed before building features on them rather than assuming they were a deliberate decision.
- `Willow/Assets.xcassets`, `Info.plist` — app assets and configuration.
- `WillowTests/` — unit tests using the **Swift Testing** framework (`@Test`, `#expect`), not XCTest.
- `WillowUITests/` — UI tests using **XCUIAutomation**.

`Willow` is both the app name and the module name; keep them consistent. Add new source files to the `Willow` app target, and mirror non-trivial logic with tests in `WillowTests`.

## Architecture and conventions

- **SwiftUI-first.** Define UI in a view's `body`; conform views to `View`. Keep shared code shared and isolate platform differences behind `#if os(...)` rather than forking whole views per platform.
- **No Combine.** Use Swift `async`/`await` and `AsyncSequence` throughout — `URLSession`'s async APIs, structured concurrency, `@MainActor` isolation for UI state. This is a hard house rule.
- **State:** `@State private var` for local view state, `let` for constants. Lean on the type system; avoid force-unwrapping.
- **Naming/formatting:** PascalCase types, camelCase members, 4-space indentation, clear method separation. Comment non-obvious logic only.
- **Scope discipline.** Make only the change requested; do not reformat or refactor unrelated code, and inspect the worktree before editing so unrelated local work is preserved.

## AT Protocol correctness and safety

These matter the moment real feature work begins; hold to them from the first networked line.

- **DIDs identify repositories; handles are mutable.** Resolve handle → DID → PDS and key state by DID, never by handle. Support custom PDS hosts, not just `bsky.social`.
- **Treat every PDS/AppView response as untrusted.** Parse defensively — a malformed record must never crash the client. Bound response sizes, string lengths, and pagination (cursors must terminate and stay bound to one DID/PDS). Rich-text facets use **UTF-8 byte offsets**, not `String`/UTF-16 offsets — a common and silent source of bugs.
- **Preserve exact identifiers.** AT URIs, CIDs, and rkeys are contracts; validate a URI's DID, collection, and rkey before any update or delete. Never substitute a display handle for a DID.
- **Auth & secrets.** Sessions come from `com.atproto.server.createSession`, refreshed via `com.atproto.server.refreshSession`. Store access/refresh tokens in the **Keychain** — never in SwiftData, `UserDefaults`, plaintext files, or logs. Provide a sign-out path that fully wipes session state. Never commit tokens, app passwords, `.env`, or captured authenticated traffic.
- **Never fabricate success.** Do not return a "done" state for an endpoint or path that isn't actually implemented and verified.

### Talking to the network

Reads/writes live under the `app.bsky.*` and `com.atproto.*` lexicons (`app.bsky.feed.getTimeline`, `app.bsky.feed.getPostThread`, `app.bsky.notification.listNotifications`, `com.atproto.repo.createRecord` for `app.bsky.feed.post`). When behaviour isn't fully pinned down by the lexicon spec, cross-check against reference implementations rather than guessing:

- **`bluesky-social/atproto`** (TypeScript) — canonical; the tiebreaker when implementations disagree, since the real PDS/AppView are built against it. Checked out locally at **`../atproto`**; its `lexicons/` directory (`app.bsky.*`, `com.atproto.*` JSON schemas) is the authoritative source for field names, required fields, and error codes — read the lexicon before choosing them, rather than guessing from generated names.
- **`ATProtoKit`** (Swift) — the closest reference for a native Swift client: session handling, XRPC request shaping, and record types. Evaluate it as a dependency before hand-rolling XRPC.
- **`../wolfram`** — Ewan's own C AT Protocol SDK powering the sibling console clients (`../channel-blue`, `../cobalt`). Not directly usable from Swift, but a consistent reference for how these problems were solved across the wider toolset.

Keep protocol-shaped code (session, XRPC, record (de)serialisation) behind a clear boundary so it stays testable and, where practical, reusable outside Willow's UI layer.

## Working inside Xcode

Prefer the `xcode-tools` MCP commands over shell and `xcodebuild`; raw `ls`/`find`/`cat` may each prompt the user, so use `XcodeGlob`/`XcodeGrep`/`XcodeRead`/`XcodeLS` for exploration.

- **Build:** `BuildProject`.
- **Fast per-file diagnostics:** `XcodeRefreshCodeIssuesInFile` — sanity-check edits before a full build.
- **Try a snippet in context:** `RunCodeSnippet`.
- **Tests:** `RunAllTests` / `RunSomeTests` (Swift Testing for units, XCUIAutomation for UI).
- **Apple APIs:** `DocumentationSearch` — use liberally for SwiftUI, SwiftData, and anything newer than training data (Liquid Glass, FoundationModels, current SwiftUI navigation, etc.). Assume unfamiliar APIs are real and new; look them up rather than guessing.

Add or update a test for changed non-UI logic. A green build is not evidence that a networked or auth flow works — those need verification against a real PDS with a disposable account.

## Commits

- Atomic conventional commits, one logical change each, scoped by area (`feat(feed)`, `fix(auth)`, `docs(agents)`). Don't mix a code change with a docs update.
- **No AI co-author trailer.** AI assistance is welcome; committed credit goes to human authors. Omit `Co-authored-by:` for AI agents entirely, matching the convention across Ewan's other repositories.
- Don't stage build products (`build/`, DerivedData, `.app`/`.xctest` under `Products/`), secrets, or unrelated worktree changes.
