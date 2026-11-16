-- person-purge-rest.sql — uafhængig restsøgning efter en slettet person. Læser IKKE sletningens inventar:
-- tabellisten kommer fra pg_class (schema public og private), og hver tabel scannes som row::text.
-- Kun tal og tabelnavne printes, aldrig rækkeindhold. Kører i BEGIN TRANSACTION READ ONLY
-- (kun TEMP-tabeller oprettes, og de forsvinder ved ROLLBACK).
--
-- Tre tegn tælles pr. tabel:
--   tok   : P's id som helt tal-token. Grænsetegn afhænger af mode (R10/R12):
--           mode=prod    : hverken foran eller efter ciffer, bogstav, _, ., : eller - (så tidsstempler,
--                          uuid-segmenter og [[person:<pid>| ikke rammes) — streng regex, uændret.
--           mode=fixture : som prod, men : og - ER grænsetegn (så feed-pin-nøgler som portrait:<pid> og
--                          paadennedag:<pid>:født:<år> ses). Sikkert, fordi fixture-id'er er > 1.000.000 og derfor
--                          ikke kan ramle ind i dato- eller uuid-segmenter (Task 2a sætter sekvensen højt).
--           Et afsluttende punktum tæller i begge, når intet ciffer følger.
--   navn  : P's navn som delstreng (springes over, hvis navnet er tomt)
--   link  : delstrengen '[[person:<pid>|'
--
-- Variabler:
--   -v pid=123            (påkrævet)
--   -v navn='…'           (fixture: påkrævet. prod/foer: udledes af person.visning_navn, hvis udeladt.
--                          prod/efter: påkrævet, personen findes ikke længere.)
--   -v mode=fixture|prod  (default fixture)
--   -v fase=foer|efter    (kun prod; default foer)
--   -v foerfil=<sti>      (kun prod; foer SKRIVER filen, efter LÆSER den. Filen indeholder kun tabelnavne og tal
--                          plus et navnets længde, så efter kan se, at navnet ligner det samme.)
--   -v planfil=<sti>      (kun prod/efter, valgfri; linjer 'tabel|forventet_fald_i_tok'. Mangler den, springes
--                          plan-sammenligningen over, og det siges højt — det er ikke en bestået kontrol.)
--
-- Eksempler:
--   psql "$DB" -X -v pid=123 -v navn='Testperson Purge' -f tests/sql/person-purge-rest.sql
--   psql "$DB" -X -v pid=1791 -v mode=prod -v fase=foer  -v foerfil=/sti/foer.txt -f tests/sql/person-purge-rest.sql
--   psql "$DB" -X -v pid=1791 -v mode=prod -v fase=efter -v foerfil=/sti/foer.txt -v navn='…' -f …
-- Exit-kode != 0 (ON_ERROR_STOP), når kontrollen fejler; stderr siger hvorfor.
\set ON_ERROR_STOP on
\set QUIET on
\set VERBOSITY terse
\set SHOW_CONTEXT never
\if :{?mode}
\else
  \set mode fixture
\endif
\if :{?fase}
\else
  \set fase foer
\endif
\if :{?navn}
\else
  \set navn ''
\endif
\if :{?foerfil}
\else
  \set foerfil ''
\endif
\if :{?planfil}
\else
  \set planfil ''
\endif
SELECT (:'mode' = 'prod') AS is_prod, (CASE WHEN :'mode' = 'prod' THEN '0-9A-Za-z_.:-' ELSE '0-9A-Za-z_.' END) AS bnd, (:'fase' = 'efter') AS is_efter, (:'planfil' <> '') AS har_plan \gset
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'

-- CREATE (også CREATE TEMP TABLE ... AS) er forbudt i en read-only-transaktion. Derfor oprettes de tomme
-- TEMP-arbejdstabeller først, og transaktionen gøres READ ONLY, før nogen forespørgsel eller INSERT kører.
-- Efter SET TRANSACTION READ ONLY kan kun TEMP-tabeller skrives; alt i public/private er skrivebeskyttet.
BEGIN;
CREATE TEMP TABLE params (pid bigint, navn text) ON COMMIT DROP;
CREATE TEMP TABLE maaling (tabel text, tok bigint, navn bigint, link bigint) ON COMMIT DROP;
CREATE TEMP TABLE tilladt (tabel_like text, sted text, tok_art text, tekst_art text, begrundelse text) ON COMMIT DROP;
CREATE TEMP TABLE vurdering (tabel text, tok bigint, navn bigint, link bigint, sted text, tok_art text, tekst_art text) ON COMMIT DROP;
CREATE TEMP TABLE foer_raw (tabel text, tok text, navn text, link text) ON COMMIT DROP;
CREATE TEMP TABLE plan (tabel text, fald bigint) ON COMMIT DROP;
CREATE TEMP TABLE sammenlign (tabel text, sted text, tekst_art text, foer_tok bigint, efter_tok bigint,
  foer_navn bigint, efter_navn bigint, foer_link bigint, efter_link bigint, plan_fald bigint) ON COMMIT DROP;
SET TRANSACTION READ ONLY;

INSERT INTO params
SELECT (:pid)::bigint AS pid,
       coalesce(nullif(:'navn', ''), (SELECT visning_navn FROM public.person WHERE id = (:pid)::bigint), '') AS navn;

-- ---------- måling: alle tabeller i public og private ----------
INSERT INTO maaling
SELECT t.tabel, x.tok, x.navn, x.link
  FROM (SELECT n.nspname || '.' || c.relname AS tabel, n.nspname, c.relname
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('public', 'private') AND c.relkind IN ('r', 'p') AND NOT c.relispartition) t
 CROSS JOIN params p
 CROSS JOIN LATERAL (
   SELECT (xpath('/row/tok/text()',  q))[1]::text::bigint AS tok,
          (xpath('/row/navn/text()', q))[1]::text::bigint AS navn,
          (xpath('/row/link/text()', q))[1]::text::bigint AS link
     FROM (SELECT query_to_xml(format(
            $q$SELECT count(*) FILTER (WHERE t::text ~ %L) AS tok,
                      count(*) FILTER (WHERE (SELECT navn FROM pg_temp.params) <> ''
                                         AND strpos(t::text, (SELECT navn FROM pg_temp.params)) > 0) AS navn,
                      count(*) FILTER (WHERE strpos(t::text, %L) > 0) AS link
                 FROM %I.%I t$q$,
            '(^|[^' || :'bnd' || '])' || p.pid::text || '(\.(?![0-9])|[^' || :'bnd' || ']|$)',
            '[[person:' || p.pid::text || '|',
            t.nspname, t.relname), false, true, '') AS q) s) x;

-- ---------- tilladt rest (Global Constraints »Tilladt rest«) ----------
-- tok : 'ja' = P's id-nummer må stå i andres rækker.  tekst: 'ja' = bogtekst med navn/link må stå;
-- 'q9' = kun hvis rækken stod i forhåndsvisningens til_kontrol (kan denne måler ikke afgøre; tallet rapporteres
-- særskilt, og testen skal afstemme det mod til_kontrol); 'nej' = aldrig.
INSERT INTO tilladt
SELECT * FROM (VALUES
  -- P's id-nummer i andres rækker (Global Constraints: S11c, S23b, S32c, S41b, S43b, S45b, S46, S48, S49c, S50, NY-C, S57, S52b, S39c)
  ('private.source_persona_identity_event',      'S11c',       'ja', 'q9', 'andres identitetsevents: P-id i evidence; noter i Y-events er Q9'),
  ('private.narrative_publication_event',        'S23b/K2',    'ja', 'ja', 'andres publiceringshistorik: P i state; navn er bogtekst (K2/Q2)'),
  ('private.narrative_legacy_publication',       'S23b/K2',    'ja', 'ja', 'andres narrativ-baseline: P i state; navn er bogtekst (K2/Q2)'),
  ('public.feed_pin',                            'S32c',       'ja', 'nej','forbundet:<bevaret familie>'),
  ('private.reimport_event',                     'S41b',       'ja', 'nej','aktiverings-kvitteringer og same_as_hint med P-id'),
  ('private.reimport_case_event',                'S43b',       'ja', 'nej','identity_different-par med P-id'),
  ('private.identity_control_parent_card',       'S45b',       'ja', 'nej','partner_ids med P'),
  ('private.identity_control_sample',            'S46/bog',    'ja', 'ja', 'bogens lag (kandidat-uuid, intet P-id)'),
  ('private.relation_classification_event',      'S48/S58',    'ja', 'q9', 'S48: hash over familierækker; S58: evidence er Q9'),
  ('private.interpretation_promotion',           'S39c/S58',   'ja', 'q9', 'S39c: andres bindinger (id/hash); S58: evidence er Q9'),
  ('private.marriage_ordinal_correction',        'S49c',       'ja', 'q9', 'familie-id; evidence er Q9'),
  ('private.narrative_record_cutover_receipt',   'S50/bog',    'ja', 'ja', 'bogens lag'),
  ('private.identity_control_exclusion',         'NY-C/bog',   'ja', 'ja', 'bogens lag'),
  ('public.change_event',                        'S57/K2',     'ja', 'ja', 'andres events; andres narrativ-/notehistorik med P-link er bogtekst (K2/Q2)'),
  ('public.change_set',                          'S52b',       'ja', 'nej','sæt med subjekt P, som stadig har andres events (id)'),
  -- Bogtekst med navn, men INGEN id-tilladelse
  ('private.reimport_authorization',             'S44a/Q1',    'nej','ja', 'authorized_elements er bogtekst og kopi af bogens lag'),
  -- Fritekst på Q9-stederne: kun navn/link, og kun når til_kontrol har rækken; ingen id-tilladelse
  ('private.identity_control_parent_event',      'S45b/Q9',    'nej','q9', 'parent_event.note er fritekst'),
  ('private.reimport_case_authorization',        'S44b/Q9',    'nej','q9', 'C3-elementer; fritekst'),
  ('public.suggestion',                          'S34b/Q9',    'nej','q9', 'andres forslag: token blokerer, øvrig fritekst er Q9'),
  ('public.media',                               'S37b/K3/Q9', 'nej','q9', 'delt medies titel'),
  ('public.fact',                                'K5/S38b/Q9', 'nej','q9', 'vielsesfakta i bevarede familier (beslutning 7)'),
  ('public.assertion',                           'K5/S38b/Q9', 'nej','q9', 'vielsens vaerdi_tekst i bevarede familier'),
  ('public.citation',                            'K5/S38b/Q9', 'nej','q9', 'vielsens citat_tekst i bevarede familier'),
  ('private.relation_reopen',                    'S58/Q9',     'nej','q9', 'context er fritekst'),
  ('private.text_revision_reconciliation',       'S58/Q9',     'nej','q9', 'context er fritekst'),
  ('private.legacy_placement_disposition',       'S58/Q9',     'nej','q9', 'evidence er fritekst'),
  ('private.source_persona_identity_candidate',  'S58/Q9',     'nej','q9', 'basis er fritekst'),
  -- Bogens lag slettes aldrig (Global Constraints) og dens underordnede tabeller (afstemt mod pg_class på stand-in)
  ('private.source_record%',                     'bog',        'ja', 'ja', 'source_record, _occurrence, _anchor_event, _revision_event, _placement, _placement_decision'),
  ('private.source_observation%',                'bog',        'ja', 'ja', 'source_observation, _text'),
  ('private.source_mention',                     'bog',        'ja', 'ja', 'bogens lag'),
  ('private.source_rendition',                   'bog',        'ja', 'ja', 'bogens lag'),
  ('private.extraction_run',                     'bog',        'ja', 'ja', 'bogens lag'),
  ('private.source_persona',                     'bog',        'ja', 'ja', 'bogens lag'),
  ('private.source_persona_mention',             'bog',        'ja', 'ja', 'bogens lag'),
  ('private.source_persona_placement%',          'bog',        'ja', 'ja', 'source_persona_placement, _decision'),
  ('private.identity_control_run',               'bog',        'ja', 'ja', 'bogens lag'),
  ('private.identity_control_event',             'bog',        'ja', 'ja', 'bogens lag'),
  ('private.interpretation',                     'bog',        'ja', 'ja', 'bogens lag'),
  ('private.interpretation_observation',         'bog',        'ja', 'ja', 'bogens lag'),
  ('private.interpretation_party',               'bog',        'ja', 'ja', 'bogens lag'),
  ('private.interpretation_predicate',           'bog',        'ja', 'ja', 'underordnet fortolkningstabel'),
  ('private.reimport_writer_profile',            'bog',        'ja', 'ja', 'bogens lag')
) v(tabel_like, sted, tok_art, tekst_art, begrundelse);

-- tabel -> mest specifikke (længste) tilladt-linje
INSERT INTO vurdering
SELECT m.tabel, m.tok, m.navn, m.link,
       coalesce(a.sted, '-') AS sted,
       coalesce(a.tok_art, 'nej') AS tok_art,
       coalesce(a.tekst_art, 'nej') AS tekst_art
  FROM maaling m
  LEFT JOIN LATERAL (SELECT t.* FROM tilladt t WHERE m.tabel LIKE t.tabel_like
                      ORDER BY length(t.tabel_like) DESC LIMIT 1) a ON true;

\if :is_prod
  -- ======================= mode=prod =======================
  \if :is_efter
    \echo '== person-purge-rest mode=prod fase=efter'
    SELECT (:'foerfil' <> '') AS har_foerfil \gset
    \if :har_foerfil
    \else
      \echo 'FEJL: -v foerfil=<sti> er påkrævet i fase=efter'
      SELECT 1/0;
    \endif
    \set cpy '\\copy foer_raw FROM ' :'foerfil' ' WITH (FORMAT csv, DELIMITER ''|'')'
    :cpy
    \if :har_plan
      \set cpy '\\copy plan FROM ' :'planfil' ' WITH (FORMAT csv, DELIMITER ''|'')'
      :cpy
    \endif
    -- konsistens: samme person, samme navn
    SELECT (SELECT count(*) FROM foer_raw WHERE tabel = '#pid' AND tok = (SELECT pid::text FROM params)) = 1 AS pid_ok,
           (SELECT navn = '' FROM params)
             OR (SELECT count(*) FROM foer_raw WHERE tabel = '#navnlaengde' AND tok = length((SELECT navn FROM params))::text) = 1 AS navn_ok,
           (SELECT navn = '' FROM params) AS navn_mangler
      \gset
    \if :pid_ok
    \else
      \echo 'FEJL: foer-filen er for en anden person'
      SELECT 1/0;
    \endif
    \if :navn_mangler
      \echo 'ADVARSEL: navn ikke angivet; navn-kontrollen er sprunget over'
    \else
      \if :navn_ok
      \else
        \echo 'FEJL: navnet matcher ikke foer-filens navn-længde'
        SELECT 1/0;
      \endif
    \endif

    INSERT INTO sammenlign
    SELECT v.tabel, v.sted, v.tekst_art,
           coalesce(f.tok::bigint, 0) AS foer_tok,  v.tok  AS efter_tok,
           coalesce(f.navn::bigint, 0) AS foer_navn, v.navn AS efter_navn,
           coalesce(f.link::bigint, 0) AS foer_link, v.link AS efter_link,
           coalesce(pl.fald, 0) AS plan_fald
      FROM vurdering v
      LEFT JOIN foer_raw f ON f.tabel = v.tabel
      LEFT JOIN plan pl ON pl.tabel = v.tabel;

    \echo '-- tabel|foer_tok|efter_tok|fald_tok|foer_navn|efter_navn|foer_link|efter_link|plan_fald|status (kun tabeller med nogen aendring eller rest)'
    SELECT tabel, foer_tok, efter_tok, foer_tok - efter_tok, foer_navn, efter_navn, foer_link, efter_link,
           CASE WHEN :'har_plan' = 't' THEN plan_fald::text ELSE '-' END,
           concat_ws(',',
             CASE WHEN efter_tok  > foer_tok  OR efter_navn > foer_navn OR efter_link > foer_link THEN 'STIGNING' END,
             CASE WHEN :'har_plan' = 't' AND (foer_tok - efter_tok) <> plan_fald THEN 'AFVIGER_PLAN' END,
             CASE WHEN (efter_navn > 0 OR efter_link > 0) AND tekst_art = 'nej' THEN 'REST_PAA_UTILLADT_STED' END,
             CASE WHEN (efter_navn > 0 OR efter_link > 0) AND tekst_art = 'q9'  THEN 'Q9_AFSTEM_MOD_TIL_KONTROL' END)
      FROM sammenlign
     WHERE foer_tok <> efter_tok OR foer_navn <> efter_navn OR foer_link <> efter_link OR efter_navn > 0 OR efter_link > 0 OR plan_fald <> 0
     ORDER BY tabel;
    \if :har_plan
    \else
      \echo 'plan-sammenligning sprunget over: ingen planfil (dette er IKKE en bestået plankontrol)'
    \endif
    SELECT count(*) FILTER (WHERE efter_tok > foer_tok OR efter_navn > foer_navn OR efter_link > foer_link) AS stigning,
           count(*) FILTER (WHERE :'har_plan' = 't' AND (foer_tok - efter_tok) <> plan_fald) AS afviger_plan,
           count(*) FILTER (WHERE (efter_navn > 0 OR efter_link > 0) AND tekst_art = 'nej') AS udtilladt,
           coalesce(sum(efter_navn + efter_link) FILTER (WHERE tekst_art = 'q9'), 0) AS q9_rest
      FROM sammenlign \gset
    \echo '== sammenfatning: stigning=' :stigning ' afviger_plan=' :afviger_plan ' udtilladt_navn_link=' :udtilladt ' q9_rest=' :q9_rest
    SELECT (:stigning + :afviger_plan + :udtilladt = 0) AS alt_ok \gset
    \if :alt_ok
      \echo 'REST_OK (q9_rest skal afstemmes mod til_kontrol af kalderen)'
    \else
      \echo 'REST_FEJL'
      SELECT 1/0;
    \endif
  \else
    \echo '== person-purge-rest mode=prod fase=foer: skriver foer-tal'
    SELECT (:'foerfil' <> '') AS har_foerfil \gset
    \if :har_foerfil
    \else
      \echo 'FEJL: -v foerfil=<sti> er påkrævet i fase=foer'
      SELECT 1/0;
    \endif
    \o :foerfil
    SELECT '#pid', pid::text, '', '' FROM params
    UNION ALL SELECT '#navnlaengde', length(navn)::text, '', '' FROM params
    UNION ALL SELECT tabel, tok::text, navn::text, link::text FROM maaling ORDER BY 1;
    \o
    \echo '-- tabel|tok|navn|link (kun tabeller med nogen forekomst; fuld liste i foer-filen)'
    SELECT tabel, tok, navn, link FROM maaling WHERE tok + navn + link > 0 ORDER BY tabel;
    SELECT count(*) AS antal_tabeller, count(*) FILTER (WHERE tok + navn + link > 0) AS med_forekomst,
           coalesce(sum(tok), 0) AS sum_tok, coalesce(sum(navn), 0) AS sum_navn, coalesce(sum(link), 0) AS sum_link
      FROM maaling \gset
    \echo '== foer: tabeller=' :antal_tabeller ' med_forekomst=' :med_forekomst ' sum_tok=' :sum_tok ' sum_navn=' :sum_navn ' sum_link=' :sum_link
  \endif
\else
  -- ======================= mode=fixture =======================
  \echo '== person-purge-rest mode=fixture'
  SELECT (navn = '') AS navn_mangler FROM params \gset
  \if :navn_mangler
    \echo 'FEJL: -v navn er påkrævet i mode=fixture'
    SELECT 1/0;
  \endif
  \echo '-- tabel|tok|navn|link|tilladt_tok|tilladt_tekst|sted (kun tabeller med forekomst)'
  SELECT tabel, tok, navn, link, tok_art, tekst_art, sted FROM vurdering WHERE tok + navn + link > 0 ORDER BY tabel;
  SELECT count(*) FILTER (WHERE (tok > 0 AND tok_art = 'nej')
                             OR ((navn > 0 OR link > 0) AND tekst_art = 'nej')) AS fejl,
         coalesce(sum(navn + link) FILTER (WHERE tekst_art = 'q9'), 0) AS q9_rest
    FROM vurdering \gset
  \echo '== sammenfatning: fejl=' :fejl ' q9_rest=' :q9_rest
  SELECT (:fejl > 0) AS har_fejl \gset
  \if :har_fejl
    \echo 'REST_FEJL: rest på utilladte steder (tabeller med tilladt=nej ovenfor)'
    SELECT 1/0;
  \else
    \echo 'REST_OK (q9_rest skal afstemmes mod til_kontrol af kalderen)'
  \endif
\endif
ROLLBACK;
