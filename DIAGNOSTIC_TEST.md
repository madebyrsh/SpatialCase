# iPhone Reference Model 진단 실험

작업 브랜치: `experiment/object-tracking-diagnostic`

목적: Case 보정값을 제외하고, 학습 원본 모델과 실제 iPhone 17이 ObjectAnchor 위에서
얼마나 안정적으로 겹치는지 확인한다. 한 번에 iPhone 한 대로 테스트한다.

## 변경 범위

- `ImmersiveView.swift`: RCP의 `world`/Orange Case 로딩 대신 진단 모델을 표시한다.
  일반 Entity에 `ObjectAnchor.originFromAnchorTransform`을 직접 적용한다.
- `DiagnosticReferenceModel.swift`: 복사본을 로드하고 하위 mesh의 재질만 메모리에서
  청록색 UnlitMaterial, opacity 0.35로 교체한다.
- `ContentView.swift`: 실험 앱임을 알리는 제목과 안내를 표시한다.
- `SpatialCase/Resources/Diagnostic_iPhone17.usdz`: 아래 원본의 바이트 동일 복사본이다.

Extended reference object 선택과 high-frame-rate 설정은 그대로다.
세 번째 실험은 `ObjectTrackingManager`의 같은 세션에 보조 WorldTrackingProvider만 추가한다.
AnchorEntity, RCP Object Anchoring, smoothing, interpolation, prediction은 추가하지 않는다.
원본 Create ML / referenceobject / USDZ / RCP / SpatialCase.reality 파일은 수정하지 않는다.

## 좌표계 확인 근거

원본: `ObjectTracking/iPhone17/SourceModels/Apple iPhone 17.usdz`

원본과 복사본의 SHA-256:

```text
cc821b1372ce4c6d95be72ab2fc79539c5668e1fd441da4ed1caa93c86515082
```

1. 원본 USDZ는 `metersPerUnit = 1`, `upAxis = Z`이다.
2. Extended referenceobject의 `object.usdz`에는 Y-up wrapper가 있고,
   그 아래 원본에 `rotateX = -90`을 적용한다. 내장된 원본 USDZ와 위 원본 파일은 바이트가 같다.
3. macOS RealityKit에서 두 모델을 각각 읽어 비교했다. 원본 로더는 root에 Z-up → Y-up
   회전을 자동으로 넣었으며, 결과 경계는 내장 reference 모델과 일치했다.
4. 따라서 진단 모델의 **로드된 local transform을 보존**하고 일반 tracking Entity의
   자식으로 붙인다. Case의 Z -0.009 / X -90° 보정은 추가하지 않는다.
   중심 이동, 크기 정규화, 추가 scale도 하지 않는다.

anchor 좌표계에서 예상하는 모델 경계(미터, 부동소수점 오차 허용):

```text
min ≈ (-0.03617506, -0.074806176, -0.0074249473)
max ≈ ( 0.03617464,  0.074805010,  0.0039750000)
크기 ≈ (0.07234970, 0.14961119, 0.01139995)
```

`added` 시 실제 visionOS 로더의 모델 경계와 `ObjectAnchor.boundingBox`를 함께 출력한다.
이 비교는 좌표계/단위 검사용이다. 경계 일치만으로 실제 정합 정확도를 보장하지 않는다.

## Vision Pro 테스트

1. 이 브랜치의 `SpatialCase.xcodeproj`를 열고, 실제 Vision Pro를 실행 대상으로 선택한다.
   프로젝트의 기존 서명 설정으로 Build & Run한다.
2. Xcode 콘솔을 `[DIAGNOSTIC]`으로 필터링하고 ImmersiveSpace를 연다.
   필요하면 world sensing 권한을 허용한다. Orange Case 대신 청록색 반투명 iPhone이 보여야 한다.
3. 케이스를 벗긴 iPhone 17 한 대를 밝은 곳에 놓고 인식시킨다. `added` 로그와 model/anchor
   경계를 비교한다. 축 순서나 크기가 다르면 그 로그를 남긴다. 눈대중 보정은 먼저 넣지 않는다.
4. iPhone을 고정한 채 머리를 천천히 움직여 모서리, 화면, 카메라 위치가 일정하게 겹치는지 본다.
   이어 iPhone을 천천히 이동·회전해 고정된 오프셋, 흔들림, 이동 중 지연을 구분해서 기록한다.
5. 잠시 가리거나 시야 밖으로 옮겼다가 다시 보여 준다. ARKit이 `isTracked=false`를 보고하면
   모델이 숨겨지고, true로 돌아오면 다시 표시되어야 한다. 가림이 반드시 즉시 추적 상실을
   일으키는 것은 아니다. removed/added 또는 ID 변경이 있으면 해당 로그도 기록한다.
6. ImmersiveSpace를 닫았다 다시 열어 모델이 중복되지 않고 다시 추적되는지 확인한다.

표시 상태 로그는 added, removed, isTracked 전환, 새 added anchor의 ID 변경에만 출력한다.
일반 updated 프레임은 출력하지 않는다. 시작 실패는 별도 오류 로그로 표시한다.
added에는 경계 확인 로그가 함께 포함된다. 추적 상실 시 마지막 pose를 계속 표시하지 않는다.

## 10초 pose 측정 (두 번째 실험)

실기기에서 사용자가 관찰한 현상: 정지한 iPhone에서도 모델이 미세하게 흔들렸고,
머리 이동/거리 변화 시 더 커 보였다. true→false 및 새 ID의 added도 확인됐다.
이 관찰만으로 흔들림의 원인을 단정하지 않고, 이번 단계에서는 **앱이 받은 pose만 측정**한다.

- `AppModel.swift`: 창과 ImmersiveView가 하나의 측정 인스턴스를 공유한다.
- `ContentView.swift`: 기존 UI에 `10초 pose 측정` 버튼과 간단한 상태 문구를 추가한다.
- `ImmersiveView.swift`: 기존 added/updated/removed 흐름에 원본 pose 전달만 추가하고,
  세션 종료 시 진행 중인 측정을 마무리한다. 기존 표시/transform 적용 코드는 유지한다.
- `DiagnosticPoseMeasurement.swift`: 10초 타이머, 메모리 수집, tracking 구간/횟수, 요약 출력을 담당한다.
- `DiagnosticPoseStatistics.swift`: 위치와 quaternion 통계만 계산한다.
- `Tests/DiagnosticPoseMeasurementChecks.swift`: 합성 입력으로 계산과 구간 분리 등을 검증한다.
  앱 target에 포함되지 않는 독립 실행형 검사이며, 테스트 숫자는 실기기 측정값이 아니다.

### 수집과 출력

추적 중일 때 사용자가 버튼을 누르면 그 시각부터 10초 동안 수집한다. 인식 시 자동 측정하지 않는다.
버튼 이전의 pose는 넣지 않는다. 시각은 앱에서 이벤트를 받은 `systemUptime`(단조 증가 시계)이다.
ARKit 내부 촬영 시각이나 카메라 pose를 이용하는 측정은 아니다.

`isTracked == true`인 added/updated의 `originFromAnchorTransform`만 포함한다.
수집 범위는 `[시작, 시작+10초)`다. 업데이트가 없어도 별도 timer가 종료하며,
timer 처리가 늦어도 마감 시각 이후의 표본은 받지 않는다. 세션을 일찍 닫으면 `interrupted`와
실제 경과 시간을 출력한다. 측정 중 재시작은 막고, 종료 후 버튼으로 다시 측정할 수 있다.

매 프레임 출력은 없고, 종료 시 `[DIAGNOSTIC POSE SUMMARY]`를 한 번 출력한다.
전체 관찰 시간·표본 수·구간 수·tracking 횟수와 **구간별** 통계를 출력한다.
구간의 `sample span`은 마지막 표본 시각 − 첫 표본 시각이며, 10초 관찰 창과 구분한다.
표본이 없으면 데이터 없음, 1개면 안정성을 판정할 수 없다는 안내가 붙는다.
재획득 전후 pose를 합친 평균/RMS는 계산하지 않는다.

### 통계 정의

한 구간의 표본 수가 N, 위치가 pᵢ이면 평균 μ = Σpᵢ/N이다.

- 위치 RMS = √(Σ‖pᵢ−μ‖²/N)
- 위치 maximum = max‖pᵢ−μ‖
- X/Y/Z range = 각 축의 max − min
- 평균 위치와 위 결과는 m에서 mm로 변환한다. origin 좌표계의 축이며 폰 자체의 축이 아니다.

이는 프레임 간 이동량이나 최초 pose로부터의 오차가 아니라 **구간 평균 주변의 분산 정도**다.
표본마다 동일한 가중치를 적용하며 시간 가중이나 N−1 보정은 하지 않는다.

회전은 정규화한 quaternion qᵢ에서 M = Σ(qᵢqᵢᵀ)/N을 만들고,
최대 고유값의 단위 고유벡터를 구하는
[Markley 평균](https://ntrs.nasa.gov/citations/20070017872)을 사용한다.
q와 −q의 outer product가 같으므로 부호가 뒤집혀도 평균 orientation은 같다.
이는 Euler 평균이나 원본 pose 행렬 원소 평균이 아니다.

평균 quaternion q̄에 대해 상대 회전 rᵢ = inverse(q̄) × qᵢ를 구한다.
최단 각도 θᵢ = 2 atan2(‖imag(rᵢ)‖, |real(rᵢ)|)는 0…π 범위다.
회전 RMS = √(Σθᵢ²/N), maximum = max θᵢ를 degree로 출력한다.
평균 계산은 종료 후 통계에만 쓰며 렌더링 pose에는 적용하지 않는다.

### 구간과 tracking 횟수

- true→false: loss 1회, 현재 구간 종료. 반복 false는 추가 loss나 표본으로 세지 않는다.
- false→true: reacquisition 1회, 같은 ID라도 새 구간을 만든다.
- added: 항상 구간 경계다. true인 added는 reacquisition 1회, false라면 이후 true가 될 때 센다.
  측정 시작 전에 발생한 최초 인식은 횟수에 포함하지 않는다.
- 새 added의 ID가 이전 added의 ID와 다르면 ID change 1회다.
- 추적 중인 anchor가 false 없이 removed되면 loss 1회다. 이미 false였다면 중복 계산하지 않는다.
- 새 anchor가 기존 anchor를 대체해도 false/removed가 없었다면 loss를 추정해서 더하지 않는다.
- 현재 표시 anchor와 다른 ID의 늦은 updated/removed는 무시한다.

### 정확한 실기기 측정 순서

1. Build & Run 후 ImmersiveSpace를 열고 iPhone을 바닥에 고정한다.
2. 진단 모델이 보이면 충분히 안정화시킨다. 콘솔 필터를 해제해 여러 줄 요약 전체가 보이게 한다.
3. 기존 창의 `10초 pose 측정`을 누르고, 10초 동안 iPhone을 건드리지 않는다.
4. `[DIAGNOSTIC POSE SUMMARY]` 아래 전체 결과를 복사한다. 구간이 여러 개면 각각 따로 읽는다.
5. 다시 버튼을 눌러 폰은 고정한 채 머리만 천천히 움직이며 반복한다.
   정지 관찰/머리 이동/거리 변화 조건을 구분해 결과를 기록한다.
6. 필요하면 별도 측정에서 가림→재인식을 유도해 loss/구간 분리가 보고되는지 확인한다.

독립 계산 검사는 저장소 루트에서 다음처럼 실행할 수 있다(macOS Swift toolchain 필요).

```sh
swiftc -parse-as-library SpatialCase/DiagnosticPoseStatistics.swift SpatialCase/DiagnosticPoseComparison.swift SpatialCase/DiagnosticPoseMeasurement.swift Tests/DiagnosticPoseMeasurementChecks.swift -o /tmp/spatialcase-pose-checks
/tmp/spatialcase-pose-checks
```

두 번째 실험에서는 진단 USDZ, `DiagnosticReferenceModel.swift`, tracking manager와 원본 asset을 유지했다.

## Current / Rendered / Metric A/B 비교 (세 번째 실험)

목적은 **정지한 iPhone의 표시용 pose와 metric pose 변동 비교**다.
기존 표시와 10초 raw pose 측정은 보존한다. 표시 Entity에 적용하는 값은 계속
`ObjectAnchor.originFromAnchorTransform`이며, 아래 새 값들을 표시에는 사용하지 않는다.
WorldTrackingProvider는 ObjectTrackingProvider와 같은 ARKitSession에서 실행한다.

### visionOS 27 API와 공통 좌표계

Xcode 27.0 / xros 27.0 SDK의 Swift interface와 Apple 문서를 확인했다.

- Current: 동일 ObjectAnchor의 `originFromAnchorTransform`.
- Rendered: `anchor.coordinateSpace(correction: .rendered)`.
- Metric: `anchor.coordinateSpace(correction: .none)`.
- 뒤의 두 값은 `ARKitCoordinateSpace`이며 ancestor는 `WorldReferenceCoordinateSpace`다.
  각각 `let t: ProjectiveTransform3DFloat = try scene.transform(from: space)`를 호출하고
  `t.matrix`를 사용한다. scene은 실제 `runtimeRoot.scene`이다.
  ancestor transform을 별다른 변환 없이 기존 current origin 행렬과 섞지 않는다.
- ImmersiveSpace에서 RealityKit scene은 ARKit world origin이다. 따라서 변환 후 세 값은
  같은 scene origin, 미터 단위다. 기존 root는 identity인 일반 Entity로 그대로 유지한다.
- 같은 이벤트의 같은 ObjectAnchor 값에서 await 없이 세 값을 연속해서 읽는다.
  atomic snapshot이나 렌더 제출 시각과의 정확한 동시성을 보장한다고 해석하지 않는다.
  세 값을 읽고 변환/검증하는 데 든 시간도 ms로 요약한다.
- 변환 실패, 비유한 행렬, scale/shear는 비교에서 제외하고 사유별 횟수를 출력한다.
  기존 raw 측정과 visualization은 계속된다. 비교에는 유효한 세 값이 모두 있는 표본만 사용한다.

Apple은 기본 ObjectAnchor transform이 mixed overlay에 맞게 최적화된다고 설명하며,
`.rendered`는 display correction 적용, `.none`은 display correction 없는 metric 값이라고 설명한다.
이 설명만으로 기본 값과 명시적 `.rendered`의 수치 동일성을 단정하지 않는다.
`Current vs explicit Rendered`의 위치 거리/최단 회전각 RMS 및 최대값으로 실기기에서 확인한다.
시간 변동이 없는 일정한 오프셋도 이 검사에는 나타난다.

공식 근거:

- [Object tracking: perceived / metric](https://developer.apple.com/documentation/visionos/exploring_object_tracking_with_arkit)
- [기본 transform과 correction 옵션](https://developer.apple.com/documentation/visionos/using-a-reference-object-with-arkit-in-visionos)
- [Immersive scene = ARKit world origin](https://developer.apple.com/documentation/realitykit/realitycoordinatespace/scene)
- [CoordinateSpace3D 변환](https://developer.apple.com/documentation/spatial/coordinatespace3d/transform(from:))
- [DeviceAnchor current / future timestamp](https://developer.apple.com/documentation/arkit/worldtrackingprovider/querydeviceanchor(attimestamp:))
- [AnchorUpdate timestamp](https://developer.apple.com/documentation/arkit/anchorupdate/timestamp)

### Summary 읽기

각 Object tracking segment에 기존 Current 전체 표본 통계를 유지한다. 이어서 **동일한 표본 집합**의
Current / Rendered / Metric 세 통계를 각각 출력한다. 각각 위치 RMS/최대/XYZ range,
회전 RMS/최대를 포함한다. 기존 Markley/Jacobi/shortest-angle 알고리즘은 수정하지 않았고,
회전 출력만 소수점 6자리로 늘렸다. `0.000000°`도 출력 해상도 아래의 값을 배제하지 않는다.

`C(t) = inverse(T_metric) * T_rendered`의 위치/회전 변동도 같은 방식으로 요약한다.
이것은 **Metric과 Rendered API 출력 사이의 상대 차이**이며 Apple 내부 correction 자체라고
부르지 않는다. C의 translation은 metric anchor local 축 기준이다.
C translation 크기 및 identity로부터의 회전각 min/mean/max도 출력해서 일정한 차이를 구별한다.
원본 pose와 C의 RMS는 각각 자기 구간 평균에 대한 편차이며 frame 간 이동량이 아니다.

Object의 false/removed/added/새 ID/reacquisition에서 기존 segment 경계를 유지한다.
구간 사이 점프를 한 연속적인 pose 변화로 계산하지 않는다. 매 update 로그는 추가하지 않는다.

### DeviceAnchor와 시각 차이

측정 버튼을 누른 뒤 10초 동안 별도 Task가 nominal 약 30 Hz로 기기를 조회한다.
Object 업데이트가 없어도 계속 수집한다. 실제 조회 간격과 표본 수/시간 범위를 출력하므로
30 Hz의 정확한 일정 간격이라고 가정하지 않는다.

매번 `queryDeviceAnchor(atTimestamp: CACurrentMediaTime())`를 사용한다.
API 문서상 now/future의 추정 pose이며, 앱은 **현재 시각만** 요청한다. 과거 ObjectAnchor 시각을
조회하거나 미래 시각을 요청하지 않고, 자체 prediction/interpolation도 추가하지 않는다.
`.trackingState == .tracked`만 사용하고 `.none` 좌표계를 같은 scene으로 변환한다.
조회 실패/추적 불완전/변환 실패/Device ID 변경마다 device run을 나눠 통계를 출력한다.
기기 자체의 위치/회전이지 머리 중심의 정확한 좌표나 독립 ground truth가 아니다.

Object triple마다 가장 최근에 수집한 device reading의 timestamp를 연결한다.
최근 reading이 invalid이면 이전 정상 값을 재사용하지 않는다. 보간/시간 정렬/과거 재조회는 없다.
따라서 동시 표본으로 취급하지 않으며 다음 signed 차이를 min/mean/max와 표본 수로 출력한다.

- Object receipt(CACurrentMediaTime) − ObjectAnchor.timestamp
- AnchorUpdate.timestamp − ObjectAnchor.timestamp
- DeviceAnchor.timestamp − ObjectAnchor.timestamp
- Object receipt − DeviceAnchor.timestamp (연결한 보조 표본의 나이)
- DeviceAnchor.timestamp − device query 요청 시각

Object timestamp는 anchor에 대응하는 API 시각, update timestamp는 update 발생 시각이다.
이를 카메라 노출 시각이라고 추정하지 않는다. 10초 deadline은 기존 단조 시계로 유지하며,
API 시각 차이는 CACurrentMediaTime / ARKit의 absolute-time 도메인끼리만 계산한다.
Device run은 별도 스트림의 연속 구간이며 Object segment들과 일대일로 대응하지 않는다.

### A/B 테스트

1. 폰을 고정하고 인식 후 안정화한다. `A — Head Still`을 선택하고 10초 동안 머리를 최대한 고정한다.
2. 폰을 그대로 두고 `B — Head Moving`을 선택하고 10초 동안 머리를 천천히 좌우/앞뒤로 이동한다.
3. 두 `[DIAGNOSTIC POSE SUMMARY]` 전체를 저장한다. 조건, valid triples, device run/시간차,
   각 Object segment의 세 pose 및 C 통계를 비교한다. 한 표본/여러 tracking 구간은 구분해서 읽는다.

조건은 시작 순간 snapshot으로 결과에 고정하고 측정 중 Picker를 비활성화한다.
이번 단계에서도 commit/push/브랜치 변경을 하지 않는다.

## baseline으로 돌아갈 때

사용자가 diff를 확인하고 별도로 승인한 뒤에만 실험 변경 **전체(새 파일 포함)**를 이 브랜치에
로컬 commit한다. commit 후 `git status --short`가 빈 출력인지 확인한다.
그 다음 `git switch feat/case-overlay`하면 추적된 실험 파일/코드가 빠지고 기존 Case Overlay
소스로 돌아간다. 아직 commit하지 않은 상태에서는 switch만으로 격리되지 않는다.

원격 push, merge, rebase, reset, restore, stash는 실행하지 않는다.
Vision Pro에 설치된 앱은 Git switch로 바뀌지 않으므로 baseline을 다시 Build & Run해야 한다.
