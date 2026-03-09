//
//  NewSplitBottomBar.swift
//  break-even-ios
//
//  Bottom action bar for the NewSplitSheet (create and edit modes).
//

import SwiftUI

struct NewSplitBottomBar: View {
    let isEditing: Bool
    let isValid: Bool
    let isLoading: Bool
    let hasReceiptImage: Bool
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

            Spacer()

            HStack(spacing: 20) {
                scanReceiptCircleButton

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
        HStack(spacing: 20) {
            scanReceiptCircleButton

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
