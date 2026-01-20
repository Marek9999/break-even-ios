//
//  EmojiTextField.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI
import UIKit

/// A text field that only accepts emoji input - uses an emoji picker sheet for fast, responsive input
struct EmojiTextField: View {
    @Binding var text: String
    var placeholder: String = "😀"
    var size: CGFloat = 44
    
    @State private var showEmojiPicker = false
    
    var body: some View {
        Button {
            showEmojiPicker = true
        } label: {
            ZStack {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: size * 0.6))
                        .opacity(0.4)
                } else {
                    Text(text)
                        .font(.system(size: size * 0.6))
                }
            }
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Color.accentSecondary.opacity(0.3)), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(selectedEmoji: $text)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Fast emoji picker sheet with common categories
struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEmoji: String
    
    // Common emojis organized by category for quick access
    private let foodEmojis = ["🍕", "🍔", "🍟", "🌮", "🍜", "🍣", "🍱", "🍛", "🍝", "🥗", "🥪", "🍳", "🥐", "🍞", "🧀", "🥩", "🍗", "🍖", "🌭", "🥓", "🍿", "🧈", "🥚", "🥞"]
    private let drinkEmojis = ["☕", "🍵", "🧃", "🥤", "🍺", "🍻", "🥂", "🍷", "🍸", "🍹", "🧋", "🥛", "🍶", "🫖"]
    private let shoppingEmojis = ["🛒", "🛍️", "💳", "💵", "💰", "🧾", "📦", "🎁", "👕", "👖", "👗", "👠", "👟", "👜"]
    private let transportEmojis = ["🚗", "🚕", "🚌", "🚇", "✈️", "🚢", "🚲", "⛽", "🅿️", "🚦", "🛣️", "🚁", "🚀", "🛴"]
    private let entertainmentEmojis = ["🎬", "🎮", "🎵", "🎤", "🎸", "🎹", "🎯", "🎲", "🎭", "🎪", "🎨", "📺", "📱", "💻"]
    private let homeEmojis = ["🏠", "🏢", "🔑", "🛋️", "🛏️", "🚿", "🧹", "🧺", "💡", "🔌", "📡", "🛠️", "🔧", "🪛"]
    private let healthEmojis = ["💊", "🏥", "🩺", "💉", "🩹", "🧴", "🧼", "🪥", "💪", "🧘", "🏃", "🚴", "⚕️", "🩻"]
    private let otherEmojis = ["📝", "📅", "💼", "📚", "✏️", "📎", "🔔", "⭐", "❤️", "✅", "❌", "⚠️", "💡", "🎉"]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    emojiSection(title: "Food & Dining", emojis: foodEmojis)
                    emojiSection(title: "Drinks", emojis: drinkEmojis)
                    emojiSection(title: "Shopping", emojis: shoppingEmojis)
                    emojiSection(title: "Transport", emojis: transportEmojis)
                    emojiSection(title: "Entertainment", emojis: entertainmentEmojis)
                    emojiSection(title: "Home & Utilities", emojis: homeEmojis)
                    emojiSection(title: "Health & Fitness", emojis: healthEmojis)
                    emojiSection(title: "Other", emojis: otherEmojis)
                }
                .padding()
            }
            .navigationTitle("Select Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func emojiSection(title: String, emojis: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.title)
                            .frame(width: 40, height: 40)
                            .background(
                                selectedEmoji == emoji
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Emoji TextField") {
    struct PreviewWrapper: View {
        @State private var emoji = ""
        
        var body: some View {
            VStack(spacing: 20) {
                EmojiTextField(text: $emoji)
                Text("Selected: \(emoji.isEmpty ? "None" : emoji)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

#Preview("Emoji Picker Sheet") {
    struct PreviewWrapper: View {
        @State private var emoji = "🍕"
        
        var body: some View {
            EmojiPickerSheet(selectedEmoji: $emoji)
        }
    }
    
    return PreviewWrapper()
}
