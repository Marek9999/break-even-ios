//
//  OnboardingProfileCameraView.swift
//  PayUp
//
//  Camera capture screen used during onboarding to take a profile photo.
//  Mirrors the visual language of InlineScanReceiptFlow (the camera that
//  opens from the home page's "scan receipt" button): rounded viewfinder,
//  white circular capture button, glass library / dismiss side buttons,
//  and a glass flash toggle in the top-trailing corner.
//

import SwiftUI
import PhotosUI

struct OnboardingProfileCameraView: View {
    @Environment(\.dismiss) private var dismiss

    let onCapture: (UIImage) -> Void

    @State private var capturedImage: UIImage?
    @State private var captureTriggered = false
    @State private var flashMode: CameraFlashMode = .off
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    @Namespace private var bottomBarNamespace

    private let captureButtonSize: CGFloat = 74
    private let sideButtonSize: CGFloat = 56

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                viewfinder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { capturedImage = image }
                }
            }
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        return Color(white: 0.18)
            .overlay {
                if let captured = capturedImage {
                    Image(uiImage: captured)
                        .resizable()
                        .scaledToFill()
                } else {
                    CameraPreviewView(
                        capturedImage: $capturedImage,
                        captureTriggered: $captureTriggered,
                        flashMode: $flashMode
                    )
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .overlay(alignment: .topTrailing) {
                if capturedImage == nil {
                    flashButton
                        .padding(14)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.1), value: capturedImage != nil)
    }

    private var flashButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flashMode = flashMode.next
        } label: {
            Image(systemName: flashMode.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                if capturedImage != nil {
                    retakeButton
                        .glassEffectID("profile.cam.retake", in: bottomBarNamespace)

                    confirmButton
                        .glassEffectID("profile.cam.confirm", in: bottomBarNamespace)

                    dismissButton
                        .glassEffectID("profile.cam.dismiss", in: bottomBarNamespace)
                } else {
                    libraryButton
                        .glassEffectID("profile.cam.library", in: bottomBarNamespace)

                    captureButton
                        .glassEffectID("profile.cam.capture", in: bottomBarNamespace)

                    dismissButton
                        .glassEffectID("profile.cam.dismiss", in: bottomBarNamespace)
                }
            }
            .frame(height: captureButtonSize)
        }
    }

    private var libraryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPhotosPicker = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: sideButtonSize, height: sideButtonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var captureButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            captureTriggered = true
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: captureButtonSize, height: captureButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var dismissButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: sideButtonSize, height: sideButtonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var retakeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            capturedImage = nil
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: sideButtonSize, height: sideButtonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var confirmButton: some View {
        Button {
            guard let image = capturedImage else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCapture(image)
            dismiss()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: captureButtonSize, height: captureButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.tint(.white.opacity(0.9)).interactive(), in: .circle)
    }
}
