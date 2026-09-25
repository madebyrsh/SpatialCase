import Foundation
import simd

// MARK: - DIAGNOSTIC TEST — 표시와 독립적인 비교 데이터/요약

enum DiagnosticCondition: String, CaseIterable, Identifiable {
    case headStill = "A — Head Still"
    case headMoving = "B — Head Moving"
    var id: Self { self }
}

/// 세 Object pose는 모두 같은 RealityKit scene(immersive ARKit origin), 미터 기준입니다.
/// timestamp는 API가 제공한 시각이며, 센서 노출 시각이나 동시 촬영 시각이라고 해석하지 않습니다.
struct DiagnosticPoseComparison {
    let current: DiagnosticPoseSample
    let rendered: DiagnosticPoseSample
    let metric: DiagnosticPoseSample
    let relative: DiagnosticPoseSample
    let objectTime: TimeInterval
    let updateTime: TimeInterval
    let receiptTime: TimeInterval
    let readDuration: TimeInterval
    let deviceTime: TimeInterval?

    init(current: simd_float4x4, rendered: simd_float4x4, metric: simd_float4x4,
         objectTime: TimeInterval, updateTime: TimeInterval, receiptTime: TimeInterval,
         readDuration: TimeInterval, deviceTime: TimeInterval?) {
        self.current = DiagnosticPoseSample(time: receiptTime, transform: current)
        self.rendered = DiagnosticPoseSample(time: receiptTime, transform: rendered)
        self.metric = DiagnosticPoseSample(time: receiptTime, transform: metric)
        // C는 rendered 좌표를 metric anchor의 local 좌표로 옮깁니다.
        // Apple 내부 correction을 분리해 낸 값이 아니라 두 API 출력의 상대 transform입니다.
        relative = DiagnosticPoseSample(time: receiptTime, transform: simd_inverse(metric) * rendered)
        self.objectTime = objectTime
        self.updateTime = updateTime
        self.receiptTime = receiptTime
        self.readDuration = readDuration
        self.deviceTime = deviceTime
    }
}

struct DiagnosticDeviceReading {
    let queryTime: TimeInterval
    let returnedTime: TimeInterval?
    let anchorID: UUID?
    let pose: DiagnosticPoseSample?
    let issue: String?
}

enum DiagnosticComparisonSummary {
    static func number(_ value: Double) -> String { String(format: "%.6f", value) }

    static func statistics(_ title: String, samples: [DiagnosticPoseSample]) -> [String] {
        guard !samples.isEmpty else { return ["\(title): no valid samples"] }
        let s = DiagnosticPoseStatistics(samples: samples)
        return [title, "Samples: \(samples.count); span: \(number(samples.last!.time - samples.first!.time)) s",
                "Mean position (mm): \(number(s.meanPosition.x * 1000)), \(number(s.meanPosition.y * 1000)), \(number(s.meanPosition.z * 1000))",
                "Position RMS: \(number(s.positionRMS * 1000)) mm; Maximum position deviation: \(number(s.positionMaximum * 1000)) mm",
                "X/Y/Z range: \(number(s.positionRange.x * 1000)) / \(number(s.positionRange.y * 1000)) / \(number(s.positionRange.z * 1000)) mm",
                "Rotation RMS: \(number(s.rotationRMSDegrees))°; Maximum rotation deviation: \(number(s.rotationMaximumDegrees))°",
                samples.count < 2 ? "Insufficient samples to establish stability." : "Deviations are from this run's position / Markley rotation mean."]
    }

    static func distribution(_ label: String, values: [Double], unit: String) -> String {
        guard !values.isEmpty else { return "\(label): unavailable" }
        return "\(label) (n=\(values.count)): min / mean / max = \(number(values.min()!)) / \(number(values.reduce(0, +) / Double(values.count))) / \(number(values.max()!)) \(unit)"
    }

    static func object(_ rows: [DiagnosticPoseComparison]) -> [String] {
        guard !rows.isEmpty else { return ["Paired comparison: no valid triples (see capture failures)."] }
        var lines = ["Paired triples: \(rows.count); common space: RealityKit scene / immersive ARKit origin (meters)"]
        lines += statistics("Current — originFromAnchorTransform (paired subset)", samples: rows.map(\.current))
        lines += statistics("Rendered — explicit correction .rendered", samples: rows.map(\.rendered))
        lines += statistics("Metric — explicit correction .none", samples: rows.map(\.metric))
        lines += statistics("C(t) = inverse(T_metric) * T_rendered — relative API output difference, in metric anchor local axes", samples: rows.map(\.relative))
        // 시간 변화가 0이어도 일정한 오프셋을 놓치지 않도록 동일성 기준의 절대 차이도 봅니다.
        let distance = rows.map { simd_distance($0.current.position, $0.rendered.position) * 1000 }
        let angle = rows.map { DiagnosticPoseStatistics.angularDistanceDegrees($0.current.rotation, $0.rendered.rotation) }
        lines += ["Current vs explicit Rendered — differences from equality, not from a mean:",
                  "Position difference RMS / max: \(number(rms(distance))) / \(number(distance.max()!)) mm",
                  "Rotation difference RMS / max: \(number(rms(angle))) / \(number(angle.max()!))°",
                  distribution("C translation magnitude", values: rows.map { simd_length($0.relative.position) * 1000 }, unit: "mm"),
                  distribution("C rotation angle from identity", values: rows.map { DiagnosticPoseStatistics.angularDistanceDegrees(simd_quatd(angle: 0, axis: SIMD3(0, 1, 0)), $0.relative.rotation) }, unit: "°"),
                  distribution("Receipt − ObjectAnchor.timestamp", values: rows.map { ($0.receiptTime - $0.objectTime) * 1000 }, unit: "ms"),
                  distribution("AnchorUpdate.timestamp − ObjectAnchor.timestamp", values: rows.map { ($0.updateTime - $0.objectTime) * 1000 }, unit: "ms"),
                  distribution("Triple read duration (sequential, no await)", values: rows.map { $0.readDuration * 1000 }, unit: "ms"),
                  distribution("Latest valid sampled DeviceAnchor.timestamp − ObjectAnchor.timestamp (signed, NOT synchronized)", values: rows.compactMap { row in row.deviceTime.map { ($0 - row.objectTime) * 1000 } }, unit: "ms"),
                  distribution("Object receipt − latest valid sampled DeviceAnchor.timestamp (sample age)", values: rows.compactMap { row in row.deviceTime.map { (row.receiptTime - $0) * 1000 } }, unit: "ms"),
                  "Object rows without a valid latest device reading: \(rows.filter { $0.deviceTime == nil }.count)"]
        return lines
    }

    static func device(_ readings: [DiagnosticDeviceReading]) -> [String] {
        // Device 자체의 loss/ID 변경/조회 실패도 경계입니다. 유효하지 않은 pose로 연결하지 않습니다.
        var runs: [[DiagnosticPoseSample]] = []
        var previousID: UUID?
        var needsRun = true
        var failures: [String: Int] = [:]
        for reading in readings {
            guard let pose = reading.pose, let id = reading.anchorID else {
                failures[reading.issue ?? "unavailable", default: 0] += 1
                needsRun = true
                continue
            }
            if needsRun || previousID != id { runs.append([]) }
            runs[runs.count - 1].append(pose)
            previousID = id
            needsRun = false
        }
        var lines = ["", "Device motion — auxiliary ARKit estimate, NOT independent ground truth",
                     "Independent current-time polling (~30 Hz target, actual cadence below), correction .none, scene origin",
                     "Device queries: \(readings.count); valid samples: \(runs.reduce(0) { $0 + $1.count }); runs: \(runs.count)"]
        for key in failures.keys.sorted() { lines.append("Device \(key): \(failures[key]!)") }
        lines.append(distribution("Device returned timestamp − requested current time", values: readings.compactMap { r in r.returnedTime.map { ($0 - r.queryTime) * 1000 } }, unit: "ms"))
        lines.append(distribution("Device query interval", values: zip(readings, readings.dropFirst()).map { ($1.queryTime - $0.queryTime) * 1000 }, unit: "ms"))
        for (index, run) in runs.enumerated() { lines += statistics("Device run \(index + 1)", samples: run) }
        return lines
    }

    private static func rms(_ values: [Double]) -> Double {
        sqrt(values.reduce(0) { $0 + $1 * $1 } / Double(values.count))
    }
}
