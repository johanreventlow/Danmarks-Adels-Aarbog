# Trin 5b del 2b-i — genbinding efter rettelse, ordinal-afvigelserne og de uafgjorte ægtefæller (#151)

**Status:** Design godkendt af projektejeren 2026-10-11, afsnit for afsnit (brainstorm samme dato). Spec'en
afventer projektejerens gennemlæsning og et Codex-review før planen.

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
| Familiebindinger | 210 (203 ægteskab, 7 forælder); 0 forældede; alle 210 har en `state_sha256` på 64 hex-tegn (0 afvigere); `identity_control_exclusion` 0 rækker |

## 4. Genbinding (2a-specen §11 pkt. 6, mulighed a)

**Princip:** en ny binding ved siden af den gamle. Den gamle række bliver stående som historik (append-only,
invariant 1); læseren bruger den binding, hvis tilstand passer nu. Fravalgt: en afløsningshændelse i egen
tabel (mere maskineri for samme resultat) og opdatering/sletning af den gamle række (bryder append-only).

### 4.1 Data

- Det partielle unikke indeks `interpretation_promotion_one_family_per_interpretation` (2a) erstattes af
  `interpretation_promotion_one_family_per_state ON private.interpretation_promotion (interpretation_id,
  (evidence->>'state_sha256')) WHERE target_type='family'`: højst én familiebinding pr. fortolkning **og
  tilstand**.
- En familiebinding skal have en tilstandshash: `CHECK (target_type<>'family' OR evidence->>'state_sha256' ~
  '^[0-9a-f]{64}$')` (navn `interpretation_promotion_family_state_check`). Ellers ville en `NULL`-hash slippe
  uden om indekset. De 210 eksisterende rækker opfylder den (målt, §3).
- **Opgradering** (`db-migrations.sql`, idempotent): opret det nye indeks, tilføj CHECK som `NOT VALID` og
  `VALIDATE`, og drop først derefter det gamle indeks, så der aldrig er et vindue uden unikhed. De 210
  bindinger består uændret. Det gamle indeksnavn står i `schema.sql` (2a-sektionen), `db-migrations.sql`
  (2a-blokkens `CREATE UNIQUE INDEX IF NOT EXISTS`, som skal blive stående, så en base løftet fra før 2a
  stadig ender med det nye indeks) og `db-verify.sql` (2a-assertblokken, der skal assertere det nye navn
  og fraværet af det gamle).

### 4.2 Preview og batch

`private.preview_relation_promotions` ændres i ét led: et element er `RELATION_PROMOTION_ALREADY_APPLIED`,
kun når der findes en familiebinding for fortolkningen **med den nuværende `state_sha256`**. Findes der kun
forældede bindinger, er elementet egnet, og previewet sætter `supersedes_promotion_id` til den seneste
forældede familiebinding for fortolkningen (`ORDER BY promoted_at DESC, id DESC LIMIT 1`, ellers `null`). En genbinding kræver, at den nuværende tilstands
familie er den forældede bindings familie (`target_id`); ellers er elementet ikke egnet
(`RELATION_PROMOTION_REBIND_FAMILY_CHANGED`), fordi påstanden blev afgjort for en anden familie. Feltet indgår i elementerne og dermed i
previewhashen; kontrakten hedder derfor `relation-promotion-preview-v2`. Gamle batches' replay påvirkes ikke:
replay slås op på den gemte previewhash, før previewet genberegnes.

`red_promote_relation_interpretations_batch` skriver `supersedes_promotion_id` med i bindingens evidens. Ingen
ny RPC, ingen ny skrivevej, ingen ændret signatur.

Tilbage-rettelse: rettes ordinalen fra A til B (genbinding ved B) og senere tilbage til A, passer den gamle
binding igen; previewet siger `ALREADY_APPLIED`, og der skrives intet.

### 4.3 Læsning

`public.public_family_sources` ændres ikke: den kræver allerede, at bindingens `state_sha256` er lig den
nuværende tilstands hash (2a-specen §5.1 trin 2). Med det nye indeks kan højst én binding pr. fortolkning
opfylde det.

### 4.4 Hvad genbinding dækker

En ændring af de felter, tilstanden rummer (2a-specen §4.2), uden ny fortolkningsversion og i **samme
familie**: ordinal eller konfidens på de bærende rækker, eller en ny identitetsversion til samme person. En
ny fortolkningsversion får som hidtil sin egen binding. Flytter strukturen til en anden familie (fx en
identitet afgjort til en anden person), bindes der ikke igen (§4.2): påstanden blev afgjort for den gamle
familie, og en genafgørelse hører ikke til 2b-i (§13).

## 5. Arket: 22 ægtefæller og 3 ordinal-afvigelser

Menneskelig kontrol er undtagelser (memory: ingen flere fulde afgørelsesark): Claude bygger arket med
anbefalingen forudfyldt, og projektejeren retter kun det, der er forkert.

### 5.1 Værktøj (generelt, i repo)

Efter mønstret fra del 1's kontrolark (`identity_control_rows.sql` + `identity_control_sheet.py`):

- `.claude/skills/daa-extract/scripts/spouse_exception_rows.sql` — udtrækker for én kilde (a) ægtefælle-
  personas uden `accepted` identitet, der indgår i præcis én ægteskabsrelation med en `accepted` hovedperson
  (`private.persona_family_context` ikke `NULL`), og hvis kandidat nr. 1 i den gældende kandidatkørsel er partner til hovedpersonen i en kanonisk familie, og (b)
  ægteskaber med gældende klassifikation `ordinal_afvigelse`. Ingen af personaerne må ligge i en
  `identity_control_sample`; udtrækket fejler ellers.
- `.claude/skills/daa-extract/scripts/spouse_exception_sheet.py` — `render`, `parse`, `check` og `sql`
  som del 1's værktøj; tests i `test_spouse_exception_sheet.py` (python-jobbet).

Udtræk, ark og SQL-fil ligger i `~/.private/5b-2b-i/` (0700, filer 0600). Arket rummer navne og kommer
aldrig i repo eller chat.

### 5.2 Linjeformat

- `S <persona-uuid> <version> <kandidat-uuid> : <tok>  # note` med `<tok>` ∈ `S` (samme, forudfyldt), `A`
  (anden), `U` (uafklaret). Under linjen står kildens navn og år, kandidatens navn og år, familiens id og
  ordinal, og hvorfor maskinen ikke godkendte (navn afviger / flere kandidater).
- `O <family-id> <hovedperson-id> <bog>/<familie> : <tok>  # note` med `<tok>` ∈ `B` (ret familien til
  bogens nummer), `F` (behold familiens). Forudfyldt med Claudes forslag; begrundelsen står under linjen.

Ukendte, manglende, dublerede eller omformede linjer afvises samlet (som del 1).

### 5.3 Hash-binding og anvendelse

- `rows_sha256` = hash af udtrækkets kanoniske rækkesæt: for `S` persona-id, forventet version, kandidat-id
  og kandidatkørsel; for `O` familie-id, hovedperson-id, bogens og familiens nummer og bindingens
  `state_sha256`. `sheet_sha256` = SHA-256 af det udfyldte ark.
- Anvendelsen genudtrækker rækkerne i samme transaktion og afviser, hvis rækkesættet (præcis id-mængden, ikke
  kun antallet) eller `rows_sha256` afviger, eller hvis arkets hash ikke er den godkendte. Hele arket er
  én transaktion: én fejl giver 0 skrivninger.
- `S` → `red_afgoer_source_persona(persona, version, 'same', kandidatens person-id, note, {basis:
  'human_sheet', sheet_sha256, rows_sha256, line, candidate_id, run_id})`. Kandidat-id og kørsels-id binder
  svaret til den gældende kandidatkørsel (`EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE` ellers). Noten er
  arkets note eller standardteksten »ark 2b-i: partner er kandidat nr. 1«.
- `A` og `U` skriver intet. Personaen forbliver `proposed` og afgøres i køen (§6) med fuld kontekst. Arket
  har dermed kun én skrivevej.
- `B` → lås familien og dens rækker (`private.lock_family_rows` med hovedpersonens og ægtefællens
  person-id'er), kontrollér at hovedpersonens partnerrække stadig
  har familiens nummer fra arket, og kald `red_set_familie_ordinal(familie, hovedperson, 'partner', bogens
  nummer)` (eget change_set). Bindingens tilstand bliver forældet; kilden er skjult, indtil efterkørslen
  binder igen (§7). Klassifikationen `ordinal_afvigelse` bliver stående som historik for den bundne
  version (klassifikationstabellen er append-only og kender kun den ene værdi).
- `F` skriver intet. Klassifikationen `ordinal_afvigelse` bliver stående; valget står i rapporten.

`red_afgoer_source_persona` og `red_set_familie_ordinal` ændres ikke.

## 6. Webkøen: de 8 + 1 og arkets undtagelser

### 6.1 Finde sagerne

Køens eksisterende filtre `status=proposed` og `mention_role=spouse` giver præcis de resterende sager.
`red_source_persona_queue` ændres ikke.

### 6.2 Kontekst i `red_source_persona_detail`

Samme signatur (`jsonb`). To nye felter, kun for personas med en `spouse`-mention:

- `principal_partners`: hovedpersonens partnere i kanoniske familier, fra `private.persona_family_context`:
  pr. partner `person_id`, `name`, `born`, `died`, `family_id`, `ordinal` og `konfidens`, sorteret efter
  familie og person (`COLLATE "C"` hvor tekst).
- `review_reason`, udledt af tilstanden (gemmes ikke), i denne rækkefølge:
  1. `context_unavailable` — `persona_family_context` er `NULL` (hovedpersonen er ikke `accepted`, eller
     ægtefællen har ikke præcis én ægteskabsrelation);
  2. `principal_no_family` — hovedpersonen har ingen familie som partner;
  3. `partner_is_candidate` — kandidat nr. 1 i den gældende kørsel er en af partnerne (arkets undtagelser);
  4. `partner_not_candidate` — ellers.

  For en afgjort persona er feltet `null`.

### 6.3 UI

`web/src/data/sourcePersona.ts` parser de to felter (id'er som decimalstrenge). `KildepersonaKo.tsx` viser
øverst i detaljen årsagen på dansk og en boks »Hovedpersonens partnere i databasen«. Hver partner har knappen
»Samme som denne partner«, der kalder den eksisterende `same`-vej med partnerens person-id uden
`candidate_id` (samme vej som den frie personvælger) og en forudfyldt note med familie-id'et.

`red_afgoer_source_persona` får ingen ny strukturkontrol: afgørelsen i §7 (`family-structure-v1`) kræver
begge parter som partnere i samme familie, så en forkert valgt partner bliver aldrig bundet.

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
2. `red_preview_relation_promotions(1, items)` for alle `accepted` relationer i kilden uden en binding med den
   nuværende tilstand: nye bindinger og genbindinger (`supersedes_promotion_id` sat).
3. Manifestet skrives **før** bindingen: tupler `(interpretation_id, family_id, rule_key, rule_version,
   state_sha256, supersedes_promotion_id)`.
4. `red_promote_relation_interpretations_batch(1, items, preview_sha256)`; efter-digest læst fra
   `interpretation_promotion` = manifestet.

Rækkefølge: arket, køen, efterkørslen. Efterkørslen er idempotent og kan køres igen, hvis køen afgøres i
flere omgange; beviset er komplet, når et sidste genkald giver 0 nye rækker.

Forventning (k = `same` i køen ≤ 9 + arkets undtagelser; s = `S`-linjer ≤ 22; b = `B`-linjer ≤ 3): afgjorte
ægteskaber 203 + s + k; nye bindinger s + k (hvis strukturen er entydig); genbindinger b; bindingsrækker i alt
210 + s + k + b; gældende bindinger 210 + s + k.

## 8. Privatliv

Uændret fra 2a-specen §6. Nye læsefelter er redaktionsgatede (`red_source_persona_detail`). Repo, rapport og
chat indeholder tal og hashes, ingen navne, ingen kildetekst og ingen persona-, person- eller aktør-id'er.
Ark og forslagsfil ligger kun i `~/.private/5b-2b-i/`.

## 9. Færdigbevis (i restore, ikke i prod)

Arbejdsbase: en ny kopi `daa5b_2b_i_bevis_<ts>` af `daa5b_2a_bevis_20261011185524` (som bevares uændret),
løftet med `db-migrations.sql` og `db-rls.sql`; `db-verify.sql` grøn inkl. de nye asserts. Rapport:
`docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md`.

| Bevis | Krav |
| --- | --- |
| Ark | `sheet_sha256`, `rows_sha256`; antal `S`/`A`/`U`; `B`/`F` pr. linje (kun linjenummer) |
| Kø | k afgjort, fordelt på §6.4's klassifikationer; øvrige talt som 2b-ii eller parkeret |
| Afgørelse og binding | set-hash, previewhash, manifest = efter-digest, antal nye og genbindinger |
| 2a's bindinger | de 210 tupler uændrede (tupel-digest `89bde7603f8c…5923` genberegnet over de oprindelige rækker) |
| Kanonisk delta | `person`, `family`, `fact`, `assertion`, `citation`, `conclusion` uændrede (md5 som 2a); `family_member` afviger **kun** i `ordinal` på de b rækker fra `B`, hver med sit change_set |
| Læsning | `public_family_sources` som `anon` giver 210 + s + k rækker; 0 forældede bindinger efter efterkørslen; v2-biografilæsningen for 2a's 50 faste personer uændret |
| Genkald | sidste efterkørsel giver 0 nye rækker |

Negativtests, hver i sin egen kopi:

- A: ark med ændret id-sæt eller forkert `rows_sha256` → 0 skrivninger.
- B: en persona-version ændret efter arket blev bygget → hele arket afvist, 0 skrivninger.
- C: genbinding med forældet previewhash → `RELATION_PROMOTION_PREVIEW_STALE`, 0 rækker.
- D: `B` anvendt uden efterkørsel → netop den familie har 0 kilderækker; efter efterkørslen 1.

## 10. Test

- **SQL, frisk sti** (`tests/sql/test-relation-binding.sql`, job `evidence-promotion-db`): bind → ret
  ordinal → kilden skjult → preview egnet med `supersedes_promotion_id` → bind → kilden synlig, 2 rækker, den
  gamle uændret; identisk genkald skriver ingen tredje; samme forløb med en ny identitetsversion; tilbage-
  rettelse giver `ALREADY_APPLIED`; struktur flyttet til en anden familie giver
  `RELATION_PROMOTION_REBIND_FAMILY_CHANGED`; CHECK afviser en familiebinding uden `state_sha256`; indekset afviser to
  bindinger med samme tilstand.
- **SQL, detail** (samme job): `principal_partners` og alle fire `review_reason`-grene; redaktionsgaten.
- **Opgradering** (`tests/sql/test-relation-binding-upgrade.sh`, kun lokalt), to kæder (memory:
  signaturændring kræver opgraderingstest): (a) fra `ebf2022` (main før 2a) til HEAD — deploystien, hvor
  2a's og 2b-i's blokke kører efter hinanden; (b) fra 2a's head `31008f5` med familiebindinger til HEAD —
  indeksskiftet under eksisterende rækker: de gamle rækker består, det nye indeks findes, det gamle ikke,
  og CHECK er valideret.
- **Python:** `test_spouse_exception_sheet.py` (render/parse rundtur, afvisning af omformede linjer,
  hash-binding, SQL for `S` og `B`, intet for `A`/`U`/`F`).
- **Web:** vitest for parsing og boksen/knappen; Playwright-spec for køens detalje med syntetiske svar, som
  2a.
- **Hele CI lokalt** før push (7 jobs, PG-jobs i hver sin klynge, `env -u PGOPTIONS`).

## 11. Prod og fortrydelse

Som 2a-specen §9: restore-only fortrydelse; 2b-i går ikke i prod alene, men med 5b's samlede overførsel efter
5a's ceremoni; `get_advisors` er gate i overførslens runbook umiddelbart efter DDL. Arket og køens
afgørelser er data i bevisbasen og skal gentages eller overføres som del af overførslens spec.

## 12. Afvigelser fra og præciseringer af 2a-specen og hovedspecen

1. 2a-specen §4.4's »højst én familiebinding pr. fortolkning« bliver »pr. fortolkning og tilstand« (§4.1).
2. Previewkontrakten går til `relation-promotion-preview-v2` (§4.2).
3. 2b deles i 2b-i og 2b-ii (§2).
4. Første bevidste kanoniske ændring i 5b: ordinal på højst 3 rækker gennem den eksisterende redaktør-writer
   (§5.3); færdigbeviset kræver et præcist delta i stedet for 0.
5. Arkets `A`/`U` skriver intet; de afgøres i køen (§5.3).

## 13. Uden for 2b-i

1. De 14 ægteskabspåstande uden ægtefælle-persona, `new_person_needed` og `different` fra køen → 2b-ii.
   Genafgørelse af en accepteret relation, hvis struktur er flyttet til en anden familie → 2b-ii.
2. De 2 `proposed` forælderpåstande (`F`/`U`) og familiekorrektion for `F`-kortet → parkeret
   (projektejerbeslutning).
3. `samme_som` for dubletten fra del 1 → parkeret.
4. Klausul-dispositionen → 2b-ii, sidst.
5. Kildevisning i mobil, Playwright i CI → uændret åbne (2a-specen §11).
