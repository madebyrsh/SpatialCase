import ARKit
import QuartzCore
import RealityKit
import Spatial

// MARK: - DIAGNOSTIC TEST — visionOS 27 API 읽기 전용 경로

@MainActor
enum DiagnosticPoseCapture {
    enum CaptureError: Error { case sceneUnavailable, invalidTransform }

    static func object(_ anchor: ObjectAnchor, updateTime: TimeInterval,
                       scene: RealityKit.Scene?, deviceTime: TimeInterval?) throws -> DiagnosticPoseComparison {
        let receipt = CACurrentMediaTime()
        guard let scene else { throw CaptureError.sceneUnavailable }
        // 같은 anchor 값에서 await 없이 연속으로 읽습니다. 원자적 snapshot이라고 주장하지 않습니다.
        let current = anchor.originFromAnchorTransform
        // ARKitCoordinateSpace의 ancestor는 WorldReferenceCoordinateSpace입니다.
        // ancestor 행렬을 raw origin 행렬과 곧바로 비교하지 않고 Spatial이 scene까지 변환하게 합니다.
        // immersive scene은 ARKit world origin이므로 기존 current pose와 기준/단위가 일치합니다.
        let rendered: ProjectiveTransform3DFloat = try scene.transform(from: anchor.coordinateSpace(correction: .rendered))
        let metric: ProjectiveTransform3DFloat = try scene.transform(from: anchor.coordinateSpace(correction: .none))
        try validate(current)
        try validate(rendered.matrix)
        try validate(metric.matrix)
        return DiagnosticPoseComparison(current: current, rendered: rendered.matrix, metric: metric.matrix,
                                        objectTime: anchor.timestamp, updateTime: updateTime, receiptTime: receipt,
                                        readDuration: CACurrentMediaTime() - receipt, deviceTime: deviceTime)
    }

    static func device(provider: WorldTrackingProvider?, scene: RealityKit.Scene?) -> DiagnosticDeviceReading {
        // 과거 ObjectAnchor timestamp로 조회하지 않습니다. API의 current/future query 중 current만 사용합니다.
        let queryTime = CACurrentMediaTime()
        guard let provider, provider.state == .running else {
            return DiagnosticDeviceReading(queryTime: queryTime, returnedTime: nil, anchorID: nil, pose: nil, issue: "provider not running")
        }
        guard let anchor = provider.queryDeviceAnchor(atTimestamp: queryTime) else {
            return DiagnosticDeviceReading(queryTime: queryTime, returnedTime: nil, anchorID: nil, pose: nil, issue: "query returned nil")
        }
        guard anchor.trackingState == .tracked else {
            return DiagnosticDeviceReading(queryTime: queryTime, returnedTime: anchor.timestamp, anchorID: anchor.id, pose: nil, issue: "tracking state \(anchor.trackingState)")
        }
        do {
            guard let scene else { throw CaptureError.sceneUnavailable }
            let pose: ProjectiveTransform3DFloat = try scene.transform(from: anchor.coordinateSpace(correction: .none))
            try validate(pose.matrix)
            return DiagnosticDeviceReading(queryTime: queryTime, returnedTime: anchor.timestamp, anchorID: anchor.id,
                                           pose: DiagnosticPoseSample(time: anchor.timestamp, transform: pose.matrix), issue: nil)
        } catch {
            return DiagnosticDeviceReading(queryTime: queryTime, returnedTime: anchor.timestamp, anchorID: anchor.id, pose: nil, issue: "conversion failed: \(error)")
        }
    }

    private static func validate(_ matrix: simd_float4x4) throws {
        // 변환 실패를 identity로 대체하지 않습니다. scale/shear/비유한 값은 비교에서 제외합니다.
        for column in 0..<4 {
            for row in 0..<4 where !matrix[column][row].isFinite { throw CaptureError.invalidTransform }
        }
        let r = simd_float3x3(columns: (SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                                     SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                                     SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)))
        let gram = simd_transpose(r) * r
        for column in 0..<3 {
            for row in 0..<3 where abs(gram[column][row] - (column == row ? 1 : 0)) > 0.001 {
                throw CaptureError.invalidTransform
            }
        }
        guard abs(simd_determinant(r) - 1) < 0.001,
              abs(matrix.columns.0.w) < 0.001, abs(matrix.columns.1.w) < 0.001,
              abs(matrix.columns.2.w) < 0.001, abs(matrix.columns.3.w - 1) < 0.001 else {
            throw CaptureError.invalidTransform
        }
    }
}
