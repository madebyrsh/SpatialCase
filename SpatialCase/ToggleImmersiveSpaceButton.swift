//
//  ToggleImmersiveSpaceButtonView.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/22/26.
//

import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dissmissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Button {
            Task {@MainActor in
                switch appModel.immersiveSpaceState {
                case .open:
                    appModel.immersiveSpaceState = .inTransition
                    await dissmissImmersiveSpace()
                    
                case .closed:
                    appModel.immersiveSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                    case .opened:
                        break
                        
                    case .userCancelled, .error:
                        fallthrough
                        
                    @unknown default:
                        appModel.immersiveSpaceState = .closed
                    }
                    
                case .inTransition:
                    break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "추적 중지" : "추적 시작")
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}

