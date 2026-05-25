//
//  ActivityView.swift
//  PayUp
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct ActivityView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var viewModel = ActivityViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var activityScrollProgress: CGFloat = 0
    
    @Binding var searchText: String
    @Binding var isScrolled: Bool
    @Binding var isDetailShowing: Bool
    
    var onNavigateToFriends: (() -> Void)?
    var usesSheetChrome: Bool
    var onDismiss: (() -> Void)?
    
    private var subscriptionKey: String {
        "\(clerk.user?.id ?? "signed-out"):\(convexService.subscriptionRestartToken)"
    }
    
    init(
        searchText: Binding<String>,
        isScrolled: Binding<Bool>,
        isDetailShowing: Binding<Bool>,
        onNavigateToFriends: (() -> Void)? = nil,
        usesSheetChrome: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        _searchText = searchText
        _isScrolled = isScrolled
        _isDetailShowing = isDetailShowing
        self.onNavigateToFriends = onNavigateToFriends
        self.usesSheetChrome = usesSheetChrome
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if usesSheetChrome {
                    sheetHeader
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        if viewModel.groupedActivities.isEmpty {
                            if let error = viewModel.errorMessage {
                                ContentUnavailableView(
                                    "Couldn't Load Activity",
                                    systemImage: "wifi.exclamationmark",
                                    description: Text(error)
                                )
                                .frame(minHeight: 400)
                                .foregroundStyle(.white)
                            } else if !viewModel.searchText.isEmpty {
                                ContentUnavailableView(
                                    "No Results",
                                    systemImage: "magnifyingglass",
                                    description: Text("No activities match \"\(viewModel.searchText)\"")
                                )
                                .frame(minHeight: 400)
                                .foregroundStyle(.white)
                            } else {
                                ContentUnavailableView(
                                    "No Activity",
                                    systemImage: "bolt",
                                    description: Text("Your activity feed will appear here")
                                )
                                .frame(minHeight: 400)
                                .foregroundStyle(.white)
                            }
                        } else {
                            activityList
                        }
                    }
                    .padding(.horizontal, usesSheetChrome ? 16 : 0)
                    .padding(.top, usesSheetChrome ? 8 : 0)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(usesSheetChrome ? .hidden : .automatic)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y > 20
                } action: { _, newValue in
                    isScrolled = newValue
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    let scrolledFromTop = geometry.contentOffset.y + geometry.contentInsets.top
                    let threshold: CGFloat = 24
                    return min(max(scrolledFromTop / threshold, 0), 1)
                } action: { _, newValue in
                    activityScrollProgress = newValue
                }
                .overlay(alignment: .top) {
                    activityTopFadeOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(usesSheetChrome ? Color.homeSectionBackground : Color.clear)
            .toolbar {
                if !usesSheetChrome {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Activity")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        timeRangeMenu
                    }
                }
            }
            .task(id: subscriptionKey) {
                startSubscriptions()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
            }
            .navigationDestination(for: String.self) { transactionId in
                TransactionDetailLoader(transactionId: transactionId)
            }
            .safeAreaInset(edge: .bottom) {
                if let error = viewModel.errorMessage, !viewModel.activities.isEmpty {
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: navigationPath.count) { _, newCount in
            withAnimation(.spring(duration: 0.35)) {
                isDetailShowing = newCount > 0
            }
        }
    }
    
    // MARK: - Sheet Header
    
    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Text("Activity")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appText)
            
            Spacer()
            
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    timeRangeMenu
                    
                    Button {
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(Color.homeSectionBackground)
    }
    
    private var timeRangeMenu: some View {
        Menu {
            ForEach(ActivityTimeRange.allCases, id: \.self) { range in
                Button {
                    viewModel.timeRange = range
                } label: {
                    HStack {
                        Text(range.rawValue)
                        if viewModel.timeRange == range {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            timeRangeMenuLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter Activity")
    }
    
    @ViewBuilder
    private var activityTopFadeOverlay: some View {
        if usesSheetChrome {
            LinearGradient(
                colors: [
                    Color.homeSectionBackground,
                    Color.homeSectionBackground.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28 * activityScrollProgress)
            .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var timeRangeMenuLabel: some View {
        if usesSheetChrome {
            Image(systemName: "calendar")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(.white)
        }
    }
    
    // MARK: - Activity List
    
    private var activityList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(viewModel.groupedActivities) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appText.opacity(0.6))
                        .padding(.horizontal, usesSheetChrome ? 0 : 16)
                    
                    sectionCard(activities: section.activities)
                }
            }
        }
    }
    
    private func sectionCard(activities: [ConvexActivity]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(activities.enumerated()), id: \.element._id) { index, activity in
                Button {
                    handleActivityTap(activity)
                } label: {
                    ActivityRow(activity: activity)
                }
                .buttonStyle(.plain)
                
                if index < activities.count - 1 {
                    Divider()
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.historyListBackground)
        .clipShape(RoundedRectangle(cornerRadius: usesSheetChrome ? 24 : 20, style: .continuous))
        .padding(.horizontal, usesSheetChrome ? 0 : 16)
    }
    
    // MARK: - Navigation
    
    private func handleActivityTap(_ activity: ConvexActivity) {
        let type = activity.activityType
        
        switch type {
        case .invitationReceived, .invitationAccepted, .invitationRejected,
             .invitationCancelled, .friendRemoved:
            onNavigateToFriends?()
            
        case .splitCreated, .splitEdited:
            if let txId = activity.transactionId {
                navigationPath.append(txId)
            }
            
        case .splitDeleted, .settlementRecorded:
            break
        }
    }
    
    // MARK: - Subscriptions
    
    private func startSubscriptions() {
        guard let clerkId = clerk.user?.id else { return }
        viewModel.subscribeToActivities(clerkId: clerkId)
    }
}

