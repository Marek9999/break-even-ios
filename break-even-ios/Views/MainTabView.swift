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
    
    // Keyboard pre-warming - initialize keyboard early to avoid first-use lag
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
            // Hidden TextField for keyboard pre-warming
            // Positioned offscreen (not zero-sized) to properly initialize keyboard
            TextField("", text: $keyboardPrewarmText)
                .focused($keyboardPrewarmFocused)
                .keyboardType(.decimalPad) // Pre-warm the decimal pad specifically
                .opacity(0)
                .frame(width: 1, height: 1)
                .offset(x: -1000) // Move offscreen
                .allowsHitTesting(false)
        }
        .onAppear {
            prewarmKeyboard()
        }
    }
    
    /// Pre-warm the keyboard system to avoid first-use lag
    /// This initializes the keyboard infrastructure early so it's ready when user needs it
    private func prewarmKeyboard() {
        // #region agent log
        if let data = try? JSONSerialization.data(withJSONObject: ["location": "MainTabView.prewarmKeyboard:45", "message": "Keyboard prewarm STARTING", "data": [:] as [String: Any], "timestamp": Date().timeIntervalSince1970 * 1000, "sessionId": "debug-session", "hypothesisId": "PREWARM"], options: []), let json = String(data: data, encoding: .utf8) { if let handle = FileHandle(forWritingAtPath: "/Users/rudradas/break-even-ios/.cursor/debug.log") { handle.seekToEndOfFile(); handle.write((json + "\n").data(using: .utf8)!); handle.closeFile() } else { try? (json + "\n").write(toFile: "/Users/rudradas/break-even-ios/.cursor/debug.log", atomically: false, encoding: .utf8) } }
        // #endregion
        
        // Small delay to let the view settle, then trigger keyboard initialization
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            keyboardPrewarmFocused = true
            
            // Keep focused for 0.5s to ensure keyboard fully initializes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                keyboardPrewarmFocused = false
                // #region agent log
                if let data = try? JSONSerialization.data(withJSONObject: ["location": "MainTabView.prewarmKeyboard:57", "message": "Keyboard prewarm COMPLETED", "data": [:] as [String: Any], "timestamp": Date().timeIntervalSince1970 * 1000, "sessionId": "debug-session", "hypothesisId": "PREWARM"], options: []), let json = String(data: data, encoding: .utf8) { if let handle = FileHandle(forWritingAtPath: "/Users/rudradas/break-even-ios/.cursor/debug.log") { handle.seekToEndOfFile(); handle.write((json + "\n").data(using: .utf8)!); handle.closeFile() } else { try? (json + "\n").write(toFile: "/Users/rudradas/break-even-ios/.cursor/debug.log", atomically: false, encoding: .utf8) } }
                // #endregion
            }
        }
    }
}

#Preview {
    MainTabView()
}
