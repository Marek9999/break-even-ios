//
//  ReceiptCameraView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Flash Mode

enum CameraFlashMode: CaseIterable {
    case off, on, auto
    
    var next: CameraFlashMode {
        switch self {
        case .off: return .on
        case .on: return .auto
        case .auto: return .off
        }
    }
    
    var iconName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        }
    }
    
    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

// MARK: - Receipt Scan Error

enum ReceiptScanError: Identifiable {
    case noInternet
    case notAReceipt
    case serviceUnavailable
    case imageProcessingFailed
    case unreadableReceipt
    case emptyReceipt
    case timeout

    var id: String {
        switch self {
        case .noInternet: "noInternet"
        case .notAReceipt: "notAReceipt"
        case .serviceUnavailable: "serviceUnavailable"
        case .imageProcessingFailed: "imageProcessingFailed"
        case .unreadableReceipt: "unreadableReceipt"
        case .emptyReceipt: "emptyReceipt"
        case .timeout: "timeout"
        }
    }

    var icon: String {
        switch self {
        case .noInternet: "wifi.slash"
        case .notAReceipt: "doc.questionmark"
        case .serviceUnavailable: "server.rack"
        case .imageProcessingFailed: "photo.badge.exclamationmark"
        case .unreadableReceipt: "text.magnifyingglass"
        case .emptyReceipt: "list.bullet"
        case .timeout: "clock.badge.exclamationmark"
        }
    }

    var title: String {
        switch self {
        case .noInternet: "No Connection"
        case .notAReceipt: "Not a Receipt"
        case .serviceUnavailable: "Service Unavailable"
        case .imageProcessingFailed: "Image Error"
        case .unreadableReceipt: "Couldn't Read Receipt"
        case .emptyReceipt: "No Items Found"
        case .timeout: "Request Timed Out"
        }
    }

    var message: String {
        switch self {
        case .noInternet:
            "Check your internet connection and try again."
        case .notAReceipt:
            "The image doesn't appear to be a receipt. Please take a photo of a receipt."
        case .serviceUnavailable:
            "The analysis service is temporarily unavailable. Please try again shortly."
        case .imageProcessingFailed:
            "Could not process the photo. Try taking a clearer picture."
        case .unreadableReceipt:
            "The receipt could not be read. It may be blurry, too dark, or partially obscured."
        case .emptyReceipt:
            "The receipt was recognized but no line items were found."
        case .timeout:
            "The analysis took too long. Please check your connection and try again."
        }
    }

    /// Whether the primary action should retry with the same image (true) or retake a new photo (false).
    var canRetryWithSameImage: Bool {
        switch self {
        case .noInternet, .serviceUnavailable, .timeout: true
        case .notAReceipt, .imageProcessingFailed, .unreadableReceipt, .emptyReceipt: false
        }
    }

    static func from(_ error: Error) -> ReceiptScanError {
        if let geminiError = error as? GeminiError {
            switch geminiError {
            case .notAReceipt:
                return .notAReceipt
            case .imageConversionFailed:
                return .imageProcessingFailed
            case .noContent, .parsingFailed:
                return .unreadableReceipt
            case .invalidURL, .requestFailed:
                return .serviceUnavailable
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .noInternet
            case .timedOut:
                return .timeout
            case .cancelled:
                return .serviceUnavailable
            default:
                return .serviceUnavailable
            }
        }

        return .serviceUnavailable
    }
}

/// Camera view for scanning receipts
struct ReceiptCameraView: View {
    @Environment(\.dismiss) private var dismiss

    let onReceiptScanned: (ReceiptScanResult) -> Void

    @State private var capturedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var scanError: ReceiptScanError?
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captureTriggered = false
    @State private var flashMode: CameraFlashMode = .off
    @State private var analysisTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured = capturedImage {
                GeometryReader { geo in
                    Image(uiImage: captured)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                .edgeCurveOverlay(isActive: isAnalyzing)
            } else {
                CameraPreviewView(
                    capturedImage: $capturedImage,
                    captureTriggered: $captureTriggered,
                    flashMode: $flashMode
                )
                .ignoresSafeArea()
            }

            if !isAnalyzing && capturedImage == nil {
                VStack {
                    Spacer()
                    cameraControls
                }
            }

            if isAnalyzing && scanError == nil {
                cancelButton
            }

            if let error = scanError {
                errorOverlay(error: error)
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    capturedImage = image
                }
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            guard newImage != nil, !isAnalyzing else { return }
            startAnalysis()
        }
    }

    // MARK: - Camera Controls

    private var cameraControls: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Button {
                        showPhotosPicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.text)
                            .font(.headline)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)

                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        captureTriggered = true
                    } label: {
                        Text("Scan receipt")
                            .font(.headline)
                            .foregroundStyle(.text)
                    }
                    .frame(height: 48)
                    .padding(.horizontal, 24)
                    .glassEffect(.regular.tint(Color.accent).interactive())
                }

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.text)
                            .font(.headline)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)

                    Spacer()

                    Button {
                        withAnimation {
                            flashMode = flashMode.next
                        }
                    } label: {
                        Image(systemName: flashMode.iconName)
                            .foregroundStyle(.text)
                            .font(.headline)
                            .frame(width: 48, height: 48)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        VStack {
            Spacer()
            Button {
                cancelAnalysis()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.text)
                    .font(.headline)
                    .frame(width: 48, height: 48)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Error Overlay

    private func errorOverlay(error: ReceiptScanError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: error.icon)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))

            Text(error.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button {
                    if error.canRetryWithSameImage {
                        retryAnalysis()
                    } else {
                        retakePhoto()
                    }
                } label: {
                    Text(error.canRetryWithSameImage ? "Retry" : "Retake")
                        .font(.headline)
                        .foregroundStyle(.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .glassEffect(.regular.tint(Color.accent).interactive())

                Button {
                    dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.headline)
                        .foregroundStyle(.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .glassEffect(.regular.interactive())
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Analysis Control

    private func startAnalysis() {
        scanError = nil
        isAnalyzing = true
        analysisTask = Task { await processReceipt() }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        capturedImage = nil
    }

    private func retryAnalysis() {
        scanError = nil
        isAnalyzing = true
        analysisTask = Task { await processReceipt() }
    }

    private func retakePhoto() {
        scanError = nil
        capturedImage = nil
    }

    // MARK: - Process Receipt

    private func processReceipt() async {
        guard let image = capturedImage else { return }

        if !NetworkMonitor.shared.isConnected {
            await MainActor.run {
                isAnalyzing = false
                scanError = .noInternet
            }
            return
        }

        do {
            let result = try await GeminiService.shared.analyzeReceipt(image: image)

            guard !Task.isCancelled else { return }

            if result.safeItems.isEmpty && (result.total ?? 0) == 0 {
                await MainActor.run {
                    isAnalyzing = false
                    scanError = .emptyReceipt
                }
                return
            }

            var splitItems = result.safeItems.map { item in
                SplitItem(
                    name: item.name,
                    quantity: max(1, Int(item.quantity)),
                    amount: item.unitPrice
                )
            }
            if let tax = result.tax, tax > 0 {
                splitItems.append(SplitItem(name: "Tax", amount: tax))
            }
            if let tip = result.tip, tip > 0 {
                splitItems.append(SplitItem(name: "Tip", amount: tip))
            }
            
            let scanResult = ReceiptScanResult(
                title: result.merchantName ?? "Receipt",
                emoji: result.emoji,
                total: result.total ?? result.subtotal ?? 0,
                items: splitItems,
                date: result.date,
                image: image
            )

            #if DEBUG
            print("=== Receipt Scan Result Created ===")
            print("Title: \(scanResult.title), Total: \(scanResult.total), Items: \(scanResult.items.count)")
            print("===================================")
            #endif

            await MainActor.run {
                isAnalyzing = false
                onReceiptScanned(scanResult)
                dismiss()
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isAnalyzing = false
                scanError = ReceiptScanError.from(error)
            }
        }
    }
}

// MARK: - Receipt Scan Result

struct ReceiptScanResult: Identifiable {
    let id = UUID()
    var title: String
    var emoji: String?
    var total: Double
    var items: [SplitItem]
    var date: String?
    var image: UIImage?
}

// MARK: - Camera Preview View (UIKit wrapper)

struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var captureTriggered: Bool
    @Binding var flashMode: CameraFlashMode
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.flashMode = flashMode.avFlashMode
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.flashMode = flashMode.avFlashMode
        
        if captureTriggered {
            uiViewController.capturePhoto()
            DispatchQueue.main.async {
                captureTriggered = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
        
        func didCapturePhoto(_ image: UIImage) {
            parent.capturedImage = image
        }
    }
}

// MARK: - Camera View Controller

protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ image: UIImage)
}

class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?
    var flashMode: AVCaptureDevice.FlashMode = .off
    
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: backCamera) else {
            return
        }
        
        photoOutput = AVCapturePhotoOutput()
        
        if let captureSession = captureSession,
           captureSession.canAddInput(input),
           let photoOutput = photoOutput,
           captureSession.canAddOutput(photoOutput) {
            
            captureSession.addInput(input)
            captureSession.addOutput(photoOutput)
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = view.bounds
            
            if let previewLayer = previewLayer {
                view.layer.addSublayer(previewLayer)
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device,
           device.hasFlash {
            settings.flashMode = flashMode
        }
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }
    
    private func cropImageToPreviewBounds(_ image: UIImage) -> UIImage {
        guard let previewLayer = previewLayer,
              let cgImage = image.cgImage else { return image }
        
        let outputRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: outputRect.origin.x * width,
            y: outputRect.origin.y * height,
            width: outputRect.width * width,
            height: outputRect.height * height
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        let croppedImage = cropImageToPreviewBounds(image)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCapturePhoto(croppedImage)
        }
    }
}

// MARK: - Preview

#Preview {
    ReceiptCameraView { result in
        print("Scanned: \(result.title) - \(result.total)")
    }
}
