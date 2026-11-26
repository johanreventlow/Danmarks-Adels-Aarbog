-- Linjernes adelsnavn: to kildebundne fakta på 2018-20-linjerne IV og V
-- (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md, decisions 2026-11-26).
--
-- Forudsætning: blokken `adelsnavn-faktatype` fra db-migrations.sql er kørt (vocab-rækken findes).
-- Skrivevej: red_upsert_fakta (redaktionens RPC: ændringssæt, påstand, citation, afklaret konklusion), så
-- skrivningen kan fortrydes som en redaktionel ændring. Kilden er fritekst (red_upsert_fakta sætter source_id NULL).
--
-- Kørsel (projektejerens shell; aktøren gives som variabel og står aldrig i filen):
--   psql "$DSN" -v redaktoer_uid=<uuid> -f docs/runbooks/2026-11-26-linjernes-adelsnavn.sql            -- prøve: ROLLBACK
--   psql "$DSN" -v redaktoer_uid=<uuid> -v skriv=1 -f docs/runbooks/2026-11-26-linjernes-adelsnavn.sql -- skriv: COMMIT
-- `skriv` skal være en psql-boolean (1/0, true/false); udeladt = prøve. Uden redaktoer_uid stopper skriptet med fejlkode.
-- Idempotent: en linje, der allerede har en afklaret adelsnavn med samme værdi, røres ikke; en ANDEN afklaret værdi
-- (fx en senere redaktionel rettelse) stopper skriptet i stedet for at blive overskrevet.
-- Ændringssæt: begge kald lander i ét ændringssæt (begin_change_set genbruger transaktionens sæt), mærket med den
-- første linje (IV). Fortrydelse af sættet fortryder begge fakta.
\set ON_ERROR_STOP on
\if :{?skriv}
\else
  \set skriv false
\endif
\if :{?redaktoer_uid}
\else
  \echo 'ADELSNAVN_FEJL: angiv -v redaktoer_uid=<uuid>'
  SELECT 1/0 AS mangler_redaktoer_uid;
\endif

BEGIN;
SELECT set_config('request.jwt.claim.sub', :'redaktoer_uid', true) IS NOT NULL AS aktoer_sat;

DO $aktoer$ BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'ADELSNAVN_FEJL: aktøren har ikke rollen redaktion (rolle: %)', current_rolle();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='adelsnavn') THEN
    RAISE EXCEPTION 'ADELSNAVN_FEJL: vocab (faktatype, adelsnavn) mangler — kør blokken adelsnavn-faktatype først';
  END IF;
END $aktoer$;

-- Linjerne fastlægges ved indhold (udgave + kode), aldrig ved id.
CREATE TEMP TABLE adelsnavn_maal ON COMMIT DROP AS
SELECT l.id AS lineage_id, v.kode, v.vaerdi, v.kilde
FROM lineage l
JOIN source s ON s.id = l.source_id
JOIN (VALUES
  ('IV', 'de Reventlou',
   'DAA 2018-20, s. 164 (IV, nr. 1): »1767 (14. dec.) ophøjet i lensgrevelig stand med navnet de Reventlou«; '
   'linjens personer skrives i bogen »… greve/lensgreve de Reventlou«.'),
  ('V', 'af Reventlow',
   'DAA 2018-20, s. 202 (V, nr. 1): »fik 1692 (8. nov.) bevilling på, at alle hans sønner og descendenter på '
   'sværdsiden er grever med navnet af Reventlow«. Stifteren selv blev 1673 ophøjet »med navnet de Reventlow« (s. 201).')
) AS v(kode, vaerdi, kilde) ON v.kode = l.kode
WHERE s.udgave = 'DAA 2018-20';

DO $maal$ BEGIN
  IF (SELECT count(*) FROM adelsnavn_maal) <> 2 THEN
    RAISE EXCEPTION 'ADELSNAVN_FEJL: forventede præcis 2 linjer (DAA 2018-20 IV og V), fandt %', (SELECT count(*) FROM adelsnavn_maal);
  END IF;
END $maal$;

DO $skriv$
DECLARE m record; v_har boolean; v_anden text;
BEGIN
  FOR m IN SELECT * FROM adelsnavn_maal ORDER BY kode LOOP
    SELECT string_agg(DISTINCT btrim(a.vaerdi_tekst), ' | ') INTO v_anden
    FROM fact f
    JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id AND c.status = 'afklaret'
    JOIN assertion a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type = 'lineage' AND f.subjekt_id = m.lineage_id AND f.faktatype = 'adelsnavn'
      AND btrim(a.vaerdi_tekst) IS DISTINCT FROM m.vaerdi;
    IF v_anden IS NOT NULL THEN
      RAISE EXCEPTION 'ADELSNAVN_FEJL: % har allerede en anden afklaret adelsnavn (»%«) — overskrives ikke', m.kode, v_anden;
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM fact f
      JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id AND c.status = 'afklaret'
      JOIN assertion a ON a.id = c.valgt_assertion_id
      WHERE f.subjekt_type = 'lineage' AND f.subjekt_id = m.lineage_id AND f.faktatype = 'adelsnavn'
        AND btrim(a.vaerdi_tekst) = m.vaerdi
    ) INTO v_har;
    IF v_har THEN
      RAISE NOTICE 'ADELSNAVN_UAENDRET: % allerede »%«', m.kode, m.vaerdi;
    ELSE
      PERFORM red_upsert_fakta('lineage', m.lineage_id, 'adelsnavn', m.vaerdi, p_kilde_fritekst => m.kilde);
      RAISE NOTICE 'ADELSNAVN_SKREVET: % »%«', m.kode, m.vaerdi;
    END IF;
  END LOOP;
END $skriv$;

-- Kontrol: præcis én afklaret værdi pr. linje, og den er den forventede.
SELECT m.kode, a.vaerdi_tekst AS afklaret, c.status, ci.citat_tekst
FROM adelsnavn_maal m
JOIN fact f ON f.subjekt_type = 'lineage' AND f.subjekt_id = m.lineage_id AND f.faktatype = 'adelsnavn'
JOIN conclusion c ON c.target_type = 'fact' AND c.target_id = f.id
JOIN assertion a ON a.id = c.valgt_assertion_id
LEFT JOIN citation ci ON ci.assertion_id = a.id
ORDER BY m.kode;

DO $kontrol$ BEGIN
  IF (SELECT count(*) FROM adelsnavn_maal m
        JOIN fact f ON f.subjekt_type='lineage' AND f.subjekt_id=m.lineage_id AND f.faktatype='adelsnavn'
        JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
        JOIN assertion a ON a.id=c.valgt_assertion_id AND btrim(a.vaerdi_tekst)=m.vaerdi) <> 2 THEN
    RAISE EXCEPTION 'ADELSNAVN_FEJL: kontrollen fandt ikke begge afklarede værdier';
  END IF;
  RAISE NOTICE 'ADELSNAVN_OK: IV og V har hver én afklaret adelsnavn';
END $kontrol$;

\if :skriv
COMMIT;
\echo 'ADELSNAVN: COMMIT'
\else
ROLLBACK;
\echo 'ADELSNAVN: ROLLBACK (prøve — kør med -v skriv=1 for at skrive)'
\endif
