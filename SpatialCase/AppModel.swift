//
//  AppModel.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/22/26.
//

import SwiftUI

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    
    enum CaseColor {
        case orange
        case red
        case yellow
        case blue
        case green
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var selectedCaseColor: CaseColor = .orange
}

