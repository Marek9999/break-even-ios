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

            VStack(spacing: 0) {
                // Reserves room for the shared page indicator from
                // OnboardingFlowView.
                Color.clear.frame(height: 44)

                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                bottomTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 130)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom Title

    private var bottomTitle: some View {
        Text("Settle without having to solve an algebraic sum of who owes who")
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
