#!/usr/bin/env bash
# app/ (pristine) → build/app/ (patched). Tracked dosyalara dokunmaz.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app"
DST="$ROOT/build/app"
LOGPATH='${user.home}/Library/Logs/UHAPImza/log.out'

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC"/. "$DST"/

# 1) log4j.properties'i yazılabilir yola çevir (jar içinde)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
( cd "$TMP" && unzip -oq "$DST/Ard.ESignature.jar" log4j.properties )
# File= satırını değiştir (sed macOS: -i '')
sed -i '' "s#^log4j.appender.fileLogger.File=.*#log4j.appender.fileLogger.File=${LOGPATH}#" "$TMP/log4j.properties"
grep -q '^log4j.appender.fileLogger.File=${user.home}/Library/Logs/UHAPImza/log.out' "$TMP/log4j.properties" || { echo "HATA: log4j.properties yamasi eslesmedi" >&2; exit 1; }
( cd "$TMP" && zip -q "$DST/Ard.ESignature.jar" log4j.properties )

# 2) sunpkcs11.jar'ı payload'dan çıkar (split-package belirsizliğini önle)
rm -f "$DST/sunpkcs11.jar"

# 2b) config XML'lerini $APPDIR köküne de kopyala.
# ESYA, esya-signature-config.xml'i config/'ten mutlak yolla okur AMA içindeki
# <certificate-validation-policy-file>certval-policy.xml</...> göreli referansını
# bağlam kök URI'sine (user.dir = $APPDIR = Contents/app) göre çözer. Bu yüzden
# policy XML'leri Contents/app kökünde de bulunmalı (aksi halde
# FileNotFoundException: .../Contents/app/certval-policy.xml).
cp "$DST"/config/*.xml "$DST"/

# 3) (opsiyonel) görünür imza yolundaki ölü Windows yazımını kaldır
if [ "${PATCH_VISIBLE_SIG:-0}" = "1" ]; then
  "$ROOT/scripts/patch-visible-signature.sh"
fi

echo "prep OK → $DST"
