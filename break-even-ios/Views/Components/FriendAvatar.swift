//
//  FriendAvatar.swift
//  break-even-ios
//
//  Shared avatar component for displaying a friend's profile image or initials.
//

import SwiftUI

struct FriendAvatar: View {
    let friend: ConvexFriend
    let size: CGFloat

    var body: some View {
        if let avatarUrl = friend.avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(friend.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
}

#if DEBUG
#Preview("Friend Avatar") {
    HStack(spacing: 12) {
        FriendAvatar(friend: .previewSelf, size: 24)
        FriendAvatar(friend: .previewAlice, size: 32)
        FriendAvatar(friend: .previewBob, size: 48)
        FriendAvatar(friend: .previewCarla, size: 56)
    }
    .padding()
}
#endif
