# #244 — ægteskabsnummeret placeres efter skriverens vindue; de 4 skæve numre rettes på et lille ark (#151)

## Status

Designet blev godkendt i brainstormen 2026-10-20 i tre dele. Projektejeren valgte:
- **Godkendelse:** et lille hash-bundet ark med 4 linjer, ikke en automatisk regel.
- **Værn:** ja. En påstand stoppes, hvis bogens eget »g. N°« modsiger systemets nummer.
- **Ingen nye klassifikationsevents.**

Spec'en er revideret samme dag efter et uafhængigt review (Opus, »GO med rettelser«). Alle fund er indarbejdet. Fund 2 (familiekorroborationen) er indarbejdet som kendt begrænsning med måling og test (§7.5).

**Roadmap:** trin 5, delspec 5b, opfølgning på 2b-ii runde 2 (fund 1).

Dokumenterne kaldes herefter:
- »2a-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`;
- »2b-i-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md`;
- »2b-iii-specen«: `docs/superpowers/specs/2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md` (formskabelon for ark og skriver);
- »runde 2-rapporten«: `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`.

Beslutning: `docs/decisions.md` 2026-10-20 pkt. 4. Den nye beslutningspost (§9.4) afløser pkt. 4's »genafgør de 2 ældre bindinger«. Det svarer til en rettelse af det gemte nummer plus en genbinding, ikke en ny afgørelse (§8).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), 5b »personas for ægtefæller og børn« |
| Værdikædeled | Fortolkning → serverens ægteskabsnummer → menneskelig rettelse (hash-bundet ark) → genbinding |
| Leverancetype | Rettelse af en eksisterende serverfunktion, en smal rettelsesskriver med eget evidensspor, et værn i udtræk og skriver |
| Redaktionel/læserrettet værdi | Ingen falske »forkert nummer«-undtagelser. En redaktør kan ikke komme til at »rette« et rigtigt familienummer. Det gemte ægteskabsnummer er bogens. |
| Færdigbevis | §9 |
| Erstatter | Beslutningen 2026-10-20 pkt. 4: »behold familiens nummer« som manuel omgåelse på et undtagelsesark |

## 2. Erratum til runde 2-rapporten (fund 1) og issue #244

Fund 1 og issuet siger, at påstandens tekst »rækker ud over klausulen«. **Det er forkert.**

Målt i `daa5b_2b_iii_bevis_20261020182757` den 2026-10-20:

| Måling | Resultat |
| --- | --- |
| Ægteskabspåstande, ikke afviste, alle kilder (funktionen kender ikke kilden) | 247 |
| Rå tekst ikke ordret i klausulen | 6 |
| Tegn tilbage i klausulen efter påstandens begyndelse | 427–1323 |
| Påstande, hvor den rå tekst er længere end det resterende stykke | 0 af 6 |
| Afvigelsespunkt | Efter et mellemrum, hvor klausulen har en parentes eller andre ord |

Den rå tekst springer altså **et stykke midt i klausulen over**, typisk en parentes. Begyndelsen (9–69 tegn) står ordret i klausulen. Det er den form, som 2b-ii's skriver allerede håndterer med »det eneste minimale ordnede ordvindue« (`private.relation_ordered_windows`, runde 2 §17.7).

`relation_marriage_ordinals` søger derimod efter hele den rå tekst med `strpos`. Positionen bliver NULL og sorteres sidst. Skriveren placerer de samme påstande rigtigt med vinduet. Funktion og skriver er uenige, og det er hele fejlen.

## 3. Afgrænsning

| Med | Ikke med |
| --- | --- |
| `relation_marriage_ordinals` bruger vinduet | Ændring af klausulopdelingen |
| Rettelse af de gemte numre i ægtefælleparten for bundne påstande | Ændring af `family_member.ordinal` (familiernes numre er rigtige) |
| Genbinding i samme familie ad 2b-i-vejen | Ombinding til en anden familie |
| Værn i v3-udtrækket og i `write_relation_persona` | Værn på andre prædikater |
| Restore-bevis | Prod (§10) |

## 4. Rodrettelsen

```sql
-- position = klausulens start + starten af det eneste minimale ordnede vindue; ellers NULL
co.post_char_from + (SELECT CASE WHEN count(*)=1 THEN min(w.w_from) END
                       FROM private.relation_ordered_windows(co.verbatim_text, ic.value->>'raw') w)
```

**Signatur og sortering.** Signaturen `relation_marriage_ordinals(uuid) RETURNS TABLE(interpretation_key uuid, marriage_ordinal integer, post_offset integer)` er uændret. Sorteringen `post_offset NULLS LAST, char_length(raw), interpretation_key COLLATE "C"` er også uændret, og NULL er kun en sikkerhed. `STRICT` og `count(*)=1` giver NULL ved NULL-`raw`, som før.

**De 5 kaldesteder røres ikke:**
- `relation_persona_input`;
- `write_relation_persona`;
- `persona_family_context` (antal);
- identitetskorroborationens antals- og drifttjek (2 steder).

**Placering i `schema.sql`.** `relation_marriage_ordinals` er `LANGUAGE sql`, så kroppen tjekkes ved oprettelsen (`check_function_bodies`). `relation_ordered_windows` står i dag længere nede (schema.sql:~17060–17096). Den flyttes med sin kommentarblok op før `relation_marriage_ordinals` (~14899). Den er `IMMUTABLE STRICT` uden afhængigheder, så flytningen er sikker.

**Placering i `db-migrations.sql`.** Der kommer en ny #244-blok over `-- 5b-sektionen slutter her`, og den ligger efter vinduets definition. Blokken indeholder `CREATE OR REPLACE` af `relation_marriage_ordinals`.

**Rettigheder.** `relation_marriage_ordinals` er SECURITY DEFINER, så vinduet kaldes som ejeren. Vinduets REVOKE fra service_role rammer ikke ejeren. Begge funktioner skal oprettes af samme rolle, og det gør de i både schema og migrationer.

**Målt effekt** (samme base):

| Måling | Resultat |
| --- | --- |
| Påstande med præcis ét vindue | 247 af 247 |
| Vinduets start = `strpos` for de ordrette | 241 af 241 |
| Vinduets position = gemt `post_offset` i ægtefælleparten | 244 af 244 |
| Ændrede numre | 4, i 2 poster, byttet 1↔2 |
| Bogens »N°« stemmer | 40 af 40 (i dag 36) |
| Gemt nummer ≠ nyt nummer | 4, alle bundne, alle `accepted` med metoden `family-structure-v1`. 0 ubundne. |

**Ydelse.** Vinduet er en plpgsql-løkke. Den kaldes pr. påstand, og pr. post kaldes funktionen pr. påstand (O(k²)), i `relation_persona_input` og i `persona_family_context`. Tærskel i §9: `relation_persona_input(1)` og bind-preview må højst tage 2 × før-tiden og højst 10 s.

## 5. Værnet

**Bogens nummer.** Det er det forankrede mønster med eksplicitte klasser, sammenlignet efter `lower()`:

```
^[ \t]*(g\.|gift)[ \t]*([0-9]+)[ \t]*[°º]
```

Det undgår `\s`, `\d` og `\w`, fordi de afhænger af locale og Unicode (jf. vinduets begrundelse). Målt: alle 40 forekomster står forrest, 0 står i en parentes, og 0 påstande har to.

- **SQL.** Ny `private.relation_book_ordinal(p_raw text) RETURNS integer` (IMMUTABLE STRICT) bruges af skriveren, rettelsesskriveren og arkets input.
- **Python.** Funktionen `book_ordinal(raw)` i `relation_persona_extract_v3.py`.
- **Paritet.** Der er en fælles fixtureliste (`tests/fixtures/relation-book-ordinal.json`). Den dækker store bogstaver, »gift«, »g.«, `º` og `°`, mellemrum, et tal over 9, ikke-forankret »N°«, »N°« i en parentes og ingen »N°«. Begge sider testes mod den.

**Udtrækket (v3).** I `_propose` lige efter `intet_nummer` (relation_persona_extract_v3.py:140): hvis `book_ordinal(raw)` ikke er None og ≠ `marriage_ordinal`, bliver linjen `U` med grunden `nummer_modsiger_bog`. `propose_redecide` (:194) får samme tjek, hvis dens række bærer `raw`. Planen afgør det ud fra rækkens felter.

**Skriveren (`private.write_relation_persona`).** #244-blokken genopretter funktionen ud fra den **seneste** krop i db-migrations.sql (i dag :23203; der er tre definitioner) og tilføjer værnet. Når den har slået `v_ordinal` op for et ægteskab, og `relation_book_ordinal(raw)` ≠ `v_ordinal`, afviser den med `REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH`. Det gælder alle profiler.
- **Genkørsel i samme base** påvirkes ikke, fordi `…_EXISTS` stopper først.
- **v1/v2-udtrækkene** parkerer ikke på bognummeret. Ved en modsigelse vælter skriveren derfor hele batchen. Det er accepteret: v1/v2 er historiske profiler, og at fejle lukket er det rigtige.

## 6. Arket

**Input.** Ny `private.marriage_ordinal_correction_input(p_source_id bigint)` med wrapper `public.red_marriage_ordinal_correction_input(bigint)`.
- **Rettigheder** som børnearkets input og wrapper: REVOKE fra PUBLIC, anon, authenticated og service_role. Wrapperen får GRANT til authenticated og redaktionens rollegate.
- **Rækkerne:** én pr. påstand, der opfylder alle disse:
  - prædikat `relation.marriage`, status `accepted`, metode `family-structure-v1`;
  - mindst én binding (`interpretation_promotion`, `target_type='family'`);
  - gemt `marriage_ordinal` i den gældende ægtefællepart ≠ funktionens nummer.
- **Felter:** `interpretation_key`, `interpretation_version`, `spouse_party_version`, `stored_ordinal`, `new_ordinal`, `book_ordinal` (NULL uden »N°«), `family_id` (seneste binding), `family_ordinal`, `principal_named {navn, foedt, post}` og `spouse_named {navn, foedt}`. Navnene står kun i den private arkfil.

**Arket** (`.claude/skills/daa-extract/scripts/relation_ordinal_sheet.py`, samme form som børnearket):
- vejledning øverst og nummererede linjer `# [n] Forælder: … · Ægtefælle: … · bogens N°: … · gemt → nyt: … → … · familiens nr.: …`;
- tokens `B` (ret nummeret) og `U` (lad stå, skriver intet);
- `R` og alt andet giver `SHEET_TOKEN_NOT_ALLOWED`;
- linjefejl som børnearket: `SHEET_LINE_UNKNOWN`, `SHEET_LINE_DUPLICATE`, `SHEET_LINES_MISSING`.

**Hash-binding.** Godkendelsen hasher arket (SHA-256), og `decision_sql` verificerer hashen, før den skriver (`SHEET_HASH_MISMATCH`). Rækkefilens hash står i konteksten.

**Privat mappe:** `~/.private/244/` (0700).

**Script:** `relation_ordinal_rows.sql` kalder `red_marriage_ordinal_correction_input(:source)`.

## 7. Rettelsesskriveren

### 7.1 Tabel

`private.marriage_ordinal_correction`:

| Kolonne | |
| --- | --- |
| `id` | uuid PK |
| `interpretation_key`, `interpretation_id` | |
| `party_version_from`, `party_version_to` | |
| `ordinal_from`, `ordinal_to` | |
| `family_id` | |
| `evidence` | jsonb, ikke tom |
| `created_by`, `created_at` | |

- **Tilføj-kun.** UPDATE, DELETE og TRUNCATE afvises med `private.reject_evidence_mutation`.
- **Adgang.** `ENABLE ROW LEVEL SECURITY` og REVOKE ALL fra PUBLIC, anon, authenticated og service_role, som ved `interpretation_party` (schema.sql:1333–1335).
- **Assert i `db-verify.sql`:** RLS er slået til, og ingen API-rolle har privilegier.

### 7.2 Constraint

`interpretation_party.origin` får den tredje værdi `ordinal_correction`.
- **`schema.sql`.** Den unavngivne CHECK navngives eksplicit `interpretation_party_origin_check`, som er det navn, Postgres allerede har givet den.
- **Migration.** `ALTER TABLE … DROP CONSTRAINT IF EXISTS interpretation_party_origin_check, ADD CONSTRAINT … CHECK (origin IN ('relation_persona','relation_decision','ordinal_correction'))`, efter mønstret ved db-migrations.sql:21875.
- **Assert i `db-verify.sql`:** constraintet findes og tillader præcis de tre værdier.

### 7.3 Funktion

`public.red_ret_aegteskabsnummer(p_interpretation_key uuid, p_expected_party_version integer, p_note text, p_ctx jsonb) RETURNS integer` returnerer den nye partversion. Den er SECURITY DEFINER med redaktionens rollegate (`auth.uid()` og `current_rolle()='redaktion'`). Den REVOKE'es fra PUBLIC, anon og authenticated og får GRANT til authenticated.

| Tjek, i rækkefølge | Fejl |
| --- | --- |
| Rollegate | `EVIDENCE_ROLE_FORBIDDEN` |
| `p_ctx` er et objekt med præcis nøglerne `basis`, `sheet_sha256`, `rows_sha256` og `line`. `basis='human_sheet'`; `sheet_sha256` og `rows_sha256` matcher `^[0-9a-f]{64}$`; `line` matcher `^[1-9][0-9]*$`. `p_note` er ikke tom. | `MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID` |
| **Låse** (§7.4) | — |
| Gældende fortolkning er `relation.marriage`, `accepted`, metode `family-structure-v1`, og har mindst én binding | `MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND` |
| Gældende ægtefællepart har version = `p_expected_party_version` | `MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH` |
| Funktionens nummer er ikke NULL og ≠ det gemte nummer | `MARRIAGE_ORDINAL_CORRECTION_NOT_NEEDED` |
| Hovedpersonens `family_member.ordinal` i den seneste bindings familie er ikke NULL og = funktionens nummer | `MARRIAGE_ORDINAL_CORRECTION_FAMILY_MISMATCH` |
| `relation_book_ordinal(raw)` er enten NULL eller = funktionens nummer | `MARRIAGE_ORDINAL_CORRECTION_BOOK_MISMATCH` |

**Skrivning:**
- én række i `marriage_ordinal_correction`;
- én ny ægtefællepart: version +1, samme `source_persona_id` og `post_offset`, `marriage_ordinal` = funktionens nummer, `origin='ordinal_correction'`, `origin_ref` = korrektionsrækkens id.

**Kontrol efter skrivningen, i samme transaktion:** `relation_binding_state(fortolkningen)` er ikke NULL, dens `family.family_id` er den seneste bindings, og `book_ordinal = family_ordinal`. Ellers: `MARRIAGE_ORDINAL_CORRECTION_STATE_INVALID`. Rettelsen gælder kun, hvis genbindingen kan lykkes.

Fortolkningen og afgørelsen røres ikke.

### 7.4 Låse

Funktionens nummer afhænger af alle ikke-afviste ægteskabspåstande i posten. `red_decide_interpretation` tager ingen kildelås, så en samtidig afvisning af en søskendepåstand kunne flytte nummeret. Rækkefølgen følger promote:
1. den delte kildelås, som `red_afgoer_relation_interpretation` tager (schema.sql:~15560);
2. `FOR SHARE` på `interpretation`-rækkerne for alle ikke-afviste ægteskabspåstande i posten, sorteret efter id;
3. `private.lock_family_rows(ARRAY[hovedperson, ægtefælle] sorteret)`, altså person → familie → medlem;
4. derefter beregnes nummeret, og tjekkene i §7.3 køres.

### 7.5 Andre læsere af den gældende part

- **`relation_binding_state`** læser `pc.marriage_ordinal` som `book_ordinal`. Den nye tilstand er tilsigtet (§8).
- **`check_family_corroboration`** (schema.sql:~16080–16096) kræver `origin='relation_persona'` og sammenligner reimport-eventet med den gældende part. Efter rettelsen giver den `FAMILY_CORROBORATION_PROVENANCE_INVALID` for de 4 ægtefællepersonaer.
  - Den vej er dog **lukket for dem i forvejen**. Korroborationen kræver `p_expected=0`, altså ingen identitet endnu. De 4 ægtefæller har en `accepted` identitet, for ellers kunne påstanden ikke være bundet.
  - Derfor ændres koden ikke. I stedet er der en måling i §9 (alle 4 ægtefælleidentiteter `accepted`) og en test, der viser afvisningen efter rettelsen.
- **`relation_person_create`** (schema.sql:~16777) læser det gemte nummer. Det er harmløst her: de 4 har allerede en ægtefælle.

## 8. Genbindingen

`relation_binding_state` læser `pc.marriage_ordinal`. Efter rettelsen er `book_ordinal` = `family_ordinal`, tilstanden er ny, og dens hash er ny.

Bind-preview (2b-i-specen §4.2, schema.sql:~16515–16526) giver for de 4:
- ikke `ALREADY_APPLIED`, fordi hashen er ny;
- ikke `REBIND_FAMILY_CHANGED`, fordi familien er den samme;
- ikke `NOT_CURRENT`, fordi fortolkningen er uændret.

De 4 er dermed egnede med `supersedes_promotion_id`. `vielse_fact_id` genberegnes uændret. Bindingen skriver 4 nye rækker, og de gamle står som historik.

**Synlighedshul.** `public_family_sources` viser kun en binding, hvis tilstandens hash stadig er den bundne (schema.sql:~17213). Mellem rettelse og genbinding mister de 4 familier derfor deres kilderække for ægteskabet. I restore er det uden betydning. Det måles før, imellem og efter (§9). Overførsels-spec'en skal køre rettelse og genbinding i samme vindue.

**Afvist alternativ:** at lade `relation_binding_state` læse funktionen direkte i stedet for det gemte nummer. Det gemte nummer ville forblive forkert. Skriverens spændtjek og `FAMILY_CORROBORATION_ORDINAL_DRIFT` sammenligner netop funktion og gemt nummer, så uoverensstemmelsen ville bestå skjult.

## 9. Færdigbevis

### 9.1 Tests (lokalt og i CI)

**`tests/sql/test-marriage-ordinal-correction.sql` med fixture:**
- **Funktionen:**
  - en påstand, der springer en parentes over, får vinduets position og den rigtige rækkefølge;
  - uden præcis ét vindue bliver positionen NULL og sorteres sidst;
  - ordrette påstande nummereres uændret.
- **`relation_book_ordinal`** mod paritetsfixturen.
- **Rettelsesskriveren:**
  - hver fejl i §7.3-tabellen, inkl. en ukendt nøgle i konteksten og familienummer NULL;
  - et gyldigt kald giver ny partversion og én korrektionsrække;
  - et gentaget kald afvises på versionen;
  - ingen ændring i `family_member`.
- **Rettigheder:** `has_function_privilege` for anon, authenticated og service_role på skriver, input og wrapper. En ikke-redaktør afvises.
- **Tabellen:** UPDATE, DELETE og TRUNCATE afvises.
- **Constraint:** en ukendt `origin` afvises.
- **Værnet i `write_relation_persona`:** bognummer ≠ serverens nummer giver `…_ORDINAL_BOOK_MISMATCH`.
- **Familiekorroborationen** efter rettelsen giver `FAMILY_CORROBORATION_PROVENANCE_INVALID` (§7.5).
- **Genbinding:**
  - før rettelsen er påstanden `ALREADY_APPLIED`;
  - efter rettelsen er den egnet med `supersedes`;
  - efter genbindingen er den igen synlig i `public_family_sources`.

**Python:**
- `test_relation_ordinal_sheet.py`: render, parse, hash, `R` afvist og linjefejl;
- `nummer_modsiger_bog` i `test_relation_persona_extract_v3.py`;
- paritetsfixturen.

**E2e:** `tests/sql/test-relation-ordinal-sheet.sh` svarer til `test-relation-child-sheet.sh`. Kæden er input, ark, `decision_sql`, skrivning og preview, og testen har en negativ token-test.

**Opgradering:** `tests/sql/test-relation-ordinal-upgrade.sh` efter mønstret `test-relation-binding-upgrade.sh`. En base med den gamle funktion og den gamle constraint løftes med migrationen og giver `UPGRADE_OK`.

**CI-kobling:** den nye SQL-fil kommer i SQL-løkken, pytest-filerne og e2e- og opgraderingsscriptet kommer med, som børnearkets (ci.yml:~142 og ~491–503).

**Lokalt:** hele den lokale CI (7 jobs) og `UPGRADE_OK` er grønne før push.

### 9.2 Restore (kopi af `daa5b_2b_iii_bevis_20261020182757`)

| Måling | Forventet |
| --- | --- |
| Rækker på arket | 4 |
| Bundne ægteskaber med en anden metode end `family-structure-v1` | 0 |
| Ægtefælleidentiteter for de 4 | 4 `accepted` |
| Afgørelser | `SQL_OK b=4 u=0` |
| Nye ægtefællepartversioner / korrektionsrækker | 4 / 4 |
| Arkets input efter rettelsen | 0 rækker |
| Læsning imellem (rettelse gjort, ikke genbundet) | 4 ægteskabskilderækker færre |
| Bind-preview | 4 egnede genbindinger, 249 `ALREADY_APPLIED` |
| Bindingsrækker | 253 → 257 |
| Fortolkninger med en binding, hvis hash = den gældende tilstands | 253 før, 249 imellem, 253 efter |
| Genkørsel | 253 `ALREADY_APPLIED`, 0 egnede |
| Gældende bindinger med `book_ordinal ≠ family_ordinal` (alle ægteskaber) | 0 efter |
| Læsning efter | Som før (241 familier, 253 kilderækker) |
| Kanoniske tabeller (antal og aggregat-hashes) | Uændrede |
| `family_member.ordinal` | Uændret |
| 2a's tupel-digest | Uændret `89bde760…5923` |
| Digest over de gældende bindinger | Ændret i præcis 4 tupler |
| Univers | 272 |
| Bogens »N°« = serverens | 40 af 40 |
| Tid | Under tærsklen i §4 |

**2a's tupel-digest.** Den regnes over 2a's egne bindingsrækker, udvalgt efter 2a's batch-id, og dem ændrer genbindingen ikke. Planen skal verificere, at `hashes.sql` vælger sådan. Gør den ikke, ændres forventningen til »ændret i 2 tupler«, og det skrives.

### 9.3 Negativtests i egen kopi

- forkert arkhash → `SHEET_HASH_MISMATCH`;
- `R` på arket → `SHEET_TOKEN_NOT_ALLOWED`;
- direkte kald på en påstand, der ikke behøver rettelse → `…_NOT_NEEDED`;
- samme linje anvendt to gange → `…_VERSION_MISMATCH`.

### 9.4 Dokumentation

- rapporten `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md`;
- status og changelog;
- en beslutningspost, der afløser pkt. 4's »genafgør«;
- erratum-tilføjelse til runde 2-rapporten (fund 1) og ved `decisions.md` 2026-10-20 pkt. 4;
- rettelse af issue #244's beskrivelse.

## 10. Kendte begrænsninger

- **Mønstret er 2018-20's form.** Bognummer-mønstret dækker »g. N°« og »gift N°« forrest. Andre udgavers former fanges ikke af værnet. Rodrettelsen afhænger ikke af mønstret.
- **Kun bundne påstande.** Kun bundne påstande rettes med skriveren. Ubundne påstande med gemt part og forkert nummer (målt 0) ville kræve en anden vej.
- **Familiekorroborationen** er lukket for de 4 ægtefællepersonaer efter rettelsen (§7.5). Det er uden betydning, fordi den allerede var lukket for dem.
- **Prod-genspil.** Allerede autoriserede `relation_persona`-payloads bærer det gamle `marriage_ordinal`. Med den rettede funktion afviser skriverens eksisterende tjek (schema.sql:~15089–15091) dem med `SPAN_INVALID`. Prod kan altså ikke genspille kæden med den rettede funktion uden ny autorisation af de batches, de 4 elementer ligger i. Alternativet er at genspille de oprindelige batches med den gamle funktion og derefter rettelse og genbinding. Det valg hører til overførsels-spec'en.
- **Synlighedshullet** mellem rettelse og genbinding (§8) skal håndteres i overførslen.
