//
//  SplitMethodSelector.swift
//  break-even-ios
//
//  Created by Rudra Das on 2026-02-02.
//

import SwiftUI

struct SplitMethodSelector: View {
    
    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                HStack(spacing: 60) {
                    Text("EQUAL")
                    Text("UNEQUAL")
                    Text("BY PARTS")
                    Text("BY ITEMS")
                }
                .padding(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background.secondary)
        .clipShape(Capsule())
    }
}

#Preview {
    SplitMethodSelector()
}
