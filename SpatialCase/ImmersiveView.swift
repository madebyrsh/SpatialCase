//
//  ImmersiveView.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/22/26.
//

import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @State private var objectTrackingManager = ObjectTrackingManager()
    
    var body: some View {
        RealityView { content in
            if let world = try? await Entity(named: "world") {
                content.add(world)
            }
        }
        .task {
            do {
                try await objectTrackingManager.startTracking()
                await processAnchorUpdates()
            } catch {
                print("Failed to Start object tracking: \(error)")
            }
        }
    }
    
    private func processAnchorUpdates() async {
        guard let objectTracking = objectTrackingManager.objectTracking else {
            return
        }
        for await update in objectTracking.anchorUpdates {
            switch update.event {
            case .added:
                print("Object anchor added")
                
            case .updated:
                print("Object anchor updated")
                
            case .removed:
                print("Object anchor removed")
            }
            
        }
    }
}

#Preview {
    ImmersiveView()
}
