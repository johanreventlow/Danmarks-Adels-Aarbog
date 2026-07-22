# Review 34 — Mediehåndtering fase 4-plan (dual-review)

**Dato:** 2026-07-22
**Genstand:** `docs/superpowers/plans/2026-07-22-mediehaandtering-fase4-identitet.md`
(implementeringsplan mod specen `docs/superpowers/specs/2026-07-21-mediehaandtering-fase4-identitet-design.md`).
**Type:** PLAN-review (ingen kode implementeret endnu). Read-only.

**Metode-note:** Til forskel fra review 33 (hvor Codex ikke var tilgængeligt som værktøj i
sessionens miljø) er Codex CLI reelt tilgængeligt i denne session (`codex-cli-runtime`,
verificeret kørende `gpt-5.6-sol` direkte). Phase 3 er derfor en ægte Codex
adversarial-review, ikke en simuleret anden Claude-subagent.

Codex-trigger (Phase 2 = JA): executable SQL i tre nye SECURITY DEFINER-RPC'er + en
migrationsblok (Task 1-4), concurrency-følsomme guards (Task 2's to-trins-udrensning,
Task 3's søskende-nulstilling), og en hård sletnings-operation med evidens-invarianter
på spil (GDPR/§10.1-beslutningen).

---

## Phase 1 — egne fund (Claude, uafhængig subagent, verificeret empirisk mod `main @ caeb6a3`)

### H1 [HIGH] — `red_udrens_media` forældreløser mediets fakta-evidenskæde; preview melder fejlagtigt "grøn"

**Lokation:** plan Task 2, linje 500-524 (`red_udrens_media`) + 441-486 (`red_udrens_media_preview`); spec §4.2 + §1 ("FK-billedet ... kun `media_variant` refererer `media`").

**Symptom:** Udrens blokerer/rydder kun på `relation` (media som subjekt/objekt) og
`text_mention` (`maal_type='media'`). Den håndterer IKKE `fact`-rækker med
`subjekt_type='media'` — eller deres evidenskæde (`assertion`/`conclusion`/`citation` med
`target_type='fact'`, samt `note` med `target_type='fact'`). Disse skabes af
`red_set_media_rettigheder`, som er LIVE i prod.

**Verifikation:**

`red_set_media_rettigheder` (`db-migrations.sql:1757`, også `schema.sql:2091`) skriver
fakta på medie-entiteten:
```sql
PERFORM red_upsert_fakta('media', p_media_id, r.felt, r.val, p_kilde_fritekst => p_kilde_fritekst)
  FROM (VALUES ('licens', p_licens), ('kildehenvisning', p_kildehenvisning),
               ('gengivelsestilladelse', p_gengivelsestilladelse)) AS r(felt, val)
  WHERE nullif(btrim(r.val),'') IS NOT NULL;
```
`red_upsert_fakta` (`schema.sql:691`) bygger hele kæden:
`INSERT INTO fact(... subjekt_type='media' ...)` + `assertion` + `citation` + `conclusion`.

Planens `red_udrens_media` (plan:500-524) rører intet af det:
```sql
IF EXISTS (SELECT 1 FROM relation WHERE (subjekt_type='media' ...) OR (objekt_type='media' ...)) THEN
  RAISE EXCEPTION 'Mediet har tilknytninger ...';
END IF;
IF EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id) THEN ...
-- ... derefter direkte:
DELETE FROM media WHERE id = p_media_id;   -- kun media_variant CASCADE'r
```
Kodebasens etablerede mønster for at slette en entitet MED polymorfe fakta er
`red_slet_person` (`schema.sql:1128-1165`), som eksplicit FK-ordnet sletter kæden:
```sql
SELECT coalesce(array_agg(id),'{}') INTO v_facts FROM fact
  WHERE subjekt_type='person' AND subjekt_id=p_person_id;
DELETE FROM citation   WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id = ANY(v_facts) ...);
DELETE FROM conclusion WHERE (target_type='fact' AND target_id = ANY(v_facts)) ...;
DELETE FROM assertion  WHERE (target_type='fact' AND target_id = ANY(v_facts)) ...;
DELETE FROM note       WHERE ... target_type='fact' AND target_id = ANY(v_facts) ...;
DELETE FROM fact       WHERE id = ANY(v_facts);
```
Spec §1's præmis "kun `media_variant` refererer `media`" tæller kun DEKLARATIVE FK'er i et
skema hvis hele pointe er polymorfe FK-frie referencer — `fact.subjekt_type='media'` er
præcis en sådan (verificeret: `fact` har ingen FK til media, `schema.sql:341-347`).

**Konsekvens:** Et medie med rettigheds-dokumentation (licens/kildehenvisning/
gengivelsestilladelse udfyldt), som senere blødt fjernes og udrenses, får sin `media`-række
slettet mens fact+assertion+conclusion+citation(+note) står tilbage og peger på en
ikke-eksisterende medie-entitet. Det bryder planens egen garanti (plan:491-493: "Udrens kan
derfor aldrig forældreløse evidens"). Værre: `red_udrens_media_preview` tæller kun
`afbildet` (relationer) + `mentions`, så `kan_udrenses` returneres `true` (grøn, ingen
blokering) — sletningen sker STILLE. TDD-hullet forstærker det: Task 2's verify-blok seeder
aldrig et medie med fakta, så `blokeringer`-tællingen forbliver 2 og **suiten passerer
grøn med fejlen til stede** — falsk tryghed.

**Foreslået fix:** Enten (a) blokér fail-loud i både preview og `red_udrens_media` når
`EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id)` (ny
blokering: "Mediet har rettigheds-dokumentation — fjern den først"), eller (b) — matcher
præcedens bedst — spejl `red_slet_person`: saml mediets fakta og slet
`citation→conclusion→assertion→note→fact` FØR `DELETE FROM media`. Kæde-tabellerne står
alle i `version_pk_registry` med `skip_cols='{}'` (verificeret `schema.sql:2167-2169,2176`),
så cascade-varianten logges og er fortrydbar. Preview skal uanset hvad tælle fakta så
`kan_udrenses` er ærlig, og en verify-assert skal seede et medie med
`red_set_media_rettigheder`-fakta. Bredere: mediet kan polymorf-ankres af
`narrative`/`haendelse`/`story`/`note` (`subjekt_type`/`target_type='media'`); ingen live
red_-vej skaber dem i dag, men fix'et bør følge `red_slet_person`s komplethed frem for kun
at plastre fakta-tilfældet.

### M1 [MEDIUM, lav sandsynlighed] — `red_saet_portraet`: to samtidige kald kan sætte to primær-portrætter

**Lokation:** plan Task 3, linje 645-668 (spec §5.2).

**Symptom:** Nulstil-søskende-UPDATE og sæt-flag-UPDATE er to separate statements. Når
personen INTET portræt har i forvejen, matcher nulstil 0 rækker og tager ingen låse — to
samtidige transaktioner (READ COMMITTED) kan begge committe et `primaer:true` på hver sin
relation.

**Verifikation:**
```sql
UPDATE relation SET kvalifikator = nullif(kvalifikator - 'primaer', '{}'::jsonb)
 WHERE ... AND kvalifikator ? 'primaer';          -- T1 og T2: 0 rækker, 0 låse
IF p_media_id IS NOT NULL THEN
  UPDATE relation SET kvalifikator = coalesce(kvalifikator,'{}'::jsonb) || '{"primaer":true}'::jsonb
   WHERE ... AND objekt_id=p_media_id ...;         -- T1 låser r1, T2 låser r2 (forskellige rækker)
```
Interleaving: T1 nulstil (0 låse) → T2 nulstil (0 låse, ser ikke T1's ucommittede flag) →
T1 sæt m1 → T2 sæt m2 → begge commit → både r1 og r2 har `primaer:true`. Ingen
unik-constraint forhindrer to `primaer`-rækker pr. person. Verify-blokken (plan:584-599) er
seriel og fanger det aldrig.

**Konsekvens:** To "Portræt"-badges; `pickPortrait` vælger den første signerbare med
`primaer` (nondeterministisk mellem de to), bryder featurets "ét portræt"-invariant.
Selv-helende ved næste enkeltstående portræt-sæt; lav sandsynlighed (kræver to redaktører
der racer samme person på en 4-medie-prod).

**Foreslået fix:** Lås personens `afbildet`-relationer `FOR UPDATE` før nulstil, eller
kombinér nulstil+sæt i ét statement (fx `SET kvalifikator = CASE WHEN objekt_id=p_media_id
THEN … || primaer ELSE kvalifikator - 'primaer' END` over alle personens afbildet-rækker).

### L1 [LOW] — preview-feltet `afbildet` er et misnomer (indeholder ALLE relationer)

**Lokation:** plan Task 2, linje 449-457 + 481-483.

**Symptom:** Feltet `afbildet`/`antal_afbildet` i preview-jsonb indeholder — jf. funktionens
egen kommentar (plan:448 "ALLE relationer (enhver rolle, begge retninger) blokerer — ikke
kun 'afbildet'") — samtlige relationer, ikke kun `rolle='afbildet'`. Navnet kolliderer med
Task 7's `MediaAnvendelse.afbildet`, som KUN er person-afbildninger med `primaer`.

**Konsekvens:** Ingen funktionel fejl (UI'et viser `blokeringer`-teksten generisk, og
`fetchMediaAnvendelse` er en separat kilde). Ren forvirrings-/kontraktklarhedsrisiko for
fremtidig vedligehold.

**Foreslået fix:** Omdøb til `tilknytninger`/`antal_tilknytninger` i preview-kontrakten (og
`mapUdrensPreview`), så feltnavnet matcher semantikken.

---

## Verificeret UDEN fund

- **Cross-platform-kontrakt: verificeret, planens Kilder-note er korrekt.**
  `buildSuggestCall`/`planCall`/`role` findes KUN på web
  (`web/src/data/redaktionWrite.ts:456,492`); mobiles `submitChange(c, {dryRun}, deps)` har
  ingen degradering og kaster på `!call` (`mobile/src/data/redaktionWrite.ts:442-443`).
  Planens beslutning om web-kun-gate for erstat/udrens er faktuelt underbygget.
- **`SET search_path=public`: til stede på alle fire nye funktioner** (plan:240,442,501,646).
- **Migrations-idempotens (Task 4): korrekt.** `ADD COLUMN IF NOT EXISTS` +
  `CREATE OR REPLACE` matcher det eksisterende blok-mønster (fase 3-blok
  `db-migrations.sql:2727-2875`); ny blok appendes korrekt efter `red_publicer_personer`
  (:3109-3132). Dobbelt-kørsel er sikker.
- **Versionering af erstat/udrens/kvalifikator: korrekt.** `media` og `relation` står i
  `version_pk_registry` med `skip_cols='{}'` (`schema.sql:2168-2169,2176`);
  logging-triggeren dækker DELETE. Ny jsonb-kolonne bæres automatisk af snapshottet.
- **Hård delete blokeres ikke: verificeret.** Ingen `BEFORE DELETE`-trigger på
  `media`-tabellen; `media_variant` CASCADE'r korrekt (`schema.sql:100`).
- **`red_erstat_media_fil` dedup-guards: solide.** Egen-sha + fremmed-sha grene, med
  `media_sha256_uidx` (`schema.sql:90`) som race-bagstopper. Varianter re-registreres
  atomisk i samme change_set.
- **`bookmark` refererer IKKE media** (kun personer, `schema.sql:308`).
- **Task 4's `…`-kroppe er IKKE placeholder-mønster** — eksplicit dokumenteret som
  verbatim-kopi-instruktion (plan:719-722). Acceptabelt.
- **`relation_afbildet_uidx` garanterer ét afbildet-par** (`schema.sql:369-371`) —
  portræt-flagets entydighed holder (fraset M1's samtidigheds-hjørne).

## Spec-dækning (§3-§9)
De 11 tasks dækker specens skiver 1-7. Det eneste reelle hul er H1, som er arvet fra
spec §1's ufuldstændige FK-billede (deklarative FK'er talt, polymorfe FK-frie referencer
overset) og forplantet til §4's guard-design. M1 og L1 er plan-lokale.

---

## Phase 3 — Codex adversarial-review (2026-07-22, ægte Codex CLI, ingen `--model`-override)

**Verdict:** needs-attention (NO-SHIP før revision). H1 confirmed; M1 dismissed (med
korrekt begrundelse); L1 confirmed uændret. **To nye HIGH-fund**, begge i samme funktion
som H1 (`red_udrens_media`/preview):

- **Ny H2 — check-then-delete-race:** guardsne i `red_udrens_media` (EXISTS-tjek) og selve
  `DELETE FROM media` er to separate statements uden lås. En samtidig `red_relation`
  (`schema.sql:1191-1212` — INSERT'er blindt, ingen mål-eksistens-tjek) kan committe en ny
  `afbildet`-relation på mediet MELLEM tjek og slet.
- **Ny H3 — `story` er et fjerde LIVE polymorft anker H1's foreslåede fix stadig ville
  misse:** `red_opret_story` (`schema.sql:986-1009`) accepterer et vilkårligt
  `p_subjekt_type`/`p_subjekt_id`-par UDEN at validere målets eksistens eller type — en
  publiceret story kan altså have `subjekt_type='media'` pegende på et medie der senere
  udrenses. Modsiger Phase 1-reviewets antagelse om at "ingen live red_-vej" skaber den
  slags kryds-referencer.

## Phase 4 — reconcile (Claude, empirisk genverificeret 2026-07-22, undgår peer-review-laundering)

Alle tre Codex-påstande er selvstændigt reproduceret mod `schema.sql` på `main @ caeb6a3`
(ikke blot accepteret på Codex' ord):

| Fund | Verdikt | Reproduktion (verificeret af mig) |
|---|---|---|
| H1 | **confirmed** | Uændret fra Phase 1 — Codex' uafhængige genlæsning af samme kode-citater falder sammen med mit oprindelige fund. |
| M1 | **dismissed, korrekt begrundelse** | `begin_change_set` (`schema.sql:2234-2256`) bruger SAMME `max(id)+1`-mønster på `change_set` som `red_relation` gjorde på `relation` (kendt projekt-debt, jf. review 33's addendum). Planens `red_saet_portraet` (plan:650) kalder `begin_change_set` FØRST, før nogen af de to `relation`-UPDATEs — to samtidige kald racer altså på `change_set`s egen PK FØR de når portræt-logikken. Taberen rammer en uhåndteret `unique_violation` og ruller hele sit kald tilbage; scenariet "begge committer med `primaer:true`" i M1 kan derfor ikke opstå. Bekræftet ved direkte læsning af begge funktioners rækkefølge. |
| L1 | **confirmed, uændret severity** | Bekræftet ved genlæsning af plan:448-483 — feltet indeholder skam ALLE roller/retninger, ikke kun `afbildet`. (Codex' finjustering: "person-only" var en let overdrivelse i mit oprindelige ordvalg — begge retninger er inkluderet; ændrer intet ved fundets gyldighed.) |
| H2 (nyt) | **confirmed** | `red_relation` (`schema.sql:1191-1212`) verificeret: ingen `SELECT … FOR UPDATE`, intet mål-eksistens-tjek, ren blind INSERT. To separate statements (EXISTS-tjek, så DELETE) i samme plpgsql-funktion har et reelt — om end kun få-millisekunders — vindue mellem dem under READ COMMITTED. |
| H3 (nyt) | **confirmed, udvidet** | `red_opret_story` (`schema.sql:986-1009`) verificeret: `p_subjekt_type`/`p_subjekt_id` går direkte i INSERT uden nogen validering. **Samme mønster gælder `red_upsert_narrativ`** (`schema.sql:1170-1189`, verificeret af mig — Codex nævnte den i forbifarten, jeg har bekræftet den selvstændigt): `narrative.subjekt_type` er fritekst (kommentar `schema.sql:421`: "'person' \| 'family' \| 'line' ...", ikke en udtømmende CHECK-constraint), og RPC'en validerer intet. `haendelse` cascader FRA `narrative` (`ON DELETE CASCADE`, `schema.sql:436`) og er derfor ikke selvstændigt et fjerde anker — det følger narrativ-fixet gratis. **`note`** (target_type fritekst, `schema.sql:412-413`) har derimod INGEN live RPC der skriver `target_type='media'` direkte (`red_upsert_fakta`, `schema.sql:691-733`, skriver kun `fact`+`assertion`+`citation`+`conclusion` — ingen `note`); optages alligevel defensivt i fixet (samme "beskyt mod fremtidige skrivere"-begrundelse som `red_slet_person`s eksisterende `note`-håndtering). |

### Impact-bucketing

- **Silent-corruption (data-tab uden fejl, deterministisk, INGEN concurrency krævet):** H1 +
  H3 (story/narrativ). Sker for enhver solo-redaktør, hver gang, hvis mediet har
  rettigheds-fakta eller en tilknyttet story/narrativ. Højeste prioritet.
- **Race/concurrency (kræver samtidighed, lavere praktisk sandsynlighed ved dette
  prod-omfang — 6 medie-rækker, i praksis 1-2 samtidige redaktører):** H2. Reel, men en
  anden risikoklasse end H1/H3.
- **Selv-helende/UX (ingen data-tab):** M1 (dismissed — kan slet ikke ske som beskrevet).
- **Navngivnings-klarhed:** L1.

### Rettelser besluttet (indarbejdes i planen, se Task 2/4-revision)

1. **H1+H3 (completeness, ikke race):** `red_udrens_media_preview` og `red_udrens_media`
   udvides til at tjekke/blokere på: `fact` (subjekt_type='media', + hele kæden
   assertion/citation/conclusion via `target_type='fact'`), `story`
   (subjekt_type='media'), `narrative` (subjekt_type='media' — `haendelse` følger med via
   CASCADE, ingen selvstændig kode nødvendig). `note` medtages defensivt selvom ingen live
   skriver findes i dag (samme forsigtighed som `red_slet_person`). Verify-asserts skal
   seede ÉT medie med hver ankertype og bekræfte at `kan_udrenses=false` + at
   `red_udrens_media` fejler højlydt.
2. **H2 (race):** kollaps guard+slet til ÉT atomisk statement —
   `DELETE FROM media WHERE id=p_media_id AND NOT EXISTS(...) AND NOT EXISTS(...) …
   RETURNING …`, med `IF NOT FOUND THEN RAISE EXCEPTION` — lukker TOCTOU-vinduet til
   statement-udførelsens egen atomicitet (Postgres' standardmønster for check-then-act
   uden separate lock-primitiver på tværs af polymorfe, FK-frie tabeller). Ingen ændring af
   andre RPC'er (`red_relation`/`red_opret_story`/`red_upsert_narrativ` rører vi ikke) —
   proportionalt scope-holdt til fase 4's tre nye funktioner.
3. **M1:** ingen kodeændring — dokumenteres i planen som "verificeret umuligt" (ikke blot
   "lav sandsynlighed" som Phase 1 først antog).
4. **L1:** preview-feltet `afbildet`/`antal_afbildet` omdøbes til
   `tilknytninger`/`antal_tilknytninger` i RPC-kontrakten og `mapUdrensPreview` (Task 7).

**Læring:** en "hvilke tabeller refererer X"-analyse i en polymorf, FK-fri datamodel kan
IKKE stoppe ved `information_schema`-FK'er (spec §1's fejl) — den skal eksplicit
enumerere alle `subjekt_type`/`target_type`/`maal_type`-brugere, inklusive dem der (som
`story`/`narrative`) slet ikke validerer deres polymorfe mål ved skrivning. Samme
lærings-familie som review 33's `haendelse`-FK-fund, men her var problemet fravær af FK
snarere end en overset FK.
