# Doğrulama Notları (macOS Apple Silicon Port)

Bu belge, port çıktısının bu makinede (Apple Silicon) yapılan gerçek
doğrulamalarını özetler.

## Payload kaynağı (provenance)
Repodaki `app/` altındaki 61 JAR + `config/` + `TrustedCertificates/`, aşağıdaki
resmi Windows kurulum paketinden (MSI) `msiextract` ile çıkarılmıştır:
- Dosya: `UHAPImzalamaAraci (1).msi`
- SHA-256: `6c150820f847cb1f55a51079b65927140fdd9d707ab61891426412af4278e8db`

MSI'ın kendisi repoya dahil edilmez (`.gitignore` → `*.msi`). JAR'lar çıkarıldığı
haliyle (pristine) commit'lidir; tüm platform yamaları yalnızca build sırasında
`build/` kopyası üzerinde uygulanır.

## Ortam
- Mimari: macOS arm64 (Apple Silicon).
- Build aracı: sistem `jpackage` (Zulu 21). Runtime: gömülü **Zulu 11 arm64**
  (`jdk.crypto.cryptoki` + `java.smartcardio` modülleri mevcut).
- Kart okuyucu: **ACS ACR39U ICC Reader**, kart takılı (`cardPresent=true`).
- AKİS sürücüsü: `/usr/local/lib/libakisp11.dylib`, universal (`x86_64 arm64`).

## Uygulama katmanı (Task 5 — otomatik doğrulandı)
`build/UHAPImza.app` çift tıklamayla başlatıldı:
- `localhost:8080` HTTP sunucusu ayağa kalktı (`/imza` isteği işlendi).
- Config, bundle içinden çözüldü (`-Duser.dir=$APPDIR` çalışıyor); log ilk satırı
  `Application started. .../UHAPImza.app/Contents/app`.
- Log, yazılabilir yola yazıldı: `~/Library/Logs/UHAPImza/log.out` (read-only
  bundle'a yazma denemesi yok).
- `sun.security.pkcs11.wrapper` için `IllegalAccessError` görülmedi
  (`--add-exports=jdk.crypto.cryptoki/...` doğru).

## Akıllı kart / PKCS#11 katmanı (Task 10 — GERÇEK KARTLA DOĞRULANDI)
Portun en büyük riski, **arm64 Zulu 11 SunPKCS11'in AKİS `libakisp11.dylib`'ini
yükleyip kartla imza üretmesi** idi. Uygulamanın shipping runtime'ı ile iki probu
çalıştırıldı:

**1) Provider + token erişimi (PIN'siz):** `Provider.configure()` ile
**`SunPKCS11-AKIS`** provider'ı arm64 runtime'da AKİS dylib'ine sorunsuz bağlandı;
native yükleme/mimari/modül hatası **yok**.

**2) Uçtan uca imza (kart + PIN, kullanıcı PIN'i sağladı):** Uygulamanın (TÜBİTAK
ESYA / ma3api) kullandığı **birebir düşük-seviye `sun.security.pkcs11.wrapper`
API'si** ile:
- Okuyucu: `ACS ACR39U ICC` — 1 token'lı slot.
- `C_Login(CKU_USER, PIN)` → **LOGIN OK** (kimlik doğrulamalı erişim çalışıyor).
- Kartta 1 özel anahtar + gerçek nitelikli sertifika bulundu (sertifika sahibinin
  kimlik bilgileri gizlilik gereği burada paylaşılmamıştır).
- Token'ın desteklediği mekanizmalar: `CKM_RSA_PKCS` (0x1), `CKM_ECDSA` (0x1041).
  Anahtar tipi **RSA-2048**.
- `C_SignInit(CKM_RSA_PKCS) + C_Sign` → **GERÇEK İMZA ÜRETİLDİ, 256 byte
  (RSA-2048).** Yani arm64 + AKİS üzerinden ESYA'nın kullandığı imza yolu uçtan
  uca **çalışıyor**.

> Güvenlik notu: Yanlış PIN AKİS kartını kilitleyebileceği için yalnızca doğru
> PIN ile TEK login denendi (başarılı; hatalı deneme yok). PIN diske yazılmadı.

## Uçtan uca imza testi (2026-07-16) — iki gerçek hata bulundu ve düzeltildi
Gerçek bir belgeyle UHAP portalı üzerinden PAdES imzası denendiğinde iki hata
çıktı; ikisi de kalıcı olarak düzeltildi ve sonra imza **başarıyla** tamamlandı.

**Hata 1 — Sürücü yanlış konumdan/mimariden yükleniyor.** Uygulama (ESYA
`OpsUtil`) sürücüyü `java.library.path` üzerinden, yani önce
`~/Library/Java/Extensions/libakisp11.dylib`'ten yükler. AKİS'in Intel kurulumu
oraya **yalnızca x86_64** dylib koyduğu için arm64 JRE yükleyemedi
(`incompatible architecture (have 'x86_64', need 'arm64')`).
→ **Kalıcı düzeltme:** `kur.sh`, `~/Library/Java/Extensions/libakisp11.dylib`
arm64 değilse arm64 içeren bir kaynağı (örn. `/usr/local/lib`) oraya kopyalar
(eskisini `.x86_64.bak` olarak yedekler).

**Hata 2 — `certval-policy.xml` bundle'da yanlış klasörde aranıyor.**
`esya-signature-config.xml` içindeki `<certificate-validation-policy-file>
certval-policy.xml</...>` göreli referansı, bağlam kök URI'sine
(`user.dir = $APPDIR = Contents/app`) göre çözülüyor; dosya ise `Contents/app/
config/` altındaydı → `FileNotFoundException: .../Contents/app/certval-policy.xml`.
→ **Kalıcı düzeltme:** `scripts/prep-payload.sh` artık config XML'lerini
`config/`'e ek olarak `$APPDIR` köküne de kopyalıyor.

Her iki düzeltme uygulanınca (arm64 sürücü + kök config) imza uçtan uca çalıştı.

## Kalan: uygulama-portal entegrasyonu (kullanıcı kabul testi)
Kriptografik imza yolu kanıtlandığından geriye yalnızca uygulamanın kendi
tarayıcı↔localhost↔ESYA akışı kalıyor:
1. `/Applications/UHAPImza.app` açık.
2. Tarayıcıda https://uhap.com.tr → imzalama akışı başlat.
3. Kart PIN'i gir → belge imzalanır ve UHAP'a yüklenir.

Hata olursa `~/Library/Logs/UHAPImza/log.out` bakılır; fallback kararları
`docs/superpowers/specs/2026-07-16-uhap-eimza-mac-port-design.md` §8'de.
