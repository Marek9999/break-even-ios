//
//  ReceiptCameraView.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI
import AVFoundation
import PhotosUI

/// Camera view for scanning receipts
struct ReceiptCameraView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onReceiptScanned: (ReceiptScanResult) -> Void
    
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captureTriggered = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview
                if capturedImage == nil {
                    CameraPreviewView(
                        capturedImage: $capturedImage,
                        captureTriggered: $captureTriggered
                    )
                    .ignoresSafeArea()
                } else {
                    // Show captured image
                    Image(uiImage: capturedImage!)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
                
                // Overlay UI
                VStack {
                    Spacer()
                    
                    if isProcessing {
                        processingOverlay
                    } else if capturedImage != nil {
                        capturedImageControls
                    } else {
                        cameraControls
                    }
                }
                
                // Error overlay
                if let error = errorMessage {
                    errorOverlay(message: error)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Scan Receipt")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                    }
                }
            }
        }
    }
    
    // MARK: - Camera Controls
    
    private var cameraControls: some View {
        HStack(spacing: 40) {
            // Photo library button
            Button {
                showPhotosPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            
            // Capture button
            Button {
                captureTriggered = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            }
            
            // Flash toggle (placeholder)
            Button {
                // Toggle flash
            } label: {
                Image(systemName: "bolt.slash.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Captured Image Controls
    
    private var capturedImageControls: some View {
        HStack(spacing: 24) {
            // Retake button
            Button {
                withAnimation {
                    capturedImage = nil
                    errorMessage = nil
                }
            } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            
            // Use photo button
            Button {
                Task {
                    await processReceipt()
                }
            } label: {
                Label("Use Photo", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.5)
            
            Text("Analyzing receipt...")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.6))
    }
    
    // MARK: - Error Overlay
    
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            Button {
                errorMessage = nil
                capturedImage = nil
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8))
    }
    
    // MARK: - Process Receipt
    
    private func processReceipt() async {
        guard let image = capturedImage else { return }
        
        isProcessing = true
        errorMessage = nil
        
        do {
            let result = try await GeminiService.shared.analyzeReceipt(image: image)
            
            // Convert to our format using safe accessor for optional items
            let scanResult = ReceiptScanResult(
                title: result.merchantName ?? "Receipt",
                total: result.total ?? result.subtotal ?? 0,
                items: result.safeItems.map { item in
                    SplitItem(
                        name: item.name,
                        amount: item.unitPrice * item.quantity
                    )
                },
                date: result.date,
                image: image
            )
            
            // Debug logging
            print("=== Receipt Scan Result Created ===")
            print("Title: \(scanResult.title)")
            print("Total: \(scanResult.total)")
            print("Items: \(scanResult.items.count)")
            print("Date: \(scanResult.date ?? "nil")")
            print("===================================")
            
            await MainActor.run {
                isProcessing = false
                onReceiptScanned(scanResult)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Receipt Scan Result

struct ReceiptScanResult: Identifiable {
    let id = UUID()
    var title: String
    var total: Double
    var items: [SplitItem]
    var date: String?
    var image: UIImage?
}

// MARK: - Camera Preview View (UIKit wrapper)

struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var captureTriggered: Bool
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // When captureTriggered becomes true, capture the photo
        if captureTriggered {
            uiViewController.capturePhoto()
            // Reset the trigger on the next run loop
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
    
    /// Public method to trigger photo capture from SwiftUI
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
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
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCapturePhoto(image)
        }
    }
}

// MARK: - Preview

#Preview {
    ReceiptCameraView { result in
        print("Scanned: \(result.title) - \(result.total)")
    }
}
