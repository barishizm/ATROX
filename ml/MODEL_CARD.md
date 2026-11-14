# Model Kartı — ATROX Güç Skoru

> P053 itibarıyla çapa dağılım modeli seçildi. Kalibrasyon (P055 → P057), dışa aktarım (P060) ve cihaz içi
> eşlik (P061–P062) tamamlandıkça bu kart güncellenir.

## Amaç
Kullanıcının bir hareketteki performansını, aynı cinsiyet/yaş/vücut ağırlığındaki salon kullanıcılarına göre
0–100 yüzdelik dilim olarak ifade etmek. Tıbbi veya yarışma tavsiyesi değildir.

## Veri kaynakları
| Kaynak | Kapsam | Lisans | İndirme tarihi | SHA-256 |
|---|---|---|---|---|
| OpenPowerlifting | squat/bench/deadlift (çapa) | Kamu malı (arşivdeki `LICENSE.txt`, bkz. `data/SOURCES.md`) | 2026-11-13 | `becf379e…4503` |
| van den Hoek ve ark. 2024 | Dış doğrulama, 90. yüzdelik (özet) | Yayımlanmış özet (atıf) | 2026-11-13 | — |
| Kalibrasyon çapaları | Salon/genel nüfus (P055) | Her satır kaynaklı, `data/anchors.csv` | 2026-11-13 | — |

Kohort (P048): M/F, Raw (squat'ta wraps ayrı), testli kategori varsayılan referans, yaş 14–85, kilo 30–250 kg;
sporcu × yıl × kaldırış en iyisi, ters-frekans ağırlık (sporcu başına toplam 1). Bölme sporcu bazında %70/15/15.

## Çapa dağılım modeli (P053 kazananı)
**A · Spline-LMS, BCPE ailesi** (`gymml/models/spline_lms.py`): μ, σ, ν, τ cinsiyet başına yaş × log-kilo
tensör çarpımı P-spline'larıyla; kaldırış başına ayrı model. Yapılandırma: yaş 14, kilo 12 düğüm aralığı;
ceza μ 3.27e-4, σ 5.54e-3, ν/τ 0.126. Boyut ≈ 55 KB (pickle üst sınırı), tek çıkarım ≈ 0,13 ms (Python).

Seçim gerekçesi ve tüm sayılar: `reports/bakeoff.md`. Özet (test kümesi, 3 tohum):

| Kaldırış | Pinball (kg) | Bant dışı katman oranı | Kalibrasyon kapısı |
|---|---|---|---|
| squat | 9,115 | %2 | ✅ |
| bench | 6,021 | %5 | ✅ |
| deadlift | 9,102 | %6 | ✅ |

LightGBM pinball'da %0,87 daha iyi ama 17,6 MB ve pürüzsüz değil; %1 eşitlik kuralı A'yı seçer.

**Kullanıcının kabul ettiği sınır durumları (2026-11-13):** pürüzsüzlük testi yalnızca 19 yaştaki genç→yetişkin
bükümünde sınırı aşar (0,011–0,012; 20+ yaşta 0,008–0,009); bench'te kiloda artmama testi eşiktedir (0,0050).

## Bilinen sınırlar
- Yarışmacı powerlifting verisi salon nüfusundan güçlü olma yönünde yanlıdır (bkz. `docs/03-ML-MODEL.md` §5);
  salon/genel nüfus skoru kalibrasyonla türetilir ve "tahmini" etiketi taşır.
- Yarışma verisinde güç kilo sınıfı sınırlarının hemen altında tepe yapar (tartı için kilo düşme). Model
  bunu bilinçli olarak temsil etmez; salon kullanıcısı için pürüzsüz eğri doğru tercihtir.
- 70+ yaş ve uç kilolarda veri seyrek (P048); model orada ekstrapolasyon yapar.
- Ters-frekans ağırlıklı model, kayıt bazlı normların (van den Hoek) %2–8 altında kalır; ağırlıksız sürüm ±%1,6.
- Çapa olmayan hareketler için doğrudan veri yoktur (§6).
- Cinsiyet belirtmeyen kullanıcılar için ortak dağılım kullanılır (§4.5).

## Yeniden eğitim (P094)
`make retrain` (`gymml.retrain.run`) uygulama katkılarıyla (`ml_contributions`, P093) yeni paket üretir:
- **Veri:** yalnızca hücre başına (cinsiyet × 5 yıllık yaş bandı × 10 kg kilo bandı × hareket) ≥ 20 farklı katkıcısı olan
  satırlar; süzülen hücre sayısı her raporda. Ham satırlar diske yazılmaz. Katkıcıların %20'si (anahtara göre) kapılar için ayrılır.
- **Güncellenen:** salon nüfusu δ/κ (önsel = mevcut değer, ağırlığı en az %25 — uygulama kullanıcıları yanlı bir örnek),
  çapa dışı hareketlerin ρ/τ'su (büzülmeli kestirim; makine/kablo C'de kalır, τ sınıf tabanının altına inmez).
- **Güncellenmeyen:** çapa dağılım modeli (yarışmacı verisi), genel nüfus kalibrasyonu, 1RM eğrisi (katkı şeması
  ay başına tek set taşıdığı için öz-denetimli kayıp kurulamıyor; önerilen şema eki raporda, kullanıcı kararı bekliyor).
- **Kapılar:** altın vektör regresyonu, dışarıda tutulan katkılarda kalibrasyon (KS), skor kayması (medyan |Δ| ≤ 5 puan),
  akıl sağlığı (tekdüzelik, κ sınırları, oran değişimi ≤ 2×). Kapıdan geçemeyen paket yazılmaz.
- **Yayın:** P063 betiği, önce %10 kademeli dağıtım. Her sürüm aşağıdaki tabloya satır ekler (hat yazar).

## Sürüm tablosu
| Sürüm | Tarih | Veri | Model | Metrikler | Not |
|---|---|---|---|---|---|
| — | 2026-11-13 | OPL 2026-11-07 anlık görüntüsü | Spline-LMS BCPE (aday) | `reports/bakeoff.md` | Seçildi; henüz dışa aktarılmadı (P060) |
