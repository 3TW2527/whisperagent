# WhisperLectures 🎙️📚

A native macOS SwiftUI application designed for recording and managing lecture materials, project-by-project.

Each lecture acts as an isolated project folder containing your **Whisper-generated Markdown transcripts** and **associated lecture files** (slides, PDFs, homework, notes).

---

## Key Features

### 1. Project-Centric Lecture Organization
- **1 Lecture = 1 Project Folder** stored in your configured root directory.
- Works seamlessly on local disk or inside **iCloud Drive** (`~/Library/Mobile Documents/com~apple~CloudDocs/WhisperLectures`).
- Transparent folder-based structure: compatible with Finder, Spotlight search, and cloud backup.

### 2. Dual-Method Audio Import (iCloud & Apple Watch / iPhone)
- **Method A: Direct Drag & Drop from Voice Memos**:
  - Recordings from Apple Watch and iPhone automatically sync via iCloud to the macOS Voice Memos app.
  - Simply drag any recording directly from the macOS **Voice Memos** app window into the lecture window!
- **Method B: Native iCloud Drive File Picker**:
  - Click **"Import Audio..."** to open a native Finder sheet pre-configured to your iCloud Drive directory.

### 3. Waveform Audio Trimmer & Silence Bug Fix
- **Silence Bug Solution**: Whisper can hallucinate or fail when audio begins with several minutes of dead silence.
- The app generates a visual waveform and provides:
  - **"Auto-Trim Initial Silence"**: Detects speech onset using energy thresholding and jumps past leading dead air.
  - **Visual Dual-Handle Range Trimmer**: Drag Start and End markers to transcribe only the relevant portion.
  - **Live Audio Preview**: Play/Pause with scrubber to verify speech boundaries before transcribing.

### 4. Zero-Audio Retention Policy
- Audio files are trimmed in temporary scratch storage during transcription.
- Once transcription completes, the resulting formatted Markdown (`transcript.md`) is saved directly into the lecture folder, and the **temporary audio file is immediately deleted**.
- Keeps disk and iCloud storage minimal.

### 5. Native Apple Silicon Whisper (WhisperKit)
- Built with [Argmax WhisperKit](https://github.com/argmaxinc/WhisperKit) — 100% native Swift, hardware-accelerated on the **Apple Neural Engine (ANE)** and GPU.
- **No Python runtime or virtual environments required**.
- Integrated Model Downloader & Switcher in Settings and the Trimmer:
  - `openai_whisper-tiny` (~75 MB)
  - `openai_whisper-base` (~140 MB, Recommended)
  - `openai_whisper-small` (~460 MB)
  - `distil-whisper_distil-large-v3` (~1.5 GB)
  - `openai_whisper-large-v3-turbo` (~1.6 GB)

### 6. Lecture File Management & Quick Look
- Drag & drop lecture slides (PDF, PPTX, Keynote) and notes into the project.
- Automatically copies files into the lecture directory.
- Press **Spacebar** or double-click to invoke native macOS **Quick Look** previews.

---

## How to Open and Run

### In Xcode
Double click `WhisperLectures.xcodeproj` or run:
```bash
open WhisperLectures.xcodeproj
```
Select the `WhisperLectures` scheme and press **Cmd + R** to run.

### Via Command Line
```bash
xcodebuild -project WhisperLectures.xcodeproj -scheme WhisperLectures -destination "platform=macOS,arch=arm64" build
```

---

## Project Structure

```text
WhisperLectures/
├── WhisperLectures.xcodeproj      # Generated Xcode project
├── project.yml                    # XcodeGen project specification
├── Package.swift                  # Swift Package manifest
├── Sources/
│   ├── WhisperLecturesApp.swift   # App entry point & main commands
│   ├── Models/
│   │   ├── LectureProject.swift   # Folder & lecture metadata
│   │   ├── LectureFile.swift      # Dropped attachments (PDF, PPTX, etc.)
│   │   ├── TranscriptFile.swift   # Markdown transcript representations
│   │   ├── AudioAnalysisResult.swift # Waveform & silence timestamps
│   │   └── AppSettings.swift      # Root save path & user preferences
│   ├── Services/
│   │   ├── ProjectStorageService.swift # Folder CRUD & file copying
│   │   ├── AudioProcessingService.swift # RMS waveform & audio trimming
│   │   ├── WhisperTranscriptionService.swift # WhisperKit model management & inference
│   │   └── VoiceMemosService.swift # Voice Memos app & iCloud picker helpers
│   └── Views/
│       ├── MainView.swift         # SplitView sidebar & lecture coordinator
│       ├── ProjectDetailView.swift # Lecture header, audio dropzone, tabs
│       ├── AudioTrimmerSheet.swift # Interactive waveform trimmer & transcribe modal
│       ├── TranscriptsView.swift  # Markdown transcript reader & search
│       ├── FileAttachmentsView.swift # File dropzone & Quick Look cards
│       ├── QuickLookPreview.swift # QLPreviewView AppKit wrapper
│       ├── SettingsView.swift     # Storage path picker & model manager
│       └── Components/
│           └── WaveformView.swift # Custom canvas waveform with draggable handles
└── plan.txt                       # Architecture & design document
```
