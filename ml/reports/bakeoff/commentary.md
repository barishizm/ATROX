## 11. Yorum ve öneri (kullanıcı onayı bekliyor)

**Kurallara göre sonuç:** Hiçbir aday §1'deki bütün kapıları geçmedi; kazanan ilan edilmedi.

**Adayların kaldığı yerler:**

- **A · Spline-LMS (BCPE):** Test kümesinde kalibrasyon kapısını üç tohumda ve üç kaldırışta geçti; bant dışı
  katman oranı %2–6. Ağırlıksız van den Hoek karşılaştırmasında altı değerin hepsi ±%1,6 içinde. Boyutu 55 KB,
  Python'da tek çıkarım 0,13 ms. Kaldığı iki test sınırda:
  - *Pürüzsüzlük:* |Δ²medyan|/medyan en çok 0,0114–0,0123 (sınır 0,010). En büyük değer her kaldırışta
    **19 yaşta**: gençlikteki hızlı artışın yetişkin platosuna döndüğü büküm. 20 yaş ve üstünde en çok
    0,008–0,009 ile sınırın altında. Bu sınır P049'da belgeye dayanmadan konmuş bir uygulama ayrıntısı;
    yaş sıçraması testi de aynı nedenle 20+ yaşa çekilmişti.
  - *Kiloda artmama (bench):* +1 kg'da en büyük CDF artışı 0,0050, tolerans 0,005; eşikte.
- **B · LightGBM:** Pinball'da en iyi (test ortalaması 8,009 kg; A 8,079 kg, fark %0,87). Ama 17,6 MB ile
  boyut sınırını 17 kat aşıyor (1 MB altındaki hiçbir deneme kalibrasyon kapısını geçemedi). Pürüzsüzlük,
  kiloda artmama ve yaş testlerinden açık farkla kalıyor; kilo sınıfı dişini öğrendiği için salon
  kullanıcısına uygun değil.
- **C · Sinirsel:** Kalibrasyon kapısını testte 3 tohumun yalnızca 2'sinde geçti; pürüzsüzlükte A gibi
  19 yaşta 0,0136–0,0144.

**Eşitlik kuralı:** B ile A arasındaki birincil metrik farkı %1'in altında (%0,87). §1 madde 5'e göre B
uygun olsaydı bile daha basit model A kazanırdı.

**Öneri:** Kazanan **A · Spline-LMS (BCPE, yaş 14 / kilo 12 düğüm aralığı)**. Bunun için kullanıcının iki
sınır durumu kabul etmesi gerekir: pürüzsüzlük sınırının da yaş sıçraması gibi 20+ yaşa uygulanması ve bench
kilo testinin eşikte (0,0050) sayılması. Onaylanırsa MODEL_CARD.md güncellenir; P057'de kalibrasyon (P055)
A'ya göre yeniden kestirilir.

**Bilinen zayıflıklar:** Yarışmacı verisindeki kilo sınıfı dişi pürüzsüz modelle temsil edilmez (salon için
bilinçli tercih). 70+ yaş ve uç kilolarda veri seyrek (P048). Ağırlıklı model van den Hoek'in kayıt bazlı
değerlerinin %2–8 altında kalıyor (nicelik farkı, §8).
