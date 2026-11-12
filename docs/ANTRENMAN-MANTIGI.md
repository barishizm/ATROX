# Antrenman mantığı — aşamalı yüklenme önerisi (P043)

"Bir sonraki antrenmanda ne yapmalıyım?" sorusunun cevabı `StrengthKit/ProgressionEngine` içinde saf bir fonksiyondur
(`ProgressionEngine.suggest`). Aynı girdi her zaman aynı çıktıyı verir; arayüz ve sunucu bu hesabı tekrar yazmaz.
Aktif antrenmandaki set ön doldurması (`WorkoutPrefill`, `WorkoutSession`) bu öneriyi kullanır; kullanıcı her değeri
değiştirebilir.

## Girdi

| Alan | Kaynak |
|---|---|
| `history` | Hareketin son 6 bitmiş oturumu, en yeni önce; yalnızca tamamlanmış **çalışma** setleri (ısınma yok) |
| `repMin`, `repMax` | Programdaki hedef tekrar aralığı; program yoksa varsayılan **8–12** |
| `targetRir` | Programın hedef RIR'i; yoksa varsayılan **2** |
| `loadClass` | Katalogdan: `squat`, `hip_hinge`, `olympic` → alt vücut bileşik; `isolation_*` veya `mechanic = isolation` → izolasyon; gerisi üst vücut bileşik |
| `roundingStepKg` | Kullanıcının birimindeki en küçük plaka adımı (2,5 kg veya 5 lb), kg olarak |

Geçmişi olmayan hareket için öneri **yoktur**; ön doldurma eski davranışla (program hedefleri / boş setler) çalışır.

## Ağırlık adımı

`artış = max(sınıfın istenen adımı → plaka adımına en yakın katı, 1 plaka adımı)`

| Sınıf | İstenen | kg (adım 2,5) | lb (adım 5 lb) |
|---|---|---|---|
| Alt vücut bileşik | 5 kg | 5 kg | 10 lb |
| Üst vücut bileşik | 2,5 kg | 2,5 kg | 5 lb |
| İzolasyon | 1,25 kg | 2,5 kg (en az 1 adım) | 5 lb |

Yeni ağırlık her zaman plaka adımının katıdır.

## Kural tablosu (yukarıdan aşağıya, ilk eşleşen kazanır)

Oturum başarımı = oturumun en iyi e1RM'i (geçici Epley; tamamen vücut ağırlığıysa en iyi tekrar). Önceki oturuma göre
**%1'den fazla artış = ilerleme**, **%1'den fazla düşüş = gerileme**, aradaki = durgun.

| # | Koşul | Öneri | Gerekçe anahtarı |
|---|---|---|---|
| 1 | Geçmiş yok | Öneri yok | — |
| 2 | En ağır set 0 kg (vücut ağırlığı) | aynı, en zayıf set + 1 tekrar | `addRepBodyweight` |
| 3 | Son üç karşılaştırmanın hepsi ilerleme değil (en az 4 oturum) | son en ağır ağırlığın **%90'ı** (plakaya yuvarlı, en az 1 adım) × `repMax` | `deload` |
| 4 | Son iki karşılaştırma gerileme | aynı ağırlık, en zayıf setin tekrarı (≤ `repMax`) | `recovery` |
| 5 | Ort. RIR ≤ hedef − 1 (hedefe göre zor) | aynı ağırlık, en zayıf setin tekrarı | `holdHard` |
| 6 | Tüm setler en ağır ağırlıkta ve ≥ `repMax` | ağırlık + artış, `repMin`; RIR ≥ hedef + 2 ise artış **2 katı** | `addWeight` / `addWeightFast` |
| 7 | Diğer | aynı ağırlık, en zayıf set + 1 tekrar (RIR ≥ hedef + 2 ise **+2**), `repMax` ile sınırlı | `addRep` / `addRepsFast` |

Notlar:
- RIR kuralları yalnızca RIR girilmiş setlerin ortalamasına bakar; hiç RIR yoksa "hedefte" sayılır.
- 3. kural 4'ten önce gelir: üç ardışık gerileme de deload'dır, iki gerileme toparlanma notudur.
- Toparlanma ve deload ilerleme/durgunluk sayımını sıfırlamaz; kullanıcı ilerleyince (e1RM > %1) zincir kırılır.

## Ön doldurma

`WorkoutPrefill.sets(target:last:suggestion:)` öneri varsa **her çalışma setine** `ağırlık × tekrar` yazar. Set sayısı
programın `targetSets`'idir; program yoksa geçen seferki çalışma seti sayısı (en az 1). RIR programın hedef RIR'idir.
Program yoksa geçen seferki ısınma setleri aynen korunur. Öneri yoksa eski davranış geçerlidir.

Gerekçe cümlesi hareket kartında (set tablosunun üstünde) gösterilir: "Hedef 62,5 kg × 8. …". Cümle şablonları String
Catalog'da (`progression.*`), Türkçe + İngilizce.

## Bilinen sınırlar

- e1RM geçici Epley'dir (`TODO(P061)`); bu yüzden "ilerleme/gerileme" eşiği kaba.
- Özel hareketler katalog sınıfı taşımadığı için "üst vücut bileşik" sayılır.
- Süperset, düşürme seti ve başarısızlık setleri çalışma seti olarak hesaba girer (ısınma hariç).
- Aralık dışı (ör. 20 tekrar) geçmişte öneri ağırlığı artırıp `repMin`'e döner; programsız hareketlerde varsayılan aralık 8–12'dir.
