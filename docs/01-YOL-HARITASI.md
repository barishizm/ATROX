# 01 — Yol Haritası

104 adım, 12 faz. Süreler tek geliştirici + Claude Code için **kaba tahmindir**; ölçülmüş değildir.

## Faz özeti

| Faz | Ad | Adımlar | Tahmini süre | Çıkış kriteri |
|---|---|---|---|---|
| 0 | Kurulum ve temeller | P001–P008 | 3–4 gün | Boş uygulama simülatörde açılıyor, CI yeşil |
| 1 | Backend temeli ve kimlik | P009–P016 | 4–5 gün | Apple/Google/e-posta ile giriş çalışıyor, RLS testleri geçiyor |
| 2 | Onboarding ve profil | P017–P023 | 4–5 gün | Yeni kullanıcı 2 dakikada profilini tamamlıyor |
| 3 | Hareket kataloğu | P024–P031 | 5–6 gün | 800+ hareket TR/EN aranabiliyor, kas haritası çalışıyor |
| 4 | Antrenman takibi | P032–P045 | 10–12 gün | Çevrimdışı antrenman kaydı, Live Activity, senkronizasyon |
| 5 | ML: veri ve model | P046–P063 | 12–15 gün | Model yarışması raporu, imzalı model paketi, Swift eşliği |
| 6 | Skor ve analiz arayüzü | P064–P071 | 6–7 gün | Hareket/kas/genel skor ve içgörüler ekranda |
| 7 | AI Koç | P072–P083 | 9–11 gün | Koç veriyi okuyor, program öneriyor, değerlendirme seti geçiyor |
| 8 | Sosyal | P084–P088 | 4–5 gün | Skor kartı paylaşımı ve arkadaş sıralaması |
| 9 | Abonelik | P089–P092 | 3–4 gün | Sandbox'ta satın alma, sunucu doğrulaması, kota |
| 10 | Veri katkısı ve yeniden eğitim | P093–P095 | 3–4 gün | Anonim katkı hattı ve yeniden eğitim betiği |
| 11 | Kalite ve yayın | P096–P104 | 8–10 gün | TestFlight betası, App Store gönderimi |

Toplam: yaklaşık 14–18 hafta (yarı zamanlı çalışmada daha uzun).

## Kilometre taşları

| Taş | Ne zaman | Ne gösterir |
|---|---|---|
| **M1 — İskelet** | Faz 1 sonu | Giriş yapılabilen boş uygulama |
| **M2 — Kullanılabilir takipçi** | Faz 4 sonu | Salonda gerçek antrenman kaydedilebilir (kendi kendine kullanım başlar) |
| **M3 — Skor** | Faz 6 sonu | Ürünün asıl değeri ortaya çıkar; ilk dış testçiler |
| **M4 — Koç** | Faz 7 sonu | Ajan koç çalışır; maliyet ölçülür |
| **M5 — Beta** | Faz 11 ortası | TestFlight genel betası |
| **M6 — Yayın** | Faz 11 sonu | App Store v1.0 |

## Bağımlılık grafiği

```
Faz 0 ─► Faz 1 ─► Faz 2 ─► Faz 3 ─► Faz 4 ─► Faz 6 ─► Faz 7 ─► Faz 8 ─► Faz 9 ─► Faz 11
                                        ▲          ▲
                    Faz 5 (ML) ─────────┴──────────┘         Faz 10 (Faz 5 + Faz 4 senkronu gerekir)
```

**Faz 5 paralel yürütülebilir.** ML hattı (`ml/`) uygulamadan bağımsızdır; P046–P059 Faz 2'den itibaren başka bir
Claude Code oturumunda aynı anda ilerleyebilir. Yalnızca P061–P063 uygulamaya dokunur. Bunu öneririm: model
yarışması en uzun düşünme süresi isteyen iş ve erkenden başlaması skor kalitesini artırır.

## Faz detayları

### Faz 0 — Kurulum ve temeller
Hesaplar, araç zinciri, monorepo, XcodeGen projesi, tasarım sistemi, uygulama kabuğu, yerelleştirme altyapısı, CI.
Bu fazda atılan temel (Swift 6 katı eşzamanlılık, paket sınırları, String Catalog) sonradan değiştirmesi en pahalı şeydir.

### Faz 1 — Backend temeli ve kimlik
Supabase projesi (dev + prod), çekirdek şema, RLS ve test paketi, üç giriş yöntemi. RLS testleri bu fazda yazılır,
çünkü sonradan eklenen her tablo aynı kalıba uyar.

### Faz 2 — Onboarding ve profil
Analiz için gereken veriler (doğum tarihi, cinsiyet, boy, kilo, deneyim, hedef, sıklık, ekipman, kısıtlar), onaylar,
"ilk güç profili" (bildiği en iyi setler → anında skor), HealthKit ön doldurma, hesap silme ve veri dışa aktarma.

### Faz 3 — Hareket kataloğu
free-exercise-db içe aktarma, **skor taksonomisi** (hangi hareket hangi çapaya, hangi yük kuralıyla bağlanır),
Türkçe çeviri, görsel işleme, kas haritası, arama ve detay ekranları. Taksonomi dosyası ML'in de girdisidir.

### Faz 4 — Antrenman takibi
Program oluşturucu, şablonlar, aktif antrenman durum makinesi, hızlı set girişi, dinlenme sayacı, Live Activity,
plaka hesaplayıcı, rekor tespiti, geçmiş, aşamalı yüklenme önerisi, çevrimdışı öncelikli senkronizasyon.

### Faz 5 — ML: veri ve model
OpenPowerlifting hattı → temizleme → değerlendirme koşumu → üç aday model → Optuna → **yarışma raporu** →
1RM modülü → nüfus kalibrasyonu → hareket oranları → birleştirme → gelişim analitiği → dengesizlik →
Core ML dışa aktarımı → Swift uygulaması → model güncelleme altyapısı. Ayrıntı: `docs/03-ML-MODEL.md`.

### Faz 6 — Skor ve analiz arayüzü
Skorların hesaplanıp saklanması, hareket skoru ekranı ("dağılımda buradasın"), kas ısı haritası, genel skor panosu,
gelişim grafikleri, içgörü kartları, haftalık özet, "nasıl hesaplanıyor" ekranı.

### Faz 7 — AI Koç
Edge Function proxy, sağlayıcı katmanı, sistem istemi ve bağlam oluşturucu, okuma araçları, öneri araçları, kota,
bellek, iOS istemcisi, sohbet arayüzü, AI onay ekranı, değerlendirme seti, proaktif özetler. Ayrıntı: `docs/04-AI-KOC.md`.

### Faz 8 — Sosyal
Paylaşılabilir skor kartı, kullanıcı adı ve arkadaşlık şeması, engelle/bildir, sıralama, davet bağlantıları.

### Faz 9 — Abonelik
StoreKit 2, sunucu doğrulaması, ödeme duvarı, ücretsiz kotalar, App Store Connect yapılandırması.

### Faz 10 — Veri katkısı ve yeniden eğitim
Anonim katkı hattı, k-anonimlik, yeniden eğitim betiği ve kalite kapıları, v2 gizil faktör modeli araştırma izi.

### Faz 11 — Kalite ve yayın
Widget'lar, erişilebilirlik, performans, test sertleştirme, analitik, gizlilik/hukuk, güvenlik incelemesi,
mağaza varlıkları, TestFlight ve yayın.

## v1.0 sonrası (yol haritası dışı, sıralı öneri)

1. **v1.1** — Apple Watch uygulaması (bilekten set girişi, nabız).
2. **v1.2** — Gizil faktör modeli v2 (uygulama verisiyle öğrenilen hareket oranları, hiç yapılmamış hareket için ağırlık tahmini).
3. **v1.3** — APNs push, arkadaş etkinlik akışı.
4. **v2.0** — Core AI'a geçiş, boyun tam kovaryat olduğu model, kardiyo skoru.

## Çalışma düzeni önerisi

- Her oturumda **tek prompt**. Bağlam temiz kalır, commit'ler küçük olur.
- Faz sonlarında "çıkış kriteri" maddesini elle doğrula; geçmeden sonraki faza başlama.
- Faz 4 bittiğinde uygulamayı kendi antrenmanlarında kullanmaya başla. En iyi hata raporu kendi kullanımındır.
- Faz 5'i ikinci bir oturumda paralel yürüt.
