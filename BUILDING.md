# Building WhisperLectures

WhisperLectures is built from source on your own Mac. One script checks your setup and builds the app.

## Requirements

| | |
|---|---|
| **Mac** | Apple silicon (M1 or later) recommended. Intel Macs can build it, but transcription is much slower. |
| **macOS** | 14 (Sonoma) or later |
| **Xcode** | 16 or later, the full app from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835). The Command Line Tools alone aren't enough. |
| **Disk space** | About 5 GB for packages and build files |
| **Internet** | For the first build, which downloads [WhisperKit](https://github.com/argmaxinc/WhisperKit) from GitHub |

After installing Xcode, open it once so it can finish installing its components and you can accept its licence.

## Quick Start

```bash
git clone <repository URL> WhisperLectures
cd WhisperLectures
./build.sh
```

The script checks your Mac, downloads the Swift packages, builds the app in Release mode and saves `WhisperLectures.app` in the project folder. Open it with:

```bash
open WhisperLectures.app
```

The first build takes several minutes. Later builds only recompile what changed.

## Options

```bash
./build.sh --check     # only check that your Mac is ready to build
./build.sh --install   # build, then copy the app to /Applications
./build.sh --open      # build, then open the app
./build.sh --clean     # delete previous build output first, for a fresh build
./build.sh --help      # list the options
```

Options can be combined, for example `./build.sh --install --open`.

## What the Script Checks

| Check | If it fails |
|---|---|
| macOS 14 or later | Update macOS. |
| Full Xcode installed and selected | Install Xcode from the Mac App Store. If it's installed but the Command Line Tools are selected, run `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`. |
| Xcode 16 or later | Update Xcode. |
| Xcode licence accepted | Run `sudo xcodebuild -license accept`, or open Xcode once. |
| Xcode first-launch setup done | Run `sudo xcodebuild -runFirstLaunch`, or open Xcode once. |
| github.com reachable (first build only) | Connect to the internet. Only a warning: packages already downloaded are reused. |
| Free disk space | Only a warning below 5 GB. |

The build's full output goes to `build/build.log`. When something fails, the script shows the errors and where the log is.

## Building in Xcode Instead

```bash
open WhisperLectures.xcodeproj
```

Choose the `WhisperLectures` scheme and **My Mac** as the destination, then press **⌘R** to build and run.

The project signs the app for running on your own Mac ("Sign to Run Locally"), so no Apple developer account is needed.

## First Launch

- **Whisper models** aren't part of the build. The app downloads the model you choose the first time you transcribe, and keeps it for later.
- **Phone Notepad**: the first time you turn it on, macOS may ask whether WhisperLectures may accept incoming network connections. Allow it, or the phone can't reach the Mac.
- An app you build yourself opens normally on the Mac that built it. If you copy it to another Mac and macOS says it's damaged or can't be checked, run `xattr -dr com.apple.quarantine /path/to/WhisperLectures.app` on that Mac, or build it there instead.

## Troubleshooting

**"Only the Command Line Tools are installed" or "the Command Line Tools are selected instead"**
Install the full Xcode app, then select it:
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

**Downloading packages fails**
Check your internet connection (and any proxy or firewall that blocks github.com), then run `./build.sh --clean`.

**The build fails after updating Xcode or pulling new changes**
Run `./build.sh --clean` for a fresh build.

**Something else**
Look at the errors the script printed and at `build/build.log`. When reporting a problem, include the output of `./build.sh --check` and the errors from the log.

## For Contributors

- `WhisperLectures.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so building doesn't need XcodeGen. After adding, removing or renaming source files, regenerate it with `xcodegen generate` (or `./build.sh --regenerate`) and commit the result.
- Package versions are pinned in `WhisperLectures.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. To update WhisperKit, use **File → Packages → Update to Latest Package Versions** in Xcode and commit the new `Package.resolved`.
- `./package.sh` builds the app if needed and zips the project for distribution.
