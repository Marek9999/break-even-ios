//
//  InlineFriendSearch.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Simple capsule-shaped search bar placeholder that opens the full friend search overlay when tapped.
struct FriendSearchTrigger: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Add friends...")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Friend Search Trigger") {
    FriendSearchTrigger(onTap: {})
        .padding()
}
