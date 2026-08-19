//
//  ComposeView.swift
//  Willow
//

import SwiftUI

/// A modal sheet for writing and posting new content.
struct ComposeView: View {

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful post so the caller can refresh its feed.
    var onPosted: () -> Void = {}

    @State private var text = ""
    @State private var isPosting = false
    @State private var postError: String?
    @FocusState private var isEditorFocused: Bool

    /// Bluesky's post length limit is measured in grapheme clusters, not
    /// UTF-8 bytes or UTF-16 code units.
    static let maxLength = 300

    /// `String.count` counts grapheme clusters (a `Character` is one visible
    /// glyph, however many Unicode scalars compose it — flags, skin-tone
    /// modifiers, combining marks), which is exactly what Bluesky's limit
    /// measures. A free function so `WillowTests` can verify that against
    /// specific tricky inputs without a view instance.
    static func remainingCharacters(for text: String, limit: Int = maxLength) -> Int {
        limit - text.count
    }

    private var remaining: Int { Self.remainingCharacters(for: text) }
    private var isOverLimit: Bool { remaining < 0 }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canPost: Bool { !trimmedText.isEmpty && !isOverLimit && !isPosting }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let postError {
                    Text(postError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                TextEditor(text: $text)
                    .focused($isEditorFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)

                HStack {
                    Spacer()
                    Text("\(remaining)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(isOverLimit ? .red : .secondary)
                }
            }
            .padding()
            .navigationTitle("New Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await post() } }
                            .disabled(!canPost)
                    }
                }
            }
        }
        .task { isEditorFocused = true }
        .interactiveDismissDisabled(isPosting)
    }

    private func post() async {
        isPosting = true
        postError = nil
        defer { isPosting = false }

        do {
            _ = try await session.composeService.createPost(text: trimmedText)
            onPosted()
            dismiss()
        } catch {
            postError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
