#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${RUNTIME:-$ROOT/.jre-cache/zulu11-runtime}"
JPACKAGE="${JPACKAGE:-jpackage}"
APPNAME="UHAPImza"
DISPLAYNAME="UHAP İmzalama"
DEST="$ROOT/build"

test -d "$ROOT/build/app" || { echo "build/app yok — önce prep çalıştır"; exit 1; }
test -x "$RUNTIME/bin/java" || { echo "runtime yok — önce make jre"; exit 1; }

rm -rf "$DEST/$APPNAME.app"
"$JPACKAGE" \
  --type app-image \
  --name "$APPNAME" \
  --input "$ROOT/build/app" \
  --main-jar Ard.ESignature.jar \
  --main-class root.App \
  --arguments uhap-prod \
  --runtime-image "$RUNTIME" \
  --icon "$ROOT/assets/UHAPImza.icns" \
  --java-options "-Duser.dir=\$APPDIR" \
  --java-options "--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED" \
  --mac-package-name "$DISPLAYNAME" \
  --dest "$DEST"

# Görünen adı Türkçe yap (CFBundleDisplayName)
PLIST="$DEST/$APPNAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAYNAME" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $DISPLAYNAME" "$PLIST"

# Ad-hoc imza
codesign -s - --deep --force "$DEST/$APPNAME.app"
echo ">> app: $DEST/$APPNAME.app"
