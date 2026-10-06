# Trin 5b — andre personer i posten: ægtefæller, børn og forældre (#151/#150)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-10-06; revideret efter
Codex runde 5 (NO-GO: 2 MAJOR, 1 MINOR, se §19), Codex runde 4 (NO-GO: 1 BLOCKER, 1 MAJOR, se §18), Codex runde 3 (NO-GO: 3 BLOCKER, 2 MAJOR, se §17), Codex runde 2 (NO-GO: 4 BLOCKER, 3 MAJOR, 3 MINOR — alle efterprøvet og godtaget, se §16) og
dobbelt review runde 1 (Claude: 4 BLOCKER, 6 MAJOR; Codex `gpt-5.6-sol`: NO-GO, 4 BLOCKER, 4 MAJOR —
alle efterprøvet mod koden og godtaget, se §15). Fortrydelsen er ændret fra writer-reversal til
restore-only (§13), efter fortilfældene for 4.1c og 4.4.

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
| Leverancetype | Generel motor (relationsparter, familiesignal, strukturel binding, nye personer); udtrækkets mønstre er en udgaveprofil for 2018-20 |
| Redaktionel værdi | Ægteskaber, børn og forældre i 2018-20 bliver kildebundne: hvert ægteskab peger på kildens påstand, og ægtefællen er en sporbar persona med afgjort identitet. Redaktøren ser kun uoverensstemmelser og en blind stikprøve |
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

- Værdien er kun `{raw, normalized}` — navn og år står i fri tekst; 132 af 248 ægteskaber har et
  firecifret årstal. Hver relationspåstand citerer én klausul (én undtagelse med to).
- Kanonisk: 587 hovedpersoner (accepteret identitet), 348 familier hvor en hovedperson er partner
  (340 med to partnere, 8 med én), 330 partnere i dem uden egen persona, 562 af 566 børn i dem er selv
  hovedpersoner. Familier pr. gift hovedperson: 1 (253), 2 (49), 3 (1), 4 (1). 261 af 348 familier har
  en `vielse`-fakt. 47 af 1.222 kanoniske partnere er `levende = true`. 719 `samme_som`-relationer.
- Kodens udgangspunkt (efterprøvet i review runde 1): promotionregler tillader kun
  `property`→`assertion` med tekstmatch (`interpretation_promotion_rule`, `red_promote_interpretations_batch`);
  `red_decide_interpretation` skaber nyt id pr. version og kopierer kun observationer; kernens
  `person_create` kræver forventet version 0; `source_persona*`, `source_mention` og `interpretation`
  er append-only; `family.id` har ingen default (drift mod `db-migrations.sql`); `person.levende`
  er som standard `false`, og `insert_person_with_receipt` sætter den ikke; `family_member.ordinal`
  er unionens løbenummer (ens for begge partnere).

## 3. Beslutninger fra brainstormen

1. **Omfang: identitet + binding.** Ægtefællen får persona og afgjort identitet (eksisterende eller ny
   person), og ægteskabs-påstanden bindes til den eksisterende familie. En ny person får sin
   familieplads i samme skridt.
2. **Deterministisk udtræk, ingen ny modelkørsel.** Navn og årstal findes i den eksisterende
   påstandstekst; det uafklarlige parkeres og tælles.
3. **Kontrolmodel som trin 4.** Maskinen må acceptere entydige familie-sager; mennesket ser
   uoverensstemmelser og en blind stikprøve. Kræver en ny, smal kerne-oprindelse (§6.2).
4. **Børn og forældre bindes, `mention.person` parkeres.** Børn/forældre er hovedpersoner med egen
   persona; kun påstanden bindes. De 20 andre navngivne får ingen persona i 5b.
5. **Prod:** 5a deployes først som sin egen ceremoni; 5b bevises i restore og overføres gennem en
   separat overførsels-spec.
6. **Tilgang A — familie-forankret** (fravalgt: global matcher uden familiekontekst; »kanonisk først«,
   der ville skabe personas ud fra loaderens svar — cirkulært, strider mod invariant 1).

## 4. Arkitektur

```
relation.* (proposed)
  → [1] deterministisk udtræk: spænd, navn, år (kun ægteskab)          (§5.1)
  → [2] writer-operation relation_persona: persona, mention, år, parter (§5.2-5.3)
  → [3] generator: familie-kandidater først, så global top-K            (§6.1)
  → [4] kontrolkørsel: blind stikprøve + uoverensstemmelser i arket     (§7)
  → [5] maskinel bekræftelse (family_corroboration) efter bestået prøve (§6.2-6.3)
  → [6] relationspåstanden afgøres + bindes strukturelt til familien    (§8.1, §8.3)
  [N] → writer-operation relation_person_create: ny person + familieplads (§8.2)
```

**Ærligt om beviset.** Familiesignalet kommer fra `family_member`-rækker, som den gamle loader skrev
fra de samme poster. Matchet mod eksisterende ægtefæller er derfor næsten selvbekræftende — værre end
5a's »øvre grænse«. Beviset viser kæden og kontrolmodellen for 2018-20. Metoden prøves for alvor kun
ved nye personer og i trin 6/7, hvor familiesignalet kommer fra andre kilder.

## 5. Udtræk, persona-writer og relationsparter

### 5.1 Deterministisk udtræk

- **Input er serverens:** `private.relation_persona_input(source_id)` returnerer deterministisk
  (`ORDER BY … COLLATE "C"`) gældende `relation.marriage`/`child`/`parent`-påstande uden gældende
  parter: `interpretation_key`, version, prædikat, `raw`, og den citerede klausul læst **udelukkende fra
  `private.clause_observation_current`** (id, `verbatim_text`, `post_char_from`, `post_char_to`,
  `clause_set_seq`, klausulsættets sha256) samt postnøgle. Rækkefilen binder klausulsættets seq og
  sha256; writeren genvaliderer dem (ændret klausulsæt ⇒ fail-closed). Scriptet læser det via den rollegatede
  `red_relation_persona_input(source_id)`.
- **Script:** `.claude/skills/daa-extract/scripts/relation_persona_extract.py` (ren funktion + CLI).
- **Spænd:** påstanden skal citere **præcis én** klausul, og `raw` skal forekomme **præcis én gang**
  i dens `verbatim_text`; ellers `parkeret: flere_klausuler | ikke_ordret | tvetydigt_spaend`.
  Spændet angives 0-baseret og halvåbent mod `source_observation.verbatim_text` — samme konvention som
  mention-triggeren (`substr(text, char_from+1, char_to-char_from)`).
- **Post-relativ position:** `post_offset = klausul.post_char_from + spændstart` — klausulens
  post-relative koordinat (schemaet dokumenterer, at rendition-absolut `char_from` ikke kan oversættes
  til helpostens whitespace-foldede tekst: 494 af 591 poster afviger). Klausulen skal tilhøre postens
  gældende klausulsæt. Positionen afhænger kun af helpostens tekst, ikke af klausul- eller
  fortolknings-id'er.
- **Entydighed:** sorteringsnøglen er (`post_offset`, spændlængde, prædikat, `interpretation_key`
  `COLLATE "C"`); to påstande med samme prædikat, `post_offset` og spændlængde er uadskillelige
  dubletter og parkeres begge (`dublet`).
- **Ægteskabsnummer:** rang efter den fulde sorteringsnøgle (nedenfor) blandt **alle** postens
  ægteskabs-påstande, også de parkerede, så numrene ikke flytter sig, når parkeringsreglerne ændres.
- **Navn (kun ægteskab):** stykket efter en indledende ægteskabsmarkør til første markør for fødsel,
  død, forældre eller afslutning. Markørsættet er en versioneret profil
  (`relation-persona-2018-20-v1`), fastlagt i planens første task ud fra målte mønstre (kun tal).
  Intet navn eller tvetydige markører → `parkeret: <grund>`.
- **År (kun ægteskab):** firecifret tal umiddelbart efter en fødsels- hhv. dødsmarkør **inden for
  ægtefællens eget segment** (før første forældremarkør), så forældres eller hovedpersonens år ikke
  tages med. Det rå udsnit gemmes.
- **Børn/forældre:** ingen persona og intet navn; kun spænd og `post_offset`.
- **Output:** hash-bundet rækkefil (præcis id-mængde). CLI'en printer kun tal og hashes.

### 5.2 Writer-operation `relation_persona`

Ny operation i den generelle writer (#153). Rammen udvides for **alle tre** nye operationer
(`relation_persona`, `relation_person_create` §8.4, `relation_disposition` §8.2) samme steder:
`reimport_event_operation_check`, nøglelisten i `validate_reimport_authorization_payload`,
elementpræfiks, `red_finalize_reimport` (observed = expected for hver nøgle) og
`red_reimport_batch_result`. Den levende validator kræver, at summen af expected-counts er lig antallet
af autoriserede elementer; derfor har hver operation **én operationstæller** (antal elementer med
præfikset), og delrækkerne tælles **ikke** som expected-counts, men udledes ved finalisering af
elementernes versionerede `result_receipt` (id-arrays) og efterprøves mod databasen (distinct id'er,
antal, at hver række findes og hører til batchen). Autorisationspayload og receipt-skema står i §5.2.1; kontrakten er 1 autoriseret element → 1 event →
1 receipt.

Operationstællere og receipts:

| Operation | Elementpræfiks | Operationstæller | Receipt pr. element (efterprøves ved finalisering) |
| --- | --- | --- | --- |
| `relation_persona` | `rp:` | `relation_personas` | persona, mention, år-fortolkninger, parter |
| `relation_person_create` | `rpc:` | `relation_person_creates` | person, fact, assertion, citation, conclusion, familie (ny eller eksisterende), alle `family_member`-rækker, identitetsversion |
| `relation_disposition` | `rd:` | `relation_dispositions` | observation, dispositionsversion |

Batchen for `relation_persona` opretter sin egen `extraction_run` (kræves af
`source_persona.created_run_id` og `source_mention.created_run_id`).

#### 5.2.1 Writer-kontrakt (autorisation, receipt, efterprøvning)

Fælles: elementets autorisationspayload må kun have de nævnte nøgler (ukendt eller manglende nøgle ⇒
afvist). **Event-envelope** som det levende `interpretation_proposal`-mønster:
`reimport_event.payload = autorisationspayload || {"result_receipt": <receipt>}` og
`after_sha256 = private.reimport_canonical_json_sha256(<receipt>)`. Finalizeren læser receiptet fra
`payload->'result_receipt'`, genberegner hashen og kræver lighed med `after_sha256`. `result_receipt`
har præcis de nævnte nøgler plus `schema`; alle arrays er sorteret (`ORDER BY … COLLATE "C"` på tekst,
numerisk på id'er).
Kanoniske rækker har ingen `batch_id`; tilhørsforholdet bevises derfor ved finalisering med de angivne
joins, og hvert id må optræde i præcis ét receipt i hele batchen (batchglobal distinct-kontrol).

**`relation_persona`** — element-id `rp:<interpretation_key>`.

- Autorisation: `interpretation_key`, `interpretation_version`, `predicate`, `clause_observation_id`,
  `clause_set_seq`, `clause_set_sha256`, `post_offset`, `span_from`, `span_to`, `marriage_ordinal`
  (null for child/parent), `name_from`, `name_to`, `birth_raw`, `death_raw` (null når ikke
  ægteskab/intet år), `profile` (`relation-persona-2018-20-v1`).
- Receipt (`schema: relation-persona-receipt-v1`): `principal_source_persona_id` og
  `spouse_source_persona_id` (serverudledte, aldrig fra autorisationen; spouse null for
  child/parent), `mention_id` (null for child/parent), `year_interpretation_ids` (array, 0–2),
  `party_keys` (array af `[interpretation_key, party_role, version]`).
- Efterprøvning: persona og mention har `created_run_id` = batchens `extraction_run`; mentionens spænd =
  (`name_from`, `name_to`) på `clause_observation_id`; år-fortolkningerne har batchens
  `extraction_run_id`, `source_persona_id` = receiptets persona og citerer klausulen; partsrækkerne har
  `origin_ref` = batch-id og den autoriserede `interpretation_key`; principal-parten er den
  serverudledte hovedperson.

**`relation_person_create`** — element-id `rpc:<source_persona_id>`.

- Autorisation: `source_persona_id`, `identity_version` (den gældende `unresolved`/`new_person_needed`),
  `principal_person_id`, `marriage_ordinal`, `family_mode` (`existing`|`new`), `family_id` (kun ved
  `existing`), `name_text` (= mentionens ordrette tekst), `citation_label`.
- Receipt (`schema: relation-person-create-receipt-v1`): `person_id`, `fact_id`, `assertion_id`,
  `citation_id`, `conclusion_id`, `family_id`, `family_member_keys` (array af
  `[family_id, person_id, rolle]`; ved `new` både hovedperson og ny person, ved `existing` kun den nye),
  `identity_version`.
- Efterprøvning: `person.staged = true`, `levende = true`, `visning_navn` afledt; `fact` har
  `subjekt=('person', person_id)` og `faktatype='navn'`; `assertion` peger på `fact_id` med
  `vaerdi_tekst = name_text`; `citation` har `assertion_id`, `source_id` = batchens kilde, `side` = klausulens
  side og `citat_tekst = citation_label` (postnøgle + side; tabellen har ingen klausulkolonne — klausulen
  er bundet gennem personaens mention); `conclusion`
  på `fact_id` vælger `assertion_id`; hver `family_member_key` findes med rolle `partner` og
  ordenstallet; identitetsrækken for personaen har version = `identity_version`, status `accepted`,
  mål `person_id`, oprindelse `relation_person_create` og `batch_id` i evidensen; personen har en
  forbrugt kvittering i samme transaktion (5a).

**`relation_disposition`** — element-id `rd:<observation_id>`.

- Autorisation: `observation_id`, `from_disposition_version`, `interpretation_keys` (alle påstande, der
  citerer klausulen med `afventer_identitet`; alle skal være afgjort).
- Receipt (`schema: relation-disposition-receipt-v1`): `observation_id`, `disposition_version`.
- Efterprøvning: dispositionsrækken har version `from_disposition_version + 1`, `fortolkning_foreslaaet`,
  `batch_id` og manifestets sha256 i evidensen, og den forrige version var maskinel (aldrig oven på
  menneskelig).

**`red_reimport_batch_result`** bevarer sin eksisterende form (`batch_id`, `status`, `replayed`,
counts) og tilføjer for batches med de nye operationer nøglen `relation_results`: et array sorteret på
`operation` af `{operation, elements, receipts_sha256, derived_counts}`, hvor `receipts_sha256` =
sha256 af de sorterede `after_sha256` og `derived_counts` = antal pr. receipt-id-felt.

Pr. element, i batchens transaktion:

- **Hovedpersonen udledes af serveren, ikke af rækkefilen:** den persona, der har postens accepterede
  `principal_member`-placering og en gældende `accepted` identitet. Mangler den, afvises elementet.
- **Ægteskab:** `source_persona` med `persona_key = <postnøgle>#rel-marriage-<post_offset>-<spændlængde>`;
  `source_mention` (`mention_kind='person'`, navnespændet; triggeren efterprøver det ordret);
  `source_persona_mention` (rolle `spouse`); `person.birth`/`person.death` på personaen, når der er år:
  `derivation_kind='deterministic'`, `status='proposed'`, `method='relation-persona-v1'`, værdi =
  **skalar streng** med det rå udsnit (som 5a's inputfunktion læser med `value #>> '{}'`), citerer
  klausulen.
- **Parter:** `principal` for alle tre prædikater; `spouse` for ægteskab. Børn/forældre får deres
  modpart først ved afgørelsen (§8.3).
- Eventet binder autorisationens `interpretation_key`, `post_offset`, `marriage_ordinal` og spænd, og
  receiptet de serverudledte principal- og spouse-personas (§5.2.1). Kernen (§6.2) læser begge.

Idempotent på `persona_key` med samme payload; anden payload på samme nøgle ⇒ fail-closed. Ændrer en
ny profil spændet, giver det en ny nøgle og en ny persona; den gamle personas parter afløses (§5.3), og
personaen bliver stående som evidens (append-only).

### 5.3 Ny tabel `private.interpretation_party` (append-only, versioneret)

```
interpretation_key  uuid    -- stabil på tværs af fortolkningens versioner
party_role          text    CHECK IN ('principal','spouse','child','parent')
version             integer CHECK (version >= 1)
source_persona_id   uuid    → private.source_persona(id)  (NULL = afløst)
marriage_ordinal    integer (kun for spouse)
post_offset         integer
origin              text    CHECK IN ('relation_persona','relation_decision')
origin_ref          uuid    -- batch_id eller afgørelsens id
created_at          timestamptz
PRIMARY KEY (interpretation_key, party_role, version)
```

- Nøglet på `interpretation_key`, så parterne følger fortolkningen gennem `red_decide_interpretation`'s
  nye versioner (review: tabellen nøglet på `interpretation_id` ville miste parterne ved accept).
- Trigger: samme kilde som fortolkningen; **rolleafhængigt scope** — `principal` og `spouse` skal høre
  til relationens post (via mention/occurrence), mens `child`/`parent` skal være en persona med
  accepteret `principal_member`-placering i en anden post i samme kilde (servervalideret mod den
  entydige familiestruktur af den RPC, der skriver parten, §8.2); tilladte roller pr. prædikat (`marriage`: principal+spouse, `child`: principal+child, `parent`:
  principal+parent); `version = forrige + 1`. View `interpretation_party_current`.
- Append-only-trigger, RLS uden klientpolitikker, ingen grants; med i `db-rls.sql`'s master-array.

## 6. Kandidater og maskinel bekræftelse

### 6.1 Generatoren

`@daa/identity-candidates` udvides; `private.identity_candidate_input` tager ægtefælle-personas med og
tilføjer pr. persona: hovedpersonens person, dennes familier (`family_id`, hovedpersonens
`family_member.ordinal`, partnere, `konfidens`), antallet af ægteskabs-påstande i posten og navn/år.

- Kandidater: **familie-kandidater** (partnere ≠ hovedpersonen; signal `family_partner`,
  `ordinal_match`) før **global top-K** (5a).
- `red_record_identity_candidates` beregner pr. persona **`family_context_sha256`** af serverens
  genberegnede input (familier, partnere, ordenstal, konfidens, identitetsversioner) og gemmer den på
  kandidatrækken. Klienten leverer den ikke.
- **`samme_som`-klynger** (5a-svaghed 1) slås sammen til én kandidat; repræsentanten er partneren i
  familien, ellers laveste id.
- Generatoren sætter `corroboration_eligible` som **sorteringshjælp**; autoriteten er kernens egne
  efterprøvelser (§6.2) og den beståede kontrolkørsel (§7).

### 6.2 Kerne-oprindelse `family_corroboration` — ændrer 5a §4.2

5a besluttede, at ingen oprindelse tillader batch-match ud fra lighed. 5b indsnævrer det med én ny
oprindelse i `private.decide_source_persona_identity`, som **kernen selv efterprøver** — intet tages
fra kalderens `basis`:

- **(a) Proveniens:** personaen er gældende `spouse`-part i en ægteskabs-påstand med gældende status
  `proposed` eller `accepted`, skrevet af en finalized, ikke-fortrudt `relation_persona`-batch, og
  partens række stemmer med eventet: join `interpretation_party_current` (spouse) → event med
  `payload->>'interpretation_key'` = partens nøgle og `payload->'result_receipt'->>'spouse_source_persona_id'`
  = personaen → samme receipts `principal_source_persona_id` = gældende `principal`-part, og eventets
  `marriage_ordinal`/`post_offset` = partens.
  `principal`-personaen har postens accepterede `principal_member`-placering og en gældende `accepted`
  identitet.
- **(b) Struktur, talt af kernen:** antallet af ikke-afviste ægteskabs-påstande i posten = antallet af
  familier, hvor hovedpersonen er partner; familien vælges ved hovedpersonens
  `family_member.ordinal = marriage_ordinal` (NULL-ordenstal er kun tilladt ved præcis én familie);
  familien har præcis én partner ≠ hovedpersonen, og det er målpersonen; `konfidens` er ikke
  `omstridt` eller `formodet` (invariant 7); ingen anden persona i posten har gældende `accepted`
  identitet til målpersonen.
- **(c) Kandidat:** `candidate_id` er rang 1 for personaen i kildens **gældende** kandidatkørsel, peger
  på målpersonen, og kernen genberegner `family_context_sha256` nu og kræver lighed med den gemte
  (ændret familie eller identitet siden kørslen ⇒ afvist).
- **(d) Autorisation:** kaldet sker under en **bestået kontrolkørsel** (§7) for samme kandidatkørsel.
  Navnelighed kan kernen ikke beregne; den er autoriseret af stikprøven, ikke af kalderen.

**Låseprotokol (TOCTOU) — Postgres' egne rækkelåse, ingen ændring af andre writere.** Familier
kan ændres ad mange veje (familie-RPC'er, `red_flyt_barn`, `red_set_familie_ordinal`,
`red_vaelg_foraeldre`, change_set-undo, scripts). I stedet for at integrere en advisory-lås i dem alle
låser de nye RPC'er selve rækkerne, så enhver anden vej venter:

- **personrækker** (`SELECT … FROM person … ORDER BY id FOR UPDATE`) for hovedperson, målperson og —
  ved en identitetsændring — både gammelt og nyt mål. Det blokerer også enhver ny `family_member`-række,
  der peger på personen, fordi fremmednøglens kontrol tager `FOR KEY SHARE` på personrækken
  (`family_member.person_id REFERENCES person(id)`), og det konflikter med `FOR UPDATE`; samme for
  `red_slet_person`;
- **familie- og medlemsrækker** (`FOR UPDATE`, sorteret på id) for alle hovedpersonens og målpersonens
  familier — blokerer `UPDATE`/`DELETE` af ordenstal, konfidens og medlemskab ad enhver vej.

**Én total låseorden** for alle 5b-RPC'er og kernen: writer-/kildelås (som i dag) → kontrolkørslens
lås (§7.2) → persona- og identitetsrækker (sorteret) → personrækker (sorteret) → familierækker
(sorteret) → `family_member`-rækker (sorteret) → genberegning af (b)/(c) → skrivning. Eksisterende
writere tager ingen nye låse, så den eneste mulige konflikt er en Postgres-detekteret deadlock mod en
ældre vej; den ruller transaktionen tilbage (fail-closed, falsk STOP). Kernen låser selv personaens
identitetsrække (som i dag) og både gammelt og nyt mål.

**`samme_som` er ikke en del af kernens efterprøvelse.** Klyngesammenlægningen (§6.1) påvirker kun
kandidatvisningen; kernens (b) bruger alene `family_member`, og målet er familiens partner-id.
`family_context_sha256` omfatter derfor familier, partnere, ordenstal, konfidens og identitetsversioner,
ikke `samme_som`-topologien.

Kræver `accepted` og forventet version 0. Alle andre lighedsmatch forbliver lukkede; kernen har
fortsat ingen grants, og kalder-allowlisten (`test_identity_guard_static.py`) udvides med præcis den
nye RPC. Posten i `docs/decisions.md` skrives, når specen er godkendt.

### 6.3 RPC `red_corroborate_family_identities(p_control_run_id uuid, p_expect_set_sha256 text)`

Rollegatet (redaktion). Tager kildelåsen **eksklusivt**, så ingen menneskelig afgørelse i kilden
(der tager den delt) kan ske mellem genvalidering og skrivning. Serveren:

1. kræver, at kontrolkørslens **seneste** status er `passed`, at den hører til kildens gældende
   kandidatkørsel, og **genvaliderer alle stikprøvens gældende afgørelser** (§7.2) under låsen umiddelbart
   før skrivning — ved afvigelse skrives et `failed`-event, og kaldet returnerer uden maskinelle
   skrivninger;
2. finder selv de egnede personas (rang 1, uden gældende afgørelse, ikke i stikprøven);
3. kræver SHA-256 af den sorterede persona-id-mængde = `p_expect_set_sha256` — **mængde, ikke
   antal**; drift ⇒ `IDENTITY_CORROBORATION_SET_DRIFT`, intet skrives;
4. kalder kernen for hver; ét afvist krav ⇒ hele kaldet ruller tilbage.

Evidens: `{basis:'family_corroboration', run_id, candidate_id, family_id, ordinal, control_run_id,
family_context_sha256, method:'family-corroboration-v1'}`. Aktøren er redaktøren, der kører RPC'en.

### 6.4 Kandidatvisning (5a-svaghed 3)

Detalje-RPC, ark og webkø viser pr. kandidat titler og embeder (gældende konklusioner), postnøglen på
kandidatens egen persona (hvis nogen) og — uden for stikprøven — familie og ordenstal.

### 6.5 1939-årstal (5a-svaghed 2)

Kun med, hvis planens måling viser, at globale kandidater for parkerede eller nye sager rammer
1939-personer uden udfyldt dato. Ellers åbent punkt til trin 6.

## 7. Kontrolkørsel, ark og webkø

### 7.1 Kontrolkørslen er serverens

Ny tabel `private.identity_control_run` (append-only status-events) med `private.identity_control_sample`:

- **To serverberegnede populationer:** (1) *identitet* — kandidatkørslens egnede ægtefælle-personas;
  (2) *relation* — gældende `relation.child`/`relation.parent`-påstande med præcis én strukturel
  kandidat-familie (§8.3). Kontrolkørslen gemmer begge populationers mængde-hash.
- **Tre skridt, serveren først:**
  1. `red_register_identity_control_run(p_candidate_run_id)` — **serveren vælger stikprøven selv** i
     `private.identity_control_sample` (polymorf: `sample_kind` ∈ `identity` med `source_persona_id`,
     `relation` med `interpretation_key`+version), stratificeret (identitet: én familie / flere
     familier; relation: ét stratum). Størrelse pr. population: `min(N, max(10, ceil(0,1·N)))`,
     fordelt proportionalt på ikke-tomme strata (mindst én pr. stratum), deterministisk orden
     `sha256(candidate_run_id || id)`. **Serveren gemmer også den blinde mapping** pr. stikprøvesag:
     visningsplads `1`–`3` → `candidate_id` (identitet) hhv. `family_id` (relation), blandet
     deterministisk med `sha256(control_run_id || sample_id || candidate_id)`. Klienten kan ikke vælge,
     udelade eller ombytte noget.
  2. Rækkefil og ark genereres fra serverens stikprøve og mapping (læst via en rollegatet RPC) plus
     uoverensstemmelserne.
  3. `red_seal_identity_control_run(p_control_run_id, p_sheet_sha256, p_rows_sha256)` forsegler ark og
     rækkefil, før noget afgøres; en forseglet kørsel kan ikke forsegles igen.
- **Stikprøvesager afgøres med visningsplads, ikke id.** For en sag i en aktiv kontrolkørsel kræver
  `red_afgoer_source_persona` og `red_afgoer_relation_interpretation` altid `control_run_id` og
  forseglingskonteksten (`sheet_sha256`, `rows_sha256`, linje) og håndhæver betingede inputregler:
  - `same` (token `1`–`3`): kræver `display_position`, forbyder klientleveret `candidate_id`/`family_id`;
    serveren **opløser selv** målet via den gemte mapping;
  - `X`, `U`, `N`: forbyder `display_position` og mål; registreres som afvigelse;
  - `P <id>`: forbyder `display_position`, kræver det eksplicitte person-id; registreres som afvigelse.
  Evalueringen (§7.2) sammenholder afgørelsen med den gemte mapping.
- Arket bygges fra rækkefilen, som indeholder netop stikprøven og alle uoverensstemmelser.

### 7.2 Status: `not_ready`, `passed`, `failed`

`red_evaluate_identity_control_run(p_control_run_id)` under kildelåsen:

- **`not_ready`** (intet event), så længe en stikprøvesag er uafgjort.
- **`passed`**, når for **begge** `sample_kind` hver stikprøvesags gældende afgørelse er truffet efter
  forseglingen med `basis: human_sheet`, kontrolkørslens eksakte `sheet_sha256` **og** `rows_sha256`,
  den samplede version og et mål opløst af serveren fra den gemte mapping; identitetssager med `action = same` og `candidate_id` = rang 1 i samme kørsel,
  relationssager `same` til den familie, maskinen ville vælge; og kandidatkørslen stadig er gældende.
  `web_detail` kan ikke opfylde kriteriet. `red_afgoer_relation_interpretation` gemmer og validerer
  samme arkkontekst som 5a's identitets-RPC.
- **`failed`** ved en faktisk afvigelse — anden kandidat, `X`, `U`, `N`, `P <id>`, anden familie.
- **Den seneste status er autoritativ.** Evaluering og begge maskin-RPC'er (§6.3, §8.2) tager
  kildelåsen eksklusivt og kontrolkørslens række `FOR UPDATE`, låser alle samplede identitets- og
  fortolkningsrækker (sorteret) og genvaliderer stikprøven umiddelbart før skrivning; de menneskelige
  afgørelses-RPC'er tager kildelåsen delt og kan derfor ikke interleave; en ændret stikprøveafgørelse efter `passed` giver et
  `failed`-event og ingen maskinelle skrivninger. En `failed` kørsel kan ikke bestå igen.
- **Stopregel:** kun en bestået kørsel autoriserer `family_corroboration` (§6.2 d) og maskinel
  relationsafgørelse (§8.2) — og kun for sager i kørslens egne populationer (mængde-hash). Ved fejl går
  sagerne til mennesket, eller profilen revideres → ny kandidatkørsel → ny kontrolkørsel.

### 7.3 Ark

5a's `identity_decision_sheet.py` med dets tokens: `1`–`3` (kandidat), `X` (anden person), `U`, `N`,
`P <id>`. Udvidelser:

- **Blinde stikprøvelinjer:** kandidaterne i deterministisk blandet orden, uden score, tier, signaler
  og familiemarkør — kun navn, år, titler, embeder og egen postnøgle, i serverens blandede orden
  (§7.1); tokenet er visningspladsen, som serveren opløser.
- **Uoverensstemmelseslinjer:** kontekst (hovedpersonens postnøgle, ægteskabsnummer, grund) og fuld
  visning (§6.4).
- **Relationslinjer** (børn/forældre, §8.3): `R <interpretation_key> <version> : <1-3|U>` med
  familie-kandidater; afgøres gennem `red_afgoer_relation_interpretation`.
- Overstiger arket 80 linjer, deles det i flere hash-bundne ark i rækkefølge, alle under samme
  kontrolkørsel.

### 7.4 Webkø

Kildepersona-køen kan filtrere på `spouse` og viser familiekonteksten (§6.4). Beviset er paritet som i
5a (payload fastlåst i vitest → psql → feltsammenligning); der findes ingen lokal Supabase-API. **Den
første levende webkø-afgørelse** er et eksplicit punkt i 5b's prod-overførsels-spec.

## 8. Afgørelse og binding af relationer; nye personer

### 8.1 Strukturel binding — ny DDL

- **Regeltype:** `private.interpretation_promotion_rule` får `rule_mode` ∈ `text_assertion`
  (eksisterende) | `structural_family`, med gensidigt udelukkende CHECKs: `structural_family` kræver
  `interpretation_kind='relation'`, `target_type='family'`, `expected_fact_type IS NULL`,
  `value_kind='relation'`; `text_assertion` bevarer dagens krav. Valideringstriggeren,
  `private.add_interpretation_promotion_rule_version` (signatur med `rule_mode`, revokes) og det
  promoverbare views kontrakt udvides tilsvarende. Regler: `relation-marriage-v1`,
  `relation-child-v1`, `relation-parent-v1`.
- **Ny RPC `red_promote_relation_interpretations_batch(p_items jsonb, p_preview_sha256 text)`** (ikke
  en udvidelse af den eksisterende, der kun kender assertion-mål). Pr. element efterprøves: gældende
  fortolkning `accepted`; gældende parter; begge parters identiteter `accepted`; præcis én familie med
  strukturen (ægteskab: begge partnere; barn: principal partner + child `barn`; forælder: principal
  `barn` + parent partner); `konfidens` ikke `omstridt`. Låseorden: den totale orden i §6.2 (fortolkningsrækker
  på personaernes plads). Previewhash som den eksisterende batch-RPC. Skriver `interpretation_promotion` med
  `target_type='family'` og evidens `{family_id, vielse_fact_id|null, party_versions}`.
- Ingen familie eller flere ⇒ ingen binding, talt med grund.

### 8.2 Afgørelse af relationspåstanden

- **Maskinelt:** `red_decide_relation_interpretations(p_control_run_id, p_expect_set_sha256)` —
  autoriseret af en bestået og genvalideret kontrolkørsel (§7.2); børn/forældre kun fra kørslens
  relationspopulation, ægteskaber kun hvor ægtefællens identitet er afgjort. Accepterer
  relationspåstande, hvor begge parter har
  `accepted` identitet og strukturen er entydig (§8.1), ved at kalde `red_decide_interpretation`'s
  kerne med `method: family-structure-v1`; mængde-hash som §6.3. For børn/forældre skriver den
  modpartens part (`origin: relation_decision`).
- **Menneskeligt:** `red_afgoer_relation_interpretation(p_interpretation_key, p_expected_version,
  p_action, p_family_id, p_context)` — `same` (med familie) eller `unresolved`; skriver modpartens part
  og afgørelsen; `basis: human_sheet | web_detail`.
- **Klassifikation:** ny `relation_control_classification.sql` (den eksisterende klassifikation
  filtrerer på assertion-regler og kan ikke genbruges).
- **Klausul-disposition:** sættes først, når alle påstande, der citerer klausulen med
  `afventer_identitet`, er afgjort; skrives af en afsluttende writer-operation `relation_disposition`
  (maskinel disposition kræver `manifest_sha256` + `batch_id`), og aldrig oven på en menneskelig
  disposition.

### 8.3 Børn og forældre (24 påstande)

Ingen ny persona. Modparten findes strukturelt blandt kilde 1's hovedpersoner: `relation.child` —
hovedpersonen er partner i en familie, og en anden hovedperson er `barn` i den; `relation.parent` —
hovedpersonen er `barn` i en familie, og modparten er partner i den. Præcis én kandidat-familie ⇒
egnet til maskinel afgørelse (§8.2) og med i kontrolkørslens relationspopulation (§7.1); ellers en relationslinje i
arket (§7.3).

### 8.4 Nye personer (`N`)

`N` afgør identiteten som `unresolved` med `reason: new_person_needed` (5a, menneskelig oprindelse).

- **Ny kerne-oprindelse `relation_person_create`:** kræver, at den gældende afgørelse er `unresolved`
  med `reason: new_person_needed` og `basis` ∈ `human_sheet`, `web_detail`; forventet version = den
  gældende (ikke 0); personaen er gældende `spouse`-part (§6.2 a); oprettelseskvittering i samme
  toptransaktion. Den almindelige `person_create`-gren (version 0) ændres ikke.
- **Ny writer-operation `relation_person_create`** (ikke en udvidelse af `person_create`, som kræver
  `person_external_id` og placering og ville kollidere med hovedpersonens post). Pr. sag, atomisk:
  1. `insert_person_with_receipt(staged => true, visning_navn => NULL)`;
  2. **`levende` sættes eksplicit til `true`** (invariant 8, fail-closed). Ægtefællens
     `person.death`-fortolkning er kun `proposed` og må ikke bruges som dødsafgørelse; `levende`
     genberegnes først, når dødsfakta får en promotionregel med menneskelig afgørelse (åbent punkt 3);
  3. navnekæden **fact (`navn`) → assertion → citation (kilde, side, label med postnøgle) → conclusion** efter mønstret
     i name-completion-writeren, derefter efterkontrol af at `visning_*` er afledt (invariant 4);
  4. familieplads: har hovedpersonen præcis én familie med kun én partner og passende ordenstal,
     indsættes personen dér som partner; ellers ny familie (`type='vielse'`) med hovedpersonen og den
     nye person, ordenstal = `marriage_ordinal`. Familie-id: planens første task måler driften
     (`schema.sql` uden default, `db-migrations.sql` indsætter uden id) og retter den med en
     identity/sekvens-migration; indtil da ingen familieoprettelse;
  5. identitet med `relation_person_create` og kvittering;
  6. kvittering med alle id'er (person, fact, assertion, citation, conclusion, familie, family_member).
- Personen forbliver `staged`, til prod-overførslen afgør aktiveringen. Kun navn og familieplads;
  fødsels-/dødsfakta er en senere promotionregel.

### 8.5 `mention.person`

De 20 parkeres og tælles; ingen persona i 5b.

## 9. Privatliv

Ingen modelkald. Scripts printer kun tal og hashes. Arket bærer navne og læses kun af projektejeren
(5a's regler: privat mappe 0700, filer 0600, aldrig til en model). Nye personer er `staged` og
fail-closed `levende` (§8.4). Nye tabeller og RPC'er får RLS/ACL og står i `db-rls.sql`'s lister og
`db-verify.sql`'s ACL-drift-asserts; nye `red_*`-funktioner defineres før `$public_red_revoke$` (149b's
mønster).

## 10. Færdigbevis (i restore, ikke i prod)

Arbejdsbase: kopi af `daa2018f_20261001133125`, løftet med `db-migrations.sql` + `db-rls.sql`
(5a + 5b). Rapport `docs/evidensbaseret-genimport/relationspersonas-5b-bevis.md` — kun tal, hashes og
basenavne.

1. Udtræk: personas, parkerede pr. grund, 0 værdier i log.
2. Kalibrering: egnede, uoverensstemmelser, navnelighedsfordeling — rapporteret som næsten
   selvbekræftende (§4).
3. Kontrolkørsel registreret; ark + stikprøve afgjort af projektejeren; kørslen evalueret.
   **Negativtests:** bekræftelse før registrering, ved `not_ready`, efter én afvigelse, og efter en
   ændret stikprøveafgørelse oven på `passed` afvises (begge maskin-RPC'er).
4. Maskinel bekræftelse: antal, mængde-hash; 0 skrivninger ved mængde-drift og ved ændret
   familiekontekst (negativtests).
5. Nye personer: antal, `staged`, `levende = true` for alle, familieplads, navnekæde, kvitteringer.
6. Relationsafgørelser og bindinger: ægteskaber/børn/forældre bundet, ubundne pr. grund, intet
   kanonisk delta ud over nye personer, familier og navnekæder.
7. Webspor-paritet (§7.4).
8. Restore af arbejdsbasens dump før 5b-kørslen gendanner tilstanden eksakt (§13).

## 11. Test

- **SQL** (CI's friske schema-sti): `interpretation_party` (append-only, versioner, roller pr.
  prædikat, rolleafhængigt post-scope — `child`/`parent` fra anden post godtages, fremmed `spouse`
  afvises — overlever `red_decide_interpretation`); `relation_persona` (rammeudvidelserne,
  principal udledt af serveren, ordret spænd, idempotens, anden payload afvist); `family_corroboration`
  med hvert af (a)–(d) negativt, herunder `count_mismatch`, NULL-ordenstal ved flere familier,
  `omstridt`, dobbelt mål i posten, ændret familiekontekst, ikke-bestået kontrolkørsel; låseprotokollen (to-sessionstests: samtidig
  `red_tilfoej_partner`, `red_set_familie_ordinal`, change_set-undo og menneskelig om-afgørelse venter
  eller fejler lukket mellem genvalidering og skrivning; deadlock ruller tilbage); kontrolkørslen (to populationer, `not_ready` uden event,
  seneste status autoritativ, stale efter ændret stikprøveafgørelse, størrelse ved N < 10, serverens udvalg,
  ingen genoplivning af `failed`); mængde-drift; kildelås; `structural_family`-
  constraints og den nye promotion-RPC (én familie, ingen, flere); `relation_person_create`-oprindelsen
  (kun menneskelig `N`, version = gældende) og writeren (`staged`, `levende = true` også ved proposed død, navnekæde, `visning_*`,
  familie); familie-id-migrationen; funktionsflade og ACL-lister.
- **Pytest:** udtrækkets parser på syntetiske eksempler (alle parkeringsgrunde, år i forældresegment
  tages ikke); arkets blinde stikprøvelinjer (blanding, ingen signaler), relationslinjer, hashbinding.
- **Vitest:** familiesignal, `ordinal_match`, klyngesammenlægning, egnethed, deterministisk
  output/hash; webkøens filter og visning.
- Statisk test af kernens kalder-allowlist (`test_identity_guard_static.py` udvides).
- `get_advisors` efter DDL. Hele CI-jobbet køres lokalt før push.

## 12. Søm og rækkefølge (til planen)

- **Task 0 (måling, intet skrives):** udtrækkets mønstre (kun tal), familie-id-driften,
  uoverensstemmelsernes forventede antal, behovet for 1939-årstal (§6.5).
- **Del 1 — identitet:** `interpretation_party`, `relation_persona` med rammeudvidelser, generator og
  `family_context_sha256`, kontrolkørsel, `family_corroboration`, ark, webkø.
- **Del 2 — binding:** `structural_family`-regler og promotion-RPC, relationsafgørelser,
  `relation_person_create` (oprindelse + writer + familie-id), disposition, færdigbevis og rapport.

Bliver planen længere end 5a's, skrives den som to planer, der udføres i rækkefølge.

## 13. Prod og fortrydelse

5a deployes først (egen ceremoni, skrivepause for webkøen). 5b's DDL og data går til prod gennem en
separat overførsels-spec som trin 4, inkl. første levende webkø-afgørelse og aktivering af nye
personer.

**Fortrydelse er restore-only**, som for 4.1c og 4.4 (`docs/decisions.md` 2026-09-17 og
2026-09-23): evidensen er append-only, identitetshændelser har fremmednøgle til personen, og
`red_reverse_reimport` kender kun `person_create` med name-completion. En writer-reversal for
`relation_persona`/`relation_person_create` bygges ikke i 5b. Rettelser i drift sker fremad gennem
kernens **menneskelige** oprindelse (`red_afgoer_source_persona` med gældende version, `basis`
`web_detail`/`human_sheet`), afløste parter (§5.3) og en ny kontrolkørsel; `reversal`-oprindelsen
forbeholdes en faktisk autoriseret writer-reversal (den kræver `reversed_batch_id`). Prod-overførsels-
specen arver fortilfældenes **skrivepause fra backup til `VERIFY_OK`**, så en restore ikke taber senere
skriverier. Fortrydelse af DDL'en er en migration.

## 14. Åbne punkter (registreres, løses ikke her)

1. 1939-årstal i matcheren, hvis §6.5's måling ikke kræver dem — trin 6.
2. `mention.person` (20) — personas for øvrige navngivne.
3. Fødsels-/dødsfakta for nye personer — promotionregel.
4. 1939's ægtefæller — trin 6.
5. Placement-signal (slægt/linje/generation) i matcheren — 5c.
6. Om `family_corroboration` kan generaliseres til familier fra andre kilder (trin 6/7).
7. Writer-reversal for relationsoperationerne, hvis restore-only viser sig utilstrækkelig.

## 15. Review runde 1 (2026-10-06)

Claude (Opus, læser) og Codex (`gpt-5.6-sol`, adversarial) læste specen uafhængigt mod koden. Alle
fund er efterprøvet i `schema.sql`/scripts og godtaget.

| # | Fund | Kilde | Rettelse |
| --- | --- | --- | --- |
| 1 | Stikprøven var ikke serverhåndhævet; RPC'en kunne kaldes før/efter afvigelse | begge | §7.1-7.2 kontrolkørsel; §6.2 d; §6.3 |
| 2 | `N` → `person_create` umulig (version 0 mod unresolved v≥1) | begge | §8.4 ny oprindelse `relation_person_create` |
| 3 | Strukturel promotion findes ikke (kun property→assertion, tekstmatch) | begge | §8.1 `rule_mode`, ny RPC; §8.2 afgørelsesvej + klassifikation |
| 4 | (a)-(c) ikke selvbevisende: `count_mismatch` kun i Node, ordinal i tekst, frit `basis`, status ignoreret | begge | §6.2 (a)-(d), `family_context_sha256`, `marriage_ordinal`-kolonne |
| 5 | `interpretation_party` mistede parter ved ny version | begge | §5.3 nøglet på `interpretation_key`, versioneret |
| 6 | Writer-ramme og reversal udefineret; append-only kan ikke slettes | begge | §5.2 rammeudvidelser; §13 restore-only |
| 7 | Persona-nøgle ikke entydig/stabil (to klausuler, omnummerering) | Codex | §5.1 `post_offset`, præcis én klausul, nummer over alle |
| 8 | Navnekæde henvist til forkert writer; `levende` default `false`; ikke `staged` | begge | §8.4 trin 1-6 |
| 9 | Stikprøven ikke blind (rangorden + signaler i arket) | Claude | §7.3 blinde linjer |
| 10 | Børn/forældre havde ingen afgørelsesvej | Claude | §8.2-8.3, `R`-linjer |
| 11 | `family.id` uden default, drift | Claude | §8.4 trin 4, Task 0 |
| 12 | Principal fra rækkefilen | Claude | §5.2 udledt af serveren |
| 13 | Små: spændkonvention, skalar årsværdi, ark-tokens, disposition, `extraction_run`, nummerering | Claude | §5.1, §5.2, §7.3, §8.2 |

## 16. Review runde 2 (Codex, 2026-10-06)

Codex (`gpt-5.6-sol`) efterprøvede runde 1's rettelser mod koden: NO-GO. Alle fund efterprøvet og
godtaget.

| # | Fund | Grad | Rettelse |
| --- | --- | --- | --- |
| 1 | Relationssager kunne ikke serverudvælges, men blev autoriseret af identitetsprøven | BLOCKER | §7.1 to populationer, polymorf stikprøve; §8.2 kun fra relationspopulationen |
| 2 | `passed` blev ikke stale ved senere ændret stikprøveafgørelse | BLOCKER | §7.2 seneste status autoritativ, genvalidering i begge maskin-RPC'er; §6.3 |
| 3 | `family_context_sha256` lukkede ikke TOCTOU; familie-RPC'erne tager ikke kildelåsen; `samme_som` ikke i hashen | BLOCKER | §6.2 `lock_family_structure`-protokol; §6.1 komponent i hashen |
| 4 | `levende=false` afledt af en `proposed` dødsfortolkning | BLOCKER | §8.4 trin 2: altid `true` til menneskeligt afgjort dødsfakta |
| 5 | Writer-rammen kun specificeret for `relation_persona` | MAJOR | §5.2 tabel for alle tre operationer |
| 6 | `post_offset` brugte rendition-absolut koordinat; ingen dublet-regel | MAJOR | §5.1 `post_char_from`, gældende klausulsæt, sorteringsnøgle, dubletter parkeres; nøglen med spændlængde |
| 7 | Fremadrettet rettelse via `reversal`-oprindelsen kræver `reversed_batch_id` | MAJOR | §13 menneskelig oprindelse; skrivepause fra backup til `VERIFY_OK` |
| 8 | Samme-post-triggeren umuliggjorde `child`/`parent`-parter | MINOR | §5.3 rolleafhængigt scope |
| 9 | Regelversionsfunktionen forblev tekstlåst | MINOR | §8.1 funktion, signatur, view-kontrakt |
| 10 | Tidlig evaluering gav terminal `failed`; stikprøvestørrelse > N | MINOR | §7.2 `not_ready`; §7.1 `min(N, max(10, ceil(0,1·N)))` |

## 17. Review runde 3 (Codex, 2026-10-06)

Codex bekræftede runde 2's fund 4, 7, 8, 9 og 10 som løst; fem fund stod tilbage eller var nye. Alle
efterprøvet og godtaget.

| # | Fund | Grad | Rettelse |
| --- | --- | --- | --- |
| 1 | Relationsstikprøven kunne bestå via `web_detail` eller anden rækkefil; identitetssager bandt ikke `rows_sha256` | BLOCKER | §7.2 begge `sample_kind`: `human_sheet`, sheet- og rows-hash, samplet version, blind mapping |
| 2 | Genvalidering under delt kildelås kunne interleave med menneskelig om-afgørelse | BLOCKER | §6.3 og §7.2: maskin-RPC'er og evaluering tager kildelåsen eksklusivt + kontrolkørsel `FOR UPDATE` |
| 3 | `lock_family_structure` dækkede ikke alle familieveje (ordinal, flyt barn, undo, scripts) og havde ingen total orden | BLOCKER | §6.2 erstattet af rækkelåse (`FOR UPDATE` på person-, familie- og medlemsrækker; FK-`KEY SHARE` blokerer nye medlemmer), én total orden, gammelt og nyt mål låses; `samme_som` ude af kernens efterprøvelse |
| 4 | Writer-tabellen passede ikke til validatorens »sum = antal elementer« | MAJOR | §5.2 én operationstæller pr. operation; delrækker via versionerede receipts efterprøvet ved finalisering |
| 5 | Inputkontrakten leverede ikke `post_char_from` | MAJOR | §5.1 input fra `clause_observation_current` med post-koordinater, klausulsæt-seq og -sha bundet og genvalideret; ægteskabsnummer efter fuld sorteringsnøgle |

## 18. Review runde 4 (Codex, 2026-10-06)

Codex bekræftede runde 3's fund 2, 3 og 5 som løst, herunder at rækkelåsene dækker eksisterende og nye
familie-/medlemsveje, og at den eksklusive kildelås ikke giver deadlock. To fund stod tilbage:

| # | Fund | Grad | Rettelse |
| --- | --- | --- | --- |
| 1 | Den blinde mapping lå kun i rækkefilen; en fejlagtig oversætter kunne sende rang-1-id og bestå | BLOCKER | §7.1 serveren gemmer mappingen; tre skridt (registrér → generér → forsegl); stikprøvesager afgøres med visningsplads, som serveren opløser |
| 2 | Writer-/receipt-kontrakten var udskudt til planen | MAJOR | §5.2.1 autorisation, receipt, hash, efterprøvningsjoins og resultatkort for alle tre operationer |

## 19. Review runde 5 (Codex, 2026-10-06)

Ingen BLOCKER; begge runde 4-fund løst i substansen, men tre kontraktdetaljer manglede:

| # | Fund | Grad | Rettelse |
| --- | --- | --- | --- |
| 1 | Receipts kunne ikke persisteres/læses (payload = autorisation, kun hash i `after_sha256`); resultatkort ufuldstændigt | MAJOR | §5.2.1 event-envelope `payload || {result_receipt}` som `interpretation_proposal`; sorterede arrays; fuldt `red_reimport_batch_result` |
| 2 | Principal/spouse manglede i eventet, som §6.2 (a) efterprøver imod | MAJOR | §5.2.1 serverudledte personas i receiptet; §6.2 (a) eksakt join |
| 3 | Uenighedstokens havde ingen RPC-kontrakt efter mappingrettelsen | MINOR | §7.1 betingede inputregler for `same`, `X/U/N`, `P <id>` |
