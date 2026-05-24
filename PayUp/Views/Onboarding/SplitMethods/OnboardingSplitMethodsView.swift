//
//  OnboardingSplitMethodsView.swift
//  PayUp
//
//  Fourth onboarding step. Introduces split-method switching with the
//  same video-first structure as the receipt scanning walkthrough.
//

import SwiftUI

struct OnboardingSplitMethodsView: View {
    @Binding var selectedMethod: NewSplitMethod

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
                SplitMethodSelector(selectedMethod: $selectedMethod)
                    .frame(height: 64)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                bottomTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 130)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom Title

    private var bottomTitle: some View {
        Text("Swipe between the split methods that work for you")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var selectedMethod: NewSplitMethod = .equal
    OnboardingSplitMethodsView(selectedMethod: $selectedMethod)
        .preferredColorScheme(.dark)
}
