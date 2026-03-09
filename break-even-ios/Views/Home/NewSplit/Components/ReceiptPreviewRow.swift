//
//  ReceiptPreviewRow.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Pill-shaped bar showing receipt photo info, with optional total mismatch warning.
/// This view requires an image -- callers should only show it when scannedReceiptImage != nil.
struct ReceiptPreviewRow: View {
    let image: UIImage
    let showMismatchWarning: Bool
    var itemsTotal: Double = 0
    var splitTotal: Double = 0
    var currencyCode: String = "USD"
    let onScanReceipt: () -> Void
    let onDeletePhoto: () -> Void
    let onScanNewReceipt: () -> Void
    let onTapPhoto: () -> Void
    
    private var mismatchText: String {
        let diff = abs(itemsTotal - splitTotal)
        let diffFormatted = diff.asCurrency(code: currencyCode)
        if itemsTotal > splitTotal {
            return "Items exceed total by \(diffFormatted)"
        } else {
            return "Items short of total by \(diffFormatted)"
        }
    }
    
    var body: some View {
        receiptPhotoBar
    }
    
    // MARK: - Receipt Photo Bar
    
    private var receiptPhotoBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Receipt Photo")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                
                if showMismatchWarning {
                    Text(mismatchText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            Button {
                onTapPhoto()
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.text.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.background.secondary.opacity(0.6))
        .clipShape(Capsule())
    }
    
}

// MARK: - Items Total Mismatch Bar

/// Standalone pill-shaped warning bar for when items total doesn't match the split total.
/// Used in the by-item section when no receipt image exists.
struct ItemsTotalMismatchBar: View {
    let itemsTotal: Double
    let splitTotal: Double
    let currencyCode: String
    
    private var mismatchText: String {
        let diff = abs(itemsTotal - splitTotal)
        let diffFormatted = diff.asCurrency(code: currencyCode)
        if itemsTotal > splitTotal {
            return "Items exceed total by \(diffFormatted)"
        } else {
            return "Items short of total by \(diffFormatted)"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            
            Text(mismatchText)
                .font(.caption)
                .foregroundStyle(.orange)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background.secondary.opacity(0.6))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("With Photo") {
    let size = CGSize(width: 200, height: 280)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { ctx in
        UIColor.systemGray5.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    
    VStack(spacing: 20) {
        ReceiptPreviewRow(
            image: img,
            showMismatchWarning: false,
            onScanReceipt: {},
            onDeletePhoto: {},
            onScanNewReceipt: {},
            onTapPhoto: {}
        )
        
        ReceiptPreviewRow(
            image: img,
            showMismatchWarning: true,
            itemsTotal: 52.47,
            splitTotal: 50.00,
            currencyCode: "USD",
            onScanReceipt: {},
            onDeletePhoto: {},
            onScanNewReceipt: {},
            onTapPhoto: {}
        )
    }
    .padding()
}

#Preview("Mismatch Bar") {
    VStack(spacing: 20) {
        ItemsTotalMismatchBar(
            itemsTotal: 52.47,
            splitTotal: 50.00,
            currencyCode: "USD"
        )
        
        ItemsTotalMismatchBar(
            itemsTotal: 42.00,
            splitTotal: 50.00,
            currencyCode: "USD"
        )
    }
    .padding()
}
