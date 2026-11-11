# Prompt Listesi — Kullanım Kılavuzu

104 adım, dört dosya:

| Dosya | Fazlar | Adımlar |
|---|---|---|
| [`01-temel-backend-onboarding.md`](01-temel-backend-onboarding.md) | 0, 1, 2 | P001–P023 |
| [`02-katalog-antrenman.md`](02-katalog-antrenman.md) | 3, 4 | P024–P045 |
| [`03-ml-skor.md`](03-ml-skor.md) | 5, 6 | P046–P071 |
| [`04-koc-sosyal-abonelik-yayin.md`](04-koc-sosyal-abonelik-yayin.md) | 7, 8, 9, 10, 11 | P072–P104 |

## Nasıl kullanılır

1. Mac'te depo kökünde Claude Code'u aç. `CLAUDE.md` otomatik yüklenir; ortak kurallar oradadır.
2. Sıradaki adımın kod bloğunu **olduğu gibi** yapıştır. Her oturumda tek adım çalıştır, sonra `/clear`.
3. Claude işi bitirince "Kabul" satırındaki maddeleri kendin doğrula.
4. `docs/ILERLEME.md` içinde kutunun işaretlendiğini ve commit atıldığını kontrol et.

## Etiketler

- `[MANUEL]` — Senin yapman gereken iş (hesap açma, panel ayarı, anahtar üretme). Claude adım adım yönlendirir.
- `[ARAŞTIRMA]` — Çıktısı kod değil, karar ve rapor olan adım. Sonucu okuyup onaylamadan devam etme.
- `[PARALEL]` — Ana akıştan bağımsız; ikinci bir oturumda aynı anda yürütülebilir.

## Bir adım takılırsa

- Derleme/test hatası: hatayı olduğu gibi yapıştır, "kök nedeni bul ve düzelt" de. Testi devre dışı bıraktırma.
- Adım çok büyük geldiyse: "Bu adımı 2–3 alt adıma böl, ilkini yap" de.
- Bir karar `docs/00-KARARLAR.md` ile çelişiyorsa: önce dokümanı güncelle, sonra kodu.

## Prompt biçimi

Her prompt şu varsayımla yazıldı: Claude `CLAUDE.md`'yi ve prompt'ta adı geçen doküman bölümünü okur, işi yapar,
test yazar ve çalıştırır, `docs/ILERLEME.md`'yi günceller, `P0xx: <özet>` biçiminde commit atar.
Bu kurallar her prompt'ta tekrar edilmez.
