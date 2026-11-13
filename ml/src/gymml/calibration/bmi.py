"""BMI tabanlı vücut kompozisyonu düzeltmesi deneyi (P055, docs/03-ML-MODEL.md §7).

Fikir: yüksek BMI'li bir salon/genel nüfus kullanıcısında kilonun tamamı yağsız kütle değildir.
Çapa modeline giren vücut ağırlığı, BMI eşiğinin üstündeki fazlanın yalnızca bir kesri sayılarak
küçültülür:

    bw_eff = bw                                   (BMI ≤ eşik)
    bw_eff = eşik·h² + β·(bw − eşik·h²)            (BMI > eşik)

Özellik bayrağı varsayılan olarak kapalıdır; açılması için değerlendirmede iyileşme göstermesi
gerekir.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BMICorrection:
    threshold: float = 25.0
    beta: float = 0.5

    def effective_bodyweight(self, bodyweight_kg: float, height_cm: float) -> float:
        h2 = (height_cm / 100.0) ** 2
        cap = self.threshold * h2
        if bodyweight_kg <= cap:
            return bodyweight_kg
        return cap + self.beta * (bodyweight_kg - cap)

    def with_assumed_height(self, heights_cm: dict[str, float]):
        """Boy bilgisi olmayan çapalar için cinsiyete göre varsayılan boyla bw → bw_eff."""

        def fn(sex: str, bw: float) -> float:
            return self.effective_bodyweight(bw, heights_cm[sex])

        return fn
