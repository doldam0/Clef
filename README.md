# Clef

> iPad-exclusive sheet music viewer — Apple-native writing tools & on-device AI music notation recognition

[![Platform](https://img.shields.io/badge/platform-iPadOS%2018+-blue)](https://developer.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](LICENSE)

---

## Why Clef?

Existing sheet music apps (forScore, Newzik, Piascore, etc.) all use **custom drawing engines**. Not a single sheet music app supports Apple Pencil Pro gestures. The only app that analyzes sheet music with AI is Newzik LiveScore — and even that is cloud-based, making offline use impossible.

Clef fills all three gaps at once:

| Existing App Limitations | Clef's Approach |
|---|---|
| Custom drawing engine → clunky writing experience | **PencilKit** — same writing tools as Apple Notes |
| No Apple Pencil Pro support | **Squeeze, Barrel Roll, Haptic Feedback** fully supported |
| No AI or cloud-dependent | **On-device Core ML** — offline OMR |

---

## Key Features

### 1. Apple-Native Writing Tools

PencilKit-based, providing the **same writing experience as Apple Notes**.

**Default Writing Tools** (PKToolPicker):
- Pen (`.pen`) — uniform stroke width
- Pencil (`.pencil`) — pressure-sensitive, textured
- Marker (`.marker`) — translucent, Barrel Roll support
- Fountain Pen (`.fountainPen`) — calligraphy, Barrel Roll support
- Monoline (`.monoline`) — pressure-independent uniform width
- Eraser (`.bitmap`, `.vector`) — pixel/stroke-level deletion
- Lasso (`.lasso`) — select and move ink
- Ruler (`.ruler`) — straight line guide

**Custom Music Tools** (PKToolPickerCustomItem, iOS 18+):
- Expression mark palette (f, p, ff, pp, sfz, crescendo, decrescendo, etc.)
- Articulations (staccato, tenuto, accent, fermata, etc.)
- Note/rest stamps (whole note–64th note, dotted notes)
- Performance marks (trill, turn, mordent, glissando, etc.)
- Repeat/structure marks (rehearsal mark, coda, segno, etc.)

### 2. Full Apple Pencil Pro Support

| Gesture | Action | API |
|---|---|---|
| **Squeeze** | Open expression mark palette | `UIPencilInteraction.Squeeze` |
| **Barrel Roll** | Adjust marker/fountain pen angle | `UITouch.rollAngle` |
| **Haptic Feedback** | Vibration on snap/alignment | `UICanvasFeedbackGenerator` |
| **Hover** | Preview before writing | `UIHoverGestureRecognizer` |
| **Double Tap** | Switch tools (respects user settings) | `UIPencilInteraction.preferredTapAction` |

**Squeeze → Unified Palette Flow:**
1. Squeeze the Apple Pencil Pro (`squeeze.phase == .ended`)
2. Display **unified context palette** at pencil hover position (`squeeze.hoverPose?.location`)
3. Palette top segment tabs: `[Expression Marks | Writing Tools]`
   - **Expression Marks tab**: dynamics, articulations, note/rest stamps, etc.
   - **Writing Tools tab**: pen/pencil/marker types, color, thickness quick switch
4. Default tab is configurable in settings (Settings > Palette > Default Tab)
5. Option to remember last-used tab
6. Only activates when user system setting is `showContextualPalette` (respects system settings)

### 3. On-Device AI Music Notation Recognition

Automatically **detects music symbols** from scanned PDF scores. All processing runs on-device, **works offline**.

**Tech Stack:**
- **Model**: YOLOv8 → Core ML conversion
- **Inference**: Vision Framework (`VNCoreMLRequest`)
- **Training Data**: Pre-trained OMR model (7,000+ images, 500K+ bounding boxes)

**Detectable Symbols:**
- Notes (whole note–64th note, dotted notes, beamed)
- Rests (whole rest–64th rest)
- Clefs (treble, bass, alto)
- Key signatures, time signatures
- Articulations, dynamics
- Ties, slurs, triplets, etc.

**User Workflow:**
1. Import a PDF score
2. Run OMR via "Analyze" button → generates bounding boxes per symbol
3. Tap detected symbols to delete/edit/move
4. Drag new symbols from palette to add
5. Modifications saved as overlay layer (original PDF preserved)

### 4. PDF Sheet Music Management

**Viewer:**
- High-performance rendering via PDFKit
- Per-page PencilKit overlay (transparent PKCanvasView)
- Continuous scroll / page flip modes
- Two-page spread (landscape)
- Bluetooth pedal page turning (AirTurn, etc.)

**Library:**
- Folder/tag-based organization
- Spotlight search integration
- Metadata (composer, key, time signature, instrument, etc.)
- iCloud Drive sync

---

## Architecture

### Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| **UI** | SwiftUI + UIKit bridge | PencilKit is UIKit-based, wrapped in SwiftUI |
| **PDF Rendering** | PDFKit (`PDFView`) | Native PDF rendering |
| **Writing** | PencilKit (`PKCanvasView`) | Per-page overlay |
| **Tools** | PencilKit (`PKToolPicker`) | Includes custom items |
| **AI/ML** | Core ML + Vision | YOLOv8-based OMR model |
| **Data** | SwiftData | Score metadata, settings |
| **Drawing Storage** | PKDrawing (Codable) | Per-page serialization |
| **Sync** | CloudKit (iCloud) | Score + drawing sync |

### Layer Structure

```
┌─────────────────────────────────────────────┐
│                 Clef App                     │
├─────────────────────────────────────────────┤
│  Presentation Layer (SwiftUI)               │
│  ├── ScoreLibraryView     (score list)      │
│  ├── ScoreReaderView      (score viewer)    │
│  │   ├── PDFPageView      (PDF rendering)   │
│  │   ├── CanvasOverlay    (PencilKit)       │
│  │   └── SymbolPalette    (expression marks)│
│  └── SettingsView         (settings)        │
├─────────────────────────────────────────────┤
│  Domain Layer                                │
│  ├── ScoreManager         (score CRUD)      │
│  ├── AnnotationManager    (drawing mgmt)    │
│  ├── OMREngine            (note recognition)│
│  └── SymbolLibrary        (symbol DB)       │
├─────────────────────────────────────────────┤
│  Infrastructure Layer                        │
│  ├── PDFService           (PDFKit wrapper)  │
│  ├── MLService            (Core ML wrapper) │
│  ├── StorageService       (SwiftData)       │
│  └── CloudService         (CloudKit)        │
└─────────────────────────────────────────────┘
```

### PDF + PencilKit Overlay Structure

```
┌─────────────────────────────────┐
│       ScoreReaderView           │
│  ┌───────────────────────────┐  │
│  │        PDFView            │  │
│  │  ┌─────────────────────┐  │  │
│  │  │     PDF Page 1      │  │  │
│  │  │  ┌───────────────┐  │  │  │
│  │  │  │ PKCanvasView  │  │  │  │  ← transparent overlay (drawing)
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
│  │      PKToolPicker         │  │  ← bottom toolbar
│  │  [pen][pencil][marker]... │  │
│  │  [♩ notes][𝆑 symbols]    │  │  ← custom music tools
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### OMR Pipeline

```
PDF Page Image
     │
     ▼
┌──────────────┐
│ Preprocessing │  → binarization, noise removal, deskew
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  YOLOv8 Model │  → Core ML inference (VNCoreMLRequest)
│  (on-device)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Post-process │  → NMS, bounding box → symbol classification
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Symbol Layer  │  → editable symbol overlay
└──────────────┘
```

---

## Data Models

### Score

```swift
@Model
class Score {
    var id: UUID
    var title: String
    var composer: String?
    var instrument: String?
    var key: String?            // key signature (e.g. "C Major")
    var timeSignature: String?  // time signature (e.g. "4/4")
    var tags: [String]
    var pdfData: Data           // original PDF
    var pageAnnotations: [PageAnnotation]  // per-page drawings
    var createdAt: Date
    var updatedAt: Date
}
```

### PageAnnotation

```swift
@Model
class PageAnnotation {
    var pageIndex: Int
    var drawingData: Data       // PKDrawing serialized
    var symbolOverlays: [SymbolOverlay]  // OMR-detected / user-added symbols
}
```

### SymbolOverlay

```swift
struct SymbolOverlay: Codable {
    var id: UUID
    var type: MusicSymbolType   // notes, rests, dynamics, etc.
    var boundingBox: CGRect     // position and size
    var isDetected: Bool        // OMR-detected vs user-added
    var isDeleted: Bool         // soft delete (preserves original)
}
```

### MusicSymbolType

```swift
enum MusicSymbolType: String, Codable {
    // Notes
    case wholeNote, halfNote, quarterNote, eighthNote, sixteenthNote
    case dottedHalfNote, dottedQuarterNote, dottedEighthNote
    
    // Rests
    case wholeRest, halfRest, quarterRest, eighthRest, sixteenthRest
    
    // Clefs
    case trebleClef, bassClef, altoClef
    
    // Dynamics
    case pianissimo, piano, mezzoPiano, mezzoForte, forte, fortissimo
    case sforzando, crescendo, decrescendo
    
    // Articulations
    case staccato, tenuto, accent, fermata, marcato
    
    // Ornaments
    case trill, turn, mordent, glissando
    
    // Structure
    case coda, segno, rehearsalMark
    case repeatStart, repeatEnd
}
```

---

## Roadmap

### Phase 1 — Basic Viewer (MVP)

- [x] Xcode project setup (iPadOS 18+, Swift 6)
- [x] PDF import & rendering (PDFKit)
- [x] Per-page PencilKit overlay
- [x] PKToolPicker default tool integration
- [x] Drawing data save/load (SwiftData)
- [x] Basic score library (list, folders)
- [x] Score metadata editor (key, time signature, tags)
- [x] Tag-based filtering
- [x] Localization (English / Korean)

### Phase 2 — Apple Pencil Pro & Custom Tools

- [ ] Apple Pencil Pro Squeeze → context palette
- [ ] Barrel Roll support (marker, fountain pen)
- [ ] Haptic Feedback (snap, alignment)
- [ ] PKToolPickerCustomItem — expression mark tools
- [ ] Symbol drag & drop placement
- [ ] SMuFL font-based symbol rendering

### Phase 3 — On-Device AI (OMR)

- [ ] YOLOv8 OMR model training & Core ML conversion
- [ ] Vision Framework inference pipeline
- [ ] Detection results → SymbolOverlay mapping
- [ ] Symbol select/delete/move UI
- [ ] Symbol addition (palette → drag)
- [ ] Preprocessing optimization (Metal Performance Shaders)
- [ ] Auto-detect score metadata (key, time signature, composer, title, etc.)
  - OCR first PDF page → extract title/composer (Vision `VNRecognizeTextRequest`)
  - Recognize key/time signatures from OMR results → auto-fill `key`, `timeSignature`
  - Apply metadata after user confirmation (suggestion UI, not auto-save)

### Phase 4 — Polish

- [ ] iCloud sync (CloudKit)
- [ ] Spotlight search integration
- [ ] Bluetooth pedal page turning
- [ ] Dark mode / sepia mode
- [ ] Half-page turning, two-page spread
- [ ] Export (PDF with annotations, images)
- [ ] Accessibility (VoiceOver, Dynamic Type)

---

## Requirements

- iPadOS 18.0+
- Apple Pencil (1st gen / 2nd gen / Pro)
- Xcode 16+
- Swift 6.0

## License

[Apache License 2.0](LICENSE)
