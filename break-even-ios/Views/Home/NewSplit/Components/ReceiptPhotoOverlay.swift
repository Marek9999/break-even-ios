//
//  ReceiptPhotoOverlay.swift
//  break-even-ios
//
//  Full-screen overlay for viewing/managing a scanned receipt photo.
//

import SwiftUI
import UIKit

struct ReceiptPhotoOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void
    let onDeletePhoto: () -> Void
    let onScanNew: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 24) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20)
                
                VStack(spacing: 16) {
                    Button {
                        onDismiss()
                        onDeletePhoto()
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.clear.interactive().tint(.destructive.opacity(0.1)))
                    }
                    
                    Button {
                        onDismiss()
                        onScanNew()
                    } label: {
                        Label("Scan New Receipt", systemImage: "viewfinder")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.text)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.clear.interactive())
                    }
                }
            }
            .padding(24)
        }
    }
}
