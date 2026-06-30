//
//  AIEmojiSuggester.swift
//  PayUp
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

@MainActor
@Observable
final class AISnarkRemarkGenerator {
    static let shared = AISnarkRemarkGenerator()

    private static let instructions = """
    You write playful, mildly snarky one-liners for a bill-splitting app.
    React to the bill title and amount. Keep it friendly, not mean, and never
    shame people for necessities, health, rent, debt, or emergencies.

    Reply with EXACTLY ONE short sentence under 85 characters.
    No quotes. No hashtags. No markdown. No emoji unless it fits naturally.

    Examples:
    Input: Dinner at Mario's, USD 86.40 -> That pasta better have sung opera.
    Input: Coffee, USD 7.25 -> A tiny bean mortgage, impressive.
    Input: Groceries, USD 143.10 -> The fridge demanded tribute again.
    """

    private var hotSession: LanguageModelSession?

    private init() {
        prepareHotSession()
    }

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private func prepareHotSession() {
        guard SystemLanguageModel.default.isAvailable else {
            hotSession = nil
            return
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        hotSession = session
    }

    func remark(for title: String, amount: Double, currencyCode: String) async -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, amount > 0 else { return "" }

        if hotSession == nil {
            prepareHotSession()
        }
        guard let session = hotSession else {
            return Self.fallbackRemark(for: trimmedTitle, amount: amount)
        }

        hotSession = nil
        prepareHotSession()

        do {
            let prompt = "Title: \"\(trimmedTitle)\"\nAmount: \(currencyCode) \(String(format: "%.2f", amount))"
            let response = try await session.respond(to: prompt)
            try Task.checkCancellation()
            return Self.clean(response.content)
                ?? Self.fallbackRemark(for: trimmedTitle, amount: amount)
        } catch is CancellationError {
            return ""
        } catch {
            #if DEBUG
            print("=== AISnarkRemarkGenerator failed: \(error) ===")
            #endif
            return Self.fallbackRemark(for: trimmedTitle, amount: amount)
        }
    }

    private static func clean(_ content: String) -> String? {
        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .replacingOccurrences(of: "\n", with: " ")

        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 85 {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 85)
        let shortened = String(trimmed[..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return shortened.isEmpty ? nil : "\(shortened)..."
    }

    private static func fallbackRemark(for title: String, amount: Double) -> String {
        let lowercasedTitle = title.lowercased()

        if lowercasedTitle.contains("coffee") || lowercasedTitle.contains("latte") {
            return amount >= 10
                ? "That caffeine came with shareholder confidence."
                : "A tiny bean mortgage, impressive."
        }

        if lowercasedTitle.contains("dinner") || lowercasedTitle.contains("pizza") || lowercasedTitle.contains("restaurant") {
            return amount >= 100
                ? "That meal better include a standing ovation."
                : "A delicious little wallet ambush."
        }

        if lowercasedTitle.contains("grocery") || lowercasedTitle.contains("market") {
            return amount >= 150
                ? "The fridge demanded tribute again."
                : "Responsible spending, suspiciously mature."
        }

        if amount >= 250 {
            return "Your wallet just requested a wellness check."
        }

        if amount >= 100 {
            return "Bold choice. The budget has entered the chat."
        }

        if amount < 15 {
            return "Tiny spend, dramatic paperwork."
        }

        return "A perfectly normal expense, allegedly."
    }
}
