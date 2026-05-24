//
//  OnboardingVideoFrameView.swift
//  PayUp
//
//  Shared tilted video/placeholder card for the demo onboarding pages.
//

import AVKit
import CoreMotion
import SwiftUI
internal import Combine

struct OnboardingVideoFrameView: View {
    let videoName: String?
    let imageName: String?

    @StateObject private var gyro = OnboardingGyroTiltModel()

    init(videoName: String? = nil, imageName: String? = nil) {
        self.videoName = videoName
        self.imageName = imageName
    }

    var body: some View {
        GeometryReader { proxy in
            let maxHeight = min(proxy.size.height * 0.72, 600)
            let widthFromHeight = maxHeight * 9.0 / 19.5
            let width = min(proxy.size.width, widthFromHeight)
            let height = width * 19.5 / 9.0
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

            ZStack {
                shape.fill(.white.opacity(0.06))

                mediaContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(shape)
                    .id(mediaIdentity)
                    .transition(
                        .modifier(
                            active: OnboardingMediaBlurFadeModifier(blur: 14, opacity: 0),
                            identity: OnboardingMediaBlurFadeModifier(blur: 0, opacity: 1)
                        )
                    )
            }
            .overlay(
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
            .rotation3DEffect(
                .degrees(gyro.pitch),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.65
            )
            .rotation3DEffect(
                .degrees(gyro.roll),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: gyro.pitch)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: gyro.roll)
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.28), value: mediaIdentity)
            .onAppear { gyro.start() }
            .onDisappear { gyro.stop() }
        }
        .frame(maxHeight: .infinity)
    }

    private var videoURL: URL? {
        guard let videoName else { return nil }
        return Bundle.main.url(forResource: videoName, withExtension: "MP4")
            ?? Bundle.main.url(
                forResource: videoName,
                withExtension: "MP4",
                subdirectory: "Resources/Onboarding"
            )
    }

    private var mediaIdentity: String {
        if let videoName { return "video-\(videoName)" }
        if let imageName { return "image-\(imageName)" }
        return "placeholder"
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let url = videoURL {
            LoopingOnboardingVideoView(url: url)
        } else if let imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct OnboardingMediaBlurFadeModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private final class OnboardingGyroTiltModel: ObservableObject {
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let gravity = motion.gravity
            let nextPitch = Self.clamp(-gravity.y * 10, min: -8, max: 8)
            let nextRoll = Self.clamp(gravity.x * 10, min: -8, max: 8)

            self.pitch = nextPitch
            self.roll = nextRoll
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        pitch = 0
        roll = 0
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct LoopingOnboardingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingOnboardingVideoUIView {
        let view = LoopingOnboardingVideoUIView()
        view.configure(with: url)
        return view
    }

    func updateUIView(_ uiView: LoopingOnboardingVideoUIView, context: Context) {
        uiView.configure(with: url)
    }

    static func dismantleUIView(_ uiView: LoopingOnboardingVideoUIView, coordinator: ()) {
        uiView.stop()
    }
}

private final class LoopingOnboardingVideoUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func configure(with url: URL) {
        guard currentURL != url else {
            player?.play()
            return
        }

        currentURL = url
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none

        playerLayer.player = queuePlayer
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
        queuePlayer.play()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        looper = nil
        player = nil
        currentURL = nil
    }
}
