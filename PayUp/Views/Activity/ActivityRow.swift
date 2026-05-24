//
//  ActivityRow.swift
//  PayUp
//

import SwiftUI

struct ActivityRow: View {
    let activity: ConvexActivity
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(activity.activityType.emoji)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.accent.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !activity.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(activity.message)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Text(activity.actorName)
                    Text("•")
                    Text(activity.createdAtDate.smartFormatted)
                }
                .font(.subheadline)
                .foregroundStyle(.text.opacity(0.6))
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
