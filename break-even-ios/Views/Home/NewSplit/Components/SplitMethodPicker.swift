//
//  SplitMethodPicker.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI

/// Picker for selecting the split method
struct SplitMethodPicker: View {
    @Binding var selectedMethod: NewSplitMethod
    @State private var showOptions = false
    
    var body: some View {
        Button {
            showOptions = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedMethod.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(selectedMethod.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(Color.accent.opacity(0.15)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOptions) {
            SplitMethodOptionsSheet(selectedMethod: $selectedMethod)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Split Method Options Sheet

struct SplitMethodOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMethod: NewSplitMethod
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("How do you want to split?")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Choose how the total will be divided")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
                
                // Options Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(NewSplitMethod.allCases) { method in
                        SplitMethodOptionCard(
                            method: method,
                            isSelected: selectedMethod == method,
                            onSelect: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedMethod = method
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    dismiss()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
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
}

// MARK: - Split Method Option Card

private struct SplitMethodOptionCard: View {
    let method: NewSplitMethod
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accent : Color.accentSecondary.opacity(0.3))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: method.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .accent)
                }
                
                // Text
                VStack(spacing: 4) {
                    Text(method.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.text)
                    
                    Text(method.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accent.opacity(0.1) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.accent : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Split Method Selector (Alternative compact design)

struct InlineSplitMethodSelector: View {
    @Binding var selectedMethod: NewSplitMethod
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(NewSplitMethod.allCases) { method in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMethod = method
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: method.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(method.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(selectedMethod == method ? .white : .accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selectedMethod == method {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accent)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentSecondary.opacity(0.2))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview("Split Method Picker Button") {
    struct PreviewWrapper: View {
        @State private var method: NewSplitMethod = .equal
        
        var body: some View {
            VStack(spacing: 20) {
                SplitMethodPicker(selectedMethod: $method)
                Text("Selected: \(method.rawValue)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}

#Preview("Split Method Options Sheet") {
    struct PreviewWrapper: View {
        @State private var method: NewSplitMethod = .equal
        @State private var showSheet = true
        
        var body: some View {
            VStack {
                Text("Selected: \(method.rawValue)")
                Button("Show Options") {
                    showSheet = true
                }
            }
            .sheet(isPresented: $showSheet) {
                SplitMethodOptionsSheet(selectedMethod: $method)
                    .presentationDetents([.medium])
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Inline Split Method Selector") {
    struct PreviewWrapper: View {
        @State private var method: NewSplitMethod = .equal
        
        var body: some View {
            VStack(spacing: 20) {
                InlineSplitMethodSelector(selectedMethod: $method)
                Text("Selected: \(method.rawValue)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
