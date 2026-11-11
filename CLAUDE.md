# GymAnalyzer (çalışma adı) — Claude için proje rehberi

iOS için yapay zekâ destekli antrenman takip ve kuvvet analiz uygulaması. Kullanıcı antrenmanını kaydeder;
kendi eğittiğimiz model her hareket için **0–100 Güç Skoru** (aynı cinsiyet/yaş/kilodaki salon kullanıcılarına
göre yüzdelik dilim) üretir; DeepSeek V4.1 Flash tabanlı **AI Spor Koçu** kullanıcının verisini okuyup program önerir.

## Önce bunları oku

| Dosya | İçerik |
|---|---|
| `docs/00-KARARLAR.md` | Kesinleşmiş ürün/teknik kararlar ve araştırma bulguları (değiştirmeden önce kullanıcıya sor) |
| `docs/01-YOL-HARITASI.md` | Fazlar, kilometre taşları, çıkış kriterleri |
| `docs/02-MIMARI.md` | Uygulama mimarisi, veri modeli, senkronizasyon, backend şeması, güvenlik |
| `docs/03-ML-MODEL.md` | Güç Skoru modelinin tüm matematiği ve eğitim hattı |
| `docs/04-AI-KOC.md` | AI Koç mimarisi, araçlar, güvenlik, maliyet |
| `docs/prompts/` | P001–P104 adım adım prompt listesi |
| `docs/ILERLEME.md` | Hangi adımın bittiğini gösteren kontrol listesi |

## Bir prompt adımını çalıştırırken uyulacak kurallar

1. İlgili prompt'ta adı geçen doküman bölümlerini oku; `docs/ILERLEME.md` içinden bağımlı adımların bittiğini doğrula.
2. Kapsamın dışına çıkma. Fark ettiğin ek işleri `docs/ILERLEME.md` sonundaki "Ertelenenler" listesine yaz.
3. Her adım test ile biter: yeni mantık için birim testi yaz, ilgili test komutunu çalıştır, çıktıyı raporla.
4. Adım bitince `docs/ILERLEME.md` içindeki kutuyu işaretle ve tek bir anlamlı commit at (`P0xx: <özet>`).
5. Bir karar `docs/00-KARARLAR.md` ile çelişiyorsa uygulamadan önce kullanıcıya sor.
6. `[MANUEL]` etiketli adımları kullanıcı yapar; sen yalnızca adım adım yönlendir ve sonucu doğrula.

## Kesinleşmiş teknik kararlar (özet)

- **Platform:** Native iOS, Swift 6 (strict concurrency), SwiftUI, SwiftData. Minimum iOS 26. Xcode 27.
- **Proje üretimi:** XcodeGen (`ios/project.yml`). `.xcodeproj` commit edilmez.
- **Backend:** Supabase (Postgres + Auth + Edge Functions + Storage). Tüm tablolarda RLS zorunlu.
- **Giriş:** Sign in with Apple + Google + e-posta.
- **ML:** Python (`ml/`) ile eğitim → Core ML + `params.json` model paketi → cihazda çıkarım (`StrengthKit`).
  Model paketi Supabase Storage'dan imzalı (Ed25519) olarak güncellenir.
- **AI Koç:** Supabase Edge Function proxy → OpenRouter `deepseek/deepseek-v4.1-flash` (birincil),
  resmi DeepSeek API `deepseek-flash` (yedek). API anahtarı asla uygulamaya girmez.
- **Gelir:** Freemium, StoreKit 2 aboneliği. **Diller:** Türkçe + İngilizce (String Catalog).
- **Tasarım:** Koyu, atletik, veri odaklı; tek vurgu rengi; Liquid Glass ile uyumlu.

## Depo yapısı (hedef)

```
ios/                 XcodeGen projesi, uygulama hedefi ve yerel Swift paketleri
  App/               Uygulama hedefi (Features/*, kompozisyon kökü)
  Packages/
    StrengthKit/     Saf Swift skor motoru (UI yok, Linux'ta da test edilir)
    DataKit/         SwiftData modelleri, depolar, senkronizasyon motoru
    DesignSystem/    Renk/tipografi belirteçleri ve ortak bileşenler
    CoachKit/        SSE istemcisi ve koç modelleri
  Widgets/           WidgetKit + Live Activity hedefi
ml/                  Python eğitim hattı (uv), raporlar, model kartı
supabase/            migrations/, functions/, seed/, tests/
tools/               Katalog ve görsel işleme betikleri
docs/                Tasarım dokümanları ve prompt listesi
```

## Komutlar (ilgili adımlar tamamlandıkça geçerli olur)

```bash
cd ios && xcodegen generate                      # projeyi üret
xcodebuild test -project ios/GymAnalyzer.xcodeproj -scheme GymAnalyzer \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # uygulama testleri
swift test --package-path ios/Packages/StrengthKit       # skor motoru testleri
cd ml && uv run pytest                           # ML testleri
supabase db reset && supabase test db            # şema + RLS testleri
deno test supabase/functions/                    # Edge Function testleri
```

## Kod kuralları

- Swift: `@Observable` + `async/await`; `ObservableObject`/Combine yok. Tüm kullanıcı metinleri String Catalog'da.
- Skor mantığı yalnızca `StrengthKit` içinde yaşar; görünümler ve sunucu aynı hesabı tekrar yazmaz.
- Python ↔ Swift sayısal eşliği `ml/golden/*.json` altın vektörleriyle test edilir (tolerans 1e-4).
- Tüm birincil anahtarlar istemcide üretilen UUID'dir; silme işlemleri yumuşak silmedir (`deleted_at`).
- Gizli anahtarlar: yalnızca Supabase Edge Function secrets. Depoya anahtar girmez.
- Ağırlıklar veritabanında her zaman **kg**, uzunluklar **cm** saklanır; birim dönüşümü yalnızca gösterimde yapılır.
