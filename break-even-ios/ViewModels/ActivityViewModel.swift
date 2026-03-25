//
//  ActivityViewModel.swift
//  break-even-ios
//

import Foundation
import ConvexMobile
internal import Combine

enum ActivityTimeRange: String, CaseIterable {
    case allTime = "All Time"
    case last7Days = "Last 7 Days"
    case last1Month = "Last 1 Month"
    case last2Months = "Last 2 Months"
    
    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .allTime: return nil
        case .last7Days: return calendar.date(byAdding: .day, value: -7, to: .now)
        case .last1Month: return calendar.date(byAdding: .month, value: -1, to: .now)
        case .last2Months: return calendar.date(byAdding: .month, value: -2, to: .now)
        }
    }
}

struct ActivitySection: Identifiable {
    let id: String
    let title: String
    let activities: [ConvexActivity]
}

@MainActor
@Observable
class ActivityViewModel {
    var activities: [ConvexActivity] = []
    var unreadCount: Int = 0
    var searchText: String = ""
    var timeRange: ActivityTimeRange = .allTime
    var errorMessage: String?
    
    private var activitiesSubscription: Task<Void, Never>?
    private var unreadSubscription: Task<Void, Never>?
    
    private func handleSubscriptionFailure(_ context: String, error: Error) {
        self.errorMessage = "Couldn't refresh Activity right now."
        
        #if DEBUG
        print("Activity subscription failed (\(context)): \(error)")
        #endif
    }
    
    func subscribeToActivities(clerkId: String) {
        activitiesSubscription?.cancel()
        
        activitiesSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "activities:listActivities",
                    with: ["clerkId": clerkId],
                    yielding: [ConvexActivity].self
                )
                .values
                
                for try await items in subscription {
                    if Task.isCancelled { break }
                    self.errorMessage = nil
                    self.activities = items
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("activities:listActivities", error: error)
            }
        }
    }
    
    func subscribeToUnreadCount(clerkId: String) {
        unreadSubscription?.cancel()
        
        unreadSubscription = Task {
            let client = ConvexService.shared.client
            do {
                let subscription = client.subscribe(
                    to: "activities:getUnreadCount",
                    with: ["clerkId": clerkId],
                    yielding: Int.self
                )
                .values
                
                for try await count in subscription {
                    if Task.isCancelled { break }
                    self.errorMessage = nil
                    self.unreadCount = count
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                handleSubscriptionFailure("activities:getUnreadCount", error: error)
            }
        }
    }
    
    func markAllAsRead(clerkId: String) {
        Task {
            do {
                let _: Int = try await ConvexService.shared.client.mutation(
                    "activities:markAllAsRead",
                    with: ["clerkId": clerkId]
                )
            } catch {
                #if DEBUG
                print("Error marking activities as read: \(error)")
                #endif
            }
        }
    }
    
    func unsubscribe() {
        activitiesSubscription?.cancel()
        unreadSubscription?.cancel()
    }
    
    // MARK: - Filtering & Grouping
    
    var filteredActivities: [ConvexActivity] {
        var result = activities
        
        if let cutoff = timeRange.cutoffDate {
            let cutoffMs = cutoff.timeIntervalSince1970 * 1000
            result = result.filter { $0.createdAt >= cutoffMs }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(query) ||
                $0.actorName.localizedCaseInsensitiveContains(query) ||
                $0.type.localizedCaseInsensitiveContains(query)
            }
        }
        
        return result
    }
    
    private static let sectionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    
    var groupedActivities: [ActivitySection] {
        let filtered = filteredActivities
        var sections: [String: [ConvexActivity]] = [:]
        var sectionOrder: [String] = []
        
        for activity in filtered {
            let date = activity.createdAtDate
            let key = Self.sectionFormatter.string(from: date)
            if sections[key] == nil {
                sections[key] = []
                sectionOrder.append(key)
            }
            sections[key]?.append(activity)
        }
        
        return sectionOrder.map { key in
            ActivitySection(id: key, title: key, activities: sections[key] ?? [])
        }
    }
}
