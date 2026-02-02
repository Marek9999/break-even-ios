//
//  EmojiTextField.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI
import UIKit

// MARK: - Emoji Extensions

extension Character {
    /// Check if a character is an emoji
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

extension String {
    /// Filter string to only contain emoji characters
    func onlyEmoji() -> String {
        return self.filter { $0.isEmoji }
    }
    
    /// Get the first emoji from the string
    var firstEmoji: String {
        guard let first = self.first(where: { $0.isEmoji }) else { return "" }
        return String(first)
    }
}

// MARK: - UIKit Emoji TextField

/// A UITextField subclass that forces the emoji keyboard to appear by default
final class UIEmojiTextField: UITextField {
    
    /// Callback when non-emoji input is rejected
    var onNonEmojiRejected: (() -> Void)?
    
    // Required for iOS 13+ to show the emoji keyboard
    override var textInputContextIdentifier: String? { "" }
    
    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes {
            if mode.primaryLanguage == "emoji" {
                self.keyboardType = .default
                return mode
            }
        }
        return nil
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        // Configure text field appearance
        textAlignment = .center
        font = .systemFont(ofSize: 28)
        backgroundColor = .clear
        borderStyle = .none
        
        // Disable autocorrection and suggestions to prevent non-emoji suggestions
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        
        // Listen for keyboard changes to reload input views
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inputModeDidChange),
            name: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func inputModeDidChange(_ notification: Notification) {
        guard isFirstResponder else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.reloadInputViews()
        }
    }
    
    /// Force switch back to emoji keyboard
    func switchToEmojiKeyboard() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadInputViews()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SwiftUI UIViewRepresentable Wrapper

/// The raw UIViewRepresentable wrapper for the emoji text field
private struct EmojiTextFieldRepresentable: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "🍗"
    var fontSize: CGFloat = 28
    
    func makeUIView(context: Context) -> UIEmojiTextField {
        let textField = UIEmojiTextField()
        textField.placeholder = placeholder
        textField.text = text
        textField.delegate = context.coordinator
        textField.font = .systemFont(ofSize: fontSize)
        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.required, for: .vertical)
        return textField
    }
    
    func updateUIView(_ uiView: UIEmojiTextField, context: Context) {
        // Only update if the text has changed externally
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextFieldRepresentable
        private let feedbackGenerator = UINotificationFeedbackGenerator()
        
        init(parent: EmojiTextFieldRepresentable) {
            self.parent = parent
            feedbackGenerator.prepare()
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Allow deletion
            if string.isEmpty {
                return true
            }
            
            // Check if the replacement string contains only emoji
            let filteredEmoji = string.onlyEmoji()
            
            if filteredEmoji.isEmpty {
                // Non-emoji input - reject with haptic feedback
                feedbackGenerator.notificationOccurred(.warning)
                
                // Try to switch back to emoji keyboard
                if let emojiTextField = textField as? UIEmojiTextField {
                    emojiTextField.switchToEmojiKeyboard()
                }
                
                return false
            }
            
            // Only allow the first emoji
            if let firstEmoji = filteredEmoji.first {
                // Replace entire text with just this emoji
                textField.text = String(firstEmoji)
                parent.text = String(firstEmoji)
                
                // Move cursor to end
                let endPosition = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
                
                return false // We handled it manually
            }
            
            return false
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let currentText = textField.text ?? ""
                // Filter to only emoji and take just the first one
                let filteredEmoji = currentText.onlyEmoji().firstEmoji
                
                // Update the text field if filtering changed the value
                if textField.text != filteredEmoji {
                    textField.text = filteredEmoji
                    
                    // Haptic feedback if something was filtered
                    if !currentText.isEmpty && filteredEmoji.isEmpty {
                        self.feedbackGenerator.notificationOccurred(.warning)
                    }
                }
                
                // Update the binding
                if self.parent.text != filteredEmoji {
                    self.parent.text = filteredEmoji
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - Public EmojiTextField View

/// A styled text field that only accepts emoji input using the native iOS emoji keyboard
struct EmojiTextField: View {
    @Binding var text: String
    var placeholder: String = "🍗"
    var size: CGFloat = 54
    
    var body: some View {
        ZStack {
            // Placeholder emoji with reduced opacity
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: size * 0.5))
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
            
            // Actual text field (transparent when showing placeholder)
            EmojiTextFieldRepresentable(
                text: $text,
                placeholder: "",
                fontSize: size * 0.6
            )
        }
        .frame(width: size, height: size)
        .background(Color.accent.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
