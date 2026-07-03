# Review: børn hvis ctx-mor ≠ forælderens registrerede ægtefælle (2026-07-03)

**Anledning:** Efter III-85-fixet (ekstraktionsfejl i `aegteskab_kontekst`) — er der andre
børn med samme type fejl? Read-only scan af `work/clean-v2.json`.

## Konklusion kort (VERIFICERET mod narrativ + prod 2026-07-03)

- **III-85's *præcise* signatur** (barn af FLERGIFT forælder hvis ctx navngiver en partner der
  slet ikke er blandt forælderens ægteskaber) var **unik** — matcheren fangede kun III-85.
- Et bredere sweep fandt **58 børn / 16 forældre** hvor ctx-moderen ≠ registreret ægtefælle, MEN
  **verifikation viser INGEN prod-korruption**: alle 16 forældre er **enkelt-gifte**, så loaderens
  matcher blev aldrig kaldt — børnene røg direkte på den ene registrerede union, og den union er
  (for 12/16 bekræftet i narrativen) den **rigtige** mor. Den forkerte `aegteskab_kontekst` er
  **inert spøgelses-tekst** (samme ekstraktionsfejl som III-85, men uden effekt).

## Hvorfor var III-85 speciel?

III-85 blev ramt netop fordi dens forælder (Friedrich III-61) var den **eneste flergifte** blandt
de berørte. For flergifte forældre KØRER matcheren og bruger ctx → en forvansket ctx fører til
fejl-parkering. For de 16 enkelt-gifte forældre her ignoreres ctx helt af loaderen.

## Verifikations-matrix (registreret ægtefælle vs. ctx-mor i forælderens narrativ)

| Dom | Forældre |
|---|---|
| **PROD OK — registreret ægtefælle i narrativ, ctx-mor fraværende (ctx = spøgelse)** | I-25, I-36, I-49, I-56, I-115, III-35, IV-17, IV-28, **IV-64** (også empirisk bekræftet i prod: børn på zu Rantzau), V-51, V-122, V-124 (12 stk.) |
| Tvetydig — mor = NN/ukendt el. navn=stednavn; ingen tegn på fejlplacering | I-6, I-11, I-37, I-97 (4 stk.) |

**IV-64 dybtjek:** narrativ: "Gift 21. aug. 1906 ... med Anna Ottilie ... zu Rantzau ... 4 børn nr.
77-81"; børn født 1907-1915 (efter vielsen). "Elisabeth Benvenuta Stein" (ctx) findes IKKE i
narrativen. Prod: alle 5 børn på familie 246 = zu Rantzau. → korrekt; ctx er spøgelse.

## Kandidater (grupperet pr. forælder — tjek hver mod bogen)

| Forælder | Registreret ægtefælle | ctx-navngiven mor | Berørte børn |
|---|---|---|---|
| I-6 Wulf | *(ukendt)* | Elisabeth NN | I-10 |
| I-11 Nicolaus | *(ukendt)* | NN | I-18,19,20,21 |
| I-25 Detlef | NN | **Beke von Pogwisch** | I-31,32,33,34,35 |
| I-36 Hartwich | Ghese NN | Cecilie (Split?) | I-42–48 |
| I-37 Lüder | *(ukendt)* | Cecilie (Split?) | I-49,50 |
| I-49 Lüder | Mette Breide | Sophie Joachimsdatter [Bjørn] | I-57 |
| I-56 Joachim (Jacob) | Abel von Buchwaldt | Sophie Joachimsdatter [Bjørn] | I-59–65 |
| I-97 Bartram | Christina von Rantzau | Maria Elisabeth von Buchwaldt til Tresdorf | I-104 |
| I-115 Otto | Hedwig Ida von Sala | Cecilia von Wickede | I-122 |
| III-35 Lorenz | Anna Katharina Both | Margareta Finecke | III-49,50,51,52 |
| IV-17 Friedrich | …Löw von und zu Steinfurth | …Julia Louisa …zu Rantzau | IV-35–40 |
| IV-28 Joachim | …von Gronsfeld-Diepenbroick | …von Löwenstern | IV-55–59 |
| IV-64 Heinrich Ernst Emil Kurt | …zu Rantzau | Elisabeth Benvenuta Stein | IV-77–81 |
| V-51 Ludvig Ditlew | …von Hammerstein-Loxten | Margarete Benedicte von Qualen | V-75–79 |
| V-122 Ernst Einar … | …d'Allemont de Broutillot | Benedicte Ulfsparre Bech | V-150 |
| V-124 Carl (Catty) … | …von dem Knesebeck-Milendonck | Benedicte Ulfsparre Bech | V-151,152,153 |

Bemærk: I-25 "Beke von Pogwisch" er kendt (kryds-slægt-bro, jf. `identitets-collapse-loesning-a`).

## Anden kategori (28 børn — beslægtet, ikke i tabellen)

Børn hvis forælder har **0 ægteskaber i sit array**, men hvis ctx navngiver en mor "med X (se nr. N)"
(fx I-109–118 "med Maria Elisabeth von Buchwaldt (se nr. 103)"). Her er der ingen konflikt — blot
en mor der ikke er blevet knyttet som union. Data-komplethed, samme rod (uudtrukket vielse).

## Anbefaling (revideret efter verifikation)

**Ingen prod-fix nødvendig for de 58.** Verifikationen viser at børnene allerede sidder på den
korrekte (registrerede) mor; ctx er inert. Konkret:

1. **De 12 "PROD OK"-forældre:** intet at gøre i prod. Den forkerte ctx er valgfri at nulstille i
   `clean-v2.json` (kun relevant hvis en ægte 2. vielse senere tilføjes — ellers ignoreres den).
2. **De 4 tvetydige (I-6, I-11, I-37, I-97):** ukendte/NN-mødre; kan kigges efter mod bogen ved
   lejlighed, men ingen tegn på fejlplacering. Lav prioritet.
3. **Rodårsag fundet + rettet i `segment.py` (2026-07-03):** III-85's fejl var IKKE marr-bleed men
   en regex-miss — headingen `af første ægteskab med Catharina von Brockdorff:-` slutter på "**:-**"
   (kolon+bindestreg), som `MARR_RE` ikke matchede → den forrige heading ("Margaretha von Rumohr")
   klæbede til III-85. `MARR_RE` tolererer nu trailing bindestreg/tankestreg. Verificeret mod hele
   `raw_full.txt`: **præcis 1 record ændret** (III-85 → korrekt Brockdorff), nul regressioner; ny
   regressions-test `test_segment.py` (4 tests). Effekt kun ved FREMTIDIGT re-extract (prod er
   allerede rettet via change_set 2). En bredere "reset marr ved kuld-markør" blev afprøvet men
   **forkastet** — den nulstillede I-96/I-97's korrekte heading (børn af flergifte I-89).

**Bemærk risiko-asymmetrien:** ctx bruges KUN af loaderen for flergifte forældre. Så en spøgelses-ctx
er farlig *kun* hvis forælderen er (eller bliver) flergift. III-85 var det eneste sådanne tilfælde.

Relaterer til [[boern-multi-union-datafix]] (III-85 = samme ekstraktionsfejl, men på en flergift
forælder → reel fejlplacering) og [[flere-foraeldre-datafix]].
