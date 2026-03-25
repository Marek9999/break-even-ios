//
//  NotificationManager.swift
//  break-even-ios
//

import Foundation
import SwiftUI
import ConvexMobile
internal import Combine
import UserNotifications
import UIKit

enum AppNotificationRoute: Equatable {
    case transaction(String)
    case friends
    case activity
}

@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()
    
    let deviceId: String
    
    var authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    var notificationsEnabled = false
    var isUpdatingPreference = false
    var pendingRoute: AppNotificationRoute?
    var lastErrorMessage: String?
    
    private var apnsToken: String?
    private var currentClerkId: String?
    
    private init() {
        if let existingId = UserDefaults.standard.string(forKey: Self.deviceIdDefaultsKey) {
            deviceId = existingId
        } else {
            let newId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newId, forKey: Self.deviceIdDefaultsKey)
            deviceId = newId
        }
    }
    
    var notificationDescription: String {
        "All the new activities listed in the activity tab will be sent as a notification."
    }
    
    var shouldShowSettingsPrompt: Bool {
        authorizationStatus == .denied
    }
    
    func handleAuthenticatedSession(clerkId: String) async {
        currentClerkId = clerkId
        await refreshAuthorizationStatus()
        
        do {
            let remoteSettings = try await fetchCurrentDeviceSettings(clerkId: clerkId)
            
            notificationsEnabled = remoteSettings?.notificationsEnabled ?? false
            apnsToken = remoteSettings?.apnsToken ?? apnsToken
            
            if notificationsEnabled && !authorizationStatus.canDeliverNotifications {
                notificationsEnabled = false
            }
            
            try await syncCurrentDeviceState(clerkId: clerkId)
            
            if notificationsEnabled && authorizationStatus.canDeliverNotifications {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    func handleSignedOutLocally() {
        currentClerkId = nil
        notificationsEnabled = false
        apnsToken = nil
        UIApplication.shared.unregisterForRemoteNotifications()
    }
    
    func prepareForSignOut(clerkId: String) async {
        do {
            let _: Bool = try await ConvexService.shared.client.mutation(
                "notificationDevices:markCurrentDeviceSignedOut",
                with: [
                    "clerkId": clerkId,
                    "deviceId": deviceId,
                ] as [String: (any ConvexEncodable)?]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        
        handleSignedOutLocally()
    }
    
    func enableNotifications() async {
        guard let clerkId = currentClerkId else { return }
        guard !isUpdatingPreference else { return }
        
        isUpdatingPreference = true
        defer { isUpdatingPreference = false }
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            
            guard granted, authorizationStatus.canDeliverNotifications else {
                notificationsEnabled = false
                try await syncCurrentDeviceState(clerkId: clerkId)
                return
            }
            
            notificationsEnabled = true
            UIApplication.shared.registerForRemoteNotifications()
            try await syncCurrentDeviceState(clerkId: clerkId)
        } catch {
            notificationsEnabled = false
            lastErrorMessage = error.localizedDescription
        }
    }
    
    func disableNotifications() async {
        guard let clerkId = currentClerkId else { return }
        guard !isUpdatingPreference else { return }
        
        isUpdatingPreference = true
        defer { isUpdatingPreference = false }
        
        notificationsEnabled = false
        UIApplication.shared.unregisterForRemoteNotifications()
        
        do {
            await refreshAuthorizationStatus()
            try await syncCurrentDeviceState(clerkId: clerkId)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    func updatePreference(isEnabled: Bool) async {
        if isEnabled {
            await enableNotifications()
        } else {
            await disableNotifications()
        }
    }
    
    func handleRemoteNotificationRegistration(deviceToken: Data) {
        apnsToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        
        guard let clerkId = currentClerkId else { return }
        Task {
            do {
                try await syncCurrentDeviceState(clerkId: clerkId)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func handleRemoteNotificationRegistrationFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
    
    func handleNotificationResponse(userInfo: [AnyHashable: Any]) {
        pendingRoute = Self.route(from: userInfo)
    }
    
    func consumePendingRoute() -> AppNotificationRoute? {
        let route = pendingRoute
        pendingRoute = nil
        return route
    }
    
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = Self.authorizationStatus(from: settings.authorizationStatus)
    }
    
    private func syncCurrentDeviceState(clerkId: String) async throws {
        var args: [String: (any ConvexEncodable)?] = [
            "clerkId": clerkId,
            "deviceId": deviceId,
            "notificationsEnabled": notificationsEnabled,
            "authorizationStatus": authorizationStatus.rawValue,
            "platform": "ios",
        ]
        
        if let apnsToken, !apnsToken.isEmpty {
            args["apnsToken"] = apnsToken
        }
        
        let _: NotificationDeviceSettings = try await ConvexService.shared.client.mutation(
            "notificationDevices:upsertCurrentDevice",
            with: args
        )
    }
    
    private func fetchCurrentDeviceSettings(clerkId: String) async throws -> NotificationDeviceSettings? {
        let stream = ConvexService.shared.client.subscribe(
            to: "notificationDevices:getCurrentDeviceSettings",
            with: [
                "clerkId": clerkId,
                "deviceId": deviceId,
            ] as [String: (any ConvexEncodable)?],
            yielding: NotificationDeviceSettings?.self
        )
        .values
        
        for try await value in stream {
            return value
        }
        
        return nil
    }
    
    private static func authorizationStatus(from status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .notDetermined
        }
    }
    
    private static func route(from userInfo: [AnyHashable: Any]) -> AppNotificationRoute {
        if let destination = userInfo["destination"] as? String {
            switch destination {
            case "transaction":
                if let transactionId = userInfo["transactionId"] as? String {
                    return .transaction(transactionId)
                }
            case "friends":
                return .friends
            default:
                break
            }
        }
        
        if let activityType = userInfo["activityType"] as? String,
           (activityType == ActivityType.splitCreated.rawValue || activityType == ActivityType.splitEdited.rawValue),
           let transactionId = userInfo["transactionId"] as? String {
            return .transaction(transactionId)
        }
        
        if let activityType = userInfo["activityType"] as? String,
           let type = ActivityType(rawValue: activityType),
           type.isFriendRelated {
            return .friends
        }
        
        return .activity
    }
    
    private static let deviceIdDefaultsKey = "notifications.device-id"
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRemoteNotificationRegistration(deviceToken: deviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRemoteNotificationRegistrationFailure(error)
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationManager.shared.handleNotificationResponse(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }
}

private struct NotificationManagerKey: EnvironmentKey {
    static let defaultValue: NotificationManager = .shared
}

extension EnvironmentValues {
    var notificationManager: NotificationManager {
        get { self[NotificationManagerKey.self] }
        set { self[NotificationManagerKey.self] = newValue }
    }
}
