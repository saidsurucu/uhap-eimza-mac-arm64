#!/usr/bin/env bash
# favicon.ico'dan macOS .icns ikonu üretir. Kaynak 48x48 olduğu için
# büyük boyutlar upscale edilir (kozmetik; kalite sınırlı).
set -euo pipefail
SRC="${1:-assets/favicon.ico}"
OUT="${2:-assets/UHAPImza.icns}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/UHAPImza.iconset"
mkdir -p "$ICONSET"
# ico → büyük png
sips -s format png "$SRC" --out "$TMP/base.png" >/dev/null
for sz in 16 32 64 128 256 512; do
  sips -z "$sz" "$sz" "$TMP/base.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz*2))
  sips -z "$dbl" "$dbl" "$TMP/base.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
