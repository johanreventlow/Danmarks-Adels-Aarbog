# Review 19: Udledt slægtsnavn — dual-review (Claude + Codex)

**Dato:** 2026-07-03
**Scope:** branch `feat/udledt-slaegtsnavn-v2` mod `main` (`schema.sql`, `db-migrations.sql`,
`db-rls.sql`, `db-verify.sql`, `.claude/skills/daa-extract/scripts/post_load_fixup.R`, web+mobile
readers). DB-laget er allerede anvendt til prod (bruger-godkendt) på tidspunktet for denne review —
dette er en post-hoc kvalitetskontrol, ikke en pre-merge-gate.
**Spec:** `docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md`
**Plan:** `docs/superpowers/plans/2026-07-03-udledt-slaegtsnavn.md`

---

## Phase 1: Claude-review (code-analyzer, fresh eyes)

### H1 [HIGH] — `trg_lineage_regen` fyrer kun på UPDATE, ikke INSERT → reload nulstiller featuren stille

**Lokation:** `schema.sql:496-499`, `db-migrations.sql:1502-1505`

**Symptom:**

```sql
DROP TRIGGER IF EXISTS trg_lineage_regen ON lineage;
CREATE TRIGGER trg_lineage_regen
  AFTER UPDATE OF slaegtsnavn, parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_lineage();
```

**Verifikation (reproduceret empirisk):** `grep -c "lineage" .claude/skills/daa-extract/scripts/load_daa.R` → `0`. Loaderen opretter ALDRIG `lineage`-rækker. Kun `post_load_fixup.R` gør det, via:

```r
ex("INSERT INTO lineage (id, source_id, kode, navn, slaegtsnavn) VALUES ($1,$2,$3,$4,'Reventlow')
    ON CONFLICT (source_id, kode) DO UPDATE SET navn=EXCLUDED.navn, slaegtsnavn=EXCLUDED.slaegtsnavn",
   list(nid("lineage"), src, kode, lineage[[kode]]))
```

**Konsekvens:** Efter et FREMTIDIGT `load_daa.R --force-reset` (som `TRUNCATE CASCADE`r `lineage` —
dokumenteret projekt-mønster) er `lineage` tom, når `load_daa.R` opretter personer/konklusioner.
`trg_conclusion_regen` kører `regen_person_visning` på det tidspunkt, hvor `person_external_id` +
`lineage` begge er tomme → `visning_efternavn`/`visning_fuldt_navn` cachede som NULL for alle.
`post_load_fixup.R` kører BAGEFTER og INSERTer de 5 `lineage`-rækker for FØRSTE gang på den friske
base → rammer plain-INSERT-stien (intet konflikt) → `UPDATE OF`-triggeren fyrer ALDRIG → ingen
cascade-regen. Frontend falder stille tilbage til `visning_navn` (kort navn) via sin egen
`?? visning_navn`-fallback, så regressionen er usynlig uden aktiv verifikation.

Dette var netop den risiko min egen plan (Task 7) forsøgte at lukke ("reload-durabilitet") — jeg
verificerede at VÆRDIEN (`slaegtsnavn='Reventlow'`) overlever et reload, men ikke at CASCADEN der
propagerer værdien til `person`-cachen også gør.

**Foreslået fix:** `AFTER INSERT OR UPDATE OF slaegtsnavn, parent_lineage_id ON lineage` (triggeren
skal også fyre ved første INSERT), OG/ELLER tilføj en eksplicit
`SELECT regen_person_visning(id) FROM person;`-sweep i `post_load_fixup.R` efter lineage-sektionen,
så et reload er selv-helbredende uafhængigt af INSERT-vs-UPDATE-stien.

---

### H2 [HIGH] — `red_slet_person` fejler for enhver karantæneret person (manglende FK-cascade)

**Lokation:** `schema.sql:227-231` (ny tabel), `schema.sql:753-786` (`red_slet_person`, IKKE
ændret af denne branch, men nu brudt af den nye tabel)

**Symptom:**

```sql
CREATE TABLE IF NOT EXISTS slaegtsnavn_karantaene (
  person_id  BIGINT PRIMARY KEY REFERENCES person(id),  -- ingen ON DELETE CASCADE
  n_distinct INT NOT NULL,
  noteret_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`red_slet_person(p_person_id)` sletter fra `citation`, `conclusion`, `assertion`, `note`,
`narrative`, `relation`, `fact`, `person_external_id`, `family_member` — men aldrig fra
`slaegtsnavn_karantaene` — før den til sidst kører `DELETE FROM person WHERE id = p_person_id`.

**Verifikation (reproduceret ved kode-inspektion):** `grep -n "slaegtsnavn_karantaene" schema.sql`
viser tabellen kun refereret i `regen_person_visning` (INSERT/DELETE), aldrig i `red_slet_person`.
FK har ingen `ON DELETE`-klausul → default `NO ACTION` → violation ved sletning af en person der
har en karantæne-række.

**Konsekvens:** 0 karantæne-rækker i prod i dag (0 personer med >1 distinkt linje-medlemskab), så
fejlen er IKKE aktiv nu — men den bygger på præcis det scenarie featuren selv er designet defensivt
til at håndtere ("fremtidig vækst" — flere linjer/forgrening). Når det scenarie først opstår, fejler
sletning af den pågældende person hårdt uden en indlysende årsag.

**Foreslået fix:** Tilføj `ON DELETE CASCADE` til FK'en (enklest, matcher at karantæne-log-rækken er
meningsløs uden personen), ELLER tilføj
`DELETE FROM slaegtsnavn_karantaene WHERE person_id = p_person_id;` til `red_slet_person` (matcher
den eksplicitte FK-ordnede sletnings-stil resten af funktionen allerede bruger).

---

### M1 [MEDIUM] — TOCTOU-race i cyklus-forebyggelse under READ COMMITTED

**Lokation:** `schema.sql:174-186` (`trg_lineage_prevent_cycle` + `lineage_ancestors`)

**Symptom:** `lineage_ancestors()` læser `parent_lineage_id` med almindelige (ikke-låsende)
`SELECT`-kald. To samtidige transaktioner der sætter A→B hhv. B→A kan begge bestå cyklus-tjekket
(hver læser den andens FØR-commit-tilstand) og begge committe — en udetekteret cyklus opstår.

**Konsekvens (hvis udløst):** `lineage_ancestors`/`lineage_descendants` `RAISE EXCEPTION` ved
ethvert efterfølgende kald i den cyklus, hvilket betyder `regen_person_visning` — og dermed ENHVER
redigering af en konklusion/assertion/external_id — begynder at fejle hårdt for alle personer i det
berørte undertræ, indtil nogen manuelt retter `lineage`-rækkerne via SQL.

**Vurdering:** Lav sandsynlighed under nuværende single-redaktør-drift (projektets etablerede
"single-writer-PoC"-mønster), men blast radius er høj hvis den udløses. Vurderes som defer — ikke
blokerende for nuværende drift, men bør noteres som kendt begrænsning før multi-redaktør-brug.

---

## Phase 2: Trigger-decision

Codex-review udløst — begrundelse:
- [x] Draft indeholder executable SQL/R-snippets (foreslåede fixes)
- [x] Repeated failure pattern (memory-dokumenteret: `TRUNCATE CASCADE`-reload-tab, tidligere
  `_version_upsert_row` GENERATED-kolonne-bug — samme klasse "reload-durabilitet"-fejl)
- [x] Severity-vurdering (H1 vs. M1) driver om fix er blokerende

---

## Phase 3-4: Codex adversarial-review + reconcile

Verdict: **needs-attention** (no-ship uden fix).

**Bekræftet (verified empirisk af Codex, uafhængig kode-læsning):**
- H1: bekræftet. `AFTER INSERT OR UPDATE OF ...` er gyldig Postgres-syntaks, MEN Codex fangede at
  `OLD` ikke er tilgængelig ved INSERT — den oprindelige foreslåede guard
  (`NEW.x IS DISTINCT FROM OLD.x`) ville have fejlet ved runtime på en frisk INSERT. Rettet til
  `TG_OP = 'INSERT' OR ...`-guard FØR OLD-referencerne evalueres.
- H2: bekræftet. Codex korrigerede den oprindelige `ON DELETE CASCADE`-anbefaling: en
  `CREATE TABLE IF NOT EXISTS`-ændring i schema.sql ændrer IKKE en allerede-deployet FK-constraint
  på prod (ville kræve en separat `DROP CONSTRAINT`/`ADD CONSTRAINT`-migration). Valgte i stedet
  Codex' alternativ: eksplicit `DELETE FROM slaegtsnavn_karantaene` i `red_slet_person` — ingen
  constraint-ændring nødvendig, virker øjeblikkeligt på prods eksisterende skema.

**Recalibreret:**
- M1: nedgraderet fra MEDIUM til LOW. Codex' vurdering: der findes i dag INGEN eksponeret
  redaktør-RPC eller UI-sti der skriver `lineage.parent_lineage_id` (kun direkte privilegeret SQL,
  matcher projektets "single-writer-PoC"-konvention) — TOCTOU-racen er reel, men ikke aktivt
  udnyttelig under nuværende drift. Dokumenteret som kendt begrænsning, ingen kode-ændring nu.

**Fix implementeret + lokalt verificeret** (daa_test2, som allerede afspejler prods fulde
migrations-historik): 2 nye db-verify.sql-asserts (H1: frisk lineage-INSERT trigger regen; H2:
`red_slet_person` fejler ikke for en karantæneret person). Fuld suite 34/34 OK (op fra 32/32), 0
regressioner.

**Læring:** Min egen plan (Task 7) verificerede at VÆRDIEN (`lineage.slaegtsnavn`) overlever et
reload — men ikke at CASCADEN der propagerer værdien til `person`-cachen også gør, fordi triggeren
kun lyttede på UPDATE. En "reload-durabilitet"-test skal eksplicit teste en FRISK INSERT-sti, ikke
kun en gentaget UPDATE-sti på allerede-eksisterende rækker — de to rammer forskellig trigger-logik.

## Phase 5-6: Anvendt til prod (2026-07-03, bruger-godkendt)

Begge fixes (H1 + H2) anvendt til prod via `mcp__supabase__apply_migration`. Data uændret (0/923
mangler `visning_fuldt_navn`, 0 karantæne, 580 fik afledt efternavn — matcher pre-fix-tilstand,
som forventet da fixet kun rører fremtidige INSERT/DELETE-stier, ikke eksisterende data).
