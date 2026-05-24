//
//  OnboardingScanReceiptView.swift
//  PayUp
//
//  Third onboarding step. Pitches the receipt scanner with a tall
//  phone-aspect video placeholder below the top title.
//  The top page indicator is rendered by OnboardingFlowView, so this
//  view leaves a fixed gap at the top for it.
//

import SwiftUI

struct OnboardingScanReceiptView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.homeSectionBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Reserves room for the shared page indicator from
                // OnboardingFlowView, mirroring OnboardingAboutYouView.
                Color.clear.frame(height: 44)

                topTitle
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            // Bottom bar (back + continue) is rendered by OnboardingFlowView
            // so the buttons can Liquid-Glass-morph between steps.
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Title

    private var topTitle: some View {
        Text("Snap the receipt and skip the drink detective work.")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

#Preview {
    OnboardingScanReceiptView()
        .preferredColorScheme(.dark)
}
