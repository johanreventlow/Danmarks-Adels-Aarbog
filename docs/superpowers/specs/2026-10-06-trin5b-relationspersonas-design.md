# Trin 5b — andre personer i posten: ægtefæller, børn og forældre (#151/#150)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-10-06; revideret efter
Codex runde 2 (NO-GO: 4 BLOCKER, 3 MAJOR, 3 MINOR — alle efterprøvet og godtaget, se §16) og
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
  parter: `interpretation_key`, version, prædikat, `raw`, den citerede klausul (id, `verbatim_text`,
  `char_from`), occurrence (`char_from`, postnøgle). Scriptet læser det via den rollegatede
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
- **Ægteskabsnummer:** rang efter `post_offset` blandt **alle** postens ægteskabs-påstande, også de
  parkerede, så numrene ikke flytter sig, når parkeringsreglerne ændres.
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
`red_reimport_batch_result`. Expected-count-nøgler og kvitteringer:

| Operation | Elementpræfiks | Count-nøgler | Kvittering pr. element |
| --- | --- | --- | --- |
| `relation_persona` | `rp:` | `relation_personas`, `relation_mentions`, `relation_year_interpretations`, `relation_parties` | persona, mention, år-fortolkninger, parter |
| `relation_person_create` | `rpc:` | `persons`, `name_facts`, `name_assertions`, `name_citations`, `name_conclusions`, `families`, `family_members`, `identities` | alle id'er (§8.4 trin 6) |
| `relation_disposition` | `rd:` | `clause_dispositions` | observation, dispositionsversion |

Batchen for `relation_persona` opretter sin egen `extraction_run` (kræves af
`source_persona.created_run_id` og `source_mention.created_run_id`).

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
- Eventets payload binder `interpretation_key`, `post_offset`, `marriage_ordinal`, principal- og
  spouse-persona og spændet. Kernen (§6.2) læser det.

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
  genberegnede input (familier, partnere, ordenstal, konfidens, identitetsversioner og den eksakte
  `samme_som`-komponent for hver kandidat) og gemmer den på kandidatrækken. Klienten leverer den ikke.
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
  partens række stemmer med eventets payload (påstand, post, principal, spouse, ordinal, spænd).
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

**Låseprotokol (TOCTOU):** ny `private.lock_family_structure(p_person_ids bigint[])` tager
transaktions-advisory-låse pr. person-id i sorteret orden. Den tages af alle writere, der kan ændre
grundlaget — `red_opret_union`, `red_tilfoej_partner`, `red_tilfoej_barn`, `red_slet_familie_link`,
`red_set_familie_konfidens`, `samme_som`-writeren og kernen ved enhver identitetsafgørelse (for
målpersonen) — og af `family_corroboration`, `red_decide_relation_interpretations`,
`red_afgoer_relation_interpretation`, promotion-RPC'en og `relation_person_create` for hovedperson og
mål(e) **før** den sidste genberegning af (b) og (c). Ændringen af de eksisterende familie-RPC'er er
additiv (én låsning øverst).

Kræver `accepted` og forventet version 0. Alle andre lighedsmatch forbliver lukkede; kernen har
fortsat ingen grants, og kalder-allowlisten (`test_identity_guard_static.py`) udvides med præcis den
nye RPC. Posten i `docs/decisions.md` skrives, når specen er godkendt.

### 6.3 RPC `red_corroborate_family_identities(p_control_run_id uuid, p_expect_set_sha256 text)`

Rollegatet (redaktion). Tager kildelåsen delt som 5a's afgørelser. Serveren:

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
- `red_register_identity_control_run(p_candidate_run_id, p_sheet_sha256, p_rows_sha256)` —
  **serveren vælger stikprøven selv** i `private.identity_control_sample` (polymorf: `sample_kind` ∈
  `identity` med `source_persona_id`, `relation` med `interpretation_key`+version), stratificeret
  (identitet: én familie / flere familier; relation: ét stratum). Størrelse pr. population:
  `min(N, max(10, ceil(0,1·N)))`, fordelt proportionalt på ikke-tomme strata (mindst én pr. stratum),
  deterministisk orden `sha256(candidate_run_id || id)`. Klienten kan ikke vælge eller udelade sager.
  Kørslen registreres, før arket afgøres, og binder ark- og rækkefilens hash.
- Arket bygges fra rækkefilen, som indeholder netop stikprøven og alle uoverensstemmelser.

### 7.2 Status: `not_ready`, `passed`, `failed`

`red_evaluate_identity_control_run(p_control_run_id)` under kildelåsen:

- **`not_ready`** (intet event), så længe en stikprøvesag er uafgjort.
- **`passed`**, når hver identitetssag har en gældende menneskelig afgørelse (`basis: human_sheet`,
  samme `sheet_sha256`) med `action = same` og `candidate_id` = rang 1 i samme kørsel, hver
  relationssag er afgjort `same` til den familie, maskinen ville vælge, og kandidatkørslen stadig er
  gældende.
- **`failed`** ved en faktisk afvigelse — anden kandidat, `X`, `U`, `N`, `P <id>`, anden familie.
- **Den seneste status er autoritativ.** Begge maskin-RPC'er (§6.3, §8.2) genvaliderer stikprøven
  under låsen umiddelbart før skrivning; en ændret stikprøveafgørelse efter `passed` giver et
  `failed`-event og ingen maskinelle skrivninger. En `failed` kørsel kan ikke bestå igen.
- **Stopregel:** kun en bestået kørsel autoriserer `family_corroboration` (§6.2 d) og maskinel
  relationsafgørelse (§8.2) — og kun for sager i kørslens egne populationer (mængde-hash). Ved fejl går
  sagerne til mennesket, eller profilen revideres → ny kandidatkørsel → ny kontrolkørsel.

### 7.3 Ark

5a's `identity_decision_sheet.py` med dets tokens: `1`–`3` (kandidat), `X` (anden person), `U`, `N`,
`P <id>`. Udvidelser:

- **Blinde stikprøvelinjer:** kandidaterne i deterministisk blandet orden, uden score, tier, signaler
  og familiemarkør — kun navn, år, titler, embeder og egen postnøgle. Rækkefilen mapper visningsplads
  → `candidate_id`.
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
  `barn` + parent partner); `konfidens` ikke `omstridt`. Låseorden: kildelås → fortolkninger →
  familierækker. Previewhash som den eksisterende batch-RPC. Skriver `interpretation_promotion` med
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
  3. navnekæden **fact (`navn`) → assertion → citation (kilde + klausul) → conclusion** efter mønstret
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
  `omstridt`, dobbelt mål i posten, ændret familiekontekst (inkl. `samme_som`), ikke-bestået kontrolkørsel; låseprotokollen (samtidig
  familie-RPC venter, genberegning efter lås); kontrolkørslen (to populationer, `not_ready` uden event,
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
