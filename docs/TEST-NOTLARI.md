# Elle doğrulama notları

Otomatik testlerin (birim/UI) kapsamadığı, simülatörde veya gerçek cihazda elle denenen adımlar. Her bölüm ilgili prompt
adımının kabul ölçütüne bağlıdır.

## P038 · Live Activity ve Dynamic Island

Ön koşul: iOS 26+ simülatör (iPhone 14 Pro ve üstü Dynamic Island gösterir; iPhone 14'te yalnızca kilit ekranı
görünümü vardır) ya da gerçek cihaz. Cihaz ayarı: Ayarlar → ATROX → Canlı Etkinlikler açık.

1. **Başlama.** Antrenman sekmesi → "Boş antrenman başlat" → bir hareket ekle. Ana ekrana/kilit ekranına çık
   (simülatörde `Cmd+L`). Kilit ekranında etkinlik görünür: antrenman adı, "Hareket adı · 1/3" ve sağda sürekli
   ilerleyen toplam süre.
2. **Set ilerlemesi.** Uygulamaya dön, bir seti tamamla. Etkinlikte set sayısı `2/3`'e geçer; tüm setler bitince bir
   sonraki hareketin adı görünür.
3. **Dinlenme geri sayımı.** Set tamamlanınca dinlenme başlar. Kilit ekranında "Dinlenme" ve geri sayım görünür; saniyeler
   uygulama arka plandayken de akar (uygulama güncelleme göndermez). Süreyi uygulamadaki sayaçla karşılaştır (±1 sn).
4. **Dynamic Island.** Kompakt: solda simge, sağda geri sayım (dinlenmede) ya da toplam süre. Minimal (başka bir
   etkinlik varken): simge. Uzun basınca genişler: hareket + set, sağda süre, altta "Atla" ve "+15 sn".
5. **Etkileşimler.** "+15 sn": geri sayım 15 sn uzar (hem etkinlikte hem uygulamadaki halkada). "Atla": dinlenme
   biter, etkinlik toplam süreye döner. Uygulama arka plandayken de dene.
6. **Dinlenme bitişi.** Dinlenmenin kendiliğinden bitmesini kilit ekranında bekle: geri sayım 0'da durup kaybolmalı
   (uygulama askıdaysa etkinlik "stale" olur ve dinlenme bölümünü gizler); bildirim yine gelir (P037).
7. **Bitirme.** Antrenmanı bitir: etkinlik "Antrenman tamamlandı", set sayısı ve toplam süreyle ~2 dakika kalır, sonra
   kapanır. Antrenmanı iptal et: etkinlik hemen kapanır.
8. **Çökme kurtarma.** Antrenman sürerken uygulamayı uygulama değiştiriciden kapat (öldür), sonra aç: etkinlik
   (varsa) aynı antrenmana bağlı kalıp güncellenir; antrenman yoksa etkinlik açılışta temizlenir.
9. **Kapatma.** Ayarlar → Antrenman → "Antrenmanı kilit ekranında ve Dynamic Island'da göster" kapalıyken yeni
   antrenman etkinlik açmaz; antrenman sürerken kapatınca etkinlik hemen kapanır, tekrar açınca yeniden başlar.
10. **İzin kapalı.** Sistem ayarlarında Canlı Etkinlikler kapalıyken antrenman hatasız sürer, etkinlik açılmaz.

Bilinen sınır: uygulama tamamen kapalıyken (öldürülmüş) kilit ekranı düğmeleri çalışmaz, çünkü dinlenme sayacı bellekte
yaşar.
