# Linea

An open-source EPUB reader for iPhone and iPad that reads books aloud using Apple's on-device text-to-speech, with real-time word highlighting so you can follow along.

---

## Features

**Reading**
- Import any EPUB file from Files, iCloud, or any share sheet
- Renders the book's original HTML with proper typography — bold headings, italics, drop caps, justified text
- White, Sepia, and Dark themes
- Font family picker (Georgia, Palatino, Times New Roman, Helvetica, Charter)
- Adjustable font size, line spacing, and margins
- Two-page layout for iPad

**Playback**
- Reads aloud using AVSpeechSynthesizer with the best available on-device voice
- Only Enhanced and Premium quality voices shown — no robotic standard voices
- Personal Voice support (iOS 17+)
- Speed control from 0.5× to 2× — resumes from current word, doesn't restart
- Word-level highlight tracks exactly what's being spoken in real time
- Tap any word to jump playback to that position

**Zen Mode**
- Strips the page away and shows just a window of words centered on what's being read
- Active word is large and blue; surrounding words fade with distance
- Configurable window size (3 – 11 words)

**Library**
- Apple Books-style cover grid
- Saves your position down to the exact word — reopen a book and it picks up where you left off
- Reading progress shown as a percentage on each cover
- Long-press a cover to remove a book

**Layout**
- iPhone: auto-hides the nav bar and controls after 4 seconds, tap anywhere to bring them back
- iPad: persistent chapter sidebar with NavigationSplitView, chapter progress bar at the top

---

## Requirements

- iOS 16.0+ / iPadOS 16.0+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (to regenerate the `.xcodeproj` if needed)

---

## Getting Started

```bash
git clone https://github.com/An65011065/Reader.git
cd Reader
xcodegen generate   # only needed if you modify project.yml
open Linea.xcodeproj
```

Then select your device or simulator and hit Run. No API keys, no accounts, no backend — everything runs on-device.

---

## Project Structure

```
Linea/
├── LineaApp.swift          # app entry point
└── Sources/
    ├── Models/
    │   ├── EPUBBook.swift        # book + chapter model, BookProgress
    │   └── ReadingSettings.swift # AppStorage-backed reading preferences
    ├── Services/
    │   ├── EPUBParser.swift      # ZIP extraction, OPF/NCX/nav parsing
    │   ├── LibraryStore.swift    # per-book JSON persistence, progress tracking
    │   └── SpeechService.swift   # AVSpeechSynthesizer wrapper, voice management
    ├── Views/
    │   ├── LibraryView.swift     # cover grid, document picker
    │   ├── BookReaderContainerView.swift  # iPhone/iPad layout, chrome hide/show
    │   ├── ReaderView.swift      # WKWebView renderer, JS word highlighting
    │   ├── ZenModeView.swift     # focused word-strip reading mode
    │   ├── PlayerControlsView.swift      # floating playback pill
    │   ├── BookChaptersView.swift        # chapter list sheet
    │   └── ReadingSettingsView.swift     # font/theme/spacing controls
    └── Utilities/
        └── AttributedStringHelper.swift  # NSAttributedString helpers for Zen mode
```

---

## How It Works

**EPUB parsing** — EPUBs are ZIP archives. The parser reads `container.xml` to find the OPF package, extracts the spine and manifest, then maps spine items to TOC entries from NCX (EPUB2) or `nav.xhtml` (EPUB3). Each chapter stores both its plain text (used by TTS) and its original HTML (used for rendering).

**Word highlighting** — On playback, `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString` fires with a character range into the utterance string. The range is converted to a word index and passed to the WebView via `evaluateJavaScript`. The JS matches it against DOM spans by normalized text comparison, highlights the span, and scrolls it into view.

**Position saving** — Reading position is stored as a character offset within the chapter text. On reopen, `restorePosition` sets up the speech service state so the highlight shows the right word without auto-playing.

---

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — EPUB/ZIP extraction

---

## Contributing

PRs welcome. The codebase is straightforward SwiftUI — no third-party UI frameworks, no Combine beyond what SwiftUI needs, no backend.

A few areas that would be good to improve:
- Bookmarks and highlights
- Search within a book
- Background audio / Lock Screen controls (MPNowPlayingInfoCenter)
- Better handling of image-heavy EPUBs
- Accessibility / VoiceOver support

---

## License

MIT
