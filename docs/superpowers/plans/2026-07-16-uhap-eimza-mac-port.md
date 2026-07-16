# UHAP İmzalama Aracı — macOS (Apple Silicon) Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows MSI içindeki saf-Java UHAP e-imza aracını, Apple Silicon Mac'lerde çift tıklamayla çalışan native bir `.app` + `.dmg` paketine dönüştürmek ve tek-komut `kur.sh` ile kurulabilir hale getirmek.

**Architecture:** Uygulama zaten saf Java Swing + `localhost:8080` HTTP sunucusudur; tarayıcıdaki uhap.com.tr portalı bu sunucuya konuşur, uygulama AKİS akıllı karttan SunPKCS11 ile imzalar. Windows'a özgü parçalar (`.exe`, Windows JRE, native sürücü) atılır. Çıkarılmış JAR payload'u repoya gömülür (`app/`), build sırasında küçük yamalar uygulanır (log yolu + `sunpkcs11.jar` çıkarma), `jpackage` ile Zulu 11 arm64 runtime gömülü `.app` üretilir. AKİS `libakisp11.dylib`'i kullanıcı TÜBİTAK BİLGEM'den kurar.

**Tech Stack:** Java (Zulu 11 arm64 runtime + Zulu 21/sistem JDK jpackage için), macOS `jpackage`/`codesign`/`hdiutil`/`sips`/`iconutil`, `bash`, `make`, TÜBİTAK ESYA (ma3api) + SunPKCS11.

## Global Constraints

- **Hedef mimari:** Yalnızca macOS **arm64 (Apple Silicon)**. Intel hedeflenmez.
- **Runtime JRE:** Azul **Zulu 11 arm64** (düz, JavaFX'siz). Kanonik URL:
  `https://cdn.azul.com/zulu/bin/zulu11.88.17-ca-jdk11.0.31-macosx_aarch64.tar.gz`
  (veya Azul metadata API'den `java_version=11&os=macos&arch=aarch64&java_package_type=jdk&latest=true` ile güncel GA).
- **Build aracı:** `jpackage` **JDK 11'de yoktur**; JDK 17+ gerekir. Sistemde `jpackage` varsa (Java 17+) o kullanılır, yoksa Zulu 21 JDK indirilir.
- **Başlatma argümanı:** `root.App` main sınıfına tek argüman **`uhap-prod`** verilir (→ uhap.com.tr, port 8080). Başka değer (`uhap`, `uhap-test`) kullanılmaz.
- **Zorunlu JVM bayrağı:** `--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED` (paket `java.base`'de DEĞİL).
- **Zorunlu JVM bayrağı:** `-Duser.dir=$APPDIR` (uygulama config'i `user.dir` köküne göre okur; `$APPDIR` jpackage runtime makrosudur, `Contents/app`'e genişler).
- **Executable adı ASCII:** `UHAPImza` (Türkçe karakter imzalamada sorun çıkarır); görünen ad `Info.plist` `CFBundleDisplayName` ile "UHAP İmzalama".
- **İmza:** ad-hoc `codesign -s - --deep --force`. Notarization kapsam dışı.
- **Committed payload pristine kalır:** `app/` altındaki JAR'lar MSI'dan çıkarıldığı gibi durur; tüm yamalar `build/` kopyası üzerinde yapılır, tracked dosyalar değişmez.
- **Profesyonel dil:** README ve çıktı metinlerinde abartı/pazarlama dili yok; "resmi değil, topluluk portu" ibaresi bulunur.

---

## Kaynak Konumları (bu makinede hazır)

- Çıkarılmış payload (pristine): `SCRATCH/extracted/` — burada
  `SCRATCH=/private/tmp/claude-501/-Users-saidsurucu-Documents-GitHub-uhap-eimza-mac/2da48063-aab3-470d-bb22-7c6c97ed5271/scratchpad`
  - 61 `*.jar`, `config/*.xml`, `TrustedCertificates/SertifikaDeposu.svt`, `favicon.ico`
  - (Alternatif kaynak: repo kökündeki `UHAPImzalamaAraci (1).msi`, `msiextract` ile açılabilir — ama çıkarılmış kopya zaten mevcut.)
- AKİS sürücüsü bu makinede **kurulu ve universal**: `/usr/local/lib/libakisp11.dylib` (`lipo -archs` → `x86_64 arm64`). PCSC framework mevcut.
- Sistem Java: `/usr/bin/java` = Zulu 21.0.11, `/usr/bin/jpackage` mevcut.

## File Structure

```
uhap-eimza-mac/
├── app/                          # Committed pristine payload (jpackage --input kaynağı)
│   ├── *.jar                     # 61 JAR (Ard.ESignature.jar dahil, sunpkcs11.jar dahil)
│   ├── config/*.xml
│   └── TrustedCertificates/SertifikaDeposu.svt
├── assets/
│   ├── favicon.ico               # ikon kaynağı (48x48)
│   └── UHAPImza.icns             # üretilmiş app ikonu
├── scripts/
│   ├── prep-payload.sh           # app/ → build/app/ kopyala + yamala
│   ├── build-app.sh              # jpackage sarmalayıcı + codesign
│   └── make-icns.sh              # favicon.ico → UHAPImza.icns
├── Makefile                      # jre, prep, app, dmg, run, install, clean
├── kur.sh                        # tek-komut kurucu
├── .gitignore
├── README.md
└── docs/superpowers/{specs,plans}/
```

---

## Task 1: Repo iskeleti ve pristine payload'u gömme

**Files:**
- Create: `.gitignore`
- Create: `app/` (61 jar + config/ + TrustedCertificates/)
- Create: `assets/favicon.ico`

**Interfaces:**
- Produces: `app/Ard.ESignature.jar` (main jar), `app/config/certval-policy.xml`, `app/config/esya-signature-config.xml`, `app/TrustedCertificates/SertifikaDeposu.svt`, `assets/favicon.ico`. Sonraki task'lar `app/` dizinini `jpackage --input` olarak kullanır.

- [ ] **Step 1: `.gitignore` yaz**

```gitignore
build/
.jre-cache/
*.dmg
*.msi
.DS_Store
_tmp/
.superpowers/
```

- [ ] **Step 2: Pristine payload'u kopyala**

```bash
cd /Users/saidsurucu/Documents/GitHub/uhap-eimza-mac
SCRATCH="/private/tmp/claude-501/-Users-saidsurucu-Documents-GitHub-uhap-eimza-mac/2da48063-aab3-470d-bb22-7c6c97ed5271/scratchpad"
mkdir -p app assets
cp "$SCRATCH"/extracted/*.jar app/
cp -R "$SCRATCH"/extracted/config app/config
cp -R "$SCRATCH"/extracted/TrustedCertificates app/TrustedCertificates
cp "$SCRATCH"/extracted/favicon.ico assets/favicon.ico
```

- [ ] **Step 3: Doğrula (payload bütünlüğü)**

Run:
```bash
ls app/*.jar | wc -l          # beklenen: 61
test -f app/Ard.ESignature.jar && echo "main jar OK"
test -f app/config/certval-policy.xml && echo "config OK"
test -f app/TrustedCertificates/SertifikaDeposu.svt && echo "certs OK"
unzip -p app/Ard.ESignature.jar META-INF/MANIFEST.MF | grep 'Main-Class' # root.App
```
Expected: `61`, `main jar OK`, `config OK`, `certs OK`, `Main-Class: root.App`

- [ ] **Step 4: Commit**

```bash
git add .gitignore app assets/favicon.ico
git commit -m "Add pristine UHAP Java payload and repo scaffolding"
```

---

## Task 2: App ikonu üretme (favicon.ico → .icns)

**Files:**
- Create: `scripts/make-icns.sh`
- Create: `assets/UHAPImza.icns`

**Interfaces:**
- Consumes: `assets/favicon.ico` (Task 1)
- Produces: `assets/UHAPImza.icns` — Task 5 `jpackage --icon` ile kullanır.

- [ ] **Step 1: `scripts/make-icns.sh` yaz**

```bash
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
```

- [ ] **Step 2: Çalıştırılabilir yap ve çalıştır**

Run:
```bash
chmod +x scripts/make-icns.sh
./scripts/make-icns.sh
```
Expected: `wrote assets/UHAPImza.icns`

- [ ] **Step 3: Doğrula**

Run: `file assets/UHAPImza.icns`
Expected: `Mac OS X icon` içeren çıktı

- [ ] **Step 4: Commit**

```bash
git add scripts/make-icns.sh assets/UHAPImza.icns
git commit -m "Generate app icon from favicon"
```

---

## Task 3: Payload yama betiği (log yolu + sunpkcs11 çıkarma)

**Files:**
- Create: `scripts/prep-payload.sh`

**Interfaces:**
- Consumes: `app/` (Task 1)
- Produces: `build/app/` — yamalanmış payload kopyası. Task 5 bunu `jpackage --input build/app` ile kullanır. Garantiler: `build/app/Ard.ESignature.jar` içindeki `log4j.properties` yazılabilir log yoluna işaret eder; `build/app/sunpkcs11.jar` **yoktur**.

Arka plan: `Ard.ESignature.jar` **imzasızdır** (imza strip gerekmez). `log4j.properties` jar kökündedir ve `log4j.appender.fileLogger.File=./log/log.out` (göreli, read-only bundle'da patlar). Log4j 1.x `${...}` sistem-property genişletmesini destekler. `sunpkcs11.jar` (2008) manifest Class-Path'te listelidir; **dosyayı silmek yeterlidir** — JVM var olmayan Class-Path girdisini sessizce atlar, wrapper sınıfları `jdk.crypto.cryptoki` modülünden gelir.

- [ ] **Step 1: `scripts/prep-payload.sh` yaz**

```bash
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
( cd "$TMP" && zip -q "$DST/Ard.ESignature.jar" log4j.properties )

# 2) sunpkcs11.jar'ı payload'dan çıkar (split-package belirsizliğini önle)
rm -f "$DST/sunpkcs11.jar"

echo "prep OK → $DST"
```

- [ ] **Step 2: Çalıştırılabilir yap ve çalıştır**

Run:
```bash
chmod +x scripts/prep-payload.sh
./scripts/prep-payload.sh
```
Expected: `prep OK → .../build/app`

- [ ] **Step 3: Doğrula (yamalar uygulandı)**

Run:
```bash
unzip -p build/app/Ard.ESignature.jar log4j.properties | grep 'fileLogger.File'
test ! -f build/app/sunpkcs11.jar && echo "sunpkcs11 removed"
ls build/app/*.jar | wc -l    # beklenen: 60 (61 - sunpkcs11)
```
Expected:
```
log4j.appender.fileLogger.File=${user.home}/Library/Logs/UHAPImza/log.out
sunpkcs11 removed
60
```

- [ ] **Step 4: Commit**

```bash
git add scripts/prep-payload.sh
git commit -m "Add payload prep: writable log path, strip sunpkcs11.jar"
```

---

## Task 4: JRE/JDK edinme (Makefile `jre` hedefi)

**Files:**
- Create: `Makefile` (ilk hedefler: `jre`, değişkenler)

**Interfaces:**
- Produces: `.jre-cache/zulu11-runtime/` (Zulu 11 arm64 JDK, `--runtime-image` için) ve `JPACKAGE` değişkeni (sistem jpackage ya da indirilmiş Zulu 21). Task 5 bunları kullanır.

- [ ] **Step 1: `Makefile` iskeletini ve `jre` hedefini yaz**

```makefile
SHELL := /bin/bash
ROOT := $(shell pwd)
CACHE := $(ROOT)/.jre-cache
BUILD := $(ROOT)/build
APPNAME := UHAPImza
DISPLAYNAME := UHAP İmzalama

ZULU11_URL := https://cdn.azul.com/zulu/bin/zulu11.88.17-ca-jdk11.0.31-macosx_aarch64.tar.gz
ZULU21_URL := https://cdn.azul.com/zulu/bin/zulu21.50.19-ca-jdk21.0.11-macosx_aarch64.tar.gz

RUNTIME := $(CACHE)/zulu11-runtime
# Sistem jpackage (Java 17+) varsa onu kullan, yoksa indirilmiş Zulu 21'i
JPACKAGE := $(shell command -v jpackage 2>/dev/null || echo $(CACHE)/zulu21/bin/jpackage)

.PHONY: jre
jre: $(RUNTIME)/bin/java $(JPACKAGE)

$(RUNTIME)/bin/java:
	@mkdir -p $(CACHE)
	@echo ">> Zulu 11 arm64 runtime indiriliyor..."
	@curl -fsSL "$(ZULU11_URL)" -o $(CACHE)/zulu11.tar.gz
	@rm -rf $(CACHE)/zulu11-runtime $(CACHE)/_z11 && mkdir -p $(CACHE)/_z11
	@tar -xzf $(CACHE)/zulu11.tar.gz -C $(CACHE)/_z11 --strip-components=1
	@# .app içindeki Contents/Home gerçek JDK kökü
	@if [ -d "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" ]; then \
	   mv "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" $(RUNTIME); \
	 else mv $(CACHE)/_z11 $(RUNTIME); fi
	@rm -rf $(CACHE)/_z11 $(CACHE)/zulu11.tar.gz
	@echo ">> runtime: $(RUNTIME)"

$(CACHE)/zulu21/bin/jpackage:
	@if command -v jpackage >/dev/null 2>&1; then \
	   echo ">> sistem jpackage kullanılacak: $$(command -v jpackage)"; \
	 else \
	   echo ">> Zulu 21 (jpackage) indiriliyor..."; \
	   mkdir -p $(CACHE); \
	   curl -fsSL "$(ZULU21_URL)" -o $(CACHE)/zulu21.tar.gz; \
	   rm -rf $(CACHE)/zulu21 $(CACHE)/_z21 && mkdir -p $(CACHE)/_z21; \
	   tar -xzf $(CACHE)/zulu21.tar.gz -C $(CACHE)/_z21 --strip-components=1; \
	   if [ -d "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" ]; then \
	     mv "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" $(CACHE)/zulu21; \
	   else mv $(CACHE)/_z21 $(CACHE)/zulu21; fi; \
	   rm -rf $(CACHE)/_z21 $(CACHE)/zulu21.tar.gz; \
	 fi
```

Not: `ZULU21_URL` sistemde jpackage varsa hiç indirilmez. URL rotasyonuna karşı Azul metadata API alternatifi README'de belirtilir.

- [ ] **Step 2: `jre` hedefini çalıştır**

Run: `make jre`
Expected: `>> runtime: .../.jre-cache/zulu11-runtime` (ve sistemde jpackage varsa "sistem jpackage kullanılacak")

- [ ] **Step 3: Doğrula (runtime modülleri)**

Run:
```bash
.jre-cache/zulu11-runtime/bin/java -version 2>&1 | head -1
.jre-cache/zulu11-runtime/bin/java --list-modules | grep -E 'jdk.crypto.cryptoki|java.smartcardio'
```
Expected: `openjdk version "11.0.31"` ve `jdk.crypto.cryptoki@11...`, `java.smartcardio@11...`

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Add Makefile jre target: fetch Zulu 11 runtime + resolve jpackage"
```

---

## Task 5: `.app` build (jpackage + codesign)

**Files:**
- Create: `scripts/build-app.sh`
- Modify: `Makefile` (`prep`, `app` hedefleri)

**Interfaces:**
- Consumes: `build/app/` (Task 3), `.jre-cache/zulu11-runtime` + `JPACKAGE` (Task 4), `assets/UHAPImza.icns` (Task 2)
- Produces: `build/UHAPImza.app` — ad-hoc imzalı, çift tıklamayla açılan uygulama. Task 6 (dmg) ve Task 7 (kur.sh) bunu kullanır.

- [ ] **Step 1: `scripts/build-app.sh` yaz**

```bash
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
```

- [ ] **Step 2: `Makefile`'a `prep` ve `app` hedeflerini ekle**

```makefile
.PHONY: prep app
prep:
	@./scripts/prep-payload.sh

app: jre prep
	@RUNTIME="$(RUNTIME)" JPACKAGE="$(JPACKAGE)" ./scripts/build-app.sh
```

- [ ] **Step 3: Build'i çalıştır**

Run:
```bash
chmod +x scripts/build-app.sh
make app
```
Expected: `>> app: .../build/UHAPImza.app`

- [ ] **Step 4: Doğrula — bundle yapısı ve imza**

Run:
```bash
test -d build/UHAPImza.app && echo "bundle OK"
codesign -dv build/UHAPImza.app 2>&1 | grep -i 'adhoc\|Signature' | head -1
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" build/UHAPImza.app/Contents/Info.plist
test -d build/UHAPImza.app/Contents/app && echo "payload embedded"
test -f build/UHAPImza.app/Contents/runtime/Contents/Home/bin/java && echo "runtime embedded"
```
Expected: `bundle OK`, adhoc signature satırı, `UHAP İmzalama`, `payload embedded`, `runtime embedded`

- [ ] **Step 5: Doğrula — çalıştır, HTTP server + config + log yolu**

Bu, portun asıl işlevsel testidir. Uygulamayı arka planda başlat, endpoint'i yokla, log dosyasının yazılabilir yola yazıldığını ve config-not-found hatası olmadığını doğrula.

Run:
```bash
# Eski instansı temizle
pkill -f UHAPImza 2>/dev/null; sleep 1
open build/UHAPImza.app
sleep 12
echo "--- port ---"; lsof -nP -iTCP:8080 -sTCP:LISTEN | grep -i java && echo "8080 LISTEN"
echo "--- /imza ---"; curl -s -m 5 "http://localhost:8080/imza" | head -c 120; echo
echo "--- log yazıldı mı ---"; ls -la "$HOME/Library/Logs/UHAPImza/log.out" && tail -5 "$HOME/Library/Logs/UHAPImza/log.out"
echo "--- config-not-found kontrolü ---"; grep -iE 'FileNotFound|config.*not|esya-signature-config.xml.*bulun|No such file' "$HOME/Library/Logs/UHAPImza/log.out" && echo "!!! CONFIG HATASI" || echo "config OK"
pkill -f UHAPImza 2>/dev/null
```
Expected: `8080 LISTEN`; `/imza` bir yanıt döner (gerçek imza süreci olmadığı için hata metni normaldir); `log.out` **`~/Library/Logs/UHAPImza/` altında mevcut** (read-only bundle'a yazma denemesi yok); `config OK` (config dosyaları $APPDIR'den çözülür).

Eğer `log.out` yoksa veya server 8080'de değilse: `-Duser.dir=$APPDIR` genişlememiş olabilir → Fallback (spec §8.2): `build-app.sh`'de `--java-options "-Duser.dir=..."` yerine küçük bir launcher wrapper ile mutlak yol ver. Eğer `--add-exports` uyarısı görülürse modül adını doğrula.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app.sh Makefile
git commit -m "Add jpackage build: Zulu 11 app-image with config/log/pkcs11 fixes"
```

---

## Task 6: DMG üretme (`make dmg`)

**Files:**
- Modify: `Makefile` (`dmg`, `run`, `install`, `clean` hedefleri)

**Interfaces:**
- Consumes: `build/UHAPImza.app` (Task 5)
- Produces: `build/UHAPImza.dmg` — sürükle-bırak installer.

- [ ] **Step 1: `Makefile`'a hedefleri ekle**

```makefile
.PHONY: dmg run install clean
dmg: app
	@rm -f $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot && mkdir -p $(BUILD)/dmgroot
	@cp -R $(BUILD)/$(APPNAME).app $(BUILD)/dmgroot/
	@ln -s /Applications $(BUILD)/dmgroot/Applications
	@hdiutil create -volname "$(APPNAME)" -srcfolder $(BUILD)/dmgroot \
	   -ov -format UDZO $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot
	@echo ">> dmg: $(BUILD)/$(APPNAME).dmg"

run: app
	@open $(BUILD)/$(APPNAME).app

install: app
	@rm -rf "/Applications/$(APPNAME).app"
	@cp -R $(BUILD)/$(APPNAME).app /Applications/
	@echo ">> kuruldu: /Applications/$(APPNAME).app"

clean:
	@rm -rf $(BUILD)
	@echo ">> temizlendi (build/). .jre-cache korunur."
```

- [ ] **Step 2: DMG üret**

Run: `make dmg`
Expected: `>> dmg: .../build/UHAPImza.dmg`

- [ ] **Step 3: Doğrula — DMG mount olur ve app içerir**

Run:
```bash
hdiutil attach build/UHAPImza.dmg -nobrowse -mountpoint /tmp/uhapdmg
test -d /tmp/uhapdmg/UHAPImza.app && echo "dmg içerik OK"
hdiutil detach /tmp/uhapdmg
```
Expected: `dmg içerik OK`

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Add dmg, run, install, clean Makefile targets"
```

---

## Task 7: Tek-komut kurucu (`kur.sh`)

**Files:**
- Create: `kur.sh`

**Interfaces:**
- Consumes: repo (tüm önceki task'lar). `kur.sh` build zincirini uçtan uca çalıştırır ve `/Applications`'a kurar.
- Produces: `/Applications/UHAPImza.app`, ve AKİS sürücü talimatı çıktısı.

- [ ] **Step 1: `kur.sh` yaz**

```bash
#!/usr/bin/env bash
# UHAP İmzalama — macOS (Apple Silicon) tek-komut kurulum.
# Resmi değildir; topluluk portudur.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
info(){ echo "${GRN}>>${RST} $*"; }
warn(){ echo "${YEL}!!${RST} $*"; }
die(){ echo "${RED}HATA:${RST} $*" >&2; exit 1; }

# 1) Mimari kontrolü
[ "$(uname -s)" = "Darwin" ] || die "Yalnızca macOS."
[ "$(uname -m)" = "arm64" ] || die "Yalnızca Apple Silicon (arm64)."

# 2) Xcode CLT (make, git, curl için)
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode Command Line Tools kuruluyor — pencereyi onaylayın..."
  xcode-select --install || true
  die "CLT kurulumu bitince kur.sh'i tekrar çalıştırın."
fi

# 3) Repo kökü (kur.sh repo içinden çalıştırılır)
cd "$(cd "$(dirname "$0")" && pwd)"
[ -f Makefile ] && [ -d app ] || die "kur.sh'i repo kökünde çalıştırın."

# 4) Build + kur
info "İkon üretiliyor..."; ./scripts/make-icns.sh >/dev/null || warn "ikon üretilemedi (kozmetik)"
info "Runtime ve build aracı hazırlanıyor..."; make jre
info "Uygulama derleniyor..."; make app
info "/Applications'a kuruluyor..."; make install

# 5) AKİS sürücü kontrolü + yönlendirme
DYLIB="/usr/local/lib/libakisp11.dylib"
if [ -f "$DYLIB" ] && lipo -archs "$DYLIB" 2>/dev/null | grep -q arm64; then
  info "AKİS sürücüsü mevcut (arm64): $DYLIB"
else
  warn "AKİS arm64 sürücüsü bulunamadı."
  warn "TÜBİTAK BİLGEM'den 'Mac OS Arm (Apple Silicon)' AKİS paketini kurun:"
  warn "  https://akiskart.bilgem.tubitak.gov.tr/tr/destek/"
  warn "Kurulum sonrası doğrulama: lipo -archs $DYLIB  → arm64 içermeli"
fi

info "Bitti. 'UHAP İmzalama' Launchpad/Uygulamalar'dan açılabilir."
info "İlk açılışta Gatekeeper uyarısı çıkarsa: sağ tık → Aç."
```

- [ ] **Step 2: Çalıştırılabilir yap**

Run: `chmod +x kur.sh`

- [ ] **Step 3: Doğrula — uçtan uca kurulum**

Run:
```bash
make clean
./kur.sh
test -d /Applications/UHAPImza.app && echo "KURULUM OK"
```
Expected: build zinciri çalışır, `KURULUM OK`, AKİS satırında `mevcut (arm64)` (bu makinede sürücü kurulu).

- [ ] **Step 4: Commit**

```bash
git add kur.sh
git commit -m "Add one-command installer kur.sh"
```

---

## Task 8: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: tüm repo. Kurulum, AKİS sürücü, kullanım, sorun giderme, sınırlar.

- [ ] **Step 1: `README.md` yaz**

````markdown
# UHAP İmzalama — macOS (Apple Silicon) Port

UHAP e-imza aracının (ARDGRUP/ImzaTek tabanlı) Apple Silicon Mac'ler için
topluluk portu. **Resmi değildir**; UHAP veya TÜBİTAK tarafından
geliştirilmemiştir. Yalnızca paketleme betikleri içerir; Java uygulamasının
kendisi değiştirilmez (yalnızca log yolu ve platform uyumu için küçük yamalar).

## Gereksinimler

- Apple Silicon (arm64) Mac, macOS.
- AKİS akıllı kart + kart okuyucu.
- **AKİS macOS arm64 sürücüsü** (aşağıya bkz.).

## Kurulum

```bash
git clone <repo-url> uhap-eimza-mac
cd uhap-eimza-mac
./kur.sh
```

`kur.sh`: gerekli Java runtime'ı indirir, `.app`'i derler, `/Applications`'a
kurar ve AKİS sürücü durumunu bildirir. İnternet gerekir (Java runtime indirimi
ve imza doğrulaması için).

Manuel derleme: `make app` (sadece derle), `make dmg` (installer), `make run`
(çalıştır), `make install` (/Applications'a kur).

## AKİS Sürücüsü (zorunlu)

Uygulama akıllı kartı `libakisp11.dylib` üzerinden okur. TÜBİTAK BİLGEM'den
**"Mac OS Arm (Apple Silicon)"** etiketli AKİS paketini kurun:

- https://akiskart.bilgem.tubitak.gov.tr/tr/destek/

Doğrulama:

```bash
lipo -archs /usr/local/lib/libakisp11.dylib   # arm64 içermeli
```

Intel-only sürücü kuruluysa "kütüphane yüklenemedi" hatası alırsınız; arm64
paketini kurun.

## Kullanım

1. "UHAP İmzalama"yı açın (arka planda `localhost:8080`'de çalışır).
2. Tarayıcıda https://uhap.com.tr açın ve imzalama akışını başlatın.
3. Kart PIN'inizi girin.

Loglar: `~/Library/Logs/UHAPImza/log.out`.

## Sorun Giderme

- **Gatekeeper "açılamıyor":** Uygulamaya sağ tık → Aç (ad-hoc imzalı).
- **8080 meşgul:** Portu kullanan başka uygulamayı kapatın (port sabittir).
- **Sertifika doğrulama hatası:** Uygulama `depo.kamusm.gov.tr`'ye erişir;
  internet/erişim gerektirir.
- **Görünür (visible) imza sorunu:** Bu portta görünür imza yolu sınırlıdır
  (bkz. Bilinen Sınırlar).

## Bilinen Sınırlar

- Yalnızca arm64; Intel desteklenmez.
- Notarize edilmemiştir (ad-hoc imza).
- Görünür PDF imzası (imza görselini PDF'e gömme) test edilmemiştir; kaynak
  uygulamada bu yol Windows'a özgü bir dosya yolu içerir.
- Kart tipi: AKİS. Diğer token'lar test edilmemiştir.

## Lisans / Sorumluluk

Paketleme betikleri topluluk katkısıdır. UHAP/ARDGRUP/TÜBİTAK marka ve
yazılım hakları sahiplerine aittir.
````

- [ ] **Step 2: Doğrula**

Run: `grep -c 'AKİS\|kur.sh\|arm64' README.md`
Expected: `>0` (anahtar bölümler mevcut)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README with install, AKIS driver, troubleshooting"
```

---

## Task 9 (KOŞULLU): Görünür imza yaması

**Bu task yalnızca görünür (visible) PDF imzası GEREKİYORSA yapılır.** Gözlemlenen
UHAP akışında `VisibleSignature: false` idi; bu yüzden varsayılan olarak **atlanır**.
Atlanırsa görünür imza denenirse `C:\1\imza.png` yazımı başarısız olur (görünmez
imza etkilenmez).

**Files:**
- Create: `scripts/patch-visible-signature.sh`
- Modify: `scripts/prep-payload.sh` (bu betiği koşullu çağır)

**Interfaces:**
- Consumes: `build/app/Ard.ESignature.jar` (Task 3 sonrası), `JBIN` (javac/java, JDK 17+).
- Produces: `VisibleSignatureImageCreator.createImage` metodu, `C:\1\imza.png`'e
  yazan `Files.write(...)` çağrısı **kaldırılmış** olarak.

Arka plan (kesin, decompile ile doğrulandı): İlgili metod tam olarak
`public static byte[] createImage(String, tr.gov.tubitak.uekae.esya.api.pades.SignaturePanel, java.awt.Dimension)`.
Gövdesinin sonu:
```java
ByteArrayOutputStream os = new ByteArrayOutputStream();
ImageIO.write((RenderedImage)bufferedImage, "png", os);
Files.write(Paths.get("C:\\1\\imza.png"), os.toByteArray(), new OpenOption[0]); // ← kaldırılacak
return os.toByteArray();
```
Yazılan dosya **hiçbir yerde geri okunmuyor** (metod `os.toByteArray()` döndürür).
Yani `Files.write(...)` ölü debug kodudur; onu no-op yapmak (kaldırmak) tam ve
güvenli çözümdür. Javassist `ExprEditor` ile `java.nio.file.Files.write` çağrısını
boş blokla değiştiririz.

- [ ] **Step 1: `scripts/patch-visible-signature.sh` yaz**

```bash
#!/usr/bin/env bash
# VisibleSignatureImageCreator.createImage içindeki ölü "C:\1\imza.png" yazımını
# (Files.write) kaldırır. javac/java için JDK 17+ gerekir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR="$ROOT/build/app/Ard.ESignature.jar"
JAVASSIST="$ROOT/.jre-cache/javassist.jar"
# javac/java: sistem (17+) ya da indirilmiş Zulu 21
JBIN="$(command -v javac >/dev/null 2>&1 && dirname "$(command -v javac)" || echo "$ROOT/.jre-cache/zulu21/bin")"

test -f "$JAR" || { echo "build/app/Ard.ESignature.jar yok — önce prep"; exit 1; }
if [ ! -f "$JAVASSIST" ]; then
  echo ">> javassist indiriliyor..."
  curl -fsSL -o "$JAVASSIST" \
    "https://repo1.maven.org/maven2/org/javassist/javassist/3.30.2-GA/javassist-3.30.2-GA.jar"
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/out"
cat > "$WORK/Patch.java" <<'JAVA'
import javassist.*;
import javassist.expr.*;

public class Patch {
  public static void main(String[] args) throws Exception {
    String jar = args[0], outDir = args[1];
    ClassPool cp = ClassPool.getDefault();
    cp.insertClassPath(jar);
    CtClass cc = cp.get("utilities.signer.pades.VisibleSignatureImageCreator");
    CtMethod m = cc.getDeclaredMethod("createImage");
    m.instrument(new ExprEditor() {
      @Override public void edit(MethodCall c) throws CannotCompileException {
        if (c.getClassName().equals("java.nio.file.Files")
            && c.getMethodName().equals("write")) {
          // Dönüş değeri kullanılmadığı için çağrıyı no-op'a indir.
          c.replace("{ }");
        }
      }
    });
    cc.writeFile(outDir);   // outDir/utilities/signer/pades/VisibleSignatureImageCreator.class
    System.out.println("patched");
  }
}
JAVA

"$JBIN/javac" -cp "$JAVASSIST" -d "$WORK/out" "$WORK/Patch.java"
"$JBIN/java"  -cp "$WORK/out:$JAVASSIST" Patch "$JAR" "$WORK/classes"
# yamalı .class'ı jar'a geri yaz
( cd "$WORK/classes" && zip -q "$JAR" utilities/signer/pades/VisibleSignatureImageCreator.class )
echo ">> visible-signature yaması uygulandı"
```

- [ ] **Step 2: `prep-payload.sh` sonuna koşullu çağrı ekle**

`scripts/prep-payload.sh` dosyasında, `rm -f "$DST/sunpkcs11.jar"` satırından
sonra (echo'dan önce) şunu ekle:

```bash
# 3) (opsiyonel) görünür imza yolundaki ölü Windows yazımını kaldır
if [ "${PATCH_VISIBLE_SIG:-0}" = "1" ]; then
  "$ROOT/scripts/patch-visible-signature.sh"
fi
```

- [ ] **Step 3: Çalıştırılabilir yap ve doğrula**

Run:
```bash
chmod +x scripts/patch-visible-signature.sh
PATCH_VISIBLE_SIG=1 ./scripts/prep-payload.sh
javap -c -classpath build/app/Ard.ESignature.jar \
  utilities.signer.pades.VisibleSignatureImageCreator | grep -c 'imza.png'
```
Expected: `prep OK`, `>> visible-signature yaması uygulandı`, ve son grep `0`
(sabit `C:\1\imza.png` referansı jar'dan kalkmış).

- [ ] **Step 4: Commit**

```bash
git add scripts/patch-visible-signature.sh scripts/prep-payload.sh
git commit -m "Add optional visible-signature bytecode patch (off by default)"
```

---

## Task 10 (DONANIM DOĞRULAMASI): Gerçek AKİS kartıyla uçtan uca imza

**Bu task fiziksel AKİS kart + okuyucu gerektirir.** Bu makinede AKİS arm64
sürücüsü kurulu; kart+okuyucu bağlıyken uçtan uca doğrulanabilir. Aksi halde bu,
kullanıcı tarafından yapılacak son kabul testidir.

**Interfaces:**
- Consumes: `/Applications/UHAPImza.app` (Task 7), fiziksel AKİS kart.

- [ ] **Step 1: Sürücü ve kart hazır mı**

Run:
```bash
lipo -archs /usr/local/lib/libakisp11.dylib   # arm64 içermeli
```
Expected: `x86_64 arm64` veya `arm64`. Kart+okuyucu takılı olmalı.

- [ ] **Step 2: Uygulamayı başlat ve sertifika enumerasyonunu test et**

Run:
```bash
pkill -f UHAPImza 2>/dev/null; sleep 1
open /Applications/UHAPImza.app
sleep 12
tail -20 "$HOME/Library/Logs/UHAPImza/log.out"
```
Expected: log'da PKCS#11/SunPKCS11 başlatma hatası **yok**; `libakisp11` yüklenir; SunPKCS11 modül erişim uyarısı (`--add-exports`) çıkmaz. Kart slot'u görülür.

Hata durumları ve fallback:
- `IllegalAccessError: sun.security.pkcs11.wrapper` → `--add-exports` modülü/yazımı yanlış; `jdk.crypto.cryptoki` olduğunu doğrula.
- `sun.security.smartcardio` reflektif erişim hatası (kurtarma yolu) → build-app.sh'e `--add-opens=java.smartcardio/sun.security.smartcardio=ALL-UNNAMED` ekle, yeniden build.
- `libakisp11.dylib ... yüklenemedi` → arm64 sürücü kurulu değil ya da yolu farklı; sürücü kurulumunu/yolunu doğrula.

- [ ] **Step 3: Gerçek portal imza akışı**

Tarayıcıda https://uhap.com.tr açılır, bir belge imzalama akışı başlatılır, PIN
girilir. Beklenen: `/getcertificates` sertifikaları döndürür, imza tamamlanır ve
imzalı belge UHAP'a yüklenir.

- [ ] **Step 4: Sonucu not et**

Doğrulama sonucunu (başarı / karşılaşılan hata + uygulanan fallback) README
"Bilinen Sınırlar" veya bir `docs/` notuna yaz ve commit et.

---

## Notlar

- **Test felsefesi:** Bu bir paketleme projesidir; "test"ler build/çalıştırma
  doğrulamalarıdır (bundle üretimi, server bind, config çözümü, log yazımı, kart
  enumerasyonu). Birim testi altyapısı yoktur; her task kendi doğrulama
  komutuyla biter.
- **Fallback kararları** spec §8'de listelidir; işlevsel bir doğrulama başarısız
  olursa oraya bakılır (körlemesine bayrak eklenmez).
- **AKİS dylib yolu** (`/usr/local/lib`) bu makinede doğrulandı; farklı kurulum
  yolu çıkarsa build-app.sh'e açık kütüphane yolu eklenir.
