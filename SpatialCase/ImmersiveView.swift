//
//  ImmersiveView.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/22/26.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in
            if let world = try? await Entity(named: "world") {
                content.add(world)
            }
        }
    }
}

#Preview {
    ImmersiveView()
}
