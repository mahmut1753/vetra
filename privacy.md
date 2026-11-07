# Vetra — Privacy Policy / Gizlilik Politikası

**Effective Date / Yürürlük Tarihi:** November 7, 2026  
**Application / Uygulama:** Vetra — Window Manager & Dock Previews for macOS (`com.vetra.windowmanager`)

[🇺🇸 English](#english-privacy-policy) | [🇹🇷 Türkçe](#türkçe-gizlilik-politikası)

---

<a id="english-privacy-policy"></a>
## 🇺🇸 Privacy Policy (English)

### 1. Overview & Zero-Data-Collection Commitment
**Vetra** ("the Application") is a native macOS window management and live Dock preview utility developed with a strict **privacy-first, local-only architecture**.

**We do not collect, store, transmit, rent, or sell any personal data, usage analytics, telemetry, window contents, or screen captures.**

- **No Accounts Required:** Vetra operates without user registration, sign-in, or cloud accounts.
- **No Network Transmission:** Vetra makes zero outbound network requests to external servers, analytics providers, or third-party SDKs.
- **No Tracking or Telemetry:** Vetra contains no crash reporters, advertising identifiers, or behavioral tracking libraries.

### 2. macOS System Permissions & How They Are Used
To function as a window manager and live Dock preview enhancer on macOS, Vetra requests your explicit consent for two standard macOS system permissions:

#### a) Accessibility Permission (`AXUIElement` API)
- **Why it is requested:** Required by macOS to read window positions, dimensions, and focus states, and to resize or arrange application windows into tiled layouts (Side, Grid, Columns, Rows) and detect cursor hover position over the macOS Dock.
- **How data is handled:** All window geometry calculations happen **100% in volatile memory (RAM)** on your Mac in real time. Window titles and coordinates are never logged to disk or transmitted anywhere.

#### b) Screen Recording Permission (`CGWindowListCreateImage` / `ScreenCaptureKit` — Optional)
- **Why it is requested:** Optionally used to render live miniature window thumbnails when you hover over an application icon in the macOS Dock or over a stacked window tab bar.
- **How data is handled:** Window snapshots are captured on-demand in memory solely to display the live preview card on your screen. Snapshots are held in a short-lived in-memory cache (`NSCache`) for a few seconds and are **immediately discarded**. No images or video recordings are ever saved to disk or shared outside your device.

### 3. Local Configuration Storage
Your user preferences (such as preferred layout mode, window spacing, border highlight color, custom keyboard shortcuts, and ignored applications list) are stored strictly locally on your Mac using standard macOS `UserDefaults` (`com.vetra.windowmanager`). You can reset or delete these settings at any time from within the Application.

### 4. Third-Party Services
Vetra does **not** integrate with any third-party analytics, advertising, cloud storage, or AI services.

### 5. Children's Privacy
Vetra does not collect personal information from anyone, including children under the age of 13.

### 6. Changes to This Privacy Policy
If we update this Privacy Policy in future versions of Vetra, the revised version will be posted on this page with an updated effective date.

### 7. Contact Us
If you have any questions about this Privacy Policy or Vetra's privacy practices, please contact us via our GitHub repository Issues page or support email.

---

<a id="türkçe-gizlilik-politikası"></a>
## 🇹🇷 Gizlilik Politikası (Türkçe)

### 1. Genel Bakış ve Sıfır Veri Toplama Taahhüdü
**Vetra** ("Uygulama"), tamamen **gizlilik odaklı ve %100 yerel (cihaz içi)** mimariyle geliştirilmiş yerel bir macOS pencere yönetimi ve canlı Dock önizleme uygulamasıdır.

**Hiçbir kişisel veriyi, kullanım istatistiğini, telemetri verisini, pencere içeriğini veya ekran görüntüsünü toplamaz, kaydetmez, dış sunuculara iletmez veya üçüncü taraflarla paylaşmayız.**

- **Hesap Gerektirmez:** Vetra herhangi bir üyelik, giriş veya bulut hesabı olmadan çalışır.
- **İnternet Bağlantısı veya Veri Aktarımı Yoktur:** Vetra hiçbir harici sunucuya, analiz servisine veya üçüncü taraf yazılıma veri göndermez.
- **İzleme ve Telemetri Yoktur:** Uygulama içinde reklam kimliği, kullanıcı takip kodu veya üçüncü taraf analiz kütüphanesi bulunmaz.

### 2. macOS Sistem İzinleri ve Kullanım Amaçları
Vetra, macOS üzerinde pencereleri otomatik hizalamak ve canlı Dock önizlemeleri sunmak için yalnızca sizin açık onayınızla iki standart macOS sistem izni kullanır:

#### a) Erişilebilirlik İzni (Accessibility — `AXUIElement` API)
- **Neden İstenir:** Açık pencerelerin konumunu, boyutunu ve odak durumunu okumak; pencereleri seçtiğiniz düzene (Yan, Izgara, Sütun, Satır) göre otomatik boyutlandırmak ve farenin Dock üzerindeki konumunu algılamak için macOS tarafından zorunlu tutulur.
- **Veriler Nasıl İşlenir:** Tüm pencere geometrisi hesaplamaları **%100 cihazınızın geçici belleğinde (RAM)** gerçek zamanlı olarak yapılır. Pencere başlıkları veya konumları diske kaydedilmez ve hiçbir yere gönderilmez.

#### b) Ekran Kaydı İzni (Screen Recording — İsteğe Bağlı)
- **Neden İstenir:** Fareyi macOS Dock'taki bir uygulama simgesinin veya yığın (stack) sekme çubuğunun üzerine getirdiğinizde açık pencerelerin canlı küçük önizlemelerini (thumbnail) göstermek için isteğe bağlı olarak kullanılır.
- **Veriler Nasıl İşlenir:** Pencere önizleme görselleri yalnızca siz fareyi simge üzerine getirdiğinizde anlık olarak bellekte oluşturulur, birkaç saniyeliğine geçici önbellekte (`NSCache`) tutulur ve **anında silinir**. Hiçbir görüntü veya ekran kaydı diske yazılmaz veya cihaz dışına çıkmaz.

### 3. Yerel Ayarların Saklanması
Tercih ettiğiniz pencere düzeni, pencere arası boşluk miktarı, kenarlık vurgu rengi, özel klavye kısayolları ve yoksayılan uygulamalar listesi yalnızca kendi Mac bilgisayarınızda standart macOS `UserDefaults` (`com.vetra.windowmanager`) üzerinde yerel olarak saklanır. Bu ayarları dilediğiniz zaman uygulama içinden sıfırlayabilirsiniz.

### 4. Üçüncü Taraf Hizmetler
Vetra hiçbir üçüncü taraf analiz, reklam, bulut depolama veya veri işleme servisi içermez.

### 5. Çocukların Gizliliği
Vetra, 13 yaş altı çocuklar dahil olmak üzere hiçbir kullanıcıdan herhangi bir kişisel veri toplamaz.

### 6. Gizlilik Politikasındaki Değişiklikler
Gelecekteki sürümlerde bu Gizlilik Politikasında bir güncelleme yapılması durumunda, güncel metin yürürlük tarihiyle birlikte bu sayfada yayınlanacaktır.

### 7. İletişim
Bu Gizlilik Politikası veya Vetra'nın gizlilik ilkeleri hakkında sorularınız için GitHub depomuzdaki "Issues" bölümünden veya destek e-posta adresimiz üzerinden bizimle iletişime geçebilirsiniz.

