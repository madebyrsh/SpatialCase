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

    // MARK: - DIAGNOSTIC POSE MEASUREMENT
    // 창의 시작 버튼과 ImmersiveView의 pose 수집기가 같은 측정 인스턴스를 공유합니다.
    let diagnosticPoseMeasurement = DiagnosticPoseMeasurement()

    // MARK: - STATIC ALIGNMENT TEST
    // 실험 종류는 ImmersiveSpace를 열기 전에만 선택합니다. 기존 diagnostic 기능은 유지합니다.
    var experimentMode: SpatialCaseExperiment = .staticAlignment
    var caseAlignment: CaseAlignmentCandidate = .baseline
    
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
}
