//
//  FriendAvatar.swift
//  break-even-ios
//
//  Shared avatar component for displaying a friend's profile image or initials.
//

import SwiftUI

// MARK: - Avatar Color Palette

enum AvatarColors {
    static let palette: [(name: String, hex: String, color: Color)] = [
        ("Red", "#FF6B6B", Color(hex: "#FF6B6B")),
        ("Orange", "#FFA726", Color(hex: "#FFA726")),
        ("Yellow", "#FFCA28", Color(hex: "#FFCA28")),
        ("Green", "#66BB6A", Color(hex: "#66BB6A")),
        ("Teal", "#26A69A", Color(hex: "#26A69A")),
        ("Blue", "#42A5F5", Color(hex: "#42A5F5")),
        ("Indigo", "#5C6BC0", Color(hex: "#5C6BC0")),
        ("Purple", "#AB47BC", Color(hex: "#AB47BC")),
        ("Pink", "#EC407A", Color(hex: "#EC407A")),
    ]

    static func color(forHex hex: String?) -> Color {
        guard let hex else { return .accentColor }
        return palette.first(where: { $0.hex == hex })?.color ?? Color(hex: hex)
    }
}

// MARK: - Color+Hex

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - FriendAvatar

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
                fallbackView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackView
        }
    }

    private var circleColor: Color {
        AvatarColors.color(forHex: friend.avatarColor)
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let emoji = friend.avatarEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: size * 0.5))
                .frame(width: size, height: size)
                .background(circleColor)
                .clipShape(Circle())
        } else {
            Text(friend.initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(circleColor)
                .clipShape(Circle())
        }
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
