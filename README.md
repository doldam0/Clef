# Clef

> iPad 전용 악보 뷰어 — Apple-native 필기 도구와 on-device AI 음표 인식

[![Platform](https://img.shields.io/badge/platform-iPadOS%2018+-blue)](https://developer.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](LICENSE)

---

## 왜 Clef인가

기존 악보 앱(forScore, Newzik, Piascore 등)은 모두 **자체 필기 엔진**을 사용한다. Apple Pencil Pro 제스처를 지원하는 악보 앱은 **단 하나도 없다.** AI로 악보를 분석하는 앱도 Newzik LiveScore 하나뿐이며, 이마저도 클라우드 기반이라 오프라인 사용이 불가능하다.

Clef는 이 세 가지 공백을 동시에 채운다:

| 기존 앱의 한계 | Clef의 접근 |
|---|---|
| 자체 필기 엔진 → 투박한 필기감 | **PencilKit** — Apple 메모 앱과 동일한 필기 도구 |
| Apple Pencil Pro 미지원 | **Squeeze, Barrel Roll, Haptic Feedback** 완전 지원 |
| AI 미지원 or 클라우드 의존 | **On-device Core ML** — 오프라인 OMR |

---

## 핵심 기능

### 1. Apple-Native 필기 도구

PencilKit 기반으로 Apple 메모 앱과 **동일한 필기 경험**을 제공한다.

**기본 필기 도구** (PKToolPicker):
- 펜 (`.pen`) — 균일한 두께의 잉크
- 연필 (`.pencil`) — 압력 감지, 텍스처 표현
- 마커 (`.marker`) — 반투명, Barrel Roll 지원
- 만년필 (`.fountainPen`) — 캘리그래피, Barrel Roll 지원
- 모노라인 (`.monoline`) — 압력 무관 균일 두께
- 지우개 (`.bitmap`, `.vector`) — 픽셀/스트로크 단위 삭제
- 올가미 (`.lasso`) — 필기 선택 및 이동
- 눈금자 (`.ruler`) — 직선 가이드

**커스텀 악보 도구** (PKToolPickerCustomItem, iOS 18+):
- 악상 기호 팔레트 (f, p, ff, pp, sfz, crescendo, decrescendo 등)
- 아티큘레이션 (스타카토, 테누토, 악센트, 페르마타 등)
- 음표/쉼표 스탬프 (온음표~64분음표, 점음표)
- 연주 기호 (트릴, 턴, 모르덴트, 글리산도 등)
- 반복/구조 기호 (리허설 마크, 코다, 세뇨 등)

### 2. Apple Pencil Pro 완전 지원

| 제스처 | 동작 | API |
|---|---|---|
| **Squeeze** | 악상 기호 팔레트 호출 | `UIPencilInteraction.Squeeze` |
| **Barrel Roll** | 마커/만년필 각도 조절 | `UITouch.rollAngle` |
| **Haptic Feedback** | 스냅/정렬 시 진동 피드백 | `UICanvasFeedbackGenerator` |
| **Hover** | 필기 전 미리보기 | `UIHoverGestureRecognizer` |
| **Double Tap** | 도구 전환 (사용자 설정 존중) | `UIPencilInteraction.preferredTapAction` |

**Squeeze → 통합 팔레트 흐름:**
1. Apple Pencil Pro를 쥐어 짜면 (`squeeze.phase == .ended`)
2. 펜슬 hover 위치에 **통합 컨텍스트 팔레트** 표시 (`squeeze.hoverPose?.location`)
3. 팔레트 상단 세그먼트 탭: `[악상 기호 | 필기 도구]`
   - **악상 기호 탭**: 다이나믹, 아티큘레이션, 음표/쉼표 스탬프 등
   - **필기 도구 탭**: 펜/연필/마커 종류, 색상, 두께 빠른 전환
4. 기본 탭은 사용자 설정에서 변경 가능 (설정 > 팔레트 > 기본 탭)
5. 마지막 사용 탭을 기억하는 옵션도 제공
6. 사용자 시스템 설정이 `showContextualPalette`일 때만 작동 (시스템 설정 존중)

### 3. On-Device AI 음표 인식

스캔된 PDF 악보에서 **음악 기호를 자동으로 감지**한다. 모든 처리는 디바이스에서 수행되어 **오프라인에서도 동작**한다.

**기술 스택:**
- **모델**: YOLOv8 → Core ML 변환
- **추론**: Vision Framework (`VNCoreMLRequest`)
- **학습 데이터**: 사전 훈련된 OMR 모델 (7,000+ 이미지, 500K+ 바운딩 박스)

**감지 가능한 기호:**
- 음표 (온음표 ~ 64분음표, 점음표, 묶음)
- 쉼표 (온쉼표 ~ 64분쉼표)
- 음자리표 (높은음자리표, 낮은음자리표, 가온음자리표)
- 조표, 박자표
- 아티큘레이션, 다이나믹 기호
- 이음줄, 붙임줄, 셋잇단음표 등

**사용자 워크플로우:**
1. PDF 악보를 가져온다
2. "분석" 버튼으로 OMR 실행 → 기호별 바운딩 박스 생성
3. 감지된 기호를 탭하여 삭제/수정/이동
4. 팔레트에서 새 기호를 드래그하여 추가
5. 수정 사항은 오버레이 레이어로 저장 (원본 PDF 보존)

### 4. PDF 악보 관리

**뷰어:**
- PDFKit 기반 고성능 렌더링
- 페이지별 PencilKit 오버레이 (투명 PKCanvasView)
- 연속 스크롤 / 페이지 넘기기 모드
- 양면 보기 (랜드스케이프)
- AirTurn 등 블루투스 페달 페이지 넘기기

**라이브러리:**
- 폴더/태그 기반 정리
- Spotlight 검색 연동
- 메타데이터 (작곡가, 조성, 박자, 악기 등)
- iCloud Drive 동기화

---

## 아키텍처

### 기술 스택

| 레이어 | 기술 | 비고 |
|---|---|---|
| **UI** | SwiftUI + UIKit 브릿지 | PencilKit은 UIKit 기반, SwiftUI로 래핑 |
| **PDF 렌더링** | PDFKit (`PDFView`) | 네이티브 PDF 렌더링 |
| **필기** | PencilKit (`PKCanvasView`) | PDF 페이지별 오버레이 |
| **도구** | PencilKit (`PKToolPicker`) | 커스텀 아이템 포함 |
| **AI/ML** | Core ML + Vision | YOLOv8 기반 OMR 모델 |
| **데이터** | SwiftData | 악보 메타데이터, 설정 |
| **필기 저장** | PKDrawing (Codable) | 페이지별 직렬화 |
| **동기화** | CloudKit (iCloud) | 악보 + 필기 동기화 |

### 레이어 구성

```
┌─────────────────────────────────────────────┐
│                 Clef App                     │
├─────────────────────────────────────────────┤
│  Presentation Layer (SwiftUI)               │
│  ├── ScoreLibraryView     (악보 목록)        │
│  ├── ScoreReaderView      (악보 뷰어)        │
│  │   ├── PDFPageView      (PDF 렌더링)       │
│  │   ├── CanvasOverlay    (PencilKit 필기)   │
│  │   └── SymbolPalette    (악상 기호 팔레트)  │
│  └── SettingsView         (설정)             │
├─────────────────────────────────────────────┤
│  Domain Layer                                │
│  ├── ScoreManager         (악보 CRUD)        │
│  ├── AnnotationManager    (필기 관리)         │
│  ├── OMREngine            (음표 인식)         │
│  └── SymbolLibrary        (악상 기호 DB)      │
├─────────────────────────────────────────────┤
│  Infrastructure Layer                        │
│  ├── PDFService           (PDFKit 래퍼)      │
│  ├── MLService            (Core ML 래퍼)     │
│  ├── StorageService       (SwiftData)        │
│  └── CloudService         (CloudKit)         │
└─────────────────────────────────────────────┘
```

### PDF + PencilKit 오버레이 구조

```
┌─────────────────────────────────┐
│       ScoreReaderView           │
│  ┌───────────────────────────┐  │
│  │        PDFView            │  │
│  │  ┌─────────────────────┐  │  │
│  │  │     PDF Page 1      │  │  │
│  │  │  ┌───────────────┐  │  │  │
│  │  │  │ PKCanvasView  │  │  │  │  ← 투명 오버레이 (필기)
│  │  │  │   (overlay)   │  │  │  │
│  │  │  └───────────────┘  │  │  │
│  │  └─────────────────────┘  │  │
│  │  ┌─────────────────────┐  │  │
│  │  │     PDF Page 2      │  │  │
│  │  │  ┌───────────────┐  │  │  │
│  │  │  │ PKCanvasView  │  │  │  │
│  │  │  │   (overlay)   │  │  │  │
│  │  │  └───────────────┘  │  │  │
│  │  └─────────────────────┘  │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │      PKToolPicker         │  │  ← 하단 도구 막대
│  │  [펜][연필][마커]...       │  │
│  │  [♩ 음표][𝆑 기호]        │  │  ← 커스텀 악보 도구
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### OMR 파이프라인

```
PDF Page Image
     │
     ▼
┌──────────────┐
│ Preprocessing │  → 이진화, 노이즈 제거, 기울기 보정
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  YOLOv8 Model │  → Core ML 추론 (VNCoreMLRequest)
│  (on-device)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Post-process │  → NMS, 바운딩 박스 → 기호 분류
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Symbol Layer  │  → 편집 가능한 기호 오버레이
└──────────────┘
```

---

## 데이터 모델

### Score (악보)

```swift
@Model
class Score {
    var id: UUID
    var title: String
    var composer: String?
    var instrument: String?
    var key: String?            // 조성 (예: "C Major")
    var timeSignature: String?  // 박자 (예: "4/4")
    var tags: [String]
    var pdfData: Data           // PDF 원본
    var pageAnnotations: [PageAnnotation]  // 페이지별 필기
    var createdAt: Date
    var updatedAt: Date
}
```

### PageAnnotation (페이지 필기)

```swift
@Model
class PageAnnotation {
    var pageIndex: Int
    var drawingData: Data       // PKDrawing 직렬화
    var symbolOverlays: [SymbolOverlay]  // OMR 감지/사용자 추가 기호
}
```

### SymbolOverlay (악보 기호 오버레이)

```swift
struct SymbolOverlay: Codable {
    var id: UUID
    var type: MusicSymbolType   // 음표, 쉼표, 다이나믹 등
    var boundingBox: CGRect     // 위치 및 크기
    var isDetected: Bool        // OMR 감지 vs 사용자 추가
    var isDeleted: Bool         // 소프트 삭제 (원본 보존)
}
```

### MusicSymbolType (악보 기호 분류)

```swift
enum MusicSymbolType: String, Codable {
    // 음표
    case wholeNote, halfNote, quarterNote, eighthNote, sixteenthNote
    case dottedHalfNote, dottedQuarterNote, dottedEighthNote
    
    // 쉼표
    case wholeRest, halfRest, quarterRest, eighthRest, sixteenthRest
    
    // 음자리표
    case trebleClef, bassClef, altoClef
    
    // 다이나믹
    case pianissimo, piano, mezzoPiano, mezzoForte, forte, fortissimo
    case sforzando, crescendo, decrescendo
    
    // 아티큘레이션
    case staccato, tenuto, accent, fermata, marcato
    
    // 장식음
    case trill, turn, mordent, glissando
    
    // 구조
    case coda, segno, rehearsalMark
    case repeatStart, repeatEnd
}
```

---

## 로드맵

### Phase 1 — 기본 뷰어 (MVP)

- [ ] Xcode 프로젝트 설정 (iPadOS 18+, Swift 6)
- [ ] PDF 가져오기 및 렌더링 (PDFKit)
- [ ] 페이지별 PencilKit 오버레이
- [ ] PKToolPicker 기본 도구 연동
- [ ] 필기 데이터 저장/불러오기 (SwiftData)
- [ ] 기본 악보 라이브러리 (목록, 폴더)

### Phase 2 — Apple Pencil Pro & 커스텀 도구

- [ ] Apple Pencil Pro Squeeze → 컨텍스트 팔레트
- [ ] Barrel Roll 지원 (마커, 만년필)
- [ ] Haptic Feedback (스냅, 정렬)
- [ ] PKToolPickerCustomItem — 악상 기호 도구
- [ ] 기호 드래그 & 드롭 배치
- [ ] SMuFL 폰트 기반 기호 렌더링

### Phase 3 — On-Device AI (OMR)

- [ ] YOLOv8 OMR 모델 학습 및 Core ML 변환
- [ ] Vision Framework 추론 파이프라인
- [ ] 감지 결과 → SymbolOverlay 매핑
- [ ] 기호 선택/삭제/이동 UI
- [ ] 기호 추가 (팔레트 → 드래그)
- [ ] 전처리 최적화 (Metal Performance Shaders)
- [ ] 악보 메타데이터 자동 감지 (조성, 박자, 작곡가, 제목 등)
  - PDF 첫 페이지 OCR → 제목/작곡가 추출 (Vision `VNRecognizeTextRequest`)
  - OMR 결과에서 조표/박자표 자동 인식 → `key`, `timeSignature` 자동 채우기
  - 사용자 확인 후 메타데이터 반영 (자동 저장 아님, 제안 UI)

### Phase 4 — 완성도

- [ ] iCloud 동기화 (CloudKit)
- [ ] Spotlight 검색 연동
- [ ] 블루투스 페달 페이지 넘기기
- [ ] 다크 모드 / 세피아 모드
- [ ] 반페이지 넘기기, 양면 보기
- [ ] 내보내기 (PDF with annotations, 이미지)
- [ ] 접근성 (VoiceOver, Dynamic Type)

---

## 요구 사항

- iPadOS 18.0+
- Apple Pencil (1세대 / 2세대 / Pro)
- Xcode 16+
- Swift 6.0

## 라이선스

[Apache License 2.0](LICENSE)
