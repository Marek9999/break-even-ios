//
//  InlineScanReceiptFlow.swift
//  PayUp
//
//  Created by Rudra Das on 2026-04-19.
//

import SwiftUI
import PhotosUI

/// Inline receipt scanner that lives in the home view's center area while the
/// top/bottom balance panels are collapsed. Mirrors the inline new-split flow
/// transition rather than presenting a full-screen camera sheet.
struct InlineScanReceiptFlow: View {
    @Bindable var viewModel: InlineScanReceiptViewModel
    let onScanComplete: (ReceiptScanResult) -> Void
    let onDismiss: () -> Void

    @Namespace private var bottomBarNamespace
    @Namespace private var receiptImageNamespace
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var editingItem: SplitItem?

    private var isAnalyzing: Bool {
        viewModel.phase == .analyzing
    }

    private var isConfirming: Bool {
        viewModel.phase == .confirming
    }

    private var scanErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.scanError != nil },
            set: { newValue in
                if !newValue { viewModel.scanError = nil }
            }
        )
    }

    private var captureButtonSize: CGFloat { 74 }
    private var sideButtonSize: CGFloat { 56 }

    var body: some View {
        rootContent
            .modifier(InlineScanPhotosPickerModifier(
                isPresented: $showPhotosPicker,
                selection: $selectedPhotoItem,
                onPicked: handlePickedPhoto
            ))
            .onChange(of: viewModel.capturedImage) { _, newImage in
                guard newImage != nil, viewModel.phase == .capturing else { return }
                startAnalysis()
            }
            .modifier(InlineScanErrorAlert(
                scanError: $viewModel.scanError,
                isPresented: scanErrorBinding,
                onRetry: retryAnalysis,
                onRetake: retakePhoto,
                onDismiss: onDismiss
            ))
            .modifier(InlineScanEditItemSheet(
                editingItem: $editingItem,
                onUpdate: updateItem,
                onDelete: removeItem
            ))
            .animation(.spring(duration: 0.42, bounce: 0.06), value: viewModel.phase)
    }
    
    @ViewBuilder
    private var rootContent: some View {
        if isConfirming, let result = viewModel.confirmedResult {
            confirmLayout(result: result)
        } else {
            captureLayout
        }
    }

    // MARK: - Capture Layout (capturing + analyzing)

    private var captureLayout: some View {
        VStack(spacing: 18) {
            viewfinder
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        return Color(white: 0.18)
            .overlay {
                if let captured = viewModel.capturedImage {
                    Color.clear
                        .overlay {
                            Image(uiImage: captured)
                                .resizable()
                                .scaledToFill()
                                .matchedGeometryEffect(
                                    id: "receiptImage",
                                    in: receiptImageNamespace,
                                    properties: .frame,
                                    isSource: true
                                )
                        }
                        .clipped()
                        .edgeCurveOverlay(isActive: isAnalyzing, showLabel: false)
                } else {
                    CameraPreviewView(
                        capturedImage: $viewModel.capturedImage,
                        captureTriggered: $viewModel.captureTriggered,
                        flashMode: $viewModel.flashMode
                    )
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .overlay(alignment: .topTrailing) {
                if !isAnalyzing && viewModel.capturedImage == nil {
                    flashButton
                        .padding(14)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.1), value: isAnalyzing)
            .animation(.spring(duration: 0.32, bounce: 0.1), value: viewModel.capturedImage != nil)
    }

    private var flashButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.flashMode = viewModel.flashMode.next
        } label: {
            Image(systemName: viewModel.flashMode.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Bottom Bar (Capture / Analyzing)

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                if isAnalyzing {
                    cancelAnalyzingButton
                        .glassEffectID("scan.dismiss", in: bottomBarNamespace)
                } else {
                    libraryButton
                        .glassEffectID("scan.library", in: bottomBarNamespace)

                    captureButton
                        .glassEffectID("scan.capture", in: bottomBarNamespace)

                    dismissButton
                        .glassEffectID("scan.dismiss", in: bottomBarNamespace)
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
            viewModel.captureTriggered = true
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
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: sideButtonSize, height: sideButtonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var cancelAnalyzingButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            cancelAnalysis()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: sideButtonSize, height: sideButtonSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Confirm Layout

    @ViewBuilder
    private func confirmLayout(result: ReceiptScanResult) -> some View {
        VStack(spacing: 0) {
            thumbnailWithRetake(image: result.image)
                .padding(.top, 8)
                .padding(.bottom, 4)

            itemsListSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .bottom) {
            continueBar
        }
    }

    // MARK: - Confirm: Thumbnail + Retake

    private var thumbnailHeight: CGFloat { 140 }
    private var thumbnailWidth: CGFloat { 100 }

    private func thumbnailWithRetake(image: UIImage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .bottom) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .matchedGeometryEffect(
                            id: "receiptImage",
                            in: receiptImageNamespace,
                            properties: .frame,
                            isSource: false
                        )
                } else {
                    Color(white: 0.18)
                }
            }
            .frame(width: thumbnailWidth, height: thumbnailHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            retakeButton
                .offset(y: 18)
        }
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private var retakeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            retakePhoto()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("Retake")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Confirm: Items List

    private var itemsListSection: some View {
        let items = viewModel.confirmedResult?.items ?? []
        return VStack(alignment: .leading, spacing: 8) {
            columnHeaders
                .padding(.horizontal, 36)
                .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(
                            item,
                            isFirst: index == 0,
                            isLast: index == items.count - 1
                        )
                        .padding(.bottom, index == items.count - 1 ? 0 : 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.top, 24)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Qty")
                .frame(width: 44, alignment: .center)

            Text("Price")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(Color.appText.opacity(0.6))
    }

    private func itemRow(_ item: SplitItem, isFirst: Bool, isLast: Bool) -> some View {
        let topRadius: CGFloat = isFirst ? 20 : 8
        let bottomRadius: CGFloat = isLast ? 20 : 8
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius
        )

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editingItem = item
        } label: {
            HStack(spacing: 0) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(item.quantity)")
                    .font(.subheadline)
                    .foregroundStyle(.text)
                    .frame(width: 44, alignment: .center)

                Text(item.totalPrice.asCurrency)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.text)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(.background.secondary.opacity(0.6))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm: Continue Bar

    private var continueBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            confirmAndContinue()
        } label: {
            HStack(spacing: 8) {
                Text("Add Friends")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .clipShape(Capsule())
            .glassEffect(.clear.tint(.white.opacity(0.9)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func handlePickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    viewModel.capturedImage = image
                }
            }
        }
    }

    private func startAnalysis() {
        viewModel.scanError = nil
        viewModel.phase = .analyzing
        viewModel.analysisTask?.cancel()
        viewModel.analysisTask = Task { await processReceipt() }
    }

    private func cancelAnalysis() {
        viewModel.analysisTask?.cancel()
        viewModel.analysisTask = nil
        viewModel.capturedImage = nil
        viewModel.phase = .capturing
    }

    private func retryAnalysis() {
        startAnalysis()
    }

    private func retakePhoto() {
        viewModel.scanError = nil
        viewModel.confirmedResult = nil
        viewModel.capturedImage = nil
        viewModel.phase = .capturing
    }

    private func confirmAndContinue() {
        guard var result = viewModel.confirmedResult else { return }
        // Use the items total as the source of truth so any edits made on the
        // confirmation screen flow through to the new-split + summary views.
        let itemsTotal = result.items.reduce(0) { $0 + $1.totalPrice }
        if itemsTotal > 0 {
            result.total = itemsTotal
        }
        onScanComplete(result)
    }

    private func updateItem(id: UUID, name: String, quantity: Int, amount: Double) {
        guard var result = viewModel.confirmedResult,
              let index = result.items.firstIndex(where: { $0.id == id }) else { return }
        result.items[index].name = name
        result.items[index].quantity = quantity
        result.items[index].amount = amount
        viewModel.confirmedResult = result
    }

    private func removeItem(id: UUID) {
        guard var result = viewModel.confirmedResult else { return }
        result.items.removeAll { $0.id == id }
        viewModel.confirmedResult = result
    }

    private func processReceipt() async {
        guard let image = viewModel.capturedImage else { return }

        if !NetworkMonitor.shared.isConnected {
            await MainActor.run {
                viewModel.phase = .capturing
                viewModel.scanError = .noInternet
            }
            return
        }

        do {
            let result = try await GeminiService.shared.analyzeReceipt(image: image)

            guard !Task.isCancelled else { return }

            if result.safeItems.isEmpty && (result.total ?? 0) == 0 {
                await MainActor.run {
                    viewModel.phase = .capturing
                    viewModel.scanError = .emptyReceipt
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

            await MainActor.run {
                viewModel.confirmedResult = scanResult
                viewModel.phase = .confirming
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.phase = .capturing
                viewModel.scanError = ReceiptScanError.from(error)
            }
        }
    }
}

// MARK: - Modifier Helpers
//
// These wrap the photos picker, error alert, and item-editing sheet so the
// SwiftUI body chain stays small. Without this, a single downstream type
// failure (e.g. SourceKit failing to resolve `ItemEditorSheet` while it
// reindexes) would fall back to "expression too complex" on the entire body.

private struct InlineScanPhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?
    let onPicked: (PhotosPickerItem?) -> Void
    
    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                matching: .images
            )
            .onChange(of: selection) { _, newItem in
                onPicked(newItem)
            }
    }
}

private struct InlineScanErrorAlert: ViewModifier {
    @Binding var scanError: ReceiptScanError?
    @Binding var isPresented: Bool
    let onRetry: () -> Void
    let onRetake: () -> Void
    let onDismiss: () -> Void
    
    func body(content: Content) -> some View {
        content
            .alert(
                scanError?.title ?? "",
                isPresented: $isPresented,
                presenting: scanError
            ) { error in
                Button(error.canRetryWithSameImage ? "Retry" : "Retake") {
                    if error.canRetryWithSameImage {
                        onRetry()
                    } else {
                        onRetake()
                    }
                }
                Button("Dismiss", role: .cancel) {
                    onDismiss()
                }
            } message: { error in
                Text(error.message)
            }
    }
}

private struct InlineScanEditItemSheet: ViewModifier {
    @Binding var editingItem: SplitItem?
    let onUpdate: (UUID, String, Int, Double) -> Void
    let onDelete: (UUID) -> Void
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(
                    initialItem: item,
                    currencyCode: "USD",
                    onSave: { name, quantity, amount in
                        onUpdate(item.id, name, quantity, amount)
                    },
                    onDelete: {
                        onDelete(item.id)
                    }
                )
            }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class InlineScanReceiptViewModel {
    enum Phase: Equatable {
        case capturing
        case analyzing
        case confirming
    }

    var phase: Phase = .capturing
    var capturedImage: UIImage?
    var captureTriggered: Bool = false
    var flashMode: CameraFlashMode = .off
    var scanError: ReceiptScanError?
    var analysisTask: Task<Void, Never>?
    var confirmedResult: ReceiptScanResult?
}

// MARK: - Previews

#if DEBUG
private enum InlineScanReceiptPreviewData {
    static let shortItems: [SplitItem] = [
        SplitItem(name: "Margherita Pizza", quantity: 2, amount: 14.99),
        SplitItem(name: "Caesar Salad", quantity: 1, amount: 9.50),
        SplitItem(name: "Garlic Bread", quantity: 1, amount: 6.00),
        SplitItem(name: "Tiramisu", quantity: 3, amount: 8.75)
    ]

    static let longItems: [SplitItem] = [
        SplitItem(name: "Truffle Fries", quantity: 1, amount: 12.00),
        SplitItem(name: "Margherita Pizza", quantity: 2, amount: 14.99),
        SplitItem(name: "Pepperoni Pizza", quantity: 1, amount: 16.50),
        SplitItem(name: "Caesar Salad", quantity: 1, amount: 9.50),
        SplitItem(name: "Garlic Bread", quantity: 1, amount: 6.00),
        SplitItem(name: "Bruschetta", quantity: 2, amount: 7.25),
        SplitItem(name: "Penne Arrabbiata", quantity: 1, amount: 13.75),
        SplitItem(name: "Spaghetti Bolognese", quantity: 1, amount: 15.00),
        SplitItem(name: "Tiramisu", quantity: 3, amount: 8.75),
        SplitItem(name: "Cannoli", quantity: 4, amount: 5.50),
        SplitItem(name: "Espresso", quantity: 4, amount: 3.50),
        SplitItem(name: "Sparkling Water", quantity: 2, amount: 4.00),
        SplitItem(name: "House Red Wine", quantity: 1, amount: 28.00),
        SplitItem(name: "Tax", quantity: 1, amount: 12.45),
        SplitItem(name: "Tip", quantity: 1, amount: 22.00)
    ]

    /// Generates a placeholder receipt image so the thumbnail in the confirm
    /// view has something to render in previews.
    static func sampleReceiptImage() -> UIImage {
        let size = CGSize(width: 300, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor(white: 0.45, alpha: 1).setStroke()
            for row in 0..<14 {
                let y = 32 + CGFloat(row) * 28
                let line = UIBezierPath()
                line.move(to: CGPoint(x: 24, y: y))
                line.addLine(to: CGPoint(x: size.width - 24, y: y))
                line.lineWidth = 2
                line.stroke()
            }
        }
    }

    @MainActor
    static func makeViewModel(items: [SplitItem]) -> InlineScanReceiptViewModel {
        let vm = InlineScanReceiptViewModel()
        vm.phase = .confirming
        vm.confirmedResult = ReceiptScanResult(
            title: "Sample Receipt",
            emoji: "🧾",
            total: items.reduce(0) { $0 + $1.totalPrice },
            items: items,
            date: nil,
            image: sampleReceiptImage()
        )
        return vm
    }
}

/// Wraps `InlineScanReceiptFlow` with a fake header bar so the preview matches
/// what the user sees inside `HomeView` when the scan is in the confirm phase.
private struct InlineScanReceiptConfirmPreviewHost: View {
    let items: [SplitItem]

    @State private var viewModel: InlineScanReceiptViewModel

    init(items: [SplitItem]) {
        self.items = items
        _viewModel = State(initialValue: InlineScanReceiptPreviewData.makeViewModel(items: items))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                fakeHeader
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                InlineScanReceiptFlow(
                    viewModel: viewModel,
                    onScanComplete: { _ in },
                    onDismiss: {}
                )
            }
        }
    }

    private var fakeHeader: some View {
        Text("Confirm Items")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(Color.appText)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
    }
}

#Preview("Confirm Items – 4 items") {
    InlineScanReceiptConfirmPreviewHost(items: InlineScanReceiptPreviewData.shortItems)
        .preferredColorScheme(.dark)
}

#Preview("Confirm Items – Long list (scrollable)") {
    InlineScanReceiptConfirmPreviewHost(items: InlineScanReceiptPreviewData.longItems)
        .preferredColorScheme(.dark)
}
#endif
