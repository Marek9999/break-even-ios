//
//  OnboardingSettleBillsView.swift
//  PayUp
//
//  Final onboarding step. Shows settlement as the last walkthrough
//  moment using the same video-first layout as the previous demo steps.
//

import SwiftUI

struct OnboardingSettleBillsView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.homeSectionBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Reserves room for the shared page indicator from
                // OnboardingFlowView.
                Color.clear.frame(height: 44)

                topTitle
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Title

    private var topTitle: some View {
        Text("Settle up without doing friendship algebra.")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingSettleBillsView()
        .preferredColorScheme(.dark)
}
