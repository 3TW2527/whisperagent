#!/usr/bin/env bash
set -e

# WhisperLectures Build Script
# Builds the macOS application and outputs WhisperLectures.app in the project root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "  Building WhisperLectures macOS App"
echo "=========================================="

# 1. Check for required tools
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: xcodebuild is not installed or not in PATH."
    exit 1
fi

# Regenerate project if xcodegen is available and project.yml was modified
if command -v xcodegen &> /dev/null; then
    echo "⚙️  Regenerating Xcode project from project.yml..."
    xcodegen generate --quiet || echo "⚠️  xcodegen finished with warning, using existing project"
fi

if [ ! -d "WhisperLectures.xcodeproj" ]; then
    echo "❌ Error: WhisperLectures.xcodeproj not found."
    exit 1
fi

# 2. Resolve package dependencies (WhisperKit, etc.)
echo "📦 Resolving Swift Package dependencies..."
xcodebuild -project WhisperLectures.xcodeproj \
           -scheme WhisperLectures \
           -resolvePackageDependencies \
           -quiet

# 3. Compile the application
echo "🔨 Compiling WhisperLectures (Release configuration)..."
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

xcodebuild -project WhisperLectures.xcodeproj \
           -scheme WhisperLectures \
           -configuration Release \
           -destination "platform=macOS,arch=arm64" \
           -derivedDataPath "$BUILD_DIR/DerivedData" \
           build \
           -quiet

APP_SOURCE="$BUILD_DIR/DerivedData/Build/Products/Release/WhisperLectures.app"
APP_TARGET="$SCRIPT_DIR/WhisperLectures.app"

if [ -d "$APP_SOURCE" ]; then
    echo "🚚 Copying application to $APP_TARGET..."
    rm -rf "$APP_TARGET"
    cp -R "$APP_SOURCE" "$APP_TARGET"
    echo "=========================================="
    echo "✅ Build Successful!"
    echo "📁 App bundle created: $APP_TARGET"
    echo "🚀 Run with: open \"$APP_TARGET\""
    echo "=========================================="
else
    echo "❌ Build completed but application bundle was not found at $APP_SOURCE"
    exit 1
fi
