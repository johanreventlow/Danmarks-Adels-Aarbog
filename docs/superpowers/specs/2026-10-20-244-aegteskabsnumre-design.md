# #244 — ægteskabsnummeret placeres efter skriverens vindue; de 4 skæve numre rettes på et lille ark (#151)

## Status

Designet blev godkendt i brainstormen 2026-10-20 i tre dele. Projektejeren valgte:
- **Godkendelse:** et lille hash-bundet ark med 4 linjer, ikke en automatisk regel.
- **Værn:** ja. En påstand stoppes, hvis bogens eget »g. N°« modsiger systemets nummer.
- **Ingen nye klassifikationsevents.** De 4 gamle `ordinal_afvigelse` falder af undtagelseslisten af sig selv.

**Roadmap:** trin 5, delspec 5b, opfølgning på 2b-ii runde 2 (fund 1).

Dokumenterne kaldes herefter:
- »2a-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`;
- »2b-i-specen«: `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md`;
- »runde 2-rapporten«: `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`.

Beslutning: `docs/decisions.md` 2026-10-20, pkt. 4 (falske ordinal-afvigelser bindes og noteres; rodfejlen rettes i en separat runde).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), 5b »personas for ægtefæller og børn« |
| Værdikædeled | Fortolkning → serverens ægteskabsnummer → menneskelig rettelse (hash-bundet ark) → genbinding |
| Leverancetype | Rettelse af en eksisterende serverfunktion, en smal rettelsesskriver med eget evidensspor, et værn i udtræk og skriver |
| Redaktionel/læserrettet værdi | Ingen falske »forkert nummer«-undtagelser. En redaktør kan ikke komme til at »rette« et rigtigt familienummer. Ægteskabsnummeret, der gemmes i kilden, er bogens. |
| Færdigbevis | §9 |
| Erstatter | Beslutningen 2026-10-20 pkt. 4: »behold familiens nummer« som manuel omgåelse på et undtagelsesark |

## 2. Erratum til runde 2-rapporten (fund 1) og issue #244

Fund 1 og issuet siger, at påstandens tekst »rækker ud over klausulen«. **Det er forkert.**

Målt i `daa5b_2b_iii_bevis_20261020182757` den 2026-10-20:

| Måling | Resultat |
| --- | --- |
| Ægteskabspåstande (ikke afviste) | 247 |
| Rå tekst ikke ordret i klausulen | 6 |
| Tegn tilbage i klausulen efter påstandens begyndelse | 427–1323 |
| Påstandens rå tekst længere end det resterende stykke | 0 af 6 |
| Afvigelsespunkt | Efter et mellemrum, hvor klausulen har en parentes eller andre ord |

Den rå tekst springer altså **et stykke midt i klausulen over**, typisk en parentes. Begyndelsen (9–69 tegn) står ordret i klausulen. Det er den samme form, som 2b-ii's skriver allerede håndterer med »det eneste minimale ordnede ordvindue« (`private.relation_ordered_windows`, runde 2 §17.7).

**Følgen:** `relation_marriage_ordinals` søger efter hele den rå tekst med `strpos`. Positionen bliver derfor NULL og sorteres sidst. Skriveren placerer derimod de samme påstande rigtigt med vinduet. Funktion og skriver er uenige, og det er hele fejlen.

## 3. Afgrænsning

| Med | Ikke med |
| --- | --- |
| `relation_marriage_ordinals` bruger vinduet | Ændring af klausulopdelingen |
| Rettelse af de gemte numre i ægtefælleparten for bundne påstande | Ændring af `family_member.ordinal` (familiernes numre er rigtige) |
| Genbinding i samme familie ad 2b-i-vejen | Ombinding til en anden familie |
| Værn i v3-udtrækket og i `write_relation_persona` | Værn på andre prædikater |
| Restore-bevis | Prod. Overførsels-spec'en afgør, om prod genspiller kæden med den rettede funktion eller genspiller rettelse og genbinding. Rettelsen er designet som et selvstændigt, genspilbart skridt med evidens. |

## 4. Rodrettelsen

```sql
-- position = klausulens start + starten af det eneste minimale ordnede vindue; ellers NULL
co.post_char_from + (SELECT CASE WHEN count(*)=1 THEN min(w.w_from) END
                       FROM private.relation_ordered_windows(co.verbatim_text, ic.value->>'raw') w)
```

- **Signaturen** `relation_marriage_ordinals(uuid) RETURNS TABLE(interpretation_key uuid, marriage_ordinal integer, post_offset integer)` er uændret. De 5 kaldesteder røres ikke:
  - `relation_persona_input`;
  - `write_relation_persona`;
  - `persona_family_context` (antal);
  - identitetskorroborationens antals- og drifttjek (2 steder).
- **Sorteringen** `post_offset NULLS LAST, char_length(raw), interpretation_key COLLATE "C"` er uændret. NULL er kun en sikkerhed.
- **Placering.** `schema.sql` rettes på stedet. I `db-migrations.sql` lægges en ny `CREATE OR REPLACE` i #244-blokken over `-- 5b-sektionen slutter her`, så den kommer efter den oprindelige definition.

**Målt effekt** (samme base):

| Måling | Resultat |
| --- | --- |
| Påstande med præcis ét vindue | 247 af 247 |
| Vinduets start = `strpos` for de ordrette | 241 af 241 |
| Vinduets position = gemt `post_offset` i ægtefælleparten | 244 af 244 |
| Ændrede numre | 4, i 2 poster, byttet 1↔2 |
| Bogens »N°« stemmer | 40 af 40 (i dag 36) |

## 5. Værnet

**Bogens nummer.** Det er det forankrede mønster `^\s*(?:g\.|gift)\s*(\d+)\s*°` (uden hensyn til store og små bogstaver) i påstandens rå tekst. Målt: alle 40 forekomster står forrest, 0 står i en parentes, og 0 påstande har to.

- **Udtrækket (`relation_persona_extract_v3.py`).** Lige efter `intet_nummer`: har den rå tekst et bognummer, og er det forskelligt fra `marriage_ordinal`, bliver linjen `U` med grunden `nummer_modsiger_bog`.
- **Skriveren (`private.write_relation_persona`).** Når den har slået `v_ordinal` op for et ægteskab: har den rå tekst et bognummer forskelligt fra `v_ordinal`, afviser den med `REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH`. Det gælder alle profiler.
- **Fælles fixture.** Python-mønstret og SQL-mønstret skal give samme svar på den samme fixtureliste, ligesom vinduet har sin tvilling.

## 6. Arket

**Input.** Ny `private.marriage_ordinal_correction_input(p_source_id bigint)` med wrapper `public.red_marriage_ordinal_correction_input(bigint)` (kun redaktionen; REVOKE fra PUBLIC, anon og authenticated; GRANT til authenticated med rollegate som børnearkets wrapper). Den returnerer én række pr. påstand, der opfylder alle disse:
- prædikat `relation.marriage`, status `accepted`, metode `family-structure-v1`;
- mindst én binding (`interpretation_promotion`, `target_type='family'`);
- gemt `marriage_ordinal` i den gældende ægtefællepart ≠ funktionens nummer.

**Felter:**
- `interpretation_key`, `interpretation_version`, `spouse_party_version`;
- `stored_ordinal`, `new_ordinal`, `book_ordinal` (NULL uden »N°«);
- `family_id`, `family_ordinal`;
- `principal_named {navn, foedt, post}`, `spouse_named {navn, foedt}`.

Navnene står kun i den private arkfil.

**Arket** (`.claude/skills/daa-extract/scripts/relation_ordinal_sheet.py`, samme form som børnearket):
- vejledning øverst og nummererede linjer `# [n] Forælder: … · Ægtefælle: … · bogens N°: … · gemt → nyt: … → … · familiens nr.: …`;
- tokens `B` (ret nummeret) og `U` (lad stå, skriver intet);
- `R` og alt andet giver `SHEET_TOKEN_NOT_ALLOWED`;
- linjefejl som børnearket: `SHEET_LINE_UNKNOWN`, `SHEET_LINE_DUPLICATE`, `SHEET_LINES_MISSING`.

**Hash-binding.** Godkendelsen hasher arket (SHA-256), og `decision_sql` verificerer hashen, før den skriver (`SHEET_HASH_MISMATCH`). Rækkefilens hash står i konteksten.

**Privat mappe:** `~/.private/244/` (0700).

## 7. Rettelsesskriveren

**Tabel** `private.marriage_ordinal_correction` (tilføj-kun; afviser UPDATE, DELETE og TRUNCATE med `private.reject_evidence_mutation`):

| Kolonne | |
| --- | --- |
| `id` | uuid PK |
| `interpretation_key`, `interpretation_id` | |
| `party_version_from`, `party_version_to` | |
| `ordinal_from`, `ordinal_to` | |
| `family_id` | |
| `evidence` | jsonb, ikke tom |
| `created_by`, `created_at` | |

**Constraint.** `interpretation_party.origin` får den tredje værdi `ordinal_correction`. Den ændres idempotent i migrationen med DROP og ADD af den navngivne constraint. `db-verify.sql` tjekkes for asserts på constraintet.

**Funktion** `public.red_ret_aegteskabsnummer(p_interpretation_key uuid, p_expected_party_version integer, p_note text, p_ctx jsonb) RETURNS integer`. Den returnerer den nye partversion. SECURITY DEFINER, redaktionens rollegate, REVOKE fra PUBLIC, anon og authenticated, GRANT til authenticated.

| Tjek, i rækkefølge | Fejl |
| --- | --- |
| `p_ctx` har `basis='human_sheet'`, `sheet_sha256`, `rows_sha256` og `line`; `p_note` er ikke tom | `MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID` |
| Rådgivende lås på påstanden (som `red_afgoer_relation_interpretation`), derefter rækkelås på familien | — |
| Gældende fortolkning: `relation.marriage`, `accepted`, metode `family-structure-v1`, mindst én binding | `MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND` |
| Gældende ægtefællepart har version = `p_expected_party_version` | `MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH` |
| Funktionens nummer ≠ gemt nummer | `MARRIAGE_ORDINAL_CORRECTION_NOT_NEEDED` |
| Funktionens nummer = `family_member.ordinal` for hovedpersonen i den bundne familie | `MARRIAGE_ORDINAL_CORRECTION_FAMILY_MISMATCH` |
| Bogens nummer (§5), hvis det findes, = funktionens nummer | `MARRIAGE_ORDINAL_CORRECTION_BOOK_MISMATCH` |

**Skrivning:**
- én række i `marriage_ordinal_correction`;
- én ny ægtefællepart: version +1, samme `source_persona_id` og `post_offset`, `marriage_ordinal` = funktionens nummer, `origin='ordinal_correction'`, `origin_ref` = korrektionsrækkens id.

Fortolkningen og afgørelsen røres ikke. Den bundne familie står i den seneste binding.

## 8. Genbindingen

`relation_binding_state` læser `pc.marriage_ordinal` som `book_ordinal`. Efter rettelsen er `book_ordinal` = `family_ordinal`, tilstanden er ny, og dens hash er ny.

Bind-preview (2b-i-specen §4.2) giver for de 4: egnet, `supersedes_promotion_id` = den gamle binding, samme familie. Bindingen skriver 4 nye rækker. De gamle står som historik.

**Afvist alternativ:** at lade `relation_binding_state` læse funktionen direkte i stedet for det gemte nummer. Det gemte nummer ville forblive forkert. Skriverens spændtjek og `FAMILY_CORROBORATION_ORDINAL_DRIFT` sammenligner netop funktion og gemt nummer, så uoverensstemmelsen ville bestå skjult.

## 9. Færdigbevis

**Tests (lokalt og i CI):**
- **`tests/sql/test-marriage-ordinal-correction.sql` med fixture:**
  - Funktionen: en påstand, der springer en parentes over, får vinduets position og den rigtige rækkefølge. Uden præcis ét vindue bliver positionen NULL og sorteres sidst. Ordrette påstande nummereres uændret.
  - Rettelsesskriveren: hver fejl i §7's tabel. Et gyldigt kald giver ny partversion og én korrektionsrække. Et gentaget kald afvises på version. Der er ingen ændring i `family_member`.
  - Værnet i `write_relation_persona`: bognummer ≠ serverens nummer giver `…_ORDINAL_BOOK_MISMATCH`.
  - Genbinding: efter rettelsen er påstanden egnet med `supersedes`, før rettelsen er den `ALREADY_APPLIED`.
- **Python:** `test_relation_ordinal_sheet.py` (render, parse, hash, `R` afvist, linjefejl) og en test af `nummer_modsiger_bog` i `test_relation_persona_extract_v3.py`.
- **Paritet:** fælles fixture for bognummer-mønstret (SQL og Python).
- **Opgradering:** migrationen løfter en base med den gamle funktion og den gamle constraint (`UPGRADE_OK`).
- **Lokalt:** hele den lokale CI (7 jobs) er grøn før push.

**Restore (kopi af `daa5b_2b_iii_bevis_20261020182757`):**

| Måling | Forventet |
| --- | --- |
| Rækker på arket | 4 |
| Afgørelser | `SQL_OK b=4 u=0` |
| Nye ægtefællepartversioner | 4 |
| Korrektionsrækker | 4 |
| Bind-preview | 4 egnede genbindinger, 249 `ALREADY_APPLIED` |
| Nye bindingsrækker | 4, gældende bindinger stadig 253 |
| Genkørsel | 253 `ALREADY_APPLIED`, 0 egnede |
| Kanoniske tabeller (antal og aggregat-hashes) | Uændrede |
| `family_member.ordinal` | Uændret |
| 2a's tupel-digest (over 2a's oprindelige rækker) | Uændret `89bde760…5923` |
| Univers | 272 |
| Undtagelseslisten (`ordinal_afvigelse` med `book≠family` nu) | 4 → 0 |
| Bogens »N°« = serverens | 40 af 40 |
| Tid | Tiden for `relation_persona_input(1)` og bind-preview måles før og efter |

**Negativtests i egen kopi:**
- forkert arkhash → `SHEET_HASH_MISMATCH`;
- `R` på arket → `SHEET_TOKEN_NOT_ALLOWED`;
- direkte kald på en påstand, der ikke behøver rettelse → `…_NOT_NEEDED`;
- samme linje anvendt to gange → `…_VERSION_MISMATCH`.

**Dokumentation:**
- rapporten `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md`;
- status, changelog og en beslutningspost;
- erratum-tilføjelse til runde 2-rapporten (fund 1) og ved `decisions.md` 2026-10-20 pkt. 4;
- rettelse af issue #244's beskrivelse.

## 10. Kendte begrænsninger

- **Mønstret er 2018-20's form.** Mønstret for bognummeret dækker »g. N°« og »gift N°« forrest. Andre udgavers former fanges ikke af værnet. Rodrettelsen afhænger ikke af mønstret.
- **Kun bundne påstande rettes med skriveren.** Ubundne påstande med gemt part og forkert nummer (målt 0) ville kræve en anden vej.
- **Prod.** Rettelsen ligger, som resten af 5b, kun i restore, indtil overførsels-spec'en er godkendt.
