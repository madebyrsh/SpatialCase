import Foundation
import Observation
import simd

// MARK: - DIAGNOSTIC POSE MEASUREMENT

/// 표시 동작을 바꾸지 않고, 전달받은 ObjectAnchor pose만 10초 동안 기록하는 보조 타입입니다.
@MainActor
@Observable
final class DiagnosticPoseMeasurement {
    enum Event { case added, updated, removed }

    struct Segment {
        let anchorID: UUID
        var samples: [DiagnosticPoseSample] = []
        var comparisons: [DiagnosticPoseComparison] = []
        var captureFailures: [String: Int] = [:]
    }

    struct Result {
        let duration: TimeInterval
        let reason: String
        let segments: [Segment]
        let losses: Int
        let reacquisitions: Int
        let anchorIDChanges: Int
        let condition: DiagnosticCondition
        let deviceReadings: [DiagnosticDeviceReading]

        var sampleCount: Int { segments.reduce(0) { $0 + $1.samples.count } }

        var summary: String {
            var lines = [
                "[DIAGNOSTIC POSE SUMMARY]",
                "Condition: \(condition.rawValue)",
                "Duration: \(format(duration)) s (\(reason); monotonic app receipt time)",
                "Samples: \(sampleCount)",
                "Segments: \(segments.count) — statistics are separate; no cross-segment deviations",
                "Tracking — Losses: \(losses), Reacquisitions: \(reacquisitions), Anchor ID changes: \(anchorIDChanges)"
            ]
            for (index, segment) in segments.enumerated() {
                let samples = segment.samples
                let stats = DiagnosticPoseStatistics(samples: samples)
                let span = samples.last!.time - samples.first!.time
                lines += [
                    "", "Segment \(index + 1) — anchor \(segment.anchorID)",
                    "Samples: \(samples.count), sample span: \(format(span)) s",
                    "Current pose — originFromAnchorTransform (all original samples)",
                    "Position (origin coordinate system; deviation from segment mean)",
                    "Mean: \(vector(stats.meanPosition * 1000)) mm",
                    "RMS deviation: \(format(stats.positionRMS * 1000)) mm",
                    "Maximum deviation: \(format(stats.positionMaximum * 1000)) mm",
                    "X range: \(format(stats.positionRange.x * 1000)) mm",
                    "Y range: \(format(stats.positionRange.y * 1000)) mm",
                    "Z range: \(format(stats.positionRange.z * 1000)) mm",
                    "Rotation (shortest angle from segment Markley mean)",
                    "RMS deviation: \(DiagnosticComparisonSummary.number(stats.rotationRMSDegrees))°",
                    "Maximum deviation: \(DiagnosticComparisonSummary.number(stats.rotationMaximumDegrees))°"
                ]
                if samples.count < 2 {
                    lines.append("Insufficient samples: a single sample cannot establish stability.")
                }
                for key in segment.captureFailures.keys.sorted() {
                    lines.append("Comparison unavailable — \(key): \(segment.captureFailures[key]!)")
                }
                lines += DiagnosticComparisonSummary.object(segment.comparisons)
            }
            if sampleCount == 0 { lines.append("No tracked pose samples in this measurement window.") }
            lines += DiagnosticComparisonSummary.device(deviceReadings)
            return lines.joined(separator: "\n")
        }

        private func format(_ value: Double) -> String { String(format: "%.3f", value) }
        private func vector(_ value: SIMD3<Double>) -> String {
            "(\(format(value.x)), \(format(value.y)), \(format(value.z)))"
        }
    }

    private(set) var isMeasuring = false
    private(set) var isTracking = false
    private(set) var status = "iPhone 인식을 기다리는 중"
    var canStart: Bool { isTracking && !isMeasuring }
    var selectedCondition: DiagnosticCondition = .headStill

    // 매 frame 배열을 추가해도 SwiftUI 화면을 갱신하지 않도록 관찰 대상에서 제외합니다.
    @ObservationIgnored private(set) var lastResult: Result?
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var activeSegment: Int?
    @ObservationIgnored private var currentAnchorID: UUID?
    @ObservationIgnored private var lastAddedAnchorID: UUID?
    @ObservationIgnored private var startedAt: TimeInterval?
    @ObservationIgnored private var losses = 0
    @ObservationIgnored private var reacquisitions = 0
    @ObservationIgnored private var anchorIDChanges = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var deviceTimer: Task<Void, Never>?
    @ObservationIgnored private var deviceReadings: [DiagnosticDeviceReading] = []
    @ObservationIgnored private var condition: DiagnosticCondition = .headStill
    @ObservationIgnored var captureDevice: (() -> DiagnosticDeviceReading)?
    var latestDeviceTime: TimeInterval? {
        guard let last = deviceReadings.last, last.pose != nil else { return nil }
        return last.returnedTime
    }
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let emitSummary: (String) -> Void
    private let duration: TimeInterval = 10

    // 실제 실행은 단조 증가 시계를 사용합니다. 검증에서는 가짜 시각으로 loss/마감 시점을 재현합니다.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         emitSummary: @escaping (String) -> Void = { print($0) }) {
        self.now = now
        self.emitSummary = emitSummary
    }

    func start() {
        guard canStart else { return }
        segments = []
        activeSegment = nil
        losses = 0
        reacquisitions = 0
        anchorIDChanges = 0
        lastResult = nil
        deviceReadings = []
        condition = selectedCondition // 선택 변경과 무관하게 이 측정의 조건을 시작 순간에 고정합니다.
        startedAt = now()
        isMeasuring = true
        status = "\(condition.rawValue): 10초 측정 중 — iPhone을 움직이지 마세요"

        // ObjectAnchor 업데이트와 별도로 조회하므로 object loss 중에도 기기 움직임을 기록합니다.
        // nominal 30 Hz일 뿐 실시간 보장은 없으며 실제 timestamp 간격을 summary에 출력합니다.
        deviceTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isMeasuring, let start = self.startedAt,
                      let captureDevice = self.captureDevice else { return }
                if self.now() >= start + self.duration {
                    self.finish(at: self.now(), reason: "completed")
                    return
                }
                self.deviceReadings.append(captureDevice())
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }

        // 새 pose가 전혀 오지 않거나 추적을 잃어도 10초 후 종료합니다.
        // 버튼 이전의 cached pose는 표본에 넣지 않으며 자동 시작/자동 재시작하지 않습니다.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        timer = Task { [weak self] in
            // Task가 늦게 실행되어도 그 시점부터 10초를 다시 세지 않습니다.
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self else { return }
            self.finish(at: self.now(), reason: "completed")
        }
    }

    func receive(_ event: Event, anchorID: UUID, isTracked: Bool, transform: simd_float4x4,
                 comparison: DiagnosticPoseComparison? = nil, captureFailure: String? = nil) {
        let time = now()
        // timer 실행이 지연돼도 [start, start+10) 밖의 표본/상태 전환은 수집하지 않습니다.
        if let startedAt, time >= startedAt + duration {
            finish(at: time, reason: "completed")
        }

        switch event {
        case .added:
            if isMeasuring {
                activeSegment = nil // 같은 ID의 added라도 새로운 tracking 구간입니다.
                if let lastAddedAnchorID, lastAddedAnchorID != anchorID { anchorIDChanges += 1 }
                if isTracked { reacquisitions += 1 }
            }
            currentAnchorID = anchorID
            lastAddedAnchorID = anchorID
            isTracking = isTracked

        case .updated:
            // 표시 중인 anchor와 같은 ID만 관찰합니다. 이전 anchor의 늦은 이벤트는 무시합니다.
            guard currentAnchorID == anchorID else { return }
            if isTracking && !isTracked {
                if isMeasuring { losses += 1 }
                activeSegment = nil
            } else if !isTracking && isTracked {
                if isMeasuring { reacquisitions += 1 }
            }
            isTracking = isTracked

        case .removed:
            guard currentAnchorID == anchorID else { return }
            // false를 먼저 받았다면 이미 loss를 셌으므로 removed에서 중복 계산하지 않습니다.
            if isMeasuring && isTracking { losses += 1 }
            activeSegment = nil
            currentAnchorID = nil
            isTracking = false
        }

        if !isMeasuring {
            // 상태가 동일하면 메시지도 동일합니다. per-frame 콘솔 출력은 없습니다.
            if lastResult == nil {
                status = isTracking ? "폰을 안정화한 뒤 측정을 시작하세요" : "iPhone 인식을 기다리는 중"
            }
            return
        }
        guard event != .removed, isTracked else { return }

        if activeSegment == nil {
            segments.append(Segment(anchorID: anchorID))
            activeSegment = segments.count - 1
        }
        // 기존 원본 pose 표본은 그대로 보존합니다. 변환 실패도 기존 측정/표시를 중단하지 않습니다.
        segments[activeSegment!].samples.append(DiagnosticPoseSample(time: time, transform: transform))
        if let comparison { segments[activeSegment!].comparisons.append(comparison) }
        if let captureFailure { segments[activeSegment!].captureFailures[captureFailure, default: 0] += 1 }
    }

    func stopSession() {
        // ImmersiveSpace를 일찍 닫으면 실제 경과 시간과 interrupted 사유로 요약합니다.
        finish(at: now(), reason: "interrupted: tracking session ended")
        currentAnchorID = nil
        lastAddedAnchorID = nil
        isTracking = false
        if lastResult == nil { status = "iPhone 인식을 기다리는 중" }
    }

    private func finish(at time: TimeInterval, reason: String) {
        guard let startedAt else { return }
        let result = Result(duration: min(max(time - startedAt, 0), duration),
                            reason: time >= startedAt + duration ? "completed" : reason,
                            segments: segments, losses: losses, reacquisitions: reacquisitions,
                            anchorIDChanges: anchorIDChanges, condition: condition, deviceReadings: deviceReadings)
        self.startedAt = nil
        isMeasuring = false
        activeSegment = nil
        timer?.cancel()
        timer = nil
        deviceTimer?.cancel()
        deviceTimer = nil
        lastResult = result
        status = "측정 종료: \(result.sampleCount) samples / \(result.segments.count)구간 — 콘솔 확인"
        emitSummary(result.summary) // 측정당 한 번만 출력합니다.
    }
}
