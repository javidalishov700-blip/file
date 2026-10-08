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
   - Gizlilik: Uygulama **veri toplamıyor** (“Data Not Collected”). `PrivacyInfo.xcprivacy` dahil.
   - Şifreleme sorusu: `ITSAppUsesNonExemptEncryption = NO` (yalnızca Apple'ın sistem şifrelemesi kullanılıyor).
4. İncelemeye gönder.

> Not: "iLovePDF" adı ve logosu başka bir şirkete ait; App Store'da kendi adını ve ikonunu kullan.
> Uygulama adı `Config/Info.plist` → `CFBundleDisplayName`, ikon `PDFStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024).

## Proje yapısı

```
project.yml                 XcodeGen proje tanımı
Config/Info.plist           İzinler (kamera, fotoğraf), belge türleri
PDFStudio/
  App/                      Uygulama girişi, sekmeler
  Models/                   Araç listesi, dosya deposu
  Services/                 PDF işlemleri (PDFKit), OCR (Vision), Office/Web→PDF (WebKit), DOCX yazıcı
  Views/                    Ana ekran, My Files, Ayarlar, araç ekranları, PDF editörü
  Resources/                Assets, PrivacyInfo.xcprivacy
.github/workflows/          Her push'ta macOS üzerinde derleme kontrolü
```
