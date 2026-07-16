# UHAP İmzalama Aracı — macOS (Apple Silicon) Port Tasarımı

**Tarih:** 2026-07-16
**Durum:** Onay bekliyor

## 1. Amaç

Windows için dağıtılan `UHAPImzalamaAraci.msi` içindeki UHAP e‑imza aracını,
Apple Silicon (arm64) Mac'lerde çift tıklamayla çalışan native bir `.app`
paketine dönüştürmek. Referans desen: kullanıcının kendi
`saidsurucu/edevlet-eimza-mac-arm64` reposu (jpackage app-image + gömülü JRE +
AKİS dylib + Makefile/kur.sh/dmg).

## 2. Kaynak Uygulamanın Analizi (MSI'dan çıkarıldı)

- **Tür:** Saf Java Swing masaüstü uygulaması. ARDGRUP / ImzaTek imzalama
  aracının UHAP markalı sürümü.
- **Ana motor:** `Ard.ESignature.jar`, ana sınıf `root.App`. Yanında 60 kütüphane
  JAR'ı (TÜBİTAK ESYA `ma3api-*`, Apache PDFBox/POI, HTTP client, sqlite-jdbc,
  jna, sunpkcs11 vb.). Toplam ~82 MB (en büyük tek dosya `Ard.ESignature.jar`
  ~40 MB; GitHub'ın 100 MB dosya sınırının altında).
- **Çalışma modeli:** `localhost:8080` üzerinde bir HTTP sunucusu açar
  (`com.sun.net.httpserver.HttpServer`). Endpoint'ler: `/imza`, `/imzapost`,
  `/uyaplogin`, `/getcertificates`. Tarayıcıdaki UHAP portalı (uhap.com.tr) bu
  yerel sunucuya istek atar; uygulama AKİS akıllı karttan PKCS#11 ile imzalar.
- **Başlangıç argümanı:** `root.App.main(args)` bir konfigürasyon argümanı
  bekler. Prod için doğru değer: **`uhap-prod`** (→ `BASE_URL=https://uhap.com.tr/`,
  `SIGNER_CHECK_URL=https://uhap.com.tr/api/SignerCheck`, `HTTP_SERVER_PORT=8080`).
- **Config yükleme:** `config/*.xml`, `TrustedCertificates/SertifikaDeposu.svt`
  ve `certval-policy*.xml` dosyaları `constants.ROOT_DIR = System.getProperty("user.dir")`
  köküne göre okunur (`SignerBase.getRootDir()`, `PadesSigner` içinde
  `getRootDir() + "/config/esya-signature-config.xml"`).

### Windows'a özgü olan ve değiştirilecek parçalar
1. `UhapSigner.exe` — Launch4j launcher (sadece `java -jar` çağırıyor). **Atılacak.**
2. Gömülü Windows JRE. **Zulu 11 arm64 ile değiştirilecek.**
3. Akıllı kart native PKCS#11 sürücüsü (`akisp11.dll`). **macOS'ta AKİS arm64
   `libakisp11.dylib` kullanıcı tarafından `/usr/local/lib/`'e kurulur.**

### Doğrulama bulguları
- Uygulama, sistemdeki Zulu Java 21 ile **çalıştırıldı**: HTTP sunucusu 8080'de
  ayağa kalktı, `/imza` isteği işlendi (gerçek imza süreci olmadığı için 503).
  Yani Java katmanı zaten cross-platform.
- **PKCS#11 wrapper: SunPKCS11** (`sun.security.pkcs11.wrapper.PKCS11`). IAIK
  **yok**. Yanında 2008 tarihli eski bir `sunpkcs11.jar` taşınıyor. Bu, e‑Devlet
  portundaki IAIK'e özel Javassist arm64 yamasının burada **gerekmediği**
  anlamına gelir; buradaki analog risk SunPKCS11 modül erişimi (aşağıda).
- e‑Devlet reposundaki `elektronik-imza.jar` (ana sınıf
  `tr.gov.turkiye.esignui.run.StartFrame`, IAIK) ile UHAP'ın JAR'ları **farklı
  uygulamalardır**; ortak indirme kaynağı yoktur.

## 3. Karar: JAR'ları Repoya Gömme

MSI'ın kamuya açık bir indirme endpoint'i yok ve e‑Devlet kaynağıyla uyuşmuyor.
Bu nedenle **çıkarılmış JAR'lar + `config/` + `TrustedCertificates/` doğrudan
repoya gömülür** (payload ~82 MB). `kur.sh` MSI çıkarma / indirme yapmaz; sadece
JRE indirir ve jpackage çalıştırır.

## 4. Repo Yapısı

```
uhap-eimza-mac/
├── app/                        # Gömülü çalışma zamanı payload'u (jpackage --input)
│   ├── *.jar                   # 61 JAR (Ard.ESignature.jar dahil)
│   ├── config/                 # esya-signature-config.xml, smartcard-config.xml, certval-policy*.xml
│   └── TrustedCertificates/    # SertifikaDeposu.svt
├── assets/
│   ├── UHAPImza.icns           # favicon.ico'dan üretilecek ikon
│   └── dmg-background.*         # (opsiyonel) DMG arka planı
├── scripts/
│   └── build-app.sh            # jpackage sarmalayıcı (Makefile'dan çağrılır)
├── Makefile                    # jre, app, dmg, run, install, clean hedefleri
├── kur.sh                      # tek-komut kurucu (curl | bash)
├── .gitignore                  # build/, .jre-cache/ vb.
├── .github/workflows/release.yml  # (opsiyonel) sürüm otomasyonu
└── README.md
```

## 5. Build Akışı (jpackage)

`make app` şunu çalıştırır:

```sh
jpackage \
  --type app-image \
  --name UHAPImza \
  --input app/ \
  --main-jar Ard.ESignature.jar \
  --main-class root.App \
  --arguments uhap-prod \
  --runtime-image <zulu-11-arm64-jre> \
  --java-options "-Duser.dir=\$APPDIR" \
  --java-options "--add-exports=java.base/sun.security.pkcs11.wrapper=ALL-UNNAMED" \
  --icon assets/UHAPImza.icns \
  --dest build/
```

Önemli noktalar:
- **`-Duser.dir=$APPDIR`**: Uygulama config'i `user.dir`'e göre okuduğu için,
  jpackage'ın `$APPDIR` token'ı (runtime'da `.app/Contents/app`'e genişler)
  `user.dir` olarak set edilir. Böylece `config/` ve `TrustedCertificates/`
  bundle içinden bulunur. `.app` çift tıklamayla açıldığında aksi halde
  `user.dir` `/` olur ve config bulunamaz.
- **`--add-exports ...sun.security.pkcs11.wrapper`**: ESYA bu JDK-iç paketine
  doğrudan eriştiği için Java 11'de modül erişimi açılmalı.
- **JRE:** Azul **Zulu 11 arm64** (`make jre` ile indirilip `.jre-cache/`'e
  koyulur; e‑Devlet portunda kanıtlanmış sürüm, HiDPI/Retina destekli).
- Ad-hoc imza: jpackage sonrası `codesign -s - --deep --force build/UHAPImza.app`.
  Executable adı ASCII (`UHAPImza`); kullanıcıya görünen ad `Info.plist`'te
  `CFBundleDisplayName` ile Türkçe yazılabilir.

`make dmg`: `build/UHAPImza.app`'ten sürükle-bırak `UHAPImza.dmg` üretir
(hdiutil, /Applications sembolik linki).

`kur.sh`: Xcode CLT kontrolü → repoyu klonla/güncelle → `make jre` → `make app`
→ `codesign` → `/Applications`'a kopyala → AKİS sürücü talimatlarını yazdır.

## 6. Akıllı Kart (AKİS / PKCS#11)

- Uygulama `smartcard-config.xml`'de `AKIS` kart tipi için `akisp11`
  kütüphanesini arar. macOS'ta bu `libakisp11.dylib`'e çözülür ve JDK'nin
  `libj2pkcs11.dylib`'i tarafından `dlopen` edilir.
- **Kullanıcı adımı (README'de):** TÜBİTAK BİLGEM'den
  (https://akiskart.bilgem.tubitak.gov.tr/tr/destek/) **"Mac OS Arm (Apple
  Silicon)"** etiketli AKİS paketini indirip kurar; `libakisp11.dylib`
  `/usr/local/lib/` altında olmalı. Doğrulama: `lipo -archs
  /usr/local/lib/libakisp11.dylib` → `arm64` içermeli.

## 7. Bilinen Riskler ve Fallback'ler

1. **SunPKCS11 kart yolu (BAŞLICA RİSK):** Zulu 11 arm64 + eski (2008)
   `sunpkcs11.jar` + `--add-exports` kombinasyonunda kart okuma/imzalama ancak
   **gerçek AKİS kartıyla** doğrulanabilir. HTTP sunucusu ve JAR yükleme kısmı
   Mac'te çalışır durumda görüldü; kart yolu doğrulanmadı.
   - **Fallback A:** Eski `sunpkcs11.jar`'ı classpath'ten çıkarıp JDK'nin kendi
     `sun.security.pkcs11` modülüne bırakmak (native/Java sürüm uyumu için).
   - **Fallback B:** Gerekirse ek `--add-opens` bayrakları (jaxb/reflection).
   - **Fallback C:** JRE sürümünü değiştirmek (Zulu 8 tam uyum ama HiDPI yok /
     jpackage desteği yok; Zulu 17/21 alternatif).
2. **Config yolu:** `-Duser.dir=$APPDIR` beklendiği gibi genişlemezse, config'i
   mutlak yolla veren küçük bir launcher wrapper'a geçilir.
3. **Kod imzalama / Gatekeeper:** Ad-hoc imza yeterli (kullanıcı ilk açılışta
   sağ tık → Aç). Notarization kapsam dışı.
4. **HTTPS/mixed-content:** Portal `https://uhap.com.tr`, yerel sunucu
   `http://localhost:8080`. Windows'ta çalıştığı için mimari aynı; ek bir
   sertifika işi beklenmiyor, doğrulama sırasında izlenecek.

## 8. Kapsam Dışı (YAGNI)

- Intel (x86_64) desteği — sadece arm64 hedefleniyor.
- Notarization / Apple Developer imzası.
- Otomatik güncelleme mekanizması (uygulamanın kendi VERSION_URL kontrolü
  `uhap-prod`'da devrede; ayrıca bir şey yapılmayacak).
- UYAP dışı diğer portal config'leri (eusigner, uksigner vb.) — sadece
  `uhap-prod`.

## 9. Doğrulama Kriterleri

1. `make app` hatasız `build/UHAPImza.app` üretir.
2. `.app` çift tıklamayla açılır, HTTP sunucusu 8080'de dinler
   (`curl localhost:8080/imza` → app log'unda istek görülür).
3. Uygulama log'unda config/TrustedCertificates yolu doğru çözülür (503 değil,
   config-not-found hatası olmamalı).
4. AKİS kartı takılıyken `/getcertificates` sertifikaları döndürür ve gerçek bir
   UHAP imza akışı tamamlanır. *(Donanım gerektiren adım — kullanıcı doğrulaması.)*
5. `make dmg` kurulabilir `UHAPImza.dmg` üretir.
