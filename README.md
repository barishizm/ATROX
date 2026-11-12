# ATROX

iOS için yapay zekâ destekli antrenman takip ve kuvvet analiz uygulaması.

- **Güç Skoru:** Kendi eğittiğimiz model, her hareket için aynı cinsiyet/yaş/kilodaki salon kullanıcılarına göre
  0–100 yüzdelik skor üretir; kas grubu ısı haritası, genel skor, gelişim hızı ve dengesizlik analiziyle birlikte.
- **AI Spor Koçu:** DeepSeek V4.1 Flash tabanlı ajan; verini okur, program önerir, onayınla uygular.
- **Antrenman takibi:** Çevrimdışı öncelikli hızlı set girişi, dinlenme sayacı, Live Activity, HealthKit.

## Durum

Planlama tamamlandı; geliştirme [`docs/prompts/`](docs/prompts/README.md) içindeki 104 adımla ilerliyor.
Güncel durum: [`docs/ILERLEME.md`](docs/ILERLEME.md).

## Depo yapısı

| Dizin | İçerik |
|---|---|
| [`ios/`](ios/README.md) | XcodeGen projesi, uygulama hedefi, yerel Swift paketleri, widget'lar |
| [`ml/`](ml/README.md) | Güç Skoru modeli eğitim hattı (Python, uv) |
| [`supabase/`](supabase/README.md) | Şema göçleri, RLS, Edge Functions, tohum verisi, testler |
| [`tools/`](tools/README.md) | Katalog ve görsel işleme betikleri |
| [`docs/`](docs/README.md) | Tasarım dokümanları ve prompt listesi |

## Hızlı başlangıç

Gereksinimler: macOS, Xcode 27, Homebrew ile `xcodegen`, `swiftlint`, `swiftformat`, `uv`, `deno`, `supabase`.
Hesap ve anahtar kurulumu için [`docs/KURULUM.md`](docs/KURULUM.md).

```bash
# iOS projesini üret (P003'ten sonra)
cd ios && xcodegen generate

# Testler (ilgili adımlar tamamlandıkça geçerli olur)
swift test --package-path ios/Packages/StrengthKit
cd ml && uv run pytest
supabase db reset && supabase test db
deno test supabase/functions/

# Biçim ve lint
swiftformat ios && swiftlint
```

Gizli anahtarlar depoya girmez: `.env*` ve `Secrets.xcconfig` git dışıdır.

## Dokümanlar

| Dosya | İçerik |
|---|---|
| [`docs/00-KARARLAR.md`](docs/00-KARARLAR.md) | Kesinleşmiş kararlar, araştırma bulguları, riskler, kaynaklar |
| [`docs/01-YOL-HARITASI.md`](docs/01-YOL-HARITASI.md) | 12 faz, kilometre taşları, bağımlılıklar |
| [`docs/02-MIMARI.md`](docs/02-MIMARI.md) | Uygulama, veri modeli, senkronizasyon, backend, güvenlik |
| [`docs/03-ML-MODEL.md`](docs/03-ML-MODEL.md) | Güç Skoru modelinin tasarımı ve eğitim hattı |
| [`docs/04-AI-KOC.md`](docs/04-AI-KOC.md) | AI Koç mimarisi, araçlar, güvenlik, maliyet |
| [`docs/KURULUM.md`](docs/KURULUM.md) | Hesaplar ve anahtar saklama tablosu |
| [`docs/prompts/`](docs/prompts/README.md) | P001–P104 prompt listesi ve kullanım kılavuzu |
| [`docs/ILERLEME.md`](docs/ILERLEME.md) | Adım adım ilerleme kontrol listesi |

## Teknoloji

Swift 6 · SwiftUI · SwiftData · iOS 26+ · XcodeGen · Supabase (Postgres, Auth, Edge Functions, Storage) ·
Python (PyTorch, LightGBM, Optuna, coremltools) · Core ML · StoreKit 2 · HealthKit · ActivityKit

## Lisans

Bkz. [`LICENSE`](LICENSE).
