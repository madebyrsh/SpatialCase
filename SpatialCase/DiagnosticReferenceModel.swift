import Foundation
import RealityKit
import UIKit

// MARK: - DIAGNOSTIC TEST

/// 학습에 사용한 원본 USDZ의 복사본을 읽고, 메모리 안에서만 진단용 재질을 적용합니다.
@MainActor
enum DiagnosticReferenceModel {
    static func load(from url: URL) async throws -> Entity {
        let model = try await Entity(contentsOf: url)
        model.name = "Diagnostic_iPhone17"

        // 원본은 metersPerUnit=1, upAxis=Z입니다. RealityKit은 로드할 때
        // root에 Z-up → Y-up 변환을 넣습니다. 이 transform을 초기화하지 않습니다.
        // Extended referenceobject의 내장 모델도 같은 원본에 이 축 변환을 적용합니다.
        // 따라서 추가 회전/이동/scale은 필요 없습니다. Case의 X -90°/Z -0.009를
        // 여기에 다시 적용하면 이중 회전 또는 위치 오차가 생깁니다.

        // 조명에 덜 영향받는 청록색 반투명 재질로 실제 iPhone과 가상 표면을 비교합니다.
        // 원본/복사본 파일의 geometry, 재질, 좌표계는 디스크에서 수정하지 않습니다.
        var material = UnlitMaterial(color: .cyan)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        apply(material, to: model)
        return model
    }

    private static func apply(_ material: UnlitMaterial, to entity: Entity) {
        // USDZ는 여러 하위 mesh로 구성되므로 모든 ModelComponent에 적용합니다.
        // mesh와 entity transform은 유지하고, 각 material slot만 교체합니다.
        if var component = entity.components[ModelComponent.self] {
            component.materials = Array(repeating: material, count: max(component.materials.count, 1))
            entity.components.set(component)
        }
        for child in entity.children {
            apply(material, to: child)
        }
    }
}
