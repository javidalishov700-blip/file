# PDF Studio (iOS)

iLovePDF tarzı, **tamamen cihaz üzerinde çalışan** (sunucuya dosya yüklemeyen) hepsi bir arada PDF uygulaması.
SwiftUI ile yazıldı, iOS 17+ (iPhone ve iPad).

## Araçlar

| Kategori | Araçlar |
|---|---|
| Tarama | **Scan to PDF** (kamera ile belge tarama, otomatik kenar algılama, renk/gri/siyah-beyaz filtre, OCR), **OCR PDF** (taranmış PDF'i aranabilir yapar veya metin çıkarır) |
| Düzenle | **Merge** (birleştir), **Split** (her sayfa / aralıklar / sayfa çıkar), **Organize** (sırala, döndür, sil), **Rotate** |
| Optimize | **Compress** (3 seviye), **Crop** (kenar kırp, önizlemeli) |
| PDF'e çevir | **JPG/Fotoğraf → PDF**, **Office → PDF** (Word, Excel, PowerPoint, Pages, Numbers, Keynote, RTF, TXT, HTML, CSV), **HTML/URL → PDF** |
| PDF'ten çevir | **PDF → JPG/PNG**, **PDF → Word (.docx)**, **PDF → Metin / Markdown** (taranmış sayfalarda otomatik OCR) |
| Düzenle | **Edit PDF** (metin, resim, kalem/fosforlu kalem/silgi), **Sign PDF** (imza çiz, kaydet, sayfaya yerleştir), **Watermark**, **Page Numbers** |
| Güvenlik | **Protect** (şifre koy), **Unlock** (şifreyi kaldır) |

Ayrıca: **My Files** sekmesi (önizleme, paylaş, yeniden adlandır, sil), dosyalar iOS *Dosyalar* uygulamasında da görünür,
başka uygulamalardan "PDF Studio ile aç" desteği.

## Kurulum (Mac gerekli)

1. Xcode 16+ ve [XcodeGen](https://github.com/yonaskolb/XcodeGen) kur: `brew install xcodegen`
2. Proje klasöründe: `xcodegen generate`
3. `PDFStudio.xcodeproj` dosyasını aç.
4. *Signing & Capabilities* → kendi **Team**'ini seç, gerekirse **Bundle Identifier**'ı değiştir
   (`project.yml` içindeki `PRODUCT_BUNDLE_IDENTIFIER` ve `DEVELOPMENT_TEAM`).
5. Gerçek bir iPhone seçip ▶︎ Run. (Kamera ile tarama simülatörde çalışmaz.)

## App Store'a gönderme

1. [App Store Connect](https://appstoreconnect.apple.com)'te yeni uygulama oluştur (aynı Bundle ID ile).
2. Xcode → *Product › Archive* → *Distribute App* → *App Store Connect*.
3. App Store Connect'te ekran görüntüleri, açıklama, gizlilik politikası URL'si ekle.
   - Gizlilik: Belgeler cihazda kalır, ama **AdMob reklamları veri topluyor** — aşağıdaki "App Privacy" cevaplarını kullan.
   - Şifreleme sorusu: `ITSAppUsesNonExemptEncryption = NO` (yalnızca Apple'ın sistem şifrelemesi kullanılıyor).
4. İncelemeye gönder.

> Not: "iLovePDF" adı ve logosu başka bir şirkete ait; App Store'da kendi adını ve ikonunu kullan.
> Uygulama adı `Config/Info.plist` → `CFBundleDisplayName`, ikon `PDFStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024).

## Codemagic ile TestFlight'a otomatik gönderme (Mac gerekmez)

`codemagic.yaml` → `pdf-studio-ios` workflow'u (Slice & Blast ile aynı yapı): XcodeGen ile projeyi üretir,
build numarasını ayarlar (2024'ten beri geçen dakika), imzalar, `.ipa` yapar ve TestFlight'a yükler.
`main` branch'ine her push'ta çalışır; Codemagic'ten elle de başlatılabilir.

Bir kerelik kurulum:
1. **Codemagic** → *Add application* → bu repo (`javidalishov700-blip/file`) → *codemagic.yaml* kullan.
2. **App Store Connect API key**: Slice & Blast için oluşturulan `SliceBlast ASC Key` entegrasyonu hesap geneli
   çalışır, yeni key gerekmez.
3. **Apple Developer** → *Identifiers* → `com.javidalishov.pdfstudio` App ID'sini oluştur →
   *Profiles* → bu ID için **App Store** provisioning profile oluştur (mevcut Distribution sertifikasıyla).
4. **Codemagic** → *Team settings → Code signing identities → iOS provisioning profiles* → *Fetch profiles*
   (sertifika `.p12` Slice & Blast'tan zaten yüklü).
5. **App Store Connect** → *Apps → +* → aynı Bundle ID ile "PDF Studio" uygulamasını oluştur.
6. Codemagic'te *Start new build* → `pdf-studio-ios`.

## AdMob reklamları

- **Banner**: Araçlar ve My Files ekranlarının altında.
- **Interstitial**: Her 2. tamamlanan işlemden sonra, sonuç ekranı kapatılınca (ilk işlemde asla, en az 90 sn arayla).
- Açılışta önce Apple **ATT** izni, sonra Google **UMP** onay formu (AB/UK kullanıcıları için GDPR). Onay yoksa
  reklam istenmez. Ayarlar'da "Ad privacy choices" butonu (gerekiyorsa) görünür.
- Kod: `PDFStudio/Ads/AdsManager.swift`, `BannerAdView.swift`. SDK Swift Package Manager ile geliyor.

**Gerçek ID'leri ekle** — şu an Google'ın **test** ID'leri var (para kazandırmaz):
AdMob → *Apps → Add app → iOS* → "PDF Studio" → 1 Banner + 1 Interstitial reklam birimi oluştur, sonra
`project.yml` içinde `ADMOB_APP_ID` (`~` içeren), `ADMOB_BANNER_UNIT_ID`, `ADMOB_INTERSTITIAL_UNIT_ID` değerlerini değiştir.
Debug build'ler her zaman test reklamı gösterir; Release build'ler bu ID'leri kullanır.

**App Store Connect → App Privacy** (Google'ın önerisi, Slice & Blast ile aynı):
- *Identifiers → Device ID*: toplanıyor, kullanıcıya bağlı **değil**, amaç **Third-Party Advertising**.
- *Usage Data → Advertising Data*: toplanıyor, kullanıcıya bağlı **değil**, amaç **Third-Party Advertising**.
- **Used for Tracking = Yes** (uygulama ATT izni istiyor).
- Gizlilik politikasında AdMob, reklam kimliği ve ATT'den bahset; açıklamada "reklamsız" deme (Guideline 2.3.6).

## Proje yapısı

```
project.yml                 XcodeGen proje tanımı
Config/Info.plist           İzinler (kamera, fotoğraf), belge türleri
PDFStudio/
  Ads/                      AdMob (ATT + UMP onayı, banner, interstitial)
  App/                      Uygulama girişi, sekmeler
  Models/                   Araç listesi, dosya deposu
  Services/                 PDF işlemleri (PDFKit), OCR (Vision), Office/Web→PDF (WebKit), DOCX yazıcı
  Views/                    Ana ekran, My Files, Ayarlar, araç ekranları, PDF editörü
  Resources/                Assets, PrivacyInfo.xcprivacy
.github/workflows/          Her push'ta macOS üzerinde derleme kontrolü
codemagic.yaml              Codemagic → TestFlight
```
