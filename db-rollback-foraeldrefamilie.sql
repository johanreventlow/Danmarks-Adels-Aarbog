-- =====================================================================
-- Problem 2 — TARGETED ROLLBACK (Fase 4 down-script)
-- =====================================================================
-- Fjerner KUN Problem 2-additionerne kirurgisk (ingen fuld schema-restore, som er risikabel på
-- Supabase). Reverterer de tre objekt-refererende funktioner til deres pre-Problem-2-versioner
-- (fra git 64cfdfa), sletter backfill/slot-data, og dropper de nye objekter + kolonner.
--
-- BRUG: primær rollback ved fejlet cutover (fanger IKKE skrivninger foretaget efter cutover — kør
-- kun under skrive-frys). ØVES OBLIGATORISK mod den test-restorede dump-kopi før prod-cutover.
-- Kør som ejer/service_role. Atomisk (én transaktion).
--
-- Efterlader bevidst: guard-tilføjelserne i red_upsert_fakta/red_opret_fakta/red_tilfoej_oplysning/
-- red_set_konklusion/red_edit_oplysning/red_slet_oplysning (de tjekker kun faktatype-strengen
-- 'forældrefamilie', refererer ingen droppede kolonner → harmløs død kode uden slot-data/-vocab).
BEGIN;

-- 1) slet backfill/slot-data (FK-ordnet: conclusion → citation → assertion → fact)
DELETE FROM conclusion WHERE target_type='fact' AND target_id IN
  (SELECT id FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie');
DELETE FROM citation WHERE assertion_id IN
  (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN
    (SELECT id FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie'));
DELETE FROM assertion WHERE target_type='fact' AND target_id IN
  (SELECT id FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie');
DELETE FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie';

-- 2) drop konflikt-view (afhænger af fact/assertion/conclusion → skal væk før kolonne-drop)
DROP VIEW IF EXISTS red_foraeldre_konflikt;

-- 3) revertér de tre objekt-refererende funktioner til pre-Problem-2 (git 64cfdfa)
CREATE OR REPLACE FUNCTION red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_familie_link', format('Slettede familie-link %s/%s/%s', p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
END $$;

CREATE OR REPLACE FUNCTION red_tilfoej_barn(p_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn', p_konfidens text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cyklus boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_tilfoej_barn', format('Tilføjede barn %s til familie %s', p_barn_id, p_family_id), 'person', p_barn_id);
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_barn_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_barn_id; END IF;
  IF p_rolle NOT IN ('barn','adopteret_barn','plejebarn','stedbarn') THEN RAISE EXCEPTION 'Ugyldig barn-rolle %', p_rolle; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle='partner')
    THEN RAISE EXCEPTION 'Person % er partner i familie % — kan ikke også være barn', p_barn_id, p_family_id; END IF;
  WITH RECURSIVE efterkommere(pid) AS (
    SELECT p_barn_id
    UNION
    SELECT b.person_id FROM efterkommere e
      JOIN family_member par ON par.person_id = e.pid AND par.rolle = 'partner'
      JOIN family_member b   ON b.family_id = par.family_id
        AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
  )
  SELECT EXISTS(
    SELECT 1 FROM family_member fp
    WHERE fp.family_id = p_family_id AND fp.rolle='partner' AND fp.person_id IN (SELECT pid FROM efterkommere)
  ) INTO v_cyklus;
  IF v_cyklus THEN RAISE EXCEPTION 'Cyklus: barn % er ane til en partner i familie %', p_barn_id, p_family_id; END IF;
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
END $$;

CREATE OR REPLACE FUNCTION red_flyt_barn(p_fra_family_id bigint, p_til_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_konfidens text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_flyt_barn', format('Flyttede barn %s fra familie %s til familie %s', p_barn_id, p_fra_family_id, p_til_family_id), 'person', p_barn_id);
  IF p_fra_family_id = p_til_family_id THEN RAISE EXCEPTION 'Fra- og til-familie er ens'; END IF;
  SELECT konfidens INTO v_konfidens FROM family_member
    WHERE family_id=p_fra_family_id AND person_id=p_barn_id AND rolle=p_rolle;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barn-link findes ikke (family %, person %, rolle %)', p_fra_family_id, p_barn_id, p_rolle; END IF;
  PERFORM red_tilfoej_barn(p_til_family_id, p_barn_id, p_rolle, v_konfidens);
  PERFORM red_slet_familie_link(p_fra_family_id, p_barn_id, p_rolle);
END $$;

-- 4) drop de nye RPC'er + helper (nu ingen refererer objekt-kolonnerne)
DROP FUNCTION IF EXISTS red_tilfoej_foraeldre_paastand(bigint, bigint, bigint, text, text, text);
DROP FUNCTION IF EXISTS red_vaelg_foraeldre(bigint, text);
DROP FUNCTION IF EXISTS _ensure_foraeldrefamilie_redaktionel(bigint, bigint);

-- 5) drop EXCLUDE-constraint
ALTER TABLE family_member DROP CONSTRAINT IF EXISTS family_member_en_foedselsfamilie;

-- 6) drop objekt-kolonner + indeks
DROP INDEX IF EXISTS ix_assertion_objekt;
ALTER TABLE assertion DROP COLUMN IF EXISTS objekt_type;
ALTER TABLE assertion DROP COLUMN IF EXISTS objekt_id;

-- 7) fjern vocab-rækken
DELETE FROM vocab WHERE scheme='faktatype' AND code='forældrefamilie';

COMMIT;
