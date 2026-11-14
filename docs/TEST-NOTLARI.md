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

## P044/P045 — Senkronizasyon ve hesap işlemleri (elle doğrulama)

Hazırlık: `supabase start && supabase db reset`, `supabase functions serve` (ayrı terminal). İki simülatör (ör. iPhone 14
ve ikinci bir cihaz) Debug yapılandırmasında yerel Supabase'e bağlı.

1. **Cihaz A → B:** A'da giriş yap, bir antrenman başlat → 2 set tamamla. Antrenman sürerken `sets` tablosunda satır
   olmamalı (`select count(*) from sets`). Bitir → birkaç saniye içinde satırlar sunucuda. B'de aynı hesapla giriş:
   "Verilerin geri yükleniyor" ekranı, ardından Geçmiş'te antrenman ve setler görünür.
2. **Çevrimdışı düzenleme:** B'yi çevrimdışı yap (Mac'te ağı kapat), bir ölçüm ekle ve geçmişte bir seti düzenle.
   Profil kartı "Eşitlenmeyi bekleyen: 2" göstermeli. Ağı aç → kart "Güncel"e döner; A öne gelince değişiklikleri alır.
3. **Çakışma:** A ve B'de aynı ölçümü çevrimdışı farklı değerlerle düzenle (önce A, sonra B); ikisini de çevrimiçi yap →
   iki cihazda da B'nin değeri kalır.
4. **Çıkış uyarısı:** çevrimdışıyken bir değişiklik yap → Ayarlar → Çıkış: uyarıda "1 değişiklik henüz sunucuya
   ulaşmadı" yazmalı. Çıkış sonrası farklı hesapla giriş: önceki hesabın verisi görünmemeli.
5. **Dışa aktarma:** Ayarlar → Verilerimi dışa aktar → paylaş sayfası açılır; dosya geçerli JSON, `tables` altında
   tüm tablolar.
6. **Hesap silme:** Ayarlar → Hesabı sil → onay kelimesi. Sonra `select count(*) from auth.users where id = …` ve kullanıcı
   tablolarında satır kalmamalı. Apple hesabıyla: Apple onay sayfası bir kez daha açılır; Apple secret'ları tanımlı değilse
   yanıt `apple_revoked: null`.
7. **Arka plan eşitlemesi:** uygulamayı arka plana al, Xcode'da duraklat ve
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.barishizm.atrox.sync.refresh"]`
   → devam et; logda `sync` kategorisinde hata olmamalı ve bekleyen satırlar gönderilmeli.

## P088 · Davet bağlantıları (gerçek cihaz / simülatör)

Ön koşul: alan adı hazır ve `web/` yayında; `APP_LINK_HOST` ve `TEAMID` gerçek değerlerde; App ID'de Associated Domains açık.

1. **AASA:** `curl -sI https://<alan-adı>/.well-known/apple-app-site-association` → `200`, `content-type: application/json`, yönlendirme yok.
   Apple CDN önbelleği için cihazda kurulumdan sonra birkaç dakika bekle.
2. **Simülatör (şema):** `xcrun simctl openurl booted "atrox://u/<kullanıcı_adı>"` → Profil sekmesi > Arkadaşlar > Davet ekranı açılır.
   `atrox://today`, `atrox://coach`, `atrox://weekly` ilgili ekranı açar.
3. **Evrensel bağlantı (gerçek cihaz):** Notlar'a `https://<alan-adı>/u/<kullanıcı_adı>` yaz ve dokun → uygulama açılır (Safari'de adres çubuğundan açılırsa web sayfası görünür; sayfadaki "ATROX'ta aç" düğmesi uygulamayı açar).
4. **Uygulama yüklü değil:** aynı bağlantı web sayfasını ve App Store düğmesini gösterir.
5. **Oturum kapalı:** çıkış yap, bağlantıyı aç → giriş ekranı; giriş/onboarding bitince davet ekranı açılır.
6. **Davet ekranı:** profilin yoksa önce katılma formu; kendi bağlantın → "kendi davet bağlantın"; olmayan kullanıcı → "bulunamadı"; aranabilir olmayan biri de bulunur ve istek gönderilebilir.
7. **Paylaşım:** Arkadaşlar > Ekle > Davet et → metinde bağlantı bulunur.

## P092 · App Store Connect abonelikleri ve sandbox uçtan uca `[MANUEL]`

Ön koşul: Ücretli Uygulamalar Sözleşmesi, banka ve vergi bilgileri tamam; abonelik grubu ve iki ürün (`atrox.pro.monthly`,
`atrox.pro.yearly`; yıllıkta ücretsiz deneme) App Store Connect'te; staging projesinde `appstore-notifications` ve
`verify-purchase` yayında, V2 bildirim URL'leri (production ve sandbox) tanımlı; gerçek cihazda sandbox test hesabı.

| # | Adım | Beklenen | Sonuç |
|---|---|---|---|
| 1 | Profil > ATROX Pro: planlar yüklenir | Yıllık öne çıkar; yerelleştirilmiş fiyat, aylık eşdeğer, deneme metni | _bekliyor_ |
| 2 | Yıllık planı satın al | Pro açılır; paywall "Pro'sun" gösterir | _bekliyor_ |
| 3 | Supabase `entitlements` | Satır oluştu (`environment = sandbox`, `status = trial` veya `active`) | _bekliyor_ |
| 4 | Koç kotası | `coach-chat` yanıtında katman `pro` | _bekliyor_ |
| 5 | Aboneliği iptal et (Ayarlar > Abonelikler) | Dönem sonuna kadar Pro, `will_renew = false` | _bekliyor_ |
| 6 | Sandbox süresi dolunca | `entitlements.status = expired`; uygulama ücretsize döner, kilitler geri gelir | _bekliyor_ |
| 7 | "Satın alımları geri yükle" (silinip yeniden kurulmuş uygulamada) | Pro geri gelir | _bekliyor_ |

Sonuçlar ve tarih: _(doldurulacak)_
