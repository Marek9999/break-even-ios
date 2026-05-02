//
//  HomeView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import Glur

enum HomeHistoryRequest: Equatable {
    case open
    case openTransaction(String)
}

struct HomeView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    @Environment(\.sessionCoordinator) private var sessionCoordinator
    
    @State private var viewModel = HomeViewModel()
    @State private var historyViewModel = HistoryViewModel()
    @State private var showReceiptCamera = false
    @State private var scanReceiptForInline = false
    @State private var selectedFriend: FriendWithBalance?
    @State private var receiptScanResult: ReceiptScanResult?
    @State private var pendingSavedTransactionId: String?
    private let edgeLightConfiguration = HomeEdgeLightConfiguration()
    @State private var inlineNewSplitViewModel: NewSplitViewModel?
    @State private var inlineNewSplitStartsAtFriends: Bool = false
    @State private var inlineScanViewModel: InlineScanReceiptViewModel?
    @State private var headerHeight: CGFloat = 0
    @State private var centerHeight: CGFloat = 0
    @State private var isHistoryMode: Bool = false
    @State private var historyActionProgress: CGFloat = 0
    @State private var historyPanelContentProgress: CGFloat = 0
    @State private var historyPanelContentTask: Task<Void, Never>?
    @State private var historyNavigationPath = NavigationPath()
    @State private var historyScrollProgress: CGFloat = 0
    @State private var isHistorySearchActive: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isHistorySearchFocused: Bool
    @Namespace private var glassNamespace
    @Namespace private var historySearchNamespace
    
    private let panelPeek: CGFloat = 18
    private let panelCornerRadius: CGFloat = 72
    private let topPanelCollapsedBottomRadius: CGFloat = 20
    private let historyPanelCornerRadius: CGFloat = 36
    
    let userAvatarUrl: String?
    let userInitials: String
    let unreadActivityCount: Int
    let onOpenProfile: (() -> Void)?
    let onOpenActivity: (() -> Void)?
    let onOpenTransactionInHistory: ((String) -> Void)?
    @Binding var historyRequest: HomeHistoryRequest?
    
    private let sectionBackground = Color.homeSectionBackground
    private let owedSectionLightColor = Color(red: 128 / 255, green: 123 / 255, blue: 1.0, opacity: 1.0)
    private let iOweSectionLightColor = Color(red: 251 / 255, green: 165 / 255, blue: 228 / 255, opacity: 0.59)
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    private var userCurrency: String {
        sessionCoordinator.currentUser?.defaultCurrency ?? "USD"
    }
    
    private var hasUnreadActivity: Bool {
        unreadActivityCount > 0
    }
    
    private var isInlineNewSplitPresented: Bool {
        inlineNewSplitViewModel != nil
    }
    
    private var isInlineScanPresented: Bool {
        inlineScanViewModel != nil
    }
    
    private var isInlineModePresented: Bool {
        isInlineNewSplitPresented || isInlineScanPresented
    }
    
    private var isScanAnalyzing: Bool {
        inlineScanViewModel?.phase == .analyzing
    }
    
    private var isScanConfirming: Bool {
        inlineScanViewModel?.phase == .confirming
    }
    
    init(
        userAvatarUrl: String? = nil,
        userInitials: String = "U",
        unreadActivityCount: Int = 0,
        onOpenProfile: (() -> Void)? = nil,
        onOpenActivity: (() -> Void)? = nil,
        onOpenTransactionInHistory: ((String) -> Void)? = nil,
        historyRequest: Binding<HomeHistoryRequest?> = .constant(nil)
    ) {
        self.userAvatarUrl = userAvatarUrl
        self.userInitials = userInitials
        self.unreadActivityCount = unreadActivityCount
        self.onOpenProfile = onOpenProfile
        self.onOpenActivity = onOpenActivity
        self.onOpenTransactionInHistory = onOpenTransactionInHistory
        self._historyRequest = historyRequest
    }
    
    var body: some View {
        NavigationStack(path: $historyNavigationPath) {
            homeBody
                .navigationDestination(for: String.self) { txId in
                    TransactionDetailLoader(transactionId: txId)
                }
        }
        .onChange(of: historyRequest) { _, request in
            guard let request else { return }
            switch request {
            case .open:
                enterHistoryMode()
            case .openTransaction(let id):
                enterHistoryMode()
                historyNavigationPath.append(id)
            }
            historyRequest = nil
        }
    }
    
    private var homeBody: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let visibleHeight = proxy.size.height + safeBottom
            let availableHeight = max(0, visibleHeight - headerHeight - centerHeight)
            let halfPanelHeight = availableHeight / 2
            let topPanelHeight = isHistoryMode ? availableHeight : halfPanelHeight
            let bottomPanelHeight = isHistoryMode ? 0 : halfPanelHeight
            let topY = headerHeight
            let centerY = headerHeight + topPanelHeight
            let bottomY = headerHeight + topPanelHeight + centerHeight
            let bottomOffscreenOffset = bottomPanelHeight + safeBottom + 120
            
            ZStack(alignment: .topLeading) {
                Color.black
                
                if let vm = inlineNewSplitViewModel {
                    InlineNewSplitFlow(
                        viewModel: vm,
                        allFriends: viewModel.allFriends,
                        selfFriend: viewModel.selfFriend,
                        onScanReceipt: { openReceiptCameraForInline() },
                        onSave: { saveInlineNewSplit() },
                        startsAtFriends: inlineNewSplitStartsAtFriends
                    )
                    .id(ObjectIdentifier(vm))
                    .padding(.top, headerHeight + panelPeek + 12)
                    .padding(.bottom, 16)
                    .frame(width: proxy.size.width, height: visibleHeight)
                    .transition(.opacity.combined(with: .blurReplace))
                }
                
                if let scanVM = inlineScanViewModel {
                    InlineScanReceiptFlow(
                        viewModel: scanVM,
                        onScanComplete: handleInlineScanComplete,
                        onDismiss: cancelInlineScan
                    )
                    .id(ObjectIdentifier(scanVM))
                    .padding(.top, headerHeight + panelPeek + 12)
                    .padding(.bottom, isScanConfirming ? 16 : safeBottom + 12)
                    .frame(width: proxy.size.width, height: visibleHeight)
                    .transition(.opacity.combined(with: .blurReplace))
                }
                
                topPanel(panelHeight: topPanelHeight)
                    .frame(width: proxy.size.width, height: topPanelHeight)
                    .offset(y: topY)
                    .offset(y: isInlineModePresented ? -(topPanelHeight - panelPeek) : 0)
                
                bottomPanel(panelHeight: bottomPanelHeight + safeBottom)
                    .frame(width: proxy.size.width, height: bottomPanelHeight + safeBottom)
                    .offset(y: bottomY)
                    .offset(y: isInlineModePresented ? bottomPanelHeight + safeBottom + 100 : 0)
                    .offset(y: isHistoryMode ? bottomOffscreenOffset : 0)
                    .opacity(isHistoryMode ? 0 : 1)
                    .allowsHitTesting(!isHistoryMode)
                
                centerActionSection
                    .background {
                        GeometryReader { centerProxy in
                            Color.clear.preference(
                                key: CenterHeightPreferenceKey.self,
                                value: centerProxy.size.height
                            )
                        }
                    }
                    .frame(width: proxy.size.width)
                    .offset(y: centerY)
                    .opacity(isInlineModePresented ? 0 : 1)
                    .blur(radius: isInlineModePresented ? 12 : 0)
                    .allowsHitTesting(!isInlineModePresented)
                
                sharedHeader
                    .padding(.horizontal, 10)
                    .background(headerBackground)
                    .background {
                        GeometryReader { headerProxy in
                            Color.clear.preference(
                                key: HeaderHeightPreferenceKey.self,
                                value: headerProxy.size.height
                            )
                        }
                    }
                    .frame(width: proxy.size.width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.black.ignoresSafeArea())
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { headerHeight = $0 }
        .onPreferenceChange(CenterHeightPreferenceKey.self) { centerHeight = $0 }
        .navigationBarHidden(true)
        .animation(.spring(duration: 0.42, bounce: 0.08), value: isInlineNewSplitPresented)
        .animation(.spring(duration: 0.42, bounce: 0.08), value: isInlineScanPresented)
        .animation(.spring(duration: 0.32, bounce: 0.05), value: isScanAnalyzing)
        .animation(.spring(duration: 0.42, bounce: 0.06), value: isScanConfirming)
        .fullScreenCover(item: $receiptScanResult, onDismiss: handleSplitSheetDismissal) { result in
            NewSplitSheet(
                receiptResult: result,
                allFriends: viewModel.allFriends,
                selfFriend: viewModel.selfFriend,
                userDefaultCurrency: userCurrency,
                onSaveSuccess: { transactionId in
                    pendingSavedTransactionId = transactionId
                }
            )
        }
        .fullScreenCover(isPresented: $showReceiptCamera) {
            ReceiptCameraView { result in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if scanReceiptForInline, let vm = inlineNewSplitViewModel {
                        scanReceiptForInline = false
                        vm.replaceReceiptData(from: result)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else {
                        receiptScanResult = result
                    }
                    
                    #if DEBUG
                    print("=== HomeView: Receipt Result Set ===")
                    print("Title: \(result.title), Total: \(result.total), Items: \(result.items.count)")
                    print("====================================")
                    #endif
                }
            }
        }
        .sheet(item: $selectedFriend) { friendWithBalance in
            PersonDetailSheet(
                friend: friendWithBalance.friend,
                balance: BalanceSummary(
                    friendOwesUser: friendWithBalance.friendOwesUser,
                    userOwesFriend: friendWithBalance.userOwesFriend,
                    netBalance: friendWithBalance.netBalance,
                    userCurrency: userCurrency,
                    balancesByCurrency: friendWithBalance.balancesByCurrency
                ),
                onStartSplit: { friend in
                    selectedFriend = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openNewSplit(preSelectedFriend: friend)
                    }
                }
            )
        }
        .task(id: subscriptionKey) {
            startSubscriptions()
        }
    }
    
    // MARK: - Mode toggling
    
    private func enterHistoryMode() {
        guard !isHistoryMode else { return }
        triggerHaptic(.medium)
        historyPanelContentTask?.cancel()
        historyPanelContentTask = nil
        
        withAnimation(.easeOut(duration: 0.1)) {
            historyPanelContentProgress = 1
        }
        
        withAnimation(.spring(duration: 0.45, bounce: 0.08)) {
            isHistoryMode = true
            historyActionProgress = 1
        }
    }
    
    private func exitHistoryMode() {
        guard isHistoryMode else { return }
        triggerHaptic(.light)
        historyPanelContentTask?.cancel()
        
        isHistorySearchFocused = false
        isHistorySearchActive = false
        historyViewModel.searchText = ""
        
        withAnimation(.spring(duration: 0.45, bounce: 0.08)) {
            isHistoryMode = false
            historyActionProgress = 0
        }
        
        historyPanelContentTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    historyPanelContentProgress = 0
                }
                historyPanelContentTask = nil
            }
        }
    }
    
    // MARK: - Shared Header
    
    private var sharedHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack(alignment: .leading) {
                Text("What did you\nspend on today?")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .blur(radius: (isInlineModePresented || isHistoryMode) ? 8 : 0)
                    .opacity((isInlineModePresented || isHistoryMode) ? 0 : 1)
                
                Text("New Split")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .blur(radius: isInlineNewSplitPresented ? 0 : 8)
                    .opacity(isInlineNewSplitPresented ? 1 : 0)
                
                Text("History")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .blur(radius: isHistoryMode ? 0 : 8)
                    .opacity(isHistoryMode ? 1 : 0)
            }
            
            Spacer(minLength: 12)
            
            headerActionsArea
                .opacity(isInlineScanPresented ? 0 : 1)
                .blur(radius: isInlineScanPresented ? 8 : 0)
                .allowsHitTesting(!isInlineScanPresented)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .overlay {
            scanModeHeaderTitle
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }
    
    private var isScanCapturing: Bool {
        isInlineScanPresented && !isScanAnalyzing && !isScanConfirming
    }
    
    @ViewBuilder
    private var scanModeHeaderTitle: some View {
        ZStack {
            Text("Scan Receipt")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appText)
                .blur(radius: isScanCapturing ? 0 : 8)
                .opacity(isScanCapturing ? 1 : 0)
            
            Text("Analyzing...")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appText)
                .blur(radius: (isInlineScanPresented && isScanAnalyzing) ? 0 : 8)
                .opacity((isInlineScanPresented && isScanAnalyzing) ? 1 : 0)
            
            Text("Confirm Items")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appText)
                .blur(radius: (isInlineScanPresented && isScanConfirming) ? 0 : 8)
                .opacity((isInlineScanPresented && isScanConfirming) ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
    
    private var headerBackground: some View {
        HStack {
            Text("test")
                .opacity(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sectionBackground)
        .overlay(
            LinearGradient(stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.6)
            ], startPoint: .top, endPoint: .bottom)
        )
    }
    
    private var headerActionsArea: some View {
        GlassEffectContainer(spacing: 12) {
            if !isInlineNewSplitPresented {
                HStack(spacing: 10) {
                    Button {
                        triggerHaptic(.light)
                        onOpenActivity?()
                    } label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .overlay(alignment: .topTrailing) {
                                if hasUnreadActivity {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 1, y: -1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        triggerHaptic(.light)
                        onOpenProfile?()
                    } label: {
                        profileAvatar(size: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(sectionBackground)
                .clipShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("headerActions", in: glassNamespace)
            } else {
                HStack(spacing: 8) {
                    newSplitDateButton
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(sectionBackground)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                    
                    Button {
                        cancelInlineNewSplit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(sectionBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .glassEffectID("headerActions", in: glassNamespace)
            }
        }
    }
    
    private var newSplitDateBinding: Binding<Date> {
        Binding(
            get: { inlineNewSplitViewModel?.date ?? Date() },
            set: { inlineNewSplitViewModel?.date = $0 }
        )
    }
    
    @ViewBuilder
    private var newSplitDateButton: some View {
        if let vm = inlineNewSplitViewModel {
            Text(vm.date.smartFormatted)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .overlay {
                    DatePicker(selection: newSplitDateBinding, in: ...Date(), displayedComponents: .date) {}
                        .labelsHidden()
                        .colorMultiply(.clear)
                }
        }
    }
    
    // MARK: - Center Actions
    
    private var centerActionSection: some View {
        VStack(spacing: 12) {
            if let error = viewModel.error, !isHistoryMode {
                Button {
                    Task {
                        try? await convexService.recoverAuthenticatedSession(
                            clerk: clerk,
                            forceTokenRefresh: true
                        )
                    }
                } label: {
                    Label(error, systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
            
            historyActionCluster
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
        .background(Color.black)
    }
    
    private var historyActionCluster: some View {
        let progress = historyActionProgress
        return GlassEffectContainer(spacing: interpolate(18, 8, progress: progress)) {
            GeometryReader { proxy in
                let buttonSize: CGFloat = 52
                let expandedCenterWidth: CGFloat = 142
                let outerSpacing: CGFloat = 16
                let homeTotalWidth = buttonSize + outerSpacing + expandedCenterWidth + outerSpacing + buttonSize
                let historyTotalWidth = buttonSize + outerSpacing + buttonSize
                let homeStartX = (proxy.size.width - homeTotalWidth) / 2
                let historyStartX = (proxy.size.width - historyTotalWidth) / 2
                let scanHomeX = homeStartX + (buttonSize / 2)
                let centerHomeX = homeStartX + buttonSize + outerSpacing + (expandedCenterWidth / 2)
                let historyHomeX = homeStartX + buttonSize + outerSpacing + expandedCenterWidth + outerSpacing + (buttonSize / 2)
                let clusterHistoryX = historyStartX + (buttonSize / 2)
                let historyModeX = historyStartX + buttonSize + outerSpacing + (buttonSize / 2)
                let scanX = interpolate(scanHomeX, clusterHistoryX, progress: progress)
                let centerX = interpolate(centerHomeX, clusterHistoryX, progress: progress)
                let historyX = interpolate(historyHomeX, historyModeX, progress: progress)
                let centerWidth = interpolate(expandedCenterWidth, buttonSize, progress: progress)
                
                ZStack {
                    clusterScanButton(progress: progress)
                        .frame(width: buttonSize, height: buttonSize)
                        .position(x: scanX, y: proxy.size.height / 2)
                        .opacity(1 - Double(progress * 0.9))
                        .allowsHitTesting(progress < 0.2)
                    
                    clusterCenterButton(progress: progress, width: centerWidth)
                        .frame(width: centerWidth, height: buttonSize)
                        .position(x: centerX, y: proxy.size.height / 2)
                    
                    clusterHistoryButton(progress: progress)
                        .frame(width: buttonSize, height: buttonSize)
                        .position(x: historyX, y: proxy.size.height / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 56)
        }
    }
    
    private func clusterScanButton(progress: CGFloat) -> some View {
        return Button {
            openInlineScanReceipt()
        } label: {
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(1 - Double(progress))
                    .blur(radius: 8 * progress)
            }
            .frame(width: 52, height: 52)
            .glassEffect(
                .clear.tint(.white.opacity(interpolate(0.08, 0.12, progress: progress))).interactive(),
                in: .circle
            )
        }
        .buttonStyle(.plain)
    }
    
    private func clusterCenterButton(progress: CGFloat, width: CGFloat) -> some View {
        Button {
            if progress > 0.5 {
                exitHistoryMode()
            } else {
                openNewSplit(preSelectedFriend: nil)
            }
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("New Split")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.black)
                .opacity(1 - Double(progress))
                .blur(radius: 8 * progress)
                
                Image(systemName: "house")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(Double(progress))
                    .blur(radius: 8 * (1 - progress))
            }
            .frame(width: width, height: 52)
            .glassEffect(
                .clear.tint(.white.opacity(interpolate(0.9, 0, progress: progress))).interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }
    
    private func clusterHistoryButton(progress: CGFloat) -> some View {
        Button {
            if progress < 0.5 {
                enterHistoryMode()
            }
        } label: {
            ZStack {
                Image(systemName: "clock")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(1 - Double(progress))
                
                Image(systemName: "clock")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.black)
                    .opacity(Double(progress))
            }
            .frame(width: 52, height: 52)
            .glassEffect(
                .clear.tint(.white.opacity(interpolate(0.08, 0.88, progress: progress))).interactive(),
                in: .circle
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(progress < 0.95)
    }
    
    // MARK: - Balance Panels
    
    private var topPanelShape: UnevenRoundedRectangle {
        let bottomRadius: CGFloat
        if isInlineModePresented {
            bottomRadius = topPanelCollapsedBottomRadius
        } else if isHistoryMode {
            bottomRadius = historyPanelCornerRadius
        } else {
            bottomRadius = panelCornerRadius
        }
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
    }
    
    private var bottomPanelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: panelCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: panelCornerRadius
            ),
            style: .continuous
        )
    }
    
    private func topPanel(panelHeight: CGFloat) -> some View {
        let shape = topPanelShape
        return ZStack {
            shape.fill(sectionBackground)
            
            VStack(spacing: 0) {
                sectionContent(friends: viewModel.owedToMe, isOwedToUser: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                balanceInfo(title: "Owed to you", amount: viewModel.totalOwedToMe)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.top, 4)
                    .padding(.bottom, 42)
            }
            .opacity(isInlineModePresented ? 0 : 1 - Double(historyPanelContentProgress))
            .blur(radius: isInlineModePresented ? 12 : 12 * historyPanelContentProgress)
            .allowsHitTesting(!(isInlineModePresented || historyPanelContentProgress > 0.01))
            
            historyListContent
                .opacity(Double(historyPanelContentProgress))
                .blur(radius: 12 * (1 - historyPanelContentProgress))
                .allowsHitTesting(isHistoryMode && historyPanelContentProgress > 0.99)
            
            HomeEdgeLightOverlay(
                edge: .bottom,
                color: owedSectionLightColor,
                configuration: edgeLightConfiguration
            )
            .clipShape(shape)
            .opacity(isInlineModePresented ? 0 : 1 - Double(historyPanelContentProgress))
        }
        .clipShape(shape)
        .overlay(
            shape
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
                .opacity(isInlineModePresented ? 1 : 0)
        )
        .allowsHitTesting(!isInlineModePresented)
    }
    
    // MARK: - History List
    
    @ViewBuilder
    private var historyListContent: some View {
        let transactions = historyViewModel.filteredTransactions
        ScrollView {
            VStack(spacing: 0) {
                if transactions.isEmpty {
                    historyEmptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    historyTransactionsCard(transactions: transactions)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 72)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let scrolledFromTop = geometry.contentOffset.y + geometry.contentInsets.top
            let threshold: CGFloat = 24
            return min(max(scrolledFromTop / threshold, 0), 1)
        } action: { _, newValue in
            historyScrollProgress = newValue
        }
        .mask(historyTopFadeMask)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                historySearchBackdrop
                
                historySearchBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12 + max(0, keyboardHeight - centerHeight))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            applyHistoryKeyboardChange(notification: notification, isHiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            applyHistoryKeyboardChange(notification: notification, isHiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            applyHistoryKeyboardChange(notification: notification, isHiding: true)
        }
    }
    
    private var historySearchBackdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .opacity(0.55)
                .glur(
                    radius: 28,
                    offset: 0.0,
                    interpolation: 0.78,
                    direction: .up,
                    noise: 0.08
                )
            
            LinearGradient(
                stops: [
                    .init(color: sectionBackground.opacity(0.78), location: 0.0),
                    .init(color: sectionBackground.opacity(0.34), location: 0.48),
                    .init(color: sectionBackground.opacity(0.0), location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black.opacity(0.86), location: 0.42),
                    .init(color: .black.opacity(0.0), location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .frame(height: 132)
        .padding(.horizontal, -24)
        .padding(.bottom, -18)
        .allowsHitTesting(false)
    }
    
    private func applyHistoryKeyboardChange(notification: Notification, isHiding: Bool) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
        let target: CGFloat
        if isHiding {
            target = 0
        } else if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            target = frame.height
        } else {
            return
        }
        let animation: Animation = (UIView.AnimationCurve(rawValue: curveValue) == .linear)
            ? .linear(duration: duration)
            : .easeOut(duration: duration)
        withAnimation(animation) {
            keyboardHeight = target
        }
    }
    
    private var historyTopFadeMask: some View {
        let maxFadeHeight: CGFloat = 28
        let fadeHeight = maxFadeHeight * historyScrollProgress
        return VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            Color.black
        }
    }
    
    @ViewBuilder
    private var historyEmptyState: some View {
        if let error = historyViewModel.error {
            ContentUnavailableView(
                "Couldn't Load Transactions",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
            .foregroundStyle(.white)
        } else if !historyViewModel.searchText.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No transactions match \"\(historyViewModel.searchText)\"")
            )
            .foregroundStyle(.white)
        } else {
            ContentUnavailableView(
                "No Transactions",
                systemImage: "clock",
                description: Text("Your transaction history will appear here")
            )
            .foregroundStyle(.white)
        }
    }
    
    // MARK: - History Search
    
    @ViewBuilder
    private var historySearchBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Group {
                    if isHistorySearchActive {
                        historySearchField
                    } else {
                        historySearchPromptButton
                    }
                }
                .glassEffectID("historySearch", in: historySearchNamespace)
                
                historySearchTrailingControl
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(duration: 0.35), value: isHistorySearchActive)
    }
    
    private var historySearchPromptButton: some View {
        Button {
            activateHistorySearch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                Text("search friends, splits, items...")
                    .font(.system(size: 16))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search friends, splits, and items")
    }
    
    private var historySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white)
            
            TextField(
                "",
                text: Binding(
                    get: { historyViewModel.searchText },
                    set: { historyViewModel.searchText = $0 }
                ),
                prompt: Text("search friends, splits, items...")
                    .foregroundStyle(.white.opacity(0.6))
            )
            .focused($isHistorySearchFocused)
            .submitLabel(.search)
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
    
    @ViewBuilder
    private var historySearchTrailingControl: some View {
        if isHistorySearchActive {
            Button {
                deactivateHistorySearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Dismiss search")
            .transition(.scale(0.86).combined(with: .opacity))
        } else {
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { sortOrder in
                    Button {
                        historyViewModel.sortOrder = sortOrder
                        triggerHaptic(.light)
                    } label: {
                        Label(sortOrder.menuTitle, systemImage: sortOrder.systemImage)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Sort splits")
            .transition(.scale(0.86).combined(with: .opacity))
        }
    }
    
    private func activateHistorySearch() {
        triggerHaptic(.light)
        withAnimation(.spring(duration: 0.35)) {
            isHistorySearchActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isHistorySearchFocused = true
        }
    }
    
    private func deactivateHistorySearch() {
        isHistorySearchFocused = false
        withAnimation(.spring(duration: 0.3)) {
            isHistorySearchActive = false
            historyViewModel.searchText = ""
        }
    }
    
    private func historyTransactionsCard(transactions: [EnrichedTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(transactions.enumerated()), id: \.element._id) { index, transaction in
                NavigationLink(value: transaction._id) {
                    SplitHistoryRow(transaction: transaction)
                }
                .buttonStyle(.plain)
                
                if index < transactions.count - 1 {
                    Divider()
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.historyListBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private func bottomPanel(panelHeight: CGFloat) -> some View {
        let shape = bottomPanelShape
        return ZStack {
            shape.fill(sectionBackground)
            
            VStack(spacing: 0) {
                balanceInfo(title: "You owe", amount: viewModel.totalIOwe)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.top, 42)
                    .padding(.bottom, 8)
                
                sectionContent(friends: viewModel.iOwe, isOwedToUser: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(isInlineModePresented ? 0 : 1)
            .blur(radius: isInlineModePresented ? 12 : 0)
            
            HomeEdgeLightOverlay(
                edge: .top,
                color: iOweSectionLightColor,
                configuration: edgeLightConfiguration
            )
            .clipShape(shape)
            .opacity(isInlineModePresented ? 0 : 1)
        }
        .clipShape(shape)
        .allowsHitTesting(!isInlineModePresented)
    }
    
    private func balanceInfo(title: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.appText.opacity(0.6))
            
            Spacer(minLength: 12)
            
            Text(amount.asCurrency(code: userCurrency))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.appText)
        }
    }
    
    @ViewBuilder
    private func sectionContent(friends: [FriendWithBalance], isOwedToUser: Bool) -> some View {
        if let error = viewModel.error, friends.isEmpty {
            ContentUnavailableView(
                "Couldn't Load Your Balances",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
            .foregroundStyle(.white)
        } else if friends.isEmpty {
            BubbleClusterEmptyView(isOwedToUser: isOwedToUser)
        } else {
            BubbleClusterView(
                contacts: friends.map { ($0.friend, abs($0.netBalance)) },
                isOwedToUser: isOwedToUser,
                currencyCode: userCurrency,
                onPersonTap: { friend in
                    selectedFriend = friends.first(where: { $0.friend.id == friend.id })
                }
            )
            .id(isOwedToUser ? "owed-to-you" : "you-owe")
        }
    }
    
    // MARK: - Shared Components
    
    private func interpolate(_ from: CGFloat, _ to: CGFloat, progress: CGFloat) -> CGFloat {
        from + ((to - from) * progress)
    }
    
    @ViewBuilder
    private func profileAvatar(size: CGFloat) -> some View {
        if let userAvatarUrl, let url = URL(string: userAvatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsAvatar(size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsAvatar(size: size)
        }
    }
    
    private func initialsAvatar(size: CGFloat) -> some View {
        Text(userInitials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor)
            .clipShape(Circle())
    }
    
    // MARK: - Actions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToBalances(clerkId: clerkId)
        viewModel.subscribeToFriends(clerkId: clerkId)
        historyViewModel.subscribeToTransactions(clerkId: clerkId)
    }
    
    private func handleSplitSheetDismissal() {
        guard let transactionId = pendingSavedTransactionId else { return }
        pendingSavedTransactionId = nil
        onOpenTransactionInHistory?(transactionId)
    }
    
    private func openNewSplit(preSelectedFriend: ConvexFriend?) {
        triggerHaptic(.medium)
        
        let draft = NewSplitViewModel(
            preSelectedFriend: preSelectedFriend,
            defaultCurrency: userCurrency
        )
        prepareInlineNewSplit(viewModel: draft)
        
        inlineNewSplitStartsAtFriends = false
        withAnimation(.spring(duration: 0.42, bounce: 0.08)) {
            inlineNewSplitViewModel = draft
        }
    }
    
    private func prepareInlineNewSplit(viewModel draft: NewSplitViewModel) {
        if draft.paidBy == nil, let selfFriend = viewModel.selfFriend {
            draft.paidBy = selfFriend
        }
        
        if let selfFriend = viewModel.selfFriend {
            let alreadyRepresented = draft.participants.contains { participant in
                participant.id == selfFriend.id ||
                participant.isSelf ||
                participant.linkedUserId == selfFriend.ownerId
            }
            if !alreadyRepresented {
                draft.addParticipant(selfFriend)
            }
        }
    }
    
    private func saveInlineNewSplit() {
        guard let vm = inlineNewSplitViewModel,
              let clerkId = clerk.user?.id else { return }
        Task {
            do {
                let transactionId = try await vm.save(clerkId: clerkId)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    cancelInlineNewSplit()
                    onOpenTransactionInHistory?(transactionId)
                }
            } catch {
                #if DEBUG
                print("=== Failed to save inline new split: \(error) ===")
                #endif
            }
        }
    }
    
    private func cancelInlineNewSplit() {
        triggerHaptic(.light)
        
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        
        withAnimation(.spring(duration: 0.35, bounce: 0.04)) {
            inlineNewSplitViewModel = nil
        }
        inlineNewSplitStartsAtFriends = false
    }
    
    private func openReceiptCameraForInline() {
        scanReceiptForInline = true
        showReceiptCamera = true
    }
    
    private func openInlineScanReceipt() {
        triggerHaptic(.medium)
        let scanVM = InlineScanReceiptViewModel()
        withAnimation(.spring(duration: 0.42, bounce: 0.08)) {
            inlineScanViewModel = scanVM
        }
    }
    
    private func cancelInlineScan() {
        triggerHaptic(.light)
        inlineScanViewModel?.analysisTask?.cancel()
        withAnimation(.spring(duration: 0.35, bounce: 0.04)) {
            inlineScanViewModel = nil
        }
    }
    
    private func handleInlineScanComplete(_ result: ReceiptScanResult) {
        let draft = NewSplitViewModel(
            preSelectedFriend: nil,
            defaultCurrency: userCurrency
        )
        draft.replaceReceiptData(from: result)
        prepareInlineNewSplit(viewModel: draft)
        
        // Skip the amount + title steps since the scanned receipt already has
        // them. Land directly on the friends step so the user can add people.
        inlineNewSplitStartsAtFriends = true
        withAnimation(.spring(duration: 0.42, bounce: 0.08)) {
            inlineScanViewModel = nil
            inlineNewSplitViewModel = draft
        }
    }
    
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - Preference Keys

private struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CenterHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    HomeView(
        userInitials: "RD",
        unreadActivityCount: 2
    )
    .preferredColorScheme(.dark)
}
