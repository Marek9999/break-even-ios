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
    @State private var swipeHintOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.homeSectionBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // Reserves room for the shared page indicator from
                // OnboardingFlowView.
                Color.clear.frame(height: 44)

                topTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)

                SplitMethodSelector(selectedMethod: $selectedMethod)
                    .frame(height: 64)
                    .padding(.horizontal, 20)

                swipeHint
                    .padding(.top, 2)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Title

    private var topTitle: some View {
        Text("Pick the split that fits the chaos.")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeHint: some View {
        Text("Try swiping here")
            .font(.subheadline)
            .foregroundStyle(Color.text.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: swipeHintOffset)
            .task { await runSwipeHintAnimation() }
    }

    @MainActor
    private func runSwipeHintAnimation() async {
        while !Task.isCancelled {
            await rubberBandHint(toward: 14)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await rubberBandHint(toward: -14)
            try? await Task.sleep(for: .seconds(3))
        }
    }

    @MainActor
    private func rubberBandHint(toward offset: CGFloat) async {
        let rebound = offset * 0.45
        let steps: [(CGFloat, TimeInterval)] = [
            (offset, 0.3),
            (rebound, 0.24),
            (offset, 0.26),
            (0, 0.42)
        ]

        for (targetOffset, duration) in steps {
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: duration)) {
                swipeHintOffset = targetOffset
            }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}

#Preview {
    @Previewable @State var selectedMethod: NewSplitMethod = .equal
    OnboardingSplitMethodsView(selectedMethod: $selectedMethod)
        .preferredColorScheme(.dark)
}
