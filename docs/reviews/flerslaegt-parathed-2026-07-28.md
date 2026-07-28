# Flerslægts-parathed + krav til fremtidige udtræk

**Dato:** 2026-07-28 · **Målt mod:** prod (`xjnvdhajfyrcytatnzos`) + koden på `main`
**Status:** vurdering. Ingen ændringer foretaget.

Anledning: hvis PoC'en lykkes, skal andre slægter ind (Ahlefeldt-Laurvig m.fl.). To spørgsmål:
hvad skal vi kræve af næste udtræk, og er mekanikken overhovedet gearet til andet end Reventlow?

**Kort svar: datamodellen er klar; pipelinen og én enkelt constraint er det ikke.**

---

## Del 1 — Krav til fremtidige udtræk

Alle punkter stammer fra fund gjort på Reventlow-korpuset 2026-07-27/28. De er formuleret som krav
til den *næste* ekstraktion, ikke som fejlrapporter.

### K1. Ægtefælle-poster skal dekomponeres

Det største enkeltfund. Ægtefæller (personer bogen ikke gav et eget opslag) blev oprettet som
biprodukt af et ægteskab, og **hele bogens klausul røg i `visning_navn`**. Det gav fem symptomer
der alle er den samme defekt:

| Symptom | Omfang |
|---|---|
| ingen kilde vist | 627 (rettet i visningen, PR #105 — men årsagen består) |
| `koen` mangler | 625 |
| ingen datoer | 296 af 296 fra 1939 |
| navn indeholder gods/titel/parentes | 112 af 604 (18,5 %) |
| dublet på tværs af udgaver, uopdaget | 454 uden `samme_som` |

Krav: en ægtefælle-omtale skal give **navn**, **titel**, **køn**, **datoer** og **godsbesiddelser**
som separate fakta — ikke én streng. Titel ≠ navn er allerede modellens regel; udtrækket
respekterede den kun for hovedposter.

### K2. Oversigts- og prosaregioner må ikke producere personposter

1939-stamtavlens indledende oversigtsprosa blev udtrukket som selvstændige poster, så én person
optræder både som omtale-fragment og som rigtig post. ~30 bekræftede dubletpar, 50 mistænkte poster.
Se [`dubletter-1939-2026-07-27.md`](dubletter-1939-2026-07-27.md).

Krav: prosaomtaler skal markeres, ikke materialiseres. **Behold `_ctx.gruppe`-etiketteringen** —
det var modellens egen etiket (`narrativ-kæde (…)`, `I-IV (Joachim havde Sønnerne)`) der gjorde
defekten maskinelt detekterbar bagefter. Uden den havde fundet krævet manuel læsning.

### K3. Dedup skal normalisere før sammenligning

To udtræk af samme post overlevede dedup'en fordi dødsteksten var `i samme Maaned` i den ene og
`i samme Maaned (Febr. 1643)` i den anden. Krav: normalisér (whitespace, parenteser, ortografi)
før strengsammenligning — ellers fanger dedup kun de eksakte gengangere.

### K4. Hver post skal have en stabil `record_key`

DAA 2018-20 har fået `record_key` backfillet (591 poster). **1939 har stadig ingen stabil
identitet**, hvilket blokerer re-import og gør enhver rettelse til et engangsindgreb. Krav:
`record_key` sættes ved udtræk, ikke bagefter.

### K5. Kildebinding — allerede opfyldt, hold den

Alle 1756 personer har `fact → assertion → citation → source`, og 296 har sidetal. Det er
invariant 1 der virker. Krav: intet faktum uden citation, og sidetal hvor bogen har det.

### K6. Slægtsnavnet hører ikke i fornavnsfeltet

Se Del 2. Navnet der udtrækkes skal være personens *egennavn*; efternavnet kommer fra
linje-medlemskabet. Et udtræk der selv skriver "Reventlow" ind i navnet, dublerer det og gør
tværudgave-matchning sværere.

### K7. Småting med målt effekt

- `matchKey`'s `TITLE_RE` (`packages/core/src/navnevarianter.ts:7`) fjerner rangord (`greve`,
  `baron`, `von`, `til`) men **ikke embedstitler** (`Geheimekonferensraad`, `Kammerherre`,
  `Amtmand i …`). Målt: en godshale koster næsten intet (Jaro-Winkler 0,857/0,886 — over
  cutoff 0,70), men et titel-*præfiks* koster alt (0,541 — under). Placeringen afgør, ikke
  mængden, fordi Jaro-Winkler præmierer fælles præfiks. 21 poster ramt.

---

## Del 2 — Er mekanikken gearet til andre slægter?

### Allerede generisk (den gode nyhed)

**Efternavns-maskineriet er bygget til præcis dette og er slægtsagnostisk:**

- `lineage.slaegtsnavn` bærer families-efternavnet på linjen — ikke på personen.
- `lineage_effective_slaegtsnavn()` (`schema.sql:655`) går rekursivt op ad `parent_lineage_id` til
  første ikke-NULL, så en undergren arver moderslægtens navn uden at gentage det.
- `regen_person_visning` udleder `visning_efternavn`/`visning_fuldt_navn` af linje-medlemskab.
- `slaegtsnavn_karantaene` fanger personer hvis linjer er uenige om efternavnet, i stedet for at
  vælge tilfældigt.
- Graf-walkerne er cyklus- og dybdesikrede og fejler højlydt frem for at trunkere stille.

Evidenslaget (`source`/`assertion`/`citation`), det polymorfe relations-lag og fakta-modellen er
alle slægtsneutrale i forvejen. **Ingen af dem skal ændres.**

### Reventlow-bundet (det der spærrer)

**B1 — `lineage UNIQUE (source_id, kode)` (`schema.sql:578`) kolliderer på tværs af slægter.**
`source.import_key` er i dag `'daa:2018-20'`, altså nøglet på **udgaven**, ikke på udgave×slægt.
Ahlefeldt-Laurvig i samme årbog ville derfor lande på `source_id = 1` — og begge slægter har en
"Linje I", "Linje II". Hård kollision. To veje, og valget er reelt:

1. **Namespace `source`** → `'daa:2018-20:ahlefeldt-laurvig'`, én `source`-række pr. udgave×slægt.
   Billigst, ingen skemaændring. Men det bryder med `CLAUDE.md`'s "hver trykt DAA-udgave er en
   selvstændig `source`", som er dét der gør modstridende udgaver indfødt håndterbare — to slægter
   fra samme bog ville nu se ud som to kilder.
2. **Scope constraint'en til slægten** → `UNIQUE (source_id, <slægt>, kode)`. Bevarer source-
   semantikken, men kræver migration og en slægts-dimension på `lineage`.

**B2 — der findes ingen slægts-rod.** Alle fem Reventlow-linjer har `parent_lineage_id = NULL`, så
*intet* knudepunkt siger "dette er slægten Reventlow". Mekanikken til at nøgle grene under en rod
findes og er cyklus-sikret — den er bare ikke taget i brug.

Beviset for at det gør ondt allerede: de to slægts-narrativer
(`narrative.subjekt_type='slaegt'`, "# von REVENTLOW …" og "Holstensk og mecklenburgsk
uradelsslægt …") har `subjekt_id = 1`, hvilket er **`lineage`-rækken for linje I**. Teksten om
*slægten* sidder altså parkeret på dens første *gren*, fordi der ikke er noget andet sted at gøre af
den.

Migrationen er additiv: én rod-`lineage` pr. slægt med `slaegtsnavn` på roden, eksisterende grene
repeget via `parent_lineage_id`, slægts-narrativer flyttet til roden. `lineage_effective_slaegtsnavn()`
gør resten af sig selv.

**B3 — pipelinen har slægtsnavnet indbygget tre steder:**

| Sted | Hvad |
|---|---|
| `post_load_fixup.R:53` | `INSERT INTO lineage (…) VALUES (…,'Reventlow')` — hardkodet |
| `convert_1939_stamtavle.py:67` | `SLAEGTSNAVN = "reventlow"` — styrer navne-token-match |
| `segment_1939.py:43` | `HEADER_LINE_RE = ^Reventlow\.$` — sidehoved-filter |

Alle tre er parametre forklædt som konstanter. De skal komme fra en slægts-konfiguration (navn,
sidehoved-mønster, linjeinddeling), ikke fra kildekoden.

`segment_1939.py` har derudover flere Reventlow-specifikke prosamønstre (`… Reventlows Børn m. …`)
i gruppe-header-genkendelsen. De er formsprog fra DAA generelt, men slægtsnavnet indgår i regexet.

### Hvad "Linje II" skal hedde i stedet

Brugerens egen pointe: linjen kan ikke bare hedde "II". Med B2 løst gør den det heller ikke —
`kode` forbliver bogens rå token (proveniens, korrekt), mens visningen bliver
`<slægtsrod>.navn` + `<gren>.navn`, fx "Ahlefeldt-Laurvig — Den langelandske linje". `kode` bør
ikke bære slægten; roden gør.

---

## Rækkefølge

1. **B2 (slægts-rod)** — additiv, ingen constraint-ændring, giver slægts-narrativerne et hjem og
   gør `slaegtsnavn` til ét sted pr. slægt i stedet for fem.
2. **B1 (nøglerum)** — beslutning før næste slægt loades. Vej 1 eller vej 2; ikke en kodeopgave
   før valget er truffet.
3. **B3 (parametrisering)** — når en anden slægt faktisk skal udtrækkes; det er dér kravene bliver
   testbare frem for hypotetiske.
4. **K1–K7** — indarbejdes i `/daa-extract`-skillens kontrakt, så de gælder pr. konstruktion i
   stedet for at blive genopdaget pr. slægt.

---

**Forbehold**

- B1's to veje er ikke afvejet til bunds — valget afhænger af, om to slægter fra samme bog skal
  kunne være uenige om noget, hvilket er et redaktionelt spørgsmål mere end et teknisk.
- Vurderingen bygger på Reventlow-korpuset alene. En anden slægts stamtavle kan have formsprog
  (fx flere våben pr. linje, adoptioner, navneskifte ved len) som ingen af disse fund rører.
- `lineage.presens_kode` har et **globalt** unikt indeks (`schema.sql:588`), ikke pr. slægt. Det er
  ikke undersøgt om det er tilsigtet — men det kolliderer på samme måde som B1 hvis to slægter får
  præsenslister.
