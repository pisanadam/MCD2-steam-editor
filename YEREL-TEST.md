# Yerel Codex oturumunda devam et

Bu proje bir bulut Linux ortamında geliştirildi. Gerçek Minecraft Dungeons II oyunu o ortamda yoktu. Windows bilgisayarındaki yeni yerel oturum, Steam kurulumunu ve gerçek kayıtları inceleyebilir; oyun ekranını test etmek için Computer Use kurulabilir.

## Masaüstü uygulamasından aç

1. ChatGPT'nin Windows masaüstü uygulamasını kullan: https://chatgpt.com/download/
2. Seçiciden Codex'i aç. Yeni sohbette **Work in → This computer** seç.
3. Bu ZIP'i çıkardığın proje klasörünü aç.
4. Görsel oyun testi için **Plugins → Computer Use** eklentisini kur/etkinleştir. Eklentinin server ve skill seçenekleri açık olsun. Windows'ta oyun test boyunca etkin masaüstünde görünür olmalı.
5. Yerel sohbete şu metni gönder:

> YEREL-TEST.md ve README.md dosyalarını oku. Minecraft Dungeons II Steam düzenleyicisini gerçek kurulumum ve çevrimdışı karakter kaydım ile test et, hataları düzelt. Önce kayıt yedeği al. Zümrüt ve mevcut bir eşyanın gücü/büyüsünde küçük değişiklikler yap; Computer Use varsa karakteri oyunda açıp görselleri ve değerleri kontrol et. Kaydedip çıktıktan sonra kayıt dosyasını yeniden oku. Kayıt değişikliklerinin korunup korunmadığını somut kanıtla raporla. Oyun içi test yapılmadan “uyumluluk doğrulandı” deme. Çevrimiçi karakterleri değiştirme, kayıt biçimini ve 64-bit sayıları koru. Bu klasördeki çalışmayı tamamla.

Resmî kaynaklar:
- Yerel/bulut ortam seçimi: https://learn.chatgpt.com/docs/environments/modes
- Computer Use kurulumu: https://learn.chatgpt.com/docs/computer-use
- Windows çalışma ortamı: https://learn.chatgpt.com/docs/windows/windows-sandbox

## Terminal alternatifi

Codex CLI Windows'ta da yerel çalışır: https://learn.chatgpt.com/docs/codex/cli
PowerShell'de proje klasöründen `codex` açıp ChatGPT hesabınla oturum aç. Yukarıdaki test isteğini gönder. Computer Use olmadan komutlarla kayıt ve dosya testleri yapılabilir; gerçek oyun ekranı testi için masaüstü uygulaması daha uygundur.

## Şu anda neler tamam?

- `index.html` çevrimdışı çalışan, 440 özgün PNG/WebP'yi içinde taşıyan Türkçe gerçek kayıt düzenleyicisidir.
- `native.js` FCharacterSaveV1 JSON tokenlarını patchler. Bilinmeyen alanlar ve büyük sayılar yeniden serialize edilmez; dokunulmayan tokenlar aynen korunur.
- Gerçek ikon kapsamı:296 gear,34 enchantments,196 etki tier kayıtları,28 kostüm,7 pelerin,3 pet,2 kaynak,7 arayüz ikonu.573 katalog entries,632 native/alias mapping. `assets/icon-manifest.json` kaynak URL/hash/provenance içerir.
- Kozmetikler gerçek görsellerdir ama kaynakta native SW.Skin kimlikleri yoktur; tag:null kayıtları karaktere tahminen eşlenmez. Tam 3B karakter modeli yoktur.
- `Kayit-Bul.cmd/.ps1` Steam AppID 1912410 kayıtlarını bulur, kopya+SHA256+ZIP+rapor alır ve gerçek kaydı bağımsız HTML'e güvenli base64 bootstrap ile açar.
- `Kaydi-Uygula.cmd/.ps1` offline karakter ID/sürüm/FormatHash/GameDataUpdated karşılaştırır, yedek alır, atomik dosya değişimi yapar. Canlı oyun işlemini engeller.
- `Oyunda-Dogrula.cmd/.ps1` uygulanan değişikliklerin gerçek oyun yükleme/kaydetme sonrasında tutulmasını kontrol etmek içindir. Yeniden sıralanan envanter veya gözlenemeyen koşullar için kesin başarı iddiası verilmemelidir.
- En son kamuya açık Steam build araştırması:25647713 (1 Ekim 2026). Kamu ikon veri setinin tabanı25041023 / 1.1.1.0. Son build'in tüm ikonları veya bütün eşya kombinasyonları doğrulanmış değildir.
- Resmî 1 Ekim Steam güncellemesi zümrüt sınırını 99.999 olarak değiştirir. ItemPower için evrensel üst sınır doğrulanmadı; talisman/blacksmith caps tüm item türleriyle aynı kabul edilmemeli.

## Test ve derleme

`python build.py` tek HTML'i kaynak PNG/WebP byte'larını değiştirmeden yeniden üretir. `python test_native.py` ve `python test_icons.py` doğrudan yerel HTML üzerinde çalışır. Python Playwright ve Windows'ta Microsoft Edge gerekir; farklı Chromium tarayıcısı için BROWSER_PATH ortam değişkeni kullanılabilir. Kaynak metinler UTF-8 olarak okunur.

Bulutta sentetik kayıtlar ile native roundtrip/BOM/64bit/undo/copy/delete/level/power/enchant tier/invalid input,440 görsel browserdecode/hash/offline render ve mobil testleri geçti. PowerShell scriptleri Linux'ta PowerShell 7.6.6 ile sahte Windows klasörlerinde sınandı. Windows 5.1, Windows OpenFileDialog ve canlı oyunda yükleme, burada yapılacak yeni testtir.

İlk yükleme testini bir kopya/ayrı çevrimdışı karakter üzerinde ve küçük değişikliklerle yap. Yedek dosyalarını koru. Gerçek kabulü oyunda gözlemlenmiş testin sonucuna göre bildir; otomatik testleri canlı oyun testiyle karıştırma.
