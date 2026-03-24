import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    enum Step {
        case searchAndCreate
        case inviteOptions
    }
    
    enum InviteMethod: String, CaseIterable {
        case username = "Username"
        case email = "Email"
    }
    
    enum SearchState: Equatable {
        case idle
        case searching
        case found(PublicUserProfile)
        case notFound
        
        static func == (lhs: SearchState, rhs: SearchState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.searching, .searching), (.notFound, .notFound):
                return true
            case (.found(let a), .found(let b)):
                return a.id == b.id
            default:
                return false
            }
        }
    }
    
    enum EmailLookupState: Equatable {
        case idle
        case checking
        case onApp(userName: String?)
        case offApp
    }
    
    @State private var step: Step = .searchAndCreate
    @State private var inviteMethod: InviteMethod = .username
    @State private var inviteInput = ""
    @State private var searchState: SearchState = .idle
    @State private var emailLookupState: EmailLookupState = .idle
    @State private var searchTask: Task<Void, Never>?
    
    // Dummy user fields
    @State private var name = ""
    @State private var avatarEmoji = ""
    @State private var avatarColorHex: String? = nil
    
    // Loading / error
    @State private var isLoading = false
    @State private var error: String?
    
    // Result from createDummyFriend
    @State private var createdFriendId: String?
    @State private var userExistsOnApp = false
    
    // Invitation state
    @State private var inviteToken: String?
    @State private var copiedLink = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case search, name
    }
    
    private var trimmedInput: String {
        inviteInput.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }
    
    private var showDummyUserForm: Bool {
        switch inviteMethod {
        case .username:
            switch searchState {
            case .notFound:
                return true
            case .idle:
                return false
            default:
                return false
            }
        case .email:
            switch emailLookupState {
            case .onApp:
                return false
            case .idle, .checking, .offApp:
                return true
            }
        }
    }
    
    private var canProceed: Bool {
        switch inviteMethod {
        case .username:
            switch searchState {
            case .found:
                return true
            default:
                return !trimmedName.isEmpty
            }
        case .email:
            switch emailLookupState {
            case .onApp:
                return isValidEmail(trimmedInput)
            case .idle, .checking, .offApp:
                return isValidEmail(trimmedInput) && !trimmedName.isEmpty
            }
        }
    }
    
    private var displayName: String {
        if case .found(let profile) = searchState {
            return profile.name
        }
        if case .onApp(let userName) = emailLookupState, let userName, !userName.isEmpty {
            return userName
        }
        return trimmedName.isEmpty ? "Friend" : trimmedName
    }
    
    private var nextButtonTitle: String {
        if case .found = searchState {
            return "Add & Invite"
        }
        if case .onApp = emailLookupState {
            return "Add & Invite"
        }
        return "Create"
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .searchAndCreate:
                    searchAndCreateForm
                case .inviteOptions:
                    inviteOptionsView
                }
            }
            .navigationTitle(step == .searchAndCreate ? "Add Person" : "Invite \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .inviteOptions ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                if step == .searchAndCreate {
                    ToolbarItem(placement: .confirmationAction) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Button(nextButtonTitle) {
                                createPerson()
                            }
                            .fontWeight(.semibold)
                            .disabled(!canProceed)
                        }
                    }
                }
            }
            .onAppear {
                focusedField = .search
            }
            .interactiveDismissDisabled(isLoading)
        }
    }
    
    // MARK: - Step 1: Search & Create
    
    private var searchAndCreateForm: some View {
        Form {
            searchSection
            
            if case .found(let profile) = searchState {
                matchedUserSection(profile)
            }
            
            if case .onApp(let userName) = emailLookupState {
                emailLookupSection(userName: userName)
            }
            
            if searchState == .notFound {
                notFoundBanner
            }
            
            if showDummyUserForm {
                dummyUserDetailsSection
                avatarCustomizerSection
            }
            
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        Section {
            Picker("Search by", selection: $inviteMethod) {
                ForEach(InviteMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .onChange(of: inviteMethod) { _, _ in
                inviteInput = ""
                searchState = .idle
                emailLookupState = .idle
                error = nil
                searchTask?.cancel()
            }
            
            switch inviteMethod {
            case .username:
                usernameInputRow
            case .email:
                emailInputRow
            }
        } header: {
            Text("Find on BreakEven")
        } footer: {
            switch inviteMethod {
            case .username:
                Text("Search for their BreakEven username to add them directly.")
            case .email:
                Text("Enter their email to see whether they already use BreakEven. If they do, they can accept in app. If not, you can still invite them by email.")
            }
        }
    }
    
    private var usernameInputRow: some View {
        HStack(spacing: 4) {
            Text("@")
                .foregroundStyle(.secondary)
                .font(.body.monospaced())
            
            TextField("username", text: $inviteInput)
                .focused($focusedField, equals: .search)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.body.monospaced())
                .onChange(of: inviteInput) { _, newValue in
                    inviteInput = newValue.lowercased().filter {
                        $0.isLetter || $0.isNumber || $0 == "_"
                    }
                    if inviteInput.count > 20 {
                        inviteInput = String(inviteInput.prefix(20))
                    }
                    error = nil
                    debounceUsernameSearch()
                }
            
            searchStateIndicator
        }
    }
    
    @ViewBuilder
    private var searchStateIndicator: some View {
        switch searchState {
        case .searching:
            ProgressView()
                .controlSize(.small)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
        case .idle:
            if !trimmedInput.isEmpty && trimmedInput.count >= 3 {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var emailLookupIndicator: some View {
        switch emailLookupState {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .onApp:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .offApp:
            if isValidEmail(trimmedInput) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.secondary)
            }
        case .idle:
            if isValidEmail(trimmedInput) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var emailInputRow: some View {
        HStack(spacing: 8) {
            TextField("Email", text: $inviteInput)
                .focused($focusedField, equals: .search)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: inviteInput) { _, newValue in
                    inviteInput = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    error = nil
                    debounceEmailLookup()
                }
            
            emailLookupIndicator
        }
    }
    
    // MARK: - Matched User Section
    
    private func matchedUserSection(_ profile: PublicUserProfile) -> some View {
        Section {
            HStack(spacing: 12) {
                if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initialsCircle(for: profile.name, size: 44)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    initialsCircle(for: profile.name, size: 44)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                    if let username = profile.displayUsername {
                        Text(username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .padding(.vertical, 4)
        } header: {
            Text("User Found")
        }
    }
    
    private func emailLookupSection(userName: String?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Already on BreakEven", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                
                Text("\(userName ?? trimmedInput) already has an account. We'll connect them and send an in-app invite.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Not Found Banner
    
    private var notFoundBanner: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No user found with that username")
                        .font(.subheadline.weight(.medium))
                    Text("You can still create them as a contact and invite them later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - Dummy User Details
    
    private var dummyUserDetailsSection: some View {
        Section {
            TextField("Name", text: $name)
                .focused($focusedField, equals: .name)
                .textContentType(.name)
                .submitLabel(.done)
        } header: {
            Text("Contact Details")
        }
    }
    
    // MARK: - Avatar Customizer
    
    private var avatarCustomizerSection: some View {
        Section {
            VStack(spacing: 16) {
                avatarPreview
                emojiPickerRow
                colorPaletteRow
            }
            .padding(.vertical, 8)
        } header: {
            Text("Avatar")
        } footer: {
            Text("Customize how this person appears in your splits.")
        }
    }
    
    private var avatarPreview: some View {
        let bgColor = AvatarColors.color(forHex: avatarColorHex)
        
        return ZStack {
            if !avatarEmoji.isEmpty {
                Text(avatarEmoji)
                    .font(.system(size: 36))
            } else {
                Text(previewInitials)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 80, height: 80)
        .background(bgColor)
        .clipShape(Circle())
        .animation(.smooth(duration: 0.2), value: avatarEmoji)
        .animation(.smooth(duration: 0.2), value: avatarColorHex)
        .frame(maxWidth: .infinity)
    }
    
    private var previewInitials: String {
        let text = trimmedName
        guard !text.isEmpty else { return "?" }
        let components = text.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(text.prefix(2)).uppercased()
    }
    
    private var emojiPickerRow: some View {
        HStack {
            Text("Emoji")
                .foregroundStyle(.secondary)
            
            Spacer()
            
            EmojiTextField(
                text: $avatarEmoji,
                placeholder: "None",
                size: 40
            )
            
            if !avatarEmoji.isEmpty {
                Button {
                    avatarEmoji = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var colorPaletteRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 10) {
                colorSwatch(hex: nil, color: .accentColor, label: "Default")
                
                ForEach(AvatarColors.palette, id: \.hex) { item in
                    colorSwatch(hex: item.hex, color: item.color, label: item.name)
                }
            }
        }
    }
    
    private func colorSwatch(hex: String?, color: Color, label: String) -> some View {
        let isSelected = avatarColorHex == hex
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                avatarColorHex = hex
            }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                        Circle()
                            .strokeBorder(color, lineWidth: 1)
                            .padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
    
    private func initialsCircle(for name: String, size: CGFloat) -> some View {
        let components = name.split(separator: " ")
        let initials: String
        if components.count >= 2 {
            initials = "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            initials = String(name.prefix(2)).uppercased()
        }
        return Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
    
    // MARK: - Step 2: Invite Options
    
    private var inviteOptionsView: some View {
        List {
            if userExistsOnApp {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(displayName) is already on BreakEven")
                                .font(.subheadline.weight(.medium))
                            Text("They will be notified about your invitation in the app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Section {
                Button {
                    copyInviteLink()
                } label: {
                    Label {
                        HStack {
                            Text("Copy Invite Link")
                            Spacer()
                            if copiedLink {
                                Text("Copied!")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    } icon: {
                        Image(systemName: "link")
                    }
                }
                
                if inviteMethod == .email, !trimmedInput.isEmpty, !userExistsOnApp {
                    Button {
                        guard let inviteToken else { return }
                        sendViaEmail(to: trimmedInput, token: inviteToken)
                    } label: {
                        Label("Send Invite via Email", systemImage: "envelope")
                    }
                    .disabled(inviteToken == nil)
                }
            } header: {
                Text("Invite Options")
            } footer: {
                Text("You can use \(displayName) in splits right away. When they accept, your splits will sync with them.")
            }
            
            Section {
                Button {
                    dismiss()
                } label: {
                    Text("Skip — I'll invite later")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Username Search
    
    private func debounceUsernameSearch() {
        searchTask?.cancel()
        
        guard trimmedInput.count >= 3 else {
            searchState = trimmedInput.isEmpty ? .idle : .idle
            return
        }
        
        searchState = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            
            let subscription = convexService.client.subscribe(
                to: "users:getUserByUsername",
                with: ["username": trimmedInput],
                yielding: PublicUserProfile?.self
            )
            .replaceError(with: nil)
            .values
            
            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let profile = result {
                        searchState = .found(profile)
                    } else {
                        searchState = .notFound
                    }
                }
                break
            }
        }
    }
    
    private func debounceEmailLookup() {
        searchTask?.cancel()
        
        guard let clerkId = clerk.user?.id else {
            emailLookupState = .idle
            return
        }
        
        guard isValidEmail(trimmedInput) else {
            emailLookupState = .idle
            return
        }
        
        emailLookupState = .checking
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            
            let subscription = convexService.client.subscribe(
                to: "friends:checkEmailOnApp",
                with: [
                    "clerkId": clerkId,
                    "email": trimmedInput
                ],
                yielding: EmailLookupResponse.self
            )
            .replaceError(with: EmailLookupResponse(exists: false, userName: nil))
            .values
            
            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    emailLookupState = result.exists ? .onApp(userName: result.userName) : .offApp
                }
                break
            }
        }
    }
    
    private func isValidEmail(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return candidate.contains("@") && candidate.contains(".")
    }
    
    // MARK: - Create Person
    
    private func createPerson() {
        guard let clerkId = clerk.user?.id else {
            error = "Not authenticated"
            return
        }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                var args: [String: String] = [
                    "clerkId": clerkId
                ]
                
                if case .found = searchState {
                    args["linkedUsername"] = trimmedInput
                    args["name"] = displayName
                } else if inviteMethod == .email, case .onApp = emailLookupState {
                    args["name"] = displayName
                } else {
                    args["name"] = trimmedName
                    if !avatarEmoji.isEmpty {
                        args["avatarEmoji"] = avatarEmoji
                    }
                    if let hex = avatarColorHex {
                        args["avatarColor"] = hex
                    }
                }
                
                switch inviteMethod {
                case .username:
                    if case .found = searchState {
                        args["linkedUsername"] = trimmedInput
                    }
                case .email:
                    if !trimmedInput.isEmpty {
                        args["email"] = trimmedInput
                    }
                }
                
                let result: CreateFriendResponse = try await convexService.client.mutation(
                    "friends:createDummyFriend",
                    with: args
                )
                
                createdFriendId = result.friendId
                userExistsOnApp = result.userExistsOnApp
                
                // Auto-create invitation if we have invite info
                let hasInviteInfo = !trimmedInput.isEmpty
                if hasInviteInfo {
                    var inviteArgs: [String: String] = [
                        "clerkId": clerkId,
                        "friendId": result.friendId
                    ]
                    if inviteMethod == .email {
                        inviteArgs["recipientEmail"] = trimmedInput
                    }
                    
                    let inviteResult: CreateInvitationResponse = try await convexService.client.mutation(
                        "invitations:createInvitation",
                        with: inviteArgs
                    )
                    
                    inviteToken = inviteResult.token
                    
                    if inviteResult.autoAccepted {
                        await MainActor.run {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isLoading = false
                    withAnimation { step = .inviteOptions }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Invite Link Actions
    
    private func copyInviteLink() {
        guard let token = inviteToken else {
            generateAndCopyInvite()
            return
        }
        
        let link = "breakeven://invite/\(token)"
        UIPasteboard.general.string = link
        copiedLink = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { copiedLink = false }
        }
    }
    
    private func generateAndCopyInvite() {
        guard let clerkId = clerk.user?.id, let friendId = createdFriendId else { return }
        
        Task {
            do {
                var args: [String: String] = [
                    "clerkId": clerkId,
                    "friendId": friendId
                ]
                if inviteMethod == .email, !trimmedInput.isEmpty {
                    args["recipientEmail"] = trimmedInput
                }
                
                let result: CreateInvitationResponse = try await convexService.client.mutation(
                    "invitations:createInvitation",
                    with: args
                )
                
                inviteToken = result.token
                let link = "breakeven://invite/\(result.token)"
                UIPasteboard.general.string = link
                copiedLink = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { copiedLink = false }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func sendViaEmail(to emailAddress: String, token: String) {
        let link = "breakeven://invite/\(token)"
        let friendName = displayName
        let subject = "\(friendName), join me on BreakEven!"
        let body = "Hey \(friendName),\n\nI'd like to split expenses with you on BreakEven. Tap the link below to accept my invitation:\n\n\(link)\n\nSee you there!"
        
        let mailtoString = "mailto:\(emailAddress)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: mailtoString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    AddPersonSheet()
}
