# Trin 5b — andre personer i posten: ægtefæller, børn og forældre (#151/#150)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-10-06. Ikke reviewet.

**Roadmap:** trin 5, »Placement/membership og én identitetsvej konsolideres (#150/#151)«, delspec 2 af 3
(5a identitetsvej → **5b andre personer i posten** → 5c placement/membership). Bygger på 5a
(`docs/superpowers/specs/2026-09-24-trin5a-identitetsvej-design.md`, merget #236, ikke deployet) og
lukker trin 4-specens åbne punkter 11.3 (delvist: nye personer) og 11.7 (persona-oprettelse for andre
aktører).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151, med #150's familiedel) |
| Værdikædeled | Fortolkning → source persona for anden aktør → identitet → afgørelse → dokumenteret binding |
| Leverancetype | Generel motor (relationspersonas, familiesignal, strukturel binding, nye personer); udtrækkets mønstre er en udgaveprofil for 2018-20 |
| Redaktionel værdi | Ægteskaber, børn og forældre i 2018-20 bliver kildebundne: hvert ægteskab peger på kildens påstand, og ægtefællen er en sporbar persona med afgjort identitet. Redaktøren ser kun uoverensstemmelser og en stikprøve |
| Færdigbevis | Ende-til-ende i en kopi af den fulde 2018-20-base med projektejerens ark, bestået stikprøve, maskinel bekræftelse, nye personer og bindinger (§10) |
| Erstatter | Den gamle loaders ukildebundne `family_member`-rækker som eneste spor af ægteskaber; 5a's `new_person_needed` som blindgyde |

## 2. Udgangspunkt (målt 2026-10-06 i `daa2018f_20261001133125`, samme indhold som prod)

Gældende fortolkninger i kilde 1 uden persona (alle `proposed`, uafgjorte):

| Prædikat | Antal | Står ordret i citeret klausul | Poster |
| --- | --- | --- | --- |
| `relation.marriage` | 248 | 242 | 217 (højst 4 pr. post) |
| `relation.child` | 14 | 14 | 14 |
| `relation.parent` | 10 | 10 | 10 |
| `mention.person` | 20 | — | — |
| `mention.place` | 680 | — | uden for 5b |

- Værdien er kun `{raw, normalized}` — ægtefællens navn og år står i fri tekst; 132 af 248 har et
  firecifret årstal.
- Hver relationspåstand citerer én klausul (én undtagelse med to) i én post.
- Kanonisk: 587 hovedpersoner (accepteret identitet), 348 familier hvor en hovedperson er partner
  (340 med to partnere, 8 med én), 330 partnere i dem uden egen persona, 562 af 566 børn i dem er selv
  hovedpersoner. Familier pr. gift hovedperson: 1 (253), 2 (49), 3 (1), 4 (1); ordenstal udfyldt for
  næsten alle. 261 af 348 familier har en `vielse`-fakt. 47 af 1.222 kanoniske partnere er
  `levende = true`.
- `interpretation_promotion.target_type` tillader allerede `family`.
- 719 `samme_som`-relationer.

## 3. Beslutninger fra brainstormen

1. **Omfang: identitet + binding.** Ægtefællen får persona og afgjort identitet (eksisterende eller ny
   person), og ægteskabs-påstanden bindes til den eksisterende familie. En ny person får sin
   familieplads i samme skridt.
2. **Deterministisk udtræk, ingen ny modelkørsel.** Navn og årstal findes i den eksisterende
   påstandstekst; det uafklarlige parkeres og tælles.
3. **Kontrolmodel som trin 4.** Maskinen må acceptere entydige familie-sager; mennesket ser
   uoverensstemmelser og en blind stikprøve. Kræver en ny, smal kerne-oprindelse (§6).
4. **Børn og forældre bindes, `mention.person` parkeres.** Børn/forældre er hovedpersoner med egen
   persona; kun påstanden bindes. De 20 andre navngivne får ingen persona i 5b.
5. **Prod:** 5a deployes først som sin egen ceremoni; 5b bevises i restore og overføres gennem en
   separat overførsels-spec.
6. **Tilgang A — familie-forankret** (fravalgt: global matcher uden familiekontekst; »kanonisk først«,
   der ville skabe personas ud fra loaderens svar — cirkulært, strider mod invariant 1).

## 4. Arkitektur

```
relation.marriage (proposed)
  → [1] deterministisk udtræk: navnespænd + årstal i klausulen            (§5.1)
  → [2] writer-operation relation_persona: persona + mention + årstal     (§5.2)
  → [3] generator: familie-kandidater først, så global top-K              (§6.1)
  → [4] afgørelse: menneske (ark/webkø) eller family_corroboration        (§6.2, §7)
  → [5] påstanden accepteres + bindes strukturelt til familien             (§8.1)
  [N] → writer-operation relation_person_create: ny person + familieplads (§8.2)
```

**Stabil nøgle.** `persona_key` = postnøgle + `#aegteskab-<n>`, hvor `n` er påstandens nummer i
tekstrækkefølge i posten (klausulens `char_from`, derefter spændets start). Nøglen afhænger ikke af
klausul- eller fortolknings-id'er, som omsegmenteringen allerede har ændret én gang.

**Ærligt om beviset.** Familiesignalet kommer fra `family_member`-rækker, som den gamle loader skrev
fra de samme poster. Matchet mod eksisterende ægtefæller er derfor næsten selvbekræftende — værre end
5a's »øvre grænse«. Beviset viser kæden og kontrolmodellen for 2018-20. Metoden prøves for alvor kun
ved nye personer og i trin 6/7, hvor familiesignalet kommer fra andre kilder.

## 5. Udtræk og persona-writer

### 5.1 Deterministisk udtræk

- **Input er serverens:** `private.relation_persona_input(source_id)` returnerer deterministisk
  (`ORDER BY … COLLATE "C"`) de gældende `relation.marriage`-, `relation.child`- og
  `relation.parent`-påstande uden `interpretation_party`, med citeret klausul (tekst, id, `char_from`),
  postnøgle og hovedpersonens persona. Scriptet læser det via en rollegatet RPC
  `red_relation_persona_input(source_id)`.
- **Script:** `.claude/skills/daa-extract/scripts/relation_persona_extract.py` (ren funktion +
  CLI). Regler for ægteskaber:
  - `raw` skal stå ordret i den citerede klausul → spændet (`char_from`/`char_to` i klausulen). Ellers
    `parkeret: ikke_ordret`.
  - Navnet er stykket fra spændets start, efter en indledende ægteskabsmarkør, til den første markør
    for fødsel, død, forældre eller afslutning. Markørsættet er en versioneret profil
    (`relation-persona-2018-20-v1`), fastlagt i planens første task ud fra målte mønstre (kun tal).
    Intet navn eller tvetydige markører → `parkeret: <grund>`.
  - Årstal: firecifret tal umiddelbart efter en fødsels- hhv. dødsmarkør; originalteksten gemmes.
  - Børn/forældre: ingen persona; scriptet videregiver kun påstanden til §8.3.
- **Output:** en hash-bundet rækkefil (præcis id-mængde) til writeren. CLI'en printer kun tal og
  hashes (antal pr. udfald, pr. parkeringsgrund).

### 5.2 Writer-operation `relation_persona`

Ny operation i den generelle writer (#153) ved siden af `clause_evidence` og
`interpretation_proposal`: batch, manifest, profil under `requires_human_go_for_change`,
godkendelseshash og reversal følger med. Pr. ægtefælle, i batchens transaktion:

- `private.source_persona` (kilde, `persona_key`).
- `private.source_mention` med `mention_kind='person'` på klausulens observation; serveren efterprøver,
  at `substring(klausultekst, char_from, char_to)` er lig det deklarerede navn ordret.
- `private.source_persona_mention` (rolle `spouse`, ordinal 1).
- Deterministiske fortolkninger `person.birth` / `person.death` på den nye persona, når der er
  årstal: `derivation_kind='deterministic'`, `status='proposed'`, `method='relation-persona-v1'`,
  citerer klausulen, værdien bærer det rå udsnit og året.
- `private.interpretation_party`: (ægteskabspåstand, hovedpersonens persona, `principal`) og
  (ægteskabspåstand, ægtefællens persona, `spouse`).

Idempotent på (`source_id`, `persona_key`); en genkørsel med andet spænd eller anden påstand rejser
fail-closed i stedet for at overskrive. Reversal fjerner batchens rækker, så længe ingen identitet er
afgjort for personaerne (ellers afvises den).

### 5.3 Ny tabel `private.interpretation_party`

```
interpretation_id  uuid  → private.interpretation(id)
source_persona_id  uuid  → private.source_persona(id)
party_role         text  CHECK IN ('principal','spouse','child','parent')
created_batch_id   uuid  → writerens batch
PRIMARY KEY (interpretation_id, party_role)
```

Append-only (triggere som de øvrige evidenstabeller), RLS uden politikker for klientroller, ingen
grants. Den bærer relationens to ender, fordi `interpretation.source_persona_id` kun kan bære én.

## 6. Kandidater og maskinel bekræftelse

### 6.1 Generatoren

`@daa/identity-candidates` udvides; serverens inputfunktion (5a's `private.identity_candidate_input`)
tager ægtefælle-personas med og tilføjer pr. persona:

- hovedpersonens accepterede person, dennes familier (`family_id`, ordenstal, partnere) og antallet af
  ægteskabs-påstande i posten;
- personaens navn (mention) og år (de deterministiske fortolkninger).

Kandidater i rækkefølge: **familie-kandidater** (partnerne ≠ hovedpersonen i hovedpersonens familier,
signal `family_partner`, `ordinal_match` sand/falsk) før **global top-K** (5a's matcher). Generatoren
sætter `corroboration_eligible` med grund; egnet kræver alle:

1. præcis én familie-kandidat efter ordenstal (eller hovedpersonen har præcis én familie);
2. antal ægteskabs-påstande i posten = antal familier for hovedpersonen — ellers går **hele posten**
   til mennesket (`count_mismatch`);
3. navnet er foreneligt over en grænse, der fastsættes i planen ud fra en målt fordeling og
   dokumenteres med begrundelse (forsigtig, fordi målingen næsten bekræfter sig selv).

**`samme_som`-klynger** (5a-svaghed 1): kandidater i samme klynge slås sammen til én kandidat med
medlemmerne listet; repræsentanten er den, der er partner i familien, ellers laveste id. En klynge kan
derfor ikke give falsk uafgjort.

### 6.2 Kerne-oprindelse `family_corroboration` — ændrer 5a §4.2

5a besluttede, at ingen oprindelse tillader batch-match ud fra lighed. 5b indsnævrer det med én ny
oprindelse i `private.decide_source_persona_identity`, som **kernen selv efterprøver strukturelt** og
ikke tager fra kalderen:

- (a) personaen har en `interpretation_party`-rolle `spouse`, og påstandens `principal`-persona har en
  gældende `accepted` identitet;
- (b) målpersonen er den eneste partner ≠ hovedpersonen i præcis én familie, som ordenstallet (eller
  den eneste familie) udpeger — kernen læser `family_member` selv;
- (c) `candidate_id` er rang 1 for netop denne persona i kildens **gældende** kandidatkørsel og
  peger på målpersonen.

Kræver `accepted`, forventet version 0, `basis='family_corroboration'`. Navnelighed kan kernen ikke
beregne (den er Node); den er generatorens og spores via `candidates_sha256`. Alle andre lighedsmatch
forbliver lukkede. Posten i `docs/decisions.md` skrives, når specen er godkendt.

### 6.3 RPC `red_corroborate_family_identities(p_run_id uuid, p_expect_set_sha256 text)`

Rollegatet (redaktion). Tager kildelåsen delt som 5a's afgørelser. Serveren:

1. finder selv de egnede personas i kørslen (rang 1, `corroboration_eligible`, uden gældende
   afgørelse);
2. kræver, at SHA-256 af den sorterede persona-id-mængde er lig `p_expect_set_sha256` — **mængde, ikke
   antal**; drift ⇒ `IDENTITY_CORROBORATION_SET_DRIFT`, intet skrives;
3. kalder kernen med `family_corroboration` for hver; ét afvist krav ⇒ hele kaldet ruller tilbage.

Evidens: `{basis, run_id, candidate_id, family_id, ordinal, method:'family-corroboration-v1'}`.
Aktøren er redaktøren, der kører RPC'en.

### 6.4 Kandidatvisning (5a-svaghed 3)

Detalje-RPC, ark og webkø viser pr. kandidat titler og embeder (gældende konklusioner), postnøglen på
kandidatens egen persona (hvis nogen) og hvilken familie/ordenstal kandidaten kommer fra.

### 6.5 1939-årstal (5a-svaghed 2)

Kun med, hvis planens måling viser, at globale kandidater for parkerede eller nye sager rammer
1939-personer uden udfyldt dato. Ellers åbent punkt til trin 6.

## 7. Kontrolmodel, ark og webkø

### 7.1 Rækkefølge

1. Generatoren kører; egnethed beregnet (§6.1).
2. **Arket** = alle uoverensstemmelser + en **blind stikprøve** af de egnede (stratificeret: én
   familie / flere familier; størrelse max(10, 10 % af de egnede)). Stikprøven viser kun kandidaterne,
   ikke maskinens svar. Projektejeren godkender med hash; rækkefil og præcis id-mængde bindes (5a).
3. Arket køres gennem `red_afgoer_source_persona` (`human`, `basis: human_sheet`).
4. **Stikprøven er bestået**, når hver stikprøvesag er afgjort som kandidat 1 (= maskinens valg).
5. Først da kører `red_corroborate_family_identities` på de resterende egnede (afgjorte springes over).

### 7.2 Stopregel

Én afvigelse i stikprøven — anden person, `D`, `U` eller `N` — stopper den maskinelle bekræftelse for
hele kørslen. Sagerne går til mennesket, eller reglen revideres og får en ny runde med ny stikprøve.

### 7.3 Ark

5a's `identity_decision_sheet.py` med tokens kandidatnummer, `D`, `U`, `N`, `S <id>`. Ny kontekstlinje
pr. sag: hovedpersonens postnøgle, ægteskabsnummer og uoverensstemmelsens grund. Ingen værdier forlader
arket. Relationslinjer for børn/forældre (§8.3) bruger samme ark med familie-kandidater. Overstiger
arket 80 linjer, deles det i flere hash-bundne ark i rækkefølge (projektejerens regel: ingen fulde
afgørelsesark).

### 7.4 Webkø

Kildepersona-køen kan filtrere på `spouse` og viser familiekonteksten (§6.4). Beviset er paritet som i
5a (payload fastlåst i vitest → psql → feltsammenligning); der findes ingen lokal Supabase-API. **Den
første levende webkø-afgørelse** er et eksplicit punkt i 5b's prod-overførsels-spec.

## 8. Binding, nye personer, børn og forældre

### 8.1 Ægteskabs-påstanden

Når både `principal` og `spouse` har gældende `accepted` identitet:

- serveren finder familien, hvor begge er partnere; præcis én kræves;
- påstanden accepteres maskinelt gennem den eksisterende kontrolmodels afgørelsesvej
  (`control_model.py` / `interpretation_control_classification.sql`) med metode
  `family-structure-v1`, evidens `{family_id, principal_persona_id, spouse_persona_id,
  identity_versions}`;
- **ny bindingstype — strukturel:** regel `relation-marriage-v1`, `target_type='family'`,
  `target_id` = familien. Trin 4's regler binder på tekstidentisk værdi mod en assertion; en rå
  ægteskabstekst er aldrig lig en `vielse`-værdi, så relationer binder på struktur (begge partnere i
  familien). Findes en `vielse`-fakt, står dens id i evidensen; målet er altid familien;
- ingen eller flere familier ⇒ påstanden forbliver `accepted` uden binding, talt med grund;
- citerede klausuler får ny maskinel dispositionsversion: `afventer_identitet` →
  `fortolkning_foreslaaet`.

### 8.2 Nye personer (`N`)

`N` afgør identiteten som `unresolved` med `reason: new_person_needed` (5a). Derefter tager
writer-operationen `relation_person_create` (udvidelse af #153's `person_create`) alle sådanne sager i
én batch med godkendelseshash. Writeren efterprøver, at hver sag er afgjort `new_person_needed` af et
menneske (`human`-oprindelse), og pr. sag i én transaktion:

- `private.insert_person_with_receipt` (kvittering, 5a);
- **`levende`** (invariant 8, fail-closed): `false` kun hvis klausulen har et dødsår; ellers `true`;
- navnet som fact/assertion/konklusion efter mønstret i `red_apply_reimport_person_create`, så
  `visning_*` afledes (invariant 4), assertion kildebundet til kilden;
- **familieplads:** har hovedpersonen en familie med kun én partner og passende ordenstal, indsættes
  personen dér; ellers ny familie (`type='vielse'`) med hovedpersonen og den nye person, ordenstal fra
  tekstrækkefølgen;
- identitet med `person_create` og kvittering;
- påstandens afgørelse og binding som §8.1.

Kun navn og familieplads; fødsels-/dødsfakta er en senere promotionregel. Reversal fjerner personen,
familiepladsen og identiteten, så længe intet andet peger på personen.

### 8.3 Børn og forældre (24 påstande)

Ingen ny persona. Modparten findes strukturelt blandt kilde 1's hovedpersoner:

- `relation.child`: hovedpersonen er partner i en familie, og en anden hovedperson er `barn` i den;
- `relation.parent`: hovedpersonen er `barn` i en familie, og modparten er partner i den;
- navnet foreneligt (samme grænse som §6.1).

Præcis én modpart ⇒ maskinel accept og binding til familien med `relation-child-v1` /
`relation-parent-v1` (metode `family-structure-v1`); sagerne indgår i stikprøvens stratum. Ellers en
relationslinje i arket. `interpretation_party` får rollerne `principal` og `child`/`parent`.

### 8.4 `mention.person`

De 20 parkeres og tælles; ingen persona i 5b.

## 9. Privatliv

Ingen modelkald. Scripts printer kun tal og hashes. Arket bærer navne og læses kun af projektejeren
(5a's regler: privat mappe 0700, filer 0600, aldrig til en model). Nye personer er skjulte, indtil
andet er vist (§8.2). Nye tabeller og RPC'er får RLS/ACL og står i `db-rls.sql`'s lister og
`db-verify.sql`'s ACL-drift-asserts.

## 10. Færdigbevis (i restore, ikke i prod)

Arbejdsbase: kopi af `daa2018f_20261001133125`, løftet med `db-migrations.sql` + `db-rls.sql`
(5a + 5b). Rapport `docs/evidensbaseret-genimport/relationspersonas-5b-bevis.md` — kun tal, hashes og
basenavne.

1. Udtræk: personas, parkerede pr. grund, 0 værdier i log.
2. Kalibrering: egnede, uoverensstemmelser, navnelighedsfordeling — rapporteret som næsten
   selvbekræftende (§4).
3. Ark + stikprøve afgjort af projektejeren; stopreglen negativtestet (én afvigelse blokerer).
4. Maskinel bekræftelse: antal, mængde-hash, 0 skrivninger ved drift (negativtest).
5. Nye personer: antal, `levende`-fordeling, familieplads, kvitteringer; reversal af hele batchen.
6. Binding: ægteskaber/børn/forældre bundet, ubundne pr. grund, intet kanonisk delta ud over nye
   personer og familier.
7. Webspor-paritet (§7.4).

## 11. Test

- **SQL** (CI's friske schema-sti): `interpretation_party` (append-only, RLS, `TRUNCATE`);
  `relation_persona` (rollegate, ordret spænd, idempotens, genkørsel med andet spænd afvises, reversal);
  `family_corroboration` med (a), (b), (c) hver negativt; mængde-drift; kildelås; de tre bindingsregler
  (én familie, ingen, flere); `relation_person_create` (`levende`, eksisterende enkelt-partner-familie,
  ny familie, kvittering, kun `human`-`N`, reversal); funktionsflade og ACL-lister.
- **Pytest:** udtrækkets parser på syntetiske eksempler (alle parkeringsgrunde); arkets nye
  kontekst- og relationslinjer; arkets hashbinding.
- **Vitest:** familiesignal, `ordinal_match`, `count_mismatch`, klyngesammenlægning, egnethed,
  deterministisk output/hash; webkøens filter og visning.
- Statisk test af kernens kalder-allowlist (5a's `test_identity_guard_static.py` udvides).
- `get_advisors` efter DDL. Hele CI-jobbet køres lokalt før push.

## 12. Søm og rækkefølge (til planen)

- **Del 1 — identitet:** udtræk, `interpretation_party`, `relation_persona`, generatorudvidelse,
  `family_corroboration`, ark, kontrolmodel, webkø.
- **Del 2 — binding:** bindingsreglerne, `relation_person_create`, børn/forældre, færdigbevis og
  rapport.

Bliver planen længere end 5a's, skrives den som to planer, der udføres i rækkefølge.

## 13. Prod

5a deployes først (egen ceremoni, skrivepause for webkøen). 5b's DDL og data går til prod gennem en
separat overførsels-spec som trin 4, inkl. første levende webkø-afgørelse. Fortrydelse af DDL er en
migration; dataenes fortrydelse er writer-operationernes reversal.

## 14. Åbne punkter (registreres, løses ikke her)

1. 1939-årstal i matcheren, hvis §6.5's måling ikke kræver dem — trin 6.
2. `mention.person` (20) — personas for øvrige navngivne.
3. Fødsels-/dødsfakta for nye personer — promotionregel.
4. 1939's ægtefæller — trin 6.
5. Placement-signal (slægt/linje/generation) i matcheren — 5c.
6. Om `family_corroboration` kan generaliseres til familier fra andre kilder (trin 6/7) — afgøres på
   trin 6's målinger.
