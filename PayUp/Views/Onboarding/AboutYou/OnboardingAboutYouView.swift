//
//  OnboardingAboutYouView.swift
//  PayUp
//
//  Second onboarding step. Collects the user's profile photo (or emoji),
//  their display name, and a unique username. Used inside
//  OnboardingFlowView's step machine.
//

import SwiftUI
import Clerk
import ConvexMobile
import PhotosUI
internal import Combine

struct OnboardingAboutYouView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService

    /// The flow-level bottom bar owns the continue button now, so it
    /// needs to know whether the form passes validation and needs a way
    /// to force-show inline errors when the user taps a disabled button.
    /// Both are driven via these bindings/values from OnboardingFlowView.
    @Binding var canContinue: Bool
    /// Monotonically increasing counter. Each increment means "the user
    /// tapped the flow's continue button while the form was invalid";
    /// reacting to it marks both fields as touched so hints appear.
    var validationTrigger: Int = 0

    // Profile state
    @Binding var profileImage: UIImage?
    @Binding var selectedEmoji: String?
    @Binding var profileHue: Double
    @Binding var isEditingEmoji: Bool
    @Binding var imageDominantColor: Color?

    // Form state
    @Binding var name: String
    @Binding var username: String
    @Binding var nameTouched: Bool
    @Binding var usernameTouched: Bool

    // Sheets
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var hasScrolledContent = false

    // Emoji pill animation
    @State private var currentEmojiPreview: String = "😀"

    // Username check
    @State private var isChecking = false
    @Binding var availability: UsernameAvailabilityResponse?
    @State private var checkTask: Task<Void, Never>?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, username }

    private static let faceEmojis: [String] = [
        "🦁", "🐧", "🐼", "🐔", "🐮", "🐶", "🐱", "🐭", "🐹", "🐰",
        "🦊", "🐻", "🐨", "🐯", "🐷", "🐸", "🐵", "🦆", "🦉", "🐺"
    ]

    private static let usernameRegex = #"^[a-z0-9_]+$"#

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.lowercased().trimmingCharacters(in: .whitespaces) }

    private var isNameValid: Bool { !trimmedName.isEmpty }
    private var isUsernameLocallyValid: Bool {
        trimmedUsername.count >= 3
            && trimmedUsername.count <= 20
            && trimmedUsername.range(of: Self.usernameRegex, options: .regularExpression) != nil
    }
    private var isFormValid: Bool {
        isNameValid && isUsernameLocallyValid && availability?.available == true
    }

    private var topGradientColor: Color? {
        if let imageDominantColor { return imageDominantColor }
        if selectedEmoji != nil { return profileColor }
        return nil
    }

    private var profileColor: Color {
        Color(hue: profileHue, saturation: 0.72, brightness: 0.96)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.homeSectionBackground.ignoresSafeArea()

            topGradientOverlay

            VStack(spacing: 0) {
                // Spacer reserves the same height the local page indicator
                // used to occupy. The indicator itself now lives in
                // OnboardingFlowView so its pills can morph across steps.
                Color.clear.frame(height: 44)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 28) {
                            topTitle
                            profileSection
                            photoActionPills
                            formSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 280)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .mask(onboardingScrollTopFadeMask)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y > 1
                    } action: { _, isScrolled in
                        guard hasScrolledContent != isScrolled else { return }

                        withAnimation(.easeInOut(duration: 0.16)) {
                            hasScrolledContent = isScrolled
                        }
                    }
                    .onChange(of: focusedField) { _, newValue in
                        scrollToFocusedField(newValue, proxy: scrollProxy)
                    }
                }
            }

            // The continue button has been hoisted to OnboardingFlowView
            // so it can morph (via Liquid Glass) into a back + continue
            // pair when advancing to the next step. This view no longer
            // renders its own bottom bar.
        }
        .preferredColorScheme(.dark)
        .onAppear {
            hydrateFromClerk()
            if isUsernameLocallyValid && availability == nil {
                debounceUsernameCheck()
            }
        }
        .onChange(of: username) { _, _ in
            availability = nil
            if !usernameTouched { usernameTouched = true }
            debounceUsernameCheck()
        }
        .onChange(of: name) { _, _ in
            if !nameTouched { nameTouched = true }
        }
        // Single source-of-truth sync: any time the derived form-valid
        // state changes (from name, username, or availability), push it
        // up to the flow-level binding.
        .onChange(of: isFormValid, initial: true) { _, newValue in
            canContinue = newValue
        }
        .onChange(of: validationTrigger) { _, _ in
            // Flow asked us to surface validation hints (user tapped the
            // disabled continue button at the flow level).
            nameTouched = true
            usernameTouched = true
        }
        .fullScreenCover(isPresented: $showCamera) {
            OnboardingProfileCameraView { image in
                applyProfileImage(image)
            }
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { applyProfileImage(image) }
                }
            }
        }
    }

    /// Sets a new profile image and updates the top-of-screen tint by
    /// extracting the image's dominant color (mirrors ProfileView).
    private func applyProfileImage(_ image: UIImage) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            profileImage = image
            selectedEmoji = nil
            isEditingEmoji = false
        }
        Task.detached(priority: .userInitiated) {
            let color = image.dominantColor()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.4)) {
                    imageDominantColor = color
                }
            }
        }
    }

    // MARK: - Profile Circle

    private static let profileCircleDiameter: CGFloat = 100

    @ViewBuilder
    private var profileSection: some View {
        if isEditingEmoji {
            emojiEditSection
        } else {
            staticProfileSection
        }
    }

    private var staticProfileSection: some View {
        ZStack(alignment: .topTrailing) {
            profileCircle

            if profileImage != nil || selectedEmoji != nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        profileImage = nil
                        selectedEmoji = nil
                        imageDominantColor = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(
            width: Self.profileCircleDiameter,
            height: Self.profileCircleDiameter
        )
    }

    @ViewBuilder
    private var profileCircle: some View {
        let size = Self.profileCircleDiameter
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let emoji = selectedEmoji {
                ZStack {
                    profileColor
                    Text(emoji)
                        .font(.system(size: size * 0.55))
                }
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.46))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    /// Replaces the static profile circle while the user is choosing an
    /// emoji avatar. Visually identical to AddPersonSheet's dummy-friend
    /// editor: the carousel sits behind a fixed center circle and a hue
    /// slider sits directly below it.
    private var emojiEditSection: some View {
        VStack(spacing: 16) {
            EmojiCarousel(
                baseEmojis: Self.faceEmojis,
                selectedColor: profileColor,
                selectedEmoji: Binding(
                    get: { selectedEmoji ?? "🐼" },
                    set: { newValue in
                        selectedEmoji = newValue
                        profileImage = nil
                    }
                ),
                circleSize: 84
            )
            .frame(height: 96)

            HueSlider(value: $profileHue)
                .padding(.horizontal, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var topGradientOverlay: some View {
        if let color = topGradientColor {
            LinearGradient(
                colors: [color.opacity(0.35), color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: - Photo Action Pills

    private static let actionPillHeight: CGFloat = 44

    private var photoActionPills: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                actionPill(
                    icon: { Image(systemName: "camera").font(.footnote) },
                    label: "Take photo"
                ) {
                    showCamera = true
                }

                emojiActionPill

                actionPill(
                    icon: { Image(systemName: "photo.on.rectangle").font(.footnote) },
                    label: "Choose"
                ) {
                    showPhotoLibrary = true
                }
            }
            .frame(height: Self.actionPillHeight)
        }
    }

    private func actionPill<Icon: View>(
        @ViewBuilder icon: () -> Icon,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(label)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: Self.actionPillHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var emojiActionPill: some View {
        actionPill(
            icon: { animatedEmojiIcon },
            label: "Set emoji"
        ) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                if isEditingEmoji {
                    // Tap again to lock in the choice and collapse back to
                    // the static profile circle.
                    isEditingEmoji = false
                } else {
                    if selectedEmoji == nil {
                        selectedEmoji = currentEmojiPreview
                    }
                    profileImage = nil
                    imageDominantColor = nil
                    isEditingEmoji = true
                }
            }
        }
    }

    /// Rotating face emoji with a blur-fade-up transition that mimics the
    /// system "rolling number" content transition.
    private var animatedEmojiIcon: some View {
        ZStack {
            Text(currentEmojiPreview)
                .font(.footnote)
                .id(currentEmojiPreview)
                .transition(
                    AnyTransition.asymmetric(
                        insertion: AnyTransition.move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.6)),
                        removal: AnyTransition.move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.6))
                    )
                )
        }
        .frame(width: 16, height: 18)
        .clipped()
        .task { await runEmojiPreviewLoop() }
    }

    @MainActor
    private func runEmojiPreviewLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            var next = Self.faceEmojis.randomElement() ?? currentEmojiPreview
            // Avoid repeating the same emoji twice in a row.
            while next == currentEmojiPreview && Self.faceEmojis.count > 1 {
                next = Self.faceEmojis.randomElement() ?? next
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                currentEmojiPreview = next
            }
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Your name").foregroundStyle(Color.appText.opacity(0.32))
                )
                .textContentType(.name)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .username }
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.white.opacity(0.05))
                .clipShape(Capsule())
                // Make the whole capsule tappable, not just the glyph
                // hit area of the underlying UITextField.
                .contentShape(Capsule())
                .onTapGesture { focusedField = .name }

                if nameTouched && !isNameValid {
                    inlineHint(
                        text: "Add your name so friends can recognise you.",
                        color: .orange
                    )
                }
            }
            .id(Field.name)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("@")
                        .foregroundStyle(Color.appText.opacity(0.45))

                    TextField(
                        "",
                        text: $username,
                        prompt: Text("username").foregroundStyle(Color.appText.opacity(0.32))
                    )
                    .focused($focusedField, equals: .username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.done)
                    .foregroundStyle(Color.appText)
                    .onChange(of: username) { _, newValue in
                        var filtered = newValue.lowercased().filter {
                            $0.isLetter || $0.isNumber || $0 == "_"
                        }
                        if filtered.count > 20 {
                            filtered = String(filtered.prefix(20))
                        }
                        if filtered != newValue {
                            username = filtered
                        }
                    }

                    usernameStateIndicator
                }
                .font(.body)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.white.opacity(0.05))
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { focusedField = .username }

                usernameStatusText
            }
            .id(Field.username)
        }
    }

    private func scrollToFocusedField(_ field: Field?, proxy: ScrollViewProxy) {
        guard let field else { return }

        withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
            proxy.scrollTo(field, anchor: .center)
        }

        // The bottom CTA follows the keyboard, so run one more scroll after
        // the keyboard/button animation has started to keep the input visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(duration: 0.3, bounce: 0.04)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var onboardingScrollTopFadeMask: some View {
        if hasScrolledContent {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.black
        }
    }

    private func inlineHint(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var usernameStateIndicator: some View {
        if isChecking {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.7))
        } else if let availability {
            Image(systemName: availability.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(availability.available ? .green : .red)
        } else if usernameTouched && !username.isEmpty && !isUsernameLocallyValid {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var usernameStatusText: some View {
        let info = usernameStatusInfo
        if let (text, color) = info {
            inlineHint(text: text, color: color)
        }
    }

    private var usernameStatusInfo: (String, Color)? {
        if isChecking {
            return ("Checking availability…", .white.opacity(0.5))
        }
        if let availability {
            if availability.available {
                return ("Available!", .green)
            }
            return (availability.reason ?? "Not available", .red)
        }
        if usernameTouched {
            if username.isEmpty {
                return ("Pick a username so friends can find you.", .orange)
            }
            if !isUsernameLocallyValid {
                return ("3-20 characters: letters, numbers, underscores.", .orange)
            }
        }
        return nil
    }

    // MARK: - Title

    /// Title lives below the shared onboarding pills and above the page content.
    private var topTitle: some View {
        Text("Add your name so friends know it's you.")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hydration

    private func hydrateFromClerk() {
        guard name.isEmpty else { return }
        guard let user = clerk.user else { return }

        let first = user.firstName ?? ""
        let last = user.lastName ?? ""
        let fromClerk = [first, last].filter { !$0.isEmpty }.joined(separator: " ")

        if !fromClerk.isEmpty {
            name = fromClerk
        } else if let email = user.primaryEmailAddress?.emailAddress {
            let local: String
            if let atIndex = email.firstIndex(of: "@") {
                local = String(email[..<atIndex])
            } else {
                local = email
            }
            let cleaned = local
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            name = cleaned
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        // Skip the touched-side-effects since this is a programmatic hydration.
        nameTouched = false

        let urlString = user.imageUrl
        if !urlString.isEmpty, let url = URL(string: urlString) {
            Task { await loadProfileImage(from: url) }
        }
    }

    private func loadProfileImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run { applyProfileImage(image) }
            }
        } catch {
            // Ignore – the user can pick a photo manually.
        }
    }

    // MARK: - Username Availability Check

    private func debounceUsernameCheck() {
        checkTask?.cancel()

        guard isUsernameLocallyValid else {
            isChecking = false
            return
        }

        isChecking = true
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            var args: [String: (any ConvexEncodable)?] = [
                "username": trimmedUsername
            ]

            if let clerkId = clerk.user?.id {
                args["clerkId"] = clerkId
            }

            let subscription = convexService.client.subscribe(
                to: "users:checkUsernameAvailable",
                with: args,
                yielding: UsernameAvailabilityResponse.self
            )
            .replaceError(
                with: UsernameAvailabilityResponse(available: false, reason: "Check failed")
            )
            .values

            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    availability = result
                    isChecking = false
                }
                break
            }
        }
    }
}

#Preview {
    OnboardingAboutYouView(
        canContinue: .constant(false),
        profileImage: .constant(nil),
        selectedEmoji: .constant(nil),
        profileHue: .constant(0.571),
        isEditingEmoji: .constant(false),
        imageDominantColor: .constant(nil),
        name: .constant(""),
        username: .constant(""),
        nameTouched: .constant(false),
        usernameTouched: .constant(false),
        availability: .constant(nil)
    )
        .preferredColorScheme(.dark)
}
