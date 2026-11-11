# GymAnalyzer (çalışma adı)

iOS için yapay zekâ destekli antrenman takip ve kuvvet analiz uygulaması.

- **Güç Skoru:** Kendi eğittiğimiz model, her hareket için aynı cinsiyet/yaş/kilodaki salon kullanıcılarına göre
  0–100 yüzdelik skor üretir; kas grubu ısı haritası, genel skor, gelişim hızı ve dengesizlik analiziyle birlikte.
- **AI Spor Koçu:** DeepSeek V4.1 Flash tabanlı ajan; verini okur, program önerir, onayınla uygular.
- **Antrenman takibi:** Çevrimdışı öncelikli hızlı set girişi, dinlenme sayacı, Live Activity, HealthKit.

## Durum

Planlama tamamlandı; uygulama geliştirmesi `docs/prompts/` içindeki 104 adımla ilerleyecek.

## Dokümanlar

| Dosya | İçerik |
|---|---|
| [`docs/00-KARARLAR.md`](docs/00-KARARLAR.md) | Kesinleşmiş kararlar, araştırma bulguları, riskler, kaynaklar |
| [`docs/01-YOL-HARITASI.md`](docs/01-YOL-HARITASI.md) | 12 faz, kilometre taşları, bağımlılıklar |
| [`docs/02-MIMARI.md`](docs/02-MIMARI.md) | Uygulama, veri modeli, senkronizasyon, backend, güvenlik |
| [`docs/03-ML-MODEL.md`](docs/03-ML-MODEL.md) | Güç Skoru modelinin tasarımı ve eğitim hattı |
| [`docs/04-AI-KOC.md`](docs/04-AI-KOC.md) | AI Koç mimarisi, araçlar, güvenlik, maliyet |
| [`docs/prompts/`](docs/prompts/README.md) | P001–P104 prompt listesi ve kullanım kılavuzu |
| [`docs/ILERLEME.md`](docs/ILERLEME.md) | Adım adım ilerleme kontrol listesi |

## Teknoloji

Swift 6 · SwiftUI · SwiftData · iOS 26+ · XcodeGen · Supabase (Postgres, Auth, Edge Functions, Storage) ·
Python (PyTorch, LightGBM, Optuna, coremltools) · Core ML · StoreKit 2 · HealthKit · ActivityKit

## Başlarken

`docs/prompts/README.md` dosyasını oku, ardından Mac'te Claude Code ile **P001**'den başla.

## Lisans

Bkz. [`LICENSE`](LICENSE).
