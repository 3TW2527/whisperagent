#!/usr/bin/env bash
set -e

# WhisperLectures Packaging & Distribution Script
# Packages the project into a clean, distributable zip archive.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ZIP_NAME="WhisperLectures-Distribution.zip"
OUTPUT_PATH="$SCRIPT_DIR/$ZIP_NAME"

echo "=========================================="
echo "  Packaging WhisperLectures for Distribution"
echo "=========================================="

# 1. Build the app if it doesn't already exist
if [ ! -d "WhisperLectures.app" ]; then
    echo "⚙️  WhisperLectures.app not found. Running ./build.sh first..."
    ./build.sh
fi

# 2. Remove any previous distribution zip
if [ -f "$OUTPUT_PATH" ]; then
    rm -f "$OUTPUT_PATH"
fi

echo "📦 Creating $ZIP_NAME..."

# 3. Create zip excluding version control, intermediate build artifacts, and caches
zip -r -q "$OUTPUT_PATH" . \
    -x "*.git*" \
    -x "build/*" \
    -x "DerivedData/*" \
    -x ".build/*" \
    -x "*.xcuserstate" \
    -x "xcuserdata/*" \
    -x "*.DS_Store" \
    -x "*.zip" \
    -x "scratch/*" \
    -x "/tmp/*"

# 4. Report results
ZIP_SIZE=$(du -sh "$OUTPUT_PATH" | cut -f1)

echo "=========================================="
echo "✅ Package created successfully!"
echo "📁 Archive: $OUTPUT_PATH"
echo "⚖️  Size:    $ZIP_SIZE"
echo "=========================================="
echo "You can now distribute $ZIP_NAME directly."
