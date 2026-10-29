#!/usr/bin/env bash
#
# Builds WhisperLectures.app from source.
#
#   ./build.sh            check the environment, then build WhisperLectures.app into this folder
#   ./build.sh --check    only check the environment
#   ./build.sh --install  build, then copy the app to /Applications
#   ./build.sh --open     build, then open the app
#   ./build.sh --clean    delete previous build output first
#
# Options can be combined, e.g. ./build.sh --clean --install --open
# See BUILDING.md for details and troubleshooting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="WhisperLectures"
PROJECT="$APP_NAME.xcodeproj"
SCHEME="$APP_NAME"
BUILD_DIR="$SCRIPT_DIR/build"
LOG_FILE="$BUILD_DIR/build.log"
APP_TARGET="$SCRIPT_DIR/$APP_NAME.app"

MIN_MACOS_MAJOR=14
MIN_XCODE_MAJOR=16

CHECK_ONLY=0
INSTALL=0
OPEN_APP=0
CLEAN=0
REGENERATE=0

usage() {
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    echo "Developer option: --regenerate  regenerate $PROJECT from project.yml with XcodeGen first"
}

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --install) INSTALL=1 ;;
        --open) OPEN_APP=1 ;;
        --clean) CLEAN=1 ;;
        --regenerate) REGENERATE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg"; echo; usage; exit 1 ;;
    esac
done

# ---------- Output helpers ----------

if [ -t 1 ]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

step() { echo; echo "${BOLD}==> $1${RESET}"; }
ok()   { echo "  ${GREEN}✓${RESET} $1"; }
warn() { echo "  ${YELLOW}!${RESET} $1"; }
fail() {
    echo "  ${RED}✗ $1${RESET}"
    shift
    for line in "$@"; do echo "    $line"; done
    echo
    echo "See BUILDING.md for help."
    exit 1
}

# ---------- Environment checks ----------

check_environment() {
    step "Checking your environment"

    # macOS version
    if [ "$(uname -s)" != "Darwin" ]; then
        fail "This app can only be built on macOS."
    fi
    local macos_version macos_major
    macos_version="$(sw_vers -productVersion)"
    macos_major="${macos_version%%.*}"
    if [ "$macos_major" -lt "$MIN_MACOS_MAJOR" ]; then
        fail "macOS $macos_version is too old." "WhisperLectures needs macOS $MIN_MACOS_MAJOR (Sonoma) or later."
    fi
    ok "macOS $macos_version"

    # Processor
    ARCH="$(uname -m)"
    if [ "$ARCH" = "arm64" ]; then
        ok "Apple silicon ($ARCH)"
    else
        warn "Intel Mac ($ARCH): the app builds, but transcription is much slower without Apple silicon's Neural Engine."
    fi

    # Full Xcode, not only the Command Line Tools
    if ! command -v xcodebuild >/dev/null 2>&1; then
        fail "Xcode is not installed." \
             "Install Xcode from the Mac App Store (https://apps.apple.com/app/xcode/id497799835)," \
             "open it once to finish setup, then run this script again."
    fi
    local developer_dir
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$developer_dir" == *CommandLineTools* ]] || ! xcodebuild -version >/dev/null 2>&1; then
        if [ -d "/Applications/Xcode.app" ]; then
            fail "Xcode is installed, but the Command Line Tools are selected instead." \
                 "Switch to Xcode with:" \
                 "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
        fi
        fail "Only the Command Line Tools are installed; the full Xcode app is needed." \
             "Install Xcode from the Mac App Store (https://apps.apple.com/app/xcode/id497799835)," \
             "open it once to finish setup, then run this script again."
    fi

    local xcode_version xcode_major
    xcode_version="$(xcodebuild -version | awk 'NR==1 {print $2}')"
    xcode_major="${xcode_version%%.*}"
    if [ "$xcode_major" -lt "$MIN_XCODE_MAJOR" ]; then
        fail "Xcode $xcode_version is too old." "WhisperLectures needs Xcode $MIN_XCODE_MAJOR or later (for Swift 6). Update it from the Mac App Store."
    fi
    ok "Xcode $xcode_version ($developer_dir)"

    # Licence and first-launch setup
    if ! xcodebuild -license check >/dev/null 2>&1; then
        fail "The Xcode licence hasn't been accepted yet." \
             "Accept it with:  sudo xcodebuild -license accept" \
             "(or open Xcode once and agree to it there)."
    fi
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        fail "Xcode hasn't finished its first-launch setup." \
             "Run:  sudo xcodebuild -runFirstLaunch" \
             "(or open Xcode once and let it install its components)."
    fi
    ok "Xcode licence accepted and setup complete"

    # Project files
    if [ ! -d "$PROJECT" ]; then
        fail "$PROJECT is missing." "Run this script from the root of the WhisperLectures source folder."
    fi
    ok "Project found"

    # Network, for downloading Swift packages the first time
    if [ -d "$BUILD_DIR/DerivedData/SourcePackages/checkouts" ]; then
        ok "Swift packages already downloaded"
    elif curl -fsS --max-time 8 -o /dev/null https://github.com 2>/dev/null; then
        ok "github.com reachable (needed once to download WhisperKit)"
    else
        warn "Can't reach github.com. The first build downloads WhisperKit from there, so it may fail offline."
    fi

    # Disk space: packages and build products take a few GB
    local free_gb
    free_gb="$(df -g "$SCRIPT_DIR" | awk 'NR==2 {print $4}')"
    if [ "${free_gb:-0}" -lt 5 ]; then
        warn "Only ${free_gb} GB free. The build needs about 5 GB."
    else
        ok "${free_gb} GB free disk space"
    fi
}

# ---------- Build ----------

run_logged() {
    # Runs a command, sending its output to the log; on failure shows the errors and the end of the log.
    local description="$1"
    shift
    if ! "$@" >>"$LOG_FILE" 2>&1; then
        echo "  ${RED}✗ $description failed.${RESET}"
        echo
        if grep -q "error:" "$LOG_FILE"; then
            echo "  Errors:"
            grep "error:" "$LOG_FILE" | sort -u | head -20 | sed 's/^/    /'
        else
            echo "  Last lines of the log:"
            tail -20 "$LOG_FILE" | sed 's/^/    /'
        fi
        echo
        echo "  Full log: $LOG_FILE"
        echo "  See BUILDING.md for help."
        exit 1
    fi
}

build_app() {
    mkdir -p "$BUILD_DIR"
    : >"$LOG_FILE"

    if [ "$CLEAN" -eq 1 ]; then
        step "Cleaning previous build"
        rm -rf "$BUILD_DIR/DerivedData" "$APP_TARGET"
        mkdir -p "$BUILD_DIR"
        ok "Removed build/DerivedData and $APP_NAME.app"
    fi

    if [ "$REGENERATE" -eq 1 ]; then
        step "Regenerating $PROJECT from project.yml"
        if ! command -v xcodegen >/dev/null 2>&1; then
            fail "XcodeGen is not installed." "Install it with:  brew install xcodegen"
        fi
        run_logged "xcodegen" xcodegen generate --quiet
        ok "Project regenerated"
    fi

    step "Downloading Swift packages (WhisperKit)"
    echo "  The first time this takes a few minutes."
    run_logged "Downloading packages" xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -derivedDataPath "$BUILD_DIR/DerivedData" -resolvePackageDependencies
    ok "Packages ready"

    step "Building $APP_NAME (Release)"
    echo "  The first build takes several minutes; later builds are faster."
    local started=$SECONDS
    run_logged "Build" xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Release \
        -destination "platform=macOS,arch=$ARCH" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        build
    ok "Built in $((SECONDS - started)) s"

    local app_source="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
    if [ ! -d "$app_source" ]; then
        fail "The build finished, but $APP_NAME.app wasn't found at $app_source." "Full log: $LOG_FILE"
    fi
    rm -rf "$APP_TARGET"
    cp -R "$app_source" "$APP_TARGET"
    ok "App saved to $APP_TARGET"

    if [ "$INSTALL" -eq 1 ]; then
        step "Installing to /Applications"
        local installed="/Applications/$APP_NAME.app"
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            warn "$APP_NAME is running; quit it first so the new version replaces it cleanly."
        fi
        if [ -w "/Applications" ]; then
            rm -rf "$installed"
            cp -R "$APP_TARGET" "$installed"
        else
            echo "  /Applications needs your password to write to."
            sudo rm -rf "$installed"
            sudo cp -R "$APP_TARGET" "$installed"
        fi
        APP_TARGET="$installed"
        ok "Installed to $installed"
    fi
}

check_environment

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo
    echo "${GREEN}${BOLD}Your Mac is ready to build $APP_NAME.${RESET} Run ./build.sh to build it."
    exit 0
fi

build_app

echo
echo "${GREEN}${BOLD}Done.${RESET} Open the app with:"
echo "  open \"$APP_TARGET\""

if [ "$OPEN_APP" -eq 1 ]; then
    open "$APP_TARGET"
fi
