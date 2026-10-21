# Trin 5a + 5b — 2018-20's identitetsvej, relationspersonas og bindinger i prod (overførsel)

**Status:** designudkast. Godkendt afsnit for afsnit i brainstormen 2026-10-20/21. **Revideret efter Fable-review
runde 1** (2026-10-21; afsnit 1 GO med rettelser, afsnit 2 NO-GO, afsnit 3 GO med rettelser; 1 BLOCKER, 11
MAJOR, 4 MINOR, alle godtaget, to af dem ved projektejerens valg; se §12). Spec'en er ikke et prod-GO: hver
ceremoni kræver sit eget GO (§8). **Runde 2** (2026-10-21; GO med rettelser i alle tre afsnit, 4 MAJOR og 7 MINOR,
alle indarbejdet; se §13).

**Forudsætning:** forudsætningsleddet i §4 (»id'er af indholdet«) får sin egen spec, sit eget review og bliver
merget, før planen for denne overførsel skrives.

**Bygger på:** trin 4's overførsel (`docs/superpowers/specs/2026-10-03-trin4-2018-20-prod-overfoersel-design.md`,
`VERIFY_OK` 2026-10-05) og dens runbook (`docs/runbooks/transfer-2018-20-prod.md`). Dens konventioner for
ceremoni, private scripts, digests (`to_jsonb(…)::text`, `COLLATE "C"`, nøgle i hver hashet række),
tilstandsklassifikation og fortrydelse ved restore gælder, hvor intet andet står. Afsnit, der afviger, er
markeret **(ændret fra trin 4)**.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#150/#151), delspec 5a og 5b for 2018-20 |
| Værdikædeled | Identitetsafstemning (source persona → kanonisk person) og promotion af relationer (binding til familien) i prod |
| Leverancetype | Generel overførselsvej med DDL: forudsætningsled (deterministiske id'er hvor de bærer menneskelige artefakter), DDL-ceremoni, arbejdskørsel, genspilspakke og nøglede digests |
| Redaktionel/læserrettet værdi | Projektejerens ark og webkø-afgørelser fra 5a/5b bliver gældende i prod. Læseren ser kildehenvisningen for ægteskaber, forældrelinjer og børneflokke (253 kilderækker i beviset). Redaktørens identitetskø virker i prod. |
| Færdigbevis | `REHEARSAL_OK` for begge ceremonier og `VERIFY_OK` i prod med alle nøglede digests lig arbejdskørslens (§9) |
| Erstatter | De 8 led i restore-beviskæden som eneste bærer af 5a/5b. #244-spec'ens §10 og `decisions.md` #244 pkt. 5 kræver et valg bevist i restore: arbejdskørslen (§6.2) er det bevis (§3, beslutning 4). |

## 2. Udgangspunkt

- **Beviskæden.** Roden er `daa2018f_20261001133125` (prod-dump 2026-10-01 + den fulde 2018-20-kørsel = prods
  indhold efter overførslen 2026-10-05). Herfra 8 led, hvert en kopi af det forrige, løftet med de da aktuelle
  migrationer: 5a, 5b del 1, 2a, 2b-i, 2b-ii, navneregel v3, 2b-iii, #244. Sidste base er
  `daa244_bevis_20261020222244` (253 bindinger, 0 kanonisk delta i alle led). Alle bevisbaser bevares; de er
  kilden til svaroverførslen (§6.2).
- **Prod er uændret siden 2026-10-05** og står under skrivepause (projektejeren 2026-10-20). Prod har ingen
  5a/5b-DDL.
- **Prod og beviskæden har forskellige tilfældige id'er** (Fable-kortlægningen og -reviewet 2026-10-20/21,
  efterprøvet mod koden):
  - Prods `interpretation.id`, kørsels-, batch- og bindings-id'er stammer fra prods egen ingest 2026-10-05.
    Kun kanoniske id'er, klausulobservationer og 149b-personas er fælles.
  - Nye ægtefællepersonas får `gen_random_uuid()` (`schema.sql:15188`). Kandidat-, kontrol-, stikprøve-,
    batch-, autorisations-, afgørelsesversions- (`schema.sql:8250`) og bindings-id'er er tilfældige.
  - Kontrolprøven i 5b del 1 trækkes efter `sha256(candidate_run_id ‖ persona_id)` og kortenes visning efter
    `sha256(control_run_id ‖ candidate_id)` (`schema.sql:16140`, `:16188`). Prod ville trække en anden prøve.
  - `set_sha256`, `preview_sha256`, `state_sha256` og writer-autorisationen indeholder `interpretation_id`
    og/eller databasens identitet (`current_database()`), som er forskellig i en lokal restore og i prod.
- **Deterministiske nøgler:** `interpretation_key`, ægtefællens `persona_key`
  (`record_key#rel-marriage-<post_offset>-<længde>`, uden ægteskabsnummer; `post_offset` er uændret af #244),
  `interpretation_party` (nøgle, rolle, version) og klassifikationshændelser (nøgle, løbenummer).
- **`db-migrations.sql` er ikke atomar.** Filen ejer #153's egen `BEGIN`/`COMMIT` (linje 11565/12936) og kan
  ikke køres med `--single-transaction` (`docs/database-current-state.md`, apply-proceduren). Sikkerheden er
  idempotens plus backuppen.
- **`db-verify.sql` må ikke køres mod prod** (filens egen advarsel; den seeder midlertidige rækker).
- **En restore i prod giver rettigheder tilbage:** prods `DEFAULT PRIVILEGES` giver genskabte objekter grants
  til `anon`/`authenticated`, som dumpet ikke tager tilbage. Trin 4's `09` afstemmer dem (runbookens
  fortrydelsesafsnit; 415 grants målt lokalt med emulerede default privileges).
- **Web-fladen kører allerede `main`** (Vercel auto-deploy). Læserens kildelinje giver en tom liste, når
  `public_family_sources` mangler (`web/src/data/familySources.ts`). Redaktørens identitetskø fejler, indtil
  DDL'en er deployet, hvilket er uden betydning under skrivepausen.

## 3. Beslutninger

### 3.1 Brainstorm (2026-10-20/21)

1. **Skrivepause og ingen drift.** Prod redigeres ikke, før overførslen er kørt. Afviger prod fra tilstanden
   2026-10-05 eller fra D0/D1 (§5, §6), overføres intet.
2. **Kontrolprøven: id'er af indholdet (valg C).** Fravalgt: A (ny kontrolprøve direkte i prod: øvelsen kan
   ikke forudsige prøven, en fejlet kontrol stopper prod halvvejs, og arkene skal godkendes to gange) og B
   (genbrug af restore-kontrollen som pakke-afgørelser: prod mister mærket »bekræftet maskinelt«).
3. **Øvelsen er facit (ændret fra trin 4).** Facit er en arbejdskørsel med den endelige kode på en restore af
   prods eget dump efter DDL'en (D1), ikke beviskæden. Beviskæden bruges som indholdskontrol (§6.3).
4. **#244 opstår ikke i prod.** Arbejdskørslen regenererer alle persona-manifester med den endelige kode, så
   ægteskabsnumrene er rigtige fra start: ingen rettelse, intet synlighedshul og ingen gamle payloads at
   genspille. Rettelsesvejen (`red_ret_aegteskabsnummer`) deployes, men bruges ikke, og genbindingsvejen med
   `supersedes` er derfor ikke øvet i prod. En beslutningspost noterer, at prod aldrig har haft de 4 fejlnumre.
5. **To ceremonier, hver med sit fortrydelsespunkt (ændret fra trin 4).** DDL-ceremonien har D0 som
   fortrydelsespunkt. Data-ceremonien har D1 og indeholder ingen DDL.
6. **Kun én ny menneskelig opgave.** Svar overføres fra beviskæden via deterministiske nøgler til de
   regenererede ark, og projektejeren godkender hvert regenereret ark efter en linjevis forskelsvisning
   (§6.2). Den nye opgave er kontrolarkets identitetskort (navnefæller og tilfældige): de er en ny, blind
   stikprøve. Kontrolarkets 9 forældrekort (R-linjer) overføres via nøgle.

### 3.2 Efter Fable-review runde 1 (projektejeren 2026-10-21)

7. **Nøglede digests, ikke bytes (ændret fra brainstormen).** Prod sammenlignes med arbejdskørslen på indhold
   pr. nøgle (persona-, fortolknings-, parti-, klassifikations-, stikprøve- og bindingsnøgle). Id-, hash- og
   tidsstempelkolonner udelades efter en eksplicit liste. Deterministiske id'er kræves kun, hvor de bærer et
   menneskeligt artefakt eller stikprøven (§4). Et skridt, der fejler før commit, må køres igen. #153's
   writer og trin 4's afgørelses-RPC, som er `produktionsverificeret` og deles med 1939, røres ikke. Fravalgt:
   byte-identitet (kræver indgreb i de delte, verificerede RPC'er, og en genkørsel ville give fortrydelse).
8. **Modenheden afgrænses.** Oprettelse af nye kanoniske personer (2b-ii `relation_person_create`) har 0
   elementer i hele kæden og er kun bevist syntetisk. Den forbliver `isoleret implementeret`. Overførslen
   påstår `produktionsverificeret` for 5a og for 5b's personas, identiteter, bindinger og børnehenvisninger.
   Et værn kræver 0 oprettelser (§6.2). Beslutningspost i `decisions.md`.

## 4. Forudsætningsleddet: id'er af indholdet (egen spec)

Leddet skal levere følgende. Dets spec fastlægger mekanikken og efterprøver listen mod koden.

1. **Deterministiske id'er, hvor de bærer et menneskeligt artefakt, stikprøven eller en senere skrivning, der
   refererer dem i et ark:** ægtefællepersonas (og deres omtaler), kandidatkørsler og kandidater,
   kontrolkørsel, stikprøve, forældrekort og hændelser. Id'et afledes af kilde-id'et og rækkens indholdsnøgle
   (fx `persona_key`), aldrig af tid eller tilfældighed. Øvrige tilfældige id'er (batch, autorisation,
   ekstraktionskørsel, afgørelsesversion, bindingsbatch, binding) forbliver tilfældige og verificeres på
   nøgleniveau (§7).
2. **Stikprøve og kortvisning** trækkes efter hashes af indhold og konfiguration (fx `input_sha256 ‖
   config_sha256 ‖ persona_key`), ikke efter tilfældige id'er.
3. **Hashes, som et menneske godkender** (rækkefiler, ark), indeholder ikke databasens identitet og ingen
   tilfældige id'er. Arklinjer refererer deterministiske id'er eller nøgler, og **genereret ark-SQL må aldrig
   hårdkode et tilfældigt id**; det slås op på kørselstidspunktet via nøglen (som `relation_marriage_sheet.py`
   allerede gør). Konkret: `spouse_exception_sheet.py`'s `O`-linjer nøgles på `interpretation_key` i stedet for
   den gældende afgørelsesversions `interpretation_id` (`schema.sql:16853-16858`). Leddets spec gennemgår
   hvert arkværktøj (5a-identitetsark, kontrolark, 2b-i-undtagelsesark og -kø, 2b-ii-/v3-ark, børneark,
   nummerark) og lister, hvad hver linje og hver genereret SQL-sætning refererer.
4. **Kollision fejler lukket.** Et deterministisk id, der allerede findes med andet indhold, giver en
   fejlkode, aldrig en stille genbrug.
5. **Ingen ændring af eksisterende rækker eller af delte RPC'er.** 149b-personas, prods `interpretation.id`,
   alt fra trin 4, #153's writer og `red_decide_interpretation` er uændrede.
6. **Opgraderingstest fra prods træ 2026-10-05.** De eksisterende opgraderingstests starter fra senere træer.
   Leddet tilføjer en test, der starter fra det træ, prod faktisk har.

## 5. Fase 0: før DDL

Måles i prod, læse-kun:

- **Ingen ændring siden 2026-10-05:** trin 4's tre digests (`interpretation_transfer_digests.sql`) er lig
  pakkens fra 2026-10-05, og der er 0 `change_set` med `created_at` efter overførslen.
- **Det kanoniske lag** er lig rodbasens (driftsbaselinen `transfer_baseline.sql`).
- **Ingen 5a/5b-spor:** de nye tabeller findes ikke. Postgres er version 15 eller nyere (`family.id` identity,
  2b-ii). `narrative_record_contract_version()` er 2. Der er 587 accepterede 149b-identiteter. Der findes en
  redaktionsprofil. `family.id` er en identitetskolonne i prod (`db-migrations.sql:21953` siger det; det måles).
- **Rettigheder:** et ACL-fingeraftryk (`proacl`, `relacl`, `pg_default_acl` for `public`/`private`) og en
  `has_function_privilege`-matrix for `anon`/`authenticated`/`service_role`/`PUBLIC` gemmes som
  preflight-liste. `get_advisors` gemmes som baseline.
- **Dump D0** tages krypteret (Supabase free tier har ingen backup) og gendannelses-verificeres.
  Restore-hashen (`transfer_restore_hash.sql`) og katalogfingeraftrykket måles straks.

## 6. Faserne

### 6.1 DDL-ceremonien (GO 1) **(ændret efter review)**

DDL'en køres efter den etablerede apply-procedure: hele `db-migrations.sql`, derefter `db-rls.sql` med
`--single-transaction`, derefter `NOTIFY pgrst, 'reload schema'`. `db-migrations.sql` er ikke atomar (§2), så
sikkerheden er idempotens, en øvet afbrydelse og D0.

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | Fase 0 (§5) | nej |
| 2 | **Øvelse** på en restore af D0 med Supabases default privileges emuleret: apply-proceduren, derefter én gang til (idempotens); `db-verify.sql` grøn **her** (aldrig i prod); varigheden måles; katalog- og ACL-fingeraftryk gemmes som forventet efter-tilstand | kun lokalt |
| 3 | **Afbrudsøvelse** på tre punkter: efter #153's `COMMIT`; inde i 5a's cutover-vindue (efter `REVOKE`, før den nye wrapper); mellem en 5b-tabels oprettelse og dens RLS/`REVOKE`. Hver gang køres apply derefter færdig, og resultatet er lig trin 2's fingeraftryk. ACL-porten (`EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED`) må ikke efterlade åbne rettigheder | kun lokalt |
| 4 | **Fortrydelsesøvelse** med netop den kommandofølge, §8 bruger: (a) de nye objekter fjernes **først**, i én transaktion, efter en eksplicit liste udledt af katalogforskellen mellem D0 og trin 2 (`CASCADE` kun på listede objekter; nye tabeller har fremmednøgler til eksisterende, så `pg_restore --clean` ellers ikke kan droppe dem); (b) `pg_restore --clean --if-exists --no-owner --schema=private --schema=public` af D0; (c) grants afstemmes mod preflight-listen som trin 4's `09`; (d) `NOTIFY pgrst, 'reload schema'`; (e) hele `pg_restore`-fejllisten læses, og restore-hash, katalog- og ACL-fingeraftryk skal være lig prods egne fra fase 0 ⇒ `REHEARSAL_OK` (DDL) | kun lokalt |
| 5 | GO 1 | — |
| 6 | **Prod:** apply-proceduren. Derefter en **læse-kun probe**: katalog- og ACL-fingeraftryk lig øvelsens (trin 2), privilegiematrix som forventet, `get_advisors`-delta kun kendte mønstre, `anon` ser 0 private rækker. Fejler apply midtvejs, køres den igen (idempotens, øvet i trin 3); kan det ikke rettes, ⇒ fortrydelse (§8) | DDL |
| 7 | **Dump D1** (krypteret, gendannelses-verificeret); restore-hash og ACL-fingeraftryk måles | nej |

### 6.2 Arbejdskørslen (lokalt, på en restore af D1)

Kæden køres igen led for led med den endelige kode, i beviskædens rækkefølge: 5a → 5b del 1 → 2a → 2b-i →
2b-ii → navneregel v3 (inkl. P-linjens afvisning) → 2b-iii. #244 udgår (beslutning 4). Rækkefølgen er
bindende: 5a's afgørelser skal ligge før del 1's kandidatkørsel 2, og kontrolprøven skal være forseglet før
korroborationen.

- **Manifester regenereres altid** (del 1's personamanifest, 2b-ii's og v3's manifester, dispositionernes
  manifester med `actor_persona_ids`) af den endelige kode. Intet manifest eller payload fra beviskæden
  genspilles.
- **Svaroverførsel:** et script bygger en oversættelsestabel (beviskædens id → nøgle → arbejdskørslens id)
  fra de bevarede bevisbaser og overfører hvert svar via nøglen. Det printer kun tal og hashes. Et svar
  uden mål eller et mål uden svar stopper scriptet, medmindre netop den linje står på listen over forventede
  bortfald (§6.3).
- **Svarene overføres som afklarede værdier, ikke som tokens:** `persona_key` → handling + `person_id`;
  `interpretation_key` → token. Et rangtal (5a's `1/2/3`) peger på den nye kørsels kandidatliste og kan
  derfor ramme en anden person; 5a-svar gengives som eksplicit person eller som rang, der verificeres mod det
  oprindelige `person_id`, ellers stop.
- **Godkendelse:** før et regenereret ark hashes, får projektejeren vist en forskel over **hele de gengivne
  linjer** efter id-oversættelse (også kontekst: viste kandidater, familie, nummer, klausul), ikke kun
  tokens. Ændringer ud over de opregnede bortfald vises og skal accepteres udtrykkeligt. Linjer, der i
  beviskæden blev godkendt med en advarsel, som nu ikke vises (v3's 2 linjer med nummer-OBS), accepteres
  udtrykkeligt igen. Den gamle arkhash, oversættelsestabellen, forskelsrapporten og den nye arkhash bindes i
  GO 2.
- **Kontrolarket (5b del 1):** identitetskortene er en ny, blind stikprøve trukket efter indholdet.
  Projektejeren svarer blindt. Fejler kontrollen, stopper overførslen, og det forelægges som en sag for sig.
  Forældrekortene overføres via nøgle.
- **5a's webafgørelse** (én afgørelse uden ark, `web_detail`) er sit eget skridt med sit eget indhold bundet i
  GO 2.
- **Pakken:** hvert skrivende skridt gemmes i en ordnet pakke med:
  - **type:** `sql` (fast SQL), `writer` (autorisation + begin/apply/finalize som ét skridt) eller
    `hash_gated` (RPC, der kræver en forhåndsberegnet hash);
  - inputartefakter (manifester, rækkefiler og ark med hashes);
  - den forventede indgangs- og udgangsdigest (§7) for de tabeller, skridtet rører;
  - den målte varighed.
  - For `hash_gated` gemmes ikke hashen, men de forventede items (nøgler, familier, klassifikation,
    supersedes). Genspilleren genberegner hashen i basen, sammenligner items med pakken og kalder med den
    genberegnede hash.
  - For `writer` klassificeres tilstanden før autorisationen. Indgangs- og udgangsdigest regnes kun over de
    nøglede tabeller. En genkørsel efter afbrud genbruger en uudløbet `issued`-autorisation for samme manifest,
    eller efterlader den; kun `consumed`-autorisationer tælles (§7).
- **Værn for nye personer:** `relation_person_create_input(1)` giver 0 elementer, og der oprettes 0 personer
  (beslutning 8).
- **#244-værn:** `ORDINAL_BOOK_MISMATCH` rammes 0 gange, `marriage_ordinal_correction_input(1)` er 0, og
  bogens »N°« er lig serverens nummer 40/40.

### 6.3 Indholdskontrol mod beviskæden **(ændret efter review)**

Arbejdskørslen skal reproducere beviskædens indhold på nøgleniveau. Før arbejdskørslen udleder planen en
**nøglet liste over forventede forskelle** fra de bevarede bevisbaser. Den skrives i den private pakke (nøgler
er uuid'er uden navne; listen må gerne nævnes i rapporten med antal). Mindst:

| Mål | Forventet |
| --- | --- |
| Bindinger (`interpretation_key`, familie) | Samme 253 par som `daa244_bevis_…`; ingen `supersedes` fra #244 |
| Ægteskabsnumre i ægtefælleparter (`interpretation_key`) | Lig `daa244_bevis_…`'s gældende numre; de 4 nøgler fra `marriage_ordinal_correction` er rigtige fra start |
| Accepterede identiteter (`persona_key` → person) | Samme mængde |
| Identiteternes oprindelse (`human`/`family_corroboration`) | Må forskyde sig, fordi kontrolprøven er ny; mængden af accepterede er den samme |
| Klassifikationshændelser (nøgle, løbenummer) | Uden de falske `ordinal_afvigelse` for de 4 nøgler og uden de `ordinal_beholdt`-svar, der kun fandtes for dem. Hvilke led og arklinjer det rammer, måles nøglet i bevisbaserne før arbejdskørslen. De 6 ægte afvigelser er uændrede |
| Manifest- og arkhashes | Nye for del 1, 2b-ii, v3 og dispositionerne; v3's payloads udstedes på ny med den nye arkhash; P-afvisningens evidens bærer den nye arkhash |
| 5a's afgørelser | Nye kandidat- og kørsels-id'er i evidensen; samme (persona, person, status) |
| Kanonisk delta | 0 |
| Nye personer | 0 |
| Kildevisning for `anon` | Samme rækker (familie, slags, nøgle) som `daa244_bevis_…` |

Enhver anden forskel stopper arbejdskørslen og forelægges projektejeren. Den løses aldrig stiltiende.

### 6.4 Genspilsprøven (lokalt)

- Pakken genspilles på en **anden, frisk restore af D1** under et andet databasenavn, af genspilleren alene,
  uden menneskelig handling. Alle nøglede digests skal være lig arbejdskørslens efter hvert skridt. Det beviser,
  at pakken er uafhængig af databasens identitet og af tilfældige id'er.
- **Genkørselsprøve:** ét `writer`-skridt og ét `hash_gated`-skridt afbrydes før commit og køres igen. Digesten
  skal være lig pakkens.
- **Fortrydelsesøvelse:** D1 gendannes oven på den genspillede base. Grants afstemmes som i §6.1 trin 4.
  Bagefter er restore-hashen og ACL-fingeraftrykket lig D1's. Data-ceremonien indeholder ingen DDL, så trin
  4's restore-forudsætninger gælder (0 forældreløse rækker, `transfer_restore_preconditions.sql` asserteret).
- Alt bestået ⇒ `REHEARSAL_OK` (data).

### 6.5 Data-ceremonien (GO 2)

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | Indgang: restore-hash og ACL-fingeraftryk i prod = D1's, 0 `change_set` siden D1 (`NO_WRITE_SINCE_DUMP`) | nej |
| 2 | GO 2 | — |
| 3 | Genspil af pakken skridt for skridt. Hvert skridt klassificerer sin indgangstilstand først og sammenligner sin udgangsdigest med pakkens, før det næste starter. `sql`- og `hash_gated`-skridt er én transaktion; `writer`-skridt følger writerens transaktionsmønster (§6.2) | privat lag + kildevisning |
| 4 | `VERIFY_OK` (§9); derefter ophører skrivepausen | nej |

## 7. Verifikation **(ændret efter review)**

**Nøglede digests.** Trin 4's `interpretation_transfer_digests.sql` udvides med 5a/5b-lagene, eller en ny
læse-kun repo-fil gør det. Hver digest hasher rækker som `to_jsonb(…)` med nøglen i rækken og `COLLATE "C"`:

| Digest | Nøgle | Udelader |
| --- | --- | --- |
| Personas og omtaler | `persona_key` | id'er, `created_run_id`, tidsstempler |
| Identiteter (gældende + hændelser) | `persona_key`, version | hændelses-id, tidsstempler, kandidat-/kørsels-id'er i evidensen |
| Kandidater | kørslens `input_sha256 ‖ config_sha256`, `persona_key`, rang | id'er, tidsstempler |
| Kontrol: stikprøve, udelukkelser, forældrekort | stikprøvens `persona_key` / udelukkelsens `persona_key` + grund / forældrekortets `interpretation_key` | id'er, tidsstempler |
| Kontrolhændelser og forældrehændelser | kontrolkørslens indholdsnøgle + løbenummer (forsegl, bestå) / `interpretation_key` + løbenummer + udfald | id'er, tidsstempler |
| Fortolkninger og afgørelser for 2018-20 (alle prædikater) | `interpretation_key`, version | id'er, tidsstempler, `pack_sha256` |
| Parter | `interpretation_key`, rolle, version | `origin_ref`, tidsstempler |
| Klassifikationshændelser | `interpretation_key`, løbenummer | `interpretation_id`, `state_sha256`, tidsstempler |
| Dispositioner | `observation_id` (klausulobservationer er fælles med prod), version | `batch_id`, kørsels-id'er; `actor_persona_ids`/`citing_interpretation_ids` oversættes til nøgler |
| Writer-profiler | profilnøgle | tidsstempler |
| Bindinger | `interpretation_key`, `target_type`, `target_id`, `rule_key`, `rule_version` | id'er, batch, `preview_hash`, `state_sha256`, `supersedes_promotion_id`, tidsstempler |
| Autorisationer | antal `consumed` pr. operation og manifest-hash | alt andet; `issued` rapporteres separat |
| Batches, reimport-hændelser, ekstraktionskørsler, bindingsbatches | antal pr. operation | alt andet |

Planen fastlægger den eksakte kolonneliste pr. tabel. Sekvenser og identitetskolonner indgår ikke.

**Ud over digests:**
- **Kanonisk delta 0:** driftsbaselinen før og efter i samme base.
- **Uberørt:** `transfer_untouched_hash.sql` udvides med alle tabeller, kæden skriver i. De øvrige skal være
  uændrede. For hver tabel, kæden skriver i, hashes desuden rækkerne for **andre kilder end 2018-20**; de skal
  være uændrede, så en skrivning uden for kilden ikke er usynlig.
- **`anon`:** privilegiematrix lig efter-DDL-målingen; `anon` ser 0 private rækker og præcis de forventede
  rækker i `public_family_sources`.

**Tilstande pr. skridt (som trin 4 §5):** skridtets digests er lig pakkens indgangsdigest ⇒ skriv; lig
udgangsdigesten ⇒ `already_applied`; alt andet ⇒ `MIXED` og fortrydelse (§8). En delvis overførsel er aldrig
en accepteret sluttilstand.

## 8. GO og fortrydelse

**GO 1** binder: D0's hash, fase 0's målinger (inkl. ACL-fingeraftryk og advisors-baseline),
katalogfingeraftrykket, DDL-øvelsens rapport (idempotens, afbrudsøvelse, varighed, fortrydelsesøvelse, listen
over objekter at fjerne), repoets commit og hashes for `db-migrations.sql` og `db-rls.sql`.

**GO 2** binder: D1's hash, restore-hash og ACL-fingeraftryk, pakkens hash (over skridtenes kanoniske JSON),
alle forventede digests, arkhashes med oversættelsestabeller (§6.2), genspilsprøvens rapport (inkl.
genkørsels- og fortrydelsesøvelse og varighed pr. skridt), repoets commit og et eksakt filinventar for scripts
og repo-filer, kontrolleret som mængde.

**Fortrydelse** (begge med netop den kommando, der er øvet, og med grant-afstemning mod preflight-listen
bagefter; `get_advisors` efter enhver restore):
- **DDL-ceremonien:** fejler apply midtvejs, køres den igen (idempotens). Kan problemet ikke rettes, følges
  kommandofølgen fra §6.1 trin 4: nye objekter fjernes først efter listen, derefter restore af D0,
  grant-afstemning og `NOTIFY pgrst, 'reload schema'`. Fase 0's målinger skal derefter holde.
- **Data-ceremonien:** `MIXED`, en digest-afvigelse efter commit eller et STOP, der ikke kan rettes ved at
  køre et skridt igen, ⇒ D1 gendannes, grants afstemmes, og `NOTIFY pgrst, 'reload schema'` sendes. Pakken genspilles efter rettelse. Projektejerens svar ligger i pakken,
  så intet skal afgøres igen.

## 9. Færdigbevis og modenhed

- **Før ceremonierne:** forudsætningsleddet merget; overførslens scripts og tests grønne i CI.
- **DDL:** `REHEARSAL_OK` (DDL) og en verificeret DDL i prod (læse-kun probe, `get_advisors`).
- **Data:** arbejdskørslen bestået inkl. indholdskontrollen (§6.3), `REHEARSAL_OK` (data) og `VERIFY_OK` i
  prod: alle nøglede digests lig arbejdskørslens, kanonisk delta 0, uberørte tabeller uændrede, `anon` som
  forventet, 0 nye personer.
- **Modenhed (beslutning 8):** 5a og 5b's personas, identiteter, bindinger, børnehenvisninger,
  klausuldispositioner, klassifikationshændelser (`ordinal_beholdt`) og P-afvisningen for 2018-20 ⇒
  `produktionsverificeret`. Oprettelse af nye personer og #244's rettelsesvej (`red_ret_aegteskabsnummer`,
  deployet men ubrugt) forbliver `isoleret implementeret`. #244 noteres som »opstod aldrig i prod«.

## 10. Test (test først)

- **Forudsætningsleddet** (i dets egen spec): samme indhold i to baser med forskelligt `system_identifier` og
  databasenavn giver samme deterministiske id'er, samme stikprøve og samme kortrækkefølge; ændret indhold
  giver nye id'er; kollision fejler lukket; opgradering fra prods træ 2026-10-05.
- **Nøglede digests:** ens i to baser med samme indhold og forskellige tilfældige id'er og databasenavne;
  ændres ved én ændret værdi, ved ombyttet status mellem to nøgler og ved ændret mål for en binding; uændret
  af tidsstempler, sekvenser og locale.
- **Svaroverførslen:** entydig overførsel; svar uden mål og mål uden svar stopper; forventede bortfald går
  igennem; oversættelsestabellen er komplet.
- **Pakkebygger og genspiller:** forkert indgangstilstand, ukendt skridt, digest-afvigelse, afbrud midt i et
  skridt (ruller tilbage) og genkørsel, `already_applied`, `hash_gated`-skridt på tværs af to databasenavne,
  `writer`-skridt afbrudt efter autorisation, GO-hash-mismatch, ukendte argumenter og manglende
  `--jeg-mener-det`.
- **DDL:** afbrudt apply og genkørsel giver samme fingeraftryk; fortrydelse med emulerede default privileges
  og grant-afstemning giver fase 0's ACL-fingeraftryk; PostgREST-reload.
- **Værn:** `ORDINAL_BOOK_MISMATCH` = 0, korrektionsinput = 0 og 0 personoprettelser i arbejdskørslen.
- **Runde 2's huller:** genkørsel af et `writer`-skridt med en efterladt `issued`-autorisation; et `sql`-skridt
  genspillet i to baser, hvor et kæde-skabt id er forskelligt (fanger hårdkodede id'er i ark-SQL);
  DDL-fortrydelse med nye tabeller, der har fremmednøgler til eksisterende; 5a-svar, hvor samme rang peger
  på en anden person i den nye kørsel (skal stoppe).
- **Integration:** genspilsprøven (§6.4) og begge fortrydelsesøvelser.

## 11. Afgrænsning

Ikke med:
- **#240** (dobbelte familier; 7 ægteskaber står fortsat fejlet lukket);
- **#248** (2 familienumre modsagt af bogens »N°«);
- **5c** (placement/membership);
- oprettelse af nye kanoniske personer på rigtige data (beslutning 8);
- de 2 børnepåstande, der står `proposed`;
- `mention.place`;
- 1939.

**Udgavenavne i permanente overflader:** writerens profilliste (`relation-persona-2018-20-v1/v2/v3`) og
bognummer-mønstret er 2018-20's form. Det er de undtagelser, der allerede står i 2b-ii's og #244's specs
(#244 §10); overførslen tilføjer ingen nye. Planen citerer de beslutningsposter, der dækker dem, eller
opretter én, hvis en mangler.

**Kendt risiko:** arbejdskørslen kan afsløre afvigelser fra beviskæden, som ikke står i §6.3. Hver af dem
stopper kørslen og forelægges projektejeren.

**Rækkefølge:**
1. Forudsætningsleddets spec, review, implementering og merge.
2. Overførslens plan, scripts og tests.
3. Fase 0 og GO 1.
4. Arbejdskørslen med projektejerens ark.
5. Genspilsprøven og GO 2.

## 12. Revision efter Fable-review runde 1 (2026-10-21)

Uafhængig Fable-agent uden samtalekontekst. De bærende påstande (#153's `BEGIN`/`COMMIT` i
`db-migrations.sql`, `db-verify.sql`'s forbud mod prod, trin 4's grant-afstemning, tilfældigt id i
`red_decide_interpretation`) er efterprøvet mod koden, før de blev godtaget.

| Fund | Ændring |
| --- | --- |
| BLOCKER 2.1 — DDL er ikke én transaktion | §2, §6.1: etableret apply-procedure; idempotens, afbrudsøvelse og D0 er sikkerheden; §8 omskrevet |
| MAJOR 1.1 — id-listen ufuldstændig | Projektejerens valg: nøglede digests (§3 beslutning 7, §7); §4 minimal og eksplicit om, hvad der forbliver tilfældigt |
| MAJOR 1.2 — #244 kræver regenererede manifester | §3 beslutning 4, §6.2 (manifester og #244-værn), §6.3 |
| MAJOR 2.2 — fortrydelsens rettigheder umålt | §5 ACL-fingeraftryk og privilegiematrix; §6.1 trin 2/4 emulerede default privileges, katalogforskel, grant-afstemning; §8 |
| MAJOR 2.3 — `db-verify` i prod | §6.1: kun i øvelsen; læse-kun probe i prod |
| MAJOR 2.4 — writer-skridt er to transaktioner | §6.2 skridttyper; klassifikation før autorisation; autorisationer kun antal og manifest-hash (§7) |
| MAJOR 2.5 — færdigberegnede hashes i pakken | §6.2 `hash_gated`: items i pakken, hash genberegnes; §6.4 to databasenavne; sekvenser udeladt |
| MAJOR 2.6 — §6.3 skal være nøglet | §6.3 nøglet liste udledt af bevisbaserne; opregnede forskelle udvidet |
| MAJOR 2.7 — overførte svar og hash-bundet godkendelse | §6.2 oversættelsestabel, linjevis forskelsvisning, v3's 2 linjer genaccepteres, webafgørelsen eget skridt; §8 GO 2 |
| MAJOR 3.1 — modenhed overdrevet | Projektejerens valg: §3 beslutning 8, §9, §11 |
| MAJOR 3.2 — testhuller | §10 udvidet |
| MINOR 1.3 / 2.8 — kontrolarket er en ny afgørelse | §3 beslutning 6, §6.2 |
| MINOR 3.3 — udgavenavne | §11 |

## 13. Revision efter Fable-review runde 2 (2026-10-21)

Ny Fable-agent uden kontekst; dom GO med rettelser i alle tre afsnit. De bærende påstande (O-linjens
tilfældige `interpretation_id` i `spouse_exception_projection` og den genererede SQL; `pg_restore --clean` uden
`CASCADE` i runbookens fortrydelse) er efterprøvet mod koden.

| Fund | Ændring |
| --- | --- |
| P1-1 MAJOR — 2b-i's `O`-linjer hårdkoder et tilfældigt id | §4 pkt. 3: ark-SQL slår id op via nøgle; `spouse_exception_sheet.py` nøgles på `interpretation_key`; alle arkværktøjer gennemgås |
| P2-1 MAJOR — fortrydelsens rækkefølge umulig | §6.1 trin 4 og §8: nye objekter fjernes først, så restore, grants, `NOTIFY pgrst` |
| P2-2 MAJOR — writer-genkørsel modsiger autorisationsdigest | §6.2 og §7: digests kun over nøglede tabeller; kun `consumed` tælles; `issued` genbruges eller rapporteres |
| P2-3 MAJOR — godkendelsens forskel kun over tokens | §6.2: svar som afklarede værdier; 5a-rang verificeres mod `person_id`; forskel over hele linjer inkl. kontekst |
| P1-2 MINOR — `family.id` | §5 måles; ikke forhåndslistet til fjernelse |
| P1-3 MINOR — kandidatnøgle ikke unik | §7: kørslens indholdsnøgle i nøglen |
| P2-4 MINOR — rækker uden for nøglerummet | §7: kontrol-, forældre- og udelukkelsesdigests, profiler, antal for batches/kørsler, andre kilders rækker |
| P2-5 MINOR — dispositionernes nøgle | §7: (`observation_id`, version); id'er i evidensen oversættes |
| P2-6 MINOR — ét afbrudspunkt | §6.1 trin 3: tre afbrudspunkter |
| P3-1 MINOR — modenhed for dispositioner m.m. | §9 |
| P3-2 MINOR — testhuller | §10 |
