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

## P039 — Plaka hesaplayıcı ve ısınma setleri (elle doğrulama)

1. **Hesaplayıcıyı aç.** Aktif antrenmanda bir setin ağırlığına uzun bas: "Plaka hesaplayıcı" açılır, hedef o setin
   ağırlığıdır. 100 kg, 20 kg olimpik bar için tek taraf `25 + 15` (ya da `20 + 20`) görünür; çizimde bar iki yanda simetrik.
2. **Alt/üst seçenekler.** Hedefi 101 kg yap: "Tam eşleşme" kaybolur, alt (100) ve üst (102,5) seçenekleri çıkar; satıra
   dokununca hedef o yüke gider. Hedefi bardan hafif yap: "Bardan hafif" uyarısı.
3. **Bar türleri.** Olimpik 20/15, EZ, özel arasında geç; özel barda ağırlığı değiştir. lb biriminde 45 lb bar ve lb plakaları.
4. **Sete uygula.** "Bu sete uygula" setin ağırlığını günceller.
5. **Ayarlar.** Ayarlar → Bar ve plakalar: bir plakayı kapat (ör. 25 kg), hesaplayıcıda artık kullanılmadığını doğrula.
6. **Isınma.** Bir hareketin ilk setine çalışma ağırlığı yaz (ör. 100 kg), hareket menüsünden "Isınma setleri ekle": bar ×10,
   40 ×8, 60 ×5, 80 ×3 ısınma (W) setleri en üste eklenir, çalışma setleri aşağı kayar. Ağırlık yokken menü öğesi pasif.

## P040 — Rekor tespiti (elle doğrulama)

1. **İlk kayıt.** Hiç yapılmamış bir harekette ilk seti tamamla: rozet çıkmaz.
2. **Rekor.** Aynı harekette sonraki antrenmanda daha ağır (veya aynı ağırlıkta daha çok tekrar) bir seti tamamla: satırda kupa rozeti
   ve hafif zıplama + haptik. Eşit değer rozet vermez; ısınma seti vermez.
3. **Geri alma / düzenleme.** Rozetli seti geri al veya ağırlığını değiştir: rozet kalkar; yeni değer yine rekorsa tamamlayınca döner.
4. **Aykırı değer.** Önceki en iyiden ~%15 fazla e1RM'li set: "Bu seti doğru mu girdin?" sorusu. Evet → rozet; Düzelt → ağırlık tuş takımı açılır.
5. **Silme.** Rekoru taşıyan antrenmanı iptal et/sil: bir sonraki daha hafif set önceki en iyiye göre yeniden değerlendirilir.

## P041 — Antrenman özeti ve Sağlık kaydı (elle doğrulama)
1. **Tam akış.** Birkaç set tamamla, Bitir: onay → özet ekranı (süre, hacim, set, kas haritası, rekor varsa liste). Ad/not/yıldız gir, Bitti: Antrenman sekmesine dönülür.
2. **Açık setler.** Bir setı boş bırak, Bitir: "N set tamamlanmadı" → "Sil ve bitir" / "Geri dön".
3. **Kısa/boş.** Hiç set tamamlamadan Bitir: yalnızca "Antrenmanı sil". 2 dakikadan kısa antrenman: Kaydet / Sil / Geri dön.
4. **Sağlık.** Sağlık izni verilmişse Sağlık → Gezin → Egzersiz: "Güç Antrenmanı" kaydı başlangıç/bitişle görünür; aynı antrenman ikinci kez yazılmaz. İzin kapalıysa hata göstermeden atlanır.
5. **Karşılaştırma.** Aynı gün programından ikinci antrenman: özet "… tarihli antrenmanla karşılaştırıldı" ve hacim farkını gösterir.

## P042 — Geçmiş (elle doğrulama)
1. **Takvim ve liste.** Antrenman → Geçmiş: bu ayın antrenman günlerinde nokta, altında ay özeti. Ok düğmeleriyle önceki aya geç; gelecek aya geçilemez.
2. **Detay ve düzenleme.** Bir antrenmana gir → Düzenle: bir setin ağırlığını yükselt (rekor rozeti oraya taşınır), set ekle/sil, hareket ekle/kaldır. Hareket başlığına dokun: hareket geçmişi.
3. **Rekor tutarlılığı.** Rekoru taşıyan antrenmanı sil: önceki en iyi rekor olarak döner. "Geri al" (8 sn): rekor geri gelir, Sağlık'ta kayıt yeniden görünür.
4. **Tekrarla / Programa dönüştür.** Tekrarla: aynı hareket ve ağırlıklarla, hiçbir set tamamlanmamış yeni antrenman açılır (zaten antrenman varsa uyarı). Programa dönüştür: Programlar'da tek günlü yeni program.
5. **Hareket detayı.** Kütüphane → bir hareket → "Senin verin": en iyi set, e1RM, son antrenman; "Tüm geçmiş ve grafik" e1RM çizgisini gösterir (en az iki oturum).
6. **Uzun geçmiş.** Uygulamada 500 antrenmanı yükleyen bir hata ayıklama düğmesi yok; akıcılık yalnızca birim testlerle (`LargeHistoryTests`) ölçüldü. Gerçek cihazda uzun bir geçmişle kaydırma elle denenmeli.
