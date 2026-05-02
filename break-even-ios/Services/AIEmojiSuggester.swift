//
//  AIEmojiSuggester.swift
//  break-even-ios
//
//  Thin wrapper around Apple's on-device Foundation Model. Asks the model to
//  pick a single emoji for an expense title. Falls back silently when the
//  framework is unavailable (older device, Apple Intelligence disabled,
//  unsupported region, etc.) – callers should layer this on top of a
//  deterministic suggester (see `EmojiSuggester`).
//
//  Design: every `suggest(for:)` call uses a *fresh* `LanguageModelSession`
//  and we keep one prewarmed session hot in the background. This avoids two
//  problems with reusing one session globally:
//    1. Concurrent `respond(to:)` calls on the same session (Apple's session
//       is single-context and will throw or stall under concurrent use).
//    2. The session transcript growing without bound, eventually hitting
//       `exceededContextWindowSize` and silently failing every request after.
//

import Foundation
import FoundationModels

@MainActor
@Observable
final class AIEmojiSuggester {
    static let shared = AIEmojiSuggester()
    
    /// Instructions are deliberately compact – keeps the per-request token
    /// cost low and lets the model focus on the single-emoji output rule.
    private static let instructions = """
    You suggest a single emoji that visually represents an expense title in a \
    bill-splitting app. Pick the most fitting emoji – food for restaurants, \
    a vehicle for transport, a gift for birthdays, etc.
    
    Reply with EXACTLY ONE emoji character and nothing else. No words, no \
    punctuation, no quotes.
    
    Examples:
    Input: "Dinner at Mario's"   -> 🍝
    Input: "Uber to airport"     -> 🚕
    Input: "Costco run"          -> 🛒
    Input: "Concert tickets"     -> 🎤
    Input: "Coffee with Sam"     -> ☕
    Input: "Birthday gift"       -> 🎁
    Input: "Beach trip Airbnb"   -> 🏖️
    """
    
    /// A pre-warmed session waiting to be handed out to the next request.
    /// `nil` while we're spinning the next one up or when Apple Intelligence
    /// is unavailable.
    private var hotSession: LanguageModelSession?
    
    /// `true` if Apple Intelligence is enabled on this device and the system
    /// language model is ready to be invoked. Re-checked on every access so
    /// toggling Apple Intelligence at runtime is picked up without an app
    /// restart.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
    
    private init() {
        prepareHotSession()
    }
    
    /// Spin up + prewarm a fresh session ready for the next request. Cheap –
    /// session init doesn't load model weights; `prewarm()` does that on a
    /// background thread.
    private func prepareHotSession() {
        guard SystemLanguageModel.default.isAvailable else {
            hotSession = nil
            return
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        hotSession = session
    }
    
    /// Returns a single emoji for `title`, or `nil` if the model is
    /// unavailable, the request fails, the response can't be parsed into an
    /// emoji, or the surrounding `Task` is cancelled. Each call uses a fresh
    /// session and immediately starts prewarming the next one, so back-to-back
    /// calls never share transcript history and never overlap on the same
    /// session.
    func suggest(for title: String) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Lazy availability re-check + recovery – if Apple Intelligence was
        // just enabled (or the previous session was torn down) we'll grab a
        // fresh one here.
        if hotSession == nil {
            prepareHotSession()
        }
        guard let session = hotSession else { return nil }
        
        // Hand off the hot session and immediately start prewarming the next
        // one in the background so the next request also gets a warm start.
        hotSession = nil
        prepareHotSession()
        
        do {
            let response = try await session.respond(to: "Title: \"\(trimmed)\"")
            try Task.checkCancellation()
            let firstEmoji = response.content.firstEmoji
            return firstEmoji.isEmpty ? nil : firstEmoji
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            print("=== AIEmojiSuggester failed: \(error) ===")
            #endif
            return nil
        }
    }
}
