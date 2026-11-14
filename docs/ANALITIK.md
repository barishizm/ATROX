# ATROX — Analitik ve gözlemlenebilirlik (P100)

Durum: **olay sözlüğü onay bekliyor.** Onaylanmadan hiçbir ekrana olay çağrısı eklenmedi; altyapı hazır.

## İlkeler

- Olaylar kimlik toplamaz: kullanıcı kimliği, e-posta, cihaz tanıtıcısı gönderilmez (TelemetryDeck kimliksiz çalışır).
- Olaylarda **kişisel veri, ağırlık, skor değeri, mesaj içeriği yok**; yalnızca sayım ve kategori. Bu kural tür düzeyinde
  zorlanır: `AnalyticsEvent` (DataKit) kapalı bir enum'dur; serbest metin veya sayı alan bir durum yoktur.
- Kapatma anahtarı: Ayarlar → Gizlilik → "Anonim kullanım istatistiklerini paylaş" (varsayılan açık). Kapalıyken hiçbir olay
  gönderilmez, ilk-açılış kaydı da tutulmaz.
- `TELEMETRYDECK_APP_ID` boşsa (yerel derleme, UI testleri) olaylar hiçbir yere gitmez.

## Olay sözlüğü

| Olay | Parametre (kapalı küme) | Ne zaman | Sıklık |
|---|---|---|---|
| `atrox.funnel.signUpCompleted` | `method`: apple · google · email | Kayıt tamamlanınca | kurulum başına 1 |
| `atrox.funnel.onboardingCompleted` | — | Onboarding bitince | kurulum başına 1 |
| `atrox.funnel.firstWorkoutFinished` | — | İlk antrenman bitince | kurulum başına 1 |
| `atrox.funnel.firstScoreViewed` | — | İlk Güç Skoru görülünce | kurulum başına 1 |
| `atrox.funnel.day7Return` | — | İlk açılıştan ≥7 gün sonraki ilk açılış | kurulum başına 1 |
| `atrox.coach.messageSent` | — | Koça mesaj gönderilince | her seferinde |
| `atrox.coach.suggestionDecided` | `decision`: applied · rejected | Öneri uygulanınca/reddedilince | her seferinde |
| `atrox.share.completed` | `target`: instagramStories · shareSheet · saveImage | Paylaşım tamamlanınca | her seferinde |
| `atrox.scores.referenceGroupChanged` | `group`: gym · general · competitor | Referans grubu değişince | her seferinde |
| `atrox.revenue.paywallViewed` | `source`: coach · scores · history · settings · onboarding · other | Ödeme duvarı görününce | her seferinde |
| `atrox.revenue.trialStarted` | `plan`: monthly · yearly | Deneme başlayınca | her seferinde |
| `atrox.revenue.subscriptionStarted` | `plan`: monthly · yearly | Abonelik başlayınca | her seferinde |

"Kurulum" (install) adımını TelemetryDeck'in kendi ilk-oturum sinyali verir; ayrıca olay yazılmaz.
Huni: kurulum → `signUpCompleted` → `onboardingCompleted` → `firstWorkoutFinished` → `firstScoreViewed` → `day7Return`.

Yeni olay eklemek: `AnalyticsEvent`'e durum ekle, bu tabloya satır ekle, `AnalyticsTests` zaten ad benzersizliğini ve
parametre değerlerinin kapalı enum'lardan geldiğini denetler.

## Çökme ve takılma (MetricKit)

`DiagnosticsCollector` günlük metrik ve tanı paketlerini alır; yalnızca sayıları (`crashes`, `hangs`, `cpu`, `diskWrites`,
anormal ön plan çıkışı) `OSLog` `diagnostics` kategorisine yazar. Çağrı yığını metni veya kimlik kaydedilmez. Ayrıntılı
yığınlar için App Store Connect → Crashes kullanılır.

## Sunucu panoları (SQL)

Migration `schema_22_ops_dashboards` (yalnızca service role okur; mesaj içeriği içermez):

| Soru | Nerede |
|---|---|
| Günlük aktif koç kullanıcıları | `ops_coach_daily.active_users` |
| Mesaj başına maliyet | `ops_coach_daily.cost_usd_per_message` |
| Sağlayıcı hata oranı (error + timeout) | `ops_coach_daily.provider_error_rate` |
| Kota aşım oranı | `ops_coach_daily.quota_hit_rate` |
| Model sürümü dağılımı | `ops_coach_model_mix` (gün × sağlayıcı × model) |

```sql
select * from public.ops_coach_daily order by day desc limit 14;
select * from public.ops_coach_model_mix where day >= current_date - 7 order by day desc, requests desc;
```

## Uyarılar

`select * from public.ops_alerts();` eşik aşan her uyarı için bir satır döner (boş = sağlıklı). Eşikler
`ops_alert_thresholds` tablosunda: günlük LLM harcaması (`daily_cost_usd`, varsayılan 25 USD), son saatte hata oranı
(`error_rate_1h`, varsayılan %15; saatte en az 20 istek varsa). Edge Function hata oranı `coach_usage.status` üzerinden
ölçülür (tüm koç Edge Function çağrıları oraya yazar).

**[MANUEL]**
1. TelemetryDeck'te uygulama oluştur, App ID'yi `ios/Config/Release.xcconfig` (ve Staging) içine `TELEMETRYDECK_APP_ID` olarak yaz.
2. Zamanlama: Supabase'de `pg_cron` ile `ops_alerts()` çağrısını saatlik çalıştır ve satır dönerse bildirim gönder
   (ör. küçük bir Edge Function + e-posta/Slack webhook). Bildirim kanalı henüz seçilmedi.
