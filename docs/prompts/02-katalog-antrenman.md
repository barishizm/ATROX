# Faz 3–4 · Hareket Kataloğu, Antrenman Takibi (P024–P045)

---

## Faz 3 — Hareket kataloğu

### P024 · Katalog içe aktarma hattı

```text
tools/catalog altında bir Python (uv) aracı yaz: free-exercise-db'yi içe aktarıp normalleştirilmiş kataloğa çevirir.
- Kaynağı belirli bir commit'e sabitleyerek indir; LICENSE dosyasının Unlicense olduğunu doğrula ve
  tools/catalog/SOURCES.md'ye commit özeti + lisans + erişim tarihi yaz.
- Kararlı slug kimlikleri üret (kaynaktaki id'den; çakışma denetimi). Kimlikler bir kez üretilince asla değişmez:
  tools/catalog/id_lock.json ile kilitle.
- Enum eşlemesi: equipment, mechanic, force, level, category, 17 kas (docs/00-KARARLAR.md §5.4).
  null alanları raporla.
- Doğrulama: zorunlu alanlar, en az bir birincil kas, görsel dosyalarının varlığı, yinelenen adlar.
- Çıktı: tools/catalog/out/exercises.base.json + kalite raporu (kaç hareket, eksik alan sayıları, kategori dağılımı).
pytest ile eşleme ve doğrulama testleri.
```

Kabul: 800+ hareket içe aktarılıyor; kalite raporu üretiliyor; testler geçiyor.

### P025 · Skor taksonomisi `[ARAŞTIRMA]`

```text
docs/03-ML-MODEL.md §6'yı oku. tools/catalog/scoring_taxonomy.yaml dosyasını oluştur: her hareket için
movement_pattern (yatay itiş, dikey itiş, yatay çekiş, dikey çekiş, squat, kalça menteşesi, gövde, izolasyon-*),
scoring_type, load_convention, is_unilateral.
- Önce kural tabanlı otomatik atama yap (ekipman + kas + ad kalıpları), sonra salonda en sık yapılan ~150 hareketi
  "çekirdek" (is_core) olarak seç ve bunların atamalarını tek tek gözden geçir.
- Çekirdek listeyi bana onaylatmak için docs/CEKIRDEK-HAREKETLER.md tablosunu üret (ad, kalıp, tür, yük kuralı).
- Kardiyo, esneme, pliometrik → scoring_type: none. Plank türü → time. Şınav/mekik türü → reps_only.
- anchor, ratio, tau, bw_fraction alanlarını ŞİMDİ doldurma; P056'da doldurulacak (şemada null bırak).
- Şemayı JSON Schema ile tanımla ve doğrulayıcı yaz.
Belirsiz kaldığın atamaları tabloda işaretle; tahmin edip geçme.
```

Kabul: Her hareketin kalıbı ve skor türü var; çekirdek liste onayıma sunulmuş.

### P026 · Türkçe çeviri

```text
Hareket adları, takma adları ve talimatları için Türkçe çeviri hattı kur (tools/catalog/translate.py):
- Önce tools/catalog/glossary.tr.yaml sözlüğünü oluştur: Türk salonlarında gerçekten kullanılan terimler
  (ör. bench press çoğunlukla çevrilmez; pull-up → barfiks; push-up → şınav; lat pulldown → lat pulldown).
  Sözlüğü bana onaylat.
- Çeviri LLM ile toplu yapılır (OpenRouter anahtarı ortam değişkeninden); sözlük zorunlu terim listesi olarak
  isteme girer; çıktı JSON şemasıyla doğrulanır; sonuçlar önbelleğe alınır (aynı girdi tekrar çevrilmez).
- Her hareket için aliases üret: Türkçe karşılık + yaygın İngilizce ad + aksansız yazım.
- Çekirdek ~150 hareket için tools/catalog/review/tr_core.csv incelememe sunulur; onayladığım satırlar kilitlenir.
- Çıktı: exercises.tr.json ve exercises.en.json.
Çeviri kalitesi için örneklem denetimi: 20 rastgele hareketi yan yana göster.
```

Kabul: Tüm hareketlerin TR adı ve talimatı var; çekirdek liste elle onaylanmış.

### P027 · Görsel işleme

```text
tools/catalog/images.py yaz:
- Kaynak JPG'leri iki boyuta dönüştür: küçük resim (ör. 320 px) ve tam boy (ör. 960 px). Biçim: HEIC veya
  WebP — iOS 26'da SwiftUI ile sorunsuz çözülen ve en küçük dosyayı vereni ölçerek seç, kararı belgeye yaz.
- İçerik özetine dayalı dosya adları (önbellek dostu) ve hareket → görsel yolları manifesti.
- Çekirdek hareketlerin küçük resimleri uygulama paketine girer (toplam boyutu raporla, hedef < 15 MB);
  kalan her şey Supabase Storage'da herkese açık "exercise-images" kovasından sunulur.
- Yükleme betiği: yalnızca değişen dosyaları yükler, uzun süreli Cache-Control başlığı koyar.
Toplam boyut, hareket başına görsel sayısı ve görseli eksik hareketler için rapor üret.
```

Kabul: Görseller iki boyutta üretilmiş ve yüklenmiş; paket içi boyut hedefin altında.

### P028 · Katalog tohumlama ve uygulama içi eşitleme

```text
Kataloğu hem sunucuya hem uygulamaya taşı:
- tools/catalog/build.py: base + taksonomi + çeviriler + görsel manifestini birleştirip sürümlü
  catalog.v{N}.json üretir (checksum ile).
- Sunucu: exercises / exercise_translations / catalog_versions tablolarını upsert eden tohumlama betiği
  (servis rolüyle, idempotent).
- Uygulama: catalog.v{N}.json paketlenir. DataKit'te Exercise SwiftData modeli ve CatalogService:
  ilk açılışta paketten içe aktarır; sonraki açılışlarda catalog_versions'ı kontrol edip yalnızca fark varsa günceller.
- Katalog güncellemesi kullanıcının geçmiş antrenmanlarını bozmamalı: kimlikler kilitli, silinen hareket
  "arşivlenmiş" olur.
İçe aktarma süresini ölç (hedef: ilk açılışta < 1 sn, arka planda). Sürüm yükseltme senaryosunu test et.
```

Kabul: İlk açılışta katalog yerelde; sürüm artınca fark eşitleniyor; test geçiyor.

### P029 · Kas haritası

```text
DesignSystem'e MuscleMapView ekle:
- Kaynak aday: react-native-body-highlighter SVG yolları. Önce deposundaki LICENSE'ı oku ve MIT olduğunu doğrula;
  değilse dur ve bana alternatif öner. Uygunsa atfı uygulamadaki lisanslar ekranına ve SOURCES.md'ye ekle.
- SVG yollarını SwiftUI Shape/Path'e çeviren tek seferlik bir betik (tools/musclemap) yaz; ön ve arka görünüm.
- Bizim 17 kasımızı haritadaki bölgelere eşle (birden çoğa eşleme olabilir; eşlenemeyen kası raporla).
- API: MuscleMapView(intensities: [Muscle: Double], style:) — 0–1 yoğunluk vurgu rengine eşlenir; birincil/ikincil
  kas gösterimi için hazır yardımcı; dokunulan kası bildiren geri çağırma.
- Erişilebilirlik: her bölge için VoiceOver etiketi (kas adı + değer).
Bileşen Galerisi'ne örnekler ekle (tek hareket vurgusu, ısı haritası).
```

Kabul: Ön/arka harita 17 kası gösteriyor; dokunma ve VoiceOver çalışıyor; lisans doğrulanmış.

### P030 · Hareket kütüphanesi

```text
Library özelliğini yaz:
- Liste: küçük resim, ad, birincil kas, ekipman rozeti. Bölümler: Son kullanılanlar, Favoriler, Tümü.
- Arama: Türkçe ve İngilizce adlarda ve takma adlarda; aksan ve büyük/küçük harf duyarsız ("sinav" → Şınav);
  yazım hatasına toleranslı basit sıralama (önek > kelime başı > içerir). 800+ kayıtta her tuşta akıcı olmalı.
- Filtreler: kas grubu, ekipman, yalnızca skorlanabilir. Kullanıcının ekipman erişimine göre varsayılan filtre önerisi.
- Favorileme. Seçim modu: programa/antrenmana hareket eklemek için çoklu seçim ve "Ekle (3)" düğmesi.
- Görseller: paket içi küçük resim varsa o, yoksa uzaktan; disk önbelleği ve yer tutucu.
Arama sıralaması ve aksan katlama için birim testleri; kaydırma performansını Instruments ile kontrol et.
```

Kabul: Arama anlık; filtreler birleşebiliyor; çoklu seçim çalışıyor.

### P031 · Hareket detayı ve özel hareket

```text
Hareket detay ekranı:
- İki kareyi (başlangıç/bitiş) yumuşak geçişle döngüde gösteren görsel; dokununca duraklat; kaydırarak elle geçiş.
- Kas haritası (birincil/ikincil), ekipman, mekanik, seviye.
- Adım adım talimatlar (kullanıcının dilinde).
- "Senin verin" bölümü: en iyi set, e1RM, son yapılış, skor halkası — şimdilik boş durum; Faz 6'da dolacak.
- Skor türüne göre bilgi notu (ör. makine hareketi: "Makineler arası yük farklı olduğundan skor düşük güvenlidir").
Özel hareket oluşturma: ad, ekipman, kaslar, yük kuralı; scoring_type varsayılan none; isteğe bağlı olarak
katalogdan bir harekete "benzer" işaretlenebilir (o hareketin skor ayarlarını devralır). custom_exercises ile
senkron olacak biçimde modelle.
```

Kabul: Detay ekranı TR/EN doğru; özel hareket oluşturulup kütüphanede aranabiliyor.

---

## Faz 4 — Antrenman takibi

### P032 · Antrenman veri modelleri

```text
DataKit'e antrenman modellerini ekle (docs/02-MIMARI.md §2.3): Routine, RoutineDay, RoutineExercise, Workout,
WorkoutExercise, SetEntry, PersonalRecord. SchemaV1'e dahil et (henüz yayın yok; göç gerekmez).
- İlişkiler ve silme kuralları (yumuşak silme zincirleme işaretlenir).
- Değişmezler: position alanları boşluksuz; tamamlanmamış set skora girmez; aynı anda en çok bir aktif antrenman.
- Depolar: RoutineRepository, WorkoutRepository (aktif antrenmanı getir, hareket geçmişi, son yapılan setler,
  tarih aralığı sorguları). Sık sorgular için indeksler/predicate'ler.
- P021'deki onboarding setlerini gerçek bir Workout (source = onboarding) olarak kaydet; TODO'yu kapat.
- Fixtures: 12 haftalık gerçekçi örnek geçmiş üreten yardımcı (önizleme, test ve demo hesabı için).
Depolar ve değişmezler için birim testleri.
```

Kabul: Testler geçiyor; örnek geçmiş üreticisi tutarlı veri üretiyor.

### P033 · Program oluşturucu

```text
Program (routine) oluşturma ve düzenleme arayüzü:
- Program: ad, günler (ör. "İtiş", "Çekiş", "Bacak"), her günde hareketler.
- Hareket satırı: hedef set sayısı, tekrar aralığı (ör. 8–12), hedef RIR (isteğe bağlı), dinlenme süresi,
  not. Sürükle-bırak sıralama, kaydırarak silme, çoğaltma.
- Süperset: iki veya daha çok hareketi grupla (görsel bağlayıcı ile).
- Hareket ekleme P030'daki seçim modunu kullanır.
- Haftalık plan: hangi gün hangi programın günü (isteğe bağlı), "aktif program" seçimi.
- Doğrulama: boş gün uyarısı; kas grubu başına haftalık set sayısı özeti (program düzeyinde canlı hesap).
Düzenleme sırasında otomatik kayıt; geri al desteği.
```

Kabul: 3 günlük program 2 dakikada oluşturuluyor; sıralama ve süperset kalıcı.

### P034 · Program şablonları

```text
Hazır program şablonları ekle (paket içi JSON + yükleyici):
- Yeni başlayan tam vücut (3 gün), Üst/Alt (4 gün), İtiş/Çekiş/Bacak (3 ve 6 gün), 5×5 kuvvet (3 gün),
  ev-dumbbell tam vücut (3 gün), yalnızca vücut ağırlığı (3 gün).
- Her şablon: hedef kitle, hedef, haftalık gün, süre tahmini, hareketler (katalog kimlikleriyle), set-tekrar-RIR.
  Haftalık set hacimleri makul aralıkta olsun; her şablonda itiş/çekiş dengesini denetleyen bir test yaz.
- Kişiselleştirme: kullanıcının ekipmanına uymayan hareketleri aynı kalıp + kas grubundan eşdeğeriyle değiştir;
  kısıtlara (ör. omuz) göre işaretlenen hareketler için alternatif öner.
- Onboarding sonunda profil (deneyim, sıklık, ekipman, hedef) ile en uygun 2 şablonu öner.
Şablon seçince düzenlenebilir bir kopya oluşur.
```

Kabul: Tüm şablonlar yükleniyor; ekipman kişiselleştirmesi ve denge testi geçiyor.

### P035 · Aktif antrenman motoru

```text
Aktif antrenmanı yöneten durum makinesini yaz (WorkoutSession, @Observable, arayüzden bağımsız, test edilebilir):
- Başlat: programın bir gününden veya boş. Hedef setler program satırlarından ve son antrenmandaki değerlerden
  ön doldurulur.
- İşlemler: seti tamamla/geri al, ağırlık/tekrar/RIR düzenle, set ekle/sil, set türü değiştir, hareket ekle/çıkar/
  değiştir/sırala, not ekle, antrenmanı bitir/iptal et.
- Her değişiklik anında SwiftData'ya yazılır. Uygulama öldürülse bile aktif antrenman açılışta geri gelir.
- Süre takibi sistem saatine dayanır (arka planda sayaç çalıştırmaya güvenmez).
- Aktif antrenman senkronizasyonda "kilitli" işaretlidir (P044).
- Olay akışı: setCompleted, exerciseCompleted, prAchieved (P040), workoutFinished.
Tüm geçişler, kurtarma ve kenar durumlar (boş antrenmanı bitirme, son seti silme) için birim testleri.
```

Kabul: Durum makinesi testleri geçiyor; uygulama öldürülüp açılınca antrenman kaldığı yerden devam ediyor.

### P036 · Aktif antrenman arayüzü

```text
Aktif antrenman ekranını yaz. Tasarım hedefi: salonda tek elle, set başına en çok 3 dokunuş.
- Hareket kartları; her set satırında: sıra/tür rozeti, "geçen sefer" değeri, ağırlık, tekrar, tamamla düğmesi.
- Ön doldurma: geçen seferki değerler soluk gösterilir; tamamla'ya basınca aynen kabul edilir.
- Özel sayısal tuş takımı: ± plaka adımı düğmeleri, ondalık, "öncekiyle aynı", alanlar arası ilerleme.
- RIR/RPE seçici (isteğe bağlı, ayarlardan kapatılabilir).
- Set türü menüsü (ısınma/normal/drop/tükeniş), kaydırarak silme.
- Üstte süre ve küçültülebilir oturum çubuğu: antrenman sürerken diğer sekmelerde altta mini çubuk.
- Hareket başlığından: detay, geçmiş, değiştir (aynı kalıptan öneriler), not.
- Büyük dokunma hedefleri, haptik geri bildirim, ekranın kapanmasını engelleme seçeneği.
XCUITest: programdan başlat → 3 set tamamla → bitir.
```

Kabul: Ön doldurulmuş set tek dokunuşla tamamlanıyor; UI testi geçiyor.

### P037 · Dinlenme sayacı ve bildirimler

```text
Dinlenme sayacını ekle:
- Set tamamlanınca otomatik başlar (ayarlanabilir); süre hareketin program ayarından, yoksa hareket türüne göre
  varsayılandan (bileşik/izolasyon) gelir.
- Ekranda dairesel sayaç, +15/−15 sn, atla. Bitiş anı sistem saatine göre hesaplanır.
- Arka planda: bitiş anına zamanlanmış yerel bildirim + ses/haptik. Bildirim izni yalnızca ilk sayaç
  başlatıldığında, ön açıklama ekranıyla istenir.
- Uygulama öne gelince bekleyen bildirim iptal edilir.
- NotificationService protokolü: zamanla, iptal et, izin durumu.
Sayaç mantığı için saat enjeksiyonlu birim testleri (arka plana geçiş, süre değiştirme, atlama).
```

Kabul: Uygulama arka plandayken süre bitince bildirim geliyor; testler geçiyor.

### P038 · Live Activity ve Dynamic Island

```text
ActivityKit ile antrenman Live Activity'si ekle (yeni widget uzantısı hedefi project.yml'de; uygulama grubu paylaşımı):
- İçerik: antrenman süresi, geçerli hareket ve set (ör. "Bench Press · 2/4"), dinlenme geri sayımı
  (Text(timerInterval:) ile, sürekli güncelleme göndermeden).
- Kilit ekranı görünümü, Dynamic Island kompakt/minimal/genişletilmiş düzenleri.
- Etkileşim (App Intents): "Dinlenmeyi atla", "+15 sn".
- Yaşam döngüsü: antrenman başlayınca başlar, set/hareket değişince güncellenir, bitince özetle kapanır;
  uygulama çökerse açılışta artık etkinlikler temizlenir.
- Ayarlardan kapatılabilir; izin kapalıysa sessizce atlanır.
Durum → içerik eşlemesini test et; gerçek cihazda elle doğrulama adımlarını docs/TEST-NOTLARI.md'ye yaz.
```

Kabul: Simülatörde Live Activity görünüyor ve geri sayım doğru; etkileşimler çalışıyor.

### P039 · Plaka hesaplayıcı ve ısınma setleri

```text
İki yardımcı araç ekle (mantık StrengthKit'te, saf fonksiyonlar):
- Plaka hesaplayıcı: hedef ağırlık + bar ağırlığı + kullanıcının sahip olduğu plakalar → taraf başına plaka
  dizilimi; tam tutmuyorsa en yakın alt/üst seçenek. kg ve lb plaka setleri; bar türleri (20 kg, 15 kg, EZ, özel).
  Görsel bar çizimi. Set satırındaki ağırlığa uzun basınca açılır.
- Isınma seti üretici: çalışma ağırlığına göre kademeli ısınma (ör. boş bar, %40, %60, %80; tekrarlar azalarak),
  plaka adımına yuvarlanmış; tek dokunuşla antrenmana "ısınma" türünde eklenir.
- Ayarlar: varsayılan bar, mevcut plakalar.
Birim testleri: kenar durumlar (bar ağırlığının altı, tek plaka çifti, lb yuvarlama).
```

Kabul: 100 kg için 20 kg barda 20+15+5 dizilimi; ısınma setleri tek dokunuşla ekleniyor.

### P040 · Rekor tespiti

```text
Rekor (PR) motorunu yaz (StrengthKit + DataKit):
- Türler: en ağır ağırlık, belirli ağırlıkta en çok tekrar, en yüksek e1RM, tek sette en yüksek hacim.
- e1RM için şimdilik StrengthKit'te Epley tabanlı geçici fonksiyon kullan ve TODO(P061) bırak; arabirimi
  docs/03-ML-MODEL.md §2 ile uyumlu tasarla (güven ağırlığı döndürsün).
- Isınma setleri ve tamamlanmamış setler rekor sayılmaz. İlk kez yapılan hareketteki ilk set "ilk kayıt"tır, kutlanmaz.
- Geçmiş düzenlenince/silinince rekorlar yeniden hesaplanır (artımlı; tüm geçmişi her seferinde taramaz).
- Aykırı değer koruması: e1RM bir önceki en iyinin %12 üzerindeyse kutlamadan önce "Bu seti doğru mu girdin?" onayı.
- Arayüz: set tamamlanınca satırda rekor rozeti + hafif kutlama animasyonu ve haptik; abartısız.
Kapsamlı birim testleri (düzenleme/silme sonrası tutarlılık dahil).
```

Kabul: Rekorlar doğru tespit ediliyor; geçmiş düzenlenince tutarlı kalıyor.

### P041 · Antrenman özeti ve HealthKit kaydı

```text
Antrenman bitiş akışı:
- Özet ekranı: süre, toplam hacim, set sayısı, çalışılan kaslar (MuscleMapView ile yoğunluk), kırılan rekorlar,
  önceki aynı antrenmanla karşılaştırma. Koç yorumu ve skor değişimi için yer tutucu bölümler (Faz 6–7).
- İsteğe bağlı: antrenman adı, not, his (1–5).
- HealthKit'e HKWorkout (traditionalStrengthTraining) olarak başlangıç/bitiş ile yaz; yinelenen yazmayı engelle
  (HealthKit UUID'sini Workout'ta sakla); antrenman silinirse Sağlık kaydını da sil.
- Tamamlanmamış setler için: "Sil ve bitir" / "Geri dön".
- 2 dakikadan kısa veya setsiz antrenmanı kaydetmeden önce sor.
Özet hesaplamalarını (hacim, kas yoğunluğu) saf fonksiyonlar olarak yaz ve test et.
```

Kabul: Biten antrenman Sağlık uygulamasında görünüyor; özet değerleri testlerle doğrulanmış.

### P042 · Geçmiş

```text
Antrenman sekmesinin geçmiş bölümü:
- Takvim görünümü (antrenman günleri işaretli, aylık özet) ve kronolojik liste.
- Antrenman detayı: hareketler, setler, rekorlar, notlar; düzenleme (set değerleri, ekleme/silme), silme (geri al ile).
- "Tekrarla": geçmiş antrenmandan yeni aktif antrenman başlat. "Programa dönüştür".
- Hareket geçmişi ekranı: bir hareketin tüm oturumları, en iyi setler, basit e1RM çizgi grafiği (Swift Charts).
  Hareket detayındaki "Senin verin" bölümünü buna bağla.
- Büyük geçmişte performans: sayfalı yükleme; 500 antrenmanlık örnek veriyle akıcılığı ölç.
Düzenleme sonrası rekorların ve özetlerin yeniden hesaplandığını test et.
```

Kabul: 500 antrenmanla liste akıcı; düzenleme rekorları güncelliyor.

### P043 · Aşamalı yüklenme önerisi

```text
"Bir sonraki antrenmanda ne yapmalıyım?" motorunu yaz (StrengthKit, saf mantık):
- Çift ilerleme: tüm setlerde tekrar aralığının üst sınırına ulaşıldıysa ağırlığı en küçük anlamlı adımla artır
  (alt vücut bileşik için büyük, üst vücut/izolasyon için küçük adım; plaka adımına yuvarlı) ve tekrarı alt sınıra
  çek; ulaşılmadıysa aynı ağırlıkta +1 tekrar hedefle.
- RIR girildiyse: hedef RIR'den belirgin kolaysa daha hızlı, zorsa aynı yükte kal.
- İki ardışık oturumda gerileme varsa: aynı yükü koru ve "toparlanma" notu üret; üç ardışık oturumda yoksa
  ilerleme → %10 hafifletme (deload) önerisi.
- Çıktı: hedef ağırlık × tekrar + tek cümlelik gerekçe (yerelleştirilmiş şablon).
- Aktif antrenmanda set satırlarındaki ön doldurma bu öneriyi kullanır; kullanıcı her zaman değiştirebilir.
Kural tablosunu docs/ANTRENMAN-MANTIGI.md'ye yaz. Senaryo tabanlı birim testleri.
```

Kabul: Senaryo testleri geçiyor; öneriler aktif antrenmanda gerekçesiyle görünüyor.

### P044 · Senkronizasyon motoru 1 — çekirdek

```text
docs/02-MIMARI.md §2.4'ü uygula. DataKit'te SyncEngine (actor):
- SyncableModel protokolü: tablo adı, DTO'ya/DTO'dan dönüşüm (Codable, snake_case), bağımlılık sırası.
- Push: pending kayıtları bağımlılık sırasıyla, tablo başına toplu upsert (parça boyutu sınırlı); başarıda synced,
  kalıcı hatada failed + neden.
- Pull: tablo başına sunucu saatli imleç (updated_at > imleç, sayfalı); gelen kaydı yerelle birleştir:
  son-yazan-kazanır; yerelde pending olan ve daha yeni olan kayıt ezilmez; deleted_at mezar taşları uygulanır.
- Aktif antrenman ağacı kilitlidir: pull onu ezmez, push onu göndermez (bitene kadar).
- Uzak erişim RemoteStore protokolünün arkasında; Supabase uygulaması + testler için bellek içi sahte sunucu.
- Kapsam: profiles, user_settings, body_measurements, custom_exercises, routines*, workouts*, sets, personal_records.
Sahte sunucuyla testler: çevrimdışı kuyruk, çakışma, mezar taşı, kısmi başarısızlık, saat kayması.
```

Kabul: Tüm senkron testleri geçiyor; yerel Supabase'e karşı iki simülatör arasında veri taşınıyor.

### P045 · Senkronizasyon motoru 2 — orkestrasyon ve hesap işlemleri

```text
Senkronizasyonu ürünleştir:
- Tetikleyiciler: öne gelince, antrenman bitince, ağ geri gelince (NWPathMonitor), yazmadan birkaç saniye sonra
  (debounce), 15 dakikada bir. Üstel geri çekilme + jitter. Aynı anda tek senkron.
- İlk giriş geri yüklemesi: tüm veriyi sayfalı çek, ilerleme göstergesi; yarıda kesilirse devam et.
- Çıkış: bekleyen değişiklik varsa uyar; yerel veriyi temizle. Farklı hesapla girişte veri karışmamalı.
- Senkron durumu arayüzü: Profil'de son eşitleme zamanı, bekleyen sayısı, hata ve "şimdi eşitle".
- Edge Functions: delete-account (tüm kullanıcı verisi + Auth kaydı + Apple token iptali) ve export-data (JSON).
  P022'deki sahte servisleri bunlarla değiştir. İkisi için deno testleri.
- BGAppRefreshTask ile fırsatçı arka plan eşitlemesi.
Uçtan uca senaryo: cihaz A'da antrenman → cihaz B'de görünür; çevrimdışı düzenleme → çevrimiçi olunca birleşir.
```

Kabul: Uçtan uca senaryo çalışıyor; hesap silme tüm satırları kaldırıyor; dışa aktarma geçerli JSON üretiyor.
