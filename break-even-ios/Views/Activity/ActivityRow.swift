//
//  ActivityRow.swift
//  break-even-ios
//

import SwiftUI

struct ActivityRow: View {
    let activity: ConvexActivity
    
    var body: some View {
        HStack(spacing: 10) {
            if !activity.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            } else {
                Spacer()
                    .frame(width: 8)
            }
            
            Image(systemName: activity.activityType.iconName)
                .font(.system(size: 14))
                .foregroundStyle(.accent)
                .frame(width: 36, height: 36)
                .background(Color.accent.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
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
            
            if activity.activityType.isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.text.opacity(0.3))
            }
        }
        .contentShape(Rectangle())
    }
}
