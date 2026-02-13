#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   spinitron-export "https://spinitron.com/WXYZ/pl/12345678/My-Show"
#   spinitron-export --youtube "https://spinitron.com/WXYZ/pl/12345678/My-Show"
#   spinitron-export --debug "https://spinitron.com/WXYZ/pl/12345678/My-Show"
#
# Downloads a show from any Spinitron station and produces a normalized audio
# file with embedded cover art and metadata (default), or a YouTube-ready
# MP4 video (--youtube).
#
# The station name, show name, and duration are auto-detected from the page/URL.
#
# Options:
#   --youtube   Produce a YouTube-ready MP4 instead of audio-only
#   --debug     Download only 5 minutes for quick testing
#
# Optional env vars:
#   SHOW_NAME   Override auto-detected show name for filenames
#   DURATION    Override auto-detected recording duration (HH:MM:SS)
#
# Requires (already on most Macs):
# - ffmpeg
# - python3
# - curl

DEBUG_MODE=false
VIDEO_MODE=false
TARGET_I="-14"
TARGET_TP="-1.5"
TARGET_LRA="11"
AUDIO_BITRATE="192k"
VIDEO_FPS="1"
VIDEO_CRF="30"
VIDEO_PRESET="ultrafast"

MISSING=()
for cmd in ffmpeg python3 curl; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Missing dependencies: ${MISSING[*]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  for cmd in "${MISSING[@]}"; do
    case "$cmd" in
      ffmpeg)
        echo "  ffmpeg — Install with Homebrew:"
        echo "    brew install ffmpeg"
        echo ""
        ;;
      python3)
        echo "  python3 — Install Xcode Command Line Tools:"
        echo "    xcode-select --install"
        echo ""
        ;;
      curl)
        echo "  curl — Install with Homebrew:"
        echo "    brew install curl"
        echo ""
        ;;
    esac
  done
  if ! command -v brew >/dev/null 2>&1; then
    echo "  Homebrew is not installed. Get it at:"
    echo "    https://brew.sh"
    echo ""
  fi
  exit 1
fi

usage() {
  echo "Usage: $0 [--youtube] [--debug] \"<spinitron_playlist_url>\""
  echo ""
  echo "Downloads a Spinitron show and produces a normalized audio file with"
  echo "embedded cover art and metadata. Use --youtube for an MP4 video."
  echo ""
  echo "The station name is auto-detected from the URL."
  echo ""
  echo "Options:"
  echo "  --youtube   Produce a YouTube-ready MP4 instead of audio-only"
  echo "  --debug     Download only 5 minutes for quick testing"
  echo ""
  echo "Optional env vars:"
  echo "  SHOW_NAME   Override auto-detected show name for filenames"
  echo "  DURATION    Override auto-detected recording duration (HH:MM:SS)"
  exit 1
}

PAGE_URL=""
for arg in "$@"; do
  case "$arg" in
    --debug)   DEBUG_MODE=true ;;
    --youtube) VIDEO_MODE=true ;;
    -*)        echo "Unknown option: $arg"; usage ;;
    *)       PAGE_URL="$arg" ;;
  esac
done

if [[ -z "$PAGE_URL" ]]; then
  usage
fi

# ── Extract station name from URL ──────────────────────────────────────
# URL format: https://spinitron.com/STATION/pl/ID/show-name
STATION_NAME="$(python3 -c "
from urllib.parse import urlparse
import sys
path = urlparse(sys.argv[1]).path.strip('/')
print(path.split('/')[0] if path else 'Unknown-Station')
" "$PAGE_URL")"

echo "Station: $STATION_NAME"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

HTML_FILE="$WORKDIR/page.html"
PASS1_LOG="$WORKDIR/loudnorm_pass1.log"

# ── Fetch Spinitron page ──────────────────────────────────────────────
echo "Fetching page..."
curl -fsSL "$PAGE_URL" > "$HTML_FILE"

# ── Parse show date & duration from page ──────────────────────────────
read -r SHOW_DATE SHOW_DURATION SHOW_DATE_DISPLAY < <(python3 - "$HTML_FILE" << 'PY'
import re, sys, html as html_mod
from datetime import datetime, timedelta

raw = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()
# Decode &nbsp; etc. for reliable matching
text = html_mod.unescape(raw)

def parse_time(s):
    """Parse a time string like '4:00 PM' or '11:00 AM'."""
    s = s.strip()
    for fmt in ("%I:%M %p", "%I:%M%p", "%I %p", "%I%p", "%H:%M"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None

# --- Date ---
months = (
    r'(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May'
    r'|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?'
    r'|Nov(?:ember)?|Dec(?:ember)?)'
)

show_date_iso = None
show_date_display = None

date_pat = rf'({months})\s+(\d{{1,2}}),?\s+(\d{{4}})'
dm = re.search(date_pat, text)
if dm:
    date_raw = f"{dm.group(1)} {dm.group(2)} {dm.group(3)}"
    for fmt in ("%B %d %Y", "%b %d %Y"):
        try:
            dt = datetime.strptime(date_raw, fmt)
            show_date_iso = dt.strftime("%Y-%m-%d")
            show_date_display = f"{dm.group(1)} {dm.group(2)}, {dm.group(3)}"
            break
        except ValueError:
            continue

if not show_date_iso:
    import datetime as dt_mod
    today = dt_mod.date.today()
    show_date_iso = today.isoformat()
    show_date_display = f"{today.strftime('%b')} {today.day}, {today.year}"

# --- Duration (from "HH:MM AM/PM – HH:MM AM/PM") ---
duration_hhmmss = "02:00:00"  # fallback default

# Match patterns like "4:00 PM – 6:00 PM" or "11:00 AM – 12:00 PM"
time_range = re.search(
    r'(\d{1,2}:\d{2}\s*[AP]M)\s*[\u2013\u2014\-]+\s*(\d{1,2}:\d{2}\s*[AP]M)',
    text, re.I
)
if time_range:
    t_start = parse_time(time_range.group(1))
    t_end   = parse_time(time_range.group(2))
    if t_start and t_end:
        delta = t_end - t_start
        if delta.total_seconds() <= 0:
            delta += timedelta(hours=24)
        total = int(delta.total_seconds())
        h, m, s = total // 3600, (total % 3600) // 60, total % 60
        duration_hhmmss = f"{h:02d}:{m:02d}:{s:02d}"

print(f"{show_date_iso} {duration_hhmmss} {show_date_display}")
PY
)

echo "Show date:     $SHOW_DATE_DISPLAY"
echo "Show duration: $SHOW_DURATION"

# Allow env var override for duration
DURATION="${DURATION:-$SHOW_DURATION}"

# --debug caps the download to 5 minutes
if [[ "$DEBUG_MODE" == true ]]; then
  DURATION="00:05:00"
  echo "DEBUG MODE:    downloading only 5 minutes"
fi

# ── Parse show name from page (unless overridden via env) ─────────────
if [[ -z "${SHOW_NAME:-}" ]]; then
  SHOW_NAME="$(python3 - "$HTML_FILE" "$PAGE_URL" << 'PY'
import re, sys, html as html_mod

html_path = sys.argv[1]
page_url  = sys.argv[2]
raw = open(html_path, "r", encoding="utf-8", errors="ignore").read()

# Strategy 1: <h3 class="show-title"> ... <a ...>Show Name</a> ... </h3>
m = re.search(r'<h3[^>]*class="[^"]*show-title[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>', raw, re.S | re.I)
if m:
    name = re.sub(r'<[^>]+>', '', m.group(1)).strip()
    name = html_mod.unescape(name)
    # Convert to filename-safe slug: "My Show" -> "My-Show"
    print(re.sub(r'\s+', '-', name))
    raise SystemExit(0)

# Strategy 2: fall back to URL slug (last path segment)
slug = page_url.rstrip('/').rsplit('/', 1)[-1]
if slug:
    print(slug)
    raise SystemExit(0)

print("Unknown-Show")
PY
)"
fi

echo "Show name: ${SHOW_NAME//-/ }"

BASE="${SHOW_NAME}-${SHOW_DATE}"
DESC_FILE="${BASE}_description.txt"

RAW_AUDIO="$WORKDIR/raw.m4a"
NORM_AUDIO="$WORKDIR/norm.m4a"

if [[ "$VIDEO_MODE" == true ]]; then
  OUT_MP4="${BASE}_youtube.mp4"
else
  OUT_M4A="${BASE}.m4a"
fi

# ── Find m3u8 stream URL ──────────────────────────────────────────────
echo "Finding m3u8 in page..."
M3U8_URL="$(python3 - "$HTML_FILE" << 'PY'
import re, sys, json
html = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()

# Method 1: look for a direct m3u8 link in the HTML
m = re.search(r'https://ark\d+\.spinitron\.com/[^"\s<>]+\.m3u8', html)
if m:
    print(m.group(0))
    raise SystemExit(0)

# Method 2: construct from ark2Player config + data-ark-start attribute
#   The JS builds: {hlsBaseUrl}/{stationName}-{arkStart}/index.m3u8
ark_start = re.search(r'data-ark-start="([^"]+)"', html)
ark_cfg   = re.search(r'ark2Player\s*\(\s*[^,]+,\s*(\{.*?\})\s*\)', html)

if ark_start and ark_cfg:
    try:
        cfg = json.loads(ark_cfg.group(1))
        base = cfg.get("hlsBaseUrl", "").rstrip("/")
        station = cfg.get("stationName", "")
        if base and station:
            print(f"{base}/{station}-{ark_start.group(1)}/index.m3u8")
            raise SystemExit(0)
    except (json.JSONDecodeError, KeyError):
        pass

print("")
PY
)" || true

if [[ -z "${M3U8_URL}" ]]; then
  echo "Could not find an m3u8 link on the page."
  echo "If the page requires a logged-in session, open the page in a browser"
  echo "and confirm the audio player loads."
  exit 1
fi

echo "m3u8: $M3U8_URL"

# ── Parse tracklist & generate description (YouTube only) ─────────────
if [[ "$VIDEO_MODE" != true ]]; then
  echo "Audio-only mode — skipping tracklist/description"
else
echo "Parsing tracklist..."
python3 - "$HTML_FILE" "$SHOW_NAME" "$SHOW_DATE_DISPLAY" "$DESC_FILE" "$DURATION" "$STATION_NAME" << 'TRACKLIST_PY'
import re, sys, html as html_mod
from datetime import datetime, timedelta

html_path    = sys.argv[1]
show_name    = sys.argv[2]
show_date    = sys.argv[3]
desc_path    = sys.argv[4]
duration_str = sys.argv[5]   # "HH:MM:SS"
station_name = sys.argv[6]

# Parse duration limit into seconds
dp = duration_str.split(":")
duration_secs = int(dp[0]) * 3600 + int(dp[1]) * 60 + int(dp[2])

raw = open(html_path, "r", encoding="utf-8", errors="ignore").read()


def clean(s):
    """Strip HTML tags and decode entities."""
    s = re.sub(r'<[^>]+>', '', s)
    s = html_mod.unescape(s)
    return s.strip()


def parse_time(t):
    """Parse a time string like '7:00 PM' or '19:00'."""
    for fmt in ("%I:%M %p", "%I:%M%p", "%H:%M"):
        try:
            return datetime.strptime(t.strip(), fmt)
        except ValueError:
            continue
    return None


tracks = []

# ── Strategy 1: table rows with >= 3 cells ───────────────────────────
# Spinitron playlists are often rendered as HTML tables.  Walk each <tr>,
# pull the <td> cells, and look for a time-stamp in the first few cells.
rows = re.findall(r'<tr[^>]*>(.*?)</tr>', raw, re.S | re.I)
for row in rows:
    cells = [clean(c) for c in re.findall(r'<td[^>]*>(.*?)</td>', row, re.S | re.I)]
    if len(cells) < 3:
        continue
    # find the first cell that looks like a clock time
    time_idx = None
    for i, cell in enumerate(cells):
        if re.match(r'\d{1,2}:\d{2}(\s*[AP]M)?$', cell, re.I):
            time_idx = i
            break
    if time_idx is None:
        continue
    # the next non-empty cells are artist and song
    rest = [c for c in cells[time_idx + 1:] if c]
    if len(rest) < 1:
        continue
    artist = rest[0]
    song   = rest[1] if len(rest) > 1 else ""
    tracks.append({"time": cells[time_idx], "artist": artist, "song": song})

# ── Strategy 2: divs / spans with "spin" or "track" classes ──────────
if not tracks:
    spin_blocks = re.findall(
        r'<(?:div|li|article)[^>]*class="[^"]*(?:spin|track)[^"]*"[^>]*>(.*?)</(?:div|li|article)>',
        raw, re.S | re.I
    )
    for block in spin_blocks:
        tm = re.search(r'(\d{1,2}:\d{2}\s*[AP]M)', block, re.I)
        if not tm:
            tm = re.search(r'(\d{1,2}:\d{2})', block)
        # try class-based artist/song
        art = re.search(r'class="[^"]*artist[^"]*"[^>]*>(.*?)<', block, re.S | re.I)
        sng = re.search(r'class="[^"]*(?:song|title)[^"]*"[^>]*>(.*?)<', block, re.S | re.I)
        if not art:
            # fallback: grab first two <a> or <span> texts
            texts = [clean(t) for t in re.findall(r'<(?:a|span|b|strong|em)[^>]*>(.*?)</', block, re.S)]
            texts = [t for t in texts if t and not re.match(r'\d{1,2}:\d{2}', t)]
            art_text = texts[0] if texts else None
            sng_text = texts[1] if len(texts) > 1 else ""
        else:
            art_text = clean(art.group(1))
            sng_text = clean(sng.group(1)) if sng else ""
        if tm and art_text:
            tracks.append({"time": clean(tm.group(1)), "artist": art_text, "song": sng_text})

# ── Compute YouTube chapter timestamps ────────────────────────────────
if tracks:
    base = parse_time(tracks[0]["time"])
    if base:
        for t in tracks:
            pt = parse_time(t["time"])
            if pt:
                delta = pt - base
                if delta.total_seconds() < 0:
                    delta += timedelta(hours=24)
                total = int(delta.total_seconds())
                h, m, s = total // 3600, (total % 3600) // 60, total % 60
                t["chapter"] = f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"

# ── Filter tracks to fit within the download duration ─────────────────
if tracks:
    base = parse_time(tracks[0]["time"])
    if base:
        filtered = []
        for t in tracks:
            pt = parse_time(t["time"])
            if pt:
                delta = pt - base
                if delta.total_seconds() < 0:
                    delta += timedelta(hours=24)
                if delta.total_seconds() < duration_secs:
                    filtered.append(t)
        tracks = filtered

# ── Write description file ────────────────────────────────────────────
display_name = show_name.replace("-", " ")
with open(desc_path, "w") as f:
    f.write(f"{display_name} \u2013 {show_date}\n")
    f.write(f"{station_name} on Spinitron\n\n")
    if tracks:
        for t in tracks:
            ch = t.get("chapter", "")
            line = f"{ch} {t['artist']}"
            if t.get("song"):
                line += f" \u2013 {t['song']}"
            f.write(line.rstrip() + "\n")
        f.write("\n")
    f.write(f"Originally aired on {station_name}.\n")

if tracks:
    print(f"Found {len(tracks)} tracks -> {desc_path}")
else:
    print(f"No tracklist found -- description written without tracklist -> {desc_path}")
TRACKLIST_PY
fi

# ── Download audio ────────────────────────────────────────────────────
if [[ -f "$RAW_AUDIO" ]]; then
  echo "Raw audio already exists, skipping download: $RAW_AUDIO"
else
  echo "Downloading audio to: $RAW_AUDIO"
  ffmpeg -hide_banner -y \
    -i "$M3U8_URL" \
    -t "$DURATION" \
    -c copy \
    "$RAW_AUDIO"
fi

# ── Loudness normalization (two-pass) ─────────────────────────────────
if [[ "$VIDEO_MODE" != true ]] && [[ -f "${OUT_M4A:-}" ]]; then
  echo "Final audio already exists, skipping normalization"
elif [[ -f "$NORM_AUDIO" ]]; then
  echo "Normalized audio already exists, skipping: $NORM_AUDIO"
else
  echo "Analyzing loudness (pass 1)..."
  ffmpeg -hide_banner -i "$RAW_AUDIO" \
    -af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:print_format=json" \
    -f null - 2> "$PASS1_LOG" || true

  JSON_BLOCK="$(python3 - "$PASS1_LOG" << 'PY'
import re, sys
txt = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()
m = re.search(r'(\{\s*"input_i"\s*:.*?\})', txt, flags=re.S)
if not m:
    print("ERROR: Could not parse loudnorm JSON from ffmpeg output.", file=sys.stderr)
    print("--- ffmpeg log ---", file=sys.stderr)
    print(txt, file=sys.stderr)
    print("--- end log ---", file=sys.stderr)
    raise SystemExit(2)
print(m.group(1))
PY
)"

  read -r measured_I measured_TP measured_LRA measured_thresh offset < <(python3 - "$JSON_BLOCK" << 'PY'
import json, sys
j = json.loads(sys.argv[1])
vals = [j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"]]
print(" ".join(str(v) for v in vals))
PY
)

  echo "Measured:"
  echo "  input_i=$measured_I LUFS"
  echo "  input_tp=$measured_TP dBTP"
  echo "  input_lra=$measured_LRA LU"
  echo "  input_thresh=$measured_thresh LUFS"
  echo "  target_offset=$offset LU"

  echo "Normalizing audio (pass 2)..."
  ffmpeg -hide_banner -y -i "$RAW_AUDIO" -vn \
    -af "loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:measured_I=${measured_I}:measured_TP=${measured_TP}:measured_LRA=${measured_LRA}:measured_thresh=${measured_thresh}:offset=${offset}:linear=true" \
    -c:a aac -b:a "$AUDIO_BITRATE" \
    "$NORM_AUDIO"
fi

# ── Cover image ───────────────────────────────────────────────────────
COVER_JPG="./cover.jpg"
COVER_IMG="$WORKDIR/cover.jpg"
DISPLAY_NAME="${SHOW_NAME//-/ }"

if [[ -f "$COVER_JPG" ]]; then
  echo "Using cover image..."
  cp "$COVER_JPG" "$COVER_IMG"
else
  if [[ "$VIDEO_MODE" == true ]]; then
    echo "No cover.jpg found — generating 1920×1080 title card..."
    ffmpeg -hide_banner -y \
      -f lavfi -i "color=c=0x1a1a2e:s=1920x1080:d=1" \
      -vf "drawtext=text='${DISPLAY_NAME}':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-50, \
           drawtext=text='${SHOW_DATE_DISPLAY}':fontsize=48:fontcolor=0xaaaaaa:x=(w-text_w)/2:y=(h-text_h)/2+50" \
      -frames:v 1 \
      "$COVER_IMG"
  else
    echo "No cover.jpg found — generating square title card..."
    ffmpeg -hide_banner -y \
      -f lavfi -i "color=c=0x1a1a2e:s=1400x1400:d=1" \
      -vf "drawtext=text='${DISPLAY_NAME}':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-50, \
           drawtext=text='${SHOW_DATE_DISPLAY}':fontsize=48:fontcolor=0xaaaaaa:x=(w-text_w)/2:y=(h-text_h)/2+50" \
      -frames:v 1 \
      "$COVER_IMG"
  fi
fi

# ── Finalize output ──────────────────────────────────────────────────
if [[ "$VIDEO_MODE" == true ]]; then
  # ── Create YouTube MP4 ─────────────────────────────────────────────
  if [[ -f "$OUT_MP4" ]]; then
    echo "Output MP4 already exists, skipping: $OUT_MP4"
  else
    echo "Creating YouTube MP4..."
    ffmpeg -hide_banner -y \
      -loop 1 -framerate "$VIDEO_FPS" -i "$COVER_IMG" \
      -i "$NORM_AUDIO" \
      -map 0:v:0 -map 1:a:0 \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
      -c:v libx264 -preset "$VIDEO_PRESET" -tune stillimage -crf "$VIDEO_CRF" \
      -g 300 -keyint_min 300 \
      -pix_fmt yuv420p \
      -c:a copy \
      -metadata title="${DISPLAY_NAME} – ${SHOW_DATE_DISPLAY}" \
      -metadata artist="${STATION_NAME}" \
      -metadata date="${SHOW_DATE}" \
      -shortest \
      "$OUT_MP4"
  fi

  echo ""
  echo "Done:"
  echo "  Video:       $OUT_MP4"
  echo "  Description: $DESC_FILE"
else
  # ── Embed cover art & metadata into final audio ────────────────────
  if [[ -f "$OUT_M4A" ]]; then
    echo "Final audio already exists, skipping: $OUT_M4A"
  else
    echo "Embedding cover art and metadata..."
    ffmpeg -hide_banner -y \
      -i "$NORM_AUDIO" -i "$COVER_IMG" \
      -map 0:a -map 1:v \
      -c:a copy -c:v copy \
      -disposition:v:0 attached_pic \
      -metadata title="${DISPLAY_NAME} – ${SHOW_DATE_DISPLAY}" \
      -metadata artist="${STATION_NAME}" \
      -metadata album="${DISPLAY_NAME}" \
      -metadata date="${SHOW_DATE}" \
      "$OUT_M4A"
  fi

  echo ""
  echo "Done:"
  echo "  $OUT_M4A"
fi
