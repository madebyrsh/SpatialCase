import RealityKit

// MARK: - STATIC ALIGNMENT TEST

enum SpatialCaseExperiment: String, CaseIterable, Identifiable {
    case staticAlignment = "Orange Case · Static alignment"
    case diagnostic = "기존 iPhone Pose Diagnostic"
    var id: Self { self }
}

enum CaseAlignmentCandidate: String, CaseIterable, Identifiable {
    case baseline = "Baseline · Z −9.000 mm"
    case noOffset = "No offset · Z 0.000 mm"
    case backSurfaceContact = "Geometry · Z −7.775 mm"
    case fineTuneHalfMillimeter = "Fine Tune · Z −7.275 mm (+0.5 mm)"
    case fineTuneOneMillimeter = "Fine Tune · Z −6.775 mm (+1.0 mm)"
    var id: Self { self }

    /// RCP에서 읽은 동일 Case의 회전/scale/X/Y를 보존하고 부모 기준 Z translation만 바꿉니다.
    /// T_parentFromCase = Translation * Rotation * Scale이므로 이 Z는 회전된 mesh의 Z축이 아닙니다.
    func transform(from baseline: Transform) -> Transform {
        var result = baseline
        switch self {
        case .baseline:
            break // 원본 RCP local transform을 그대로 재현합니다.
        case .noOffset:
            result.translation.z = 0
        case .backSurfaceContact:
            // 실제 triangle 단면: phone 후면 −3.975 mm, Case 내부 후면 +3.800 mm.
            // −3.975 − 3.800 = −7.775 mm. bounds 중심 정렬이나 실측 pose 보정이 아닙니다.
            result.translation.z = -0.007775
        case .fineTuneHalfMillimeter:
            // Geometry control에서 화면 방향으로 +0.5 mm 이동하는 지각 비교 후보입니다.
            // 새로운 geometry 접촉 정답이 아니라 Perceptual fine-tuning용입니다.
            result.translation.z = -0.007275
        case .fineTuneOneMillimeter:
            // 같은 control에서 +1.0 mm 이동합니다. 최종 선택값은 실기기 비교 후 결정합니다.
            result.translation.z = -0.006775
        }
        return result
    }
}
