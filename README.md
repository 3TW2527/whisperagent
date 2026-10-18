# WhisperLectures 🎙️📚

A native macOS app for organising study notes by **course → lecture**, transcribing lecture recordings on-device with Whisper, and laying everything out in a folder that **AI assistants such as Claude, ChatGPT/Codex, Gemini and NotebookLM can read and answer questions about**.

---

## Key Features

### Courses, Lectures and Recordings
- **Courses** have a name, an optional code (e.g. `CS101`) and **tags** for filtering, e.g. `semester-1`, `maths`. Filter the sidebar by tag, or search names, codes, tags and lecture titles.
- **Lectures** are numbered automatically within a course (L01, L02, ...), with an editable **date and time** and an optional title.
- **Materials** (slides, PDFs, readings, notes) belong to the course and are shared by all its lectures.
- **Recordings**: a lecture can have several transcribed recordings, named automatically as `<Course>_L03_R1`, `<Course>_L03_R2`, and so on. You can override the name when you start a transcription.

### Parallel, On-Device Transcription
- Built on [Argmax WhisperKit](https://github.com/argmaxinc/WhisperKit), so it runs entirely on the Mac, accelerated by the Apple Neural Engine. There's no Python and nothing is uploaded.
- **Run several transcriptions at once.** Set the limit (1–4) in Settings. Extra jobs wait in a visible queue, and each job can be cancelled, retried or dismissed.
- Recording numbers are reserved when a job is queued, so parallel jobs for the same lecture never collide.
- **Waveform trimmer** with automatic silence detection. Whisper can hallucinate on long leading silence, so the app can skip it.
- Works with Voice Memos (drag recordings straight in) and iCloud Drive.

### Output Formats
- **Markdown** (`.md`): a YAML metadata header plus timestamped paragraphs. Best for LLMs.
- **Plain text** (`.txt`)
- **SubRip subtitles** (`.srt`)
- **WebVTT subtitles** (`.vtt`)

Choose which formats are written automatically in Settings. Timing data is kept for every transcript, so you can export any recording to another format later.

### Organised for AI Assistants
The app maintains a predictable folder layout plus generated guide files:

```text
<Library root>/
  INDEX.md                    All courses: tags, lecture counts, latest dates, links
  AGENTS.md                   Layout and citation rules (read by Codex, Antigravity and other agents)
  CLAUDE.md                   Same guide, read automatically by Claude Code
  GEMINI.md                   Same guide, read by Gemini CLI / Antigravity
  <Course folder>/
    COURSE.md                 Lecture table (number, title, date, transcript links) and materials list
    course.json               Machine-readable course, lecture and recording metadata
    materials/                Slides, PDFs, notes for the whole course
    transcripts/
      <Course>_L03_R1.md      Lecture 3, recording 1
      <Course>_L03_R1.srt     (optional extra formats)
    .whisperlectures/         Timing data used for re-exporting (hidden)
```

- Generated files start with a marker comment. **Delete that first line to take ownership** of a file, and the app won't overwrite it again.
- Files are only rewritten when their content changes, which keeps iCloud sync quiet.

### "Ask an AI" Guide
A built-in page (toolbar ✨, or the button on each course) shows how to use your library with:
- **Claude Code**, the **Claude desktop app** (Cowork) and **claude.ai Projects**
- **OpenAI Codex CLI** and **ChatGPT Projects**
- **Google Antigravity CLI / Gemini CLI** and **NotebookLM**
- **Any agent that reads `AGENTS.md`**

The page fills your library or course path into ready-to-copy commands and suggests questions to start with. Chat apps that only accept uploads get an **Export Study Bundle** button, which combines a course's transcripts into a single Markdown file.

### Migrating From the Old Layout
Earlier versions used one folder per lecture. On launch, the app finds those folders and offers a guided migration. For each folder you pick a course, or skip it. It becomes a numbered lecture in that course: transcripts are renamed to the course scheme and other files move to the course's materials. Nothing moves until you confirm.

---

## How to Open and Run

### In Xcode
```bash
open WhisperLectures.xcodeproj
```
Select the `WhisperLectures` scheme and press **Cmd + R**.

### Build Script
```bash
./build.sh      # builds WhisperLectures.app into the project root
./package.sh    # creates a distributable zip
```

If [XcodeGen](https://github.com/yonaskolb/XcodeGen) is installed, `build.sh` regenerates the Xcode project from `project.yml` first. Run `xcodegen generate` yourself after adding or removing source files.

---

## Project Structure

```text
Sources/
├── WhisperLecturesApp.swift            App entry point & menu commands
├── Models/
│   ├── Course.swift                    Course, Lecture, RecordingInfo, RecordingGroup
│   ├── TranscriptFile.swift            Transcript file on disk (md/txt/srt/vtt)
│   ├── LectureFile.swift               Course material file
│   ├── TranscriptionJob.swift          Queued/running job state
│   ├── AudioAnalysisResult.swift       Waveform & silence detection result
│   └── AppSettings.swift               Root folder, formats, concurrency, model
├── Services/
│   ├── CourseStorageService.swift      Course/lecture CRUD, recording reservations, export, migration
│   ├── WhisperTranscriptionService.swift  Parallel job queue, WhisperKit instance pool, model downloads
│   ├── TranscriptFormatter.swift       Markdown / text / SRT / VTT rendering from timed segments
│   ├── LibraryIndexGenerator.swift     INDEX.md, COURSE.md, AGENTS.md / CLAUDE.md / GEMINI.md
│   ├── StudyBundleExporter.swift       Single-file course bundle for upload-based chat apps
│   ├── AudioProcessingService.swift    Waveform analysis & trimming
│   └── VoiceMemosService.swift         Voice Memos & audio file picker helpers
└── Views/
    ├── MainView.swift                  Sidebar (courses, tag filter), sheets, audio queue
    ├── CourseDetailView.swift          Course header, audio drop bar, Lectures/Materials tabs
    ├── LecturesView.swift              Lecture list, lecture detail, recording viewer & export
    ├── EditorSheets.swift              New/edit course and lecture sheets, tag chips
    ├── AudioTrimmerSheet.swift         Trimmer + lecture/name/model selection
    ├── JobsPanelView.swift             Transcription queue panel
    ├── AskAIView.swift                 "Ask an AI" provider guides & bundle export
    ├── MigrationSheet.swift            Old-layout migration
    ├── FileAttachmentsView.swift       Materials browser (card/list, Quick Look)
    ├── QuickLookPreview.swift          QLPreviewView wrapper
    ├── SettingsView.swift              Storage, formats, concurrency, models
    └── Components/WaveformView.swift   Draggable waveform trimmer
```

## Privacy

Audio is transcribed locally and never uploaded. The app doesn't send your notes anywhere. The "Ask an AI" page only shows instructions, and you choose whether and where to share your files.
