//
//  EmojiTextField.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI

// MARK: - Emoji Extensions

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

extension String {
    func onlyEmoji() -> String {
        return self.filter { $0.isEmoji }
    }
    
    var firstEmoji: String {
        guard let first = self.first(where: { $0.isEmoji }) else { return "" }
        return String(first)
    }
}

// MARK: - Public EmojiTextField View

struct EmojiTextField: View {
    @Binding var text: String
    var placeholder: String = "🍗"
    var size: CGFloat = 54
    
    @State private var showPicker = false
    
    var body: some View {
        Button {
            showPicker = true
        } label: {
            ZStack {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: size * 0.5))
                        .opacity(0.5)
                } else {
                    Text(text)
                        .font(.system(size: size * 0.6))
                }
            }
            .frame(width: size, height: size)
            .background(Color.accent.opacity(0.2))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            EmojiPickerSheet(selectedEmoji: $text)
                .presentationCompactAdaptation(.popover)
        }
    }
    
    init(text: Binding<String>, placeholder: String = "🍗", size: CGFloat = 54) {
        self._text = text
        self.placeholder = placeholder
        self.size = size
    }
    
    @available(*, deprecated, message: "isFocused is no longer used. Use init(text:placeholder:size:) instead.")
    init(text: Binding<String>, isFocused: Binding<Bool>?, placeholder: String = "🍗", size: CGFloat = 54) {
        self._text = text
        self.placeholder = placeholder
        self.size = size
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

#Preview("Emoji TextField with Value") {
    struct PreviewWrapper: View {
        @State private var emoji = "🍕"
        
        var body: some View {
            VStack(spacing: 20) {
                EmojiTextField(text: $emoji)
                Text("Selected: \(emoji)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

#Preview("Large Emoji TextField") {
    struct PreviewWrapper: View {
        @State private var emoji = "🎉"
        
        var body: some View {
            VStack(spacing: 20) {
                EmojiTextField(text: $emoji, size: 60)
                Text("Selected: \(emoji)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
