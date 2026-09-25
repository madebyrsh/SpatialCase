//
//  ContentView.swift
//  SpatialCase
//
//  Created by Shayne Ryu on 9/21/26.
//

import SwiftUI


struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        @Bindable var measurement = appModel.diagnosticPoseMeasurement
        VStack {

            // MARK: - STATIC ALIGNMENT TEST
            Picker("실험", selection: $model.experimentMode) {
                ForEach(SpatialCaseExperiment.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(appModel.immersiveSpaceState != .closed)

            if appModel.experimentMode == .staticAlignment {
                Text("Orange Case Static Alignment")
                    .font(.headline)
                ToggleImmersiveSpaceButton()
                Picker("Case alignment", selection: $model.caseAlignment) {
                    ForEach(CaseAlignmentCandidate.allCases) { candidate in
                        Text(candidate.rawValue).tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                Text("폰을 고정하고 외곽·모서리·카메라 홀·앞뒤 들뜸만 비교하세요.")
                    .font(.caption)
                Text("모든 후보는 같은 회전/크기를 사용합니다. 흔들림은 평가하지 않습니다.")
                    .font(.caption)
            } else {

                // MARK: - DIAGNOSTIC TEST
                Text("iPhone Reference Model Diagnostic")
                    .font(.headline)
                Text("실제 iPhone 17과 청록색 반투명 모델의 겹침을 확인하세요.")
                    .font(.subheadline)
            
                ToggleImmersiveSpaceButton()

                // MARK: - DIAGNOSTIC POSE MEASUREMENT
                Picker("측정 조건", selection: $measurement.selectedCondition) {
                    ForEach(DiagnosticCondition.allCases) { condition in
                        Text(condition.rawValue).tag(condition)
                    }
                }
                .pickerStyle(.menu)
                .disabled(measurement.isMeasuring)
                Text(measurement.selectedCondition == .headStill
                     ? "iPhone 고정 + 머리 최대한 고정"
                     : "iPhone 고정 + 머리를 천천히 좌우/앞뒤로 이동")
                    .font(.caption)
                Button("10초 pose 측정") {
                    appModel.diagnosticPoseMeasurement.start()
                }
                .disabled(!appModel.diagnosticPoseMeasurement.canStart)
                Text(appModel.diagnosticPoseMeasurement.status)
                    .font(.caption)
                if !appModel.diagnosticPoseMeasurement.isTracking {
                    Text("측정을 시작하려면 iPhone이 추적 중이어야 합니다.")
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
