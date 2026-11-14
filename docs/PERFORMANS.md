# Performans (P098)

Ölç → değiştir → yeniden ölç. Sayılar geliştirme Mac'inde (Debug derleme, `swift test`) alındı; cihaz hedefleri
Release + Instruments ile `[MANUEL]` doğrulanır (aşağıda).

## Ölçümler (`PerformanceBudgetTests`, DataKit)

Her ölçüm 5 koşunun medyanıdır; bütçe, ölçülenin 5–10 katıdır (yavaş CI'da yalancı hata vermesin, O(n²) gibi
gerilemeyi yakalasın).

| Senaryo | Ölçülen (Debug) | Bütçe |
|---|---|---|
| Katalog JSON çözümü (1,9 MB, 876 hareket) | 43 ms | 500 ms |
| İlk katalog içe aktarma (arka plan bağlamı) | 390 ms | 3 sn |
| Kütüphane araması, 4 sorgu × 1.752 öğe | 168 ms (≈ 42 ms/sorgu) | 400 ms |
| Geçmiş ilk sayfa (30 antrenman, 520 kayıtlı) | 23 ms | 500 ms |
| Skor: tam hesap, 520 antrenman | 253 ms | 5 sn |
| Skor: değişiklik yok yenilemesi | 213 ms | 1 sn |

Açılış (`PerformanceUITests.testColdLaunchStaysUnderBudget`, `XCTApplicationLaunchMetric`) CI'da koşar.
Taban değerleri `.xcodeproj` içinde saklanır ve `.xcodeproj` commit edilmediği için bütçeler testlerde sabittir.

## Değişiklikler (öncesi → sonrası)

1. **Katalog açılışı.** `CatalogService.bootstrap` her açılışta 1,9 MB JSON'u çözüp sonra "güncel" diyordu. Artık
   paket dosya adındaki sürüm (`catalog.v{N}.json`) yüklü sürümden büyük değilse dosya hiç okunmuyor
   (`BundledCatalog.bundledVersion`). Kazanç: ilk kurulum dışındaki her açılışta ≈ 43 ms (Debug; cihazda daha
   fazla) ve ~2 MB geçici bellek. Test: `upToDateBootstrapSkipsDecoding`.
2. **Kütüphane yüklemesi ana iş parçacığında değildi.** `LibraryModel.load` 876 satırı okuyup adları katlıyordu
   (`@MainActor`). Okuma/dönüştürme artık `nonisolated` async işlev (arka plan); yalnızca sonuç ana iş parçacığında
   atanır. Özel hareket sonrası `reload()` (küçük, eşzamanlı) olduğu gibi kaldı.
3. **Küçük resim önbelleği.** `NSCache` yalnızca adet (400) ile sınırlıydı; çözülmüş bitmap maliyetine göre
   sınırsızdı. Artık `totalCostLimit` = 24 MB (maliyet = piksel × 4 B). Görseller önbelleğe girmeden **arka planda**
   (`preparingForDisplay`) çözülüyor; ilk çizimde ana iş parçacığında çözme (kaydırma takılması) kalmadı.

## Doğrulananlar (değişiklik gerekmedi)

- **Skor yeniden hesabı / senkron ana iş parçacığını bloklamıyor:** `ScoreService` ve `CatalogImporter` kendi
  `ModelContext`'lerinde actor üzerinde çalışır; yenileme yerel kayıtlardan sonra *debounce* edilir
  (`AppContainer.scoresMayHaveChanged`).
- **Geçmiş:** 30'luk sayfalama + yalnızca gösterilen ay yüklenir (P042); 520 kayıtta ilk sayfa 23 ms.
- **Live Activity:** `LiveActivityCoordinator` durum değişmediyse (`state != shownState`) güncelleme göndermez; geri
  sayım `restStart/restEnd` tarihleriyle sistem tarafından çizilir, saniyelik güncelleme yok. Güncelleme yalnızca set
  tamamlama / egzersiz değişimi / dinlenme başlangıç-bitişinde olur.
- **Paket boyutu:** katalog 1,9 MB + küçük resimler 3,1 MB (309 dosya, WebP) + skor modeli 16 KB. Uygulama
  kaynakları toplam ≈ 5,5 MB; indirme boyutu hedefi **< 40 MB** (sıkıştırılmış, Swift paketleri dâhil).
  Gerçek rakam arşivde ölçülür (Xcode Organizer → App Thinning raporu, P103/P104).

## Hedefler ve elle doğrulama `[MANUEL]`

| Hedef | Nasıl ölçülür |
|---|---|
| Soğuk açılış, ilk kare < 1 sn (iPhone 14 sınıfı) | Release derleme, Instruments *App Launch*; `PerformanceUITests` CI'da gerilemeyi izler |
| Kaydırma takılma oranı < 5 ms/sn | Instruments *Animation Hitches*: kütüphane (876), geçmiş (500+ antrenman), koç sohbeti (uzun akan mesaj) |
| Bellek / sızıntı | Instruments *Leaks* + *Allocations*: 60 dk aktif antrenman, kütüphane sürekli kaydırma |
| Pil | Instruments *Energy Log*: aktif antrenmanda arka plan etkinliği, Live Activity güncelleme sıklığı |

## Ertelenenler

- Skor "değişiklik yok" yenilemesi (213 ms Debug) tüm tamamlanmış setleri her çağrıda yeniden okuyup karşılaştırır;
  actor'da çalıştığı için arayüzü bloklamaz ama pil için set değişikliği olayından türetilen bir "kirli" bayrağı ile
  atlanabilir.
- Kütüphane araması her tuş vuruşunda ana iş parçacığında süzer/sıralar (≈ 10 ms Release tahmini, 876 öğe); takılma
  Instruments'ta görülürse 150 ms debounce + arka plan sıralama eklenir.
- Sohbet kaydırma takılması ve uzun antrenman sızıntı geçişi cihazda ölçülmedi (yukarıdaki tablo).
