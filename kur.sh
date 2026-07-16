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

# 3) Repo kökünü bul; `curl | bash` ile çalıştırıldıysa repoyu klonla/güncelle
REPO_URL="https://github.com/saidsurucu/uhap-eimza-mac-arm64.git"
CLONE_DIR="$HOME/uhap-eimza-mac-arm64"
if [ -f "./Makefile" ] && [ -d "./app" ]; then
  REPO_ROOT="$(pwd)"                                   # repo kökünden çalıştırıldı
elif [ -n "${BASH_SOURCE:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/Makefile" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # bash /yol/kur.sh
else
  # curl | bash ile çalıştırıldı: depoyu klonla ya da güncelle
  if [ -d "$CLONE_DIR/.git" ]; then
    info "Mevcut kopya güncelleniyor: $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only || warn "güncelleme atlandı (yerel değişiklik olabilir)"
  else
    info "Depo klonlanıyor: $CLONE_DIR"
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  REPO_ROOT="$CLONE_DIR"
fi
cd "$REPO_ROOT"
[ -f Makefile ] && [ -d app ] || die "Repo kökü bulunamadı: $REPO_ROOT"

# 4) Build + kur
if [ ! -f assets/UHAPImza.icns ]; then info "İkon üretiliyor..."; ./scripts/make-icns.sh >/dev/null || warn "ikon üretilemedi (kozmetik)"; fi
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
