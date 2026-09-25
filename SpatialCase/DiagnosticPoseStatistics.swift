import Foundation
import simd

// MARK: - DIAGNOSTIC POSE MEASUREMENT

/// 앱이 받은 원본 pose의 한 표본입니다. camera/Entity/model transform은 사용하지 않습니다.
struct DiagnosticPoseSample {
    let time: TimeInterval
    let position: SIMD3<Double>
    let rotation: simd_quatd

    init(time: TimeInterval, transform: simd_float4x4) {
        self.time = time
        position = SIMD3(Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z))
        let rotationMatrix = simd_double3x3(columns: (
            SIMD3(Double(transform.columns.0.x), Double(transform.columns.0.y), Double(transform.columns.0.z)),
            SIMD3(Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z)),
            SIMD3(Double(transform.columns.2.x), Double(transform.columns.2.y), Double(transform.columns.2.z))
        ))
        rotation = simd_normalize(simd_quatd(rotationMatrix))
    }

    // 순수 계산 검증에서도 같은 통계 코드를 사용할 수 있도록 제공하는 초기화입니다.
    init(time: TimeInterval, position: SIMD3<Double>, rotation: simd_quatd) {
        self.time = time
        self.position = position
        self.rotation = simd_normalize(rotation)
    }
}

/// 한 번도 추적이 끊기지 않은 단일 anchor 구간 안에서만 계산합니다.
struct DiagnosticPoseStatistics {
    let meanPosition: SIMD3<Double>
    let positionRMS: Double
    let positionMaximum: Double
    let positionRange: SIMD3<Double>
    let meanRotation: simd_quatd
    let rotationRMSDegrees: Double
    let rotationMaximumDegrees: Double

    init(samples: [DiagnosticPoseSample]) {
        precondition(!samples.isEmpty)
        let count = Double(samples.count)
        let mean = samples.reduce(SIMD3<Double>.zero) { $0 + $1.position } / count
        meanPosition = mean

        // μ = Σp/N. 각 표본의 3차원 거리 d = |p-μ|를 구합니다.
        // RMS = sqrt(Σd²/N), maximum = max(d). 연속 프레임 간 이동거리와는 다릅니다.
        // 모든 표본의 가중치는 동일하며 N-1 보정이나 시간 가중을 사용하지 않습니다.
        let squaredDistances = samples.map { simd_length_squared($0.position - mean) }
        positionRMS = sqrt(squaredDistances.reduce(0, +) / count)
        positionMaximum = sqrt(squaredDistances.max() ?? 0)
        let minimum = samples.reduce(samples[0].position) { simd_min($0, $1.position) }
        let maximum = samples.reduce(samples[0].position) { simd_max($0, $1.position) }
        positionRange = maximum - minimum

        // quaternion을 단순 평균하지 않고 Markley 평균을 사용합니다.
        // M = Σ(q qᵀ)/N의 최대 고유값에 해당하는 단위 고유벡터가 평균 orientation입니다.
        // q qᵀ = (-q)(-q)ᵀ이므로 quaternion 부호 선택에 영향을 받지 않습니다.
        let meanQuaternion = Self.averageQuaternion(samples.map(\.rotation))
        meanRotation = meanQuaternion
        let angles = samples.map { Self.angularDistanceDegrees(meanQuaternion, $0.rotation) }
        rotationRMSDegrees = sqrt(angles.reduce(0) { $0 + $1 * $1 } / count)
        rotationMaximumDegrees = angles.max() ?? 0
    }

    static func angularDistanceDegrees(_ lhs: simd_quatd, _ rhs: simd_quatd) -> Double {
        let difference = simd_normalize(simd_inverse(lhs) * rhs)
        // 상대 quaternion의 실수부 절댓값으로 q/-q를 동일시합니다.
        // 2 atan2(|imag|, |real|)는 0...π의 shortest angle이며 작은 각도에도 안정적입니다.
        return 2 * atan2(simd_length(difference.imag), abs(difference.real)) * 180 / .pi
    }

    private static func averageQuaternion(_ rotations: [simd_quatd]) -> simd_quatd {
        var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        var vectors = matrix
        for index in 0..<4 { vectors[index][index] = 1 }
        for rotation in rotations {
            let q = simd_normalize(rotation).vector
            for row in 0..<4 {
                for column in 0..<4 {
                    matrix[row][column] += q[row] * q[column] / Double(rotations.count)
                }
            }
        }

        // 대칭 4×4 행렬의 Jacobi 고유값 분해입니다. 가장 큰 비대각 원소를
        // 회전으로 제거하면서 고유벡터를 누적합니다. 종료 후에만 실행되며 HFR 경로에는 없습니다.
        for _ in 0..<64 {
            var p = 0
            var q = 1
            for row in 0..<4 {
                for column in (row + 1)..<4 where abs(matrix[row][column]) > abs(matrix[p][q]) {
                    p = row
                    q = column
                }
            }
            let offDiagonal = matrix[p][q]
            if abs(offDiagonal) < 1e-14 { break }
            let tau = (matrix[q][q] - matrix[p][p]) / (2 * offDiagonal)
            let tangent = (tau >= 0 ? 1.0 : -1.0) / (abs(tau) + sqrt(1 + tau * tau))
            let cosine = 1 / sqrt(1 + tangent * tangent)
            let sine = tangent * cosine
            matrix[p][p] -= tangent * offDiagonal
            matrix[q][q] += tangent * offDiagonal
            matrix[p][q] = 0
            matrix[q][p] = 0

            for index in 0..<4 {
                if index != p && index != q {
                    let a = matrix[index][p]
                    let b = matrix[index][q]
                    matrix[index][p] = cosine * a - sine * b
                    matrix[p][index] = matrix[index][p]
                    matrix[index][q] = sine * a + cosine * b
                    matrix[q][index] = matrix[index][q]
                }
                let a = vectors[index][p]
                let b = vectors[index][q]
                vectors[index][p] = cosine * a - sine * b
                vectors[index][q] = sine * a + cosine * b
            }
        }
        let largest = (0..<4).max { matrix[$0][$0] < matrix[$1][$1] }!
        return simd_normalize(simd_quatd(vector: SIMD4(
            vectors[0][largest], vectors[1][largest], vectors[2][largest], vectors[3][largest]
        )))
    }
}
