//
//  OnboardingScanReceiptView.swift
//  PayUp
//
//  Third onboarding step. Pitches the receipt scanner with a tall
//  phone-aspect video placeholder above the bottom title + button.
//  The top page indicator is rendered by OnboardingFlowView, so this
//  view leaves a fixed gap at the top for it.
//

import SwiftUI

struct OnboardingScanReceiptView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.homeSectionBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Reserves room for the shared page indicator from
                // OnboardingFlowView, mirroring OnboardingAboutYouView.
                Color.clear.frame(height: 44)

                Spacer(minLength: 0)
            }

            // Title pinned near the bottom, ignoring the keyboard inset
            // for consistency with the previous step (there's no keyboard
            // on this screen, but the behaviour reads the same on push).
            VStack {
                Spacer()
                bottomTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 130)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .allowsHitTesting(false)

            // Bottom bar (back + continue) is rendered by OnboardingFlowView
            // so the buttons can Liquid-Glass-morph between steps.
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom Title

    private var bottomTitle: some View {
        Text("Scan receipts, and stop worrying about who didn't have drinks")
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
