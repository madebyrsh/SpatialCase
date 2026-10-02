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
    @Environment(AppModel.self) private var appModel
    @State private var objectTrackingManager = ObjectTrackingManager()
    @State private var trackedEntity: Entity?
    @State private var caseEntity: Entity?
    @State private var caseContainer = Entity()
    @State private var runtimeRoot = Entity()
    
    var body: some View {
        RealityView { content in
            do {
                caseEntity = try await Entity(named: caseEntityName)
                print("✅ \(caseEntityName) loaded")
            } catch {
                print("❌ \(caseEntityName) load failed:", error)
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
    
                caseContainer.position.z = -0.006775
                entity.addChild(caseContainer)
                
                if let caseEntity {
                    caseContainer.addChild(caseEntity)
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
    
    private var caseEntityName: String {
        switch appModel.selectedCaseColor {
        case .orange:
            "CaseOrange"
        case .red:
            "CaseRed"
        case .yellow:
            "CaseYellow"
        case .blue:
            "CaseBlue"
        case .green:
            "CaseGreen"
        }
    }
}

#Preview {
    ImmersiveView()
}
