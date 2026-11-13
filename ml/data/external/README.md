# Dış doğrulama verisi

## `van_den_hoek_2024.csv`

van den Hoek DJ, Beaumont PL, van den Hoek AK, Owen PJ, Garrett JM, Buhmann R, Latella C. *Normative data for the
squat, bench press and deadlift exercises in powerlifting: Data from 809,986 competition entries.*
J Sci Med Sport. 2024;27(10):734–742. doi:10.1016/j.jsams.2024.07.005. PMID 39060209.

Birincil kaynaktan (PubMed özeti, NCBI E-utilities ile 2026-11-13'te okundu) alınan 90. yüzdelik göreli güç
değerleri (kaldırılan ağırlık / vücut ağırlığı). Özet yalnızca 18–35 ("young adults") ve >80 yaş için 90. yüzdeliği
veriyor; kilo sınıfı ve diğer yüzdelikler makalenin tablolarındadır (tam metin erişilemediği için alınmadı).
Örneklem: ilaç testli, ekipmansız yarışma kayıtları (571.650 erkek, 238.336 kadın), kilo sınıfları toplu.

Kullanım: `gymml/eval/external.py`, docs/03-ML-MODEL.md §4.3 ölçütü "90. yüzdeliğe ±%3 uyum" (18–35);
>80 satırları yalnızca raporlanır.
