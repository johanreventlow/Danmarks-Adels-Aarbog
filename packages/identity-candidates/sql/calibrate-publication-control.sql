-- Trin 6b (spec §4.3 pkt. 7, plan Task 10/15): kalibrering af publiceringskontrollens controlMargin mod en kildes kendte
-- svar. Læse-kun mod en stand-in, hvor kandidatkørslerne allerede er registreret. Udskriver KUN antal pr. gitterværdi:
-- ingen navne, ingen id'er, intet rækkeindhold.
--
-- KUN TIL EN DEDIKERET KALIBRERINGSBASE: alle kildens øvrige kørsler med samme input_spec, generator_version og config
-- som en hovedkørsel tælles og klassificeres som negativkontrolkørsler. Hele kæden køres af
-- scripts/calibrate-publication-control.sh.
--
-- Brug: psql -X -d <base> -v source_id=<n> -v input_sha256=<hovedinputtets hash> [-v facit=…] -f calibrate-publication-control.sql
--
-- Facit (-v facit, standard authority:person_external_id; samme definition som export-calibration-truth.sql):
--   authority:<a>  accepterede identiteter for kilden med evidence.authority = <a> (for kilde 1 de 587 kendte);
--   binding        bindingens person for kildens personas med publiceret narrativbinding, undtagen staged.
-- Facits klynge = facit plus alle personer, der via samme_som (begge retninger, transitivt) hænger sammen med facit.
-- Hovedkørsler: kildens kørsler med input_sha256 = :input_sha256 og et controlMargin i config; præcis én pr. værdi
-- (ellers CALIBRATION_MAIN_RUN_DUPLICATE; ingen → CALIBRATION_MAIN_RUN_MISSING).
-- Negativkontrolkørsler: kildens øvrige kørsler med samme input_spec, generator_version og config (dermed samme
-- controlMargin) som en hovedkørsel, men en anden input_sha256: kopier af inputtet med syntetiske samme_som-par mellem
-- en forkert bindingsperson og facit (calibration-negative-pairs.sql, calibration-cli.ts split).
--
-- Fail-closed: facit_udfald kalder klassifikatoren for hver facit-persona i hver hovedkørsel; en kandidatrække uden
-- gyldige member_scores eller en config uden controlMargin/autoCutoff/topK ≥ 2 kaster PUBLICATION_CONTROL_CONFIG_MISSING,
-- så scriptet afbrydes i stedet for at tælle for lavt (kf ville ellers lydløst få 0 rækker for en defekt række).
--
-- Pr. gitterværdi (controlMargin):
--   rigtige                 antal personas, hvor publication_control_outcome(persona, hovedkørsel, facit) = enig;
--   facit_udfald            udfaldsfordelingen for facit som bindingsperson (svag også fordelt på grund);
--   kf_par / forkerte       kontrafaktisk: hvert klyngemedlem i member_scores i personaens kandidatrækker (top-K) uden
--                           for facits klynge, sat som bindingsperson; forkerte = antal (persona, person)-par med enig,
--                           forkerte_personas = antal personas med mindst ét sådant par; kf_fordeling = parrenes udfald;
--   neg_par / neg_forkerte  samme par klassificeret i den negativkontrolkørsel, hvor parret er lagt i samme klynge
--                           (en række for personaen rummer både den forkerte person og facit); par, hvor facit ikke er
--                           blandt personaens scorede personer i nogen negativkørsel, tælles i neg_uberoert;
--                           neg_par_flere_koersler = par prøvet i mere end én negativkørsel (samme klyngesammenlægning
--                           via en anden partner); neg_klynge_rang1_auto = par, hvor klyngerækken er rang 1 med
--                           generatorens tier auto (dvs. ville bestå en kontrol på klyngens sammenfoldede score ved en
--                           margin ≤ ambiguityMargin).
\set ON_ERROR_STOP on
\if :{?facit}
\else
  \set facit 'authority:person_external_id'
\endif
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('cal.facit', :'facit', true), set_config('cal.source', :'source_id', true),
       set_config('cal.input_sha256', :'input_sha256', true) \g /dev/null
DO $$ BEGIN
  IF current_setting('cal.facit') !~ '^(authority:[a-z_]+|binding)$' THEN RAISE EXCEPTION 'CALIBRATION_FACIT_INVALID'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity_candidate_run r
                  WHERE r.source_id=current_setting('cal.source')::bigint AND r.input_sha256=current_setting('cal.input_sha256')
                    AND jsonb_typeof(r.config->'controlMargin')='number') THEN
    RAISE EXCEPTION 'CALIBRATION_MAIN_RUN_MISSING';
  END IF;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity_candidate_run r
              WHERE r.source_id=current_setting('cal.source')::bigint AND r.input_sha256=current_setting('cal.input_sha256')
                AND jsonb_typeof(r.config->'controlMargin')='number'
              GROUP BY (r.config->>'controlMargin')::numeric HAVING count(*)>1) THEN
    RAISE EXCEPTION 'CALIBRATION_MAIN_RUN_DUPLICATE';
  END IF;
END $$;
WITH RECURSIVE
truth AS (
  SELECT i.source_persona_id AS pid, i.canonical_person_id AS facit
    FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE :'facit' LIKE 'authority:%' AND p.source_id=:source_id AND i.decision_status='accepted'
     AND i.canonical_person_id IS NOT NULL AND i.evidence->>'authority'=substr(:'facit',11)
  UNION ALL
  SELECT p.id, b.person_id
    FROM private.source_persona p CROSS JOIN LATERAL private.publication_persona_binding(p.id) b
    JOIN public.person q ON q.id=b.person_id
   WHERE :'facit'='binding' AND p.source_id=:source_id AND b.binding_status='published' AND NOT coalesce(q.staged,false)),
edge AS (
  SELECT r.subjekt_id AS a, r.objekt_id AS b FROM public.relation r
   WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
  UNION
  SELECT r.objekt_id, r.subjekt_id FROM public.relation r
   WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'),
klynge(facit, person) AS (
  SELECT DISTINCT t.facit, t.facit FROM truth t
  UNION
  SELECT k.facit, e.b FROM klynge k JOIN edge e ON e.a=k.person),
hoved AS (
  SELECT r.id, (r.config->>'controlMargin')::numeric AS cm, r.input_spec, r.generator_version, r.config
    FROM private.source_persona_identity_candidate_run r
   WHERE r.source_id=:source_id AND r.input_sha256=:'input_sha256' AND jsonb_typeof(r.config->'controlMargin')='number'),
neg AS (
  SELECT r.id, h.cm
    FROM private.source_persona_identity_candidate_run r
    JOIN hoved h ON h.config=r.config AND h.input_spec=r.input_spec AND h.generator_version=r.generator_version
   WHERE r.source_id=:source_id AND r.input_sha256<>:'input_sha256'),
facit_udfald AS (
  SELECT h.cm, private.publication_control_outcome(t.pid,h.id,t.facit) AS o
    FROM hoved h CROSS JOIN truth t
   WHERE EXISTS (SELECT 1 FROM jsonb_array_elements_text(h.input_spec->'persona_ids') x WHERE x=t.pid::text)),
kf AS (
  SELECT DISTINCT h.cm, h.id AS run_id, t.pid, t.facit, (e->>'person_id')::bigint AS w
    FROM hoved h JOIN private.source_persona_identity_candidate c ON c.run_id=h.id
    JOIN truth t ON t.pid=c.source_persona_id
    CROSS JOIN LATERAL jsonb_array_elements(c.basis->'member_scores') e
   WHERE NOT EXISTS (SELECT 1 FROM klynge k WHERE k.facit=t.facit AND k.person=(e->>'person_id')::bigint)),
kf_udfald AS (
  SELECT kf.cm, kf.pid, kf.w, o->>'outcome' AS outcome, o->>'outcome'||coalesce(':'||(o->>'reason'),'') AS udfald
    FROM kf CROSS JOIN LATERAL private.publication_control_outcome(kf.pid,kf.run_id,kf.w) o),
neg_match AS (
  SELECT kf.cm, kf.pid, kf.w, n.id AS run_id
    FROM kf JOIN neg n ON n.cm=kf.cm
   WHERE EXISTS (SELECT 1 FROM private.source_persona_identity_candidate c
                  WHERE c.run_id=n.id AND c.source_persona_id=kf.pid
                    AND c.basis->'member_scores' @> jsonb_build_array(jsonb_build_object('person_id',kf.w))
                    AND c.basis->'member_scores' @> jsonb_build_array(jsonb_build_object('person_id',kf.facit)))),
-- Negativkontrollens skarphed: par, hvor den sammenfoldede klyngerække (forkert person + facit) står som rang 1 med
-- generatorens tier auto; en kontrol på klyngens score ville have godtaget den forkerte binding her.
neg_klynge_auto AS (
  SELECT DISTINCT m.cm, m.pid, m.w
    FROM neg_match m JOIN kf ON kf.cm=m.cm AND kf.pid=m.pid AND kf.w=m.w
    JOIN private.source_persona_identity_candidate c ON c.run_id=m.run_id AND c.source_persona_id=m.pid
   WHERE c.rank=1 AND c.tier='auto'
     AND c.basis->'member_scores' @> jsonb_build_array(jsonb_build_object('person_id',m.w))
     AND c.basis->'member_scores' @> jsonb_build_array(jsonb_build_object('person_id',kf.facit))),
neg_udfald AS (
  SELECT m.cm, m.pid, m.w, bool_or(private.publication_control_outcome(m.pid,m.run_id,m.w)->>'outcome'='enig') AS enig,
         count(*) AS koersler
    FROM neg_match m GROUP BY m.cm, m.pid, m.w),
pr_cm AS (
  SELECT h.cm,
         (SELECT count(*) FROM facit_udfald f WHERE f.cm=h.cm) AS personas,
         (SELECT count(*) FROM facit_udfald f WHERE f.cm=h.cm AND f.o->>'outcome'='enig') AS rigtige,
         (SELECT jsonb_object_agg(x.k,x.n) FROM (SELECT f.o->>'outcome'||coalesce(':'||(f.o->>'reason'),'') AS k, count(*) AS n
                                                   FROM facit_udfald f WHERE f.cm=h.cm GROUP BY 1) x) AS facit_udfald,
         (SELECT count(*) FROM kf_udfald k WHERE k.cm=h.cm) AS kf_par,
         (SELECT count(*) FROM kf_udfald k WHERE k.cm=h.cm AND k.outcome='enig') AS forkerte,
         (SELECT count(DISTINCT k.pid) FROM kf_udfald k WHERE k.cm=h.cm AND k.outcome='enig') AS forkerte_personas,
         (SELECT jsonb_object_agg(x.udfald,x.n) FROM (SELECT k.udfald, count(*) AS n FROM kf_udfald k WHERE k.cm=h.cm
                                                         GROUP BY 1) x) AS kf_fordeling,
         (SELECT count(*) FROM neg n WHERE n.cm=h.cm) AS neg_koersler,
         (SELECT count(*) FROM neg_udfald u WHERE u.cm=h.cm) AS neg_par,
         (SELECT count(*) FROM neg_udfald u WHERE u.cm=h.cm AND u.enig) AS neg_forkerte,
         (SELECT count(*) FROM neg_udfald u WHERE u.cm=h.cm AND u.koersler>1) AS neg_par_flere_koersler,
         (SELECT count(*) FROM neg_klynge_auto a WHERE a.cm=h.cm) AS neg_klynge_rang1_auto,
         (SELECT count(*) FROM kf_udfald k WHERE k.cm=h.cm
             AND NOT EXISTS (SELECT 1 FROM neg_udfald u WHERE u.cm=k.cm AND u.pid=k.pid AND u.w=k.w)) AS neg_uberoert
    FROM hoved h)
SELECT cm, personas, rigtige, kf_par, forkerte, forkerte_personas, neg_koersler, neg_par, neg_forkerte,
       neg_par_flere_koersler, neg_klynge_rang1_auto, neg_uberoert, facit_udfald, kf_fordeling
  FROM pr_cm ORDER BY cm;
COMMIT;
