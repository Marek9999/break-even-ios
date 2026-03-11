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
    
    @State private var keyboardPrewarmText = ""
    @FocusState private var keyboardPrewarmFocused: Bool
    
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
        .background {
            TextField("", text: $keyboardPrewarmText)
                .focused($keyboardPrewarmFocused)
                .keyboardType(.decimalPad)
                .opacity(0)
                .frame(width: 1, height: 1)
                .offset(x: -1000)
                .allowsHitTesting(false)
        }
        .onAppear {
            prewarmKeyboard()
        }
    }
    
    private func prewarmKeyboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            keyboardPrewarmFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                keyboardPrewarmFocused = false
            }
        }
    }
}

#Preview {
    MainTabView()
}
