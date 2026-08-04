# 1939 tekstkvalitet: behold eksisterende renditioner, ingen ny OCR

**Dato:** 2026-08-03  
**Beslutning:** Brug den eksisterende Calamari R6-rendition som frosset
arbejdskilde; bevar både kilde-PDF og `raw.txt` uændret. Der udføres hverken
udvalgt eller fuld gen-OCR i denne fase.

## Kontrolleret input

| Materiale | SHA-256 | Rolle |
|---|---|---|
| `Dansk Adels Aarbog - Reventlow 1939.pdf` | `5711975512a2b14a2ce49eee404cc9796c9020343ca67d64b99606035deba0b7` | autoritativ sidekontrol |
| `work_1939_stamtavle/raw.txt` | `efab316b528eafc60074c21c877590b31ab8e960cd1adc14f5c79bf01f12dab7` | tidligere OCR-rendition og komplethedsreference |
| `work_1939_stamtavle/full_ocr_calamari_r6_clean.txt` | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` | frosset arbejdsrendition |

`raw.txt` dækker PDF-side 490--598. Det omfatter den efterspurgte indledende
kontekst før stamtavlen og den efterfølgende liste over uplacerede personer;
intet af dette afskæres eller overskrives.

## Stikprøve mod renderede sider

Der er visuelt kontrolleret sider 490 (indledning), 496 (første stamtavle-
side), 503 og 512 (tæt, spærret sats, ægteskaber og sideskift) samt 560
(illustration/layout). PDF'en er læsbar, men eksisterende OCR har reelle
tegnforvekslinger, fx `Qotskalk` for det trykte `Gotskalk`. OCR må derfor
aldrig være eneste sandhed ved usikre ankre, navne eller datoer.

Den tidligere PDF-baserede stikprøve på 25 poster fandt, at de materielle
fejl overvejende var fragmenter og fejlsnit, ikke forkerte navne, år eller
ægtefæller. Calamari-patchen har allerede forbedret tegnniveauet; den kendte
restklasse er segmentering. En ny OCR ville derfor både være dyr og mangle en
påvist fejlklasse, som den løser bedre end den eksisterende rendition.

## Arbejdsregel

1. `full_ocr_calamari_r6_clean.txt` bruges til ny segmentering og til
   record-/clause-forekomster.
2. `raw.txt` bevares som separat, ældre rendition og bruges til
   kompletheds- og kontinuitetskrydstjek; det erstattes aldrig.
3. Renderet PDF-side er afgørende ved uoverensstemmelse. Uafklarede ankre,
   relationer eller identiteter parkeres til menneskereview.
4. Før en senere ny OCR kan godkendes, skal den foreslåede rendition måles mod
   de samme PDF-sider og vise forbedring uden tabte/sammenblandede records.

Dette er en read-only beslutning. Den autoriserer ikke produktion-load,
narrativpatch eller ændring af eksisterende OCR-artefakter.
