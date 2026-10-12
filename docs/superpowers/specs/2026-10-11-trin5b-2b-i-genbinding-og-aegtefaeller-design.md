# Trin 5b del 2b-i — genbinding efter rettelse, ordinal-afvigelserne og de uafgjorte ægtefæller (#151)

**Status:** Design godkendt af projektejeren 2026-10-11, afsnit for afsnit (brainstorm samme dato). Revideret
samme dag efter Codex `gpt-5.6-sol` runde 1 (NO-GO: 4 BLOCKER, 8 MAJOR, 1 MINOR; alle efterprøvet og godtaget,
§14) runde 2 (NO-GO: 4 BLOCKER, 6 MAJOR, 1 MINOR, §15) og runde 3 (NO-GO: 1 BLOCKER, 3 MAJOR, §16); alle fund
efterprøvet og godtaget. To af rettelserne
omgør godkendte designvalg med projektejerens ja: partnerknappen kontrolleres i serveren (§6.3), og `F`
skrives som hændelse (§5.4). Afventer Codex runde 4 og projektejerens gennemlæsning.

**Roadmap:** trin 5, delspec 5b (`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`,
herefter »hovedspecen«), del 2, skive b, første halvdel. Bygger på 2a
(`docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`, herefter »2a-specen«; draft-PR #239, ikke
merget) og 2a's bevisrapport `docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md`. Beslutninger:
`docs/decisions.md` 2026-10-06, 2026-10-10 og 2026-10-11. Delingen af 2b i 2b-i og 2b-ii (§2) skrives som
decisions-post, når spec'en er godkendt.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151, med #150's familiedel) |
| Værdikædeled | Identitetsafgørelse → relationsafgørelse → (gen)binding → læserens kildevisning |
| Leverancetype | Generel motor: genbinding af familiebindinger efter en rettelse; et generelt undtagelsesark for ægtefæller hvis partner er kandidat nr. 1; partnerkontekst og strukturel årsag i webkøen. Intet udgavespecifikt |
| Redaktionel/læserrettet værdi | Redaktøren kan rette et bundet ægteskab uden at miste kilden for altid. De 31 uafgjorte ægtefæller afgøres med et kort ark (undtagelser) og en kø med den kontekst, der i dag mangler. Læseren får kilde på op til 31 ægteskaber mere |
| Færdigbevis | §9: i en kopi af 2a's bevisbase; ark og kø hash- og versionsbundet; manifest = efter-digest; 2a's 210 bindinger uændrede; et præcist kanonisk delta (kun ordinal på de rettede rækker); negativtests |
| Erstatter | 2a's »ingen vej til at binde igen« (2a-specen §11 pkt. 6); webkøens blinde vinkel, hvor hovedpersonens faktiske partner ikke ses, når den ikke er kandidat; et fuldt afgørelsesark for de 31 |

## 2. 2b i to halvdele

2a-specen §2 samlede 2b i én skive. Den deles nu (projektejerens valg 2026-10-11):

- **2b-i (denne spec):** (1) genbindingsvejen (2a-specen §11 pkt. 6, mulighed a), (2) de 3
  `ordinal_afvigelse`-ægteskaber fra 2a, (3) de 31 ægtefælle-personas uden identitet, og efterkørslen der
  afgør og binder det, de frigør.
- **2b-ii:** nye personer (hovedspecen §8.4, herunder `family.id`-driften i errata §22.3; `new_person_needed`
  og `different` fra køen; de 14 ægteskabspåstande uden ægtefælle-persona) og klausul-dispositionen
  `relation_disposition` sidst.

Restpunkterne fra 2a-specen §2 (»(F.: …)«-fejllæsningen, ægtefællers år §22.7, final reviews M1-M3 og
M5-M10) foldes ind i den halvdel, hvis kode de rører; planen for 2b-i peger hvert berørt punkt ud.

## 3. Udgangspunkt (målt 2026-10-11 i `daa5b_2a_bevis_20261011185524`, læse-kun)

| | |
| --- | --- |
| Ægtefælle-personas i kilde 1 | 234: 203 `accepted`, **31** `proposed` (ingen identitetshændelse) |
| De 31 | **22** hvor hovedpersonens partner i databasen er kandidat nr. 1 i den gældende kandidatkørsel, men navn eller antal fejlede maskinelt; **8** hvor partneren ikke er blandt kandidaterne; **1** hvor hovedpersonen ingen familie har |
| Kontrolstikprøve | 0 af de 31 ligger i `identity_control_sample` (så `red_afgoer_source_persona` tillader `human_sheet` uden kontrolkørsel) |
| `relation.marriage` | 203 `accepted` (2a), 45 `proposed` = de 31 + 14 uden ægtefælle-persona |
| `relation.parent` | 7 `accepted` og bundet, 2 `proposed` (`F`/`U`-kort), 1 `rejected` |
| Klassifikationer | 3 `ordinal_afvigelse` (bundet trods afvigelsen, 2a-specen §4.3) |
| Relationsuniverset i kilde 1 | 272 gældende relationspåstande: `relation.marriage` 203 `accepted` + 45 `proposed`; `relation.parent` 7 `accepted` + 2 `proposed` + 1 `rejected`; `relation.child` 14 `proposed` |
| Andre kilder | 0 `proposed` ægtefælle-personas uden for kilde 1 |
| Familiebindinger | 210 (203 ægteskab, 7 forælder); 0 forældede; alle 210 har en `state_sha256` på 64 hex-tegn (0 afvigere); `identity_control_exclusion` 0 rækker |

## 4. Genbinding (2a-specen §11 pkt. 6, mulighed a)

**Princip:** en ny binding ved siden af den gamle. Den gamle række bliver stående som historik (append-only,
invariant 1); læseren bruger den binding, hvis tilstand passer nu. Fravalgt: en afløsningshændelse i egen
tabel (mere maskineri for samme resultat) og opdatering/sletning af den gamle række (bryder append-only).

### 4.1 Data

`private.interpretation_promotion` har i dag **to** unikhedsregler, der begge forbyder en genbinding i samme
familie: tabellens `UNIQUE (interpretation_id, target_type, target_id)` (schema.sql ~1516, db-migrations.sql
~5833) og 2a's partielle indeks `interpretation_promotion_one_family_per_interpretation (interpretation_id)
WHERE target_type='family'`. Begge erstattes:

- `interpretation_promotion_one_target_per_interpretation ON private.interpretation_promotion
  (interpretation_id, target_type, target_id) WHERE target_type<>'family'` — den hidtidige regel, uændret for
  alle andre mål.
- `interpretation_promotion_one_family_per_state ON private.interpretation_promotion (interpretation_id,
  (evidence->>'state_sha256')) WHERE target_type='family'` — højst én familiebinding pr. fortolkning **og
  tilstand**.
- `interpretation_promotion_family_state_check CHECK (target_type<>'family' OR (evidence ? 'state_sha256' AND
  jsonb_typeof(evidence->'state_sha256')='string' AND evidence->>'state_sha256' ~ '^[0-9a-f]{64}$'))`. Alle
  led er ikke-NULL, så udtrykket bliver aldrig `NULL` (en CHECK godtager `NULL`): en familiebinding uden
  hash, med JSON-`null`, med et tal eller med forkert format afvises. De 210 eksisterende rækker opfylder den
  (målt, §3).

**Ingen tom unikhed undervejs.** Ingen kode bruger `ON CONFLICT` på tabellen (efterprøvet). Rækkefølgen i
2b-i-blokken i `db-migrations.sql`, i én transaktion: opret de to nye indeks (`IF NOT EXISTS`); tilføj CHECK
som `NOT VALID` og `VALIDATE` (beskyttet af et `pg_constraint`-opslag); drop tabellens unikhedsregel, fundet
via `pg_constraint` som den `u`-constraint, hvis kolonner er præcis `(interpretation_id, target_type,
target_id)` — ikke via et antaget autogenereret navn; drop til sidst `…_one_family_per_interpretation IF
EXISTS`.

**Idempotens efter første genbinding.** En senere fuld genkørsel af `db-migrations.sql` må aldrig genskabe en
af de to gamle regler, for den ville fejle på de nu lovlige rækker:

- Tabellens `UNIQUE` står i en `CREATE TABLE IF NOT EXISTS` og genskabes derfor ikke på en eksisterende
  tabel. `schema.sql` (frisk sti) får tabellen uden den og de to nye indeks i stedet.
- 2a-blokkens `CREATE UNIQUE INDEX IF NOT EXISTS …_one_family_per_interpretation` **fjernes** fra
  `db-migrations.sql` og `schema.sql`. Det er muligt, fordi 2a hverken er merget eller deployet; de eneste
  baser med det gamle indeks er lokale (bevisbasen), og dem rammer 2b-i-blokkens `DROP … IF EXISTS`.
- `db-verify.sql`'s 2a-assert (ca. linje 10131) skifter til at kræve de to nye indeks og CHECK og fraværet
  af begge gamle regler.

### 4.2 Preview og batch

`private.preview_relation_promotions` ændres i ét led: et element er `RELATION_PROMOTION_ALREADY_APPLIED`,
kun når der findes en familiebinding for fortolkningen **med den nuværende `state_sha256`**. Findes der kun
forældede bindinger, er elementet egnet, og previewet sætter `supersedes_promotion_id` til den seneste
forældede familiebinding for fortolkningen (`ORDER BY promoted_at DESC, id DESC LIMIT 1`; ellers `null`).

En genbinding kræver, at den nuværende tilstands familie er den forældede bindings familie (`target_id`);
ellers er elementet ikke egnet (`RELATION_PROMOTION_REBIND_FAMILY_CHANGED`), fordi påstanden blev afgjort for
en anden familie.

`supersedes_promotion_id` indgår i elementerne og dermed i previewhashen; kontrakten hedder derfor
`relation-promotion-preview-v2`. `red_promote_relation_interpretations_batch` skriver feltet med i bindingens
evidens. Ingen ny RPC til binding, ingen ændret signatur.

**Replay af gamle batches:** batchen slår allerede replay op på den gemte previewhash, før previewet
genberegnes (schema.sql ~16227). Et præcist genkald af en v1-batch efter opgraderingen giver derfor samme
batch-id og 0 nye rækker. Det bevises i opgraderingstesten (§10).

Tilbage-rettelse: rettes ordinalen fra A til B (genbinding ved B) og senere tilbage til A, passer den gamle
binding igen; previewet siger `ALREADY_APPLIED`, og der skrives intet.

### 4.3 Læsning

`public.public_family_sources` ændres ikke: den kræver allerede, at bindingens `state_sha256` er lig den
nuværende tilstands hash (2a-specen §5.1 trin 2). Med `…_one_family_per_state` kan højst én binding pr.
fortolkning opfylde det.

### 4.4 Hvad genbinding dækker

En ændring af de felter, tilstanden rummer (2a-specen §4.2), uden ny fortolkningsversion og i **samme
familie**: ordinal eller konfidens på de bærende rækker, eller en ny identitetsversion til samme person. En
ny fortolkningsversion får som hidtil sin egen binding. Flytter strukturen til en anden familie (fx en
identitet afgjort til en anden person), bindes der ikke igen (§4.2): påstanden blev afgjort for den gamle
familie, og en genafgørelse hører ikke til 2b-i (§13).

## 5. Arket: 22 ægtefæller og 3 ordinal-afvigelser

Menneskelig kontrol er undtagelser (memory: ingen flere fulde afgørelsesark): Claude bygger arket med
anbefalingen forudfyldt, og projektejeren retter kun det, der er forkert. Udtræk og anvendelse ligger i
databasen (to RPC'er), så låse, hashkontrol og skrivning sker i én servertransaktion og kan testes i CI.

### 5.1 `red_spouse_exception_rows(p_source_id bigint) RETURNS jsonb`

Redaktionsgatet, `STABLE`, `SECURITY DEFINER`, `SET search_path=pg_catalog,public,private`. Afviser en
`NULL` eller ukendt kilde (`SPOUSE_SHEET_INVALID`). Returnerer `{contract: 'spouse-exception-rows-v1',
database_identity, source_id, s_rows, o_rows, rows_sha256}`:

- **`s_rows`** — ægtefælle-personas i kilden uden `accepted` identitet, hvor `private.persona_family_context`
  ikke er `NULL`, og hvor kandidat nr. 1 i den gældende kandidatkørsel er partner til hovedpersonen i en af
  dens familier. Pr. række: `source_persona_id`, `identity_version` (0 uden hændelse), `candidate_id`,
  `run_id`, `candidate_rank`, `candidate_tier`, `candidate_score`, `candidate_count` (kandidater i kørslen),
  `candidate_person_id`, `principal_person_id`, kandidatens visningsfelter (`visning_navn`,
  `visning_fuldt_navn`, `visning_foedt`, `visning_doed`), personaens mentions (`mention_role`,
  `verbatim_text`; `ORDER BY source_persona_mention.ordinal`) og `family_context_sha256` (hash af
  `persona_family_context`).
- **`o_rows`** — ægteskaber i kilden med en **gældende** `ordinal_afvigelse` (Codex r2 #7): den seneste
  klassifikationshændelse for nøglen er `ordinal_afvigelse`, dens `interpretation_id` er den gældende version
  med status `accepted`, dens `state_sha256` er lig den nuværende tilstands hash, og tilstandens
  `book_ordinal` afviger stadig fra `family_ordinal`. Pr. række: `interpretation_id`, `interpretation_key`,
  `family_id`, `principal_person_id`, `spouse_person_id`, `book_ordinal`, `family_ordinal`, `state_sha256`,
  `classification_seq`. (Målt: alle 3 opfylder kriteriet i dag.)
- **Orden** (Codex r2 #11): `s_rows ORDER BY source_persona_id::text COLLATE "C"`, `o_rows ORDER BY
  interpretation_id::text COLLATE "C"`. Arkets linjer er `s_rows` som 1..|s| og derefter `o_rows` som
  |s|+1..n; den mapping `line → (kind, id)` er kanonisk og kontrolleres af serveren (§5.4).
- Alle bigint-id'er udleveres som decimalstrenge (`::text`).
- Fejler (`SPOUSE_SHEET_CONTROL_SAMPLE`), hvis en persona fra `s_rows` ligger i en `identity_control_sample`.
- `rows_sha256` = `private.reimport_canonical_json_sha256` af hele projektionen uden selve hashen: alt, hvad
  arket viser, er dermed bundet (Codex r1 #5).

Funktionen er en redaktionsflade med navne; den er ikke offentlig.

### 5.2 Arkværktøjet (generelt, i repo)

`.claude/skills/daa-extract/scripts/spouse_exception_sheet.py` med underkommandoerne `render`, `check` og
`answers`; tests i `test_spouse_exception_sheet.py` (python-jobbet). Værktøjet taler ikke selv med databasen:
det læser RPC-svaret fra en fil og skriver ark og svar-JSON.

**Privatliv håndhæves i værktøjet** (Codex r1 #11): alle ind- og udstier skal efter `realpath` ligge under
`$HOME/.private/`, uden for ethvert git-arbejdstræ (ingen forfader med `.git`), og må ikke være symlinks; den
private mappe skal have mode `0700`; nye filer oprettes med `O_CREAT|O_EXCL` og mode `0600`. Værktøjet
skriver aldrig ark- eller kildeindhold til stdout/stderr, kun antal og hashes. Negative tests for repo-sti,
symlink, `/tmp`, åben mappe og eksisterende fil.

### 5.3 Linjeformat og hashes

- `S <persona-uuid> : <tok>  # note` med `<tok>` ∈ `S` (samme, forudfyldt), `A` (anden), `U` (uafklaret).
  Under linjen står kildens navn og år, kandidatens navn og år, familiens id og ordinal, tier, score og antal
  kandidater.
- `O <interpretation-uuid> <bog>/<familie> : <tok>  # note` med `<tok>` ∈ `B` (ret familien til bogens
  nummer), `F` (behold familiens). Forudfyldt med Claudes forslag; begrundelsen står under linjen.

`render` skriver linjerne i den kanoniske orden (§5.1). `check` afviser samlet ukendte, manglende, dublerede,
omformede og omordnede linjer (som del 1). `answers` danner `[{line, kind, id, token, note}]` og to hashes,
som projektejeren godkender sammen:

- `sheet_sha256` = SHA-256 af den udfyldte arkfil (menneskets dokument; værktøjet sikrer, at svarene er
  udledt af netop den fil).
- `answers_sha256` = SHA-256 (hex, små bogstaver) af UTF-8-teksten, der består af én linje pr. svar i
  linjeorden, `line TAB kind TAB id TAB token TAB note`, adskilt af LF uden afsluttende LF (Codex r3 #2):
  - `line` er svarets 1-baserede ordinal blandt arkets **svarlinjer** (`S`/`O`), uafhængigt af filens
    fysiske linjenumre og kontekstlinjer, skrevet som decimaltal uden foranstillede nuller;
  - `kind` er `S` eller `O`; `id` er uuid'et med små bogstaver; `token` er ét tegn;
  - `note` er teksten efter `#`, trimmet for mellemrum (U+0020) i begge ender; tom note er den tomme streng.
    En note med TAB, CR, LF eller andre kontroltegn (Unicode-kategori Cc) afvises af både værktøj og server.
  Serveren genberegner hashen fra `p_answers` (§5.4) — det er den kryptografiske binding mellem de anvendte
  svar og godkendelsen (Codex r2 #4). En delt fixture `tests/fixtures/spouse-exception-answers.json` med
  svar, den eksakte præimage (som base64) og den forventede hash skal ramme byte-identisk i både Python-testen
  og SQL-testen.

### 5.4 `red_apply_spouse_exception_sheet(p_source_id bigint, p_rows_sha256 text, p_sheet_sha256 text, p_answers_sha256 text, p_answers jsonb) RETURNS jsonb`

Redaktionsgatet (`auth.uid()` og `current_rolle()='redaktion'`), `SECURITY DEFINER`, `SET
search_path=pg_catalog,public,private`. Én transaktion; enhver fejl giver 0 skrivninger. I denne rækkefølge:

1. **Form** (Codex r2 #5): `p_source_id` er ikke `NULL` og findes; de tre hashes er 64 hex-tegn; `p_answers`
   er et ikke-tomt array, hvor hvert element har præcis nøglerne `line`, `kind`, `id`, `token`, `note`;
   `token` hører til `kind`; den af serveren genberegnede `answers_sha256` (§5.3) er lig `p_answers_sha256`.
   Ellers `SPOUSE_SHEET_INVALID`.
2. **Intet fremmed change_set** (Codex r2 #3): er `app.change_set_id` sat i transaktionen, fejler kaldet med
   `SPOUSE_SHEET_FOREIGN_CHANGE_SET` før første lås og skrivning (som `REIMPORT_CASE_FOREIGN_CHANGE_SET`).
3. **Kildelås** eksklusivt (`pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||source,0))`,
   samme nøgle som kandidatwriteren og `red_decide_relation_interpretations`), og derefter `LOCK TABLE
   public.family_member IN SHARE MODE` under `lock_timeout` (Codex r3 #1). Projektionens medlemskab afhænger
   af `family_member` (gennem `persona_family_context`), og redaktørens familiewritere tager ikke kildelåsen;
   tabellåsen blokerer deres `INSERT`/`UPDATE`/`DELETE` til commit, så en række uden for arket ikke kan blive
   egnet mellem genberegning og commit. Ark-RPC'ens egne `B`-opdateringer er tilladt (samme transaktion).
   Projektionens øvrige afhængigheder skrives kun under kildelåsen (kandidatkørsler, identiteter,
   relationsafgørelser og klassifikationer) eller er låst som rækker (kandidaternes `person`-rækker, trin 5).
   Overskrides `lock_timeout`, fejler kaldet med 0 skrivninger.
4. **Replay** (Codex r2 #6): findes der en kvittering (§5.5) for `(p_source_id, p_rows_sha256)`, returneres
   dens resultat uden at skrive, hvis `sheet_sha256` og `answers_sha256` er de samme; ellers
   `SPOUSE_SHEET_REPLAY_MISMATCH`. Opslaget sker efter kildelåsen og før genberegningen, fordi skrivningerne
   ændrer projektionen.
5. **Rækkelåse i fast orden** (Codex r2 #2): personarækkerne for `s_rows` og deres identitetsrækker `FOR
   UPDATE`, sorteret (samme orden som identitetskernen, schema.sql ~8326-8340); fortolkningsrækkerne for
   `o_rows` `FOR UPDATE`, sorteret; `private.lock_family_rows` over alle person-id'er, arket berører
   (hovedpersoner, kandidater, ægtefæller i `o_rows`), sorteret. Alle andre writere af disse rækker tager
   enten kildelåsen (identitet, relationsafgørelse, binding) og venter derfor på trin 3, eller tager kun
   familierækker (redaktørens familiewritere) og venter på de sidste låse.
6. **Genberegning under lås:** projektionen fra §5.1 beregnes igen. Afviger dens `rows_sha256`, er
   projektionen tom (`SPOUSE_SHEET_EMPTY`), eller er `p_answers`' mapping `line → (kind, id)` ikke **præcis**
   den kanoniske (§5.1; samme linjenummer, samme type, samme id — ikke kun samme mængde), fejler kaldet med
   `SPOUSE_SHEET_ROWS_STALE`.
7. **Ét change_set:** `begin_change_set('red_apply_spouse_exception_sheet', ‹antal pr. token,
   sheet_sha256, answers_sha256›, NULL, NULL)`. De indre writere genbruger netop dette (Codex r1 #8).
8. **`S`** → `red_afgoer_source_persona(persona, identity_version, 'same', candidate_person_id, note,
   {basis: 'human_sheet', sheet_sha256, rows_sha256, line, candidate_id, run_id})`. Noten er linjens note
   eller »ark 2b-i: partner er kandidat nr. 1«. **`A`/`U`** skriver intet; personaen forbliver `proposed` og
   afgøres i køen (§6).
9. **`B`** → kontrollér under lås, at hovedpersonens partnerrække har `family_ordinal` fra projektionen, og at
   ingen gældende familiebinding fra en **anden kilde** har en tilstand, der indeholder den række (ellers
   `SPOUSE_SHEET_SHARED_FAMILY_BINDING`, Codex r2 #8); kald `red_set_familie_ordinal(family_id,
   principal_person_id, 'partner', book_ordinal)`, og skriv `private.append_relation_classification(
   interpretation_id, 'ordinal_rettet', evidens)`. **`F`** → `private.append_relation_classification(
   interpretation_id, 'ordinal_beholdt', evidens)` (Codex r1 #7). Evidensen er `{sheet_sha256,
   answers_sha256, rows_sha256, line, book_ordinal, family_ordinal_before, change_set_id, note}`;
   hændelsens `state_sha256` er tilstanden efter skrivningen. Bindinger i samme kilde, hvis tilstand rummer
   rækken (fx en forælderbinding), bliver forældede og genbindes af efterkørslen (§7); universbeviset (§9)
   fanger dem.
10. **Kvittering:** skriv `{change_set_id, s, a, u, b, f}` i kvitteringen (§5.5) og returnér det.

Efter `B` er bindingens tilstand forældet, og kilden er skjult, indtil efterkørslen binder igen (§7).
`red_set_familie_ordinal` ændres ikke.

### 5.5 Data til arket

- **Klassifikationstabellen** (`private.relation_classification_event`): CHECK-reglen
  `relation_classification_event_kind_check` udvides til `('ordinal_afvigelse', 'ordinal_rettet',
  'ordinal_beholdt')`. Tabellen er append-only, så `ordinal_afvigelse` står tilbage som historik, og den
  seneste hændelse er den gældende. Opgradering (Codex r2 #10), idempotent og ens i `schema.sql` og
  `db-migrations.sql`: i en `DO`-blok, kun hvis `pg_get_constraintdef` afviger fra den nye definition, `DROP
  CONSTRAINT relation_classification_event_kind_check`, `ADD CONSTRAINT … NOT VALID`, `VALIDATE`.
  `db-verify.sql` sammenligner den præcise definition.
- **Kvitteringen** `private.spouse_exception_sheet_receipt` (`id uuid`, `source_id`, `rows_sha256`,
  `sheet_sha256`, `answers_sha256`, `change_set_id`, `result jsonb`, `created_by`, `created_at`), `UNIQUE
  (source_id, rows_sha256)`, append-only-trigger (`private.reject_evidence_mutation`), RLS slået til uden
  politikker og ingen grants (som de øvrige private 5b-tabeller; står i `db-rls.sql`'s master-array).
- **ACL** (Codex r2 #1): `red_spouse_exception_rows(bigint)` og
  `red_apply_spouse_exception_sheet(bigint,text,text,text,jsonb)` står i `db-rls.sql`'s allow-liste; ellers
  ville RLS-kørslens nulstilling af alle `red_*` gøre dem ukaldbare. `REVOKE ALL … FROM
  PUBLIC,anon,authenticated,service_role`; `GRANT EXECUTE … TO authenticated`. `db-verify.sql` asserterer
  efter RLS-kørslen: `authenticated` ja; `PUBLIC`, `anon`, `service_role` nej; `prosecdef` og
  `proconfig` med `search_path`.

## 6. Webkøen: de 8 + 1 og arkets undtagelser

### 6.1 Finde sagerne

Med kildefilteret sat til kilde 1 giver køens filtre `status=proposed` og `mention_role=spouse` præcis de
resterende sager (målt: 0 `proposed` ægtefælle-personas i andre kilder). `KildepersonaKo.tsx` kræver et valgt
kildefilter, når rollefiltret er `spouse`, og henter ingen liste uden (Codex r1 #13).
`red_source_persona_queue` ændres ikke.

### 6.2 Kontekst i `red_source_persona_detail`

Samme signatur (`jsonb`). Alle bigint-id'er i svaret — også de eksisterende i `persona`, `candidates`
(`person_id`, `family_id`) og `family_context` — udleveres som decimalstrenge (`::text`), så et id aldrig
afrundes under JSON-parsning i browseren (Codex r2 #9). Det samme gælder køen og historikken (Codex r3 #3):
`red_source_persona_queue` returnerer `source_id` og `canonical_person_id` som `text`, og
`red_source_persona_history` returnerer `canonical_person_id` som `text`. Argumenttyperne er uændrede, men
returtypen ændres, så migrationen `DROP`'er og genskaber de to funktioner (samme regprocedure-signatur;
`db-rls.sql`'s allow-liste genudsteder grants), og `db-verify.sql` asserterer returtyperne. Eneste kalder er
`web/src/data/sourcePersona.ts` (efterprøvet med `git grep`); `tests/sql/test-identity-detail.sql` tilpasses.
Nye felter i detaljen, kun for personas med en `spouse`-mention:

- `principal_partners`: hovedpersonens partnere i kanoniske familier, fra `private.persona_family_context`:
  pr. partner `person_id` og `family_id` som decimalstrenge, `name`, `born`, `died`, `ordinal` og
  `konfidens`, sorteret efter familie og person.
- `family_context_sha256`: hash af `persona_family_context` (samme som §5.1).
- `review_reason`, udledt af tilstanden (gemmes ikke), i denne rækkefølge:
  1. `context_unavailable` — `persona_family_context` er `NULL` (hovedpersonen er ikke `accepted`, eller
     ægtefællen har ikke præcis én ægteskabsrelation);
  2. `principal_no_family` — hovedpersonen har ingen familie som partner;
  3. `partner_is_candidate` — kandidat nr. 1 i den gældende kørsel er en af partnerne (arkets undtagelser);
  4. `partner_not_candidate` — ellers.

  For en afgjort persona er feltet `null`.

### 6.3 Partnervalget kontrolleres i serveren (Codex r1 #6)

`red_afgoer_source_persona` (samme signatur) får to nye, valgfri kontekstnøgler, der kun må optræde sammen,
kun med `basis='web_detail'`, `p_action='same'` og uden `candidate_id`: `partner_family_id` (decimalstreng)
og `family_context_sha256`. Når de er der, tager funktionen efter den delte kildelås først personarækken og
identitetsrækken `FOR UPDATE` — samme orden som identitetskernen (schema.sql ~8326-8340), som tager dem igen
uden ny ventetid — og derefter `private.lock_family_rows` over hovedpersonen og `p_canonical_person_id`
(Codex r2 #2). Så genberegner den `persona_family_context` og afviser
(`IDENTITY_PARTNER_CONTEXT_STALE`), hvis hashen afviger, eller hvis `p_canonical_person_id` ikke er partner i
`partner_family_id` sammen med hovedpersonen. Evidensen får `{partner_family_id, family_context_sha256}`.
Dermed skrives identiteten kun, hvis familien stadig ser ud, som redaktøren så den.

### 6.4 UI og id-kontrakt (Codex r1 #9)

`web/src/data/sourcePersona.ts` parser alle id'er fra kø, detalje og historik som decimalstrenge; detaljens
personatype skilles fra `SourcePersonaQueueRow`, og kildefiltret sendes som valideret decimalstreng.
`decideSourcePersona`
tager person-id som decimalstreng (`/^[1-9][0-9]*$/`) og sender den uændret som RPC-argument; eksisterende
kaldere (kandidatknap, fri personvælger) går over til strenge, og `Number`/`Number.isSafeInteger` forsvinder
fra vejen. Den frie personvælger (`web/src/data/redaktionRead.ts`) henter `id` som tekst (PostgREST
`select=id::text,…`), så id'et aldrig passerer et JSON-tal (Codex r2 #9). `KildepersonaKo.tsx` viser øverst i detaljen årsagen på dansk og en boks »Hovedpersonens partnere
i databasen«; hver partner har knappen »Samme som denne partner«, der sender `partner_family_id` og
`family_context_sha256` med (§6.3) og en forudfyldt note med familie-id'et.

### 6.5 Afgørelser pr. sag (hovedspecen §23.5)

| Klassifikation | Handling | Videre |
| --- | --- | --- |
| anden kandidat / partner | `same` | §7 |
| ny person | `new_person_needed` | 2b-ii |
| forkert udtræk | `different` + note | 2b-ii |
| mulig familiefejl | `unresolved` + note | parkeret (familiekorrektion kræver projektejerbeslutning) |
| uafklaret | `unresolved` + note | parkeret |

Claudes forslag til hver sag ligger kun i `~/.private/5b-2b-i/forslag.txt` (persona-nøgle, forslag,
begrundelse): ikke i databasen og ikke i UI'et.

## 7. Efterkørslen

Samme fire skridt og samme RPC'er som 2a (scripts i `~/.private/5b-2b-i/`, kopieret fra `~/.private/5b-2a/`):

1. `red_preview_relation_decisions(1)` → `red_decide_relation_interpretations(1, set_sha256)`. Ægteskaber,
   hvor ægtefællen nu er `accepted` og strukturen entydig, afgøres maskinelt; allerede afgjorte springes over.
2. `red_preview_relation_promotions(1, items)` for **alle** `accepted` relationer i kilden uden en binding med
   den nuværende tilstand: nye bindinger og genbindinger (`supersedes_promotion_id` sat). Ikke-egnede elementer
   tælles pr. `reason_code`.
3. Manifestet skrives **før** bindingen: tupler `(interpretation_id, family_id, rule_key, rule_version,
   state_sha256, supersedes_promotion_id)` for de egnede.
4. `red_promote_relation_interpretations_batch(1, egnede items, preview_sha256)`; efter-digest læst fra
   `interpretation_promotion` = manifestet.

Rækkefølge: arket, køen, efterkørslen. Efterkørslen er idempotent og kan køres igen, hvis køen afgøres i
flere omgange.

Forventning (k = `same` i køen ≤ 9 + arkets undtagelser; s = `S`-linjer ≤ 22; b = `B`-linjer ≤ 3): afgjorte
ægteskaber 203 + s + k; nye bindinger s + k (hvis strukturen er entydig); genbindinger b; bindingsrækker i alt
210 + s + k + b; gældende bindinger 210 + s + k.

## 8. Privatliv

Uændret fra 2a-specen §6. Nye flader med navne (`red_spouse_exception_rows`, detail-felterne) er
redaktionsgatede (ACL §5.5). Arkværktøjet håndhæver den private placering (§5.2). Repo, rapport og chat indeholder tal
og hashes, ingen navne, ingen kildetekst og ingen persona-, person- eller aktør-id'er. Ark, svar-JSON og
forslagsfil ligger kun i `~/.private/5b-2b-i/`.

## 9. Færdigbevis (i restore, ikke i prod)

Arbejdsbase: en ny kopi `daa5b_2b_i_bevis_<ts>` af `daa5b_2a_bevis_20261011185524` (som bevares uændret),
løftet med `db-migrations.sql` og `db-rls.sql`; `db-verify.sql` grøn inkl. de nye asserts. Rapport:
`docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md`.

| Bevis | Krav |
| --- | --- |
| Ark | `sheet_sha256`, `answers_sha256`, `rows_sha256`; antal `S`/`A`/`U`/`B`/`F`; ét `change_set_id`; kvitteringen |
| Kø | k afgjort, fordelt på §6.5's klassifikationer |
| Afgørelse og binding | set-hash, previewhash, manifest = efter-digest, antal nye og genbindinger |
| 2a's bindinger | de 210 oprindelige rækker uændrede (tupel-digest `89bde7603f8c…5923` genberegnet over dem) |
| Kanonisk delta | `person`, `family`, `fact`, `assertion`, `citation`, `conclusion` uændrede (md5 som 2a); `family_member` afviger **kun** i `ordinal` på de b rækker fra `B`, alle under arkets change_set |
| Læsning | `public_family_sources` som `anon` giver 210 + s + k rækker; v2-biografilæsningen for 2a's 50 faste personer uændret |
| **Lukket univers** (Codex r1 #12) | Hver af kildens gældende relationspåstande (272 ved start) ligger i præcis én spand, og summen er universet: (i) `accepted` med en binding med nuværende tilstand; (ii) `accepted` uden — skal være **0** efter efterkørslen, ellers står hver med `reason_code`, og beviset er ikke grønt; (iii) ikke `accepted`, talt pr. årsag mod en eksplicit liste: ægteskab uden ægtefælle-persona (14), ægtefælle `new_person_needed`/`different`/`unresolved` (fra køen), forælder `proposed` (2), forælder `rejected` (1), `relation.child` (14, 2c). En årsag uden for listen gør beviset rødt. Univers-digest over `(interpretation_id, spand, årsag)` |
| Globalt (Codex r2 #8, r3 #4) | I **alle** kilder efter efterkørslen: **0** gældende `accepted` fortolkninger, der har mindst én familiebinding, men ingen binding, hvis `target_id` og `state_sha256` passer den nuværende tilstand. Historiske bindinger med en anden tilstand er forventede (append-only, §4) og rapporteres særskilt: mindst b, og præcis lig antallet af genbindinger |
| Genkald | en ekstra efterkørsel giver 0 egnede elementer og 0 nye rækker; et præcist genkald af ark-RPC'en returnerer kvitteringen uden skrivning |

Negativtests, hver i sin egen kopi:

- A: `red_apply_spouse_exception_sheet` med ændret id-sæt eller forkert `rows_sha256` → `SPOUSE_SHEET_ROWS_STALE`,
  0 skrivninger.
- B: en kandidats visningsnavn eller en persona-version ændret efter udtrækket → `SPOUSE_SHEET_ROWS_STALE`,
  0 skrivninger.
- C: genbinding med forældet previewhash → `RELATION_PROMOTION_PREVIEW_STALE`, 0 rækker.
- D: `B` anvendt uden efterkørsel → netop den familie har 0 kilderækker og universet en spand (ii)-række;
  efter efterkørslen 1 kilderække og 0 i spand (ii).

## 10. Test

- **SQL, genbinding** (`tests/sql/test-relation-binding.sql`, job `evidence-promotion-db`): bind → ret
  ordinal → kilden skjult → preview egnet med `supersedes_promotion_id` → bind → kilden synlig, 2 rækker, den
  gamle uændret; identisk genkald skriver ingen tredje; samme forløb med en ny identitetsversion;
  tilbage-rettelse giver `ALREADY_APPLIED`; struktur flyttet til en anden familie giver
  `RELATION_PROMOTION_REBIND_FAMILY_CHANGED`; CHECK afviser en familiebinding uden nøglen, med JSON-`null`,
  med et tal og med forkert format; to bindinger med samme tilstand afvises; en ikke-familiebinding med samme
  `(interpretation_id, target_type, target_id)` afvises stadig.
- **SQL, ark** (ny `tests/sql/test-spouse-exception-sheet.sql`, samme job): projektion, orden og hash
  (gentaget projektion giver samme hash); `S`/`A`/`U`/`B`/`F` med de rigtige skrivninger og intet for `A`/`U`;
  ét change_set; klassifikationshændelser; formfejl; `NULL`/ukendt kilde og tom projektion (0 rækker, 0
  change_sets); forkert `answers_sha256`; ombyttede id'er, tokens, noter og linjenumre med uændret id-mængde;
  stale id-sæt og stale visningsfelt; fremmed change_set (0 skrivninger); replay af præcis samme kald
  (kvitteringen, 0 nye rækker) og af et kald med andre svar (`REPLAY_MISMATCH`); en historisk
  `ordinal_afvigelse`, hvis tilstand er ændret siden, kommer ikke i `o_rows`; `B` afvist ved en gældende
  binding fra en anden kilde; kontrolstikprøve afvist; redaktionsgate. **Fantom:** session 2's
  `family_member`-indsættelse, der ville gøre en ny ægtefælle egnet, venter på session 1's tabellås og ses
  først efter commit (Codex r3 #1). **Golden vector:** fixturens `answers_sha256` genberegnes i SQL. **To sessioner:** en
  identitets- eller `family_member`-skrivning i session 2 efter session 1's låse venter, og session 1's
  genberegning ser den ikke; omvendt fejler session 1 med `ROWS_STALE`, når session 2 committer først
  (mønster fra 2a's to-sessionstests).
- **SQL, detail og partner** (samme job): `principal_partners`, `family_context_sha256` og alle fire
  `review_reason`-grene; `IDENTITY_PARTNER_CONTEXT_STALE` ved ændret familie mellem visning og kald, ved
  forkert familie og ved en ikke-partner; nøglerne afvises sammen med `candidate_id` eller `human_sheet`.
  **To sessioner:** partnerknappen mod kandidatvejen og mod den frie personvælger på samme persona —
  den ene venter og fejler derefter på versionen, ingen deadlock.
- **ACL** (`db-verify.sql` efter `db-rls.sql`): de to nye RPC'er kaldbare for `authenticated`, ikke for
  `PUBLIC`/`anon`/`service_role`; kvitteringstabellen uden grants og med RLS.
- **Opgradering** (`tests/sql/test-relation-binding-upgrade.sh`, kun lokalt), to kæder (memory:
  signaturændring kræver opgraderingstest): (a) fra `ebf2022` (main før 2a) til HEAD — deploystien; (b) fra
  2a's head `31008f5`: bind en v1-batch, opgradér, gentag det præcise v1-kald (samme batch-id, 0 rækker),
  lav en genbinding, anvend et ark med både `B` og `F` (den udvidede klassifikations-CHECK på en opgraderet
  2a-base), og kør derefter hele `db-migrations.sql` og `db-rls.sql` **to gange mere** uden fejl. Begge
  kæder slutter med `db-verify.sql` grøn.
- **Python:** `test_spouse_exception_sheet.py` — render/check-rundtur, afvisning af omformede, manglende,
  dublerede og omordnede linjer, svar-JSON, `sheet_sha256`, golden vector for `answers_sha256` (samme fixture
  som SQL; også et ark med kontekstlinjer, hvor fysiske og logiske linjenumre afviger), noter med
  kontroltegn afvist, og stinegativerne fra §5.2.
- **Web:** vitest for de DB-formede mappere for kø, detalje og historik med id'er som strenge (inkl. et id
  over `Number.MAX_SAFE_INTEGER`, der skal komme uændret ud i visningen og i RPC-argumentet), partnerboks,
  knap med `partner_family_id`/`family_context_sha256` og kildekravet ved `spouse`; Playwright-spec for køens
  detalje med syntetiske svar, som 2a.
- **Hele CI lokalt** før push (7 jobs, PG-jobs i hver sin klynge, `env -u PGOPTIONS`).

## 11. Prod og fortrydelse

Som 2a-specen §9: restore-only fortrydelse; 2b-i går ikke i prod alene, men med 5b's samlede overførsel efter
5a's ceremoni; `get_advisors` er gate i overførslens runbook umiddelbart efter DDL. Arkets og køens
afgørelser ligger som hændelser i bevisbasen (identitetshændelser, klassifikationshændelser, change_set) og
gentages i prod gennem samme RPC'er som del af overførslens spec.

## 12. Afvigelser fra og præciseringer af 2a-specen og hovedspecen

1. 2a-specen §4.4's »højst én familiebinding pr. fortolkning« bliver »pr. fortolkning og tilstand«, og
   tabellens generelle unikhedsregel bliver partiel for ikke-familiemål (§4.1).
2. 2a-blokkens gamle indeks fjernes fra migrationen (§4.1); muligt, fordi 2a ikke er deployet.
3. Previewkontrakten går til `relation-promotion-preview-v2` (§4.2).
4. 2b deles i 2b-i og 2b-ii (§2).
5. Første bevidste kanoniske ændring i 5b: ordinal på højst 3 rækker gennem den eksisterende redaktør-writer
   inde i en ny ark-RPC (§5.4); færdigbeviset kræver et præcist delta i stedet for 0.
6. Klassifikationstabellen får `ordinal_rettet` og `ordinal_beholdt`; ny kvitteringstabel og to nye RPC'er
   (§5.5).
7. `red_afgoer_source_persona` får valgfri partnerkontekst (§6.3).
8. Arkets `A`/`U` skriver intet; de afgøres i køen (§5.4).
9. `red_source_persona_detail`, `red_source_persona_queue` og `red_source_persona_history` udleverer
   bigint-id'er som tekst; de to sidste genskabes med ny returtype (§6.2).
10. Ark-RPC'en tager en `SHARE`-lås på `family_member` i sin korte transaktion (§5.4 trin 3).

## 13. Uden for 2b-i

1. De 14 ægteskabspåstande uden ægtefælle-persona, `new_person_needed` og `different` fra køen → 2b-ii.
   Genafgørelse af en accepteret relation, hvis struktur er flyttet til en anden familie → 2b-ii.
2. De 2 `proposed` forælderpåstande (`F`/`U`) og familiekorrektion for `F`-kortet → parkeret
   (projektejerbeslutning).
3. `samme_som` for dubletten fra del 1 → parkeret.
4. Klausul-dispositionen → 2b-ii, sidst.
5. Kildevisning i mobil, Playwright i CI → uændret åbne (2a-specen §11).

## 14. Review runde 1 (Codex `gpt-5.6-sol`, 2026-10-11)

NO-GO: 4 BLOCKER, 8 MAJOR, 1 MINOR. Alle efterprøvet mod koden og godtaget.

| # | Fund | Alvor | Rettelse |
| --- | --- | --- | --- |
| 1 | CHECK med `->>` bliver `NULL` ved manglende nøgle og godtages | BLOCKER | §4.1 ikke-NULL-udtryk; tests for nøgle/null/type/format |
| 2 | Tabellens `UNIQUE (interpretation_id, target_type, target_id)` forbyder genbinding i samme familie | BLOCKER | §4.1 erstattes af partielt indeks for ikke-familiemål |
| 3 | 2a-blokkens `CREATE UNIQUE INDEX IF NOT EXISTS` fejler ved genkørsel efter første genbinding | BLOCKER | §4.1 fjernes fra 2a-blokken; §10 genkørsel to gange efter genbinding |
| 4 | Arkets kontrol og kanoniske skrivning ikke låst sammen | BLOCKER | §5.4 ark-RPC: låse → genberegning → skrivning; to-sessionstest |
| 5 | `rows_sha256` bandt ikke det viste grundlag | MAJOR | §5.1 hash over hele projektionen |
| 6 | Partnerknappen kunne skrive en forældet identitet | MAJOR | §6.3 serverkontrol under lås |
| 7 | `F` efterlod intet spor | MAJOR | §5.4 `ordinal_beholdt`/`ordinal_rettet`-hændelser |
| 8 | »Eget change_set pr. `B`« umuligt i én transaktion | MAJOR | §5.4 ét change_set, linjen knyttet via hændelsen |
| 9 | Decimalstreng-id'er stoppede ved `Number.isSafeInteger` | MAJOR | §6.4 streng hele vejen; test over safe-integer |
| 10 | Replay af v1-batches ubevist efter opgradering | MAJOR | §10 kæde (b) gentager et v1-kald |
| 11 | Privatliv kun som operatørkonvention | MAJOR | §5.2 stihåndhævelse i værktøjet + negative tests |
| 12 | »Sidste genkald = 0« beviste ikke et lukket univers | MAJOR | §9 univers i spande med eksplicit årsagsliste |
| 13 | Køfiltret var tværkilde | MINOR | §6.1 kildekrav i UI ved `spouse`; målt 0 i andre kilder |

## 15. Review runde 2 (Codex `gpt-5.6-sol`, 2026-10-12)

NO-GO: 4 BLOCKER, 6 MAJOR, 1 MINOR. Runde 1's fund 1, 2, 3, 5, 7, 10, 11 og 13 bekræftet løst; fund 4's
TOCTOU lukket. Alle nye fund efterprøvet mod koden og godtaget.

| # | Fund | Alvor | Rettelse |
| --- | --- | --- | --- |
| 1 | De nye RPC'er står ikke i `db-rls.sql`'s allow-liste og bliver ukaldbare | BLOCKER | §5.5 ACL + asserts efter RLS |
| 2 | Partnerkontrollen låste familie før persona, omvendt af identitetskernen: deadlock | BLOCKER | §6.3 persona → identitet → familie; §5.4 trin 5 samme orden; to-sessionstest |
| 3 | Ark-RPC'en kunne melde sig ind i et fremmed change_set | BLOCKER | §5.4 trin 2 `SPOUSE_SHEET_FOREIGN_CHANGE_SET` |
| 4 | Svarene var ikke serverbundet til godkendelsen; kun id-mængden blev tjekket | BLOCKER | §5.3 `answers_sha256` genberegnet i serveren; §5.4 trin 6 præcis linjemapping |
| 5 | `NULL`-kilde omgik kildelåsen | MAJOR | §5.1/§5.4 trin 1; tom projektion afvist |
| 6 | Ingen replay ved tabt svar | MAJOR | §5.5 kvittering; §5.4 trin 4 |
| 7 | `o_rows` kunne genoplive en historisk klassifikation | MAJOR | §5.1 gældende version, tilstand og afvigelse; målt 3/3 |
| 8 | `B` kunne gøre en anden kildes binding forældet uden at nogen så det | MAJOR | §5.4 trin 9 afvisning; §9 globalt 0 forældede |
| 9 | Id'er blev afrundet som JSON-tal før strengkonverteringen | MAJOR | §6.2 `::text` i detail; §6.4 fri vælger `id::text`; test af DB-formet mapper |
| 10 | Klassifikations-CHECK blev ikke udvidet på en opgraderet 2a-base | MAJOR | §5.5 idempotent constraint-skift; §10 `B`+`F` i opgraderingen |
| 11 | Projektionens array- og linjeorden udefineret | MINOR | §5.1 orden og kanonisk linjemapping |

## 16. Review runde 3 (Codex `gpt-5.6-sol`, 2026-10-12)

NO-GO: 1 BLOCKER, 3 MAJOR. Runde 2's fund 1, 3, 5, 6, 7, 10 og 11 bekræftet løst; fund 4's serverbinding
tilføjet; fund 2, 8 og 9 delvist lukket og fulgt op her.

| # | Fund | Alvor | Rettelse |
| --- | --- | --- | --- |
| 1 | Rækker uden for arket kunne blive egnede mellem genberegning og commit (familiewritere tager ikke kildelåsen) | BLOCKER | §5.4 trin 3 `SHARE`-lås på `family_member`; fantomtest |
| 2 | `line` og noter ikke entydige på tværs af Python og SQL | MAJOR | §5.3 logisk linjeordinal, note-normalisering, kontroltegn afvist; delt golden vector |
| 3 | Kø og historik leverede stadig bigint som JSON-tal | MAJOR | §6.2 tekst-id'er i alle tre RPC'er, DROP/genskab, returtype-asserts; §6.4 typer |
| 4 | »0 forældede bindinger« modsagde append-only-historikken | MAJOR | §9 præcis invariant; historiske bindinger rapporteret særskilt |
