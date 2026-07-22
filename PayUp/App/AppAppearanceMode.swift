//
//  AppAppearanceMode.swift
//  PayUp
//
//  Created by Cursor on 2026-06-23.
//

import SwiftUI

enum AppAppearanceMode {
    case standard
    case lightLab

    static var current: Self {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAYUP_APPEARANCE"] == "lightLab" {
            return .lightLab
        }
        #endif

        return .standard
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .standard:
            return .dark
        case .lightLab:
            return .light
        }
    }
}
