//
//  ReceiptPreviewRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Row displaying receipt thumbnail with remove option
struct ReceiptPreviewRow: View {
    let image: UIImage
    let onRemove: () -> Void
    let onTap: (() -> Void)?
    
    @State private var showFullImage = false
    
    init(image: UIImage, onRemove: @escaping () -> Void, onTap: (() -> Void)? = nil) {
        self.image = image
        self.onRemove = onRemove
        self.onTap = onTap
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Receipt label
            Text("Receipt")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Thumbnail
            Button {
                if let action = onTap {
                    action()
                } else {
                    showFullImage = true
                }
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .sheet(isPresented: $showFullImage) {
            ReceiptFullImageView(image: image)
        }
    }
}

// MARK: - Receipt Full Image View

struct ReceiptFullImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
            .background(Color.black)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Receipt Preview Row") {
    VStack {
        // Create a sample image for preview
        if let sampleImage = UIImage(systemName: "doc.text.fill") {
            ReceiptPreviewRow(
                image: sampleImage,
                onRemove: { print("Remove tapped") }
            )
            .padding()
        }
    }
}
