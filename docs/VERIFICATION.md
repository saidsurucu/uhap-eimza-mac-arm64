# Doğrulama Notları (macOS Apple Silicon Port)

Bu belge, port çıktısının bu makinede (Apple Silicon) yapılan gerçek
doğrulamalarını özetler.

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

## Akıllı kart / PKCS#11 katmanı (Task 10 — otonom kısım doğrulandı)
Portun en büyük riski, **arm64 Zulu 11 SunPKCS11'in AKİS `libakisp11.dylib`'ini
yükleyip token'a ulaşması** idi. Uygulamanın shipping runtime'ı ile birebir
SunPKCS11 probu (public `Provider.configure()` API) çalıştırıldı:

- Provider başarıyla yüklendi: **`SunPKCS11-AKIS`** — AKİS dylib arm64 runtime'a
  bağlandı, native yükleme/mimari/modül hatası **yok**.
- PIN'siz `KeyStore.load(null, null)` şu kök nedenle başarısız oldu:
  `LoginException: no password provided, and no callback handler available`.
  Bu, SunPKCS11'in token'a **ulaştığını** ve yalnızca PIN beklediğini gösterir
  (token-yok / kütüphane-yüklenemedi hatası DEĞİL).

> Not: Yanlış PIN AKİS kartını kilitleyebileceği için doğrulama sırasında
> **hiçbir PIN denenmedi**; token erişilebilirliği login öncesi hata zinciriyle
> kanıtlandı.

## Kullanıcı kabul testi (bekliyor — donanım + PIN + canlı portal)
Aşağıdaki uçtan uca akış, PIN ve canlı UHAP oturumu gerektirdiği için kullanıcı
tarafından tamamlanmalıdır:
1. `/Applications/UHAPImza.app` açık.
2. Tarayıcıda https://uhap.com.tr → imzalama akışı başlat.
3. Kart PIN'i gir → `/getcertificates` sertifikaları döndürür → imza tamamlanır
   ve imzalı belge UHAP'a yüklenir.

Hata olursa `~/Library/Logs/UHAPImza/log.out` bakılır; fallback kararları
`docs/superpowers/specs/2026-07-16-uhap-eimza-mac-port-design.md` §8'de.
