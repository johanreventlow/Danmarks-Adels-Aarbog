# Design — »Nævnes …« i stedet for »Livsdatoer ikke angivet« (leverance 1: strukturerede datoer)

**Status:** udkast 2026-11-19, bygherre-tjek indarbejdet (GDPR-filter, konfidens, kvalifikatorer — §5), til
projektejerens godkendelse.
Projektejerens afgørelser står i §3; mine valg er markeret *mit valg*.
**Arv:** projektejerens gennemgang af personsiden 19/11 (memory »personside: kun det der er«, PR #392 og #394).

## 1. Hvorfor

En person uden fødsel og død står i dag som »Livsdatoer ikke angivet (i Aarbogen)« på personsiden, i panelet, i
søgningen og i slægtskabsfinderen. Teksten er sand, men den skjuler, at bogen ofte *har* en dato for personen: et
floruit (»Nævnes 1671«, »1349 (29. maj) – 1391 (23. juni)«), et vielsesår eller en dateret titel. Læseren skal se
den tid, personen er dokumenteret i, så en middelalderperson kan placeres i tid.

**Kobling:** læserflade og visningscache. Ikke genimport, ikke fortolkning af kildetekst; evidenslaget røres ikke.
Leverance 2 (biografierne, §9) er fortolkning og går gennem `docs/evidensbaseret-genimport/`.

## 2. Målt udgangspunkt (prod, læse-kun, 2026-11-19)

| | |
|---|---|
| Person-rækker uden `visning_foedt` og `visning_doed` | 473 (0 levende) |
| … heraf hvor en samme_som-alias har livsdatoer (læseren ser allerede år) | 179 |
| **Identiteter uden livsdatoer** (samme_som foldet, som læseren ser dem) | **185** |
| … med floruit-faktum | 62 |
| … uden floruit, men med dateret vielse | 23 |
| … uden struktureret dato | 100 (leverance 2) |
| Rækker med både livsdatoer og floruit | 40 |
| Daterede faktatyper hos rækker uden livsdatoer | floruit 60, titel 16, begravelse 6, klosterindgang 2 |
| Daterede relationer hos rækker uden livsdatoer | 0 |
| `haendelse`-rækker | 0 (bevidst, decisions §»haendelse-kravet«, #130) |

Floruit-påstandene har `date_min/date_max` udfyldt (104 af 105); `date_raw` er fri form (»levede 1680«, »Skrives 1729
til Brunsholm«), så visningen bygges af `date_min/date_max`, ikke af råteksten. Målescripts: job-tmp
`floruit-maal.sh`, `floruit-kilder.sh`, `floruit-biografi.sh`, `floruit-identitet.sh` (genskabes ved behov).

## 3. Projektejerens afgørelser (19/11)

1. **Altid »Nævnes …«**, også når årstallet er udledt af en vielse, titel eller begravelse — ens tekst overalt.
2. **Vej A:** et nyt cachefelt `person.visning_floruit`, beregnet af den eksisterende regenerering, så lister og søgning
   får det med. (Fravalgt B: klienten beregner selv ud fra en ekstra bulk-hentning — tungere opstart under anons 3 s
   timeout og logik i klienten frem for i dataene.)
3. **Først leverance 1** (strukturerede datoer), **så leverance 2** (biografier).
4. **Leverance 2 må udvide et spænd**, ikke kun udfylde huller (§9).
5. Tomme sektioner/tekster vises ikke (»vis kun det, der er«): uden livsdatoer og uden floruit står der ingenting.

## 4. Mål, ikke-mål, anti-mål

**Mål**
- `person.visning_floruit` = personens dokumenterede år som `'1671'` eller `'1349–1391'` (en-tankestreg), afledt af
  afklarede konklusioner.
- De fem visningssteder (`PersonSide.tsx:89`, `DetailPanel.tsx:71`, `SoegView.tsx:179`, `RelateView.tsx:112` og
  `:202`) viser livsdatoer, ellers »Nævnes 1349–1391«, ellers intet.
- Samme_som-foldede identiteter viser foreningsmængden af aliasernes spænd.

**Ikke-mål**
- Biografierne (leverance 2).
- Daterede relationer (embede, ejer) som kilde — 0 i dag; kan tilføjes, når de findes.
- Redaktionens flade (viser rå fakta og påstande, ikke cachen).
- Mobilens personside-redesign (mobil er dev-only); mobilen får kun feltet med i load + den delte formatter.

**Anti-mål** (ville være fejl, selv om det virker)
- At skrive `visning_floruit` direkte (invariant 4) — kun `regen_person_floruit` (som `regen_person_visning` kalder til sidst); aldrig direkte, og aldrig ved livsdatoer.
- At vise »Nævnes …« for en person med livsdatoer.
- At logik, der i dag bruger `years`/`born`/`died` som »har livsdatoer« (sortering, generationer, alder, aarUnder),
  begynder at opfatte et floruit som en fødsel eller død.
- At gemme ordet »Nævnes« i databasen — ordet er præsentation; cachen bærer kun årstallene.

## 5. Beregning (DB)

**Kilder** — kun afklarede konklusioners **valgte** påstand (`conclusion.status='afklaret'`,
`assertion.id = conclusion.valgt_assertion_id`), som resten af `regen_person_visning`:

1. Personens egne fakta, **alle faktatyper undtagen `fødsel` og `død`**, hvor påstanden har `date_min` eller
   `date_max`. Generisk frem for en liste (*mit valg*): en ny dateret faktatype — og leverance 2's floruit-påstande —
   kommer med uden ny kode.
2. Fakta på en `family`, hvor personen er `partner` (vielse o.l.), daterede som ovenfor — **kun når
   `family_offentlig(family_id)` er sand** og **personens partner-række ikke har `konfidens` i
   (`formodet`, `omstridt`)** (begge *mit valg*, bygherre-tjek 19/11):
   - *GDPR (invariant 8, F-02c):* `family_offentlig` skjuler familien og dens fakta for anon, så snart ét medlem
     (også et barn) er levende, privat eller staged. `person`-rækken er læsbar for anon, så et vielsesår fra en
     skjult familie ville lække gennem cachen. Cachen er én værdi for alle læsere og skal derfor være offentlig-sikker
     (fail-closed).
   - *Konfidens (invariant 7):* en formodet eller omstridt ægteskabsforbindelse må ikke datere personen; usikkerheden
     vises i familieafsnittet, ikke i årstallet.

**Spænd:** `lo = min(år(least(date_min, date_max)))`, `hi = max(år(greatest(date_min, date_max)))` over alle
kilder (`least`/`greatest` ignorerer NULL og vender et omvendt interval). Åbne ender (`date_min` NULL = »før«) falder dermed tilbage på den kendte ende. `lo = hi` → `'1671'`, ellers
`'lo–hi'`; ingen kilder → NULL.

**Kvalifikatorer og læsesikkerhed** (*mit valg*): `date_qualifier` (`before`, `after`, `about` …) og
`date_certainty` vises ikke og filtrerer ikke. »Nævnes« er i sig selv en tilnærmelse (dokumenteret, ikke levetid —
invariant 5), og råteksten bevares urørt i påstanden. Kun årstal, aldrig dag og måned, så visningen bliver aldrig mere
præcis end bogen.

**NULL når livsdatoer findes** (projektejerens afgørelse 19/11, erstatter »altid beregnet«): har personen ikke-tom
`visning_foedt` eller `visning_doed`, er `visning_floruit` NULL — floruit er kun relevant uden livsdatoer. I en
samme_som-gruppe kan en alias uden livsdatoer stadig bære et floruit; collapse lader livsdatoerne vinde (§6).

**Regenerering** (revideret efter Task 1, ruling R4) — en særskilt `regen_person_floruit(pid)` skriver **kun**
`visning_floruit` (beregner spændet, NULL ved livsdatoer, `IS DISTINCT FROM`-vagt). `regen_person_visning(pid)` er
uændret for de seks eksisterende felter og kalder `regen_person_floruit(pid)` til sidst, så den ser de friske
livsdatoer. Alle nye invalideringsveje kalder kun `regen_person_floruit` — en trigger genberegner kun det, dens input
påvirker, og eksisterende drift i de seks felter (issue #396) røres ikke:

- `trg_regen_from_conclusion` og `trg_regen_from_assertion`: når target er et `fact` med `subjekt_type='family'`,
  regenerér alle familiens `partner`-medlemmer.
- `family_member`: INSERT/DELETE/UPDATE (også af `konfidens`) af **enhver** række regenererer familiens
  `partner`-medlemmer (gammel og ny familie) — et nyt levende barn kan lukke familien.
- `person`: UPDATE OF `levende`, `privat`, `staged` regenererer partnerne i alle familier, personen er medlem af
  (`family_offentlig` kan skifte). Triggeren er kolonnebegrænset, så regen-funktionernes egne `UPDATE`s af
  `visning_*` ikke udløser den igen.

**Versionering:** `visning_floruit` tilføjes `version_pk_registry.skip_cols` for `person` (som `visning_efternavn`,
`db-migrations.sql:1512`), så fortrydelse ikke logger eller genspiller en cacheværdi.

**Udrulning:** `schema.sql` (source of truth) + idempotent spejl i `db-migrations.sql` + asserts i `db-verify.sql`;
prod-ceremoni efter den sædvanlige procedure (`docs/database-current-state.md`): DDL, derefter en backfill, der kalder
`regen_person_floruit` for alle personer; de seks eksisterende `visning_*` skal være identiske som mængde før/efter.

## 6. Visning (app)

- **Delt formatter i `@daa/core`** (`fields.ts`): `fmtVisningsAar(foedt, doed, floruit)` = `fmtYears(foedt, doed)`,
  hvis den ikke er tom, ellers `'Nævnes ' + floruit`, hvis floruit findes, ellers `''`.
- **Model:** `web/src/data/model.ts` og `mobile/src/data/load.ts` henter `visning_floruit`; `AppPerson` får
  `floruit: string | null` (rå spænd). `years` beregnes med `fmtVisningsAar` (*mit valg*), så alle steder, der viser
  `years` (også feed-kort og stamtræ), får teksten uden ændringer. `born`/`died`/`foedtSpaend`/`doedSpaend` er
  uændrede — logik, der bruger dem, påvirkes ikke.
- **Collapse** (`collapseSameAs.ts:302`): `floruit` flettes som foreningsmængden (mindste lo, største hi) af
  aliasernes spænd, og `regenYears` bruger `fmtVisningsAar`, så en alias med livsdatoer stadig vinder.
- **Tekster:** de fem »Livsdatoer ikke angivet«-fallbacks fjernes; tom `years` → linjen udelades (personsiden og
  panelet) eller kun de øvrige led vises (`SoegView`: titel; `RelateView:112`: linje).

## 7. Færdigbevis

- `db-verify.sql`: en person med floruit-faktum, en med kun vielse, en uden dato, en med livsdatoer + floruit, og
  invalidering ved ændring af vielsens konklusion og af `family_member`. **Lækagetest:** en afdød, offentlig partner
  i en familie med et levende barn får *ikke* vielsesåret i `visning_floruit`; markeres barnet afdødt, kommer det;
  en `formodet` partner-række giver intet årstal.
- Core-tests for `fmtVisningsAar` og collapse-fletningen; web-tests for de fem steder (ingen »Livsdatoer ikke angivet«).
- Prod efter backfill: antal identiteter, der viser »Nævnes …«, ≈ 85 (62 + 23, §2) minus de vielser, GDPR-/konfidensfilteret fjerner — planens første skridt måler det
præcise forventede tal læse-kun, før DDL'en skrives; antal personer med livsdatoer
  uændret; `get_advisors` uden nye fund.
- Visuelt i preview: 44 (floruit 1349–1391), en ingift med kun vielse (fx 594), 392 Conrad (livsdatoer, ingen ændring).

## 8. Overladt til bygherren

- Præcis trigger-form (statement- vs. rækkeniveau) og om `family`-sletning skal dækkes særskilt.
- Om RPC'er, der returnerer `born`/`died` til feed eller redaktion (fx `db-migrations.sql:7302`, `:7333`), bør
  returnere `floruit` — kun hvis en læserflade viser dem uden modellen.
- Gennemgang af steder, der bruger `years` som sandhedsværdi for »har livsdatoer«; skift dem til `born`/`died`.

## 9. Leverance 2 (eget forløb, kun skitse)

Årstal i biografierne (egen og ægtefælles; 212 + 242 narrativer, gns. 350–490 tegn, 1 GDPR-spærret), der vedrører
personen selv, udtrækkes og gemmes som **nye, kildebundne floruit-påstande** (invariant 1, 5, 6) med citation til
narrativets udgave og tekststed. §5's generiske beregning tager dem med og udvider spændet. Fravalgt: `haendelse`
(nøglet til narrativets ejer, dækker ikke ingifte) og at skrive i cachen. Kræver læsning af
`docs/evidensbaseret-genimport/` (vision → roadmap → målarkitektur → status), GDPR-filter som
`export_narratives.R` og en indgang i `docs/decisions.md`.
