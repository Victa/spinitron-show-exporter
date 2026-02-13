# Spinitron Show Exporter

A macOS desktop app that downloads radio shows from [Spinitron](https://spinitron.com) and produces loudness-normalized audio files (M4A) or YouTube-ready videos (MP4) — complete with embedded cover art, metadata, and chapter markers.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

> **A note from the author:** I built this app to archive my own radio show from the station I broadcast on, which uses Spinitron. My radio station only keeps shows archived for two weeks, and I wanted a solution to build my own personal archive. This tool is intended strictly for **personal use** — for DJs and hosts who want to keep a copy of their own shows. It is **not** designed or intended to download copyrighted content illegally. Please respect the rights of artists, stations, and content creators.

![App Preview](App%20Preview.png)

## What It Does

- **Downloads full shows** from any Spinitron station given a playlist URL.
- **Auto-detects** the station name, show name, date, and duration from the Spinitron page.
- **Normalizes loudness** using a two-pass EBU R128 algorithm (via `ffmpeg`) so every export sounds consistent.
- **Embeds cover art** into the final file — either a user-provided image or an auto-generated title card.
- **Embeds metadata** (title, artist/station, date, album) into the output file.
- **Two output formats:**
  - **Audio** — A standalone `.m4a` file with embedded artwork and metadata.
  - **YouTube** — An `.mp4` video (still image + audio) ready to upload, plus a `_description.txt` file containing a tracklist with YouTube chapter timestamps.
- **Debug mode** — Downloads only 5 minutes of a show for quick testing.
- Provides a native **SwiftUI GUI** — no terminal required for day-to-day use.

## What It Does Not Do

- **Not a live stream player** — it only downloads archived/on-demand shows that have an HLS (`.m3u8`) stream available on Spinitron.
- **Does not upload to YouTube** — it produces a ready-to-upload file, but you upload it yourself.
- **Does not edit or trim audio** — it exports the full show duration (or 5 minutes in debug mode). Any editing must be done separately.
- **Does not run on Windows or Linux** — it's a native macOS app built with SwiftUI.
- **Does not handle authentication** — if a Spinitron page requires a login to access the audio player, the export will fail.

## Requirements

### System

- **macOS 14 (Sonoma)** or later

### Dependencies

| Dependency | Purpose | How to Install |
|---|---|---|
| **Xcode Command Line Tools** | Provides Swift compiler, `python3`, and other build tools | `xcode-select --install` |
| **ffmpeg** | Audio/video downloading, loudness normalization, muxing | `brew install ffmpeg` |
| **python3** | HTML parsing and metadata extraction (ships with Xcode CLT) | Included with Xcode CLT |
| **curl** | Fetching the Spinitron page HTML (ships with macOS) | Pre-installed on macOS |

> **Note:** If you don't have [Homebrew](https://brew.sh), install it first:
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/<your-username>/SpinitronShowExporter.git
cd SpinitronShowExporter
```

### Run from Source (Development)

You can run the app directly from source using Swift Package Manager:

```bash
swift run
```

This compiles and launches the GUI app in one step. The app window will appear and you can start exporting shows right away.

### Build a Release Binary

To compile an optimized release binary:

```bash
swift build -c release
```

The binary will be located at `.build/release/SpinitronShowExporter`.

### Build the macOS `.app` Bundle

To package the app as a double-clickable `.app` bundle (with the shell script bundled inside):

```bash
./build-app.sh
```

This will:

1. Compile a release build via `swift build -c release`.
2. Create a `Spinitron Show Exporter.app` bundle in the repo root.
3. Copy the `spinitron-export.sh` script into the app's `Resources/` folder.
4. Generate an `Info.plist`.
5. Ad-hoc code sign the bundle.

Once built, you can:

- **Launch it:** Double-click the `.app`, or run `open "Spinitron Show Exporter.app"`.
- **Share it:** Zip the `.app` and send it to someone. Recipients may need to right-click → Open on first launch (since it's ad-hoc signed, not notarized).

## Usage

1. **Open the app.**
2. **Paste a Spinitron playlist URL** into the "Show URL" field, e.g.:
   ```
   https://spinitron.com/WXYZ/pl/12345678/My-Show
   ```
3. **(Optional)** Choose a cover image (JPEG, PNG, TIFF, or HEIC). If you don't pick one, a title card is auto-generated.
4. **Select the output format:** Audio (`.m4a`) or YouTube (`.mp4`).
5. **Choose the output folder** (defaults to `~/Downloads`).
6. **(Optional)** Toggle **Debug Mode** to export only 5 minutes.
7. Click **Export** (or press <kbd>⌘</kbd><kbd>Return</kbd>).
8. When finished, click **Show in Finder** to locate your exported file.

### Using the Shell Script Directly

The underlying `spinitron-export.sh` script can also be used standalone from the terminal:

```bash
# Audio export (default)
./spinitron-export.sh "https://spinitron.com/WXYZ/pl/12345678/My-Show"

# YouTube-ready MP4
./spinitron-export.sh --youtube "https://spinitron.com/WXYZ/pl/12345678/My-Show"

# Debug mode (5 minutes only)
./spinitron-export.sh --debug "https://spinitron.com/WXYZ/pl/12345678/My-Show"
```

**Optional environment variables:**

| Variable | Description |
|---|---|
| `SHOW_NAME` | Override the auto-detected show name |
| `DURATION` | Override the auto-detected duration (format: `HH:MM:SS`) |

## Project Structure

```
SpinitronShowExporter/
├── Package.swift                          # Swift Package Manager manifest
├── Sources/
│   └── SpinitronShowExporterApp.swift     # SwiftUI app (GUI)
├── spinitron-export.sh                    # Core export script (bash)
├── build-app.sh                           # Builds the .app bundle
└── Icon.png                               # App icon
```

## License

This project is provided as-is for personal use.
