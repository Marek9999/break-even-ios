//
//  AmountField.swift
//  break-even-ios
//
//  Custom expanding amount text field with UIKit backing for precise cursor/scroll control.
//

import SwiftUI
import UIKit

// MARK: - Width Preference Key

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

// MARK: - Expanding Amount Field

struct ExpandingAmountField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let fieldWidth: CGFloat

    @State private var isClippedLeft = false
    @State private var isClippedRight = false

    static let amountFont = UIFont.systemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .title1).pointSize,
        weight: .bold
    )

    private let fadeWidth: CGFloat = 24

    private var displayText: String {
        text.isEmpty ? placeholder : text
    }

    private var textContentWidth: CGFloat {
        Self.measuredWidth(for: displayText)
    }

    private var isOverflowing: Bool {
        textContentWidth > fieldWidth
    }

    private var textAlignment: NSTextAlignment {
        (!isFocused && isOverflowing) ? .left : .right
    }

    var body: some View {
        AmountUITextField(
            text: $text,
            isFocused: $isFocused,
            isClippedLeft: $isClippedLeft,
            isClippedRight: $isClippedRight,
            placeholder: placeholder,
            font: Self.amountFont,
            textAlignment: textAlignment
        )
        .frame(width: fieldWidth, height: 44)
        .transaction { $0.animation = nil }
        .clipped()
        .mask {
            fadeMask
        }
    }

    static func measuredWidth(for value: String) -> CGFloat {
        (value as NSString).size(withAttributes: [.font: amountFont]).width
    }

    @ViewBuilder
    private var fadeMask: some View {
        if isFocused && isOverflowing {
            HStack(spacing: 0) {
                if isClippedLeft {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fadeWidth)
                }
                Rectangle().fill(.black)
                if isClippedRight {
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fadeWidth)
                }
            }
        } else if !isFocused && isOverflowing {
            HStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fadeWidth)
            }
        } else {
            Rectangle().fill(.black)
        }
    }
}

// MARK: - Observable UITextField Subclass

class ObservableAmountTextField: UITextField {
    var onLayoutChange: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }
}

// MARK: - UIKit-backed Amount TextField

struct AmountUITextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isClippedLeft: Bool
    @Binding var isClippedRight: Bool
    let placeholder: String
    let font: UIFont
    var textAlignment: NSTextAlignment

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ObservableAmountTextField {
        let tf = ObservableAmountTextField()
        tf.delegate = context.coordinator
        tf.font = font
        tf.textColor = .label
        tf.tintColor = .label
        tf.keyboardType = .decimalPad
        tf.borderStyle = .none
        tf.textAlignment = textAlignment
        tf.clipsToBounds = true
        tf.defaultTextAttributes[.paragraphStyle] = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byClipping
            return style
        }()
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.tertiaryLabel, .font: font]
        )
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        tf.onLayoutChange = { [weak tf] in
            guard let tf else { return }
            context.coordinator.updateClipState(tf)
        }
        return tf
    }

    func updateUIView(_ tf: ObservableAmountTextField, context: Context) {
        if tf.text != text {
            tf.text = text
        }
        if tf.textAlignment != textAlignment {
            tf.textAlignment = textAlignment
        }

        let shouldFocus = isFocused
        DispatchQueue.main.async {
            if shouldFocus && !tf.isFirstResponder {
                tf.becomeFirstResponder()
            } else if !shouldFocus && tf.isFirstResponder {
                tf.resignFirstResponder()
            }
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountUITextField
        private var scrollObservation: NSKeyValueObservation?
        private weak var observedScrollView: UIScrollView?
        private weak var textFieldRef: UITextField?

        init(_ parent: AmountUITextField) {
            self.parent = parent
        }

        @objc func textChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            textFieldRef = tf
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            scrollObservation = nil
            observedScrollView = nil
            textFieldRef = nil
            DispatchQueue.main.async {
                self.parent.isFocused = false
                self.parent.isClippedLeft = false
                self.parent.isClippedRight = false
            }
        }

        func textFieldDidChangeSelection(_ tf: UITextField) {
            updateClipState(tf)
        }

        func updateClipState(_ tf: UITextField) {
            guard tf.isFirstResponder,
                  let text = tf.text, !text.isEmpty,
                  let font = tf.font else {
                DispatchQueue.main.async {
                    if self.parent.isClippedLeft { self.parent.isClippedLeft = false }
                    if self.parent.isClippedRight { self.parent.isClippedRight = false }
                }
                return
            }

            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let boundsWidth = tf.bounds.width
            guard textWidth > boundsWidth else {
                DispatchQueue.main.async {
                    if self.parent.isClippedLeft { self.parent.isClippedLeft = false }
                    if self.parent.isClippedRight { self.parent.isClippedRight = false }
                }
                return
            }

            guard let scrollView = tf.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else {
                return
            }

            if observedScrollView !== scrollView {
                observedScrollView = scrollView
                scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak tf] _, _ in
                    guard let self, let tf else { return }
                    self.updateClipState(tf)
                }
            }

            let offset = scrollView.contentOffset.x
            let visibleWidth = scrollView.bounds.width
            let contentWidth = scrollView.contentSize.width
            let tolerance: CGFloat = 2

            let left = offset > tolerance
            let right = (offset + visibleWidth) < (contentWidth - tolerance)

            DispatchQueue.main.async {
                if left != self.parent.isClippedLeft { self.parent.isClippedLeft = left }
                if right != self.parent.isClippedRight { self.parent.isClippedRight = right }
            }
        }
    }
}
