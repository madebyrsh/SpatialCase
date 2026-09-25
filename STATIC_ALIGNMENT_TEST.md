# Orange Case static alignment 실험

이 실험은 pose 안정성을 평가하지 않는다. ObjectAnchor pose는 그대로 적용하고,
동일 Orange Case Entity의 부모 기준 Z translation만 세 후보 사이에서 바꾼다.
브랜치: `experiment/object-tracking-diagnostic`. 기존 diagnostic 기능은 별도 모드로 보존한다.

## 사용한 실제 asset / runtime 확인

- Phone: `ObjectTracking/iPhone17/SourceModels/Apple iPhone 17.usdz`
- Case: `Models/iPhone17/ResizedCase/iPhone17_ThinCase_Orange.usdz`
- RCP import의 `settings.tm_usd`가 위 **ResizedCase**를 가리킨다.
  `Models/iPhone17/Case/`의 별도 파일은 meter metadata에 mm 크기의 숫자가 들어 있어
  같은 파일로 취급하지 않았다. 이번 실험에서는 그 파일을 로드하지 않는다.
- Runtime: 기존 `SpatialCase.reality`의 `world`를 읽어 `iPhone17_ThinCase_Orange` 노드를 가져온다.
  world는 화면에 추가하지 않고 Case만 기존 trackedEntity에 연결한다.
  새 USDZ 복사본이나 asset 변경은 없다.
- macOS RealityKit으로 원본 USDZ들과 `.reality`를 읽어 transform/bounds를 확인했다.
  visionOS Debug 빌드와 별개로, 실제 Vision Pro의 최종 시각적 밀착은 사용자가 평가한다.

## 좌표계와 bounds

아래 숫자는 모두 **mm**, 소수점 반올림이다. AABB는 실제 vertex extrema로 확인했고,
geometry center는 질량중심이 아니라 AABB midpoint를 뜻한다.

| 모델 / 기준 | min (X,Y,Z) | max (X,Y,Z) | dimensions (X,Y,Z) |
|---|---|---|---|
| Phone authored USD | (−36.17506, −3.97500, −74.80618) | (36.17464, 7.42495, 74.80501) | (72.34970, 11.39995, 149.61119) |
| Phone loaded / anchor axes | (−36.17506, −74.80618, −7.42495) | (36.17464, 74.80501, 3.97500) | (72.34970, 149.61119, 11.39995) |
| Resized Case authored USD | (−37.850, −13.000, −76.400) | (37.850, 0.000, 76.400) | (75.700, 13.000, 152.800) |
| Case rotated, no translation | (−37.850, −76.400, 0.000) | (37.850, 76.400, 13.000) | (75.700, 152.800, 13.000) |
| Case RCP baseline | (−37.850, −76.400, −9.000) | (37.850, 76.400, 4.000) | (75.700, 152.800, 13.000) |

Phone의 35개 mesh, Case의 1개 mesh의 vertex/face 배열을 분석했다.
두 모델의 USD metadata는 `metersPerUnit=1`, `upAxis=Z`다. mesh와 그 상위 노드에는
pivot 이동이나 비identity geometry transform이 없다. Phone의 DomeLight 회전은 geometry에 작용하지 않는다.
RealityKit USDZ loader는 root에 X −90°를 적용하여 (x,y,z) → (x,z,−y)로 변환한다.
RCP의 Case 노드도 X −90°, scale (1,1,1)이며 `.reality` bounds는 같은 변환과 일치한다.
따라서 Case에 −90°를 한 번 더 곱하지 않는다.

- Phone origin은 대략 본체 중앙이다. 전면 +3.975, 일반 후면 −3.975.
  카메라 돌출부까지 포함한 AABB 중심은 (−0.00021, −0.00058, −1.72497).
- Case origin은 전체 bounds 중심이 아니다. 회전 후 가장 뒤쪽 끝(카메라 주변 테두리)이 Z≈0,
  AABB 중심은 (0,0,6.5)다. 일반 back plate 외면은 +2.3, 내면은 +3.8.
  전면 lip 안쪽은 +12, 바깥쪽 끝은 +13 부근이다.

## 축과 −9 mm의 의미

정립한 phone의 화면 쪽에서 보는 기준으로 anchor +X는 오른쪽, +Y는 위, +Z는 화면 쪽이다.
−Z는 후면/카메라 쪽이다. Case의 회전 전 mesh 축은 +X→anchor +X, +Y→anchor −Z,
+Z→anchor +Y로 대응한다. Case의 authored −Y가 화면 쪽이 된다.

`p_anchor = t + R * p_case`다. translation은 회전 후 부모 좌표로 더한다.
따라서 `(0,0,−0.009)`는 anchor −Z로 9 mm 이동시킨다.
0으로 되돌리면 baseline에서 anchor +Z(화면 쪽)로 9 mm 돌아온다.
반대 방향으로 이동시키는 조작은 **부모 기준 translation.z를 늘리는 것**이다.
Case 자신의 회전 후 local Z 방향으로 옮기는 조작과 구분한다.

## Bounds 중심 대신 접촉면으로 계산

삼각형과 두께 방향 ray의 교차를 이용하여 Phone의 일반 후면과 Case 내부 후면을 조사했다.
anchor XY=(0,−60),(20,−40),(−20,0),(0,0),(0,25) mm 등의 지점에서
Phone 후면은 Z=−3.975, Case 내부 후면은 Z=+3.800이다.
Case의 일반 후판 두께는 3.800−2.300=1.500 mm다.

내부 후면을 Phone 후면에 맞추는 translation은 다음과 같다.

```text
z_case = phone_back − case_inner_back
       = −3.975 − 3.800
       = −7.775 mm
```

제조 공차·압입·재질의 유연성을 제외한 mesh 접촉 예측이며, 실기기 최적값이라는 단정은 아니다.

추가 geometry 확인:

- 내부 영역을 3 mm 격자로 조사한 후면 ray에서 가장 엄격한 접촉값은 약 −7.775025 mm,
  중앙값은 −7.775 mm였다. 카메라 개구부에서는 없는 면을 보완해서 계산하지 않았다.
- 두 후면 렌즈 중심 부근 (X,Y)≈(22.104,43.465),(22.104,61.185) mm에서 Case의 두께 방향
  ray는 mesh와 교차하지 않는다. 카메라 개구부의 좌우/상하 배치가 맞는다.
  카메라 주변도 몇 지점 확인했으나 전 표면의 엄밀한 collision 검사는 아니다.
- 일반 측벽 단면의 Case 내폭은 71.700 mm, 본체 폭(버튼 제외)은 약 71.451 mm다.
  상단 내벽 Y≈74.900에 대해 Phone 상단은 74.805다. 큰 X/Y 이동이 필요하다는 근거는 없다.
  버튼·USB 개구부·모서리를 하나의 직육면체로 취급하지 않았다.
- Geometry 후보의 Case lip 안쪽은 Z≈4.225, 바깥쪽 끝은 5.225다.
  Phone 전면 3.975에 비해 각각 약 0.250 mm, 1.250 mm 앞에 나온다.
- 카메라를 포함한 AABB 중심을 기계적으로 맞추면 Z≈−8.225로, 후면 접촉값과 다르다.

## 실기기 후보: 3개

전 후보에서 RCP의 rotation X=−90°, scale=1, translation X/Y=0을 유지한다.

| 후보 | 부모 기준 Z | 일반 Case 내부 후면 Z | Phone 후면과의 관계 | lip 끝 Z |
|---|---:|---:|---|---:|
| Baseline | −9.000 | −5.200 | 1.225 mm 후면 쪽 간격 | 4.000 |
| No offset | 0.000 | 3.800 | 후면 접촉 위치보다 7.775 mm 화면 쪽 | 13.000 |
| Geometry | −7.775 | −3.975 | 일반 후면이 접촉하는 예측 | 5.225 |

Baseline의 lip 끝은 화면과 거의 같은 높이지만 후면은 떨어진다.
No offset은 translation의 의미를 직접 보는 비교 기준이다.
Geometry는 후면 접촉에서 도출했으며 baseline에서 +1.225 mm 차이가 난다.
세부 후보를 늘릴 근거가 없어 fine-tuning 후보는 추가하지 않는다.

Diagnostic iPhone은 학습 source와 같은 origin/geometry를 쓰므로 그대로 겹치는 구성이다.
Case는 origin과 내부 공간이 다르므로, Diagnostic에 offset이 필요하지 않다는 사실만으로
Case도 offset 0이 맞다고 판단할 수 없다.

## 구현과 실기기 순서

1. Vision Pro에서 Build & Run. `Orange Case · Static alignment`를 선택하고 ImmersiveSpace를 연다.
2. iPhone을 고정하고 Orange Case가 표시되면 Case alignment Picker로 세 후보를 전환한다.
3. 같은 자세에서 외곽·모서리·카메라 홀을 비교하고, 조금 비스듬히/측면에서 앞뒤 들뜸과 lip을 본다.
4. 가장 자연스럽게 감싸는 후보 이름을 기록한다. 흔들림 크기로 평가하지 않는다.
5. 이전 진단은 ImmersiveSpace를 닫고 실험 Picker에서 선택한다. 기존 A/B와 10초 측정을 보존했다.

후보 전환은 동일한 Case Entity의 local transform만 즉시 바꾼다.
ObjectAnchor/추적 Entity/계층/세션/HFR/referenceobject는 바꾸지 않는다.
Static 모드에서는 기존 measurement에 이벤트를 전달하지 않고 Device pose 진단 polling도 시작하지 않는다.
ObjectTrackingManager 본체와 provider 구성은 변경하지 않았다.

알 수 있는 것: 이 asset·실물·표시 조건에서 세 후보 중 어느 것이 자연스럽게 밀착되어 보이는지.
알 수 없는 것: jitter 원인/개선, 물리적 절대 정확도, 전체 geometry의 제조 적합성/공차,
모든 각도에서의 카메라·버튼·모서리 일치. Z 변경만으로 shape 차이나 국소적인 X/Y 불일치는 고칠 수 없다.

원본 asset/RCP/기존 진단 계산 로직을 보호하며 commit/push/branch 변경은 하지 않는다.

## 마지막 Perceptual fine-tuning 단계 — 결과 미정

위 초기 3후보 실험을 보존하고, 기존 Picker에 두 후보만 추가했다.

- Fine Tune · Z −7.275 mm: Geometry control에서 화면 방향으로 +0.5 mm.
- Fine Tune · Z −6.775 mm: Geometry control에서 화면 방향으로 +1.0 mm.

Geometry −7.775 mm는 기존 후면 접촉 계산의 control이며, 추가값은 새로운 geometry 정답이 아니다.
이번 핵심 비교는 Geometry / Fine Tune 두 값 / No offset 0 mm이고, Baseline −9 mm도 유지한다.
동일 Case의 부모 기준 Z translation만 바꾸며 회전·scale·X/Y·계층·tracking·측정 로직은 유지한다.
정지 시 Static Fit과 움직일 때 Motion Perception을 따로 평가한다. 후자는 tracking accuracy 측정이 아니다.
실기기 비교 전이므로 최종 선택과 결과는 미정이다.

## 마지막 Perceptual fine-tuning 단계 — 최종 결과

초기 3후보 실험 이후, Geometry control을 기준으로 화면 방향(+Z)으로 이동한
두 개의 Perceptual fine-tuning 후보를 추가하여 Vision Pro 실기기에서 비교했다.

- Geometry · Z −7.775 mm: 후면 접촉 geometry 계산값.
- Fine Tune · Z −7.275 mm: Geometry control에서 화면 방향으로 +0.5 mm.
- Fine Tune · Z −6.775 mm: Geometry control에서 화면 방향으로 +1.0 mm.
- No Offset · Z 0 mm: offset이 없는 비교 기준.
- Baseline · Z −9.000 mm: 기존 RCP 값으로 Picker에 보존.

실기기 비교 결과 **Fine Tune · Z −6.775 mm가 최종적으로 가장 자연스러웠다.**

따라서 SpatialCase의 Orange Case static alignment 최종값은:

**Z = −6.775 mm**

로 선택한다.

이 값은 새로운 geometry 계산값이 아니다.
Geometry에서 계산된 후면 접촉 기준은 계속 **Z = −7.775 mm**이며,
최종 −6.775 mm는 해당 control에서 화면 방향으로 **+1.0 mm** 이동한
Vision Pro 실기기 기반의 perceptual calibration 결과다.

실기기에서는 Case의 정적인 밀착감뿐 아니라 iPhone을 기울이고 회전하거나 이동시킬 때의
시각적 자연스러움도 함께 비교했으며, −6.775 mm가 두 측면의 균형에서 가장 자연스럽게 보였다.

이 결과는 Case의 parent-space Z translation에 대한 시각적 calibration 결과이며,
Object Tracking 자체의 정확도나 ObjectAnchor의 temporal stability가 개선되었다는 의미는 아니다.
후보 전환 동안 ObjectAnchor, trackedEntity, HFR, referenceobject, rotation, scale,
X/Y translation 및 hierarchy는 동일하게 유지했다.

이 값으로 Static Alignment 실험을 종료하며 추가적인 Z fine-tuning 후보는 만들지 않는다.
