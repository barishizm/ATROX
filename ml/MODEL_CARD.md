# Model Kartı — ATROX Güç Skoru

> İskelet (P046). İçerik model eğitildikçe (P050–P058) doldurulur; boş bölümler bilerek boştur.

## Amaç
Kullanıcının bir hareketteki performansını, aynı cinsiyet/yaş/vücut ağırlığındaki salon kullanıcılarına göre
0–100 yüzdelik dilim olarak ifade etmek. Tıbbi veya yarışma tavsiyesi değildir.

## Veri kaynakları
| Kaynak | Kapsam | Lisans | İndirme tarihi | SHA-256 |
|---|---|---|---|---|
| OpenPowerlifting | squat/bench/deadlift (çapa) | _P047'de `data/SOURCES.md`'ye işlenecek_ | — | — |

## Bilinen sınırlar
- Yarışmacı powerlifting verisi salon nüfusundan güçlü olma yönünde yanlıdır (bkz. `docs/03-ML-MODEL.md` §5).
- Çapa olmayan hareketler için doğrudan veri yoktur (§6).
- Cinsiyet belirtmeyen kullanıcılar için ortak dağılım kullanılır (§4.5).

## Sürüm tablosu
| Sürüm | Tarih | Veri | Model | Metrikler | Not |
|---|---|---|---|---|---|
| — | — | — | — | — | Henüz yayımlanmış sürüm yok |
