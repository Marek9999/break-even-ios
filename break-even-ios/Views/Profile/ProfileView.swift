//
//  ProfileView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import PhotosUI
import Clerk
import ConvexMobile

private enum ProfileDestination: Hashable {
    case friends
    #if DEBUG
    case shaderTest
    case edgeCurveLab
    #endif
}

struct ProfileView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    @Environment(\.openURL) private var openURL
    
    @Binding var isDetailShowing: Bool
    
    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var navigationPath = NavigationPath()
    
    private var displayName: String {
        if let user = clerk.user {
            let first = user.firstName ?? ""
            let last = user.lastName ?? ""
            let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { return full }
            if let email = user.primaryEmailAddress?.emailAddress {
                return email
            }
        }
        return viewModel.currentUser?.name ?? "User"
    }
    
    private var userEmail: String {
        clerk.user?.primaryEmailAddress?.emailAddress
            ?? viewModel.currentUser?.email
            ?? ""
    }
    
    private var userInitials: String {
        if let user = clerk.user {
            let first = user.firstName?.first.map(String.init) ?? ""
            let last = user.lastName?.first.map(String.init) ?? ""
            if !first.isEmpty || !last.isEmpty { return "\(first)\(last)" }
        }
        return "U"
    }
    
    // MARK: - Body
    
    init(isDetailShowing: Binding<Bool> = .constant(false)) {
        _isDetailShowing = isDetailShowing
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    infoSection
                    cardsSection
                    feedbackSection
                    signOutSection
                    
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(alignment: .top) {
                gradientOverlay
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                profileDestinationView(for: destination)
            }
            .sheet(isPresented: $viewModel.showAddContact) {
                AddPersonSheet()
            }
            .sheet(isPresented: $viewModel.showCurrencyPicker) {
                CurrencyPickerSheet(
                    selectedCurrency: Binding(
                        get: { viewModel.currentUser?.defaultCurrency ?? "USD" },
                        set: { updateUserCurrency(to: $0) }
                    )
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .photosPicker(
                isPresented: $viewModel.showPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePickedPhoto(newItem) }
            }
            .fullScreenCover(isPresented: $viewModel.showCamera) {
                CameraCaptureView { image in
                    Task { await uploadProfileImage(image) }
                }
            }
            .alert("Sign Out?", isPresented: $viewModel.showSignOutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) { performSignOut() }
            } message: {
                Text("Are you sure you want to sign out of your account?")
            }
            #if DEBUG
            .alert("Nuke All Data?", isPresented: $viewModel.showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Nuke It", role: .destructive) { clearAllUserData() }
            } message: {
                Text("This will delete ALL your friends, transactions, and splits. This cannot be undone.")
            }
            #endif
            .onChange(of: navigationPath.count) { _, newCount in
                withAnimation(.spring(duration: 0.35)) {
                    isDetailShowing = newCount > 0
                }
            }
            .onAppear { startSubscriptions() }
            .onDisappear { viewModel.unsubscribe() }
            .task(id: clerk.user?.imageUrl) {
                await viewModel.loadAvatarImage(from: clerk.user?.imageUrl)
            }
        }
    }
    
    // MARK: - Gradient Overlay
    
    @ViewBuilder
    private var gradientOverlay: some View {
        if let color = viewModel.dominantColor {
            LinearGradient(
                colors: [color.opacity(0.15), color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                avatarImageView(size: 100)
                
                Menu {
                    Button {
                        viewModel.showPhotoLibrary = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        viewModel.showCamera = true
                    } label: {
                        Label("Take Picture", systemImage: "camera")
                    }
                    
                    if viewModel.cachedAvatarImage != nil {
                        Button(role: .destructive) {
                            Task { await removeProfileImage() }
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .offset(x: 2, y: 2)
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Avatar Image
    
    @ViewBuilder
    private func avatarImageView(size: CGFloat) -> some View {
        if let cachedImage = viewModel.cachedAvatarImage {
            Image(uiImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if viewModel.isUpdatingPhoto {
                        Circle().fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
        } else {
            Text(userInitials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.accentColor)
                .clipShape(Circle())
                .overlay {
                    if viewModel.isUpdatingPhoto {
                        Circle().fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(label: "User Name", value: displayName)
            Divider().padding(.horizontal)
            infoRow(label: "Email", value: userEmail)
        }
        .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.text.opacity(0.6))
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
    }
    
    // MARK: - Cards Section
    
    private var cardsSection: some View {
        HStack(spacing: 20) {
            friendsCard
            currencyCard
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: Friends Card
    
    private var friendsCard: some View {
        NavigationLink(value: ProfileDestination.friends) {
            VStack(alignment: .leading, spacing: 12) {
                friendAvatarStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                HStack {
                    Text("My Friends")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    
                    Spacer()
                    
                    Text("\(viewModel.otherFriends.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var friendAvatarStack: some View {
        let previews = viewModel.oldestFriendPreviews
        if previews.isEmpty {
            Image(systemName: "person.2.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 40)
        } else {
            HStack(spacing: -10) {
                ForEach(previews, id: \.id) { friend in
                    FriendAvatar(friend: friend, size: 40)
                        .overlay(
                            Circle()
                                .stroke(.background, lineWidth: 2)
                        )
                }
            }
        }
    }
    
    // MARK: Currency Card
    
    private var currencyCard: some View {
        let currencyCode = viewModel.currentUser?.defaultCurrency ?? "USD"
        let currency = SupportedCurrency.from(code: currencyCode)
        let flag = currency?.flag ?? "🇺🇸"
        
        return Button {
            viewModel.showCurrencyPicker = true
        } label: {
            VStack(spacing: 12) {
                Text(flag)
                    .font(.system(size: 52))
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
                
                HStack {
                    Text("Default Currency")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.background.secondary.opacity(0.6))
                    
                    currencyGradient(for: currency)
                        .frame(height: 80)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 16
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
    
    private func currencyGradient(for currency: SupportedCurrency?) -> some View {
        let color: Color = {
            switch currency {
            case .USD: return .blue
            case .EUR: return .indigo
            case .GBP: return .purple
            case .CAD: return .red
            case .AUD: return .green
            case .INR: return .orange
            case .JPY: return .red
            case .none: return .blue
            }
        }()
        
        return LinearGradient(
            colors: [color.opacity(0.1), color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(spacing: 0) {
            Text("Feedback")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            Button {
                if let url = URL(string: "mailto:createplus.club@gmail.com") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Text("Contact Us")
                        .fontWeight(.medium)
                        .foregroundStyle(.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Sign Out Section
    
    private var signOutSection: some View {
        Button {
            viewModel.showSignOutConfirmation = true
        } label: {
            Text("Sign Out")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appDestructive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appDestructive.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
    }
    
    // MARK: - DEBUG Section
    
    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: 0) {
            Text("Developer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                NavigationLink(value: ProfileDestination.shaderTest) {
                    debugRow(label: "Scan Beam Shader Test", icon: "wand.and.rays")
                }
                
                Divider().padding(.leading, 16)
                
                NavigationLink(value: ProfileDestination.edgeCurveLab) {
                    debugRow(label: "Edge Curve Lab", icon: "chart.line.uptrend.xyaxis")
                }
                
                Divider().padding(.leading, 16)
                
                Button { manualSyncUser() } label: {
                    if viewModel.isSyncing {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Syncing...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Sync User to Convex", icon: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(viewModel.isSyncing)
                
                Divider().padding(.leading, 16)
                
                Button { seedSampleData() } label: {
                    if viewModel.isSeedingData {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Creating sample data...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Seed Sample Data", icon: "wand.and.stars")
                    }
                }
                .disabled(viewModel.isSeedingData || viewModel.currentUser == nil)
                
                Divider().padding(.leading, 16)
                
                Button { viewModel.showClearConfirmation = true } label: {
                    if viewModel.isClearingData {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Clearing data...")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    } else {
                        debugRow(label: "Nuke All Data", icon: "trash.fill", destructive: true)
                    }
                }
                .disabled(viewModel.isClearingData || viewModel.currentUser == nil)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            
            if let message = viewModel.clearMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.clearError ? .red : .green)
                    .padding(.top, 6)
            } else if let message = viewModel.syncMessage ?? viewModel.seedMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle((viewModel.syncError || viewModel.seedError) ? .red : .green)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 10)
    }
    
    private func debugRow(label: String, icon: String, destructive: Bool = false) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(destructive ? .red : .text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    #endif
    
    // MARK: - Navigation Destinations
    
    @ViewBuilder
    private func profileDestinationView(for destination: ProfileDestination) -> some View {
        switch destination {
        case .friends:
            ContactsListView(friends: viewModel.otherFriends)
        #if DEBUG
        case .shaderTest:
            ShaderTestView()
        case .edgeCurveLab:
            EdgeCurveLabView()
        #endif
        }
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToFriends(clerkId: clerkId)
        viewModel.subscribeToUser(clerkId: clerkId)
    }
    
    // MARK: - Currency Update
    
    private func updateUserCurrency(to newCurrency: String) {
        guard let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let _: String = try await convexService.client.mutation(
                    "users:updateProfile",
                    with: [
                        "clerkId": clerkId,
                        "defaultCurrency": newCurrency
                    ]
                )
            } catch {
                #if DEBUG
                print("Failed to update currency: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Photo Actions
    
    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        await uploadProfileImage(uiImage)
    }
    
    private func uploadProfileImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        viewModel.isUpdatingPhoto = true
        do {
            let _ = try await clerk.user?.setProfileImage(imageData: imageData)
            try await convexService.syncUser(clerk: clerk)
            await viewModel.loadAvatarImage(from: clerk.user?.imageUrl)
        } catch {
            #if DEBUG
            print("Failed to upload profile image: \(error)")
            #endif
        }
        viewModel.isUpdatingPhoto = false
    }
    
    private func removeProfileImage() async {
        viewModel.isUpdatingPhoto = true
        do {
            let _ = try await clerk.user?.deleteProfileImage()
            try await convexService.syncUser(clerk: clerk)
            viewModel.cachedAvatarImage = nil
            withAnimation { viewModel.dominantColor = nil }
        } catch {
            #if DEBUG
            print("Failed to remove profile image: \(error)")
            #endif
        }
        viewModel.isUpdatingPhoto = false
    }
    
    // MARK: - Sign Out
    
    private func performSignOut() {
        Task {
            do {
                try await clerk.signOut()
            } catch {
                #if DEBUG
                print("Failed to sign out: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Developer Functions
    
    #if DEBUG
    private func manualSyncUser() {
        viewModel.isSyncing = true
        viewModel.syncMessage = nil
        viewModel.syncError = false
        
        Task {
            do {
                try await convexService.syncUser(clerk: clerk)
                viewModel.syncMessage = "User synced successfully!"
                viewModel.syncError = false
                startSubscriptions()
            } catch {
                viewModel.syncMessage = "Sync failed: \(error.localizedDescription)"
                viewModel.syncError = true
            }
            viewModel.isSyncing = false
        }
    }
    
    private func seedSampleData() {
        guard let clerkId = clerk.user?.id else {
            viewModel.seedMessage = "Error: Not logged in"
            viewModel.seedError = true
            return
        }
        
        viewModel.isSeedingData = true
        viewModel.seedMessage = nil
        viewModel.seedError = false
        
        Task {
            do {
                let message = try await convexService.seedSampleData(clerkId: clerkId)
                viewModel.seedMessage = message
                viewModel.seedError = false
                startSubscriptions()
            } catch {
                viewModel.seedMessage = "Error: \(error.localizedDescription)"
                viewModel.seedError = true
            }
            viewModel.isSeedingData = false
        }
    }
    
    private func clearAllUserData() {
        guard let clerkId = clerk.user?.id else {
            viewModel.clearMessage = "Error: Not logged in"
            viewModel.clearError = true
            return
        }
        
        viewModel.isClearingData = true
        viewModel.clearMessage = nil
        viewModel.clearError = false
        viewModel.seedMessage = nil
        viewModel.syncMessage = nil
        
        Task {
            do {
                struct ClearResult: Codable {
                    let message: String
                    let deleted: DeletedCounts
                    struct DeletedCounts: Codable {
                        let friends: Int
                        let transactions: Int
                        let splits: Int
                    }
                }
                
                let result: ClearResult = try await convexService.client.mutation(
                    "seed:clearUserData",
                    with: ["clerkId": clerkId]
                )
                
                viewModel.clearMessage = "Nuked: \(result.deleted.friends) friends, \(result.deleted.transactions) transactions, \(result.deleted.splits) splits"
                viewModel.clearError = false
                startSubscriptions()
            } catch {
                viewModel.clearMessage = "Error: \(error.localizedDescription)"
                viewModel.clearError = true
            }
            viewModel.isClearingData = false
        }
    }
    #endif
}

// MARK: - Camera Capture View

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}
