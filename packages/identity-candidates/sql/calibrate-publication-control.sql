-- Trin 6b (spec §4.3 pkt. 7, plan Task 10): kalibrering af publiceringskontrollens controlMargin mod en kildes kendte
-- identiteter. Læse-kun mod en stand-in, hvor kandidatkørslerne allerede er registreret. Udskriver KUN antal pr.
-- gitterværdi: ingen navne, ingen id'er, ingen rækkeindhold.
--
-- Brug: psql -X -d <stand-in> -v source_id=1 -v input_sha256=<hovedinputtets hash> -f calibrate-publication-control.sql
--
-- Facit: accepterede identiteter for kilden med evidence.authority='person_external_id' (149b's faste kobling; for
-- kilde 1 de 587 kendte). Facits klynge = facit plus alle personer, der via samme_som (begge retninger, transitivt)
-- hænger sammen med facit.
-- Hovedkørsler: kildens kørsler med input_sha256 = :input_sha256 og et controlMargin i config (én pr. gitterværdi).
-- Negativkontrolkørsler: kildens øvrige kørsler med samme input_spec, generator_version og controlMargin, men en anden
-- input_sha256 (en kopi af inputtet med syntetiske samme_som-par mellem en forkert bindingsperson og facit).
--
-- Pr. gitterværdi (controlMargin):
--   rigtige                 antal personas, hvor publication_control_outcome(persona, hovedkørsel, facit) = enig;
--   facit_udfald            udfaldsfordelingen for facit som bindingsperson (svag også fordelt på grund);
--   kf_par / forkerte       kontrafaktisk: hver anden person i personaens kandidatrækker (member_scores, top-K) uden for
--                           facits klynge som bindingsperson; forkerte = antal (persona, person)-par med enig,
--                           forkerte_personas = antal personas med mindst ét sådant par; kf_fordeling = parrenes udfald;
--   neg_par / neg_forkerte  samme par klassificeret i den negativkontrolkørsel, hvor parret er lagt i samme klynge
--                           (en række for personaen rummer både den forkerte person og facit); par, hvor facit ikke er
--                           blandt personaens scorede personer i nogen negativkørsel, tælles i neg_uberoert;
--                           neg_par_flere_koersler = par prøvet i mere end én negativkørsel (samme klyngesammenlægning
--                           via en anden partner); neg_klynge_rang1_auto = par, hvor klyngerækken er rang 1 med tier auto.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
WITH RECURSIVE
truth AS (
  SELECT i.source_persona_id AS pid, i.canonical_person_id AS facit
    FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE p.source_id=:source_id AND i.decision_status='accepted' AND i.evidence->>'authority'='person_external_id'),
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
  SELECT r.id, (r.config->>'controlMargin')::numeric AS cm, r.input_spec, r.generator_version
    FROM private.source_persona_identity_candidate_run r
   WHERE r.source_id=:source_id AND r.input_sha256=:'input_sha256' AND jsonb_typeof(r.config->'controlMargin')='number'),
neg AS (
  SELECT r.id, h.cm
    FROM private.source_persona_identity_candidate_run r
    JOIN hoved h ON h.cm=(r.config->>'controlMargin')::numeric AND h.input_spec=r.input_spec
                AND h.generator_version=r.generator_version
   WHERE r.source_id=:source_id AND r.input_sha256<>:'input_sha256' AND jsonb_typeof(r.config->'controlMargin')='number'),
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
