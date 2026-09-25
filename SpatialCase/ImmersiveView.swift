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
    // MARK: - DIAGNOSTIC POSE MEASUREMENT
    @Environment(AppModel.self) private var appModel

    @State private var objectTrackingManager = ObjectTrackingManager()
    @State private var trackedEntity: Entity?
    @State private var runtimeRoot = Entity()

    // MARK: - STATIC ALIGNMENT TEST
    @State private var caseEntity: Entity?
    @State private var baselineCaseTransform: Transform?

    // MARK: - DIAGNOSTIC TEST

    // 이번 실험은 iPhone 한 대를 대상으로 합니다. 현재 anchor의 ID와 추적 상태를
    // 기억해서 이전 anchor의 늦은 이벤트를 구분하고, 상태가 바뀔 때만 로그를 남깁니다.
    @State private var diagnosticModel: Entity?
    @State private var trackedAnchorID: UUID?
    @State private var lastAddedAnchorID: UUID?
    @State private var lastIsTracked: Bool?

    var body: some View {
        RealityView { content in
            // 표시할 모델은 아래 task에서 선택합니다. RCP world 자체는 scene에 추가하지 않습니다.
            content.add(runtimeRoot)
        }
        .onChange(of: appModel.caseAlignment) {
            // 같은 Entity에 즉시 local transform만 적용합니다. 세션/anchor/hierarchy는 재생성하지 않습니다.
            applyCaseAlignment()
        }
        .task {
            let isDiagnostic = appModel.experimentMode == .diagnostic
            // ImmersiveSpace를 닫거나 오류가 발생하면 이번 진단 세션을 정리합니다.
            defer {
                if isDiagnostic { appModel.diagnosticPoseMeasurement.stopSession() }
                appModel.diagnosticPoseMeasurement.captureDevice = nil
                objectTrackingManager.session.stop()
                trackedEntity?.removeFromParent()
                trackedEntity = nil
                diagnosticModel = nil
                trackedAnchorID = nil
                lastAddedAnchorID = nil
                lastIsTracked = nil
                caseEntity = nil
                baselineCaseTransform = nil
            }

            do {
                if !isDiagnostic {
                    // baseline과 동일한 .reality의 Case 노드를 읽습니다. USDZ를 다시 회전시키지 않습니다.
                    let world = try await Entity(named: "world")
                    guard let model = world.findEntity(named: "iPhone17_ThinCase_Orange") else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    baselineCaseTransform = model.transform
                    model.removeFromParent(preservingWorldTransform: false)
                    caseEntity = model
                    applyCaseAlignment()
                } else {
                    guard let modelURL = Bundle.main.url(
                        forResource: "Diagnostic_iPhone17", withExtension: "usdz"
                    ) else {
                        throw CocoaError(.fileNoSuchFile)
                    }

                    // 모델 로딩을 마친 뒤 tracking을 시작하여 첫 added 이벤트부터 표시합니다.
                    diagnosticModel = try await DiagnosticReferenceModel.load(from: modelURL)
                }
                try Task.checkCancellation()
                try await objectTrackingManager.startTracking()
                try Task.checkCancellation()
                if isDiagnostic {
                    appModel.diagnosticPoseMeasurement.captureDevice = {
                        DiagnosticPoseCapture.device(provider: objectTrackingManager.diagnosticWorldTracking,
                                                     scene: runtimeRoot.scene)
                    }
                }
                await processAnchorUpdates()
            } catch is CancellationError {
                // ImmersiveSpace를 닫아서 취소된 경우는 실패가 아닙니다.
            } catch {
                print("[DIAGNOSTIC] Failed to start: \(error)")
            }
        }
    }

    // MARK: - DIAGNOSTIC TEST — ObjectAnchor → 일반 Entity

    private func processAnchorUpdates() async {
        guard let objectTracking = objectTrackingManager.objectTracking,
              let overlayModel = caseEntity ?? diagnosticModel else {
            return
        }

        for await update in objectTracking.anchorUpdates {
            if Task.isCancelled { break }
            let objectAnchor = update.anchor

            switch update.event {
            case .added:
                // MARK: - DIAGNOSTIC POSE MEASUREMENT
                recordDiagnosticUpdate(.added, anchor: objectAnchor, updateTime: update.timestamp)
                print("[DIAGNOSTIC] added id=\(objectAnchor.id) isTracked=\(objectAnchor.isTracked)")
                if let previousID = lastAddedAnchorID, previousID != objectAnchor.id {
                    print("[DIAGNOSTIC] anchor ID changed: \(previousID) → \(objectAnchor.id)")
                }
                lastAddedAnchorID = objectAnchor.id

                // 재검출 시 기존 표시를 제거하고 새 anchor를 따라갑니다.
                trackedEntity?.removeFromParent()
                let entity = Entity()
                entity.name = caseEntity == nil ? "DiagnosticTrackedAnchor" : "StaticAlignmentTrackedAnchor"
                entity.transform = Transform(matrix: objectAnchor.originFromAnchorTransform)
                entity.isEnabled = objectAnchor.isTracked
                runtimeRoot.addChild(entity)

                // 선택 모델의 local transform을 보존합니다. Diagnostic은 로드된 축 변환 그대로,
                // Case는 RCP 회전/scale과 선택한 static translation을 유지합니다.
                entity.addChild(overlayModel, preservingWorldTransform: false)
                trackedEntity = entity
                trackedAnchorID = objectAnchor.id
                lastIsTracked = objectAnchor.isTracked
                if appModel.experimentMode == .diagnostic {
                    logModelBounds(overlayModel, relativeTo: entity, anchor: objectAnchor)
                }

            case .updated:
                guard objectAnchor.id == trackedAnchorID, let trackedEntity else { continue }

                // MARK: - DIAGNOSTIC POSE MEASUREMENT
                recordDiagnosticUpdate(.updated, anchor: objectAnchor, updateTime: update.timestamp)

                if let previous = lastIsTracked, previous != objectAnchor.isTracked {
                    print("[DIAGNOSTIC] isTracked \(previous) → \(objectAnchor.isTracked) id=\(objectAnchor.id)")
                    lastIsTracked = objectAnchor.isTracked
                }

                // 추적을 잃으면 숨겨서 마지막 위치가 여전히 유효한 것처럼 보이지 않게 합니다.
                trackedEntity.isEnabled = objectAnchor.isTracked
                if objectAnchor.isTracked {
                    // ARKit pose를 직접 사용합니다. smoothing/interpolation/prediction은 없습니다.
                    trackedEntity.transform = Transform(matrix: objectAnchor.originFromAnchorTransform)
                }

            case .removed:
                // MARK: - DIAGNOSTIC POSE MEASUREMENT
                if appModel.experimentMode == .diagnostic {
                    appModel.diagnosticPoseMeasurement.receive(
                        .removed, anchorID: objectAnchor.id, isTracked: objectAnchor.isTracked,
                        transform: objectAnchor.originFromAnchorTransform
                    )
                }
                print("[DIAGNOSTIC] removed id=\(objectAnchor.id)")
                // 이전 anchor의 removed 이벤트가 새 anchor의 모델을 지우지 않도록 합니다.
                guard objectAnchor.id == trackedAnchorID else { continue }
                trackedEntity?.removeFromParent()
                trackedEntity = nil
                trackedAnchorID = nil
                lastIsTracked = nil
            }
        }
    }

    // MARK: - DIAGNOSTIC TEST — 3 pose를 읽기만 하며 Entity에는 적용하지 않습니다.
    private func recordDiagnosticUpdate(_ event: DiagnosticPoseMeasurement.Event,
                                        anchor: ObjectAnchor, updateTime: TimeInterval) {
        guard appModel.experimentMode == .diagnostic else { return }
        let measurement = appModel.diagnosticPoseMeasurement
        var comparison: DiagnosticPoseComparison?
        var failure: String?
        if measurement.isMeasuring && anchor.isTracked {
            do {
                comparison = try DiagnosticPoseCapture.object(anchor, updateTime: updateTime,
                                                             scene: runtimeRoot.scene,
                                                             deviceTime: measurement.latestDeviceTime)
            } catch { failure = String(describing: error) }
        }
        measurement.receive(event, anchorID: anchor.id, isTracked: anchor.isTracked,
                            transform: anchor.originFromAnchorTransform,
                            comparison: comparison, captureFailure: failure)
    }

    // MARK: - STATIC ALIGNMENT TEST
    private func applyCaseAlignment() {
        guard appModel.experimentMode == .staticAlignment,
              let caseEntity, let baselineCaseTransform else { return }
        caseEntity.transform = appModel.caseAlignment.transform(from: baselineCaseTransform)
    }

    private func logModelBounds(_ model: Entity, relativeTo entity: Entity, anchor: ObjectAnchor) {
        // added 때만 모델과 reference object의 경계를 같은 anchor 좌표계에서 비교합니다.
        // 이 값은 좌표계/단위 오류 확인용이며, 물리적 정합 정확도를 측정하는 값은 아닙니다.
        let bounds = model.visualBounds(relativeTo: entity)
        let referenceBounds = anchor.boundingBox
        print("[DIAGNOSTIC] model bounds (m) min=\(bounds.min) max=\(bounds.max)")
        print("[DIAGNOSTIC] anchor bounds (m) min=\(referenceBounds.min) max=\(referenceBounds.max)")
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}
