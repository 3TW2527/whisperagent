# WhisperLectures 🎙️📚

A native macOS app for organising study notes by **course → lecture**, transcribing lecture recordings on-device with Whisper, and laying everything out in a folder that **AI assistants such as Claude, ChatGPT/Codex, Gemini and Gemini Notebook can read and answer questions about**.

---

## Key Features

### Courses, Lectures and Recordings
- **Courses** have a name, an optional code (e.g. `CS101`) and **tags** for filtering, e.g. `semester-1`, `maths`. Filter the sidebar by tag, or search names, codes, tags and lecture titles.
- **Lectures** are numbered automatically within a course (L01, L02, ...), with an editable **date and time** and an optional title.
- **Materials** (slides, PDFs, readings, notes) belong to the course and are shared by all its lectures.
- **Recordings**: a lecture can have several transcribed recordings, named automatically as `<Course>_L03_R1`, `<Course>_L03_R2`, and so on. You can override the name when you start a transcription.

Open a course and the sidebar switches to its **Lectures** and **Documents**. The main area shows a bar of the lecture's transcripts and your notes beside the open item. Use the gear icon (or right-click a course) to edit its name, code and tags, or to store it in a folder other than the library folder. Courses stored elsewhere are marked with a folder icon.

### Home Screen
With no course open, the main area shows the **home screen**. Return to it at any time with the house button in the toolbar, **⇧⌘H**, or the back button in a course's sidebar.
- **Recent Lectures**: the latest lectures across every course, newest first, with each lecture's course, date, recording count, recorded time and note count. Click one to open it. Set how many are shown in Settings (lectures dated after today aren't listed).
- **Tools**: extra features, each opened from a card. New tools are registered in `Sources/Views/Home/HomeTool.swift`. A tool's own settings open from the gear in its header and are also listed under **Settings → Tools**, separate from the general settings.

The library button at the bottom of the sidebar (iCloud Drive / Local) opens the library folder in Finder.

### Canvas
A home-screen tool that lists the files in your Canvas courses and shows what's new. Connect it from the tool's gear with your school's Canvas address and an access token (Canvas → Account → Settings → New Access Token). The token is kept in your keychain and only sees what you can see as a student.
- **Finds hidden files too.** Files come from each course's Files list, its modules, and links in its pages, assignments, discussions, announcements and syllabus, so files still show up when a lecturer hides the Files tab.
- **By Date** groups every course's files by day: Upcoming (not unlocked yet), Today, Yesterday, and so on. A file goes under its newest date, whichever of these is latest: uploaded, changed, unlocked, or first seen by the app. A badge says which (New, Updated, Released, Found). On a course's first sync nothing counts as found, so connecting doesn't make every old file look new.
- **By Course** lists each course's files A–Z or newest first, with the module each file is in.
- **Downloading:** tick files, use **Select All** (its menu can also pick only files not yet downloaded), then **Download**. In the tool's settings you can link a Canvas course to one of your courses, so its files go into that course's materials folder; files from other courses go to Downloads. A file that changes on Canvas shows **Update**, and downloading it again moves the old copy to the Trash. Files already in a linked course's materials folder are recognised: the same name and size counts as downloaded, the same name with another size shows **Update**. Downloads isn't checked this way.
- Syncs when the tool opens, on refresh, and optionally every 15, 30 or 60 minutes while the app is open. The home-screen card shows how many files are new today.

### Markdown Library
A home-screen tool for Markdown files outside your courses. Add folders from the tool, its gear menu, or **Settings → Tools** and it lists every `.md` file in them, subfolders included. Files open in the same editor as course notes, with preview, side-by-side and edit modes, LaTeX, PDF export, and `[[wikilinks]]` between files in the same folder. You can create, rename and delete files there too. Files stay where they are, and edits are saved straight back to them.

### Markdown Notes
Write notes per course from the **Notes** section of the transcript bar. They are plain `.md` files in the course's `notes/` folder. The editor shows a live preview next to the text (or switch to edit-only / preview-only). It supports GitHub-style Markdown, LaTeX math (`$x^2$`, `$$...$$`, `\(...\)`, `\[...\]`, rendered with KaTeX), and Obsidian-style `[[wikilinks]]` to other notes, lectures (`[[Lecture 3]]`) and files; clicking a link to a missing note creates it. **Export PDF** saves a paginated PDF of the rendered note.

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
    materials/                Slides, PDFs, readings for the whole course
    notes/                    Your own Markdown notes
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
- **Google Antigravity CLI / Gemini CLI** and **Gemini Notebook**
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
│   ├── CanvasModels.swift              Canvas API responses, file records, saved sync state
│   ├── TranscriptionJob.swift          Queued/running job state
│   ├── AudioAnalysisResult.swift       Waveform & silence detection result
│   └── AppSettings.swift               Root folder, formats, concurrency, model
├── Services/
│   ├── CourseStorageService.swift      Course/lecture CRUD, recording reservations, export, migration
│   ├── WhisperTranscriptionService.swift  Parallel job queue, WhisperKit instance pool, model downloads
│   ├── TranscriptFormatter.swift       Markdown / text / SRT / VTT rendering from timed segments
│   ├── LibraryIndexGenerator.swift     INDEX.md, COURSE.md, AGENTS.md / CLAUDE.md / GEMINI.md
│   ├── StudyBundleExporter.swift       Single-file course bundle for upload-based chat apps
│   ├── CanvasClient.swift              Canvas REST API: paging, files, modules, pages, downloads
│   ├── CanvasSyncService.swift         Canvas sync, first-seen tracking, downloads into materials
│   ├── KeychainStore.swift             Keychain storage for the Canvas token
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
    ├── Home/CanvasView.swift           Canvas tool: by date / by course, checkboxes, downloads
    ├── Home/CanvasSettingsView.swift   Canvas connection, course links, sync interval
    └── Components/WaveformView.swift   Draggable waveform trimmer
```

## Privacy

Audio is transcribed locally and never uploaded. The app doesn't send your notes anywhere. The Canvas tool only talks to the Canvas site you enter, with your own token. The "Ask an AI" page only shows instructions, and you choose whether and where to share your files.
