// MARK: - DIAGNOSTIC POSE MEASUREMENT
// 합성 입력의 정답으로 계산/구간 분리만 검증합니다. 실기기 측정 결과가 아닙니다.
import Foundation
import simd

@main
struct DiagnosticPoseMeasurementChecks {
    static func close(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) {
        precondition(abs(actual - expected) < tolerance, "Expected \(expected), received \(actual)")
    }

    static func rotation(_ degrees: Double) -> simd_quatd {
        simd_quatd(angle: degrees * .pi / 180, axis: SIMD3(0, 0, 1))
    }

    static func sample(_ position: SIMD3<Double> = .zero, _ quaternion: simd_quatd = rotation(0)) -> DiagnosticPoseSample {
        DiagnosticPoseSample(time: 0, position: position, rotation: quaternion)
    }

    @MainActor
    static func main() async throws {
        let constant = DiagnosticPoseStatistics(samples: [sample(), sample()])
        close(constant.positionRMS, 0)
        close(constant.rotationRMSDegrees, 0)

        let positions = DiagnosticPoseStatistics(samples: [
            sample(SIMD3(-0.001, -0.002, -0.002)), sample(SIMD3(0.001, 0.002, 0.002))
        ])
        close(positions.positionRMS * 1000, 3)
        close(positions.positionMaximum * 1000, 3)
        precondition(positions.meanPosition == .zero)
        precondition(positions.positionRange == SIMD3(0.002, 0.004, 0.004))

        let quarterTurn = DiagnosticPoseStatistics(samples: [sample(.zero, rotation(0)), sample(.zero, rotation(90))])
        close(quarterTurn.rotationRMSDegrees, 45)
        close(quarterTurn.rotationMaximumDegrees, 45)

        let wrap = DiagnosticPoseStatistics(samples: [sample(.zero, rotation(179)), sample(.zero, rotation(-179))])
        close(wrap.rotationRMSDegrees, 1)
        close(wrap.rotationMaximumDegrees, 1)

        let tiny = DiagnosticPoseStatistics(samples: [sample(.zero, rotation(-0.000001)), sample(.zero, rotation(0.000001))])
        close(tiny.rotationRMSDegrees, 0.000001, tolerance: 1e-12)

        let q = simd_quatd(angle: 0.723, axis: simd_normalize(SIMD3(1, 2, 3)))
        let signs = DiagnosticPoseStatistics(samples: [sample(.zero, q), sample(.zero, simd_quatd(vector: -q.vector))])
        close(signs.rotationMaximumDegrees, 0)

        // 첫 quaternion과 직교하는 orientation이 다수인 경우에도 평균이 올바른지 검증합니다.
        let dominant = DiagnosticPoseStatistics(samples: [sample(), sample(.zero, rotation(180)), sample(.zero, rotation(180))])
        close(DiagnosticPoseStatistics.angularDistanceDegrees(dominant.meanRotation, rotation(180)), 0)
        close(dominant.rotationRMSDegrees, sqrt(180 * 180 / 3))
        close(dominant.rotationMaximumDegrees, 180)

        var matrix = simd_float4x4(simd_quatf(angle: .pi / 4, axis: SIMD3(0, 0, 1)))
        matrix.columns.3 = SIMD4(1, 2, 3, 1)
        let extracted = DiagnosticPoseSample(time: 0, transform: matrix)
        precondition(extracted.position == SIMD3(1, 2, 3))
        close(DiagnosticPoseStatistics.angularDistanceDegrees(extracted.rotation, rotation(45)), 0, tolerance: 0.00001)

        // 공통 origin에서 두 pose가 함께 이동/회전해도 C의 상대값에는 섞이지 않아야 합니다.
        let identity = matrix_identity_float4x4
        var offset = identity
        offset.columns.3.x = 0.002
        func paired(_ base: simd_float4x4, _ correction: simd_float4x4) -> DiagnosticPoseComparison {
            DiagnosticPoseComparison(current: base, rendered: base * correction, metric: base,
                                     objectTime: 9.9, updateTime: 9.91, receiptTime: 10,
                                     readDuration: 0.0002, deviceTime: 9.98)
        }
        let pairs = [paired(identity, offset), paired(matrix, offset)]
        close(pairs[0].relative.position.x, 0.002, tolerance: 1e-8)
        close(DiagnosticPoseStatistics(samples: pairs.map(\.relative)).positionRMS, 0, tolerance: 1e-6)
        precondition(DiagnosticPoseStatistics(samples: pairs.map(\.metric)).positionRMS > 1)
        var opposite = offset; opposite.columns.3.x = -0.002
        close(DiagnosticPoseStatistics(samples: [paired(identity, offset).relative, paired(identity, opposite).relative]).positionRMS, 0.002, tolerance: 1e-8)
        let pairedSummary = DiagnosticComparisonSummary.object([paired(identity, offset), paired(identity, offset)]).joined(separator: "\n")
        precondition(pairedSummary.contains("Position difference RMS / max: 2.000000 / 2.000000 mm"))
        precondition(pairedSummary.contains("80.000000")) // Device timestamp − Object timestamp = +80ms
        precondition(pairedSummary.contains("20.000000")) // receipt − sampled device timestamp = 20ms
        precondition(DiagnosticComparisonSummary.statistics("tiny", samples: [sample(.zero, rotation(-0.000001)), sample(.zero, rotation(0.000001))]).joined().contains("0.000001°"))

        let deviceID = UUID(), nextDeviceID = UUID()
        let deviceSummary = DiagnosticComparisonSummary.device([
            DiagnosticDeviceReading(queryTime: 1, returnedTime: 1, anchorID: deviceID, pose: sample(), issue: nil),
            DiagnosticDeviceReading(queryTime: 2, returnedTime: nil, anchorID: nil, pose: nil, issue: "query returned nil"),
            DiagnosticDeviceReading(queryTime: 3, returnedTime: 3, anchorID: deviceID, pose: sample(SIMD3(100, 0, 0)), issue: nil),
            DiagnosticDeviceReading(queryTime: 4, returnedTime: 4, anchorID: nextDeviceID, pose: sample(SIMD3(-100, 0, 0)), issue: nil)
        ]).joined(separator: "\n")
        precondition(deviceSummary.contains("valid samples: 3; runs: 3"))
        precondition(!deviceSummary.contains("Position RMS: 100000")) // invalid gap/ID replacement stay separate

        var time = 100.0
        var summaries: [String] = []
        let measurement = DiagnosticPoseMeasurement(now: { time }, emitSummary: { summaries.append($0) })
        let a = UUID(), b = UUID(), c = UUID()
        let pose = matrix_identity_float4x4
        func send(_ event: DiagnosticPoseMeasurement.Event, _ id: UUID, _ tracked: Bool, _ positionX: Float = 0) {
            var input = pose
            input.columns.3.x = positionX
            measurement.receive(event, anchorID: id, isTracked: tracked, transform: input)
        }

        measurement.start()
        precondition(!measurement.isMeasuring) // 인식 전 시작 불가
        send(.added, a, true)
        measurement.selectedCondition = .headMoving
        measurement.start()
        measurement.selectedCondition = .headStill // UI는 disabled지만 조건 snapshot 자체도 검증합니다.
        measurement.start() // 중복 버튼 호출은 현재 측정을 초기화하지 않음
        time = 100.1; send(.updated, a, true)
        time = 100.2; send(.updated, a, true)
        time = 101; send(.updated, a, false, 100)
        time = 101.1; send(.updated, a, false, -100)
        time = 102; send(.updated, a, true, 1) // 동일 ID라도 새 구간
        time = 103; send(.added, b, true, 2) // ID 교체: 새 구간
        time = 103.1; send(.removed, a, false) // 이전 ID의 늦은 이벤트 무시
        time = 104; send(.updated, b, false)
        time = 104.1; send(.removed, b, false) // loss 중복 계산 금지
        time = 105; send(.added, c, false)
        time = 106; send(.updated, c, true)
        time = 107; send(.added, c, true) // 같은 ID라도 added는 새 구간
        time = 110; send(.updated, c, true) // 정확한 deadline의 표본은 제외

        let result = measurement.lastResult!
        close(result.duration, 10)
        precondition(result.sampleCount == 6)
        precondition(result.condition == .headMoving && result.summary.contains("Condition: B — Head Moving"))
        precondition(result.segments.map { $0.samples.count } == [2, 1, 1, 1, 1])
        precondition(result.losses == 2 && result.reacquisitions == 4 && result.anchorIDChanges == 2)
        precondition(result.segments.map(\.anchorID) == [a, a, b, c, c])
        // 재획득 시 1m/2m 점프와 false pose의 ±100m를 구간 내 흔들림에 섞지 않습니다.
        for segment in result.segments {
            close(DiagnosticPoseStatistics(samples: segment.samples).positionRMS, 0)
        }
        precondition(summaries.count == 1)
        time = 111; send(.updated, c, true)
        precondition(summaries.count == 1 && measurement.lastResult!.sampleCount == 6)

        // 재측정이 가능하고, tracked 상태에서 바로 removed가 오면 loss를 세는지 검증합니다.
        measurement.start()
        time = 111.1; send(.updated, c, true)
        time = 112; send(.removed, c, false)
        time = 114; measurement.stopSession()
        close(measurement.lastResult!.duration, 3)
        precondition(measurement.lastResult!.losses == 1)
        precondition(measurement.lastResult!.sampleCount == 1)
        precondition(measurement.lastResult!.reason.contains("interrupted"))
        precondition(measurement.lastResult!.summary.contains("Condition: A — Head Still"))
        precondition(!measurement.canStart && summaries.count == 2)

        let comparisonMeasurement = DiagnosticPoseMeasurement(now: { time }, emitSummary: { _ in })
        comparisonMeasurement.receive(.added, anchorID: a, isTracked: true, transform: pose)
        comparisonMeasurement.start()
        comparisonMeasurement.receive(.updated, anchorID: a, isTracked: true, transform: pose, comparison: pairs[0])
        comparisonMeasurement.receive(.updated, anchorID: a, isTracked: true, transform: pose, captureFailure: "unresolved scene")
        comparisonMeasurement.receive(.updated, anchorID: a, isTracked: false, transform: pose)
        comparisonMeasurement.receive(.updated, anchorID: a, isTracked: true, transform: pose, comparison: pairs[1])
        comparisonMeasurement.stopSession()
        precondition(comparisonMeasurement.lastResult!.segments.map { $0.comparisons.count } == [1, 1])
        precondition(comparisonMeasurement.lastResult!.sampleCount == 3) // 변환 실패여도 기존 raw 표본은 보존
        precondition(comparisonMeasurement.lastResult!.segments[0].captureFailures["unresolved scene"] == 1)

        // 이벤트가 없어도 독립 timer가 종료해야 합니다. 가짜 시계를 마감 이후로 이동해 검증합니다.
        let noUpdates = DiagnosticPoseMeasurement(now: { time }, emitSummary: { summaries.append($0) })
        noUpdates.receive(.added, anchorID: a, isTracked: true, transform: pose)
        noUpdates.start()
        time += 10
        // OS의 timer coalescing/스케줄링 지연은 수집 창과 별개입니다.
        // 작은 고정 여유 시간으로 테스트를 불안정하게 만들지 않고 완료를 최대 15초 기다립니다.
        let timeout = ContinuousClock.now.advanced(by: .seconds(15))
        while noUpdates.isMeasuring && ContinuousClock.now < timeout {
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(noUpdates.lastResult?.sampleCount == 0)
        precondition(noUpdates.lastResult?.duration == 10)
        precondition(summaries.count == 3)

        // Object update가 없어도 보조 device stream은 수집됩니다. 종료 뒤에는 수집을 멈춥니다.
        let deviceOnly = DiagnosticPoseMeasurement(emitSummary: { _ in })
        var queries = 0
        deviceOnly.captureDevice = {
            queries += 1
            return DiagnosticDeviceReading(queryTime: Double(queries), returnedTime: Double(queries),
                                           anchorID: deviceID, pose: sample(), issue: nil)
        }
        deviceOnly.receive(.added, anchorID: a, isTracked: true, transform: pose)
        deviceOnly.start()
        try await Task.sleep(for: .milliseconds(150))
        deviceOnly.stopSession()
        precondition(queries > 0 && deviceOnly.lastResult!.sampleCount == 0)
        precondition(deviceOnly.lastResult!.deviceReadings.count == queries)
        let stoppedQueries = queries
        try await Task.sleep(for: .milliseconds(100))
        precondition(queries == stoppedQueries)
        print("PASS: existing pose/quaternion/segment/deadline checks; paired relative transforms; fixed API offset; six-decimal rotation; timestamps; A/B snapshot; device gaps, IDs and independent sampling")
    }
}
