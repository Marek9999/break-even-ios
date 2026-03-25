//
//  ActivityView.swift
//  break-even-ios
//

import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct ActivityView: View {
    @Environment(\.clerk) private var clerk
    
    @State private var viewModel = ActivityViewModel()
    @State private var navigationPath = NavigationPath()
    
    @Binding var searchText: String
    @Binding var isScrolled: Bool
    @Binding var isDetailShowing: Bool
    
    var onNavigateToFriends: (() -> Void)?
    
    init(
        searchText: Binding<String>,
        isScrolled: Binding<Bool>,
        isDetailShowing: Binding<Bool>,
        onNavigateToFriends: (() -> Void)? = nil
    ) {
        _searchText = searchText
        _isScrolled = isScrolled
        _isDetailShowing = isDetailShowing
        self.onNavigateToFriends = onNavigateToFriends
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.groupedActivities.isEmpty {
                        if !viewModel.searchText.isEmpty {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "magnifyingglass",
                                description: Text("No activities match \"\(viewModel.searchText)\"")
                            )
                            .frame(minHeight: 400)
                        } else {
                            ContentUnavailableView(
                                "No Activity",
                                systemImage: "bolt",
                                description: Text("Your activity feed will appear here")
                            )
                            .frame(minHeight: 400)
                        }
                    } else {
                        activityList
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 20
            } action: { _, newValue in
                isScrolled = newValue
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Activity")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                
                ToolbarItem(placement: .topBarTrailing) {
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
                        Image(systemName: "calendar")
                            .font(.caption)
                    }
                }
            }
            .task(id: clerk.user?.id) {
                startSubscriptions()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
            }
            .navigationDestination(for: String.self) { transactionId in
                TransactionDetailLoader(transactionId: transactionId)
            }
        }
        .onChange(of: navigationPath.count) { _, newCount in
            withAnimation(.spring(duration: 0.35)) {
                isDetailShowing = newCount > 0
            }
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
                        .foregroundStyle(.text.opacity(0.6))
                        .padding(.horizontal)
                    
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
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

