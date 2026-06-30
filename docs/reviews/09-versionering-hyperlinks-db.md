# Review 09 — Versionering + hyperlinks (DB-lag)

**Dato:** 2026-06-30
**Område:** `schema.sql` / `db-migrations.sql` / `db-rls.sql` / `db-verify.sql` — VERSIONERING + HYPERLINKS-sektionen (11-task DB-plan, merged til main lokalt).
**Reviewer:** Claude (draft) → Codex (adversarisk) → reconcile.
**Test-base:** lokal prod-kopi (se [[lokal-db-testbase]]); 22 verify-asserts grønne før review.

> Bemærk: 3 bugs blev allerede fanget+rettet under TDD-implementeringen (flerlinjet rolle-tjek mis-placerede begin_change_set; assert-filter-fejlklassificering; `FOREACH IN ARRAY NULL`-crash på non-person-restore). Dette review leder efter det der OVERLEVEDE de 22 asserts.

---

## H1 [HIGH] — Optimistisk divergens-tjek (B9) springer DELETE-inverse over → blind PK-overskrivning

**Lokation:** `schema.sql` `red_fortryd_change_set`, inverse-loop (`IF ev.op IN ('INSERT','UPDATE') THEN ...`).

**Symptom:** Divergens-tjekket (B9, der skal lukke H4 "blind PK-baseret overskrivning") køres kun for `INSERT`- og `UPDATE`-events. For et `DELETE`-event (hvor inverse er at GENINDSÆTTE `foer`) er der INGEN sammenligning af nuværende tilstand.

**Verifikation (kode-citat):**
```sql
v_cur := _version_current_row(ev.tabel, ev.row_pk);
IF ev.op IN ('INSERT','UPDATE') THEN
  IF v_cur IS DISTINCT FROM ev.efter THEN
    v_div := v_div + 1;
    IF NOT p_force THEN RAISE EXCEPTION 'FEJL: nyere ændring rører ...'; END IF;
  END IF;
END IF;
-- DELETE-grenen nedenfor kalder _version_upsert_row(ev.foer) UDEN tjek:
ELSIF ev.op='DELETE' THEN
  PERFORM _version_upsert_row(ev.tabel, ev.foer);
```

**Konsekvens (failure-scenarie):** change_set CS slettede række med PK=K. Efter sletningen genbruger en anden handling samme PK=K (max(id)+1-mønsteret gør dette muligt, jf. spec §4.6) med HELT andre data. Fortryd-CS kalder `_version_upsert_row(foer)` → `ON CONFLICT (K) DO UPDATE` → **overskriver den fremmede række silently** med den gamle, slettede tilstand. Dette er præcis den H4/B9 var skrevet for at forhindre — men kun INSERT/UPDATE-grenen fik beskyttelsen.

**Foreslået fix:** Generalisér tjekket til alle op-typer ved at sammenligne mod den "post-state" sættet efterlod (DELETE efterlod række ABSENT → forventet `v_cur IS NULL`):
```sql
DECLARE v_forventet jsonb;
...
v_cur := _version_current_row(ev.tabel, ev.row_pk);
v_forventet := CASE WHEN ev.op='DELETE' THEN NULL ELSE ev.efter END;
IF v_cur IS DISTINCT FROM v_forventet THEN
  v_div := v_div + 1;
  IF NOT p_force THEN
    RAISE EXCEPTION 'FEJL: nyere ændring rører %/% — afvist (brug force)', ev.tabel, ev.row_pk;
  END IF;
END IF;
```
(fjerner `IF ev.op IN ('INSERT','UPDATE')`-indpakningen; gælder nu også DELETE).

---

## L1 [LOW] — Ubrugte variabler i `red_edit_oplysning`

**Lokation:** `schema.sql` / `db-migrations.sql` `red_edit_oplysning` DECLARE.

**Verifikation:** `DECLARE v_tt text; v_tid bigint; v_old assertion; v_new bigint; v_cit bigint;` — `v_tt` og `v_tid` bruges aldrig (arvet fra plan-skabelonen).

**Konsekvens:** Ingen runtime-effekt; støj. Ryddes i /simplify.

---

## L2 [LOW] — `profiles.navn` versioneres (spec-intent var kun reventlow_person_id)

**Lokation:** `version_pk_registry`-seed: `('profiles', ARRAY['id'], ARRAY['email','rolle'])`.

**Symptom:** skip_cols = {email, rolle}. Logget = {navn, reventlow_person_id}. Spec §4.3.1 sagde "versionér kun reventlow_person_id-bindingen" (navn fandtes ikke da specen blev skrevet; tilføjet i T10).

**Konsekvens:** Minimal — navn er redaktørens visningsnavn, ikke auth/PII på samme måde som email/rolle. Afklar om navn skal i skip_cols for at matche spec-intent strengt. Ikke en korrektheds-bug.

---

## Stier vurderet KORREKTE (ikke fund)

- **begin_change_set re-entrancy (B7):** verificeret af T5b (nested red_opret_person → ét sæt).
- **log_change kolonne-projektion + no-op-skip:** T4 + clean-slate.
- **Composite-PK row_pk/restore-hjælpere (B11):** T7b round-trippede family_member (3-kol); registry pk_cols matcher faktiske PK-constraints (verificeret).
- **parse_mentions grammatik:** T9 (malformed/escaped/leading-zero ignoreret).
- **Reverse-seq FK-sikkerhed (H5):** T8b (person-slet-restore genskaber fuld FK-graf).
- **Re-logging-undgåelse under restore:** app.change_set_id NULLes før inverse-DML.

---

## Codex adversarisk-review konsekvens (2026-06-30)

Verdict: needs-attention → **needs-fix** (2 HIGH bekræftet, begge rettet + regressions-testet).

**Bekræftet (verificeret empirisk mod lokal testbase):**
- **H1** — DELETE-inverse springer B9-divergens-tjek over. Reproduceret: manuelt DELETE-event + PK-genbrug ('FREMMED-NY') → `red_fortryd_change_set(cs,false)` overskrev til 'GAMMEL' UDEN afvisning. Fix: `v_forventet := CASE WHEN op='DELETE' THEN NULL ELSE efter END; IF v_cur IS DISTINCT FROM v_forventet`. Regressions-assert tilføjet.
- **H2** (opgraderet fra L2 af Codex) — `_version_upsert_row` nulstillede skip_cols ved restore. Reproduceret: partial profiles-snapshot → `null value in column "rolle" violates not-null constraint`. **Første fix (kun SET-klausul) var utilstrækkelig** — INSERT-rækkedannelsen fejler på NOT NULL FØR ON CONFLICT-arbitrering. Fuld fix: INSERT lister kun snapshot-kolonner eksplicit (skip_cols → DEFAULT ved insert, bevares ved update). End-to-end-assert (profil-bundet person-slet-restore) tilføjet.

**Inferred / deferred (ikke rettet — bevidst):**
- **H3 TOCTOU** — `_version_current_row`-tjek + inverse-DML er ikke-atomiske; samtidig writer kan ændre rækken i vinduet. **DEFER:** projektet er eksplicit single-writer PoC (spec §4.6, samme bucket som `max(id)+1`-id-tildeling). Hele restore kører i én txn; uden samtidige writers er vinduet tomt. Genåbnes ved flerbruger-skrivning.

**Dismissed:**
- **L1** (ubrugte vars i red_edit_oplysning) — Codex enig: ikke ship-blocker. Ryddes i /simplify.

**Impact-buckets (verified):**
- Silent-corruption / semantic drift: 2 (H1 blind PK-overskrivning, H2 skip_cols-tab/crash) — begge HIGH, begge rettet.
- Deferred (out-of-scope threat-model): 1 (H3 TOCTOU).

**Læring:** ON CONFLICT DO UPDATE beskytter ikke mod NOT NULL-violation i selve INSERT-rækkedannelsen — partial-snapshot-restore skal liste insert-kolonner eksplicit, ikke `(jsonb_populate_record).*`. Og B9-divergens-tjek skal dække DELETE-inverse (post-state = NULL), ikke kun INSERT/UPDATE.
