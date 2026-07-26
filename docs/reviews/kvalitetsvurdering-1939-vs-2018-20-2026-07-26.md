# Kvalitetsvurdering: DAA 1939 vs. DAA 2018-20

**Dato:** 2026-07-26 · **Målt mod:** prod (`xjnvdhajfyrcytatnzos`) · **Status:** måling udført, stikprøve-audit ikke udført

Formål: kvantificere om 1939-indlæsningen er markant dårligere end 2018-20, og fastlægge hvad der
skal gøres — uden at miste det manuelle matcharbejde.

---

## 0. Forsikring udført først

`work_1939_stamtavle/match_backup_2026-07-26.json` (gitignoreret) — **434 samme_som-par**
(429 på tværs af udgaver) eksporteret med `person_id`, `linje`, `nr`, **navn og rå fødsel/død-tekst
på begge sider**. Navn+dato gør parrene re-ankrbare hvis en re-segmentering forskyder `nr`.
Matcharbejdet kan derfor ikke tabes, uanset hvilket niveau vi vælger nedenfor.

---

## 1. Kohorter

Kohorte bestemt evidensbaseret (hyppigste `citation.source_id` på personens fakta), ikke via `staged`.

| | DAA 2018-20 (source 1) | DAA 1939 (source 3) |
|---|---|---|
| Personer i alt | 922 | 835 |
| Heraf **hovedposter** (egen post i bogen) | 591 | 539 |
| Heraf ægtefæller (ingen egen post) | 331 | 296 |

Definition: "hovedpost" = personen har en `person_external_id`-række (linje+nr fra bogen).
"Ægtefælle" = personen har ingen. Tallene er direkte optalt, ikke udledt ved subtraktion.

**Vigtigt for al læsning nedenfor:** ægtefæller har strukturelt hverken narrativ eller forældrelink.
Alle rater beregnes derfor på **hovedposter**, ellers bliver tallene misvisende.

---

## 2. Hvor 1939 faktisk står svagere

| Mål (hovedposter) | 2018-20 | 1939 |
|---|---|---|
| Har forældrelink | **566/591 = 95,8 %** | **355/539 = 65,9 %** |
| Snit fakta pr. person | 5,33 | 3,76 |
| Poster helt uden fødsel/død/andet fakta (kun navn) | 12 | **55** |
| Narrativ, median-længde | 377 tegn | **180 tegn** |
| Narrativ under 60 tegn (fragment) | 70 | 73 |

**Headline: 184 af 1939's 539 hovedposter mangler et forældrelink** (355 linkede).

**Dette er ikke et nyt fund — det er en bekræftelse.** `docs/plan-1939-produktionsklar.md:153`
dokumenterer at v1.3.0-artefaktet indeholdt præcis **355 links**, med de resterende parkeret som
uopløste. Prod matcher artefakt-facittet 1:1 → **K3-loadet tabte ingenting.** Manglen er en
ekstraktions-grænse, ikke en indlæsningsfejl, og brugeren traf en bevidst load-beslutning på den.

Det afgørende: A3b vurderede de parkerede links som *"strukturelt uopløselige **uden bedre
upstream-ekstraktion**"*. Bedre segmentering **er** bedre upstream-ekstraktion (se §4). Trin 1
nedenfor er derfor ikke kun kosmetisk oprydning — det er den mest sandsynlige vej til at frigøre
en del af de 184.

### Plausibilitetstest af de links der findes

Eneste automatiserede *korrekthedssignal* uden stikprøve: testet forælder→barn-kanter hvor begge
fødselsår kendes.

| | 2018-20 | 1939 |
|---|---|---|
| Testbare kanter | 771 | 255 |
| Barn født før/samme år som forælder | 1 | **0** |
| Aldersgab under 14 år | 1 | **0** |
| Aldersgab over 70 år | 0 | **0** |
| Barn født >1 år efter forælders død | 1 | **0** |

**De 1939-links der findes, ser rigtige ud.** Det bekræfter A3's "0 falske links"-verifikation
empirisk i prod. 1939's problem er *manglende* links, ikke *forkerte*.
(Forbehold: kun 255 af 355 kanter er testbare; 2018-20's 1-3 hits bør ses på ved lejlighed.)

## 3. Hvor 1939 *ikke* står svagere

- **Tegn-niveau-OCR er allerede rettet.** Calamari-patchen (`narrative_1939_patch.json`) er live i
  prod — DB-teksten matcher patchen 1:1. Restfejl som `Ehlerstori`, `XLVII1`, `1o5` findes stadig,
  men de er OCR-*rest*, ikke en uindlæst forbedring. Genkør ikke OCR-diskussionen.
- **Datoparsing: høj rate blandt de datoer der er *fanget*.** Uparsede rå datoer:
  1939 = 62/800 (**7,8 %**); 2018-20 = 331/2024 (**16,4 %**). A2-hærdningen virkede på det den fik.
  **Men rate ≠ komplethed** — man kan ikke have en uparset dato man aldrig udtrak. 1939 har 800 rå
  datoer mod 2018-20's 2024 på sammenligneligt postantal.

### Capture-gap (målt, regex mod narrativ vs. fakta)

| Hovedposter uden fakta, men med synligt datomønster i narrativet | 2018-20 | 1939 |
|---|---|---|
| Mangler `fødsel`-fakta, men `f. <tal>` står i narrativet | 0 | **16** |
| Mangler `død`-fakta, men `† <tal>` står i narrativet | 16 | **26** |
| Mangler begge, men mindst én dato står i narrativet | 5 | **19** |

Så: **parse-raten er god, men capture har et hul i 1939** — ~42 poster hvor datoen er synlig i den
bevarede prosa men ikke blev til et faktum. Forklaringen er strukturel: de nuværende narrativer
kommer fra Calamari-patchen, mens fakta blev udtrukket fra et *ældre* upstream (`linked_clean.json`).
Det gør niveau 2 nedenfor **nødvendigt** for de fakta-tomme poster, ikke valgfrit.
(Regexet er groft — tallene er en nedre grænse og skal bekræftes i stikprøven.)

- Svagt, men medtaget: 0 "født efter død" og 0 levetider > 109 år i begge udgaver. Predikatet
  rammer kun personer med *begge* datoer og er derfor et svagt signal — ikke på niveau med ovenstående.

---

## 4. Den reelle restdefekt: **segmentering**

Narrativet skæres ud af OCR-teksten med ankre. Det er dér fejlene sidder. Målt på alle 539 poster:

| Defekt | Antal | Andel |
|---|---|---|
| Narrativ starter midt i en sætning (manglende hoved) | 91 | 16,9 % |
| Narrativ under 60 tegn (fragment) | 73 | 13,5 % |
| Narrativ indeholder en gren-header (`IV.`) midt i teksten | 33 | 6,1 % |
| Narrativ slutter uden punktum → **næste afsnits-header hængt på** | 153 | 28,4 % |
| **Union (dedupliceret — læg ikke sammen)** | **280** | **51,9 %** |

Verificeret ved stikprøve at den sidste klasse er en ægte defekt og ikke bogens egen typografi —
10/10 stikprøver endte i næste gruppes overskrift, fx:

> `… 8. Ulrik, f. o. 1608.\nLandraad David Reventlows Børn m. Margarethe\nvon Finecke:`

Konkrete eksempler på de øvrige klasser:

- **nr 53** — hele narrativet er `borg († 1801), hvis Søn var Greve Detlev Chri-` (46 tegn). Fragment af en anden persons tekst.
- **nr 297** — mangler sit hoved (`f. 10 Marts 1710; …`) *og* sin `g.`-markør, så vielsen står som løsrevet dato.
- **nr 264** — bløder over i næste sektion: `IV.\nGeheimeraad Detlev Reventlows Børn`.

**Brugerens fornemmelse er altså korrekt — men årsagen er snit, ikke tegngenkendelse.**
Det er godt nyt: begge de store klasser (start-midt-i og hale-bleed) er *regulære* mønstre, som
kan rettes deterministisk mod `full_ocr_calamari_r6_clean.txt` uden LLM.

---

## 5. Hvad tallene *ikke* siger — og hvorfor stikprøven mangler

Der er 429 samme_som-par på tværs af udgaver. På dem er der næsten ingen dato-uenighed
(fødselsår 349/353 enige, dødsår 281/292 enige). **Det tal må IKKE læses som en fejlrate for 1939.**
Matchningen er lavet manuelt på navn og dato — par hvor datoerne var uenige blev i vid udstrækning
aldrig til par. Enigheden viser at *matcharbejdet er internt konsistent*, ikke at 1939 er korrekt.

Den informative population er de **111 hovedposter i 1939 uden match** (539 − 428) plus de
defektmarkerede narrativer. Der er fejlraten uopgjort.

**Alle tal ovenfor måler hvad der MANGLER. Ingen af dem måler hvad der er FORKERT.**
Kun en stikprøve mod bogen kan det.

➡️ **Den stikprøve er nu udført:** se
[`stikproeve-audit-1939-baseline-2026-07-26.md`](stikproeve-audit-1939-baseline-2026-07-26.md)
(N=25, bedømt mod renderede PDF-sider). Hovedtal: **~54 % af posterne har ≥1 materiel fejl**, men
**0 forkerte navne, år og ægtefæller** — fejlene er udeladelser og fejlklip, ikke forkerte påstande.

---

## 6. Anbefalet plan

### Trin 1 (nu, blokerer intet): stikprøve-audit mod PDF-sider

- N ≈ 70 poster, **stratificeret**: overrepræsentér de 111 umatchede og de 280 defektmarkerede,
  resten ved basisrate. Gem stratum pr. post, så resultatet kan vægtes op til et korpusestimat.
- **Bedøm mod renderede PDF-sider — ikke mod `full_ocr_calamari_r6_clean.txt`.** At auditere
  udtrækket mod dets eget input skjuler systematisk de OCR-inducerede fejl.
- Fast taksonomi, så tallene er sammenlignelige: narrativ hører til forkert person · fragment ·
  bleed · person mangler i DB · spøgelsesperson i DB · forældrelink forkert · forældrelink mangler
  (men står i bogen) · dato forkert · dato mangler (men står i bogen) · navn forkert ·
  ægteskab forkert/manglende.
- Rapportér **både** "andel poster med ≥1 materiel fejl" og fejlrate pr. felt. Kun ét af tallene
  er misvisende i begge retninger.
- Kør samme harness på **25-30 poster fra 2018-20** med samme taksonomi, så de to udgaver får
  sammenlignelige tal i stedet for ét målt estimat og ét anekdotisk.

### Trin 2: reparation i tre niveauer — vælges ud fra stikprøven

1. **Re-segmentering alene (billigst, rører ingen personer) — vejen er allerede bygget.**
   Kør `segment_1939.py` igen mod `full_ocr_calamari_r6_clean.txt` med rettede ankre +
   deterministisk afskæring af hale-headere; patch kun `narrative.tekst` via
   **`R/update-1939-narratives.R`** — samme sti som Calamari-patchen brugte til prod.
   Ingen `person`-rækker, ingen `nr`, intet match berøres. Fikser fragment/bleed/trunkerings-klassen
   (forventeligt størstedelen af de 280) og er samtidig forudsætningen for at frigøre parkerede
   forældrelinks, jf. §2. **Højeste leverage, lavest risiko — start her.**
2. **Re-ekstraktion af strukturerede fakta, samme personer.** Nøgles på
   `person_external_id(source_id=3, nr)`; skriver **nye påstande + nye konklusioner** med
   1939-citation. Datamodellen tillader det indfødt (invariant #1: påstande overskrives aldrig),
   og med uændret `person_id` overlever alle 429 matchpar.
   ⚠️ **Uverificeret forudsætning:** der findes pt. **ingen påvist loader-sti** der upserter på
   `person_external_id` og *appender* påstande til eksisterende personer. `load_daa.R` opretter
   personer, og 1939 gik netop gennem `convert_1939_stamtavle.py` med syntetisk `linje="1939"` for
   at lade den delte loader være urørt. Regn med **ny loader-kode** her — det er ikke en gratis
   egenskab ved modellen. Målrettes de 184 forældreløse og de ~42/55 fakta-tomme poster.
3. **Fuld re-load med nye person-rækker.** Kun nødvendigt for poster hvor segmenteringen har
   *splittet eller slået personer sammen* — dér ændres personmængden, ikke bare dens fakta.
   Backup fra §0 gør dette overlevelsesdygtigt.

**Forventning inden stikprøven (skal bekræftes):** niveau 1 for alle, niveau 2 for de forældreløse
og fakta-tomme, niveau 3 for en håndfuld. **Ingen fuld re-load af 1939.**

Rækkefølge: niveau 1 **før** stikprøven kan overvejes, da re-segmenteringen ændrer det materiale
stikprøven skal bedømme. Modargument: uden stikprøve først kender vi ikke effekten af niveau 1.
Kompromis: kør stikprøven på ~25 poster nu (baseline), niveau 1, derefter samme 25 igen (effektmåling)
plus de resterende ~45 til korpusestimatet.

### 2018-20

Skal ikke laves om. `docs/plan-1939-produktionsklar.md` dokumenterer allerede ~6 materielle
datofejl på 591 poster (~1 %), empirisk verificeret. Det eneste der reelt bør ses på er de
**16,4 % uparsede datoer** — sandsynligvis relative former (`s.å.`/`s.m.`), som bevidst blev
sprunget over i A2.

---

## 7. Sideobservation (ikke kvalitet — synlighed)

33 personer med `source_id=3` har `staged=false`, mens resten af 1939 er gemt for anon via K2-gaten.
De 33 er alle `levende=false`, og alle 7 `levende` 1939-personer er korrekt `staged=true` →
**ingen GDPR-lækage.** Men det betyder at en delmængde af 1939 er offentligt synlig mens udgaven
ellers er upubliceret. Bør afklares som en selvstændig sag.
