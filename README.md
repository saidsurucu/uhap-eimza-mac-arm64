# UHAP İmzalama — macOS (Apple Silicon) Portu

UHAP e-imza aracının (ARDGRUP/ImzaTek tabanlı) Apple Silicon Mac'ler için
**resmi olmayan, topluluk** portu. Gömülü arm64 Java 11 runtime ile native bir
`.app` üretir; Rosetta veya ayrı Java kurulumu gerekmez.

## Kurulum (tek komut)

Terminale şunu yapıştırın:

```bash
curl -fsSL https://raw.githubusercontent.com/saidsurucu/uhap-eimza-mac-arm64/main/kur.sh | bash
```

Bu betik sırayla: Xcode Command Line Tools'u (gerekirse) kurar, depoyu
`~/uhap-eimza-mac-arm64` altına klonlar, arm64 Java 11 runtime'ını indirir,
`UHAPImza.app`'i derleyip imzalar ve `/Applications`'a kurar. İnternet gerekir.

Kurulumdan sonra **UHAP İmzalama**'yı Launchpad/Uygulamalar'dan açın.

## Zorunlu: AKİS arm64 sürücüsü

Uygulama akıllı kartı `libakisp11.dylib` üzerinden okur ve **arm64** kod olarak
çalışır; Intel sürücü arm64 sürece yüklenemez. TÜBİTAK BİLGEM'den
**"Mac OS Arm (Apple Silicon)"** etiketli AKİS paketini kurun:

- https://akiskart.bilgem.tubitak.gov.tr/tr/destek/

Doğrulama (arm64 içermeli):

```bash
lipo -archs /usr/local/lib/libakisp11.dylib
```

`kur.sh`, uygulamanın sürücüyü aradığı yere (`~/Library/Java/Extensions/`)
arm64 `libakisp11.dylib`'i otomatik yerleştirir; oradaki eski Intel sürücüyü
`.x86_64.bak` olarak yedekler. AKİS arm64 paketini kurduktan sonra `kur.sh`'i
(tekrar) çalıştırmanız yeterlidir. Intel-only sürücü kuruluysa kart okunamaz;
arm64 paketini kurun.

## Kullanım

1. **UHAP İmzalama**'yı açın (arka planda `localhost:8080`'de çalışır).
2. Tarayıcıda https://uhap.com.tr açıp imzalama akışını başlatın.
3. Kart PIN'inizi girin; belge imzalanır.

Loglar: `~/Library/Logs/UHAPImza/log.out`

## Teknik özet

- **jpackage + Zulu 11 arm64**: `.app` içine gömülü runtime (HiDPI/Retina).
- **SunPKCS11 yolu**: uygulama TÜBİTAK ESYA (ma3api) ile SunPKCS11 üzerinden
  imzalar; `jdk.crypto.cryptoki` modülü `--add-exports` ile açılır.
- **Config çözümü**: `-Duser.dir=$APPDIR` ile config bundle içinden okunur.
- **Yazılabilir log yolu** ve **ASCII executable adı** (`UHAPImza`) +
  ad-hoc `codesign`.

arm64 Zulu 11 + AKİS ile uçtan uca gerçek imza (RSA-2048) bu makinede
doğrulanmıştır — bkz. `docs/VERIFICATION.md`.

## Elle derleme

```bash
git clone https://github.com/saidsurucu/uhap-eimza-mac-arm64.git
cd uhap-eimza-mac-arm64
make app        # sadece .app'i derle (build/UHAPImza.app)
make dmg        # sürükle-bırak disk imajı
make run        # derleyip çalıştır
make install    # /Applications'a kur
```

## Sorun giderme

- **Gatekeeper "açılamıyor":** Uygulamaya sağ tık → **Aç** (ad-hoc imzalı).
- **8080 meşgul:** Portu kullanan başka uygulamayı kapatın (port sabittir).
- **"kütüphane yüklenemedi" / kart okunmuyor:** AKİS **arm64** sürücüsünü kurun.
- **Sertifika doğrulama hatası:** Uygulama `depo.kamusm.gov.tr`'ye erişir;
  internet gerekir.

## Bilinen sınırlar

- Yalnızca **arm64** (Apple Silicon); Intel desteklenmez.
- **Notarize edilmemiştir** (ad-hoc imza; ilk açılışta sağ tık → Aç).
- Görünür (visible) PDF imzası test edilmemiştir; kaynak uygulamada bu yol
  Windows'a özgü bir dosya yolu içerir (görünmez imza test edilen yoldur).
- Kart tipi: **AKİS**. Diğer token'lar test edilmemiştir.
- Yerel sunucu tüm arayüzlerde (`*:8080`) dinler; yerel ağdan erişilebilir.

## Sorumluluk reddi

Bu depo **resmi değildir**; UHAP, ARDGRUP veya TÜBİTAK tarafından geliştirilmemiş
ya da onaylanmamıştır. Yalnızca paketleme ve derleme betikleri sağlar. UHAP /
ARDGRUP / TÜBİTAK marka ve yazılım hakları sahiplerine aittir.
