//
//  NewSplitBottomBar.swift
//  PayUp
//
//  Bottom action bar for the NewSplitSheet (create and edit modes).
//

import SwiftUI

struct NewSplitBottomBar: View {
    let isEditing: Bool
    let canDelete: Bool
    let isValid: Bool
    let isLoading: Bool
    let hasReceiptImage: Bool
    let snarkRemark: String?
    let onSave: () -> Void
    let onDelete: () -> Void
    let onScanReceipt: () -> Void
    let onReplaceReceipt: () -> Void

    private let buttonSize: CGFloat = 48

    var body: some View {
        GlassEffectContainer(spacing: 28) {
            if isEditing {
                editModeBar
            } else {
                createModeBar
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Edit Mode

    private var editModeBar: some View {
        HStack {
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.destructive)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.interactive().tint(.appDestructive.opacity(0.15)),
                    in: .circle
                )
            } else {
                Color.clear
                    .frame(width: buttonSize, height: buttonSize)
            }

            Spacer()

            HStack(spacing: 12) {
                scanReceiptCircleButton

                snarkBubble

                Button(action: onSave) {
                    Group {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.text)
                        }
                    }
                    .frame(width: buttonSize, height: buttonSize)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive().tint(.accent), in: .circle)
                .disabled(!isValid || isLoading)
                .opacity((!isValid || isLoading) ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Create Mode

    private var createModeBar: some View {
        HStack(spacing: 12) {
            scanReceiptCircleButton

            snarkBubble

            Button(action: onSave) {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Add Split")
                            .font(.body)
                            .fontWeight(.medium)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 40)
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(!isValid || isLoading)
        }
    }

    @ViewBuilder
    private var snarkBubble: some View {
        if let snarkRemark {
            SnarkRemarkBubble(text: snarkRemark)
                .frame(maxWidth: 150, alignment: .trailing)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .trailing).combined(with: .opacity),
                    removal: .scale(scale: 0.96, anchor: .trailing).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: snarkRemark)
        }
    }

    // MARK: - Shared Scan Receipt Button

    private var scanReceiptCircleButton: some View {
        Button {
            if hasReceiptImage {
                onReplaceReceipt()
            } else {
                onScanReceipt()
            }
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.text)
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.interactive().tint(.accent.opacity(0.2)),
            in: .circle
        )
    }
}
