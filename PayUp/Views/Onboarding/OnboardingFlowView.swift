//
//  OnboardingFlowView.swift
//  PayUp
//
//  Top-level container for the onboarding step machine. Welcome screen
//  fires bubbles and presents Apple/Google entry points; later steps
//  share a top pill indicator so the active pill can morph between
//  step changes while step content blur-fades horizontally.
//

import SwiftUI

struct OnboardingFlowView: View {
    let onClose: () -> Void

    fileprivate enum Step: Hashable {
        case welcome
        case aboutYou
        case scanReceipt
        case splitMethods
        case settleBills
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    private struct PageStep {
        let title: String
        let activeWidth: CGFloat
    }

    /// Titles for the four post-welcome onboarding steps. Index 0 is the
    /// currently expanded pill on the "About You" screen, etc.
    private static let pageSteps: [PageStep] = [
        PageStep(title: "About You", activeWidth: 90),
        PageStep(title: "Scan receipt", activeWidth: 112),
        PageStep(title: "Split methods", activeWidth: 118),
        PageStep(title: "Settle bills", activeWidth: 104)
    ]

    @State private var step: Step = .welcome
    @State private var bottomBarProgress: CGFloat = 0
    @State private var navigationDirection: NavigationDirection = .forward

    // State owned by the flow so the About You form survives step changes.
    @State private var aboutYouProfileImage: UIImage?
    @State private var aboutYouSelectedEmoji: String?
    @State private var aboutYouProfileHue: Double = 0.571
    @State private var aboutYouIsEditingEmoji: Bool = false
    @State private var aboutYouImageDominantColor: Color?
    @State private var aboutYouName: String = ""
    @State private var aboutYouUsername: String = ""
    @State private var aboutYouNameTouched: Bool = false
    @State private var aboutYouUsernameTouched: Bool = false
    @State private var aboutYouUsernameAvailability: UsernameAvailabilityResponse?
    @State private var onboardingSplitMethod: NewSplitMethod = .equal

    /// Flow-owned mirror of `OnboardingAboutYouView`'s form-validity flag.
    /// The About-You view writes to this binding; the flow-level bottom
    /// bar reads it to enable/disable its continue button.
    @State private var aboutYouCanContinue: Bool = false

    /// Bumped every time the user taps the disabled continue button while
    /// on About You. The About-You view watches this counter and pushes
    /// its inline error hints into the touched state in response.
    @State private var aboutYouValidationTrigger: Int = 0

    init(onClose: @escaping () -> Void) {
        self.init(onClose: onClose, initialStep: .welcome)
    }

    fileprivate init(onClose: @escaping () -> Void, initialStep: Step) {
        self.onClose = onClose
        _step = State(initialValue: initialStep)
        _bottomBarProgress = State(initialValue: Self.initialBottomBarProgress(for: initialStep))
        _aboutYouCanContinue = State(initialValue: initialStep != .aboutYou)
    }

    var body: some View {
        ZStack(alignment: .top) {
            currentStep
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsSharedMediaFrame {
                sharedMediaFrame
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if step != .welcome {
                pageIndicator
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }

            #if DEBUG
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Close onboarding (debug)")
            #endif
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(
                onAppleTap: { advance(to: .aboutYou) },
                onGoogleTap: { advance(to: .aboutYou) }
            )
            .transition(slideTransition)

        case .aboutYou:
            OnboardingAboutYouView(
                canContinue: $aboutYouCanContinue,
                validationTrigger: aboutYouValidationTrigger,
                profileImage: $aboutYouProfileImage,
                selectedEmoji: $aboutYouSelectedEmoji,
                profileHue: $aboutYouProfileHue,
                isEditingEmoji: $aboutYouIsEditingEmoji,
                imageDominantColor: $aboutYouImageDominantColor,
                name: $aboutYouName,
                username: $aboutYouUsername,
                nameTouched: $aboutYouNameTouched,
                usernameTouched: $aboutYouUsernameTouched,
                availability: $aboutYouUsernameAvailability
            )
            .transition(blurFadeTransition)

        case .scanReceipt:
            OnboardingScanReceiptView()
                .transition(blurFadeTransition)

        case .splitMethods:
            OnboardingSplitMethodsView(selectedMethod: $onboardingSplitMethod)
                .transition(blurFadeTransition)

        case .settleBills:
            OnboardingSettleBillsView()
                .transition(blurFadeTransition)
        }
    }

    // MARK: - Shared Media Frame

    private var showsSharedMediaFrame: Bool {
        switch step {
        case .scanReceipt, .splitMethods, .settleBills:
            return true
        case .welcome, .aboutYou:
            return false
        }
    }

    private var sharedMediaFrame: some View {
        GeometryReader { proxy in
            let isSplitMethods = step == .splitMethods
            let containerHeight = proxy.size.height * 0.74
            let topPadding: CGFloat = 78
            let frameScale: CGFloat = isSplitMethods ? 1.48 : 1
            let yOffset: CGFloat = isSplitMethods ? -280 : 0

            VStack(spacing: 0) {
                Color.clear.frame(height: topPadding)

                ZStack(alignment: .top) {
                    OnboardingVideoFrameView(
                        videoName: sharedMediaVideoName,
                        imageName: sharedMediaImageName
                    )
                    .padding(.horizontal, 24)
                    .scaleEffect(frameScale, anchor: .top)
                    .offset(y: yOffset)
                }
                .frame(maxWidth: .infinity)
                .frame(height: containerHeight, alignment: .top)
                .mask(sharedMediaFrameMask(fadesTop: isSplitMethods))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.spring(duration: 0.45, bounce: 0.08), value: step)
        .animation(.easeInOut(duration: 0.28), value: onboardingSplitMethod)
    }

    private func sharedMediaFrameMask(fadesTop: Bool) -> some View {
        VStack(spacing: 0) {
            if fadesTop {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
            }

            Color.black

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 130)
        }
    }

    private var sharedMediaVideoName: String? {
        switch step {
        case .scanReceipt:
            return "scan"
        case .settleBills:
            return "settle"
        case .welcome, .aboutYou, .splitMethods:
            return nil
        }
    }

    private var sharedMediaImageName: String? {
        guard step == .splitMethods else { return nil }

        switch onboardingSplitMethod {
        case .equal:
            return "equal"
        case .unequal:
            return "unequal"
        case .byParts:
            return "parts"
        case .byItem:
            return "items"
        }
    }

    // MARK: - Bottom Bar

    /// Progress-driven Liquid-Glass cluster that mirrors HomeView's
    /// `historyActionCluster`: the surfaces stay mounted while their
    /// positions, widths, and content fade between the merged and split
    /// states. Keeping the same glass surfaces alive is what makes the
    /// back button fuse into the single CTA when navigating backward.
    @ViewBuilder
    private var bottomBar: some View {
        let progress = bottomBarProgress

        GlassEffectContainer(spacing: interpolate(18, 8, progress: progress)) {
            switch step {
            case .welcome:
                EmptyView()

            case .aboutYou, .scanReceipt, .splitMethods, .settleBills:
                GeometryReader { proxy in
                    let buttonSize: CGFloat = 52
                    let spacing: CGFloat = 8
                    let mergedWidth = proxy.size.width
                    let splitCTAWidth = max(0, mergedWidth - buttonSize - spacing)
                    let mergedCenterX = mergedWidth / 2
                    let splitBackX = buttonSize / 2
                    let splitCTAX = buttonSize + spacing + (splitCTAWidth / 2)
                    let backX = interpolate(mergedCenterX, splitBackX, progress: progress)
                    let ctaX = interpolate(mergedCenterX, splitCTAX, progress: progress)
                    let ctaWidth = interpolate(mergedWidth, splitCTAWidth, progress: progress)

                    ZStack {
                        onboardingBackButton(progress: progress)
                            .frame(width: buttonSize, height: buttonSize)
                            .position(x: backX, y: proxy.size.height / 2)

                        onboardingCTAButton(progress: progress, width: ctaWidth)
                            .frame(width: ctaWidth, height: buttonSize)
                            .position(x: ctaX, y: proxy.size.height / 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 56)
            }
        }
    }

    private func onboardingCTAButton(progress: CGFloat, width: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if step == .aboutYou {
                if aboutYouCanContinue {
                    advance(to: .scanReceipt)
                } else {
                    // Tell About You to surface its inline hints.
                    aboutYouValidationTrigger += 1
                }
            } else if step == .scanReceipt {
                advance(to: .splitMethods)
            } else if step == .splitMethods {
                advance(to: .settleBills)
            } else {
                onClose()
            }
        } label: {
            ZStack {
                Text("See how to scan a receipt next")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(1 - Double(progress))
                    .blur(radius: 8 * progress)

                Text("See the split methods")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(step == .scanReceipt ? Double(progress) : 0)
                    .blur(radius: step == .scanReceipt ? 8 * (1 - progress) : 8)

                Text("See how to settle bills")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(step == .splitMethods ? 1 : 0)
                    .blur(radius: step == .splitMethods ? 0 : 8)

                Text("Start splitting!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(step == .settleBills ? 1 : 0)
                    .blur(radius: step == .settleBills ? 0 : 8)
            }
            .frame(width: width, height: 52)
            .contentShape(Capsule())
            .glassEffect(
                .clear.tint(.white.opacity(interpolate(aboutYouCanContinue ? 0.9 : 0.4, 0.9, progress: progress))).interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }

    private func onboardingBackButton(progress: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            advance(to: previousStep)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(Double(progress))
                .blur(radius: 8 * (1 - progress))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
                .glassEffect(
                    .clear.tint(.white.opacity(interpolate(0, 0.12, progress: progress))).interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .opacity(Double(progress))
        .allowsHitTesting(progress > 0.95)
        .accessibilityLabel("Back")
    }

    // MARK: - Page Indicator

    /// Index into `pageSteps` of the currently active pill. Welcome shows
    /// no indicator but we keep it at 0 so the entrance into About You
    /// reads as "first pill is active".
    private var currentStepIndex: Int {
        switch step {
        case .welcome, .aboutYou: return 0
        case .scanReceipt: return 1
        case .splitMethods: return 2
        case .settleBills: return 3
        }
    }

    /// Renders one stable set of pills. Each pill keeps the same view
    /// identity while its width, height, fill opacity, and centered text
    /// opacity/blur animate between active and inactive states.
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Self.pageSteps.indices, id: \.self) { idx in
                pill(at: idx)
            }
        }
    }

    private func pill(at idx: Int) -> some View {
        let isActive = idx == currentStepIndex
        let step = Self.pageSteps[idx]
        let width = isActive ? step.activeWidth : 20
        let height: CGFloat = isActive ? 28 : 6
        let textProgress: CGFloat = isActive ? 1 : 0

        return ZStack {
            Capsule()
                .fill(.white.opacity(isActive ? 0.9 : 0.4))
                .frame(width: width, height: height)

            Text(step.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .opacity(Double(textProgress))
                .blur(radius: 5 * (1 - textProgress))
                .frame(width: width, height: 28, alignment: .center)
        }
        .frame(width: width, height: 28)
    }

    // MARK: - Transitions

    /// Asymmetric push for the very first hop (welcome → About You).
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
    }

    /// Horizontal blur-fade used between later onboarding steps. The
    /// offset direction follows navigation: forward enters from the
    /// right, backward enters from the left.
    private var blurFadeTransition: AnyTransition {
        let insertionOffset: CGFloat = navigationDirection == .forward ? 60 : -60
        let removalOffset: CGFloat = navigationDirection == .forward ? -60 : 60

        return .asymmetric(
            insertion: .modifier(
                active: BlurFadeOffsetModifier(blur: 14, opacity: 0, offsetX: insertionOffset),
                identity: BlurFadeOffsetModifier(blur: 0, opacity: 1, offsetX: 0)
            ),
            removal: .modifier(
                active: BlurFadeOffsetModifier(blur: 14, opacity: 0, offsetX: removalOffset),
                identity: BlurFadeOffsetModifier(blur: 0, opacity: 1, offsetX: 0)
            )
        )
    }

    private func advance(to next: Step) {
        guard step != next else { return }
        // Dismiss any active keyboard before transitioning so the form
        // doesn't ride up mid-animation as the keyboard hides.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        withAnimation(.spring(duration: 0.45, bounce: 0.08)) {
            navigationDirection = navigationDirection(from: step, to: next)
            step = next
            bottomBarProgress = bottomBarProgress(for: next)
        }
    }

    private func navigationDirection(from current: Step, to next: Step) -> NavigationDirection {
        stepIndex(for: next) >= stepIndex(for: current) ? .forward : .backward
    }

    private func stepIndex(for step: Step) -> Int {
        switch step {
        case .welcome: return -1
        case .aboutYou: return 0
        case .scanReceipt: return 1
        case .splitMethods: return 2
        case .settleBills: return 3
        }
    }

    private func bottomBarProgress(for step: Step) -> CGFloat {
        Self.initialBottomBarProgress(for: step)
    }

    private static func initialBottomBarProgress(for step: Step) -> CGFloat {
        switch step {
        case .welcome, .aboutYou: return 0
        case .scanReceipt, .splitMethods, .settleBills: return 1
        }
    }

    private var previousStep: Step {
        switch step {
        case .welcome, .aboutYou:
            return .aboutYou
        case .scanReceipt:
            return .aboutYou
        case .splitMethods:
            return .scanReceipt
        case .settleBills:
            return .splitMethods
        }
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, progress: CGFloat) -> CGFloat {
        from + ((to - from) * progress)
    }
}

/// Blur + opacity + horizontal offset combined into one modifier so the
/// `.modifier(active:identity:)` transition can interpolate all three at
/// once. Each parameter animates independently between its active and
/// identity values during the transition.
private struct BlurFadeOffsetModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let offsetX: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(x: offsetX)
    }
}


#Preview {
    OnboardingFlowView(onClose: {})
}

#Preview("Demo - Scan Receipt") {
    OnboardingFlowView(onClose: {}, initialStep: .scanReceipt)
}

#Preview("Demo - Split Methods") {
    OnboardingFlowView(onClose: {}, initialStep: .splitMethods)
}

#Preview("Demo - Settle Bills") {
    OnboardingFlowView(onClose: {}, initialStep: .settleBills)
}
