//
//  SplitMethodSelector.swift
//  break-even-ios
//
//  Created by Rudra Das on 2026-02-02.
//

import SwiftUI
import UIKit

// MARK: - PreferenceKey for measuring item widths

private struct ItemWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [NewSplitMethod: CGFloat] = [:]
    static func reduce(value: inout [NewSplitMethod: CGFloat], nextValue: () -> [NewSplitMethod: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct SplitMethodSelector: View {
    
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedMethod: NewSplitMethod
    @State private var scrolledMethodID: NewSplitMethod?
    @State private var itemWidths: [NewSplitMethod: CGFloat] = [:]
    
    // iOS 18+ scroll offset tracking (includes rubber-band)
    @State private var scrollOffset: CGFloat = 0
    
    private let horizontalPadding: CGFloat = 30
    private let itemSpacing: CGFloat = 60
    private let capsulePadding: CGFloat = 44
    
    private var lastItemWidth: CGFloat {
        itemWidths[NewSplitMethod.allCases.last!] ?? 60
    }
    
    private var selectedItemWidth: CGFloat {
        itemWidths[selectedMethod] ?? 60
    }
    
    /// The scroll offset where the last item snaps to the leading edge
    /// Calculated from: sum of all item widths except last + all spacings between items
    private var lastItemSnapOffset: CGFloat {
        let allCases = NewSplitMethod.allCases
        let itemsExceptLast = allCases.dropLast()
        
        // Sum widths of all items except the last one
        let widthsSum = itemsExceptLast.reduce(CGFloat(0)) { sum, method in
            sum + (itemWidths[method] ?? 60)
        }
        
        // Number of spacings = number of items - 1
        let spacingsCount = allCases.count - 1
        let spacingsSum = CGFloat(spacingsCount) * itemSpacing
        
        return widthsSum + spacingsSum
    }
    
    var body: some View {
        // Trailing margin = the scroll offset where last item snaps
        let trailingMargin = lastItemSnapOffset
        
        // Base layer defines the component size
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 64)
            .background(.background.secondary.opacity(0.6))
            .clipShape(.capsule)
            // ScrollView overlay - doesn't influence parent size
            .overlay {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: itemSpacing) {
                        ForEach(NewSplitMethod.allCases) { method in
                            Text(method.rawValue)
                                .foregroundStyle(Color.text.opacity(method == selectedMethod ? 0.2 : 0.6))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .id(method)
                                .background {
                                    GeometryReader { itemGeo in
                                        Color.clear
                                            .preference(key: ItemWidthPreferenceKey.self, value: [method: itemGeo.size.width])
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, horizontalPadding)
                }
                .scrollPosition(id: $scrolledMethodID, anchor: .leading)
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.trailing, trailingMargin, for: .scrollContent)
                .mask {
                    ZStack {
                        LinearGradient(colors: [.black, .black, .black, .black, .black, .black, .clear, .clear], startPoint: .leading, endPoint: .trailing)
                        
                        HStack {
                            Capsule()
                                .frame(width: selectedItemWidth + capsulePadding - 12, height: 34)
                                .animation(.smooth(duration: 0.25), value: selectedItemWidth)
                                .blur(radius: 5)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in }
                )
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }
                .onChange(of: scrolledMethodID) { _, newValue in
                    if let newMethod = newValue {
                        selectedMethod = newMethod
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onPreferenceChange(ItemWidthPreferenceKey.self) { widths in
                    itemWidths = widths
                }
            }
            // Glass capsule overlay
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: selectedItemWidth + capsulePadding, height: 52)
                    .glassEffect(.clear.interactive(true), in: .capsule)
                    .animation(.smooth(duration: 0.25), value: selectedItemWidth)
                    .padding(.horizontal, 8)
            }
            // Accent text overlay - uses GeometryReader to get parent width for clipping
            .overlay {
                GeometryReader { geo in
                    HStack(spacing: itemSpacing) {
                        ForEach(NewSplitMethod.allCases) { method in
                            Text(method.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .offset(x: -scrollOffset)
                    .foregroundStyle(colorScheme == .dark ? Color.text : Color.accent)
                    .allowsHitTesting(false)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .clipped()
                    .mask {
                        HStack {
                            Capsule()
                                .frame(width: selectedItemWidth + capsulePadding, height: 48)
                                .animation(.smooth(duration: 0.25), value: selectedItemWidth)
                                .blur(radius: 5)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        .onAppear {
            scrolledMethodID = selectedMethod
        }
    }
}

#Preview {
    @Previewable @State var method: NewSplitMethod = .equal
    SplitMethodSelector(selectedMethod: $method)
}
