# UHAP İmzalama — macOS (Apple Silicon) Port

UHAP e-imza aracının (ARDGRUP/ImzaTek tabanlı) Apple Silicon Mac'ler için
topluluk portu. **Resmi değildir**; UHAP veya TÜBİTAK tarafından
geliştirilmemiştir. Yalnızca paketleme betikleri içerir; Java uygulamasının
kendisi değiştirilmez (yalnızca log yolu ve platform uyumu için küçük yamalar).

## Gereksinimler

- Apple Silicon (arm64) Mac, macOS.
- AKİS akıllı kart + kart okuyucu.
- **AKİS macOS arm64 sürücüsü** (aşağıya bkz.).
- İnternet bağlantısı (kurulum ve sertifika doğrulaması için).

## Kurulum

```bash
git clone <repo-url> uhap-eimza-mac
cd uhap-eimza-mac
./kur.sh
```

`kur.sh`: gerekli Java runtime'ı indirir, `.app`'i derler,
`/Applications/UHAPImza.app` olarak kurar ve AKİS sürücü durumunu bildirir.
İnternet gerekir (Java runtime indirimi için).

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

1. "UHAP İmzalama"yı açın (arka planda `localhost:8080`'de sabit portlu bir
   sunucu çalıştırır).
2. Tarayıcıda https://uhap.com.tr açın ve imzalama akışını başlatın.
3. Kart PIN'inizi girin.

Loglar: `~/Library/Logs/UHAPImza/log.out`.

## Sorun Giderme

- **Gatekeeper "açılamıyor":** Uygulama ad-hoc imzalıdır; ilk açılışta
  uygulamaya sağ tık → Aç gerekebilir.
- **8080 meşgul:** Portu kullanan başka uygulamayı kapatın (port sabittir,
  değiştirilemez).
- **Sertifika doğrulama hatası:** Uygulama doğrulama için
  `depo.kamusm.gov.tr`'ye ağ üzerinden erişir; internet bağlantısı gerekir.
- **Görünür (visible) imza sorunu:** Bu portta görünür imza yolu sınırlıdır
  (bkz. Bilinen Sınırlar).
- Sorunları incelemek için log dosyasına bakın:
  `~/Library/Logs/UHAPImza/log.out`.

## Bilinen Sınırlar

- Yalnızca arm64; Intel Mac'ler desteklenmez.
- Notarize edilmemiştir (ad-hoc imza); Gatekeeper ilk açılışta uyarabilir.
- Görünür PDF imzası (imza görselini PDF'e gömme) test edilmemiştir ve
  çalışmayabilir; kaynak uygulamada bu yol Windows'a özgü bir dosya yolu
  içerir. Test edilen yol görünmez (non-visible) imzalamadır.
- Sertifika doğrulaması `depo.kamusm.gov.tr`'ye ağ erişimi gerektirir;
  çevrimdışı çalışmaz.
- Kart tipi: yalnızca AKİS test edilmiştir. Diğer token'lar denenmemiştir.
- Yerel sunucu tüm ağ arayüzlerine bağlanır (`*:8080`); yerel ağdan (LAN)
  erişilebilir durumdadır. Güvenilmeyen ağlarda bunu göz önünde bulundurun.

## Lisans / Sorumluluk

Paketleme betikleri topluluk katkısıdır. UHAP/ARDGRUP/TÜBİTAK marka ve
yazılım hakları sahiplerine aittir.
