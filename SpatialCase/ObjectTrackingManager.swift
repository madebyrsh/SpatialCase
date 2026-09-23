//
//  ObjectTrackingManager.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/23/26.
//

import Foundation
import ARKit
import RealityKit

@MainActor
final class ObjectTrackingManager {
    let session = ARKitSession()
    var objectTracking : ObjectTrackingProvider?
    
    func startTracking() async throws {
        var configuration = ReferenceObject.Configuration()
        configuration.highFrameRateTrackingEnabled = true
        
        
        let referenceObject = try await ReferenceObject(
            named: "Apple iPhone 17",
            from: Bundle.main,
            configuration: configuration
        )
        
        let objectTracking = ObjectTrackingProvider(referenceObjects: [referenceObject])
        self.objectTracking = objectTracking
        
        try await session.run([objectTracking])
    }
}
