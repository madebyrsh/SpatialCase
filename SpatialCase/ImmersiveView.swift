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
    @State private var trackedEntity: Entity?
    @State private var caseEntity: Entity?
    @State private var runtimeRoot = Entity()
    
    var body: some View {
        RealityView { content in
            if let world = try? await Entity(named: "world") {
                content.add(world)
                
                caseEntity = world.findEntity(named: "iPhone17_ThinCase_Orange")
            }
            content.add(runtimeRoot)
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
                let objectAnchor = update.anchor
                let entity = Entity()
                
                entity.transform = Transform(matrix: objectAnchor.originFromAnchorTransform)
                
                trackedEntity = entity
                runtimeRoot.addChild(entity)
                
                if let caseEntity {
                    entity.addChild(caseEntity)
                }
                
                print("Object anchor added")
                
            case .updated:
                let objectAnchor = update.anchor
                trackedEntity?.isEnabled = objectAnchor.isTracked
                
                if objectAnchor.isTracked {
                    trackedEntity?.transform = Transform(matrix: objectAnchor.originFromAnchorTransform)
                }
                
                print("Object anchor updated")
                
            case .removed:
                trackedEntity?.removeFromParent()
                trackedEntity = nil
                
                print("Object anchor removed")
            }
            
        }
    }
}

#Preview {
    ImmersiveView()
}
