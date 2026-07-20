-- =====================================================================
-- Levende feed fase 2: kirurgisk rollback
--
-- Forudsætninger:
--   * Tag og verificer en fuld backup før kørsel.
--   * Stop fase 2-skrivninger under hele rollbacken.
--   * Hvis fase 3 (story/story_kilde/feed_pin) er anvendt: kør
--     db-rollback-fase3.sql FØRST. story.haendelse_id referencer haendelse,
--     og DROP TABLE kan ikke fjerne en tabel, som en anden tabels
--     fremmednøgle stadig peger på.
--   * Kør med psql -v ON_ERROR_STOP=1 -f db-rollback-fase2.sql.
--
-- Sikkerhedsmodel:
--   * Alle ændringer sker i én transaktion.
--   * haendelse låses før preflight, hvis den findes.
--   * Rollbacken afbryder, hvis haendelse indeholder data eller historik,
--     eller hvis fase 3-tabellen story stadig findes (forkert rækkefølge).
--   * Ingen DROP ... CASCADE: uventede afhængigheder skal stoppe rollbacken.
--   * Scriptet er idempotent, når fase 2 allerede er rullet tilbage.
--
-- Denne fil ruller KUN fase 2 tilbage. Den fælles versionsmotor
-- (change_set/change_event/log_change) bevares.
-- =====================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- Undgå to samtidige rollback-forsøg i samme database.
SELECT pg_advisory_xact_lock(hashtext('daa:levende-feed:fase2:rollback'));

-- Fase 3 afhænger af fase 2 (story.haendelse_id). Rul fase 3 tilbage først.
DO $$
BEGIN
  IF to_regclass('public.story') IS NOT NULL THEN
    RAISE EXCEPTION
      'Fase 2 rollback afbrudt: public.story findes stadig. Kør db-rollback-fase3.sql først.';
  END IF;
END $$;

-- Lås kun haendelse, hvis den findes, så scriptet også tåler en
-- delvis/allerede gennemført rollback. ACCESS EXCLUSIVE lukker kapløbet
-- mellem preflight og DROP.
DO $$
DECLARE
  v_has_rows boolean;
BEGIN
  IF to_regclass('public.haendelse') IS NOT NULL THEN
    LOCK TABLE public.haendelse IN ACCESS EXCLUSIVE MODE;
    SELECT EXISTS (SELECT 1 FROM public.haendelse LIMIT 1) INTO v_has_rows;

    IF v_has_rows THEN
      RAISE EXCEPTION
        'Fase 2 rollback afbrudt: public.haendelse indeholder data. Eksportér og håndtér data eksplicit før rollback.';
    END IF;
  END IF;
END $$;

-- Fase 2-historik må ikke efterlades som forældreløse revisionsspor. Vi
-- sletter den ikke automatisk: hvis den findes, kræver det en særskilt,
-- menneskeligt godkendt datahåndtering.
DO $$
BEGIN
  IF to_regclass('public.change_event') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.change_event
       WHERE tabel = 'haendelse'
     ) THEN
    RAISE EXCEPTION
      'Fase 2 rollback afbrudt: change_event indeholder haendelse-historik.';
  END IF;

  IF to_regclass('public.change_set') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.change_set
       WHERE operation = 'red_set_haendelse_status'
     ) THEN
    RAISE EXCEPTION
      'Fase 2 rollback afbrudt: change_set indeholder fase 2-historik.';
  END IF;
END $$;

-- Drift-værn: eksisterende metadata må kun være den fase 2-definition, vi
-- kender. Manglende rækker er tilladt, så en delvis rollback stadig kan køres.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.version_pk_registry
    WHERE tabel = 'haendelse'
      AND (pk_cols IS DISTINCT FROM ARRAY['id']::text[]
           OR skip_cols IS DISTINCT FROM ARRAY[
             'subjekt_type', 'subjekt_id', 'narrative_id', 'noegle',
             'span_start', 'span_laengde', 'klausul', 'kategori',
             'date_min', 'date_max', 'date_qualifier', 'date_raw',
             'fact_id', 'relation_id', 'pass_version'
           ]::text[])
  ) THEN
    RAISE EXCEPTION
      'Fase 2 rollback afbrudt: version_pk_registry afviger fra den kendte fase 2-definition.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.vocab v
    JOIN (VALUES
      ('haendelse_feed_status', 'kandidat', 'Umarkeret — må vises som arkiv-kort'),
      ('haendelse_feed_status', 'interessant', 'Redaktørens dom: godt feed-stof (boostes)'),
      ('haendelse_feed_status', 'skjult', 'Aldrig i feed'),
      ('haendelse_kategori', 'embede', 'Embede/udnævnelse'),
      ('haendelse_kategori', 'uddannelse', 'Uddannelse/immatrikulation'),
      ('haendelse_kategori', 'rejse', 'Rejse/udlandsophold'),
      ('haendelse_kategori', 'krig', 'Krig/militær tjeneste'),
      ('haendelse_kategori', 'ejendom', 'Ejendom/køb/salg/arv'),
      ('haendelse_kategori', 'kirke', 'Kirke/kloster/gejstligt'),
      ('haendelse_kategori', 'hof', 'Hof/ceremoni/hyldning'),
      ('haendelse_kategori', 'familie', 'Familiebegivenhed'),
      ('haendelse_kategori', 'personligt', 'Personligt/øvrigt dateret'),
      ('haendelse_kategori', 'andet', 'Andet')
    ) AS expected(scheme, code, label)
      ON expected.scheme = v.scheme AND expected.code = v.code
    WHERE v.label IS DISTINCT FROM expected.label
  ) THEN
    RAISE EXCEPTION
      'Fase 2 rollback afbrudt: vocab afviger fra den kendte fase 2-definition.';
  END IF;
END $$;

-- Fjern den eksakte PostgREST/RPC-signatur fra fase 2.
DROP FUNCTION IF EXISTS public.red_set_haendelse_status(bigint, text);

-- Fjern kun de registry- og vocab-rækker, som fase 2 tilføjede. Den
-- verificerede pre-fase-2-prod-backup indeholder ingen af disse tretten koder.
DELETE FROM public.version_pk_registry
WHERE tabel = 'haendelse';

DELETE FROM public.vocab
WHERE (scheme = 'haendelse_feed_status'
       AND code IN ('kandidat', 'interessant', 'skjult'))
   OR (scheme = 'haendelse_kategori'
       AND code IN ('embede', 'uddannelse', 'rejse', 'krig', 'ejendom',
                     'kirke', 'hof', 'familie', 'personligt', 'andet'));

-- Indekser, policies og trigger ejet af tabellen forsvinder sammen med den.
-- Uden CASCADE stopper uventede afhængigheder alt (fx hvis story stadig
-- refererer haendelse på trods af preflight-tjekket ovenfor).
DROP TABLE IF EXISTS public.haendelse;

COMMIT;

DO $$
BEGIN
  RAISE NOTICE 'OK: levende feed fase 2 er rullet tilbage';
END $$;
