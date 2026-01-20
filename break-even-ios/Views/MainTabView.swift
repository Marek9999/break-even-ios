//
//  MainTabView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI

/// Main tab view containing all primary app sections
struct MainTabView: View {
    @Environment(\.convexService) private var convexService
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    HomeView()
                }
            }
            
            Tab("History", systemImage: "clock.fill", value: 1) {
                HistoryView()
            }
            
            Tab("Profile", systemImage: "person.fill", value: 2) {
                ProfileView()
            }
        }
    }
}

#Preview {
    MainTabView()
}
