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

info "Bu kurucu resmi değildir; UHAP İmzalama'nın topluluk portudur."

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
