# UHAP İmzalama Aracı — macOS (Apple Silicon) Port Tasarımı

**Tarih:** 2026-07-16
**Durum:** Onay bekliyor (Codex/gpt-5.6-sol bağımsız incelemesiyle revize edildi)

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
  Not: `uhap-prod` dalında `VERSION_URL` **atanmaz** (boş kalır), dolayısıyla
  uygulama açılışta sürüm kontrolünü **atlar** — ayrıca bir güncelleme işi yok.
- **Config yükleme:** `config/*.xml` ve `certval-policy.xml` dosyaları
  `constants.ROOT_DIR = System.getProperty("user.dir")` köküne göre okunur
  (`SignerBase.getRootDir()`, `PadesSigner` içinde
  `getRootDir() + "/config/esya-signature-config.xml"`).
- **Trust store (DÜZELTME):** Prod politikası (`config/certval-policy.xml`)
  sertifika deposunu **uzak HTTP**'den çeker:
  `storepath=http://depo.kamusm.gov.tr/depo/SertifikaDeposu.xml`. Gömülü
  `TrustedCertificates/SertifikaDeposu.svt` yalnızca kullanılmayan **test**
  politikasında geçer ve içinde sabit bir Windows yolu vardır. Yani prod'da SVT
  dosyası kullanılmaz; sertifika doğrulaması **ağ bağlantısı gerektirir** (risk
  bölümüne bkz.).

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

## 5. Payload Hazırlama (Yama Adımı)

Codex incelemesi, "tüm JAR'lar olduğu gibi cross-platform" varsayımının fazla
iyimser olduğunu gösterdi. `app/` payload'u gömülmeden önce küçük ve **belirleyici**
düzeltmeler gerekir (`make prep` / `scripts/prep-payload.sh`):

1. **Log yolu (BLOCKER):** `Ard.ESignature.jar` içindeki `log4j.properties`,
   `log4j.appender.fileLogger.File=./log/log.out` ile göreli yola yazar.
   `user.dir=$APPDIR` (read-only `/Applications/...app`) altında bu **başarısız
   olur**. Log4j 1.x `${...}` sistem-property genişletmesini desteklediği için
   kaynak dosya şu şekilde düzenlenir (bytecode yaması gerekmez):
   `File=${user.home}/Library/Logs/UHAPImza/log.out`.
2. **`sunpkcs11.jar` çıkarılır:** 2008 tarihli bu jar, Java 11'de
   `jdk.crypto.cryptoki` modülüyle split-package belirsizliği yaratır. `app/`'ten
   ve `Ard.ESignature.jar` manifest Class-Path'inden çıkarılır; wrapper sınıfları
   zaten `--add-exports` ile modülden gelir.
3. **Görünür imza yazımı (KOŞULLU BLOCKER):**
   `VisibleSignatureImageCreator.class:62` sabit `Files.write(Paths.get("C:\\1\\imza.png"), ...)`
   çağrısı yapar. Görünür (visible) PDF imzası kullanılırsa macOS'ta patlar.
   Gözlemlenen UHAP akışında `VisibleSignature: false` idi; bu yüzden bu bir
   **koşullu** engel. Görünür imza gerekiyorsa bu sınıf bytecode-yama ile
   nötrlenir (yazımı kaldır veya `java.io.tmpdir`'e yönlendir); gerekmiyorsa
   dokunulmaz ve README'de not düşülür.
4. **Gereksiz native jar'lar (opsiyonel temizlik):** `armeabi-0.0.1.jar` (Android
   ARM `.so`) ve `ma3api-smartcard-android-*` masaüstü macOS için gereksiz;
   bağımlılık testinden sonra classpath karmaşasını azaltmak için çıkarılabilir.

## 6. Build Akışı (jpackage)

**Build JDK gereksinimi:** `jpackage` JDK 11'de **yoktur** (GA JDK 16+). Bu yüzden
build makinesinde **JDK 17/21** (jpackage içeren) gerekir; çalışma zamanı olarak
`--runtime-image` ile **Zulu 11 arm64** gömülür. `kur.sh` her ikisini de sağlar:
build için bir jpackage-JDK, runtime için Zulu 11.

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
  --java-options "--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED" \
  --icon assets/UHAPImza.icns \
  --dest build/
```

Önemli noktalar:
- **`-Duser.dir=$APPDIR`**: Uygulama config'i `user.dir`'e göre okuduğu için,
  jpackage'ın `$APPDIR` token'ı (runtime'da `.app/Contents/app`'e genişler)
  `user.dir` olarak set edilir. Böylece `config/` bundle içinden bulunur. `.app`
  çift tıklamayla açıldığında aksi halde `user.dir` `/` olur ve config bulunamaz.
  Yazılabilir yollar (log) $APPDIR'e düşmesin diye yukarıdaki payload yaması
  şarttır; geçici dosyalar zaten `java.io.tmpdir`'e yazılıyor.
- **`--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED`**
  (DÜZELTME): Paket `java.base`'de değil `jdk.crypto.cryptoki` modülündedir.
  Önceki `java.base/...` yazımı "paket java.base'de yok" uyarısı üretirdi.
  `--runtime-image`'ın `jdk.crypto.cryptoki` ve `java.smartcardio` modüllerini
  içerdiğinden emin olunur (tam Zulu runtime içerir).
- **Runtime JRE:** Azul **Zulu 11 arm64** (`make jre`). Gerekçe: ana jar
  class-file sürümü 55 (Java 11); MSI'daki Windows runtime da Java 11.0.19; Java
  11 kütüphanenin JDK-iç reflection'ına 17/21'den daha müsamahakâr. Java 21'de
  gözlenen "açılış çalıştı" kanıtı PKCS#11/PC-SC/PIN/sertifika/imza yolunu
  kapsamaz; 17/21 ayrıca test edilir.
- Ad-hoc imza: jpackage sonrası `codesign -s - --deep --force build/UHAPImza.app`.
  Executable adı ASCII (`UHAPImza`); kullanıcıya görünen ad `Info.plist`'te
  `CFBundleDisplayName` ile Türkçe yazılabilir.

`make dmg`: `build/UHAPImza.app`'ten sürükle-bırak `UHAPImza.dmg` üretir
(hdiutil, /Applications sembolik linki).

`kur.sh`: Xcode CLT kontrolü → repoyu klonla/güncelle → `make jre` → `make app`
→ `codesign` → `/Applications`'a kopyala → AKİS sürücü talimatlarını yazdır.

## 7. Akıllı Kart (AKİS / PKCS#11)

- Uygulama AKİS kart tipi için `akisp11` kütüphanesini arar; MA3/ESYA katmanı
  kart tanımlarını dahili olarak (`CardType.AKIS`) sağlar. macOS'ta bu
  `libakisp11.dylib`'e çözülür ve JDK'nin `jdk.crypto.cryptoki` içindeki
  `libj2pkcs11.dylib`'i tarafından `dlopen` edilir.
- **Kullanıcı adımı (README'de):** TÜBİTAK BİLGEM'den
  (https://akiskart.bilgem.tubitak.gov.tr/tr/destek/) **"Mac OS Arm (Apple
  Silicon)"** etiketli AKİS paketini indirip kurar. Doğrulama:
  `lipo -archs <dylib-yolu>` → `arm64` içermeli.
- **DOĞRULANACAK:** AKİS paketinin `libakisp11.dylib`'i tam olarak nereye
  kurduğu (`/usr/local/lib` varsayımı kesin değil) implementasyon sırasında
  teyit edilir; gerekirse config'e/JVM'e açık kütüphane yolu verilir.

## 8. Bilinen Riskler ve Fallback'ler

Codex/gpt-5.6-sol incelemesi, esas engellerin akıllı kart öncesindeki
**belirleyici** hatalar olduğunu; kart riskinin gerçek ama ilk blocker olmadığını
gösterdi. Bölüm 5'teki payload yamaları bu belirleyici hataları giderir.

1. **SunPKCS11 kart yolu (donanım riski):** Zulu 11 arm64 + AKİS `libakisp11.dylib`
   + `--add-exports` ile kart okuma/imzalama ancak **gerçek AKİS kartıyla**
   doğrulanabilir. HTTP sunucusu ve JAR yükleme Mac'te çalışır görüldü; kart yolu
   (PKCS#11/PC-SC/PIN/sertifika enumerasyonu/imza) doğrulanmadı.
   - **Fallback A:** Hata-kurtarma yolundaki `sun.security.smartcardio` reflektif
     erişimi 17/21'de gerekirse
     `--add-opens=java.smartcardio/sun.security.smartcardio=ALL-UNNAMED`.
   - **Fallback B:** JRE sürümünü değiştirmek (17/21 alternatif; Zulu 8 tam uyum
     ama HiDPI yok ve jpackage runtime olarak sorunlu).
2. **Config vs yazılabilir yol çakışması:** `user.dir=$APPDIR` config'i (read-only)
   bulur ama göreli **yazma** yollarını da oraya yönlendirir. Log yaması (5.1) bunu
   çözer; `$APPDIR` beklendiği gibi genişlemezse config'i mutlak yolla veren küçük
   bir launcher wrapper'a geçilir.
3. **Görünür imza (5.3):** `C:\1\imza.png` yazımı; görünür imza kullanılırsa
   bytecode yaması gerekir.
4. **Uzak trust store:** Sertifika doğrulaması `http://depo.kamusm.gov.tr`'ye
   bağımlı — çevrimdışı/ağ kısıtlı ortamda imza doğrulama başarısız olabilir.
5. **Server bind (sertleştirme, fonksiyonel blocker DEĞİL):** `ArdHttpServer`
   8080'i `InetSocketAddress(port)` ile **wildcard** (0.0.0.0) adreste açar —
   localhost akışı çalışır ama LAN'a açıktır ve macOS güvenlik duvarı sorabilir.
   İstenirse loopback'e bind için bytecode yaması yapılır.
6. **CORS/preflight (test edilecek):** `/imza` handler'ı origin allowlist +
   `OPTIONS` + `Access-Control-Allow-Private-Network: true` set ediyor (yani
   tarayıcı→localhost için PNA zaten düşünülmüş). Diğer endpoint'lerin
   (`/getcertificates`, `/uyaplogin`) preflight/CORS davranışı Safari ve Chrome'da
   gerçek portala karşı test edilir; eksikse yama gerekebilir.
7. **Kod imzalama / Gatekeeper:** Ad-hoc imza yeterli (ilk açılışta sağ tık → Aç).
   Notarization kapsam dışı.

## 9. Kapsam Dışı (YAGNI)

- Intel (x86_64) desteği — sadece arm64 hedefleniyor.
- Notarization / Apple Developer imzası.
- Otomatik güncelleme (uygulama `uhap-prod`'da sürüm kontrolünü zaten atlıyor).
- UYAP dışı diğer portal config'leri (eusigner, uksigner vb.) — sadece `uhap-prod`.

## 10. Doğrulama Kriterleri

1. `make prep` payload yamalarını uygular (log yolu düzeltildi, sunpkcs11.jar
   çıkarıldı); `make app` hatasız `build/UHAPImza.app` üretir.
2. `.app` çift tıklamayla açılır, HTTP sunucusu 8080'de dinler
   (`curl localhost:8080/imza` → app log'unda istek görülür) ve log yazımı
   `~/Library/Logs/UHAPImza/` altında başarılı olur (read-only bundle'a yazma
   denemesi olmamalı).
3. Uygulama log'unda `config/` yolu doğru çözülür (config-not-found hatası yok);
   `--add-exports` uyarısı çıkmaz.
4. AKİS kartı takılıyken `/getcertificates` sertifikaları döndürür ve gerçek bir
   UHAP imza akışı tamamlanır. *(Donanım gerektiren adım — kullanıcı doğrulaması.)*
5. `make dmg` kurulabilir `UHAPImza.dmg` üretir.
