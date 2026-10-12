# Trin 5b del 2b-i — genbinding efter rettelse, ordinal-afvigelserne og de uafgjorte ægtefæller (#151)

**Status:** Design godkendt af projektejeren 2026-10-11, afsnit for afsnit (brainstorm samme dato). Fire
Codex-runder (`gpt-5.6-sol`, alle NO-GO) fandt fire reelle fejl i det godkendte design, men deres rettelser
voksede spec'en fra ca. 290 til 539 linjer med nye RPC'er, en kvitteringstabel og en tabellås. Projektejeren
bad derfor 2026-10-12 Opus afveje hvert fund (nødvendig / forenkl / kendt begrænsning / afvis); dette er den
slanke version, skrevet efter den afvejning og projektejerens ja (§14). `F` skrives som hændelse
(`ordinal_beholdt`) efter projektejerens valg. Afventer projektejerens gennemlæsning.

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
| Leverancetype | Generel motor: genbinding af familiebindinger efter en rettelse; et generelt undtagelsesark (udtræk + psql-script, som del 1) for ægtefæller hvis partner er kandidat nr. 1; partnerkontekst og strukturel årsag i webkøen. Ingen nye RPC'er, ingen nye tabeller. Intet udgavespecifikt |
| Redaktionel/læserrettet værdi | Redaktøren kan rette et bundet ægteskab uden at miste kilden for altid. De 31 uafgjorte ægtefæller afgøres med et kort ark (undtagelser) og en kø med den kontekst, der i dag mangler. Læseren får kilde på op til 31 ægteskaber mere |
| Færdigbevis | §9: i en kopi af 2a's bevisbase; ark hash- og versionsbundet; manifest = efter-digest; 2a's 210 bindinger uændrede; et præcist kanonisk delta (kun ordinal på de rettede rækker); alle relationspåstande i en kendt spand; negativtests |
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
anbefalingen forudfyldt, og projektejeren retter kun det, der er forkert. Mekanikken følger del 1's
kontrolark (`identity_control_rows.sql` + `identity_control_sheet.py`): et udtræk, et værktøj og et
genereret psql-script i én transaktion. Ingen nye RPC'er.

### 5.1 Projektionen

Én privat, læsende funktion `private.spouse_exception_projection(p_source_id bigint) RETURNS jsonb`
(`STABLE`, `SECURITY DEFINER`, `SET search_path=pg_catalog,public,private`, ingen grants). Den findes, så
udtrækket og scriptets genberegning bruger præcis samme SQL. Den returnerer `{contract:
'spouse-exception-rows-v1', source_id, s_rows, o_rows}`:

- **`s_rows`** — ægtefælle-personas i kilden uden `accepted` identitet, hvor `private.persona_family_context`
  ikke er `NULL`, og hvor kandidat nr. 1 i den gældende kandidatkørsel er partner til hovedpersonen i en af
  dens familier. Pr. række: `source_persona_id`, `identity_version` (0 uden hændelse), `candidate_id`,
  `run_id`, `candidate_rank`, `candidate_tier`, `candidate_score`, `candidate_count`, `candidate_person_id`,
  `principal_person_id`, `family_id`, `family_ordinal`, kandidatens visningsfelter (`visning_navn`,
  `visning_fuldt_navn`, `visning_foedt`, `visning_doed`) og personaens mentions (`mention_role`,
  `verbatim_text`, `ORDER BY source_persona_mention.ordinal`).
- **`o_rows`** — ægteskaber i kilden med en **gældende** `ordinal_afvigelse` (Codex r2 #7, 2a-specen §4.5):
  den seneste klassifikationshændelse for nøglen er `ordinal_afvigelse`, dens `interpretation_id` er den
  gældende version med status `accepted`, dens `state_sha256` er lig den nuværende tilstands hash, og
  tilstandens `book_ordinal` afviger fra `family_ordinal`. Pr. række: `interpretation_id`, `family_id`,
  `principal_person_id`, `spouse_person_id`, `book_ordinal`, `family_ordinal`, `state_sha256`. (Målt: alle 3
  opfylder kriteriet.)
- **Orden** (Codex r2 #11): `s_rows ORDER BY source_persona_id::text COLLATE "C"`, `o_rows ORDER BY
  interpretation_id::text COLLATE "C"`.
- Fejler (`SPOUSE_SHEET_CONTROL_SAMPLE`), hvis en persona fra `s_rows` ligger i en `identity_control_sample`.

**Udtrækket** `.claude/skills/daa-extract/scripts/spouse_exception_rows.sql` kører læsende som operatør
(`SET default_transaction_read_only=on`, `TimeZone=UTC`, fast `search_path`) og skriver præcis
`private.spouse_exception_projection(:source)::text` efterfulgt af én LF til rækkefilen (`psql -XAt`).
`rows_sha256` = SHA-256 af rækkefilens bytes — samme definition som del 1, og samme bytes som scriptets
genberegning (§5.3) — så hashen binder alt, arket viser (Codex r1 #5).

### 5.2 Værktøjet og linjeformatet

`.claude/skills/daa-extract/scripts/spouse_exception_sheet.py` med `render` og `sql`, bygget på
`decision_sheet_core` som del 1 (`verify_bound`, `sql_literal`, `require_hex64`); tests i
`test_spouse_exception_sheet.py`.

- `S <persona-uuid> <version> : <tok>  # note`, `<tok>` ∈ `S` (samme, forudfyldt), `A` (anden), `U`
  (uafklaret). Under linjen: kildens navn og år, kandidatens navn og år, familiens id og ordinal, tier, score
  og antal kandidater.
- `O <interpretation-uuid> <bog>/<familie> : <tok>  # note`, `<tok>` ∈ `B` (ret familien til bogens nummer),
  `F` (behold familiens). Forudfyldt med Claudes forslag; begrundelsen står under linjen.

`render` skriver linjerne i projektionens orden. `sql` læser ark og rækkefil præcis én gang, kræver
`sheet_sha256` lig den godkendte hash og `rows_sha256` lig den forventede (`verify_bound`), afviser
ukendte, manglende, dublerede, omformede og omordnede linjer, og skriver først derefter scriptet.

**Privatliv** (Codex r1 #11, forenklet): værktøjet nægter ind- og udstier, der efter `realpath` ikke ligger
under `$HOME/.private/`, eller som ligger i et git-arbejdstræ; nye filer får mode `0600`. Det skriver kun
antal og hashes til terminalen.

### 5.3 Det genererede script

Én transaktion, `\set ON_ERROR_STOP on`, i denne rækkefølge (Codex r1 #4: låse før kontrol, kontrol før
skrivning):

1. Som operatør: `pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||source,0))` (eksklusiv;
   samme nøgle som kandidatwriteren, `red_decide_relation_interpretations` og — delt —
   `red_afgoer_source_persona`).
2. `private.lock_family_rows` over alle person-id'er, arket berører (hovedpersoner og kandidater i `s_rows`,
   hovedpersoner og ægtefæller i `o_rows`), sorteret.
3. Genberegn `encode(sha256(convert_to(private.spouse_exception_projection(source)::text||E'\n','UTF8')),'hex')`
   under samme `TimeZone` og `search_path` som udtrækket; afviger den fra `rows_sha256`, `RAISE EXCEPTION
   'SPOUSE_SHEET_ROWS_STALE'`.
4. For hver `B`: kontrollér, at hovedpersonens partnerrække stadig har `family_ordinal` fra rækkefilen.
5. `SET LOCAL ROLE authenticated` og `request.jwt.claim.sub` (som del 1; aktøren filtreres fra output):
   - **`S`** → `red_afgoer_source_persona(persona, version, 'same', candidate_person_id, note,
     {basis: 'human_sheet', sheet_sha256, rows_sha256, line, candidate_id, run_id})`. Kandidat- og
     kørsels-id binder svaret til den gældende kandidatkørsel.
   - **`B`** → `red_set_familie_ordinal(family_id, principal_person_id, 'partner', book_ordinal)`.
   - **`A`/`U`** skriver intet; personaen forbliver `proposed` og afgøres i køen (§6).
6. `RESET ROLE`; for hver **`F`** → `private.append_relation_classification(interpretation_id,
   'ordinal_beholdt', {sheet_sha256, rows_sha256, line, book_ordinal, family_ordinal, note})` (aktøren er
   `auth.uid()` fra jwt-claimet). Der er ingen RPC til klassifikationer; scriptet er operatørens, som
   udtrækket.
7. En `DO`-blok kontrollerer antallet af skrivninger pr. token mod arket; ellers fejl. `COMMIT`.

Alle kald i transaktionen deler ét change_set (`begin_change_set` er re-entrant; Codex r1 #8). Et `B` gør
bindingens tilstand forældet; kilden er skjult, indtil efterkørslen binder igen (§7). Klassifikationen
`ordinal_afvigelse` bliver stående som historik ved `B`; ved `F` er den seneste hændelse `ordinal_beholdt`.

### 5.4 Data

- `private.relation_classification_event`s CHECK `relation_classification_event_kind_check` udvides til
  `('ordinal_afvigelse', 'ordinal_beholdt')`. Opgradering (Codex r2 #10), idempotent og ens i `schema.sql` og
  `db-migrations.sql`: i en `DO`-blok, kun hvis `pg_get_constraintdef` afviger, `DROP CONSTRAINT`, `ADD
  CONSTRAINT … NOT VALID`, `VALIDATE`. `db-verify.sql` sammenligner definitionen.
- `private.spouse_exception_projection(bigint)`: `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`;
  `db-verify.sql` asserterer, at ingen af de tre roller har `EXECUTE`.

`red_afgoer_source_persona` og `red_set_familie_ordinal` ændres ikke.

## 6. Webkøen: de 8 + 1 og arkets undtagelser

### 6.1 Finde sagerne

Med kildefilteret sat til kilde 1 giver køens filtre `status=proposed` og `mention_role=spouse` præcis de
resterende sager (målt: 0 `proposed` ægtefælle-personas i andre kilder). `red_source_persona_queue` ændres
ikke.

### 6.2 Kontekst i `red_source_persona_detail`

Samme signatur og samme id-kontrakt som i dag (JSON-tal; webkoden afviser allerede tal, der ikke er sikre
heltal, `sourcePersona.ts` ~120). To nye felter, kun for personas med en `spouse`-mention:

- `principal_partners`: hovedpersonens partnere i kanoniske familier, fra `private.persona_family_context`:
  pr. partner `person_id`, `family_id`, `name`, `born`, `died`, `ordinal` og `konfidens`, sorteret efter
  familie og person.
- `review_reason`, udledt af tilstanden (gemmes ikke), i denne rækkefølge:
  1. `context_unavailable` — `persona_family_context` er `NULL` (hovedpersonen er ikke `accepted`, eller
     ægtefællen har ikke præcis én ægteskabsrelation);
  2. `principal_no_family` — hovedpersonen har ingen familie som partner;
  3. `partner_is_candidate` — kandidat nr. 1 i den gældende kørsel er en af partnerne (arkets undtagelser);
  4. `partner_not_candidate` — ellers.

  For en afgjort persona er feltet `null`.

### 6.3 UI

`web/src/data/sourcePersona.ts` parser de to felter. `KildepersonaKo.tsx` viser øverst i detaljen årsagen på
dansk og en boks »Hovedpersonens partnere i databasen«; hver partner har knappen »Samme som denne partner«,
der kalder den eksisterende `same`-vej med partnerens person-id uden `candidate_id` (samme vej som den frie
personvælger) og en forudfyldt note med familie-id'et. Sikkerhedsnettet er efterkørslens strukturregel
(§7): en relation afgøres og bindes kun, hvis begge parter er partnere i præcis én familie (2a-specen §4.2);
planen bekræfter det i koden.

### 6.4 Afgørelser pr. sag (hovedspecen §23.5)

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
ægteskaber 203 + s + k; nye bindinger s + k (hvis strukturen er entydig); genbindinger b (plus evt.
forælderbindinger i samme familie, hvis tilstand rummer den rettede række); gældende bindinger 210 + s + k.

## 8. Privatliv

Uændret fra 2a-specen §6. Projektionen er privat (ingen grants); detail-felterne er redaktionsgatede.
Værktøjet håndhæver den private placering (§5.2). Repo, rapport og chat indeholder tal og hashes, ingen navne,
ingen kildetekst og ingen persona-, person- eller aktør-id'er. Rækkefil, ark, script og forslagsfil ligger
kun i `~/.private/5b-2b-i/`.

## 9. Færdigbevis (i restore, ikke i prod)

Arbejdsbase: en ny kopi `daa5b_2b_i_bevis_<ts>` af `daa5b_2a_bevis_20261011185524` (som bevares uændret),
løftet med `db-migrations.sql` og `db-rls.sql`; `db-verify.sql` grøn inkl. de nye asserts. Rapport:
`docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md`.

| Bevis | Krav |
| --- | --- |
| Ark | `rows_sha256`, `sheet_sha256`, scriptets SHA-256; antal `S`/`A`/`U`/`B`/`F`; ét change_set |
| Kø | k afgjort, fordelt på §6.4's klassifikationer |
| Afgørelse og binding | set-hash, previewhash, manifest = efter-digest, antal nye og genbindinger |
| 2a's bindinger | de 210 oprindelige rækker uændrede (tupel-digest `89bde7603f8c…5923` genberegnet over dem) |
| Kanonisk delta | `person`, `family`, `fact`, `assertion`, `citation`, `conclusion` uændrede (md5 som 2a); `family_member` afviger **kun** i `ordinal` på de b rækker fra `B`, alle under arkets change_set |
| Læsning | `public_family_sources` som `anon` giver 210 + s + k rækker; v2-biografilæsningen for 2a's 50 faste personer uændret |
| Lukket univers (Codex r1 #12) | Hver af kildens gældende relationspåstande (272 ved start) ligger i præcis én spand: `accepted` med en binding, der passer den nuværende tilstand; `accepted` uden — skal være **0**; ikke `accepted`, talt pr. årsag mod en eksplicit liste (ægteskab uden ægtefælle-persona 14; ægtefælle `new_person_needed`/`different`/`unresolved` fra køen; forælder `proposed` 2; forælder `rejected` 1; `relation.child` 14). En årsag uden for listen gør beviset rødt |
| Globalt (Codex r3 #4) | I **alle** kilder: 0 gældende `accepted` fortolkninger, der har mindst én familiebinding, men ingen, hvis `target_id` og `state_sha256` passer den nuværende tilstand. Historiske bindinger med en anden tilstand er forventede (append-only, §4) og tælles særskilt: lig antallet af genbindinger |
| Genkald | en ekstra efterkørsel giver 0 egnede elementer og 0 nye rækker |

Negativtests, hver i sin egen kopi:

- A: scriptet med en ændret rækkefil (eller en ændret persona-version efter udtrækket) → `SPOUSE_SHEET_ROWS_STALE`,
  0 skrivninger.
- B: et ark, hvis hash ikke er den godkendte → værktøjet skriver intet script.
- C: genbinding med forældet previewhash → `RELATION_PROMOTION_PREVIEW_STALE`, 0 rækker.
- D: `B` anvendt uden efterkørsel → netop den familie har 0 kilderækker og universet en `accepted`-uden-
  binding; efter efterkørslen 1 kilderække og 0.

## 10. Test

- **SQL, genbinding** (`tests/sql/test-relation-binding.sql`, job `evidence-promotion-db`): bind → ret
  ordinal → kilden skjult → preview egnet med `supersedes_promotion_id` → bind → kilden synlig, 2 rækker, den
  gamle uændret; identisk genkald skriver ingen tredje; samme forløb med en ny identitetsversion;
  tilbage-rettelse giver `ALREADY_APPLIED`; struktur flyttet til en anden familie giver
  `RELATION_PROMOTION_REBIND_FAMILY_CHANGED`; CHECK afviser en familiebinding uden nøglen, med JSON-`null`,
  med et tal og med forkert format; to bindinger med samme tilstand afvises; en ikke-familiebinding med samme
  `(interpretation_id, target_type, target_id)` afvises stadig.
- **SQL, ark** (ny `tests/sql/test-spouse-exception-sheet.sql`, samme job): projektionens udvælgelse og orden
  (inkl. en historisk `ordinal_afvigelse`, hvis tilstand er ændret, der ikke kommer med); kontrolstikprøve
  afvist; ingen grants på projektionen; et genereret script på en lille fixture: `S`/`B`/`F` skriver det
  rigtige, `A`/`U` intet, ét change_set; samme script efter en ændring af projektionen fejler med
  `ROWS_STALE` og 0 skrivninger; `ordinal_beholdt` godtages af CHECK.
- **SQL, detail** (samme job): `principal_partners` og alle fire `review_reason`-grene; redaktionsgaten.
- **Opgradering** (`tests/sql/test-relation-binding-upgrade.sh`, kun lokalt; memory: signaturændring kræver
  opgraderingstest): fra 2a's head `31008f5` med familiebindinger → opgradér → lav en genbinding og skriv en
  `ordinal_beholdt` → kør `db-migrations.sql` og `db-rls.sql` **to gange mere** uden fejl → `db-verify.sql`
  grøn. Kæden fra `main` hører til overførsels-spec'en.
- **Python:** `test_spouse_exception_sheet.py` — render/sql-rundtur, hashbinding (`verify_bound`), afvisning
  af omformede, manglende, dublerede og omordnede linjer, scriptets rækkefølge og tælleblok, stinegativer
  (sti uden for `~/.private`, sti i et git-arbejdstræ).
- **Web:** vitest for parsing og partnerboks/knap; Playwright-spec for køens detalje med syntetiske svar, som
  2a.
- **Hele CI lokalt** før push (7 jobs, PG-jobs i hver sin klynge, `env -u PGOPTIONS`).

## 11. Prod og fortrydelse

Som 2a-specen §9: restore-only fortrydelse; 2b-i går ikke i prod alene, men med 5b's samlede overførsel efter
5a's ceremoni; `get_advisors` er gate i overførslens runbook umiddelbart efter DDL. Arkets og køens
afgørelser ligger som hændelser i bevisbasen og gentages i prod som del af overførslens spec, som også skal
tage stilling til de kendte begrænsninger i §12.

## 12. Kendte begrænsninger

Afvejet af Opus 2026-10-12 som teoretiske ved denne skala (31 personas, 3 linjer, én redaktør, lokal
restore-kopi); overførsels-spec'en tager dem op igen, hvis arket køres i prod eller bliver en webflade:

1. **Samtidige familieredigeringer.** Scriptet holder kildelåsen og låser de berørte personers familier, men
   redaktørens familiewritere tager ikke kildelåsen. En række, der bliver egnet under kørslen, er ikke på
   arket og afgøres i køen; der skrives intet forkert. I restore-kopien findes ingen anden skriver (Codex r3
   #1).
2. **Partnerknappen** bruger den eksisterende `same`-vej uden serverkontrol af partnerskabet, som den frie
   personvælger. En forkert partner bindes aldrig (§6.3), og identiteten rettes med en ny hændelse (Codex r1
   #6).
3. **Ingen kvittering.** Et genkald af et committet script fejler lukket (version, rækkehash); udfaldet
   aflæses af change_set'et (Codex r2 #6).
4. **Andre kilder.** Kun kilde 1 har familiebindinger (målt). Om et `B` kan gøre en anden kildes binding
   forældet, afgøres i overførsels-spec'en; rapporten kører alligevel den globale regel (§9) (Codex r2 #8).
5. **Id'er som JSON-tal** i kø, detalje og historik. Webkoden afviser tal, der ikke er sikre heltal; målt
   maks-id er langt derunder (Codex r2 #9, r3 #3).
6. **Køen er ikke kildelåst.** Målt 0 sager uden for kilde 1; kildefiltret sættes i hånden (Codex r1 #13).
7. **Det genererede script må ikke håndredigeres.** Rapporten bærer dets SHA-256.
8. **`F` skrives af operatørens script** gennem en privat funktion, fordi der ingen klassifikations-RPC
   findes; prod-vejen afgøres i overførsels-spec'en.

## 13. Afvigelser og uden for 2b-i

**Afvigelser fra 2a-specen og hovedspecen:**

1. 2a-specen §4.4's »højst én familiebinding pr. fortolkning« bliver »pr. fortolkning og tilstand«, og
   tabellens generelle unikhedsregel bliver partiel for ikke-familiemål (§4.1).
2. 2a-blokkens gamle indeks fjernes fra migrationen (§4.1); muligt, fordi 2a ikke er deployet.
3. Previewkontrakten går til `relation-promotion-preview-v2` (§4.2).
4. 2b deles i 2b-i og 2b-ii (§2).
5. Første bevidste kanoniske ændring i 5b: ordinal på højst 3 rækker gennem den eksisterende redaktør-writer
   (§5.3); færdigbeviset kræver et præcist delta i stedet for 0.
6. Klassifikationstabellen får `ordinal_beholdt` (§5.4).

**Uden for 2b-i:**

1. De 14 ægteskabspåstande uden ægtefælle-persona, `new_person_needed` og `different` fra køen → 2b-ii.
   Genafgørelse af en accepteret relation, hvis struktur er flyttet til en anden familie → 2b-ii.
2. De 2 `proposed` forælderpåstande (`F`/`U`) og familiekorrektion for `F`-kortet → parkeret
   (projektejerbeslutning).
3. `samme_som` for dubletten fra del 1 → parkeret.
4. Klausul-dispositionen → 2b-ii, sidst.
5. Kildevisning i mobil, Playwright i CI → uændret åbne (2a-specen §11).

## 14. Review og afvejning (2026-10-11/12)

Codex `gpt-5.6-sol` runde 1-4 (alle NO-GO; 4+4+1+0 BLOCKER) på det godkendte design og dets successive
revisioner. Opus afvejede runde 1-3's 28 fund; runde 4's tre fund ramte alle dele, som den slanke version
fjerner (tabellås, DROP/genskab af kø-RPC'er). Projektejeren godkendte den slanke version 2026-10-12.
Rundernes fulde revisioner ligger i git-historikken (`7d23710`, `6cde88b`).

| Dom | Fund | Hvor |
| --- | --- | --- |
| Nødvendig | r1 #1 (CHECK-NULL), #2 (tabellens UNIQUE), #3 (genkørsel af 2a-indeks), #8 (ét change_set); r2 #7 (gældende klassifikation), #10 (CHECK-opgradering), #11 (orden); r3 #4 (præcis bindingsinvariant) | §4.1, §5.1, §5.3, §5.4, §9 |
| Forenklet | r1 #4 (låse før kontrol: scriptets rækkefølge, ikke en RPC), #5 (hash over hele projektionen med samme SQL), #7 (kun `ordinal_beholdt`), #9 (eksisterende tal-kontrakt), #11 (én stikontrol), #12 (univers som rapportforespørgsel); r2 #4 (værktøjet kræver godkendt `sheet_sha256`, som del 1) | §5.1-§5.3, §6.2, §9 |
| Kendt begrænsning | r1 #6, #13; r2 #6, #8, #9; r3 #1, #3 | §12 |
| Afvist | r1 #10 (2a ikke deployet: løftet om v1-replay er slettet); r2 #1, #2, #3, #5, r3 #2 (følgefund af RPC'er, der ikke længere findes) | — |
