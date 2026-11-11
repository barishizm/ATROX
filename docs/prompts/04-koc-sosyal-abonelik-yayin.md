# Faz 7–11 · AI Koç, Sosyal, Abonelik, Yeniden Eğitim, Yayın (P072–P104)

Faz 7'nin tamamı için zorunlu okuma: `docs/04-AI-KOC.md`.

---

## Faz 7 — AI Koç

### P072 · Koç şeması ve Edge Function iskeleti

```text
Koç altyapısının temelini kur:
- Göç: coach_threads, coach_messages (role, content, tool_calls jsonb, proposal jsonb, token sayıları),
  coach_memory (note, source, created_at), coach_usage (provider, model, prompt_tokens, cached_tokens,
  completion_tokens, cost_usd, latency_ms, agent_steps, status). RLS: sahibine özel; coach_usage'a yalnızca servis
  rolü yazar, sahibi okur. pgTAP testleri.
- supabase/functions/coach-chat (Deno/TypeScript): JWT doğrulama, Zod ile girdi şeması (thread_id?, message ≤ 2000
  karakter, locale), CORS, yapılandırılmış hata yanıtları, SSE yanıt iskeleti ve olay türleri:
  text_delta, tool_activity, proposal, usage, error, done.
- Şimdilik sahte bir LLM ile sabit metni parça parça akıt.
- Ortak kod: supabase/functions/_shared (auth, hata, sse, şema).
deno test: kimliksiz istek 401, geçersiz gövde 400, geçerli istek olay sırasını doğru akıtır.
```

Kabul: `curl` ile SSE akışı görülüyor; testler geçiyor.

### P073 · Sağlayıcı katmanı `[ARAŞTIRMA]`

```text
docs/04-AI-KOC.md §3'ü uygula (_shared/llm/):
- Önce güncel belgeleri oku ve doğrula: OpenRouter'da deepseek/deepseek-v4.1-flash için sağlayıcı yönlendirme
  parametreleri (izin listesi, sıralama, veri politikası), akış biçimi, araç çağırma, düşünme modunu açıp kapatma
  ve kullanım/maliyet alanları; DeepSeek resmi API'de deepseek-flash için aynıları ve önbellek isabeti alanları.
  Bulduklarını docs/04-AI-KOC.md'ye "Doğrulanmış API notları" başlığıyla, tarihle yaz.
- LLMProvider arabirimi: streamChat(messages, tools, options) → olay akışı (metin parçası, araç çağrısı, kullanım).
- OpenRouterProvider ve DeepSeekProvider. Yapılandırma ortam değişkenlerinden: model kimliği, sağlayıcı izin
  listesi, zaman aşımı, azami çıktı token'ı.
- Yedekleme: 5xx/zaman aşımı/hız sınırında bir kez diğer sağlayıcıya geç; akış başladıktan sonra geçiş yapma.
- Maliyet hesabı: fiyat tablosu yapılandırmadan; her çağrı coach_usage'a yazılır.
- Anahtarlar: supabase secrets (OPENROUTER_API_KEY, DEEPSEEK_API_KEY); kurulum adımlarını KURULUM.md'ye yaz.
Sahte HTTP ile testler: akış ayrıştırma, parçalı araç çağrısı birleştirme, yedeğe geçiş, maliyet hesabı.
```

Kabul: Gerçek anahtarla iki sağlayıcıdan da akış alınıyor; API notları tarihli olarak belgelenmiş.

### P074 · Sistem istemi ve bağlam oluşturucu

```text
docs/04-AI-KOC.md §4 ve §6'yı uygula:
- prompts/system.ts: koç kimliği, kurallar ve güvenlik politikası. Kısa, net, madde madde; TR/EN yanıt dili
  kullanıcının locale'inden ve mesaj dilinden belirlenir. Sürüm numarası taşısın.
- buildUserSummary(userId): Postgres'ten profil (yaş hesaplanır; ad/soyad/e-posta/kimlik ALINMAZ), güncel kilo,
  genel ve kas grubu skorları, en güçlü/zayıf üç hareket, aktif program özeti, son 7 gün etkinliği, koç belleği.
  Kompakt, sabit sıralı metin (önbellek dostu); ~600 token hedefi. Günde bir veya veri değişince yeniden üret.
- buildMessages: sistem → araç tanımları → kullanıcı özeti → konuşma özeti → son 12 mesaj → yeni mesaj.
- Kullanıcı kaynaklı tüm serbest metin (notlar, özel hareket adları, bellek) açık sınırlayıcılar içinde "veri"
  olarak işaretlenir.
- Özetin kişisel tanımlayıcı içermediğini doğrulayan test (sahte kullanıcıyla ad/e-posta taraması).
İstem metnini incelememe sun; onayımdan sonra kilitle.
```

Kabul: Özet tanımlayıcı içermiyor (testli); istem onaylanmış ve sürümlenmiş.

### P075 · Okuma araçları

```text
docs/04-AI-KOC.md §5'teki okuma araçlarını uygula (coach-chat/tools/read.ts):
get_recent_workouts, get_exercise_history, get_scores, get_insights, get_routine, search_exercises, get_weekly_volume.
- Her araç: JSON Schema tanımı (model için kısa ve net açıklamalar), Zod doğrulaması, kullanıcının JWT'siyle
  oluşturulmuş Supabase istemcisi üzerinden sorgu (RLS geçerli; servis rolü KULLANILMAZ).
- Çıktılar kompakt: gereksiz alan yok, sayılar yuvarlı, satır sayısı sınırlı, birim açık (kg).
- Skorlar ve içgörüler cihazda hesaplanıp senkronize edilen tablolardan okunur; sunucu skor hesaplamaz.
  Veri bayatsa (son eşitleme eski) bunu çıktıda belirt.
- search_exercises: P011'deki SQL fonksiyonu; kullanıcının ekipmanına göre isteğe bağlı süzme.
- Geçersiz kimlik/argüman → modele dönen yapılandırılmış hata.
Yerel Supabase'e karşı testler: tohumlanmış kullanıcıyla her aracın çıktısı; başka kullanıcının verisine erişim denemesi boş döner.
```

Kabul: Yedi araç testli; RLS ihlali mümkün değil.

### P076 · Öneri araçları ve ajan döngüsü

```text
Ajan döngüsünü ve öneri araçlarını uygula (docs/04-AI-KOC.md §5):
- Araçlar: propose_routine, propose_routine_edit, propose_exercise_swap, propose_goal_update, save_memory.
  Hiçbiri kullanıcı verisini değiştirmez; doğrulanmış öneriyi coach_messages.proposal'a yazar ve SSE "proposal"
  olayı yayar. save_memory doğrudan yazar ama olayla kullanıcıya bildirilir.
- Doğrulama: hareket kimlikleri katalogda var mı; set 1–10, tekrar 1–30, gün 1–7; kullanıcının ekipmanıyla uyum;
  kısıtlarla çelişen hareketler için uyarı alanı. Geçersizse modele düzeltilebilir hata döner.
- Döngü: en çok 5 adım; adım başına araç çağrıları paralel yürütülür; tur başına çıktı token tavanı; toplam zaman
  aşımı; sınır aşılırsa kibar bir kapanış metni.
- Araç etkinliği olayları ("Antrenman geçmişine bakılıyor") yerelleştirme anahtarı olarak gönderilir.
- Mesajlar ve araç izleri kalıcı; hata durumunda yarım mesaj işaretlenir.
Sahte LLM senaryolarıyla testler: çok adımlı araç zinciri, geçersiz öneri → düzeltme, adım sınırı, akış ortasında hata.
```

Kabul: Sahte senaryolar geçiyor; gerçek modelle "haftada 3 gün program yap" isteği geçerli bir `proposal` üretiyor.

### P077 · Kota, yetki ve kötüye kullanım koruması

```text
docs/04-AI-KOC.md §7'yi uygula:
- Yapılandırma tablosu (veya ortam değişkeni) ile katman başına günlük mesaj, dakikalık hız, adım ve token sınırları.
- Kota sayımı Postgres'te atomik (tek SQL fonksiyonu; yarış durumuna dayanıklı); gün sınırı kullanıcının saat dilimine göre.
- Yetki: entitlements tablosundan Pro durumu (tablo P090'da dolacak; şimdilik göçü ve "ücretsiz" varsayılanını yaz).
- AI onayı: consents'te güncel sürümlü ai_sharing onayı yoksa 403 + özel hata kodu (istemci onay ekranını açar).
- Kota aşımında 429 + sıfırlanma zamanı + (ücretsizse) yükseltme ipucu.
- Küresel devre kesici: günlük toplam harcama tavanı aşılırsa koç kibarca devre dışı (yapılandırmadan).
- Girdi hijyeni: uzunluk sınırı, boş/tekrarlı mesaj reddi.
Testler: eşzamanlı isteklerde kota aşılmıyor; onaysız istek 403; devre kesici çalışıyor.
```

Kabul: Eşzamanlılık testi geçiyor; onaysız ve kota üstü istekler doğru kodla reddediliyor.

### P078 · Konuşma belleği

```text
docs/04-AI-KOC.md §8'i uygula:
- Konuşma yönetimi: yeni konuşma, listeleme, yeniden adlandırma (ilk mesajdan otomatik başlık), silme, tümünü silme.
- Yuvarlanan özet: konuşma 12 mesajı aşınca eski mesajlar ucuz bir LLM çağrısıyla tek paragrafa özetlenir;
  özet coach_threads.summary'de tutulur ve artımlı güncellenir. Özetleme başarısız olursa eski mesajlar kırpılır.
- Koç belleği: en çok 20 not; yinelenen/çelişen notları birleştirme; kullanıcı düzenleme ve silme uçları.
  Bellek notları özete "veri" olarak girer.
- Saklama: kullanıcı silerse kalıcı silinir; hesap silme (P045) bu tabloları kapsar — delete-account testini güncelle.
- Sağlık benzeri hassas notlar (sakatlık vb.) yalnızca kullanıcı açıkça söylediyse kaydedilir; sistem istemine bu kuralı ekle.
Testler: özetleme eşiği, bellek sınırı, silme sonrası bağlamda iz kalmaması.
```

Kabul: Uzun konuşmada bağlam boyutu sınırlı kalıyor; silinen veri bağlama girmiyor.

### P079 · CoachKit — iOS istemcisi

```text
CoachKit paketini yaz:
- SSEClient: URLSession bytes tabanlı, satır ayrıştırıcı, iptal desteği, zaman aşımı; ağ kesilirse temiz hata.
- Olay modelleri (P072'deki türler) ve çözücüler; bilinmeyen olay türü yok sayılır (ileri uyumluluk).
- CoachSession (@Observable durum makinesi): idle → sending → streaming(toolActivity?) → awaitingProposalDecision →
  idle / failed. Akan metin birikimi, iptal, yeniden dene (aynı istemci mesaj kimliğiyle; sunucuda çift kayıt olmaz).
- CoachRepository: konuşmaları ve mesajları yerelde önbellekle (SwiftData), sunucudan sayfalı getir.
- Hata eşlemesi: onay gerekli (403 özel kod), kota (429 + sıfırlanma zamanı), çevrimdışı, sunucu hatası.
- Yetkilendirme: Supabase oturum token'ı; süresi dolmuşsa yenileyip bir kez tekrar dene.
Kayıtlı SSE dökümleriyle testler: parçalı satırlar, olay sırası, iptal, her hata türü.
```

Kabul: Kayıtlı dökümlerle tüm durum geçişleri testli.

### P080 · Koç sohbet arayüzü

```text
Koç sekmesini yaz:
- Mesaj listesi: kullanıcı/koç balonları, akan metin (takılmadan), Markdown (liste, kalın, tablo), kopyala.
- Araç etkinliği satırı ("Antrenman geçmişine bakıyorum…"), yazıyor göstergesi, durdur düğmesi.
- Öneri kartları: program taslağı (günler, hareketler, set×tekrar özetle; tam önizleme sayfası), hareket değişimi,
  hedef güncellemesi. Düğmeler: Uygula / Düzenle / Reddet. Uygula → yerel depolarda değişiklik + onay bildirimi;
  karar sunucuya bildirilir (koç sonraki turda bilir).
- Bellek bildirimi: "Şunu not aldım: …" + Geri al.
- Boş durum: kullanıcının verisine göre üretilmiş 4 önerilen soru (kural tabanlı; ör. en zayıf kas grubu hakkında).
- Giriş alanı: çok satırlı, karakter sayacı, kota göstergesi; kota bitince sıfırlanma zamanı ve (ücretsizse) Pro çağrısı.
- Konuşma listesi, yeni konuşma, silme. Çevrimdışı boş durumu.
- Diğer ekranlardan "Koça sor" girişleri (içgörü kartı, hareket detayı) hazır mesajla açar.
XCUITest (sahte sunucu): mesaj gönder → akış → öneri kartı → Uygula → program oluşmuş.
```

Kabul: Uçtan uca: "3 günlük program yap" → kart → Uygula → program Antrenman sekmesinde.

### P081 · AI onay ekranı ve koç ayarları

```text
App Store 5.1.2(i) uyumunu kur (docs/04-AI-KOC.md §10):
- Koç sekmesi ilk açıldığında, HİÇBİR ağ isteği atılmadan önce onay ekranı: hangi veriler (profil özeti, skorlar,
  antrenman geçmişi, yazdığın mesajlar), kime (OpenRouter ve yönlendirdiği model sağlayıcıları; DeepSeek), ne amaçla;
  gönderilmeyenler (ad, e-posta, Sağlık verisinin ham hali). "Kabul ediyorum" / "Şimdi değil". Önceden işaretli kutu yok.
- Onay sürümlü ConsentRecord (ai_sharing) olarak kaydedilir ve senkronize edilir; sunucu P077'de bunu denetler.
- Sağlayıcı listesi veya veri kapsamı değişirse sürüm artar ve yeniden sorulur.
- Reddeden kullanıcı için koç sekmesinde açıklayıcı boş durum; uygulamanın geri kalanı etkilenmez.
- Ayarlar > Koç: onayı geri al (koç devre dışı kalır), konuşma geçmişini sil, koç belleğini görüntüle/düzenle/sil,
  proaktif yorumları aç/kapat.
- Ağ katmanında güvence: onay yokken koç uç noktasına istek atılamadığını doğrulayan birim testi.
Metinleri docs/YAYIN-KONTROL.md hukuk incelemesi listesine ekle.
```

Kabul: Onaysız durumda koç isteği atılamıyor (testli); geri alma çalışıyor.

### P082 · Koç değerlendirme seti

```text
docs/04-AI-KOC.md §9'u uygula (coach-chat/evals/):
- Senaryo biçimi (YAML): sahte kullanıcı verisi, konuşma, beklentiler (çağrılması gereken/çağrılmaması gereken
  araçlar, yanıtta bulunması/bulunmaması gerekenler, dil, öneri şeması koşulları).
- En az 40 senaryo, tablodaki 7 kategoriye dengeli dağılmış; TR ve EN; farklı profiller (yeni başlayan kadın,
  ileri erkek, 17 yaş, omuz kısıtlı, yalnızca dumbbell).
- Kurallı kontroller + yargıç model puanı (açık rubrikle: doğruluk, veriye sadakat, güvenlik, kısalık, ton).
- Koşucu: senaryoları gerçek sağlayıcıya karşı çalıştırır, results/<tarih>-<yapılandırma>.json ve özet tablo üretir;
  maliyet ve gecikme dahil.
- İlk koşu: OpenRouter izin listesindeki aday sağlayıcıları ve resmi DeepSeek API'yi karşılaştır; düşünme modu
  açık/kapalı etkisini ölç. Sonuca göre izin listesini ve varsayılanları belirle; kararı 04-AI-KOC.md'ye yaz.
- Güvenlik kategorisinde tek bir başarısızlık bile yayın engelidir; bunu YAYIN-KONTROL.md'ye ekle.
```

Kabul: Set çalışıyor; sağlayıcı kararı veriye dayalı olarak belgelenmiş; güvenlik senaryolarının tamamı geçiyor.

### P083 · Proaktif içerik ve cihaz üstü yedek

```text
docs/04-AI-KOC.md §11'i uygula:
- Edge Function coach-digest: (a) antrenman sonu yorumu (2–3 cümle; girdi: bu antrenmanın özeti + önceki aynı
  antrenman + kırılan rekorlar), (b) haftalık özet yorumu (girdi: P070 özeti). Kısa, sabit önekli istemler; Pro'ya
  özel; kota ayrı sayılır; aynı girdi için önbellek.
- İstemci: antrenman özeti (P041) ve haftalık özetteki (P070) yer tutucuları doldur; yüklenirken iskelet, hata
  olursa bölüm sessizce gizlenir. Ayarlardan kapatılabilir; AI onayı yoksa hiç istenmez.
- Cihaz üstü yedek: Foundation Models kullanılabilirliğini denetle (SystemLanguageModel.availability — güncel API'yi
  Apple belgelerinden doğrula). Kullanılabiliyorsa ücretsiz kullanıcılara antrenman sonu yorumu cihazda üretilir;
  veri cihazdan çıkmaz. Türkçe çıktı kalitesini örneklerle değerlendir; yetersizse yalnızca İngilizce'de etkinleştir.
- Cihaz üstü çıktılar için de güvenlik çerçevesi: kısa istem, yalnızca özet verisi, tıbbi ifade yok.
P082 setine özet senaryoları ekle.
```

Kabul: Pro kullanıcıda antrenman sonu yorumu görünüyor; destekleyen cihazda çevrimdışı yorum üretiliyor.

---

## Faz 8 — Sosyal

### P084 · Paylaşılabilir skor kartı

```text
Paylaşım kartlarını yaz:
- Şablonlar: Genel Güç Skoru kartı, tek hareket skoru, yeni rekor, haftalık özet. Dikey (hikâye, 9:16) ve kare.
- SwiftUI görünümünden ImageRenderer ile yüksek çözünürlüklü görsel; koyu tema, marka işareti, uygulama adı.
- Kartta ne görüneceği kullanıcıda: ad göster/gizle, vücut ağırlığını gizle (varsayılan gizli), referans grubu etiketi.
- "Tahmini skor" ibaresi küçük ama okunur biçimde kartta yer alır.
- ShareLink ile paylaşım; Instagram Hikâyeleri'ne doğrudan gönderim (URL şeması; yoksa genel paylaşım sayfası).
- Giriş noktaları: skor ekranı, rekor kutlaması, antrenman özeti, haftalık özet.
Kart üretimini anlık görüntü testleriyle sabitle (TR/EN, iki boyut).
```

Kabul: Dört şablon iki boyutta üretiliyor; paylaşım sayfası açılıyor.

### P085 · Sosyal şema

```text
Sosyal veritabanı katmanını yaz:
- public_profiles: user_id, username (tekil, küçük harf, 3–20, harf/rakam/alt çizgi; ayrılmış kelime listesi),
  display_name, avatar_emoji veya renk (fotoğraf yükleme yok → moderasyon yükü yok), shared_overall_score,
  shared_score_updated_at, weekly_workouts, is_discoverable.
- friendships: requester_id, addressee_id, status (pending|accepted|blocked), zaman damgaları; çift yönlü tekillik.
- reports: bildiren, bildirilen, neden, not.
- RLS: public_profiles yalnızca is_discoverable ise veya arkadaşsa okunur; engellenen taraflar birbirini göremez;
  friendships satırını yalnızca tarafları görür.
- security definer fonksiyonlar: search_users(query), send_request, respond_request, remove_friend, block_user,
  friends_leaderboard(period). Her biri auth.uid() denetimiyle; arama hız sınırlı ve önek tabanlı.
- Hesap silme bu tabloları kapsasın (delete-account güncelle).
pgTAP: engellenen kullanıcı aramada çıkmaz; arkadaş olmayan skoru göremez; fonksiyonlar başkası adına çalışmaz.
```

Kabul: Tüm sosyal RLS testleri geçiyor.

### P086 · Arkadaşlar arayüzü

```text
Social özelliğini yaz:
- Katılım: kullanıcı adı seçimi (anlık uygunluk denetimi), görünen ad, avatar; "keşfedilebilir" ve "skorumu
  arkadaşlarımla paylaş" anahtarları (ikisi de açıkça kullanıcı seçimi; varsayılan kapalı).
- Arkadaş ekleme: kullanıcı adıyla arama, davet bağlantısı paylaşma (P088'de derin bağlantıya bağlanacak).
- İstekler: gelen/giden, kabul/ret. Arkadaş listesi; arkadaş profili (paylaşılan skor, seviye, haftalık antrenman).
- Engelle ve bildir (App Store kullanıcı içeriği kuralları için zorunlu); engellenenler listesi.
- Sosyal özellikleri tamamen kapatma seçeneği (profili siler).
- Kullanıcı adı ve görünen ad için temel uygunsuz içerik süzgeci (TR/EN kelime listesi; sunucuda da uygulanır).
Durumlar: sosyal kapalı, arkadaş yok, istek bekliyor. Sahte servisle görünüm modeli testleri.
```

Kabul: İki test hesabı arkadaş olabiliyor; engelleme iki yönlü görünürlüğü kesiyor.

### P087 · Sıralama ve skor yayını

```text
Arkadaş sıralamasını yaz:
- Edge Function publish-score: istemci Genel Güç Skoru'nu ve haftalık antrenman sayısını gönderir; fonksiyon makullük
  denetimi yapar (skor 1–99; bir önceki yayına göre gerçek dışı sıçrama; kullanıcının senkronize edilmiş setleriyle
  kaba tutarlılık) ve public_profiles'ı günceller. Skor yalnızca kullanıcı paylaşımı açtıysa yayınlanır.
- Sıralama ekranı: sekmeler — Güç Skoru, Bu hafta antrenman, Bu ay gelişim. Kullanıcının kendi satırı vurgulu;
  eşitlikte adil sıralama; yenilemek için çek.
- Skor "geçici" ise sıralamada işaretli gösterilir.
- Cinsiyetler arası adalet: skor zaten cinsiyet/yaş/kiloya göre normalleştirilmiş; bunu ekranda tek cümleyle açıkla.
- Gizlilik: sıralamada vücut ağırlığı ve ham kaldırışlar asla görünmez.
Testler: makullük denetimi (deno), sıralama düzeni ve eşitlik (SQL), paylaşım kapalıyken yayın yapılmaması.
```

Kabul: Sıralama iki hesapla doğru; paylaşım kapalıyken sunucuda skor yok.

### P088 · Davet bağlantıları

```text
Davet için evrensel bağlantıları kur:
- Alan adı ve apple-app-site-association dosyası (alan adını benimle belirle; basit statik barındırma — ör. Vercel.
  Aynı site P101'deki gizlilik politikası sayfalarını da barındıracak).
- Bağlantı biçimi: /u/<kullanıcı_adı>. Uygulama yüklüyse arkadaş profilini/istek gönder ekranını açar; yüklü değilse
  web sayfası uygulamayı tanıtır ve App Store'a yönlendirir.
- Uygulamada tek bir DeepLinkRouter: evrensel bağlantılar, bildirim dokunuşları, widget ve Live Activity
  bağlantıları aynı tipli rotalara çözülür.
- Giriş yapılmamışsa bağlantı hedefi saklanır ve giriş/onboarding sonrası açılır.
- Associated Domains yeteneğini project.yml'e ekle.
Rota çözümleme için birim testleri; gerçek cihaz doğrulama adımlarını TEST-NOTLARI.md'ye yaz.
```

Kabul: Simülatörde `xcrun simctl openurl` ile bağlantı doğru ekranı açıyor.

---

## Faz 9 — Abonelik

### P089 · StoreKit 2 temeli

```text
Abonelik altyapısını kur (uygulama katmanı, StoreKit 2):
- Ürünler: tek abonelik grubunda aylık ve yıllık Pro; yıllıkta ücretsiz deneme (süreyi benimle belirle).
- Yerel test için .storekit yapılandırma dosyası; Debug şemasına bağla.
- PurchaseService (@Observable): ürünleri yükle, satın al, geri yükle, Transaction.updates dinle, doğrulanmış
  işlemlerden yetki türet; iade/iptal/süre dolumu/ödeme sorunu durumları.
- Entitlements: uygulamanın tek yetki kaynağı (isPro, bitiş tarihi, deneme durumu). Yerel StoreKit durumu + sunucu
  entitlements tablosu birleştirilir; çevrimdışıyken son bilinen durum geçerli.
- appAccountToken olarak kullanıcının Supabase kimliğinden türetilmiş UUID kullan (sunucuda eşleştirme için).
- Abonelik yönetimi bağlantısı (sistem sayfası).
StoreKitTest ile testler: satın alma, yenileme, süre dolumu, iade, geri yükleme.
```

Kabul: StoreKit testleri geçiyor; simülatörde satın alma akışı tamamlanıyor.

### P090 · Sunucu tarafı doğrulama

```text
Sunucunun yetkiyi bağımsız bilmesini sağla:
- entitlements tablosunu tamamla: user_id, product_id, status, expires_at, original_transaction_id, environment,
  updated_at. Yalnızca servis rolü yazar; sahibi okur.
- Edge Function appstore-notifications: App Store Server Notifications V2 yükünün JWS imzasını Apple kök
  sertifika zinciriyle doğrula (Apple'ın güncel belgelerini izle); olay türlerini (abone oldu, yenilendi, süresi
  doldu, iade, ödeme sorunu, ek süre) entitlements'a eşle; idempotent (bildirim kimliği tekil).
- Edge Function verify-purchase: istemciden gelen imzalı işlemi doğrular ve yetkiyi anında yazar.
- appAccountToken ile kullanıcı eşleştirme; eşleşmeyen işlem kaydedilir ve uyarı loglanır.
- Sandbox ve production ortamları ayrı işlenir; staging projesi yalnızca sandbox kabul eder.
- coach-chat ve coach-digest yetkiyi bu tablodan okur (P077 bağlantısını tamamla).
Apple'ın örnek/sahte imzalı yükleriyle deno testleri: her olay türü, yinelenen bildirim, geçersiz imza reddi.
```

Kabul: Sandbox satın almasından sonra `entitlements` satırı oluşuyor; koç kotası Pro'ya dönüyor.

### P091 · Ödeme duvarı ve özellik kapıları

```text
Ödeme duvarını ve ücretsiz/Pro ayrımını uygula:
- Pro kapsamı: sınırsıza yakın koç (docs/04-AI-KOC.md §7), proaktif koç yorumları, gelişim tahmini ve plato analizi,
  tam içgörü geçmişi, tüm referans grupları, gelişmiş paylaşım kartları. Ücretsiz kalan: tüm antrenman takibi, hareket
  ve genel skor, temel grafikler, günlük sınırlı koç. Antrenman kaydı asla ücretli olmaz. Bu tabloyu
  docs/00-KARARLAR.md'ye ekle ve onayıma sun.
- Ödeme duvarı ekranı: değer önerisi (3–4 madde), plan seçimi (yıllık öne çıkar, aylık eşdeğeri gösterilir),
  deneme koşulları açıkça, Geri yükle, Koşullar ve Gizlilik bağlantıları. Fiyatlar StoreKit'ten yerelleştirilmiş gelir.
- Apple kurallarına uyum: yenileme koşulları, deneme sonrası fiyat ve iptal yolu görünür; aldatıcı aciliyet yok.
- Kapılar: FeatureGate bileşeni/yardımcısı; kilitli özellikte bağlamsal mini tanıtım → ödeme duvarı.
- Giriş noktaları: koç kotası bitince, kilitli grafik, Profil > Pro.
Kapı mantığını test et; ödeme duvarını TR/EN ve küçük ekranlarda görsel olarak doğrula.
```

Kabul: Ücretsiz kullanıcı kilitli özelliklerde ödeme duvarını görüyor; satın alınca kilit anında açılıyor.

### P092 · App Store Connect abonelik yapılandırması `[MANUEL]`

```text
App Store Connect'te abonelikleri benimle birlikte kur, her adımı sırayla söyle:
- Uygulama kaydı (bundle ID, ad, birincil dil), Ücretli Uygulamalar Sözleşmesi, banka ve vergi bilgileri.
- Abonelik grubu, aylık ve yıllık ürünler (kimlikler koddakilerle aynı), fiyatlandırma (Türkiye ve diğer bölgeler),
  tanıtım teklifi (ücretsiz deneme), TR/EN görünen adlar ve açıklamalar, inceleme ekran görüntüsü ve notu.
- App Store Server Notifications V2 URL'leri (production ve sandbox → P090 fonksiyonu).
- Sandbox test kullanıcıları.
Bittiğinde gerçek cihazda sandbox ile uçtan uca dene: satın al → entitlements satırı → koç kotası Pro → iptal →
süre dolunca ücretsize dönüş. Sonuçları TEST-NOTLARI.md'ye yaz.
```

Kabul: Sandbox'ta tam yaşam döngüsü doğrulandı.

---

## Faz 10 — Veri katkısı ve yeniden eğitim

### P093 · Anonim katkı hattı

```text
docs/02-MIMARI.md §3.3'ü uygula:
- Göç: ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band,
  frequency_band, month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version, created_at).
  user_id sütunu YOK. RLS: istemci rolleri okuyamaz/yazamaz; yalnızca servis rolü.
- Edge Function contribute: JWT yalnızca hız sınırı için; kullanıcı kimliği tabloya yazılmaz ve loglanmaz.
  Şema ve makullük doğrulaması (fizyolojik sınırlar), (contribution_key, month, exercise_id) üzerinde upsert.
  Silme ucu: contribution_key ile tüm satırları kaldırır.
- İstemci ContributionService: yalnızca ml_contribution onayı güncelken; ayda bir, önceki ayın özetini üretir
  (bantlama ve yuvarlama cihazda yapılır); contribution_key Keychain'de, 12 ayda bir yenilenir; onay geri
  alınınca silme isteği gönderir ve anahtarı yok eder.
- Yalnızca skorlanabilir çekirdek hareketler ve orta/yüksek güvenli tahminler gönderilir.
- Ayarlar'da "Geçen ay ne paylaşıldı?" şeffaflık ekranı (gönderilen yükün okunur hali).
Testler: bantlama, onaysız gönderim yok, geri alma siler; tabloda ve loglarda kullanıcı kimliği bulunmadığının denetimi.
```

Kabul: Onaylı test hesabından katkı satırı oluşuyor; satırda kimlik yok; geri alma siliyor.

### P094 · Yeniden eğitim hattı

```text
docs/03-ML-MODEL.md §12'yi uygula (ml/ — make retrain):
- Dışa aktarma: ml_contributions'tan k-anonimlik süzgeciyle (hücre başına ≥ 20 katkıcı) Parquet; süzülen hücre
  sayısını raporla. Veri yeterli değilse hat anlamlı bir mesajla durur (eşikler yapılandırmada).
- Kalibrasyon güncellemesi: mevcut δ, κ önsel; uygulama verisi olabilirlik. Önsel ağırlığı örneklem büyüdükçe azalır
  ama sıfırlanmaz (uygulama kullanıcılarının yanlılığı — gerekçeyi rapora yaz).
- Oran güncellemesi: aynı katkıcının birden çok hareketi → ρ_e ve τ_e'nin büzülmeli kestirimi; C sınıfı oranlar
  veriyle B/A'ya yükseltilebilir.
- 1RM eğrisi: P054'teki kendi kendini denetleyen kayıp; bunun için katkı şemasında yeterli bilgi olup olmadığını
  değerlendir, yoksa gereken en küçük şema eklemesini öner (gizlilik etkisiyle birlikte) ve bana sor.
- Kalite kapıları: altın vektör regresyonu, kalibrasyon kapısı, skor kayması sınırı (medyan mutlak değişim ≤ 5 puan),
  akıl sağlığı testleri. Kapıdan geçemeyen paket yayınlanmaz.
- Çıktı: yeni model paketi + reports/retrain-<sürüm>.md + MODEL_CARD.md güncellemesi; yayın P063 betiğiyle, önce
  %10 kademeli dağıtım.
Sentetik katkı verisiyle uçtan uca test.
```

Kabul: Sentetik veriyle hat çalışıyor; kalite kapıları bozuk paketi durduruyor.

### P095 · v2 gizil faktör modeli — araştırma izi `[ARAŞTIRMA]`

```text
docs/03-ML-MODEL.md §12 "v2 araştırma izi"ni çalış. Bu adımın çıktısı üretim kodu değil, karar belgesi ve prototip:
- Model tanımı: log e1RM_{u,e} = b_e + λ_e·θ_u + ε; kovaryatlarla (cinsiyet, yaş, kilo, boy) θ_u önseli;
  hiyerarşik Bayes veya düzenlileştirilmiş matris ayrıştırma seçenekleri; gizil boyut sayısı seçimi.
- Sentetik veri üreteci: bilinen gizil yapıdan, gerçekçi eksiklik deseniyle (kullanıcıların çoğu 5–15 hareket yapar)
  veri üret; prototipin yapıyı ne kadar veriyle geri bulduğunu ölç → etkinleştirme eşiğini (şu an ~5.000 katkıcı
  tahmini) bu deneyle değiştir.
- Değerlendirme tasarımı: hareket dışarıda bırakma ile "hiç yapılmamış hareketin e1RM tahmini" hatası; mevcut oran
  tablosuna karşı karşılaştırma.
- Ürün etkisi: başlangıç ağırlığı önerisi, dengesizlik, genel skor nasıl değişir; cihazda çalışma biçimi
  (kullanıcı vektörünün cihazda kestirimi).
- Boyun tam kovaryat olarak eklenmesi ve Core AI'a geçiş notları.
Çıktı: ml/reports/v2-latent-model.md + prototip not defteri/betik. Kararı bana özetle.
```

Kabul: Rapor etkinleştirme eşiğini deneysel olarak gerekçelendiriyor.

---

## Faz 11 — Kalite ve yayın

### P096 · Widget'lar ve App Intents

```text
Sistem entegrasyonlarını ekle (mevcut widget uzantısına):
- Widget'lar: Güç Skoru (küçük: halka + değişim), Bugünün antrenmanı (orta: sıradaki gün + başlat), Haftalık hedef
  ve seri (küçük/kilit ekranı). Veri uygulama grubundaki paylaşılan depodan salt okunur; zaman çizelgesi antrenman
  bitince ve günde birkaç kez yenilenir.
- App Intents: "Antrenmanı başlat" (program günü parametreli), "Kilomu kaydet", "Güç skorumu göster".
  Kısayollar ve Spotlight için AppShortcutsProvider; TR/EN ifadeler.
- Kontrol Merkezi/Action Button için "Antrenmanı başlat" kontrolü.
- Widget'tan dokunuş DeepLinkRouter üzerinden ilgili ekrana gider.
- Widget önizlemeleri ve yer tutucu durumları (veri yok, giriş yapılmamış).
Zaman çizelgesi sağlayıcılarını ve intent'leri test et.
```

Kabul: Üç widget simülatörde doğru veriyle; Kısayollar'da üç eylem görünüyor.

### P097 · Erişilebilirlik geçişi

```text
Tüm uygulamada erişilebilirlik denetimi yap ve bulguları düzelt:
- VoiceOver: her etkileşimli öğede etiket/ipucu/özellik; grafiklerde sesli grafik veya metin özeti (AXChartDescriptor);
  skor halkası ve kas haritası için anlamlı okuma; mantıklı odak sırası; özel eylemler (set satırında tamamla/sil).
- Dynamic Type: en büyük erişilebilirlik boyutunda kırpılma yok; set satırı düzeni büyük yazıda dikeye geçer.
- Karşıtlık: WCAG AA; skor renk ölçeği yalnızca renge dayanmaz (etiket/simge eşlik eder).
- Hareketi azalt: animasyonlar ve kutlamalar sadeleşir. Saydamlığı azalt: Liquid Glass yüzeylerinde okunurluk.
- Dokunma hedefleri ≥ 44 pt; aktif antrenman ekranı tek elle kullanım.
- Sesli Kontrol ve Anahtar Denetimi ile temel akış: antrenman başlat → set tamamla → bitir.
Xcode Accessibility Inspector denetimlerini ve XCUITest performAccessibilityAudit'i kritik ekranlara ekle.
Bulguları ve kalanları docs/ERISILEBILIRLIK.md'ye yaz.
```

Kabul: Otomatik denetimler kritik ekranlarda temiz; VoiceOver ile tam antrenman kaydı yapılabiliyor.

### P098 · Performans geçişi

```text
Performansı ölç ve iyileştir (önce ölç, sonra değiştir; her iyileştirmenin öncesi/sonrasını yaz):
- Soğuk açılış süresi (hedef: ilk kare < 1 sn orta sınıf cihazda); katalog içe aktarma ve model yükleme açılışı
  engellememeli.
- Kaydırma: kütüphane (800+), geçmiş (500 antrenman), sohbet (uzun akan mesaj) — takılma (hitch) oranı.
- SwiftData: yavaş sorgular, gereksiz ilişki yüklemeleri, toplu ekleme; fetchLimit ve hafif projeksiyonlar.
- Skor yeniden hesabı ve senkronizasyonun ana iş parçacığını bloklamadığını doğrula.
- Bellek: görsel önbelleği sınırları; uzun antrenmanda sızıntı yok (Instruments Leaks/Allocations).
- Pil: aktif antrenmanda arka plan etkinliği; Live Activity güncelleme sıklığı.
- Uygulama boyutu: paket içi görseller ve model; hedef indirme boyutunu belirle.
XCTest performans ölçümleri (açılış, kütüphane arama, skor hesabı) ekle ve taban değerleri kaydet.
docs/PERFORMANS.md'ye sonuçları yaz.
```

Kabul: Hedefler tutuyor veya sapma gerekçesiyle belgelenmiş; performans testleri tabanlı.

### P099 · Test sertleştirme

```text
Test kapsamını yayın düzeyine çıkar:
- Kapsam raporu al; StrengthKit ve DataKit'te eksik dalları kapat (hedef: kritik mantıkta yüksek dal kapsamı —
  rakamı ölçümden sonra belirle).
- XCUITest kritik yollar (sahte arka uçla, deterministik): kayıt → onboarding → ilk skor; program oluştur →
  antrenman yap → özet; koç mesajı → öneri → uygula; satın alma (StoreKit test) → kilit açılır; hesap silme.
- Şema geçişi testi: SchemaV1 verisiyle açılış (ilk yayından sonraki her şema değişikliği için kalıp).
- Senkron kaos testi: rastgele sıralı çevrimdışı düzenlemeler → iki cihaz sonunda aynı durumda (özellik tabanlı).
- Yerelleştirme: eksik çeviri anahtarı ve biçim belirteci uyumsuzluğu denetimi (CI'da).
- Kararsız (flaky) testleri tespit et ve kök nedenini düzelt; testi devre dışı bırakma.
- CI süresini ölç; gerekiyorsa paralelleştir.
```

Kabul: Beş kritik UI yolu CI'da yeşil; kaos testi tutarlı.

### P100 · Analitik ve çökme izleme

```text
Gözlemlenebilirliği ekle (docs/02-MIMARI.md §5):
- TelemetryDeck SDK; kimlik toplamayan olaylar. Önce olay sözlüğünü yaz (docs/ANALITIK.md): huni (kurulum →
  kayıt → onboarding tamam → ilk antrenman → ilk skor → 7. gün dönüş), özellik kullanımı (koç mesajı, öneri
  uygula/ret, paylaşım, referans grubu değişimi), gelir (ödeme duvarı görüntüleme → deneme → abonelik).
  Olaylarda kişisel veri, ağırlık, skor değeri, mesaj içeriği YOK; yalnızca sayım ve kategoriler.
- Analytics protokolü + TelemetryDeck uygulaması + test sahtesi; Ayarlar'da analitiği kapatma anahtarı.
- MetricKit: çökme ve takılma tanılamalarını topla; kimliksiz özetini kendi uç noktamıza veya loglara yaz.
- Sunucu tarafı pano sorguları (SQL): günlük aktif koç kullanıcıları, mesaj başına maliyet, sağlayıcı hata oranı,
  kota aşımı oranı, model sürümü dağılımı.
- Uyarılar: günlük LLM harcaması eşiği, Edge Function hata oranı (basit zamanlanmış denetim).
Olay sözlüğünü onayıma sun.
```

Kabul: Olaylar TelemetryDeck'te görünüyor; hiçbir olayda kişisel veri yok (denetlendi).

### P101 · Gizlilik ve hukuk

```text
Yayın için gizlilik ve hukuk paketini hazırla. Sen hukukçu değilsin; ürettiğin metinler taslaktır ve bunu her
belgenin başına yaz.
- Veri envanteri (docs/VERI-ENVANTERI.md): toplanan her veri türü, amaç, hukuki dayanak, saklama süresi, kimle
  paylaşıldığı (Supabase, OpenRouter + model sağlayıcıları, DeepSeek, Apple, TelemetryDeck), yurt dışı aktarım.
- Gizlilik Politikası ve Kullanım Koşulları taslakları (TR/EN), KVKK aydınlatma metni ve açık rıza metinleri
  (AI paylaşımı, model katkısı) — uygulamadaki onay ekranlarıyla birebir tutarlı.
- PrivacyInfo.xcprivacy: toplanan veri türleri, izleme yok, gerekli neden API'leri; üçüncü taraf SDK manifestlerini denetle.
- App Store gizlilik etiketleri için yanıt tablosu; yaş derecelendirme anketi yanıtları.
- Sağlık ve AI sorumluluk reddi metinleri; 16+ yaş koşulu.
- Statik site (P088 ile aynı): /privacy, /terms, /support sayfaları TR/EN.
- docs/YAYIN-KONTROL.md'ye "hukukçu incelemesi gerekli" maddelerini tek tek yaz.
Envanterin kodla tutarlılığını denetle: kodda toplanan ama envanterde olmayan veri var mı?
```

Kabul: Tüm belgeler taslak olarak hazır ve tutarlı; hukukçu inceleme listesi çıkarılmış.

### P102 · Güvenlik incelemesi

```text
Uçtan uca güvenlik incelemesi yap ve bulguları önem sırasına göre düzelt:
- Veritabanı: RLS'siz/politikasız tablo, fazla geniş politika, security definer fonksiyonlarda search_path ve
  yetki denetimi, herkese açık kovalar; Supabase güvenlik danışmanı çıktısı.
- Edge Functions: kimlik doğrulama atlanabilir mi, girdi doğrulama, hız sınırı, hata mesajlarında sızıntı,
  loglarda kişisel veri veya anahtar, CORS, servis rolü kullanımının en aza indirilmesi.
- LLM: istem enjeksiyonu (notlar, hareket adları, bellek, kullanıcı adı üzerinden), araçların başkasının verisine
  erişememesi, önerilerin onaysız uygulanamaması, çıktıda Markdown/bağlantı kötüye kullanımı.
- İstemci: pakette gizli anahtar taraması, Keychain kullanımı, derin bağlantı girdileri, model paketi imza
  doğrulaması, ATS, ekran görüntüsü/önizlemede hassas veri.
- Kötüye kullanım: sahte istemciyle koç proxy'sini tüketme → App Attest'i değerlendir ve uygula (veya gerekçesiyle ertele).
- Bağımlılık denetimi ve sürüm sabitleme; gizli anahtar taraması CI'da.
docs/GUVENLIK.md: tehdit modeli, bulgular, düzeltmeler, kabul edilen riskler.
```

Kabul: Yüksek önemli bulgu kalmadı; kabul edilen riskler belgelenmiş.

### P103 · Mağaza varlıkları ve inceleme hazırlığı

```text
App Store sayfasını ve inceleme paketini hazırla:
- Ad ve marka: aday adlar için App Store'da ad çakışması ve temel marka araması yapmamda bana yol göster; seçilen
  adı tek yapılandırma değişkeninden uygula (P003).
- Uygulama simgesi (koyu/açık/renkli tonlu varyantlar; Icon Composer biçimi), açılış ekranı.
- Ekran görüntüleri: XCUITest ile otomatik üretim (demo verisiyle, TR ve EN, gerekli cihaz boyutları); başlıklı
  çerçeveler; sıralama: skor → antrenman → kas haritası → koç → gelişim.
- Metinler (TR/EN): ad, alt başlık, anahtar kelimeler, açıklama, tanıtım metni, yenilikler.
- İnceleme notları: demo hesabı (dolu veriyle), AI kullanımı ve onay akışının açıklaması, HealthKit kullanımı,
  abonelik, sağlık iddiası olmadığı, hesap silmenin yeri, kullanıcı içeriği için engelle/bildir.
- Guideline öz denetimi: 1.2 (kullanıcı içeriği), 2.1 (tamlık), 3.1.2 (abonelik), 4.8 (Sign in with Apple),
  5.1.1 (veri toplama, hesap silme), 5.1.2(i) (AI paylaşımı), HealthKit kuralları. Güncel metni Apple'ın sitesinden oku.
```

Kabul: Ekran görüntüleri otomatik üretiliyor; öz denetim listesi tamam.

### P104 · TestFlight, yayın ve yayın sonrası

```text
Yayın sürecini yürüt:
- Sürümleme ve derleme numarası kuralı; Release yapılandırmasında prod Supabase; fastlane veya Xcode Cloud ile
  TestFlight yüklemesi (hangisi daha az bakım istiyorsa onu öner ve kur).
- Prod hazırlığı: göçleri prod'a uygula, katalog tohumu, model paketi yayını (is_active), Edge Function'lar ve
  secrets, App Store bildirim URL'si, harcama tavanları, yedekleme ayarı. Tümünü docs/YAYIN-KONTROL.md'de işaretle.
- İç beta (kendi cihazların) → dış beta (TestFlight genel bağlantı): geri bildirim formu, bilinen sorunlar listesi.
  Beta çıkış kriterleri: çökme oranı, kritik hata sıfır, koç güvenlik seti temiz, senkron veri kaybı sıfır.
- App Store gönderimi; ret gelirse inceleme notunu yapıştır, kök nedeni düzelt.
- Kademeli yayın (aşamalı dağıtım) ve geri alma planı: model paketi (is_active), koç devre kesici, özellik bayrakları.
- Yayın sonrası ilk 2 hafta izleme listesi: çökmeler, huni, mesaj başına LLM maliyeti, skor dağılımı (salon
  referansında medyan ~50 civarında mı? değilse kalibrasyon sinyali), destek talepleri.
- v1.1 için docs/ILERLEME.md "Ertelenenler" listesini önceliklendir.
```

Kabul: Uygulama TestFlight'ta; yayın kontrol listesi tamam; izleme panosu çalışıyor.
