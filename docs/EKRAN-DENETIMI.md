# Ekran denetimi (2026-11-22)

Kapsam: `ios/App/Features/*`. Durum etiketleri:

- **S** = simülatörde görüldü (iPhone 14, Debug)
- **K** = yalnızca kod incelemesi / statik tarama (görülmedi)
- **U** = kullanıcıya bağlı (gerçek hesap, rıza, gerçek cihaz, build)

Büyük yazı = en büyük erişilebilirlik boyutu (accessibility-extra-large); TR = `-AppleLanguages (tr)`.

| Alan | Ekran | Durum | Not |
|---|---|---|---|
| Nutrition | Diary (halka, makrolar, öğünler) | S, TR, büyük yazı | Büyük yazıda yerleşim düzeltildi (dikey yığma) |
| Nutrition | Başlık (seri, takvim, menü) | S, büyük yazı | Seri sayısı büyük yazıda kayboluyordu, düzeltildi |
| Nutrition | Pager: Water, Fasting, Notes sayfaları | S | Temiz |
| Nutrition | Recipes sekmesi | S | Yalnızca "yakında" yer tutucusu (ürün kararı: sekme boş yayınlanıyor) |
| Nutrition | Takvim sayfası, "…" menüsü, yemek ekleme akışları, öğün detayı | K | Görülmedi |
| Workout | Ana sayfa (skor, örüntüler, plan, öne çıkanlar) | S, TR, büyük yazı | Skor modeli hatası düzeltildi, 38 / Developing görüldü |
| Workout | Create, Şablonlar | S | Temiz |
| Workout | History, Exercise Library (kısayol + ekranlar) | S | Kısayollar yoktu, geri getirildi; ham anahtarlar düzeltildi |
| Workout | Haftalık özet | S (deep link) | Temiz |
| Workout | Aktif antrenman, rest timer, tuş takımı, özet, program kurulumu | K | Aktif antrenman erişilebilirlik boyutunu ele alıyor; rest timer metni sınırlandı |
| Workout | Egzersiz detayı (medya, kaslar, talimatlar) | S | Temiz |
| Workout | Rutin editörü / gün, egzersiz skor ekranı | K | `.dynamic` anahtarları kod+katalog betiğiyle doğrulandı, ekranda görülmedi |
| Analysis | Muscles, Progress, Insights (boş) | S, TR (Muscles) | Boş durumlar temiz; dolu hali test modunda veri olmadığı için görülemedi |
| Analysis | Kas detayı | K | |
| Coach | Rıza ekranı, boş sohbet, program kartı | S (test modu) | Rıza yalnızca bellek içi test modunda kabul edildi (kullanıcı izniyle); sahte koç yanıtı + Apply/Edit/Reject kartı temiz |
| Profile | Profil, Ayarlar (tamamı), Paywall | S | Paywall görüldü, temiz; "Coming soon" bildirim satırı kaldırıldı; satın alma akışı denenmedi (U) |
| Profile | Tema seçici, profil düzenleme, ölçümler, About, rıza geçmişi, hesap silme | K | Hesap silme/çıkış bilerek denenmedi (U) |
| Social | Arkadaşlar giriş ekranı | S | Profil sekmesinden giriş yoktu (yalnızca davet linki), "Friends" satırı eklendi |
| Social | Davet ekranı, profil formu (test modu) | S | Avatar renk seçicisi gri görünüyordu, düzeltildi; arkadaş listesi ve rapor görülmedi |
| Diğer | Auth, Onboarding, HowItWorks, paylaşım kartları, widget'lar | K | Widget sürüm uyuşmazlığı düzeltildi; widget görseli doğrulanmadı |

## Hızlı yol

Hesaba dokunmadan gezmek için: `xcrun simctl launch <udid> com.barishizm.atrox.debug -uitest-fake-auth -uitest-onboarded -uitest-fake-social -uitest-fake-coach` (bellek içi, tohumlu veri), ardından `xcrun simctl openurl <udid> atrox://u/bob_lifts` gibi deep link'ler.

## Bulgular ve durum

1. Skor modeli hiç yüklenmiyordu (`SemanticVersion`, iki parçalı sürüm) — düzeltildi, test eklendi.
2. Widget `CFBundleVersion` uyuşmazlığı — düzeltildi.
3. Calories ekranı büyük yazıda bozuluyordu — düzeltildi.
4. History / Library erişilemez durumdaydı — düzeltildi.
5. 16 yerde ham yerelleştirme anahtarı riski (`LocalizedStringKey("a.\(x)")`) — düzeltildi.
6. Sabit boyutlu dairelerde (rest timer, adım numarası) büyük yazı taşması — sınırlandı.
7. Arkadaşlar ekranına yalnızca davet linkiyle girilebiliyordu — Profil'e satır eklendi.
8. Sosyal profil formunda avatar renk seçicisi renkleri göstermiyordu — düzeltildi.

## Yapılamayanlar

- Release yapılandırmasında ölçüm (Debug'da Workout sekmesi 8–12 sn, açılış 20–60 sn sürüyor).
- VoiceOver turu ve gerçek cihaz testi.
- `impeccable` skill'i çalıştırılmadı; `mobile-ios-design` referansları okundu, yığma/Dynamic Type önerileri uygulandı.
