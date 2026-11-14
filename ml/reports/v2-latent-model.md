# P095 — v2 gizil faktör modeli: araştırma raporu

> Otomatik üretildi: `make latent` (`gymml.research.latent`). Tablolar betikten; karar bölümü de betiğin eşik kuralından türetilir. Üretim kodu değildir.

## Karar özeti

- **Etkinleştirme eşiği: 1,000 katkıcı** (önceki tahmin ~5.000). Kural: o büyüklükte ve daha büyük her büyüklükte, *her tohumda* gizil model P094'ün veriyle güncellenen oran tablosundan en az %5 daha düşük hata verir ve yükleme uzayı geri kazanımı ≥ 0.9. Kazanç büyüklüğe göre: 250: %8–13, 500: %9–15, 1,000: %11–16, 2,500: %12–18, 5,000: %10–20, 10,000: %8–14, 20,000: %8–13. %10 kuralıyla eşik bulunamıyor: kazanç N ile büyümüyor (tablo da veriyle iyileşiyor), bu yüzden eşiği veri miktarından çok yapının geri kazanımı belirliyor.
- **Hareket başına koşul:** gizil model en az gözlemli bantta bile güncellenmiş tabloyu geçiyor; §12'deki "hareket başına ≥ 300 gözlem" koşulu gerekmiyor, çünkü b_e'nin önseli oran tablosu ve λ_e kalıp ortalamasına büzülüyor: az gözlemli hareket kendiliğinden tabloya düşer. Koşul yerine bu önseller zorunlu.
- Sentetik eşik yalnızca *denemeye değer* noktayı söyler; etkinleştirme, aynı ölçüt gerçek katkılarda (P094 dışarıda tutulan katkıcılar) sağlandığında ve P094 kalite kapılarıyla yapılır.
- Seçilen biçim: düzenlileştirilmiş matris ayrıştırma + kovaryatlı önsel (hiyerarşik Gauss modelinin MAP'i); b_e önseli oran tablosu, λ_e önseli kalıp ortalaması. K veriyle seçilir: bu dünyada tahmin için K = 1–2 yetiyor, K = 3 ancak kişi × hareket uzmanlaşması küçükse kazanıyor (§3 duyarlılık) — dengesizlik yorumu için K ≥ 2 şart. Tam hiyerarşik Bayes (MCMC) şimdilik gereksiz: kestirim sunucuda, cihazda yalnızca K×K çözüm var.
- **Öneri:** v2'yi ürünleştirmeden önce P094 hattına bir *gölge* adım ekle: her yeniden eğitimde gizil model de uyarlanır ve gerçek dışarıda tutulan katkılarda aynı hareket-gizleme ölçütüyle raporlanır; eşik gerçek veride sağlanınca (ve kullanıcı onayıyla) başlangıç ağırlığı önerisinden başlayarak açılır.

## 1. Model

```
log e1RM_{u,e} = b_e + λ_e · θ_u + ε,      ε ~ N(0, σ²)
θ_u ~ N(Γ x_u, I_K),  x_u = [erkek, (yaş − 35)/15, log(kilo/75), (boy − 172)/10]
λ_e ~ N(0, s_λ² I_K)
```

- `b_e` hareketin zorluk sabiti (log ölçek), `λ_e` yükleme vektörü, `θ_u` kullanıcının güç vektörü (itiş / çekiş / alt vücut gibi yorumlanabilir ama dönmeye kadar belirlidir).
- **Seçenekler:** (a) hiyerarşik Bayes (Stan/NumPyro; belirsizlik doğal, ama 10⁵–10⁶ gözlemde dakikalar–saatler ve CI'da ağır); (b) düzenlileştirilmiş matris ayrıştırma (ALS, saniyeler; belirsizlik θ'nın Laplace yaklaşımıyla: (ΛᵀΛ/σ² + I)⁻¹). Prototip (b); (a) yalnızca kalibrasyon kontrolü için önerilir.
- Kovaryatlar θ'nın önsel ortalamasına girer: hiç hareket kaydetmemiş kullanıcı için tahmin Γx'tir (başlangıç ağırlığı), her yeni kayıt θ'yı kişiye doğru çeker.

## 2. Sentetik dünya

- Gerçek katalogdaki 142 skorlanan çapalı hareket; doğru yapı K = 3 (itiş / çekiş / alt), faktörler arası 0,7 korelasyon (genel güç), yüklemeler kalıptan + gürültü, log ölçekte hareket başına 0,13–0,22 yayılım (P056: hücre içi SS 0,19–0,26 ile uyumlu).
- Kişi × hareket uzmanlaşması SS 0.1, e1RM tahmin gürültüsü SS 0.05: hiçbir modelin aşamayacağı taban hata ≈ %9.3 (MAE).
- Eksiklik: her kullanıcı 5–15 hareket; seçim olasılığı popülerlik sırasıyla Zipf (çapalar ve A/B sınıfı önde) → uzun kuyruktaki hareketler az gözlenir (gerçek uygulamadaki gibi).
- Karşılaştırma: (1) P056 oran tablosu (sınıfına göre hata: A 0,03 / B 0,07 / C 0,20 log), (2) P094 gibi veriyle güncellenen tablo (iki yönlü model y = a_u + c_e, c_e tabloya büzülür), (3) gizil model, (4) yalnızca kovaryat.

## 3. Değerlendirme: hiç yapılmamış hareketin e1RM tahmini

Test kullanıcıları (1.000, eğitimde yok) için gözlenen hareketlerden biri gizlenir, kalanlardan tahmin edilir. Gizil modelde θ cihazdaki gibi katlanır (fold-in). Hata log ölçekte MAE, yüzde olarak gösterilir.

| Katkıcı | Oran tablosu | Güncellenmiş tablo | Gizil (K=3) | Yalnız kovaryat | ±%10 içinde (gizil / tablo) | Yapı geri kazanımı |
|---|---|---|---|---|---|---|
| 250 | %21.4 | %14.6 | %13.1 | %24.6 | %47 / %43 | 0.526 |
| 500 | %20.7 | %14.1 | %12.2 | %22.9 | %50 / %45 | 0.901 |
| 1,000 | %21.5 | %14.4 | %12.3 | %24.4 | %50 / %44 | 0.920 |
| 2,500 | %21.1 | %14.4 | %12.2 | %23.4 | %51 / %45 | 0.951 |
| 5,000 | %20.6 | %14.3 | %12.0 | %23.9 | %52 / %44 | 0.964 |
| 10,000 | %20.6 | %14.0 | %12.4 | %24.1 | %51 / %44 | 0.974 |
| 20,000 | %20.3 | %13.9 | %12.4 | %23.6 | %50 / %46 | 0.980 |

Her satır 3 tohumun ortalaması. Yapı geri kazanımı: gerçek ve kestirilen yükleme uzaylarının en büyük asal açısının kosinüsü (1 = aynı uzay).

### Gizil boyut sayısı

| Katkıcı | K | Gizil MAE | Güncellenmiş tablo MAE |
|---|---|---|---|
| 1,000 | 1 | %11.8 | %14.9 |
| 1,000 | 2 | %11.7 | %14.9 |
| 1,000 | 3 | %12.6 | %14.9 |
| 1,000 | 4 | %13.7 | %14.9 |
| 1,000 | 5 | %15.2 | %14.9 |
| 5,000 | 1 | %11.6 | %14.0 |
| 5,000 | 2 | %11.6 | %14.0 |
| 5,000 | 3 | %12.5 | %14.0 |
| 5,000 | 4 | %13.3 | %14.0 |
| 5,000 | 5 | %14.7 | %14.0 |

En iyi K: 1,000 katkıcıda K = 2, 5,000 katkıcıda K = 1. Üretimde K, P094'teki dışarıda tutulan katkıcılarla aynı hareket-gizleme ölçütüyle seçilir; doğru K'dan büyük K, düzenlileştirme sayesinde az zarar verir.

### Duyarlılık: kişi × hareket uzmanlaşması

| Uzmanlaşma SS | K | Gizil MAE | Güncellenmiş tablo MAE | Yapı geri kazanımı |
|---|---|---|---|---|
| 0.05 | 1 | %8.5 | %11.0 | 1.000 |
| 0.05 | 3 | %7.8 | %11.0 | 0.987 |
| 0.1 | 1 | %11.6 | %14.0 | 1.000 |
| 0.1 | 3 | %12.5 | %14.0 | 0.964 |
| 0.15 | 1 | %15.7 | %18.2 | 1.000 |
| 0.15 | 3 | %18.3 | %18.2 | 0.920 |

Uzmanlaşma büyüdükçe faktörler arası fark (itiş/çekiş/alt) az sayıda kayıttan ayırt edilemez ve K = 1 öne geçer. Gerçek veride bu SS, P094'teki oran kalıntılarından (`between_sd`) üst sınırla kestirilebilir.

### Hareket başına gözlem sayısı (20,000 katkıcı)

| Eğitimdeki gözlem | Hareket × tohum | Gizil MAE | Güncellenmiş tablo MAE |
|---|---|---|---|
| 300–999 | 252 | %12.4 | %13.9 |
| 1000–2999 | 117 | %12.1 | %14.0 |
| ≥ 3000 | 45 | %12.6 | %13.2 |

## 4. Ürün etkisi

- **Başlangıç ağırlığı önerisi:** bugün çapası olmayan bir harekete ilk girişte öneri yok ya da oran tablosundan kaba bir değer var. Gizil modelle tahmin, kullanıcının yaptığı *tüm* hareketlerden gelir (yukarıdaki tablo); 8 tekrarlık öneri = e1RM⁻¹(tahmin, 8) × 0,9 güvenlik payı, ilk sette RIR sorusu. Hiç kaydı olmayan kullanıcıda Γx (kovaryat) tahmini kullanılır — hatası büyük, yalnızca "hafif başla" aralığı olarak gösterilmeli.
- **Dengesizlik:** P059 kalıntı tabanlıydı; gizil modelde θ'nın bileşenleri (itiş/çekiş/alt) doğrudan karşılaştırılır ve kişinin kendi kovaryatlı beklentisine (Γx) göre sapma ölçülür; az hareketli kullanıcıda önsel baskın olduğu için yanlış alarm azalır.
- **Genel skor:** §8 korelasyonlu birleştirme yerine θ'nın kovaryatlı nüfustaki yüzdeliği (Λ ağırlıklı) kullanılabilir. Geçişte iki skor bir süre paralel hesaplanır; P094'ün kayma kapısı (medyan ≤ 5 puan) aynen uygulanır.
- **Hareket skoru:** değişmez (gözlenen e1RM'den yüzdelik); gizil model yalnızca *gözlenmemiş* hareketlere ve oranların yerine geçen b_e + λ_e θ̄ ofsetlerine dokunur.

## 5. Cihazda çalışma

- Paket `params.json`'a `latent` bloğu: b (E), Λ (E×K), Γ (K×P), σ², s_λ. K = 3, E ≈ 150 → ~600 sayı (~10 KB).
- Kullanıcı vektörü cihazda kestirilir: θ̂ = (ΛₒᵀΛₒ/σ² + I)⁻¹ (Λₒᵀ(y − bₒ)/σ² + Γx); K×K (3×3) çözüm, mikro saniyeler. Belirsizlik aynı matrisin tersinden (güven rozeti). Ağ veya sunucu gerekmez; gizlilik modeli değişmez (θ cihazdan çıkmaz).
- Swift tarafı StrengthKit'te ~100 satır (Accelerate/simd gerekmez, 3×3 Cholesky). Altın vektörlerle (1e-4) eşlik aynı yolla test edilir.

## 6. Boy ve Core AI

- Boy prototipte zaten kovaryat (x'in 4. bileşeni). Etkisi kilo verildiğinde küçüktür (kaldıraç kolu: uzun kullanıcılar squat/bench'te dezavantajlı, deadlift'te nötr) — modelde hareket başına işaretini λ_e·Γ belirler. Katkı şemasında `height_band` (5 cm) var; tam kovaryat için ek alan gerekmez. Çapa modeli (yarışmacı verisi) boy içermediği için boy yalnızca gizil modelde ve salon kalibrasyonunda kullanılabilir.
- Core ML/Core AI: model küçük doğrusal cebir; bir ağ çerçevesine ihtiyacı yok. Apple'ın Core ML yerine geçen Core AI çerçevesine geçiş bu model için gerekmez; sinirsel bir çapa (P052 aday C) yeniden gündeme gelirse dönüşüm `coremltools` yerine yeni araç zinciriyle yapılmalı ve paket biçimi (`anchor.kind = coreml`) güncellenmeli.

## 7. Sınırlar

- Eşikler sentetik dünyaya koşulludur: gerçek veride yapı K = 3'ten karmaşık, uzmanlaşma daha büyük ve katkıcılar (P094) yanlı olabilir. Bu yüzden etkinleştirme, P094 hattında **gerçek** dışarıda tutulan katkılarla aynı ölçüt yeniden geçildiğinde yapılır; buradaki sayı yalnızca ne zaman denemeye değeceğini söyler.
- Tek ay/tek set katkı biçimi kişi içi gürültüyü küçümseyebilir (bkz. P094 1RM eğrisi notu).
- Seçim yanlılığı (güçlü olduğu hareketi yapma) modellenmedi; gerçek veride gizil modelin üstünlüğü azalabilir.

_Süre: 65 sn; tohumlar [1, 2, 3]; boyutlar [250, 500, 1000, 2500, 5000, 10000, 20000]._
