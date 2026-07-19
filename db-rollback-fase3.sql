-- =====================================================================
-- Levende feed fase 3: kirurgisk rollback
--
-- Forudsætninger:
--   * Tag og verificer en fuld backup før kørsel.
--   * Stop fase 3-skrivninger under hele rollbacken.
--   * Kør med psql -v ON_ERROR_STOP=1 -f db-rollback-fase3.sql.
--
-- Sikkerhedsmodel:
--   * Alle ændringer sker i én transaktion.
--   * Eksisterende fase 3-tabeller låses før preflight.
--   * Rollbacken afbryder, hvis fase 3 indeholder data eller historik.
--   * Ingen DROP ... CASCADE: uventede afhængigheder skal stoppe rollbacken.
--   * Scriptet er idempotent, når fase 3 allerede er rullet tilbage.
--
-- Denne fil ruller KUN fase 3 tilbage. Fase 2-tabellen haendelse og den
-- fælles versionsmotor (change_set/change_event/log_change) bevares.
-- =====================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- Undgå to samtidige rollback-forsøg i samme database.
SELECT pg_advisory_xact_lock(hashtext('daa:levende-feed:fase3:rollback'));

-- Lås kun tabeller, der findes, så scriptet også tåler en delvis/allerede
-- gennemført rollback. ACCESS EXCLUSIVE lukker kapløbet mellem preflight og DROP.
DO $$
DECLARE
  v_table text;
  v_has_rows boolean;
BEGIN
  -- Samme forælder-før-barn-rækkefølge som story-RPC'erne bruger. Det
  -- reducerer deadlock-risikoen, hvis en sen læsetransaktion stadig er aktiv.
  FOREACH v_table IN ARRAY ARRAY['story', 'story_kilde', 'feed_pin']
  LOOP
    IF to_regclass(format('public.%I', v_table)) IS NOT NULL THEN
      EXECUTE format('LOCK TABLE public.%I IN ACCESS EXCLUSIVE MODE', v_table);
      EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM public.%I LIMIT 1)',
        v_table
      ) INTO v_has_rows;

      IF v_has_rows THEN
        RAISE EXCEPTION
          'Fase 3 rollback afbrudt: public.% indeholder data. Eksportér og håndtér data eksplicit før rollback.',
          v_table;
      END IF;
    END IF;
  END LOOP;
END $$;

-- Fase 3-historik må ikke efterlades som forældreløse revisionsspor. Vi
-- sletter den ikke automatisk: hvis den findes, kræver det en særskilt,
-- menneskeligt godkendt datahåndtering.
DO $$
BEGIN
  IF to_regclass('public.change_event') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.change_event
       WHERE tabel IN ('story', 'feed_pin')
     ) THEN
    RAISE EXCEPTION
      'Fase 3 rollback afbrudt: change_event indeholder story/feed_pin-historik.';
  END IF;

  IF to_regclass('public.change_set') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.change_set
       WHERE operation IN (
         'red_opret_story',
         'red_rediger_story',
         'red_set_story_status',
         'red_slet_story',
         'red_set_story_kilder',
         'red_set_feed_pin',
         'red_fjern_feed_pin'
       )
     ) THEN
    RAISE EXCEPTION
      'Fase 3 rollback afbrudt: change_set indeholder fase 3-historik.';
  END IF;
END $$;

-- Drift-værn: eksisterende metadata må kun være den fase 3-definition, vi
-- kender. Manglende rækker er tilladt, så en delvis rollback stadig kan køres.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.version_pk_registry
    WHERE tabel = 'story'
      AND (pk_cols IS DISTINCT FROM ARRAY['id']::text[]
           OR skip_cols IS DISTINCT FROM ARRAY[]::text[])
  ) OR EXISTS (
    SELECT 1
    FROM public.version_pk_registry
    WHERE tabel = 'feed_pin'
      AND (pk_cols IS DISTINCT FROM ARRAY['id']::text[]
           OR skip_cols IS DISTINCT FROM ARRAY[]::text[])
  ) THEN
    RAISE EXCEPTION
      'Fase 3 rollback afbrudt: version_pk_registry afviger fra den kendte fase 3-definition.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.vocab v
    JOIN (VALUES
      ('story_status', 'kladde', 'Under udarbejdelse — kun redaktion'),
      ('story_status', 'klar', 'Færdigskrevet, ikke publiceret'),
      ('story_status', 'publiceret', 'Synlig i feed for publikum'),
      ('story_status', 'arkiveret', 'Trukket tilbage — den normale slette-vej'),
      ('story_oprindelse', 'redaktoer', 'Redaktørskrevet'),
      ('story_oprindelse', 'llm_assisteret', 'LLM-kladde, menneskeligt godkendt (fase 4)')
    ) AS expected(scheme, code, label)
      ON expected.scheme = v.scheme AND expected.code = v.code
    WHERE v.label IS DISTINCT FROM expected.label
  ) THEN
    RAISE EXCEPTION
      'Fase 3 rollback afbrudt: vocab afviger fra den kendte fase 3-definition.';
  END IF;
END $$;

-- Fjern de eksakte PostgREST/RPC-signaturer fra fase 3.
DROP FUNCTION IF EXISTS public.red_opret_story(
  text, bigint, text, text, bigint, bigint, bigint, bigint,
  date, date, text, text, boolean
);
DROP FUNCTION IF EXISTS public.red_rediger_story(
  bigint, text, text, bigint, bigint, bigint, bigint,
  date, date, text, text, boolean
);
DROP FUNCTION IF EXISTS public.red_set_story_status(bigint, text);
DROP FUNCTION IF EXISTS public.red_slet_story(bigint);
DROP FUNCTION IF EXISTS public.red_set_story_kilder(bigint, jsonb);
DROP FUNCTION IF EXISTS public.red_set_feed_pin(text, text);
DROP FUNCTION IF EXISTS public.red_fjern_feed_pin(text);

-- Fjern kun de registry- og vocab-rækker, som fase 3 tilføjede. Den
-- verificerede pre-fase-3-prod-backup indeholder ingen af disse seks koder.
DELETE FROM public.version_pk_registry
WHERE tabel IN ('story', 'feed_pin');

DELETE FROM public.vocab
WHERE (scheme = 'story_status'
       AND code IN ('kladde', 'klar', 'publiceret', 'arkiveret'))
   OR (scheme = 'story_oprindelse'
       AND code IN ('redaktoer', 'llm_assisteret'));

-- Barn før forælder. Indekser, policies og triggers ejet af tabellerne
-- forsvinder sammen med dem. Uden CASCADE stopper uventede afhængigheder alt.
DROP TABLE IF EXISTS public.story_kilde;
DROP TABLE IF EXISTS public.feed_pin;
DROP TABLE IF EXISTS public.story;

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'OK: levende feed fase 3 er rullet tilbage';
END $$;
