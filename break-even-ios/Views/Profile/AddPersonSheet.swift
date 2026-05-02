import SwiftUI
import Clerk
import ConvexMobile
import UIKit
internal import Combine

/// Add Friend sheet — dark, custom-laid-out flow with a username search at the
/// top and an always-visible "Create a dummy friend" section below an "or"
/// divider. Visual language mirrors the inline New Split flow: 23pt semibold
/// title + a 52pt glass circle dismiss in the header, capsule pill inputs, a
/// fixed-circle emoji carousel, and the project-standard white glass capsule
/// CTA at the bottom.
struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService

    let existingFriends: [ConvexFriend]
    let initialPlaceholderName: String

    init(
        existingFriends: [ConvexFriend] = [],
        initialPlaceholderName: String = ""
    ) {
        self.existingFriends = existingFriends
        self.initialPlaceholderName = initialPlaceholderName
    }

    enum SearchState: Equatable {
        case idle
        case searching
        case found(PublicUserProfile)
        case alreadyInContacts(ConvexFriend, PublicUserProfile)
        case notFound

        static func == (lhs: SearchState, rhs: SearchState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.searching, .searching), (.notFound, .notFound):
                return true
            case (.found(let a), .found(let b)):
                return a.id == b.id
            case (.alreadyInContacts(let a, _), .alreadyInContacts(let b, _)):
                return a.id == b.id
            default:
                return false
            }
        }
    }

    @State private var username = ""
    @State private var searchState: SearchState = .idle
    @State private var searchTask: Task<Void, Never>?

    @State private var placeholderName = ""
    @State private var placeholderEmoji: String = "🐼"
    @State private var placeholderHue: Double = 0.571

    @State private var isSendingInvite = false
    @State private var isCreatingPlaceholder = false
    @State private var error: String?
    @State private var sentForUserId: String?

    @FocusState private var focusedField: Field?
    enum Field { case username, placeholderName }

    private let baseEmojis: [String] = [
        "🦁", "🐧", "🐼", "🐔", "🐮", "🐶", "🐱", "🐭", "🐹", "🐰",
        "🦊", "🐻", "🐨", "🐯", "🐷", "🐸", "🐵", "🦆", "🦉", "🐺"
    ]

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var trimmedPlaceholderName: String {
        placeholderName.trimmingCharacters(in: .whitespaces)
    }

    private var selectedColor: Color {
        Color(hue: placeholderHue, saturation: 0.72, brightness: 0.96)
    }
    
    private var selectedColorHex: String {
        UIColor(hue: placeholderHue, saturation: 0.72, brightness: 0.96, alpha: 1).hexString
    }
    
    private let sheetBackground = Color(red: 14 / 255, green: 14 / 255, blue: 21 / 255)

    var body: some View {
        ZStack {
            sheetBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    searchBlock
                    dividerRow
                    dummyBlock
                    addDummyButton

                    if let error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(sheetBackground)
            }
        }
        .interactiveDismissDisabled(isSendingInvite || isCreatingPlaceholder)
        .onAppear {
            if !initialPlaceholderName.isEmpty && placeholderName.isEmpty {
                placeholderName = initialPlaceholderName
                focusedField = .placeholderName
            } else {
                focusedField = .username
            }
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    // MARK: - Header
    //
    // Mirrors `HomeView.sharedHeader` / `headerActionsArea` for the inline
    // new-split flow: 23pt semibold app-text title on the left, a 52pt glass
    // circle xmark on the right.

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Add Friend")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appText)

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(isSendingInvite || isCreatingPlaceholder)
        }
    }

    // MARK: - Search

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search friend by username to invite")
                .font(.subheadline)
                .foregroundStyle(Color.appText.opacity(0.58))

            HStack(spacing: 6) {
                Text("@")
                    .foregroundStyle(Color.appText.opacity(0.45))

                TextField(
                    "",
                    text: $username,
                    prompt: Text("username").foregroundStyle(Color.appText.opacity(0.32))
                )
                .focused($focusedField, equals: .username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundStyle(Color.appText)
                .onChange(of: username) { _, newValue in
                    username = newValue.lowercased().filter {
                        $0.isLetter || $0.isNumber || $0 == "_"
                    }
                    if username.count > 20 {
                        username = String(username.prefix(20))
                    }
                    error = nil
                    debounceUsernameSearch()
                }

                searchStateIndicator
            }
            .font(.body)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.white.opacity(0.05))
            .clipShape(Capsule())

            inlineSearchResult
        }
    }

    @ViewBuilder
    private var searchStateIndicator: some View {
        switch searchState {
        case .searching:
            ProgressView().controlSize(.small)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .alreadyInContacts:
            Image(systemName: "person.crop.circle.badge.checkmark")
                .foregroundStyle(.blue)
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
        case .idle:
            if !trimmedUsername.isEmpty {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.appText.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private var inlineSearchResult: some View {
        switch searchState {
        case .found(let profile):
            foundUserCard(profile)
        case .alreadyInContacts(let friend, _):
            alreadyInContactsCard(friend: friend)
        case .notFound:
            notFoundCard
        case .idle, .searching:
            EmptyView()
        }
    }

    private func foundUserCard(_ profile: PublicUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                profileAvatar(for: profile)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.appText)
                    if let display = profile.displayUsername {
                        Text(display)
                            .font(.caption)
                            .foregroundStyle(Color.appText.opacity(0.58))
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)

            Button {
                sendInvitationToUser(profile)
            } label: {
                HStack(spacing: 10) {
                    if isSendingInvite {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: sentForUserId == profile._id
                              ? "checkmark"
                              : "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isSendingInvite
                         ? "Sending..."
                         : (sentForUserId == profile._id ? "Invite sent" : "Send Invite"))
                        .font(.system(size: 17, weight: .medium))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .glassEffect(.clear.tint(.white.opacity(0.9)).interactive(), in: .capsule)
                .opacity((isSendingInvite || sentForUserId == profile._id) ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isSendingInvite || sentForUserId == profile._id)
        }
    }

    private func alreadyInContactsCard(friend: ConvexFriend) -> some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: friend, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.appText)
                Text(statusDescription(for: friend))
                    .font(.caption)
                    .foregroundStyle(Color.appText.opacity(0.58))
            }

            Spacer()
        }
    }

    private var notFoundCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)

                Text("No users found with this username, invite them to BreakEven or create a dummy user")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShareLink(item: shareURL, message: Text(shareMessage)) {
                Text("Invite to BreakEven")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.appText)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Divider

    private var dividerRow: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.appText.opacity(0.12))
                .frame(height: 1)
            Text("or")
                .font(.subheadline)
                .foregroundStyle(Color.appText.opacity(0.58))
            Rectangle()
                .fill(Color.appText.opacity(0.12))
                .frame(height: 1)
        }
    }

    // MARK: - Dummy block

    private var dummyBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create a dummy friend")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appText)
                Text("and you can link them with your friend later when they join BreakEven")
                    .font(.subheadline)
                    .foregroundStyle(Color.appText.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            EmojiCarousel(
                baseEmojis: baseEmojis,
                selectedColor: selectedColor,
                selectedEmoji: $placeholderEmoji
            )
            .frame(height: 76)

            hueSlider

            TextField(
                "",
                text: $placeholderName,
                prompt: Text("dummy username").foregroundStyle(Color.appText.opacity(0.32))
            )
            .focused($focusedField, equals: .placeholderName)
            .textContentType(.name)
            .submitLabel(.done)
            .foregroundStyle(Color.appText)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.white.opacity(0.05))
            .clipShape(Capsule())
        }
    }

    private var hueSlider: some View {
        HueSlider(value: $placeholderHue)
    }

    // MARK: - Add Dummy Friend
    //
    // Matches the project's primary CTA pattern (e.g. `HomeView.centerActionSection`
    // "New Split" and `InlineNewSplitFlow.bottomActionBar` "Add Split"):
    // a white glass capsule with leading SF symbol + label.

    private var addDummyButton: some View {
        let canSubmit = !trimmedPlaceholderName.isEmpty && !isCreatingPlaceholder
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            createPlaceholder()
        } label: {
            HStack(spacing: 8) {
                if isCreatingPlaceholder {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add Dummy Friend")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .clipShape(Capsule())
            .glassEffect(.clear.tint(.white.opacity( canSubmit ? 0.9 : 0.4)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - Helpers

    private func profileAvatar(for profile: PublicUserProfile) -> some View {
        Group {
            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsCircle(for: profile.name)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                initialsCircle(for: profile.name)
            }
        }
    }

    private func initialsCircle(for name: String) -> some View {
        Text(previewInitials(for: name))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.accentColor)
            .clipShape(Circle())
    }

    private func previewInitials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "?" }
        let components = trimmed.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    private func statusDescription(for friend: ConvexFriend) -> String {
        switch friend.inviteStatus ?? "none" {
        case "accepted": return "Connected"
        case "invite_sent": return "Invite sent"
        case "invite_received": return "They invited you"
        case "rejected": return "Declined your invite"
        case "removed_by_me": return "Removed by you"
        case "removed_by_them": return "They removed you"
        default: return "Already in your contacts"
        }
    }

    private var shareURL: URL {
        URL(string: "https://breakeven.app/join")!
    }

    private var shareMessage: String {
        "Join me on BreakEven so we can split expenses together!"
    }
    
    private func blockingExistingFriend(for profile: PublicUserProfile) -> ConvexFriend? {
        existingFriends.first { friend in
            friend.linkedUserId == profile._id &&
            !friend.isSelf &&
            ["accepted", "invite_sent"].contains(friend.inviteStatus ?? "none")
        }
    }

    // MARK: - Username search

    private func debounceUsernameSearch() {
        searchTask?.cancel()
        sentForUserId = nil

        guard trimmedUsername.count >= 3 else {
            searchState = .idle
            return
        }

        searchState = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let subscription = convexService.client.subscribe(
                to: "users:getUserByUsername",
                with: ["username": trimmedUsername],
                yielding: PublicUserProfile?.self
            )
            .replaceError(with: nil)
            .values

            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let profile = result {
                        if let existing = blockingExistingFriend(for: profile) {
                            searchState = .alreadyInContacts(existing, profile)
                        } else {
                            searchState = .found(profile)
                        }
                    } else {
                        searchState = .notFound
                    }
                }
                break
            }
        }
    }

    // MARK: - Actions

    private func sendInvitationToUser(_ profile: PublicUserProfile) {
        guard let clerkId = clerk.user?.id else {
            error = "Not authenticated"
            return
        }

        isSendingInvite = true
        error = nil

        Task {
            do {
                let response: SendInvitationToUserResponse = try await convexService.client.mutation(
                    "invitations:sendInvitationToUser",
                    with: [
                        "clerkId": clerkId,
                        "targetUserId": profile._id
                    ]
                )

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSendingInvite = false
                    sentForUserId = profile._id
                    if response.autoAccepted {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSendingInvite = false
                }
            }
        }
    }

    private func createPlaceholder() {
        guard let clerkId = clerk.user?.id else {
            error = "Not authenticated"
            return
        }
        guard !trimmedPlaceholderName.isEmpty else { return }

        isCreatingPlaceholder = true
        error = nil

        Task {
            do {
                var args: [String: String] = [
                    "clerkId": clerkId,
                    "name": trimmedPlaceholderName
                ]
                if !placeholderEmoji.isEmpty {
                    args["avatarEmoji"] = placeholderEmoji
                }
                args["avatarColor"] = selectedColorHex

                let _: CreateFriendResponse = try await convexService.client.mutation(
                    "friends:createDummyFriend",
                    with: args
                )

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isCreatingPlaceholder = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isCreatingPlaceholder = false
                }
            }
        }
    }
}

// MARK: - Emoji Carousel
//
// SwiftUI owns the fixed center-circle and edge fade. UIKit owns the actual
// scrolling so we get reliable momentum, snapping, tap-to-center animation,
// and wrap-around recentering without fighting SwiftUI's scroll state.

private struct EmojiCarousel: View {
    let baseEmojis: [String]
    let selectedColor: Color
    @Binding var selectedEmoji: String

    private let circleSize: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .fill(selectedColor)
                .frame(width: circleSize, height: circleSize)
                .animation(.smooth(duration: 0.25), value: selectedColor)

            InfiniteEmojiCarouselView(
                baseEmojis: baseEmojis,
                selectedEmoji: $selectedEmoji
            )
                .allowsHitTesting(true)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
    }
}

private struct HueSlider: View {
    @Binding var value: Double
    @GestureState private var isDragging = false
    
    private let knobSize: CGFloat = 36
    private let trackHeight: CGFloat = 24
    private let innerCircleSize: CGFloat = 18
    private let gradientColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map {
        Color(hue: $0, saturation: 0.72, brightness: 0.96)
    }
    
    private var selectedColor: Color {
        Color(hue: value, saturation: 0.72, brightness: 0.96)
    }
    
    private func dragGesture(travelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { gesture in
                updateValue(for: gesture.location.x, travelWidth: travelWidth)
            }
    }
    
    var body: some View {
        GeometryReader { geo in
            let travelWidth = max(0, geo.size.width - knobSize)
            let knobOffset = travelWidth * value
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.05))
                    .frame(height: trackHeight)
                
                ZStack {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: innerCircleSize, height: innerCircleSize)
                }
                .frame(width: knobSize, height: knobSize)
                .contentShape(Circle())
                .glassEffect(.clear.tint(.white.opacity(0.2)).interactive(), in: .circle)
                .scaleEffect(isDragging ? 1.08 : 1)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isDragging)
                .offset(x: knobOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(dragGesture(travelWidth: travelWidth))
        }
        .frame(height: knobSize)
    }
    
    private func updateValue(for locationX: CGFloat, travelWidth: CGFloat) {
        let raw = (locationX - (knobSize / 2)) / max(travelWidth, 1)
        value = min(max(raw, 0), 1)
    }
}

private struct InfiniteEmojiCarouselView: UIViewRepresentable {
    let baseEmojis: [String]
    @Binding var selectedEmoji: String
    
    private let itemSize = CGSize(width: 40, height: 64)
    private let itemSpacing: CGFloat = 30
    private let repeatCount = 121
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UICollectionView {
        let layout = EmojiCarouselFlowLayout(itemSize: itemSize, itemSpacing: itemSpacing)
        let collectionView = ObservableEmojiCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.decelerationRate = .fast
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(EmojiCarouselCell.self, forCellWithReuseIdentifier: EmojiCarouselCell.reuseIdentifier)
        collectionView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleInitialPositionIfNeeded()
        }
        
        context.coordinator.collectionView = collectionView
        return collectionView
    }
    
    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncExternalSelectionIfNeeded()
    }
    
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: InfiniteEmojiCarouselView
        weak var collectionView: UICollectionView?
        
        private let selectionFeedback = UISelectionFeedbackGenerator()
        private var centeredAbsoluteIndex: Int?
        private var centeredNormalizedIndex: Int?
        private var didApplyInitialPosition = false
        
        init(_ parent: InfiniteEmojiCarouselView) {
            self.parent = parent
            super.init()
            selectionFeedback.prepare()
        }
        
        private var totalCount: Int { parent.baseEmojis.count * parent.repeatCount }
        private var middleStart: Int { (parent.repeatCount / 2) * parent.baseEmojis.count }
        private var itemStride: CGFloat { parent.itemSize.width + parent.itemSpacing }
        
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            totalCount
        }
        
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: EmojiCarouselCell.reuseIdentifier,
                for: indexPath
            ) as? EmojiCarouselCell else {
                return UICollectionViewCell()
            }
            
            let normalized = normalizedIndex(for: indexPath.item)
            let isCentered = indexPath.item == centeredAbsoluteIndex
            cell.configure(emoji: parent.baseEmojis[normalized], isCentered: isCentered)
            return cell
        }
        
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            scrollToAbsoluteIndex(indexPath.item, animated: true)
        }
        
        func scheduleInitialPositionIfNeeded() {
            guard let collectionView, !didApplyInitialPosition, collectionView.bounds.width > 0 else { return }
            didApplyInitialPosition = true
            let target = middleStart + bindingNormalizedIndex()
            scrollToAbsoluteIndex(target, animated: false)
            updateCenteredSelection(force: true)
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCenteredSelection(force: false)
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                recenterIfNeeded()
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            recenterIfNeeded()
        }
        
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            recenterIfNeeded()
        }
        
        func syncExternalSelectionIfNeeded() {
            guard didApplyInitialPosition else { return }
            let desired = bindingNormalizedIndex()
            guard desired != centeredNormalizedIndex else { return }
            scrollToAbsoluteIndex(middleStart + desired, animated: false)
            updateCenteredSelection(force: true)
        }
        
        private func bindingNormalizedIndex() -> Int {
            parent.baseEmojis.firstIndex(of: parent.selectedEmoji) ?? 0
        }
        
        private func normalizedIndex(for absoluteIndex: Int) -> Int {
            ((absoluteIndex % parent.baseEmojis.count) + parent.baseEmojis.count) % parent.baseEmojis.count
        }
        
        private func nearestCenteredIndex() -> Int? {
            guard let collectionView else { return nil }
            let rawIndex = Int(round(collectionView.contentOffset.x / itemStride))
            return min(max(rawIndex, 0), totalCount - 1)
        }
        
        private func updateCenteredSelection(force: Bool) {
            guard let absoluteIndex = nearestCenteredIndex() else { return }
            let normalized = normalizedIndex(for: absoluteIndex)
            let didChangeAbsolute = centeredAbsoluteIndex != absoluteIndex
            let didChangeNormalized = centeredNormalizedIndex != normalized
            
            centeredAbsoluteIndex = absoluteIndex
            
            if didChangeNormalized || centeredNormalizedIndex == nil {
                centeredNormalizedIndex = normalized
                let emoji = parent.baseEmojis[normalized]
                if parent.selectedEmoji != emoji {
                    parent.selectedEmoji = emoji
                }
                if !force {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                }
            }
            
            updateVisibleCells()
        }
        
        private func updateVisibleCells() {
            guard let collectionView else { return }
            
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) as? EmojiCarouselCell else { continue }
                let emoji = parent.baseEmojis[normalizedIndex(for: indexPath.item)]
                cell.configure(emoji: emoji, isCentered: indexPath.item == centeredAbsoluteIndex)
            }
        }
        
        private func scrollToAbsoluteIndex(_ absoluteIndex: Int, animated: Bool) {
            guard let collectionView else { return }
            guard absoluteIndex >= 0, absoluteIndex < totalCount else { return }
            let targetOffset = CGPoint(x: CGFloat(absoluteIndex) * itemStride, y: 0)
            
            collectionView.setContentOffset(targetOffset, animated: animated)
            
            if !animated {
                centeredAbsoluteIndex = absoluteIndex
                centeredNormalizedIndex = normalizedIndex(for: absoluteIndex)
                updateVisibleCells()
            }
        }
        
        private func recenterIfNeeded() {
            guard let absoluteIndex = centeredAbsoluteIndex else { return }
            let normalized = normalizedIndex(for: absoluteIndex)
            let target = middleStart + normalized
            
            if abs(absoluteIndex - target) > parent.baseEmojis.count {
                scrollToAbsoluteIndex(target, animated: false)
            }
        }
    }
}

private final class ObservableEmojiCollectionView: UICollectionView {
    var onLayout: (() -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class EmojiCarouselFlowLayout: UICollectionViewFlowLayout {
    private let configuredItemSize: CGSize
    private let configuredItemSpacing: CGFloat
    
    init(itemSize: CGSize, itemSpacing: CGFloat) {
        self.configuredItemSize = itemSize
        self.configuredItemSpacing = itemSpacing
        super.init()
        scrollDirection = .horizontal
        minimumLineSpacing = itemSpacing
        minimumInteritemSpacing = itemSpacing
        self.itemSize = itemSize
    }
    
    required init?(coder: NSCoder) {
        return nil
    }
    
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        itemSize = configuredItemSize
        minimumLineSpacing = configuredItemSpacing
        minimumInteritemSpacing = configuredItemSpacing
        
        let horizontalInset = max(0, (collectionView.bounds.width - configuredItemSize.width) / 2)
        sectionInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        super.layoutAttributesForElements(in: rect)?
            .compactMap { $0.copy() as? UICollectionViewLayoutAttributes }
            .map(applyCenterScaling)
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.layoutAttributesForItem(at: indexPath)?.copy() as? UICollectionViewLayoutAttributes else {
            return nil
        }
        return applyCenterScaling(attributes)
    }
    
    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        let proposedRect = CGRect(
            x: proposedContentOffset.x,
            y: 0,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        let proposedCenterX = proposedContentOffset.x + (collectionView.bounds.width / 2)
        let attributes = super.layoutAttributesForElements(in: proposedRect) ?? []
        
        guard let nearest = attributes.min(by: {
            abs($0.center.x - proposedCenterX) < abs($1.center.x - proposedCenterX)
        }) else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }
        
        return CGPoint(
            x: nearest.center.x - (collectionView.bounds.width / 2),
            y: proposedContentOffset.y
        )
    }
    
    private func applyCenterScaling(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let collectionView else { return attributes }
        
        let viewportCenterX = collectionView.contentOffset.x + (collectionView.bounds.width / 2)
        let distanceFromCenter = abs(attributes.center.x - viewportCenterX)
        let falloffDistance = configuredItemSize.width + configuredItemSpacing
        let proximity = max(0, 1 - (distanceFromCenter / falloffDistance))
        let scale = 1 + (0.30 * proximity)
        
        attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        attributes.zIndex = Int(proximity * 1000)
        return attributes
    }
}

private final class EmojiCarouselCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCarouselCell"
    
    private let label = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 31)
        contentView.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        return nil
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.transform = .identity
        contentView.alpha = 1
    }
    
    func configure(emoji: String, isCentered: Bool) {
        label.text = emoji
        contentView.alpha = 1
        contentView.transform = .identity
    }
}

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

#Preview {
    AddPersonSheet()
}
