-- =====================================================================
--  Inkrementelle migrationer for den LEVENDE Supabase-base.
--  schema.sql er source of truth; denne fil afstemmer en allerede
--  deployet base op til den. Alt er idempotent (IF NOT EXISTS) — sikkert
--  at køre flere gange. Kør i Supabase -> SQL Editor.
--
--  Baggrund: den levende base kan drifte fra schema.sql (manuelle ALTER'er
--  blev ikke altid anvendt). Se docs/ + memory 'live-base-schema-drift'.
-- =====================================================================

-- ---- 2026-06 (tidligere manuelle tilføjelser, jf. CLAUDE.md §5) ----
ALTER TABLE person        ADD COLUMN IF NOT EXISTS koen      TEXT;
ALTER TABLE family_member ADD COLUMN IF NOT EXISTS konfidens TEXT;
-- (narrative-tabellen: oprettes af schema.sql hvis den mangler)

-- ---- 2026-06-15: gaps fundet ved TNG-analyse (DNA bevidst udeladt) ----

-- #3 Citation: bevar ordret kildeuddrag + citat-dato (TNG citetext/citedate).
ALTER TABLE citation   ADD COLUMN IF NOT EXISTS citat_tekst TEXT;
ALTER TABLE citation   ADD COLUMN IF NOT EXISTS citat_dato  TEXT;

-- #4 Privacy-granularitet: manuel skjulning adskilt fra afledt levende-status.
ALTER TABLE person     ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;
ALTER TABLE note       ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;
ALTER TABLE narrative  ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;

-- #5 (minor) Arkiv-adresse.
ALTER TABLE repository ADD COLUMN IF NOT EXISTS adresse TEXT;

-- 2026-06-15 (normaliserings-pass): koen kontrolleret på DB-niveau (invariant #9).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'person_koen_chk') then
    alter table person add constraint person_koen_chk
      check (koen in ('mand','kvinde','ukendt'));
  end if;
end $$;

-- 2026-06-16: indekser til relations-/evidens-opslag (UI + validering var seq-scan
-- -> statement timeout på self-joins). Idempotent.
CREATE INDEX IF NOT EXISTS ix_fammember_person   ON family_member(person_id);
CREATE INDEX IF NOT EXISTS ix_fammember_family   ON family_member(family_id);
CREATE INDEX IF NOT EXISTS ix_extid_linje_nr     ON person_external_id(linje, nr);
CREATE INDEX IF NOT EXISTS ix_extid_person       ON person_external_id(person_id);
CREATE INDEX IF NOT EXISTS ix_fact_subjekt       ON fact(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_assertion_target   ON assertion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_conclusion_target  ON conclusion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_citation_assertion ON citation(assertion_id);
CREATE INDEX IF NOT EXISTS ix_relation_subjekt   ON relation(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_relation_objekt    ON relation(objekt_type, objekt_id);
CREATE INDEX IF NOT EXISTS ix_narrative_subjekt  ON narrative(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_person_visningnavn ON person(visning_navn);

-- #1 Barn-relationstype: INGEN skemaændring — udvidet vocab på family_member.rolle
--    ('barn' | 'adopteret_barn' | 'plejebarn' | 'stedbarn'). Kun 'barn' tæller
--    som blodslægtskab i finderen.

-- ---- 2026-06-23: SLÆGTSLINJER navngives — trin (a) af lineage-promovering ----
--   Linjer levede kun som bart 'I'..'V'-token på person_external_id.linje.
--   Her får de en entitet med navn. Forward-kompatibel med (b): adling, forgrening,
--   eget våben m.m. tilføjes additivt senere (se schema.sql lineage-kommentar + §5/§9).
CREATE TABLE IF NOT EXISTS lineage (
  id        BIGINT PRIMARY KEY,
  source_id BIGINT REFERENCES source(id),
  kode      TEXT,
  navn      TEXT NOT NULL,
  UNIQUE (source_id, kode)
);
CREATE INDEX IF NOT EXISTS ix_lineage_src_kode ON lineage(source_id, kode);

-- Backfill: udled (source_id, kode) fra de faktiske eksterne ID'er (ingen hardcodet
-- source_id). Navn pr. kode fra DAA-stamtavlens linje-overskrifter. Idempotent.
INSERT INTO lineage (id, source_id, kode, navn)
SELECT row_number() OVER (ORDER BY x.source_id, x.kode) AS id,
       x.source_id, x.kode,
       CASE x.kode
         WHEN 'I'   THEN 'Den holstenske linje'
         WHEN 'II'  THEN 'Linjen Gallentin'
         WHEN 'III' THEN 'Den mecklenburgske linje'
         WHEN 'IV'  THEN 'Den lensgrevelige linje af 1767'
         WHEN 'V'   THEN 'Den grevelige linje af 1673'
       END AS navn
FROM (SELECT DISTINCT source_id, linje AS kode
      FROM person_external_id
      WHERE linje IN ('I','II','III','IV','V')) x
ON CONFLICT (source_id, kode) DO NOTHING;
