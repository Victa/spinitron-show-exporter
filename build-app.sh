#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# build-app.sh — Compile SpinitronShowExporter and package it as a macOS .app
#
# Usage:
#   ./build-app.sh
#
# Produces:  ./Spinitron Show Exporter.app  (in the repo root)
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BIN_NAME="SpinitronShowExporter"
APP_DISPLAY="Spinitron Show Exporter"
APP_BUNDLE="${SCRIPT_DIR}/${APP_DISPLAY}.app"

echo "═══════════════════════════════════════════"
echo "  Building ${APP_DISPLAY}.app"
echo "═══════════════════════════════════════════"
echo ""

# ── 1. Build ─────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
echo "▸ Compiling (release)..."
if ! swift build -c release 2>&1; then
    echo ""
    echo "❌ Build failed."
    echo "   Make sure Xcode Command Line Tools are installed:"
    echo "   xcode-select --install"
    exit 1
fi

BIN_PATH="$(swift build -c release --show-bin-path 2>/dev/null)"
BINARY="${BIN_PATH}/${BIN_NAME}"

if [ ! -f "$BINARY" ]; then
    echo "❌ Could not find compiled binary at ${BINARY}"
    exit 1
fi

echo "  ✓ Binary: ${BINARY}"

# ── 2. Create .app bundle ────────────────────────────────────────────
echo ""
echo "▸ Packaging .app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/"

# Copy shell script into Resources
cp "${SCRIPT_DIR}/spinitron-export.sh" "$APP_BUNDLE/Contents/Resources/"
chmod +x "$APP_BUNDLE/Contents/Resources/spinitron-export.sh"

# ── 3. Info.plist ────────────────────────────────────────────────────
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.spinitron.show-exporter</string>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo "  ✓ Info.plist written"

# ── 4. Ad-hoc code sign ─────────────────────────────────────────────
echo ""
echo "▸ Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
echo "  ✓ Signed (ad-hoc)"

# ── 5. Clean up stale .app bundles from previous builds ───────────────
CURRENT_BASENAME="$(basename "$APP_BUNDLE")"
for f in "$SCRIPT_DIR"/*.app; do
    [ -d "$f" ] || continue
    [ "$(basename "$f")" = "$CURRENT_BASENAME" ] && continue
    rm -rf "$f"
    echo "  ✓ Removed old $(basename "$f")"
done

# ── 6. Done ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  ✅  ${APP_BUNDLE}"
echo "═══════════════════════════════════════════"
echo ""
echo "  Double-click to launch, or run:"
echo "    open \"${APP_BUNDLE}\""
echo ""
echo "  To share: zip the .app and send it."
echo "  Recipients may need to right-click → Open on first launch."
echo ""
