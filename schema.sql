-- =====================================================================
--  Datamodel — konkret skema (PoC: Reventlow / DAA-følgesvend)
--  Mål: PostgreSQL/Supabase og DuckDB (standard SQL).  Evidensbaseret kerne + generisk relation.
--
--  Konventioner:
--   * Surrogat-PK (BIGINT). Bogens (linje, nr.) lever i person_external_id.
--   * Fuzzy dato = (date_min, date_max) interval + kvalifikator + rå tekst.
--       exact:      min = max
--       før/efter:  kun max / kun min sat
--       interval:   min < max ("1353/1356")
--       floruit:    dokumenteret-aktiv span, distinkt fra levetid
--       åben:       max IS NULL (igangværende / til død)
--   * Polymorfe referencer = (type, id)-par (ingen hård FK), så samme
--     mekanisme kan pege på enhver entitet.
-- =====================================================================

-- ---------- KONTROLLERET VOKABULAR ----------
CREATE TABLE vocab (              -- roller, faktatyper, dekorationer, forkortelser
  scheme TEXT NOT NULL,           -- 'rolle' | 'faktatype' | 'dekoration' | 'forkortelse'
  code   TEXT NOT NULL,
  label  TEXT NOT NULL,
  PRIMARY KEY (scheme, code)
);

-- ---------- KILDE-/EVIDENS-INFRASTRUKTUR ----------
CREATE TABLE repository (
  id      BIGINT PRIMARY KEY,
  navn    TEXT NOT NULL,
  adresse TEXT                    -- fysisk placering af arkivet (TNG: tng_addresses)
);

CREATE TABLE source (             -- = kilde/værk; også DAA-udgaver og eksterne værker
  id            BIGINT PRIMARY KEY,
  slags         TEXT,             -- 'kirkebog','DAA-udgave','diplomsamling','bog','artikel','segl'
  titel         TEXT,
  udgave        TEXT,             -- fx 'DAA 2018-20', 'DAA 1982-84'
  aar           SMALLINT,         -- udgave-kronologi (struktureret; udgave-fritekst er upålidelig til sortering)
  ekstern       BOOLEAN DEFAULT FALSE,   -- eksternt referenceværk (Gotha, ES, DBL ...)
  import_key    TEXT,             -- stabil loader-identitet; NULL bevarer legacy-kilder uden importkontrakt
  repository_id BIGINT REFERENCES repository(id)
);
CREATE UNIQUE INDEX source_import_key_uidx ON source (import_key) WHERE import_key IS NOT NULL;

-- ---------- KONTEKST-ENTITETER ----------
CREATE TABLE place (
  id        BIGINT PRIMARY KEY,
  navn      TEXT,
  type      TEXT,                 -- 'sogn','herred','amt','kreds','land'
  parent_id BIGINT,               -- hierarki (self-ref, ingen hård FK)
  lat DOUBLE PRECISION, lon DOUBLE PRECISION
);

CREATE TABLE organisation (
  id    BIGINT PRIMARY KEY,
  navn  TEXT,
  slags TEXT                      -- 'amt','regiment','hof','institution','ridderorden'
);

CREATE TABLE estate (             -- EJENDOM: gods/len/stamhus/lensgrevskab
  id      BIGINT PRIMARY KEY,
  navn    TEXT,
  slags   TEXT,
  sted_id BIGINT REFERENCES place(id)
);

CREATE TABLE media (
  id       BIGINT PRIMARY KEY,
  slags    TEXT,                  -- 'foto','maleri','segl','scanning'
  titel    TEXT,
  kunstner TEXT,                  -- ekstern skaber (intern skaber = relation)
  datering TEXT,
  -- ---- fysisk byte-metadata (mediehåndtering 2026-07-04) ----
  -- Eneste legitime "fedning" af den ellers tynde tabel: bytes har intet andet hjem.
  -- Semantik (afbildet/ejer/placeret_på) forbliver relation; rettigheds-dokumentation forbliver fact.
  bucket           TEXT NOT NULL DEFAULT 'media',
  storage_path     TEXT,                          -- objekt-nøgle i bucket (= storage.objects.name)
  mime_type        TEXT,
  byte_size        BIGINT,
  bredde           INT,
  hoejde           INT,
  sha256           TEXT,                          -- hex; dedup + deterministisk sti
  original_filnavn TEXT,
  upload_status    TEXT NOT NULL DEFAULT 'kladde',-- 'kladde'|'klar'|'fejlet' (to-fase: række → bytes → 'klar')
  created_at timestamptz DEFAULT now(),   -- fase 3: aldersbegreb for strandede uploads (NULL = ukendt, præ-fase-3)
  -- ---- publikations-gating (rettigheder, fra dag 1) ----
  -- Kontrol-kolonne (som person.levende/privat) der driver RLS. FAIL-CLOSED: intet vises før frigivet.
  -- Uafhængig af GDPR-person-gating: et rettigheds-begrænset billede af en afdød forbliver skjult.
  maa_publiceres     BOOLEAN NOT NULL DEFAULT false,
  rettigheder_status TEXT NOT NULL DEFAULT 'ukendt' -- vocab 'media_rettigheder_status'
);
CREATE UNIQUE INDEX IF NOT EXISTS media_storage_path_uidx ON media (bucket, storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_sha256_uidx       ON media (sha256)               WHERE sha256 IS NOT NULL;

-- Klient-genkodede størrelsestrin (billedstørrelser/lightbox 2026-07-05, Slice B). KUN 'thumb' og
-- 'medium' — 'large' ER media-rækkens egen storage_path/mime_type/bredde/hoejde (ingen separat
-- original gemmes, jf. beslutning §6.4). Dette holder eksisterende rækker migrationsfri: de er
-- allerede deres egen 'large'-variant, de mangler blot thumb/medium-rækker (ingen backfill, §6.3).
-- IKKE i version_pk_registry — afledt cache, ligesom person.visning_* (B8-mønsteret), fortrydes
-- ikke separat; ON DELETE CASCADE så variant-rækker dør med deres media-forælder.
CREATE TABLE media_variant (
  id           BIGINT PRIMARY KEY,
  media_id     BIGINT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  tier         TEXT NOT NULL CHECK (tier IN ('thumb','medium')),
  storage_path TEXT NOT NULL,
  mime_type    TEXT,
  byte_size    BIGINT,
  bredde       INT,
  hoejde       INT
);
CREATE UNIQUE INDEX IF NOT EXISTS media_variant_media_tier_uidx    ON media_variant (media_id, tier);
CREATE UNIQUE INDEX IF NOT EXISTS media_variant_storage_path_uidx ON media_variant (storage_path);

CREATE TABLE historical_event (
  id   BIGINT PRIMARY KEY,
  navn TEXT
);

CREATE TABLE coat_of_arms (       -- VÅBEN
  id          BIGINT PRIMARY KEY,
  blasonering TEXT,               -- skjold / hjelmklæde / hjelmtegn
  note        TEXT
);

-- ---------- KERNE: PERSON & FAMILIE ----------
CREATE TABLE person (
  id            BIGINT PRIMARY KEY,
  levende       BOOLEAN DEFAULT FALSE,   -- GDPR: AFLEDT synlighed (levende vs. afdød)
  privat        BOOLEAN DEFAULT FALSE,   -- GDPR: MANUEL skjulning, uafhængig af levende (TNG: living vs. private)
  staged        BOOLEAN DEFAULT FALSE,   -- KURATERING (K2): ny udgaves poster skjult for anon indtil redaktør har matchet dem mod eksisterende udgaver (undgår dublette Conrad'er). Uafhængig af levende/privat. Loaderen sætter TRUE ved --staged; red_publicer_udgave rydder.
  status        TEXT,                    -- fx 'kendt hul / ikke undersøgt'
  koen          TEXT CHECK (koen IN ('mand','kvinde','ukendt')),  -- vocab 'koen'; NULL = ikke registreret. Arbejdsværdi; afledes af konklusion hvis omstridt.
  -- afledt visnings-cache (envejs-projektion af konklusioner; redigeres ALDRIG direkte):
  visning_navn       TEXT,
  visning_foedt      TEXT,
  visning_doed       TEXT,
  visning_titel      TEXT,
  visning_efternavn  TEXT,   -- afledt families-efternavn (linje-medlemskab); NULL = ikke afledt (udledt-slægtsnavn-design)
  visning_fuldt_navn TEXT    -- visning_navn (+ ' ' + visning_efternavn); envejs-cache som de øvrige visning_*
);

CREATE TABLE person_external_id (        -- bogens (linje, nr.) som eksternt ID
  person_id BIGINT REFERENCES person(id),
  source_id BIGINT REFERENCES source(id),
  linje     TEXT,                        -- 'I','V', ... — rå bog-token (proveniens); join til lineage.kode
  nr        INTEGER,
  record_key TEXT,                        -- stabil postidentitet fra en importartefakt (NULL for legacy)
  slaegtled_lokal  INTEGER,                -- slægtled lokalt i linjen (1,2,3… fra grenens start)
  slaegtled_gennem INTEGER,                -- gennemgående slægtled (parentes-tallet i bogen)
  kuld             TEXT,                    -- børne-gruppe-markør (romertal) inde i grenen; proveniens + gruppering
  PRIMARY KEY (person_id, source_id)
);
CREATE UNIQUE INDEX person_external_id_source_record_key_uidx
  ON person_external_id (source_id, record_key) WHERE record_key IS NOT NULL;

-- Importens varige beslutningsoversigt. Ingen FK til source/person/external-id:
-- de nøgler kan regenereres, mens (import_key, record_key) er artefaktens stabile identitet.
-- change_event er den uforanderlige historik; denne række er kun den aktuelle beslutning.
CREATE TABLE import_korrektion (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  import_key text NOT NULL,
  record_key text NOT NULL,
  felt text NOT NULL CHECK (felt IN ('navn','foedsel','doed','koen','post')),
  input_fingerprint text NOT NULL CHECK (input_fingerprint ~ '^[0-9a-f]{32}$'),
  importeret jsonb NOT NULL,
  korrigeret jsonb,
  status text NOT NULL CHECK (status IN ('aaben','rettet','godkendt','udskudt','stale')),
  actor_id uuid,
  actor_navn text,
  oprettet_at timestamptz NOT NULL DEFAULT now(),
  opdateret_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (import_key, record_key, felt)
);
CREATE INDEX import_korrektion_status_import_idx
  ON import_korrektion (status, import_key);

-- Fast byte-kontrakt delt af kvalitetsarkets læse- og kommende skrivevej.
-- jsonb bevarer ikke indsat nøgleorden, så teksten bygges eksplicit i Task 2's R-orden
-- før UTF-8/0x1f/MD5. Task 4 skal genbruge denne helper, ikke kopiere logikken.
CREATE OR REPLACE FUNCTION ocr_input_fingerprint(
  p_import_key text, p_record_key text, p_felt text, p_importeret jsonb, p_ocr_context text
) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT md5(concat_ws(chr(31),
    coalesce(p_import_key,''), coalesce(p_record_key,''), coalesce(p_felt,''),
    CASE WHEN p_felt IN ('foedsel','doed') THEN format(
      '{"raw":%s,"min":%s,"max":%s,"qualifier":%s,"calendar":%s,"certainty":%s}',
      coalesce(to_jsonb(p_importeret->>'raw')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'min')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'max')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'qualifier')::text,'null'),
      coalesce(to_jsonb(coalesce(p_importeret->>'calendar','gregoriansk'))::text,'null'),
      coalesce(to_jsonb(p_importeret->>'certainty')::text,'null'))
    ELSE format('{"value":%s}',coalesce(to_jsonb(p_importeret->>'value')::text,'null'))
    END,
    coalesce(p_ocr_context,'')))
$$;

-- Én række pr. fysisk person; alle sidegrene aggregeres før slut-projektionen, så
-- relationer/facts aldrig multiplicerer griddens rækker. Samme-som er kontekst, aldrig collapse.
CREATE OR REPLACE FUNCTION red_person_grid()
RETURNS TABLE (
  person_id bigint, import_key text, record_key text, source_id bigint, source_titel text,
  source_udgave text, linje text, nr integer, slaegtled integer, navn text,
  navn_assertion_id bigint, foedsel_raw text, foedsel_min date, foedsel_max date,
  foedsel_qualifier text, foedsel_assertion_id bigint, doed_raw text, doed_min date,
  doed_max date, doed_qualifier text, doed_assertion_id bigint, input_fingerprint jsonb,
  importeret jsonb, korrigeret jsonb, ocr_context jsonb, kilde_side jsonb, koen text,
  levende boolean, privat boolean, staged boolean, person_status text, kanonisk_person_id bigint,
  samme_som_status text, antal_titler integer, antal_familier integer,
  antal_relationer integer, antal_kilde_assertions integer, qa_koder text[], qa_alvor text,
  review_status jsonb, kan_rettes jsonb, blokarsager jsonb
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
#variable_conflict use_column
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY
  WITH external_anchor AS (
    SELECT p.id AS grid_person_id, count(pei.person_id)::integer AS anchor_count,
      count(*) FILTER (WHERE s.import_key IS NOT NULL AND pei.record_key IS NOT NULL)::integer AS stable_anchor_count,
      max(s.import_key) AS import_key, max(pei.record_key) AS record_key, max(s.id) AS source_id,
      max(s.titel) AS source_titel, max(s.udgave) AS source_udgave, max(pei.linje) AS linje,
      max(pei.nr) AS nr, max(pei.slaegtled_lokal) AS slaegtled
    FROM person p LEFT JOIN person_external_id pei ON pei.person_id=p.id
      LEFT JOIN source s ON s.id=pei.source_id
    GROUP BY p.id
  ), selected_assertions AS (
    SELECT f.subjekt_id AS grid_person_id,
      CASE f.faktatype WHEN 'navn' THEN 'navn' WHEN 'fødsel' THEN 'foedsel' WHEN 'død' THEN 'doed' END AS felt,
      a.id AS assertion_id, a.vaerdi_tekst, a.date_raw, a.date_min, a.date_max, a.date_qualifier,
      a.calendar, a.date_certainty
    FROM fact f JOIN conclusion cn ON cn.target_type='fact' AND cn.target_id=f.id
      JOIN assertion a ON a.id=cn.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.faktatype IN ('navn','fødsel','død') AND cn.status='afklaret'
  ), resolved_rollup AS (
    -- Ankeruafhængigt display-fallback: den allerede AFKLAREDE evidens (samme kilde som
    -- selected_assertions ovenfor), uden anker-gaten field_candidates lægger nedenfor.
    -- Bevidst IKKE person.visning_*: regen_person_visning() ser bort fra conclusion.status
    -- og ville derfor kunne lække en forældet (ikke-afklaret) værdi ind i visningen.
    -- "Præcis 1"-reglen genbruges, så en tvetydig (flere_importerede_facts) situation
    -- forbliver blank her ligesom i den anker-gaterede sti, i stedet for at gætte.
    SELECT grid_person_id,felt,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(vaerdi_tekst) END AS vaerdi_tekst,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_raw) END AS date_raw,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_min) END AS date_min,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_max) END AS date_max,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_qualifier) END AS date_qualifier
    FROM selected_assertions GROUP BY grid_person_id,felt
  ), cited_assertions AS (
    SELECT sa.*, c.source_id, count(c.id)::integer AS citation_count,
      (array_agg(c.citat_tekst ORDER BY c.id))[1] AS ocr_context,
      (array_agg(c.side ORDER BY c.id))[1] AS kilde_side
    FROM selected_assertions sa LEFT JOIN citation c ON c.assertion_id=sa.assertion_id
    GROUP BY sa.grid_person_id,sa.felt,sa.assertion_id,sa.vaerdi_tekst,sa.date_raw,sa.date_min,sa.date_max,
      sa.date_qualifier,sa.calendar,sa.date_certainty,c.source_id
  ), field_candidates AS (
    SELECT ca.grid_person_id,ca.felt,ca.assertion_id,ca.vaerdi_tekst,ca.date_raw,ca.date_min,ca.date_max,
      ca.date_qualifier,ca.ocr_context,ca.kilde_side,
      CASE WHEN ca.felt IN ('foedsel','doed') THEN jsonb_build_object(
        'raw',ca.date_raw,'min',ca.date_min::text,'max',ca.date_max::text,
        'qualifier',ca.date_qualifier,'calendar',coalesce(ca.calendar,'gregoriansk'),'certainty',ca.date_certainty)
      ELSE jsonb_build_object('value',ca.vaerdi_tekst) END AS current_importeret
    FROM cited_assertions ca JOIN external_anchor ea ON ea.grid_person_id=ca.grid_person_id
    WHERE ea.anchor_count=1 AND ea.stable_anchor_count=1 AND ca.source_id=ea.source_id
      AND ca.citation_count > 0
  ), field_rollup AS (
    SELECT grid_person_id,felt,count(DISTINCT assertion_id)::integer AS candidate_count,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(assertion_id) END AS assertion_id,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(vaerdi_tekst) END AS vaerdi_tekst,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_raw) END AS date_raw,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_min) END AS date_min,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_max) END AS date_max,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_qualifier) END AS date_qualifier,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(ocr_context) END AS ocr_context,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(kilde_side) END AS kilde_side,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN (array_agg(current_importeret ORDER BY assertion_id))[1] END AS current_importeret
    FROM field_candidates GROUP BY grid_person_id,felt
  ), title_counts AS (
    SELECT f.subjekt_id AS grid_person_id,count(*)::integer AS antal_titler FROM fact f
    WHERE f.subjekt_type='person' AND f.faktatype='titel' GROUP BY f.subjekt_id
  ), family_counts AS (
    SELECT person_id AS grid_person_id,count(DISTINCT family_id)::integer AS antal_familier FROM family_member GROUP BY person_id
  ), relation_counts AS (
    SELECT grid_person_id,count(DISTINCT relation_id)::integer AS antal_relationer FROM (
      SELECT subjekt_id AS grid_person_id,id AS relation_id FROM relation WHERE subjekt_type='person'
      UNION ALL SELECT objekt_id,id FROM relation WHERE objekt_type='person') r GROUP BY grid_person_id
  ), citation_counts AS (
    SELECT f.subjekt_id AS grid_person_id,count(DISTINCT a.id)::integer AS antal_kilde_assertions
    FROM fact f JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id JOIN citation c ON c.assertion_id=a.id
    WHERE f.subjekt_type='person' GROUP BY f.subjekt_id
  ), counts AS (
    SELECT p.id AS grid_person_id,coalesce(tc.antal_titler,0) AS antal_titler,coalesce(fc.antal_familier,0) AS antal_familier,
      coalesce(rc.antal_relationer,0) AS antal_relationer,coalesce(cc.antal_kilde_assertions,0) AS antal_kilde_assertions
    FROM person p LEFT JOIN title_counts tc ON tc.grid_person_id=p.id LEFT JOIN family_counts fc ON fc.grid_person_id=p.id
      LEFT JOIN relation_counts rc ON rc.grid_person_id=p.id LEFT JOIN citation_counts cc ON cc.grid_person_id=p.id
  ), same_as_context AS (
    -- Højst ÉN række pr. person. En person midt i en samme_som-kæde er både alias og
    -- kanonisk; de to rækker adskiller sig på samme_som_status og overlevede derfor
    -- GROUP BY'et i den afsluttende SELECT, så samme fysiske person kom ud af griddet
    -- to gange. (Kæder er ikke hypotetiske: enforce_samme_som_invariants() er BEFORE
    -- INSERT og G4 tjekker kun NEW.subjekt, så indsættes den inderste kant først,
    -- slipper den ydre igennem — én person i prod står sådan.) Alias vinder over
    -- kanonisk: det er det stærkere udsagn om personens identitet, og redaktøren skal
    -- kunne se hvem rækken peger på. Laveste kanoniske id bryder resten deterministisk.
    SELECT DISTINCT ON (grid_person_id) grid_person_id,kanonisk_grid_person_id,samme_som_status
    FROM (
      SELECT r.subjekt_id AS grid_person_id,r.objekt_id AS kanonisk_grid_person_id,'alias'::text AS samme_som_status,1 AS prio
      FROM relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
      UNION ALL
      SELECT r.objekt_id,r.objekt_id,'kanonisk'::text,2
      FROM relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
    ) s
    ORDER BY grid_person_id,prio,kanonisk_grid_person_id
  ), all_fields AS (
    SELECT p.id AS grid_person_id,v.felt FROM person p CROSS JOIN (VALUES ('navn'::text),('foedsel'),('doed'),('koen')) v(felt)
  ), field_data AS (
    SELECT af.grid_person_id,af.felt,ea.anchor_count,ea.stable_anchor_count,ea.import_key,ea.record_key,ea.source_id,
      ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,fr.candidate_count,fr.assertion_id,fr.vaerdi_tekst,fr.date_raw,
      fr.date_min,fr.date_max,fr.date_qualifier,fr.ocr_context,fr.kilde_side,fr.current_importeret,
      rr.vaerdi_tekst AS resolved_vaerdi_tekst,rr.date_raw AS resolved_date_raw,rr.date_min AS resolved_date_min,
      rr.date_max AS resolved_date_max,rr.date_qualifier AS resolved_date_qualifier,
      CASE WHEN af.felt='koen' THEN jsonb_build_object('value',p.koen) ELSE fr.current_importeret END AS base_importeret,
      CASE WHEN af.felt='koen' THEN p.koen ELSE fr.vaerdi_tekst END AS felt_vaerdi
    FROM all_fields af JOIN person p ON p.id=af.grid_person_id JOIN external_anchor ea ON ea.grid_person_id=af.grid_person_id
      LEFT JOIN field_rollup fr ON fr.grid_person_id=af.grid_person_id AND fr.felt=af.felt
      LEFT JOIN resolved_rollup rr ON rr.grid_person_id=af.grid_person_id AND rr.felt=af.felt
  ), journal AS (
    SELECT fd.*,ik.importeret AS journal_importeret,ik.korrigeret,ik.status AS journal_status,
      ik.input_fingerprint AS journal_fingerprint,
      CASE WHEN fd.anchor_count=1 AND fd.stable_anchor_count=1
             AND (fd.felt='koen' OR fd.candidate_count=1)
        THEN ocr_input_fingerprint(fd.import_key,fd.record_key,fd.felt,coalesce(ik.importeret,fd.base_importeret),fd.ocr_context)
      END AS fingerprint
    FROM field_data fd LEFT JOIN import_korrektion ik
      ON ik.import_key=fd.import_key AND ik.record_key=fd.record_key AND ik.felt=fd.felt
  ), field_state AS (
    SELECT j.*,coalesce(j.journal_importeret,j.base_importeret) AS effective_importeret,
      CASE WHEN j.journal_status IS NULL THEN 'aaben'
           WHEN j.fingerprint IS DISTINCT FROM j.journal_fingerprint
             THEN 'stale' ELSE j.journal_status END AS effective_status,
      CASE WHEN j.anchor_count=0 THEN 'ingen_importanker'
           WHEN j.anchor_count<>1 THEN 'flere_importankre'
           WHEN j.stable_anchor_count<>1 AND j.import_key IS NULL THEN 'import_key_mangler'
           WHEN j.stable_anchor_count<>1 THEN 'record_key_mangler'
           WHEN j.felt='koen' THEN NULL
           WHEN coalesce(j.candidate_count,0)=0 THEN 'ingen_kildebelagt_assertion'
           WHEN j.candidate_count>1 THEN 'flere_importerede_facts'
      END AS blokarsag
    FROM journal j
  ), missing_context AS (
    SELECT DISTINCT sa.grid_person_id FROM selected_assertions sa JOIN external_anchor ea ON ea.grid_person_id=sa.grid_person_id
    WHERE ea.anchor_count=1 AND ea.stable_anchor_count=1 AND NOT EXISTS (
      SELECT 1 FROM citation c WHERE c.assertion_id=sa.assertion_id AND c.source_id=ea.source_id
        AND nullif(btrim(c.citat_tekst),'') IS NOT NULL)
  ), qa_items AS (
    SELECT fs.grid_person_id,'mistænkeligt_ocr_tegn'::text AS kode,'advarsel'::text AS alvor FROM field_state fs
      WHERE coalesce(fs.ocr_context,'') ~ '[?�]'
    UNION ALL SELECT sa.grid_person_id,'dato_ufortolkelig','fejl' FROM selected_assertions sa
      WHERE sa.felt IN ('foedsel','doed') AND sa.date_raw IS NOT NULL AND sa.date_min IS NULL AND sa.date_max IS NULL
    UNION ALL SELECT b.grid_person_id,'foedt_efter_doed','fejl' FROM field_state b JOIN field_state d
      ON d.grid_person_id=b.grid_person_id AND d.felt='doed'
      WHERE b.felt='foedsel' AND b.date_min IS NOT NULL AND d.date_max IS NOT NULL AND b.date_min>d.date_max
    UNION ALL SELECT fs.grid_person_id,'struktureret_afviger_fra_ocr','advarsel' FROM field_state fs
      WHERE fs.felt='navn' AND fs.felt_vaerdi IS NOT NULL AND fs.ocr_context IS NOT NULL AND btrim(fs.felt_vaerdi)<>btrim(fs.ocr_context)
    -- navn_mangler måler PRÆCIS den værdi griddet viser — ikke om rækken kan rettes.
    -- candidate_count/felt_vaerdi er anker-gatede; visningen falder tilbage til
    -- resolved_vaerdi_tekst. Målte koden på de gatede felter, flagede den hver eneste
    -- ikke-redigerbar række, uanset at navnet stod der. Redigerbarhed hører til
    -- kan_rettes/blokarsager; at blande de to gav 1169 falske flag ud af 1757.
    UNION ALL SELECT fs.grid_person_id,'navn_mangler','fejl' FROM field_state fs
      WHERE fs.felt='navn' AND nullif(btrim(coalesce(fs.felt_vaerdi,fs.resolved_vaerdi_tekst)),'') IS NULL
    UNION ALL SELECT fs.grid_person_id,'record_key_mangler','fejl' FROM field_state fs
      WHERE fs.anchor_count=1 AND fs.stable_anchor_count=0 AND fs.record_key IS NULL
    UNION ALL SELECT grid_person_id,'ocr_kontekst_mangler','advarsel' FROM missing_context
    UNION ALL SELECT fs.grid_person_id,'flere_importerede_facts','fejl' FROM field_state fs
      WHERE fs.felt IN ('navn','foedsel','doed') AND fs.candidate_count>1
    UNION ALL SELECT fs.grid_person_id,'kilde_aendret','advarsel' FROM field_state fs WHERE fs.effective_status='stale'
  ), qa AS (
    SELECT grid_person_id,array_agg(DISTINCT kode ORDER BY kode) AS qa_koder,
      CASE WHEN bool_or(alvor='fejl') THEN 'fejl' WHEN bool_or(alvor='advarsel') THEN 'advarsel' ELSE 'info' END AS qa_alvor
    FROM qa_items GROUP BY grid_person_id
  ), field_json AS (
    SELECT grid_person_id,
      jsonb_object_agg(felt,effective_status) AS review_status,
      jsonb_object_agg(felt,(blokarsag IS NULL)) AS kan_rettes,
      coalesce(jsonb_object_agg(felt,blokarsag) FILTER (WHERE blokarsag IS NOT NULL),'{}'::jsonb) AS blokarsager,
      jsonb_object_agg(felt,to_jsonb(fingerprint)) FILTER (WHERE fingerprint IS NOT NULL) AS input_fingerprint,
      jsonb_object_agg(felt,effective_importeret) FILTER (WHERE effective_importeret IS NOT NULL) AS importeret,
      jsonb_object_agg(felt,korrigeret) FILTER (WHERE korrigeret IS NOT NULL) AS korrigeret,
      jsonb_object_agg(felt,to_jsonb(ocr_context)) FILTER (WHERE ocr_context IS NOT NULL) AS ocr_context,
      jsonb_object_agg(felt,to_jsonb(kilde_side)) FILTER (WHERE kilde_side IS NOT NULL) AS kilde_side
    FROM field_state GROUP BY grid_person_id
  )
  SELECT p.id,ea.import_key,ea.record_key,ea.source_id,ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,
    coalesce(max(fs.felt_vaerdi) FILTER (WHERE fs.felt='navn'),max(fs.resolved_vaerdi_tekst) FILTER (WHERE fs.felt='navn')),max(fs.assertion_id) FILTER (WHERE fs.felt='navn'),
    coalesce(max(fs.date_raw) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_raw) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_min) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_min) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_max) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_max) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_qualifier) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_qualifier) FILTER (WHERE fs.felt='foedsel')),
    max(fs.assertion_id) FILTER (WHERE fs.felt='foedsel'),
    coalesce(max(fs.date_raw) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_raw) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_min) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_min) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_max) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_max) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_qualifier) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_qualifier) FILTER (WHERE fs.felt='doed')),
    max(fs.assertion_id) FILTER (WHERE fs.felt='doed'),
    coalesce(fj.input_fingerprint,'{}'::jsonb),coalesce(fj.importeret,'{}'::jsonb),coalesce(fj.korrigeret,'{}'::jsonb),coalesce(fj.ocr_context,'{}'::jsonb),coalesce(fj.kilde_side,'{}'::jsonb),
    p.koen,p.levende,p.privat,p.staged,p.status,sac.kanonisk_grid_person_id,sac.samme_som_status,
    coalesce(ct.antal_titler,0),coalesce(ct.antal_familier,0),coalesce(ct.antal_relationer,0),coalesce(ct.antal_kilde_assertions,0),
    coalesce(q.qa_koder,ARRAY[]::text[]),q.qa_alvor,coalesce(fj.review_status,'{}'::jsonb),coalesce(fj.kan_rettes,'{}'::jsonb),coalesce(fj.blokarsager,'{}'::jsonb)
  FROM person p JOIN external_anchor ea ON ea.grid_person_id=p.id JOIN field_state fs ON fs.grid_person_id=p.id
    LEFT JOIN counts ct ON ct.grid_person_id=p.id LEFT JOIN same_as_context sac ON sac.grid_person_id=p.id
    LEFT JOIN qa q ON q.grid_person_id=p.id LEFT JOIN field_json fj ON fj.grid_person_id=p.id
  GROUP BY p.id,ea.import_key,ea.record_key,ea.source_id,ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,
    p.koen,p.levende,p.privat,p.staged,p.status,sac.kanonisk_grid_person_id,sac.samme_som_status,ct.antal_titler,ct.antal_familier,
    ct.antal_relationer,ct.antal_kilde_assertions,q.qa_koder,q.qa_alvor,fj.input_fingerprint,fj.importeret,fj.korrigeret,
    fj.ocr_context,fj.kilde_side,fj.review_status,fj.kan_rettes,fj.blokarsager;
END $$;

-- OCR-korrekturens indre kanonisering. JSONB er semantisk (ikke tekstuelt) ordnet;
-- den delte public-fingerprint-funktion emitterer stadig Task 2's faste nøgleorden.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

-- Fremtidige objekter i det private evidenslag må ikke arve Supabases
-- direkte standard-grants til API-rollerne. Gælder for den ejer, der kører DDL'en.
ALTER DEFAULT PRIVILEGES IN SCHEMA private
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA private
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
-- Fjerner eventuelle schema-lokale Supabase-default-grants. PostgreSQLs
-- implicitte PUBLIC-EXECUTE kan ikke fjernes schema-lokalt, men bliver
-- ineffektiv uden USAGE på private; eksisterende funktioner revokes nedenfor.
ALTER DEFAULT PRIVILEGES IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- ---------- PRIVAT, APPEND-ONLY KILDEEVIDENS ----------
-- extraction_run er et færdigt, reproducerbart manifest. Delvise batchtilstande
-- hører til arbejdsartefakterne og indlæses ikke som en grøn run-række.
CREATE TABLE private.extraction_run (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id         bigint NOT NULL REFERENCES public.source(id),
  run_key           text NOT NULL CHECK (btrim(run_key) <> ''),
  schema_version    text NOT NULL CHECK (btrim(schema_version) <> ''),
  extractor_version text NOT NULL CHECK (btrim(extractor_version) <> ''),
  profile_version   text NOT NULL CHECK (btrim(profile_version) <> ''),
  input_sha256      text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
  manifest          jsonb NOT NULL DEFAULT '{}'::jsonb
                    CHECK (jsonb_typeof(manifest)='object'),
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_id, run_key),
  UNIQUE (id, source_id)
);

CREATE TABLE private.source_rendition (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id      bigint NOT NULL REFERENCES public.source(id),
  rendition_key  text NOT NULL CHECK (btrim(rendition_key) <> ''),
  rendition_kind text NOT NULL CHECK (btrim(rendition_kind) <> ''),
  content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  metadata       jsonb NOT NULL DEFAULT '{}'::jsonb
                 CHECK (jsonb_typeof(metadata)='object'),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_id, rendition_key),
  UNIQUE (id, source_id)
);
CREATE INDEX source_rendition_content_idx
  ON private.source_rendition(source_id,content_sha256);

CREATE TABLE private.source_record (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id      bigint NOT NULL REFERENCES public.source(id),
  record_key     text NOT NULL CHECK (btrim(record_key) <> ''),
  record_kind    text NOT NULL CHECK (btrim(record_kind) <> ''),
  created_run_id uuid NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_id,record_key),
  UNIQUE (id,source_id),
  FOREIGN KEY (created_run_id,source_id)
    REFERENCES private.extraction_run(id,source_id)
);

CREATE TABLE private.source_record_occurrence (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rendition_id           uuid NOT NULL REFERENCES private.source_rendition(id),
  occurrence_key         text NOT NULL CHECK (btrim(occurrence_key) <> ''),
  page_from              integer NOT NULL CHECK (page_from >= 1),
  page_to                integer NOT NULL CHECK (page_to >= page_from),
  column_label           text,
  char_from              integer NOT NULL CHECK (char_from >= 0),
  char_to                integer NOT NULL CHECK (char_to > char_from),
  bbox                   jsonb,
  verbatim_text          text NOT NULL CHECK (verbatim_text <> ''),
  physical_fingerprint   text NOT NULL CHECK (btrim(physical_fingerprint) <> ''),
  structural_fingerprint text NOT NULL CHECK (btrim(structural_fingerprint) <> ''),
  extraction_run_id      uuid NOT NULL REFERENCES private.extraction_run(id),
  created_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (rendition_id,extraction_run_id,occurrence_key)
);

CREATE TABLE private.source_record_anchor_event (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurrence_id    uuid NOT NULL REFERENCES private.source_record_occurrence(id),
  source_record_id uuid NOT NULL REFERENCES private.source_record(id),
  decision_status  text NOT NULL
                   CHECK (decision_status IN ('proposed','accepted','rejected')),
  evidence         jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  version          integer NOT NULL CHECK (version >= 1),
  -- Uforanderligt audit-id, bevidst uden FK til den mutable auth-livscyklus.
  decided_by       uuid,
  decided_by_name  text,
  decided_at       timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (occurrence_id,source_record_id,version),
  CHECK (
    decision_status='proposed'
    OR (
      nullif(btrim(decided_by_name),'') IS NOT NULL
      AND evidence <> '{}'::jsonb
    )
  )
);

CREATE TABLE private.source_record_revision_event (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  predecessor_record_id uuid NOT NULL REFERENCES private.source_record(id),
  successor_record_id   uuid NOT NULL REFERENCES private.source_record(id),
  relation_kind         text NOT NULL
                        CHECK (relation_kind IN ('split_into','merged_from','replaced_by')),
  decision_status       text NOT NULL
                        CHECK (decision_status IN ('proposed','accepted','rejected')),
  evidence              jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  version               integer NOT NULL CHECK (version >= 1),
  -- Uforanderligt audit-id, bevidst uden FK til den mutable auth-livscyklus.
  decided_by            uuid,
  decided_by_name       text,
  decided_at            timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (predecessor_record_id,successor_record_id,relation_kind,version),
  CHECK (predecessor_record_id <> successor_record_id),
  CHECK (
    decision_status='proposed'
    OR (
      nullif(btrim(decided_by_name),'') IS NOT NULL
      AND evidence <> '{}'::jsonb
    )
  )
);

CREATE TABLE private.source_observation (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurrence_id     uuid NOT NULL REFERENCES private.source_record_occurrence(id),
  observation_kind  text NOT NULL CHECK (btrim(observation_kind) <> ''),
  page_from         integer NOT NULL CHECK (page_from >= 1),
  page_to           integer NOT NULL CHECK (page_to >= page_from),
  column_label      text,
  char_from         integer NOT NULL CHECK (char_from >= 0),
  char_to           integer NOT NULL CHECK (char_to > char_from),
  bbox              jsonb,
  verbatim_text     text NOT NULL CHECK (verbatim_text <> ''),
  quality_status    text NOT NULL CHECK (
    quality_status IN ('clear','ocr_uncertain','truncated','structurally_uncertain','illegible')
  ),
  extraction_method text NOT NULL CHECK (btrim(extraction_method) <> ''),
  extraction_run_id uuid NOT NULL REFERENCES private.extraction_run(id),
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.source_observation_text (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_id  uuid NOT NULL REFERENCES private.source_observation(id),
  rendition_id    uuid NOT NULL REFERENCES private.source_rendition(id),
  version         integer NOT NULL CHECK (version >= 1),
  verbatim_text   text NOT NULL CHECK (verbatim_text <> ''),
  char_from       integer NOT NULL CHECK (char_from >= 0),
  char_to         integer NOT NULL CHECK (char_to > char_from),
  bbox            jsonb,
  is_preferred    boolean NOT NULL DEFAULT false,
  supersedes_id   uuid REFERENCES private.source_observation_text(id),
  -- Uforanderligt audit-id, bevidst uden FK til den mutable auth-livscyklus.
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (observation_id,rendition_id,version),
  CHECK (supersedes_id IS NULL OR supersedes_id <> id)
);
CREATE TABLE private.source_mention (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_id   uuid NOT NULL REFERENCES private.source_observation(id),
  mention_kind     text NOT NULL CHECK (btrim(mention_kind) <> ''),
  char_from        integer NOT NULL CHECK (char_from >= 0),
  char_to          integer NOT NULL CHECK (char_to > char_from),
  verbatim_text    text NOT NULL CHECK (verbatim_text <> ''),
  created_run_id   uuid NOT NULL REFERENCES private.extraction_run(id),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.source_persona (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id      bigint NOT NULL REFERENCES public.source(id),
  persona_key    text NOT NULL CHECK (btrim(persona_key) <> ''),
  created_run_id uuid NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_id,persona_key),
  UNIQUE (id,source_id),
  FOREIGN KEY (created_run_id,source_id)
    REFERENCES private.extraction_run(id,source_id)
);

CREATE TABLE private.source_persona_mention (
  persona_id   uuid NOT NULL REFERENCES private.source_persona(id),
  mention_id   uuid NOT NULL REFERENCES private.source_mention(id),
  mention_role text NOT NULL CHECK (btrim(mention_role) <> ''),
  ordinal      integer NOT NULL CHECK (ordinal >= 1),
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (persona_id,mention_id),
  UNIQUE (persona_id,ordinal)
);

-- Seneste event pr. logisk nøgle. Views ligger i private og er ikke API-flader.
CREATE VIEW private.source_record_anchor_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (occurrence_id,source_record_id) *
  FROM private.source_record_anchor_event
 ORDER BY occurrence_id,source_record_id,version DESC,created_at DESC,id DESC;

CREATE VIEW private.source_record_revision_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (predecessor_record_id,successor_record_id,relation_kind) *
  FROM private.source_record_revision_event
 ORDER BY predecessor_record_id,successor_record_id,relation_kind,
          version DESC,created_at DESC,id DESC;

CREATE VIEW private.source_observation_text_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (observation_id) *
  FROM private.source_observation_text
 ORDER BY observation_id,is_preferred DESC,version DESC,created_at DESC,id DESC;

-- Alle rå kilde-/hypoteserækker er uforanderlige. En rettelse er en ny række/event.
CREATE FUNCTION private.reject_evidence_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  RAISE EXCEPTION 'EVIDENCE_APPEND_ONLY: %.% kan ikke %',TG_TABLE_SCHEMA,TG_TABLE_NAME,TG_OP;
END $$;

CREATE FUNCTION private.validate_evidence_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_source_a bigint;
  v_source_b bigint;
  v_text text;
BEGIN
  IF TG_TABLE_NAME='source_record_occurrence' THEN
    SELECT source_id INTO v_source_a FROM private.source_rendition WHERE id=NEW.rendition_id;
    SELECT source_id INTO v_source_b FROM private.extraction_run WHERE id=NEW.extraction_run_id;
  ELSIF TG_TABLE_NAME='source_observation' THEN
    SELECT r.source_id INTO v_source_a
      FROM private.source_record_occurrence o
      JOIN private.source_rendition r ON r.id=o.rendition_id
     WHERE o.id=NEW.occurrence_id;
    SELECT source_id INTO v_source_b FROM private.extraction_run WHERE id=NEW.extraction_run_id;
    IF NEW.page_from < (SELECT page_from FROM private.source_record_occurrence WHERE id=NEW.occurrence_id)
       OR NEW.page_to > (SELECT page_to FROM private.source_record_occurrence WHERE id=NEW.occurrence_id)
       OR NEW.char_from < (SELECT char_from FROM private.source_record_occurrence WHERE id=NEW.occurrence_id)
       OR NEW.char_to > (SELECT char_to FROM private.source_record_occurrence WHERE id=NEW.occurrence_id) THEN
      RAISE EXCEPTION 'EVIDENCE_OBSERVATION_SPAN_INVALID';
    END IF;
  ELSIF TG_TABLE_NAME='source_observation_text' THEN
    SELECT r.source_id INTO v_source_a
      FROM private.source_observation o
      JOIN private.source_record_occurrence ro ON ro.id=o.occurrence_id
      JOIN private.source_rendition r ON r.id=ro.rendition_id
     WHERE o.id=NEW.observation_id;
    SELECT source_id INTO v_source_b FROM private.source_rendition WHERE id=NEW.rendition_id;
    IF (NEW.version=1 AND NEW.supersedes_id IS NOT NULL)
       OR (NEW.version>1 AND NOT EXISTS (
         SELECT 1 FROM private.source_observation_text previous
          WHERE previous.id=NEW.supersedes_id
            AND previous.observation_id=NEW.observation_id
            AND previous.rendition_id=NEW.rendition_id
            AND previous.version=NEW.version-1
       )) THEN
      RAISE EXCEPTION 'EVIDENCE_TEXT_VERSION_CONFLICT';
    END IF;
  ELSIF TG_TABLE_NAME='source_mention' THEN
    SELECT o.verbatim_text,r.source_id INTO v_text,v_source_a
      FROM private.source_observation o
      JOIN private.source_record_occurrence ro ON ro.id=o.occurrence_id
      JOIN private.source_rendition r ON r.id=ro.rendition_id
     WHERE o.id=NEW.observation_id;
    SELECT source_id INTO v_source_b FROM private.extraction_run WHERE id=NEW.created_run_id;
    IF NEW.char_to > length(v_text)
       OR substr(v_text,NEW.char_from+1,NEW.char_to-NEW.char_from) <> NEW.verbatim_text THEN
      RAISE EXCEPTION 'EVIDENCE_MENTION_SPAN_INVALID';
    END IF;
  ELSIF TG_TABLE_NAME='source_persona_mention' THEN
    SELECT source_id INTO v_source_a FROM private.source_persona WHERE id=NEW.persona_id;
    SELECT r.source_id INTO v_source_b
      FROM private.source_mention m
      JOIN private.source_observation o ON o.id=m.observation_id
      JOIN private.source_record_occurrence ro ON ro.id=o.occurrence_id
      JOIN private.source_rendition r ON r.id=ro.rendition_id
     WHERE m.id=NEW.mention_id;
  END IF;
  IF v_source_a IS DISTINCT FROM v_source_b THEN
    RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: %',TG_TABLE_NAME;
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_source_record_anchor_event()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_occurrence_source bigint;
  v_record_source bigint;
  v_expected_version integer;
BEGIN
  IF NEW.decision_status<>'proposed' AND (
    NEW.decided_by IS NULL
    OR nullif(btrim(NEW.decided_by_name),'') IS NULL
    OR NEW.evidence='{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_METADATA_REQUIRED';
  END IF;
  PERFORM 1 FROM private.source_record_occurrence WHERE id=NEW.occurrence_id FOR UPDATE;
  SELECT r.source_id INTO v_occurrence_source
    FROM private.source_record_occurrence o
    JOIN private.source_rendition r ON r.id=o.rendition_id
   WHERE o.id=NEW.occurrence_id;
  SELECT source_id INTO v_record_source FROM private.source_record WHERE id=NEW.source_record_id;
  IF v_occurrence_source IS DISTINCT FROM v_record_source THEN
    RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: source_record_anchor_event';
  END IF;
  SELECT coalesce(max(version),0)+1 INTO v_expected_version
    FROM private.source_record_anchor_event
   WHERE occurrence_id=NEW.occurrence_id AND source_record_id=NEW.source_record_id;
  IF NEW.version <> v_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_EVENT_VERSION_CONFLICT: expected %, got %',v_expected_version,NEW.version;
  END IF;
  IF NEW.decision_status='accepted' AND EXISTS (
    SELECT 1 FROM private.source_record_anchor_current c
     WHERE c.occurrence_id=NEW.occurrence_id
       AND c.decision_status='accepted'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_ANCHOR_CONFLICT: occurrence har allerede en accepted anchor';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_source_record_revision_event()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_predecessor_source bigint;
  v_successor_source bigint;
  v_expected_version integer;
BEGIN
  IF NEW.decision_status<>'proposed' AND (
    NEW.decided_by IS NULL
    OR nullif(btrim(NEW.decided_by_name),'') IS NULL
    OR NEW.evidence='{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_METADATA_REQUIRED';
  END IF;
  PERFORM id FROM private.source_record
   WHERE id IN (NEW.predecessor_record_id,NEW.successor_record_id)
   ORDER BY id FOR UPDATE;
  SELECT source_id INTO v_predecessor_source FROM private.source_record WHERE id=NEW.predecessor_record_id;
  SELECT source_id INTO v_successor_source FROM private.source_record WHERE id=NEW.successor_record_id;
  IF v_predecessor_source IS DISTINCT FROM v_successor_source THEN
    RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: source_record_revision_event';
  END IF;
  SELECT coalesce(max(version),0)+1 INTO v_expected_version
    FROM private.source_record_revision_event
   WHERE predecessor_record_id=NEW.predecessor_record_id
     AND successor_record_id=NEW.successor_record_id
     AND relation_kind=NEW.relation_kind;
  IF NEW.version <> v_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_EVENT_VERSION_CONFLICT: expected %, got %',v_expected_version,NEW.version;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_source_record_occurrence_scope
  BEFORE INSERT ON private.source_record_occurrence
  FOR EACH ROW EXECUTE FUNCTION private.validate_evidence_scope();
CREATE TRIGGER trg_source_observation_scope
  BEFORE INSERT ON private.source_observation
  FOR EACH ROW EXECUTE FUNCTION private.validate_evidence_scope();
CREATE TRIGGER trg_source_observation_text_scope
  BEFORE INSERT ON private.source_observation_text
  FOR EACH ROW EXECUTE FUNCTION private.validate_evidence_scope();
CREATE TRIGGER trg_source_mention_scope
  BEFORE INSERT ON private.source_mention
  FOR EACH ROW EXECUTE FUNCTION private.validate_evidence_scope();
CREATE TRIGGER trg_source_persona_mention_scope
  BEFORE INSERT ON private.source_persona_mention
  FOR EACH ROW EXECUTE FUNCTION private.validate_evidence_scope();
CREATE TRIGGER trg_source_record_anchor_event_validate
  BEFORE INSERT ON private.source_record_anchor_event
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_record_anchor_event();
CREATE TRIGGER trg_source_record_revision_event_validate
  BEFORE INSERT ON private.source_record_revision_event
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_record_revision_event();

DO $$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'extraction_run','source_rendition','source_record','source_record_occurrence',
    'source_record_anchor_event','source_record_revision_event','source_observation',
    'source_observation_text','source_mention','source_persona','source_persona_mention'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON private.%I '
      || 'FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation()',
      'trg_' || v_table || '_append_only',v_table
    );
    EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',v_table);
  END LOOP;
END $$;

REVOKE ALL ON TABLE private.source_record_anchor_current,
                    private.source_record_revision_current,
                    private.source_observation_text_current
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.reject_evidence_mutation(),
                           private.validate_evidence_scope(),
                           private.validate_source_record_anchor_event(),
                           private.validate_source_record_revision_event()
  FROM PUBLIC,anon,authenticated;

-- ---------- PRIVAT FORTOLKNING, PROMOTION OG IDENTITET ----------
-- interpretation er selv sin versionslog: en afgørelse indsætter en ny række,
-- og observationerne kopieres. Den tidligere version omskrives aldrig.
CREATE TABLE private.interpretation (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interpretation_key  uuid NOT NULL,
  version             integer NOT NULL CHECK (version>=1),
  source_id           bigint NOT NULL REFERENCES public.source(id),
  source_persona_id   uuid REFERENCES private.source_persona(id),
  interpretation_kind text NOT NULL
                      CHECK (interpretation_kind IN ('property','relation','event','mention')),
  predicate           text NOT NULL CHECK (btrim(predicate)<>''),
  value               jsonb NOT NULL,
  schema_version      text NOT NULL CHECK (btrim(schema_version)<>''),
  derivation_kind     text NOT NULL CHECK (
                        derivation_kind IN
                          ('source_statement','deterministic','model_inference','human_judgement')
                      ),
  confidence          numeric NOT NULL CHECK (confidence>=0 AND confidence<=1),
  status              text NOT NULL CHECK (
                        status IN ('proposed','accepted','rejected','unresolved','superseded')
                      ),
  method              text NOT NULL CHECK (btrim(method)<>''),
  model_version       text,
  prompt_version      text,
  extraction_run_id   uuid NOT NULL,
  supersedes_id       uuid REFERENCES private.interpretation(id),
  decision_evidence   jsonb NOT NULL DEFAULT '{}'::jsonb
                      CHECK (jsonb_typeof(decision_evidence)='object'),
  decided_by          uuid,
  decided_by_name     text,
  decided_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (interpretation_key,version),
  FOREIGN KEY (extraction_run_id,source_id)
    REFERENCES private.extraction_run(id,source_id),
  CHECK (
    (version=1 AND supersedes_id IS NULL)
    OR (version>1 AND supersedes_id IS NOT NULL)
  ),
  CONSTRAINT interpretation_decision_audit_check CHECK (
    status='proposed'
    OR (
      decided_by IS NOT NULL
      AND nullif(btrim(decided_by_name),'') IS NOT NULL
      AND decided_at IS NOT NULL
      AND decision_evidence<>'{}'::jsonb
    )
  ),
  CONSTRAINT interpretation_proposal_actor_check CHECK (
    status<>'proposed'
    OR (decided_by IS NULL AND decided_by_name IS NULL AND decided_at IS NULL)
  )
);

CREATE TABLE private.interpretation_observation (
  interpretation_id uuid NOT NULL REFERENCES private.interpretation(id),
  observation_id    uuid NOT NULL REFERENCES private.source_observation(id),
  evidence_role     text NOT NULL
                    CHECK (evidence_role IN ('supporting','context','contradicting')),
  ordinal           integer NOT NULL CHECK (ordinal>=1),
  created_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (interpretation_id,observation_id),
  UNIQUE (interpretation_id,ordinal)
);

CREATE TABLE private.interpretation_promotion (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interpretation_id   uuid NOT NULL REFERENCES private.interpretation(id),
  target_type         text NOT NULL CHECK (
                        target_type IN (
                          'person','family','fact','assertion','relation','narrative',
                          'haendelse','lineage','source','coat_of_arms','historical_event'
                        )
                      ),
  target_id           bigint NOT NULL,
  evidence            jsonb NOT NULL CHECK (
                        jsonb_typeof(evidence)='object' AND evidence<>'{}'::jsonb
                      ),
  promoted_by         uuid NOT NULL,
  promoted_by_name    text NOT NULL CHECK (btrim(promoted_by_name)<>''),
  promoted_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (interpretation_id,target_type,target_id)
);

-- Én current-state-række pr. persona gør to samtidige aktive mål umulige.
-- Hver ændring spejles først i den uforanderlige eventlog nedenfor.
CREATE TABLE private.source_persona_identity (
  source_persona_id   uuid PRIMARY KEY REFERENCES private.source_persona(id),
  canonical_person_id bigint REFERENCES public.person(id),
  decision_status     text NOT NULL CHECK (
                        decision_status IN
                          ('proposed','accepted','rejected','unresolved','superseded')
                      ),
  version             integer NOT NULL CHECK (version>=1),
  evidence            jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  decided_by          uuid,
  decided_by_name     text,
  decided_at          timestamptz,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (decision_status<>'accepted' OR canonical_person_id IS NOT NULL),
  CHECK (decision_status<>'unresolved' OR canonical_person_id IS NULL),
  CONSTRAINT source_persona_identity_decision_audit_check CHECK (
    decision_status='proposed'
    OR (
      decided_by IS NOT NULL
      AND nullif(btrim(decided_by_name),'') IS NOT NULL
      AND decided_at IS NOT NULL
      AND evidence<>'{}'::jsonb
    )
  ),
  CONSTRAINT source_persona_identity_proposal_actor_check CHECK (
    decision_status<>'proposed'
    OR (decided_by IS NULL AND decided_by_name IS NULL AND decided_at IS NULL)
  )
);

CREATE TABLE private.source_persona_identity_event (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_persona_id   uuid NOT NULL REFERENCES private.source_persona(id),
  canonical_person_id bigint REFERENCES public.person(id),
  decision_status     text NOT NULL CHECK (
                        decision_status IN
                          ('proposed','accepted','rejected','unresolved','superseded')
                      ),
  version             integer NOT NULL CHECK (version>=1),
  evidence            jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  decided_by          uuid,
  decided_by_name     text,
  decided_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_persona_id,version),
  CHECK (decision_status<>'accepted' OR canonical_person_id IS NOT NULL),
  CHECK (decision_status<>'unresolved' OR canonical_person_id IS NULL),
  CONSTRAINT source_persona_identity_event_decision_audit_check CHECK (
    decision_status='proposed'
    OR (
      decided_by IS NOT NULL
      AND nullif(btrim(decided_by_name),'') IS NOT NULL
      AND decided_at IS NOT NULL
      AND evidence<>'{}'::jsonb
    )
  ),
  CONSTRAINT source_persona_identity_event_proposal_actor_check CHECK (
    decision_status<>'proposed'
    OR (decided_by IS NULL AND decided_by_name IS NULL AND decided_at IS NULL)
  )
);

CREATE VIEW private.interpretation_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (interpretation_key) *
  FROM private.interpretation
 ORDER BY interpretation_key,version DESC,created_at DESC,id DESC;

CREATE FUNCTION private.validate_interpretation_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_source bigint;
BEGIN
  IF NEW.status<>'proposed' AND current_user<>(
    SELECT pg_catalog.pg_get_userbyid(c.relowner)
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname='interpretation'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_PROVENANCE_REQUIRED';
  END IF;
  IF NEW.source_persona_id IS NOT NULL THEN
    SELECT source_id INTO v_source FROM private.source_persona
     WHERE id=NEW.source_persona_id;
    IF v_source IS DISTINCT FROM NEW.source_id THEN
      RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: interpretation persona';
    END IF;
  END IF;
  IF NEW.version>1 AND NOT EXISTS (
    SELECT 1 FROM private.interpretation previous
     WHERE previous.id=NEW.supersedes_id
       AND previous.interpretation_key=NEW.interpretation_key
       AND previous.version=NEW.version-1
       AND previous.source_id=NEW.source_id
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_VERSION_CONFLICT';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_interpretation_observation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_interpretation_source bigint; v_observation_source bigint;
BEGIN
  SELECT source_id INTO v_interpretation_source FROM private.interpretation
   WHERE id=NEW.interpretation_id;
  SELECT r.source_id INTO v_observation_source
    FROM private.source_observation o
    JOIN private.source_record_occurrence ro ON ro.id=o.occurrence_id
    JOIN private.source_rendition r ON r.id=ro.rendition_id
   WHERE o.id=NEW.observation_id;
  IF v_interpretation_source IS DISTINCT FROM v_observation_source THEN
    RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: interpretation observation';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.assert_interpretation_has_observation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.interpretation_observation io
     WHERE io.interpretation_id=NEW.id
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_OBSERVATION_REQUIRED: %',NEW.id;
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION private.validate_interpretation_promotion()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_exists boolean;
BEGIN
  IF current_user<>(
    SELECT pg_catalog.pg_get_userbyid(c.relowner)
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname='interpretation_promotion'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_PROVENANCE_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private.interpretation i
     WHERE i.id=NEW.interpretation_id AND i.status='accepted'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_NOT_ACCEPTED';
  END IF;
  v_exists := CASE NEW.target_type
    WHEN 'person' THEN EXISTS(SELECT 1 FROM public.person WHERE id=NEW.target_id)
    WHEN 'family' THEN EXISTS(SELECT 1 FROM public.family WHERE id=NEW.target_id)
    WHEN 'fact' THEN EXISTS(SELECT 1 FROM public.fact WHERE id=NEW.target_id)
    WHEN 'assertion' THEN EXISTS(SELECT 1 FROM public.assertion WHERE id=NEW.target_id)
    WHEN 'relation' THEN EXISTS(SELECT 1 FROM public.relation WHERE id=NEW.target_id)
    WHEN 'narrative' THEN EXISTS(SELECT 1 FROM public.narrative WHERE id=NEW.target_id)
    WHEN 'haendelse' THEN EXISTS(SELECT 1 FROM public.haendelse WHERE id=NEW.target_id)
    WHEN 'lineage' THEN EXISTS(SELECT 1 FROM public.lineage WHERE id=NEW.target_id)
    WHEN 'source' THEN EXISTS(SELECT 1 FROM public.source WHERE id=NEW.target_id)
    WHEN 'coat_of_arms' THEN EXISTS(SELECT 1 FROM public.coat_of_arms WHERE id=NEW.target_id)
    WHEN 'historical_event' THEN EXISTS(SELECT 1 FROM public.historical_event WHERE id=NEW.target_id)
    ELSE false
  END;
  IF NOT v_exists THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_TARGET_NOT_FOUND: %.%',NEW.target_type,NEW.target_id;
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_source_persona_identity_event()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,private AS $$
DECLARE v_expected integer;
BEGIN
  IF NEW.decision_status<>'proposed' AND current_user<>(
    SELECT pg_catalog.pg_get_userbyid(c.relowner)
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname='source_persona_identity_event'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_PROVENANCE_REQUIRED';
  END IF;
  PERFORM 1 FROM private.source_persona WHERE id=NEW.source_persona_id FOR UPDATE;
  SELECT coalesce(max(version),0)+1 INTO v_expected
    FROM private.source_persona_identity_event
   WHERE source_persona_id=NEW.source_persona_id;
  IF NEW.version<>v_expected THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected %, got %',
      v_expected,NEW.version;
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_source_persona_identity_state()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,private AS $$
BEGIN
  IF NEW.decision_status<>'proposed' AND current_user<>(
    SELECT pg_catalog.pg_get_userbyid(c.relowner)
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname='source_persona_identity'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_PROVENANCE_REQUIRED';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.assert_identity_state_event_consistency()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE
  v_persona_id uuid;
  v_latest_version integer;
  v_state_exists boolean;
BEGIN
  v_persona_id:=CASE WHEN TG_OP='DELETE' THEN OLD.source_persona_id
                     ELSE NEW.source_persona_id END;
  SELECT max(version) INTO v_latest_version
    FROM private.source_persona_identity_event
   WHERE source_persona_id=v_persona_id;
  SELECT EXISTS(
    SELECT 1 FROM private.source_persona_identity
     WHERE source_persona_id=v_persona_id
  ) INTO v_state_exists;

  IF v_latest_version IS NOT NULL AND NOT v_state_exists THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_STATE_REQUIRED';
  END IF;
  IF v_latest_version IS NULL AND v_state_exists THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_EVENT_REQUIRED';
  END IF;
  IF v_latest_version IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM private.source_persona_identity i
     WHERE i.source_persona_id=v_persona_id
       AND i.version=v_latest_version
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_LATEST_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM private.source_persona_identity i
      JOIN private.source_persona_identity_event e
        ON e.source_persona_id=i.source_persona_id AND e.version=i.version
     WHERE i.source_persona_id=v_persona_id
       AND i.canonical_person_id IS NOT DISTINCT FROM e.canonical_person_id
       AND i.decision_status=e.decision_status
       AND i.evidence=e.evidence
       AND i.decided_by IS NOT DISTINCT FROM e.decided_by
       AND i.decided_by_name IS NOT DISTINCT FROM e.decided_by_name
       AND i.decided_at IS NOT DISTINCT FROM e.decided_at
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_EVENT_REQUIRED';
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_interpretation_scope BEFORE INSERT ON private.interpretation
  FOR EACH ROW EXECUTE FUNCTION private.validate_interpretation_scope();
CREATE TRIGGER trg_interpretation_observation_scope
  BEFORE INSERT ON private.interpretation_observation
  FOR EACH ROW EXECUTE FUNCTION private.validate_interpretation_observation();
CREATE CONSTRAINT TRIGGER interpretation_has_observation
  AFTER INSERT ON private.interpretation
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.assert_interpretation_has_observation();
CREATE TRIGGER trg_interpretation_promotion_validate
  BEFORE INSERT ON private.interpretation_promotion
  FOR EACH ROW EXECUTE FUNCTION private.validate_interpretation_promotion();
CREATE TRIGGER trg_source_persona_identity_event_validate
  BEFORE INSERT ON private.source_persona_identity_event
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_persona_identity_event();
CREATE TRIGGER trg_source_persona_identity_state_validate
  BEFORE INSERT OR UPDATE ON private.source_persona_identity
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_persona_identity_state();
CREATE CONSTRAINT TRIGGER identity_state_has_event
  AFTER INSERT OR UPDATE OR DELETE ON private.source_persona_identity
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.assert_identity_state_event_consistency();
CREATE CONSTRAINT TRIGGER identity_event_is_projected
  AFTER INSERT ON private.source_persona_identity_event
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.assert_identity_state_event_consistency();

DO $$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'interpretation','interpretation_observation','interpretation_promotion',
    'source_persona_identity_event'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON private.%I '
      || 'FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation()',
      'trg_'||v_table||'_append_only',v_table
    );
  END LOOP;
  FOREACH v_table IN ARRAY ARRAY[
    'interpretation','interpretation_observation','interpretation_promotion',
    'source_persona_identity','source_persona_identity_event'
  ] LOOP
    EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',v_table);
  END LOOP;
END $$;

REVOKE ALL ON TABLE private.interpretation_current FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.validate_interpretation_scope(),
                           private.validate_interpretation_observation(),
                           private.assert_interpretation_has_observation(),
                           private.validate_interpretation_promotion(),
                           private.validate_source_persona_identity_event(),
                           private.validate_source_persona_identity_state(),
                           private.assert_identity_state_event_consistency()
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.ocr_importeret(
  p_felt text, p_vaerdi text, p_raw text, p_min date, p_max date,
  p_qualifier text, p_calendar text, p_certainty text
) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT CASE WHEN p_felt IN ('foedsel','doed') THEN jsonb_build_object(
    'raw',p_raw,'min',p_min::text,'max',p_max::text,'qualifier',p_qualifier,
    'calendar',coalesce(p_calendar,'gregoriansk'),'certainty',p_certainty)
  ELSE jsonb_build_object('value',p_vaerdi) END
$$;

CREATE OR REPLACE FUNCTION private.ocr_fingerprint(
  p_import_key text, p_record_key text, p_felt text, p_importeret jsonb, p_ocr_context text
) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT public.ocr_input_fingerprint(p_import_key,p_record_key,p_felt,p_importeret,p_ocr_context)
$$;

REVOKE ALL ON FUNCTION private.ocr_importeret(text,text,text,date,date,text,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.ocr_fingerprint(text,text,text,jsonb,text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION red_ret_ocr_felt(
  p_person_id bigint, p_import_key text, p_record_key text, p_felt text,
  p_input_fingerprint text, p_korrigeret jsonb, p_status text DEFAULT 'rettet',
  p_actor_navn text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_source_id bigint; v_anchor_person bigint; v_anchor_count integer; v_person_anchor_count integer;
  v_assertion_id bigint; v_candidate_count integer; v_context text; v_observed jsonb;
  v_journal import_korrektion%ROWTYPE; v_importeret jsonb; v_fingerprint text;
  v_actor_id uuid := auth.uid(); v_actor_navn text; v_result jsonb;
  v_min date; v_max date;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF;
  IF p_felt NOT IN ('navn','foedsel','doed','koen') THEN RAISE EXCEPTION 'OCR_FIELD_INVALID'; END IF;
  IF p_status NOT IN ('rettet','godkendt','udskudt') THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
  IF (p_status='rettet' AND p_korrigeret IS NULL) OR (p_status<>'rettet' AND p_korrigeret IS NOT NULL) THEN
    RAISE EXCEPTION 'OCR_VALUE_INVALID';
  END IF;

  WITH anchor_rows AS (
    SELECT pei.person_id,s.id AS source_id
      FROM source s JOIN person_external_id pei ON pei.source_id=s.id
     WHERE s.import_key=p_import_key AND pei.record_key=p_record_key
     FOR UPDATE OF s,pei
  ) SELECT count(*),min(person_id),min(source_id) INTO v_anchor_count,v_anchor_person,v_source_id
      FROM anchor_rows;
  IF v_anchor_count <> 1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF;
  IF v_anchor_person <> p_person_id THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;
  SELECT count(*) INTO v_person_anchor_count
    FROM person_external_id pei JOIN source s ON s.id=pei.source_id
   WHERE pei.person_id=p_person_id AND s.import_key IS NOT NULL AND pei.record_key IS NOT NULL;
  IF v_person_anchor_count <> 1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF;
  PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;

  IF p_felt='koen' THEN
    SELECT private.ocr_importeret('koen',koen,NULL,NULL,NULL,NULL,NULL,NULL) INTO v_observed
      FROM person WHERE id=p_person_id;
    v_context := NULL;
  ELSE
    WITH candidates AS (
      SELECT DISTINCT a.id
      FROM fact f JOIN conclusion cn ON cn.target_type='fact' AND cn.target_id=f.id
        JOIN assertion a ON a.id=cn.valgt_assertion_id
        JOIN citation c ON c.assertion_id=a.id AND c.source_id=v_source_id
      WHERE f.subjekt_type='person' AND f.subjekt_id=p_person_id AND cn.status='afklaret'
        AND f.faktatype=CASE p_felt WHEN 'navn' THEN 'navn' WHEN 'foedsel' THEN 'fødsel' ELSE 'død' END
    ) SELECT count(*),min(id) INTO v_candidate_count,v_assertion_id FROM candidates;
    IF v_candidate_count <> 1 THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF;
    SELECT private.ocr_importeret(p_felt,a.vaerdi_tekst,a.date_raw,a.date_min,a.date_max,
             a.date_qualifier,a.calendar,a.date_certainty),c.citat_tekst
      INTO v_observed,v_context
      FROM assertion a JOIN citation c ON c.assertion_id=a.id AND c.source_id=v_source_id
     WHERE a.id=v_assertion_id ORDER BY c.id LIMIT 1 FOR UPDATE OF a,c;
    IF NOT FOUND THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF;
  END IF;

  -- A missing journal row has no row lock; serialize its logical key before the upsert.
  PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws(chr(31),p_import_key,p_record_key,p_felt),0));
  SELECT * INTO v_journal FROM import_korrektion
   WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt FOR UPDATE;
  v_importeret := coalesce(v_journal.importeret,v_observed);
  v_fingerprint := private.ocr_fingerprint(p_import_key,p_record_key,p_felt,v_importeret,v_context);
  IF v_journal.id IS NOT NULL AND v_journal.input_fingerprint IS DISTINCT FROM v_fingerprint THEN
    RAISE EXCEPTION 'OCR_FINGERPRINT_STALE';
  END IF;
  IF p_input_fingerprint IS DISTINCT FROM coalesce(v_journal.input_fingerprint,v_fingerprint) THEN
    RAISE EXCEPTION 'OCR_FINGERPRINT_STALE';
  END IF;

  IF p_status='rettet' THEN
    IF jsonb_typeof(p_korrigeret) <> 'object' THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
    IF p_felt='navn' THEN
      IF jsonb_typeof(p_korrigeret->'value') <> 'string' OR nullif(btrim(p_korrigeret->>'value'),'') IS NULL THEN
        RAISE EXCEPTION 'OCR_VALUE_INVALID';
      END IF;
    ELSIF p_felt='koen' THEN
      IF p_korrigeret->>'value' NOT IN ('mand','kvinde','ukendt') THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
    ELSE
      IF jsonb_typeof(p_korrigeret->'raw') <> 'string' OR nullif(btrim(p_korrigeret->>'raw'),'') IS NULL THEN
        RAISE EXCEPTION 'OCR_VALUE_INVALID';
      END IF;
      BEGIN
        v_min := NULLIF(p_korrigeret->>'min','')::date;
        v_max := NULLIF(p_korrigeret->>'max','')::date;
      EXCEPTION WHEN others THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END;
    END IF;
  END IF;

  SELECT coalesce(pr.navn,pr.email,p_actor_navn,v_actor_id::text,'ukendt') INTO v_actor_navn
    FROM profiles pr WHERE pr.id=v_actor_id;
  v_actor_navn := coalesce(v_actor_navn,p_actor_navn,'ukendt');
  PERFORM begin_change_set('red_ret_ocr_felt',format('OCR-%s: %s/%s',p_felt,p_import_key,p_record_key),'person',p_person_id);
  IF p_status='rettet' THEN
    IF p_felt='navn' THEN
      UPDATE assertion SET vaerdi_tekst=p_korrigeret->>'value' WHERE id=v_assertion_id;
    ELSIF p_felt='koen' THEN
      UPDATE person SET koen=p_korrigeret->>'value' WHERE id=p_person_id;
    ELSE
      UPDATE assertion SET date_raw=p_korrigeret->>'raw',date_min=v_min,date_max=v_max,
        date_qualifier=p_korrigeret->>'qualifier',calendar=coalesce(p_korrigeret->>'calendar','gregoriansk'),
        date_certainty=p_korrigeret->>'certainty' WHERE id=v_assertion_id;
    END IF;
  END IF;
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,korrigeret,status,actor_id,actor_navn)
    VALUES (p_import_key,p_record_key,p_felt,v_fingerprint,v_importeret,
      CASE WHEN p_status='rettet' THEN p_korrigeret ELSE NULL END,p_status,v_actor_id,v_actor_navn)
  ON CONFLICT (import_key,record_key,felt) DO UPDATE SET
    input_fingerprint=import_korrektion.input_fingerprint,
    korrigeret=CASE WHEN excluded.status='rettet' THEN excluded.korrigeret ELSE import_korrektion.korrigeret END,
    status=excluded.status,actor_id=excluded.actor_id,
    actor_navn=excluded.actor_navn,opdateret_at=now();
  SELECT to_jsonb(g) INTO v_result FROM red_person_grid() g WHERE g.person_id=p_person_id;
  RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION red_ocr_historik(p_import_key text,p_record_key text,p_felt text)
RETURNS TABLE(change_set_id bigint,changed_at timestamptz,actor_navn text,operation text,foer jsonb,efter jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_journal_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF;
  SELECT id INTO v_journal_id FROM import_korrektion
   WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt;
  IF v_journal_id IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT cs.id,cs.created_at,cs.actor_navn,cs.operation,ce.foer,ce.efter
    FROM change_event ce JOIN change_set cs ON cs.id=ce.change_set_id
   WHERE ce.tabel='import_korrektion' AND ce.row_pk->>'id'=v_journal_id::text
   ORDER BY cs.created_at DESC,cs.id DESC,ce.seq DESC;
END $$;

CREATE TABLE lineage (                   -- SLÆGTSLINJE / GREN (fx Reventlows fem linjer)
  id        BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  source_id BIGINT REFERENCES source(id),  -- hvilken udgaves linje-inddeling
  kode      TEXT,                          -- 'I'..'V' — matcher person_external_id.linje
  navn      TEXT NOT NULL,                 -- 'Den holstenske linje', ...
  -- (b) PROMOVERING (2026-06-30): forgrening + status. Tilføjet additivt; ældre rækker har NULL.
  parent_lineage_id BIGINT REFERENCES lineage(id),  -- forgrening: gren udgår af gren (NULL = rod)
  status    TEXT,                          -- fri tekst, fx 'uddød', 'kendt hul / ikke undersøgt'
  -- families-efternavn ('Reventlow'); NULL = udeledt/ukendt (udledt-slægtsnavn-design). Bevidst en
  -- ren kolonne, IKKE en fact-række (afviger fra invariant 3 "alt er et faktum", som ellers
  -- gælder lineage-attributter som adling/floruit) — lineage_effective_slaegtsnavn() kaldes
  -- rekursivt op ad parent_lineage_id INDE i regen_person_visning's per-person-trigger-sti; en
  -- fact/assertion/conclusion-join i den løkke ville være markant dyrere. Hvis efternavnet en dag
  -- får brug for evidenslag (fx to DAA-udgaver uenige om et grennavn), genovervej dette.
  slaegtsnavn TEXT,
  -- Præsenslistens EGEN, sekventielle nummerering af de nulevende linjer (springer uddøde
  -- linjer over) — IKKE det samme som `kode` (stamtræets faste nummerering). NULL = linjen
  -- indgår ikke i præsenslisten. Redaktør-sat, løbende (ændres i takt med hvem der er levende).
  -- Slås ALDRIG op med fallback til `kode` — det ville kollidere (kode='I' er typisk en anden,
  -- uddød linje). Præsensliste-redesign 2026-07-24.
  presens_kode TEXT,
  UNIQUE (source_id, kode)
  -- Resten af (b) kræver INGEN skema-ændring — den rider på de polymorfe evidens-tabeller:
  --   * fact     subjekt_type='lineage'  → adling, floruit, alternative navne m. evidens
  --   * relation lineage→coat_of_arms / →source / person→lineage (konfidens på medlemskab)
  -- En linje der adles → ny lineage-række + relation rolle='gren_af' til moderlinjen
  --   (parent_lineage_id er den hurtige FK; 'gren_af'-relationen bærer evidens/konfidens).
  -- Jf. datamodel-oversigt §5/§9.
);
-- Fanger dubletter loudly (DB-fejl) i stedet for at lade to linjer stille dele samme
-- præsens-nummer (hvilken af dem der "vinder" ved opslag ville afhænge af rækkefølge).
CREATE UNIQUE INDEX IF NOT EXISTS lineage_presens_kode_uidx ON lineage (presens_kode) WHERE presens_kode IS NOT NULL;

-- SLÆGTS-ROD (2026-07-28): hver slægt har ÉN rod-række (source_id=NULL, kode=NULL,
-- parent_lineage_id=NULL) der bærer slaegtsnavn; udgavens linjer hænger under den via
-- parent_lineage_id og arver navnet gennem lineage_effective_slaegtsnavn(). Roden er en ren
-- beholder: person_external_id joiner på (source_id, kode), som begge er NULL, så den får
-- aldrig medlemmer, og app-lagets linje-liste filtrerer kode-løse rækker fra.
-- UNIQUE (source_id, kode) håndhæver intet for roden (NULL'er er distinkte), så dubletter
-- fanges her i stedet — ellers ville to ophav til samme slægt konkurrere om opslaget.
CREATE UNIQUE INDEX IF NOT EXISTS lineage_slaegtsrod_uidx
  ON lineage (slaegtsnavn) WHERE parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL;

-- ---------- FASE 3: SLÆGT, KANONISK LINEAGE OG KILDESCHEME ----------
-- lineage bevarer foreløbig sine legacy-felter (source_id/kode/presens_kode),
-- mens den nye model adskiller den kanoniske gren fra bogens nummerering.
CREATE TABLE slaegt (
  id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  navn             text NOT NULL CHECK (btrim(navn)<>''),
  sorteringsnavn   text NOT NULL CHECK (btrim(sorteringsnavn)<>''),
  slug             text NOT NULL CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  status           text NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','inactive','historical')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (slug)
);

ALTER TABLE lineage ADD COLUMN IF NOT EXISTS slaegt_id bigint REFERENCES slaegt(id);
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS canonical_label text;
CREATE INDEX IF NOT EXISTS lineage_slaegt_idx ON lineage(slaegt_id);
-- NULL er kun overgangstilstand for gamle loader-rækker. Nye writes skal bruge
-- den nye model; Task 14 flytter loaderen, før den sidste nullable rest lukkes.

CREATE TABLE lineage_scheme (
  id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  slaegt_id        bigint NOT NULL REFERENCES slaegt(id),
  source_id        bigint REFERENCES source(id),
  kind             text NOT NULL CHECK (kind IN ('stamtavle','presensliste','editorial')),
  label            text NOT NULL CHECK (btrim(label)<>''),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (slaegt_id,source_id,kind)
);
CREATE UNIQUE INDEX lineage_scheme_slaegt_kind_no_source_uidx
  ON lineage_scheme(slaegt_id,kind) WHERE source_id IS NULL;

CREATE TABLE lineage_scheme_entry (
  id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  scheme_id        bigint NOT NULL REFERENCES lineage_scheme(id),
  code             text NOT NULL CHECK (btrim(code)<>''),
  label            text NOT NULL CHECK (btrim(label)<>''),
  sort_order       integer NOT NULL CHECK (sort_order>=0),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scheme_id,code),
  UNIQUE (scheme_id,sort_order)
);

CREATE TABLE lineage_scheme_entry_lineage (
  entry_id         bigint NOT NULL REFERENCES lineage_scheme_entry(id),
  lineage_id       bigint NOT NULL REFERENCES lineage(id),
  relation_kind    text NOT NULL CHECK (relation_kind IN ('canonical','historical_alias','source_only')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entry_id,lineage_id,relation_kind)
);

CREATE TABLE person_slaegt_membership (
  person_id        bigint NOT NULL REFERENCES person(id),
  slaegt_id        bigint NOT NULL REFERENCES slaegt(id),
  membership_kind  text NOT NULL CHECK (membership_kind IN ('agnatic','cognatic','adopted','editorial')),
  source_basis     jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(source_basis)='object'),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (person_id,slaegt_id)
);

CREATE TABLE person_lineage_membership (
  person_id        bigint NOT NULL REFERENCES person(id),
  lineage_id       bigint NOT NULL REFERENCES lineage(id),
  role             text NOT NULL CHECK (role IN ('member','founder','claimant')),
  valid_from       date,
  valid_to         date,
  source_basis     jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(source_basis)='object'),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (person_id,lineage_id),
  CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_from<=valid_to)
);

-- Navngivet overgangsprojektion. Den er kun et læselag for de eksisterende
-- kildekoordinater og bliver først evidence-backed efter Task 17/20.
CREATE VIEW person_source_coordinate_legacy
WITH (security_invoker=true) AS
SELECT person_id,source_id,linje AS legacy_line_code,nr AS printed_number,
       slaegtled_lokal AS generation_local,
       slaegtled_gennem AS generation_global,kuld AS kuld_label,
       'legacy_external_id'::text AS provenance_kind
  FROM person_external_id;

CREATE TABLE private.source_record_placement (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_record_id       uuid NOT NULL REFERENCES private.source_record(id),
  scheme_entry_id        bigint NOT NULL REFERENCES public.lineage_scheme_entry(id),
  printed_number         text,
  generation_local       integer CHECK (generation_local>=0),
  generation_global      integer CHECK (generation_global>=0),
  generation_label_raw   text,
  kuld_label             text,
  section_path           text[] NOT NULL DEFAULT ARRAY[]::text[],
  header_observation_id  uuid NOT NULL REFERENCES private.source_observation(id),
  supersedes_placement_id uuid REFERENCES private.source_record_placement(id),
  status                 text NOT NULL DEFAULT 'proposed'
                         CHECK (status IN ('proposed','accepted','superseded')),
  created_at             timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX source_record_placement_active_uidx
  ON private.source_record_placement(source_record_id,scheme_entry_id)
  WHERE status<>'superseded';

CREATE TABLE private.source_persona_placement (
  source_persona_id      uuid NOT NULL REFERENCES private.source_persona(id),
  record_placement_id    uuid NOT NULL REFERENCES private.source_record_placement(id),
  placement_role         text NOT NULL CHECK (placement_role IN (
                         'principal_member','co_principal','mentioned_spouse','child_reference')),
  basis_observation_id   uuid NOT NULL REFERENCES private.source_observation(id),
  status                 text NOT NULL DEFAULT 'proposed'
                         CHECK (status IN ('proposed','accepted','rejected')),
  created_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (source_persona_id,record_placement_id,placement_role)
);

CREATE FUNCTION private.validate_source_record_placement()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_observation o
      JOIN private.source_record_occurrence occurrence ON occurrence.id=o.occurrence_id
     JOIN private.source_record_anchor_current anchor ON anchor.occurrence_id=occurrence.id
     WHERE o.id=NEW.header_observation_id
       AND o.observation_kind='header'
       AND anchor.source_record_id=NEW.source_record_id
       AND anchor.decision_status='accepted'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_HEADER_REQUIRED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM private.source_record record
      JOIN public.lineage_scheme_entry entry ON entry.id=NEW.scheme_entry_id
      JOIN public.lineage_scheme scheme ON scheme.id=entry.scheme_id
     WHERE record.id=NEW.source_record_id
       AND scheme.source_id IS NOT NULL AND scheme.source_id<>record.source_id
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_SOURCE_MISMATCH';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.validate_source_persona_placement()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_persona persona
      JOIN private.source_record_placement placement ON placement.id=NEW.record_placement_id
      JOIN private.source_record record ON record.id=placement.source_record_id
     WHERE persona.id=NEW.source_persona_id AND persona.source_id=record.source_id
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_PLACEMENT_SOURCE_MISMATCH';
  END IF;
  -- En ægtefælle eller anden omtalt persona arver aldrig ukritisk hovedpersonens
  -- placering: dens egen observation skal ligge i den samme accepted record.
  IF NOT EXISTS (
    SELECT 1 FROM private.source_observation observation
      JOIN private.source_record_occurrence occurrence ON occurrence.id=observation.occurrence_id
      JOIN private.source_record_anchor_current anchor ON anchor.occurrence_id=occurrence.id
      JOIN private.source_record_placement placement ON placement.id=NEW.record_placement_id
      JOIN private.source_mention mention ON mention.observation_id=observation.id
      JOIN private.source_persona_mention persona_mention ON persona_mention.mention_id=mention.id
     WHERE observation.id=NEW.basis_observation_id
       AND persona_mention.persona_id=NEW.source_persona_id
       AND anchor.source_record_id=placement.source_record_id
       AND anchor.decision_status='accepted'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_PLACEMENT_BASIS_REQUIRED';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_source_record_placement_validate
  BEFORE INSERT ON private.source_record_placement
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_record_placement();
CREATE TRIGGER trg_source_persona_placement_validate
  BEFORE INSERT ON private.source_persona_placement
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_persona_placement();
CREATE TRIGGER trg_source_record_placement_append_only
  BEFORE UPDATE OR DELETE ON private.source_record_placement
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
CREATE TRIGGER trg_source_persona_placement_append_only
  BEFORE UPDATE OR DELETE ON private.source_persona_placement
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();

ALTER TABLE slaegt ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme_entry_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_slaegt_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_lineage_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_record_placement ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_persona_placement ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE person_slaegt_membership,person_lineage_membership,
                    private.source_record_placement,private.source_persona_placement
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.validate_source_record_placement(),
                           private.validate_source_persona_placement()
  FROM PUBLIC,anon,authenticated;

-- ---------- UDLEDT SLÆGTSNAVN: cyklus-sikre lineage-graf-walkers ----------
-- Bruges BÅDE til skrive-tids cyklus-forebyggelse (BEFORE-trigger nedenfor) OG læse-tids
-- efternavns-opslag/subtræ-regen (docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md
-- §4.7). RAISE EXCEPTION ved cyklus/dybde-overskridelse — trunkerer ALDRIG stille.
CREATE OR REPLACE FUNCTION lineage_ancestors(p_lineage_id BIGINT)
RETURNS BIGINT[] LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_path BIGINT[] := ARRAY[]::BIGINT[];
  v_current BIGINT := p_lineage_id;
BEGIN
  WHILE v_current IS NOT NULL LOOP
    IF v_current = ANY(v_path) THEN
      RAISE EXCEPTION 'lineage_ancestors: cyklus detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_path,1) IS NOT NULL AND array_length(v_path,1) > 50 THEN
      RAISE EXCEPTION 'lineage_ancestors: dybde-grænse (50) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_path := v_path || v_current;
    SELECT parent_lineage_id INTO v_current FROM lineage WHERE id = v_current;
  END LOOP;
  RETURN v_path;
END $$;

CREATE OR REPLACE FUNCTION lineage_descendants(p_lineage_id BIGINT)
RETURNS SETOF BIGINT LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_visited BIGINT[] := ARRAY[]::BIGINT[];
  v_queue BIGINT[] := ARRAY[p_lineage_id];
  v_current BIGINT; v_child BIGINT;
BEGIN
  WHILE array_length(v_queue,1) IS NOT NULL LOOP
    v_current := v_queue[1];
    v_queue := v_queue[2:array_length(v_queue,1)];
    IF v_current = ANY(v_visited) THEN
      RAISE EXCEPTION 'lineage_descendants: cyklus/gen-besøg detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_visited,1) IS NOT NULL AND array_length(v_visited,1) > 500 THEN
      RAISE EXCEPTION 'lineage_descendants: dybde-grænse (500) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_visited := v_visited || v_current;
    RETURN NEXT v_current;
    FOR v_child IN SELECT id FROM lineage WHERE parent_lineage_id = v_current LOOP
      v_queue := v_queue || v_child;
    END LOOP;
  END LOOP;
  RETURN;
END $$;

-- Forebyg cyklus i data: afvis en parent_lineage_id-tildeling der ville lukke en løkke.
CREATE OR REPLACE FUNCTION trg_lineage_prevent_cycle()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.parent_lineage_id IS NOT NULL AND NEW.id = ANY(lineage_ancestors(NEW.parent_lineage_id)) THEN
    RAISE EXCEPTION 'lineage: parent_lineage_id-tildeling ville skabe en cyklus (lineage % → %)', NEW.id, NEW.parent_lineage_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_cycle_guard ON lineage;
CREATE TRIGGER trg_lineage_cycle_guard
  BEFORE INSERT OR UPDATE OF parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_lineage_prevent_cycle();

-- Personens effektive families-efternavn for én linje: linjen selv, ellers gå op ad
-- parent_lineage_id til første ikke-NULL slaegtsnavn (spec §4.1).
CREATE OR REPLACE FUNCTION lineage_effective_slaegtsnavn(p_lineage_id BIGINT)
RETURNS TEXT LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT l.slaegtsnavn
  FROM unnest(lineage_ancestors(p_lineage_id)) WITH ORDINALITY AS anc(id, ord)
  JOIN lineage l ON l.id = anc.id
  WHERE l.slaegtsnavn IS NOT NULL
  ORDER BY anc.ord
  LIMIT 1;
$$;

-- ---------- UDLEDT SLÆGTSNAVN: normalisering + suffiks-token-match (spec §4.6) ----------
CREATE OR REPLACE FUNCTION slaegtsnavn_normaliser(s TEXT)
RETURNS TEXT[] LANGUAGE sql IMMUTABLE SET search_path=public AS $$
  SELECT regexp_split_to_array(
    trim(regexp_replace(regexp_replace(lower(s), '[‐‑–]', '-', 'g'), '\s+', ' ', 'g')),
    '\s+'
  );
$$;

-- Suffiks-token-sekvens-match: navnets AFSLUTTENDE tokens == efternavnets tokens. Dækker
-- fler-ords-efternavne ("von Brockdorff") og undgår falsk skip når efternavnet er et mellemnavn.
CREATE OR REPLACE FUNCTION slaegtsnavn_suffiks_match(navn TEXT, slaegtsnavn TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE n_tokens TEXT[]; s_tokens TEXT[]; n_len INT; s_len INT;
BEGIN
  IF navn IS NULL OR slaegtsnavn IS NULL THEN RETURN FALSE; END IF;
  n_tokens := slaegtsnavn_normaliser(navn);
  s_tokens := slaegtsnavn_normaliser(slaegtsnavn);
  n_len := coalesce(array_length(n_tokens,1),0);
  s_len := coalesce(array_length(s_tokens,1),0);
  IF s_len = 0 OR n_len < s_len THEN RETURN FALSE; END IF;
  RETURN n_tokens[n_len - s_len + 1 : n_len] = s_tokens;
END $$;

-- Tvetydig-karantæne (spec §4.5/§4.8): personer med >1 distinkt effektivt efternavn på tværs af
-- deres linje-medlemskaber. Idempotent (upsert pr. person_id) — selv-helbreder hvis tvetydigheden
-- forsvinder (rækken slettes af regen_person_visning).
CREATE TABLE IF NOT EXISTS slaegtsnavn_karantaene (
  person_id  BIGINT PRIMARY KEY REFERENCES person(id),
  n_distinct INT NOT NULL,
  noteret_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- AUTH / REDAKTION ----------
CREATE TABLE profiles (              -- 1:1 med auth.users; bærer rolle + binding til træet
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  rolle               TEXT NOT NULL DEFAULT 'medlem'
                        CHECK (rolle IN ('redaktion','medlem')),
  reventlow_person_id BIGINT REFERENCES person(id),
  email               TEXT
);

CREATE TABLE suggestion (            -- staging: ikke-redaktion-forslag (manuelt re-anvendt)
  id              BIGINT PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  forslagsstiller UUID REFERENCES auth.users(id),
  status          TEXT NOT NULL DEFAULT 'afventer',  -- PoC: kun 'afventer'
  art             TEXT,
  subjekt_type    TEXT, subjekt_id BIGINT,
  felt            TEXT, vaerdi TEXT,
  kilde_source_id BIGINT REFERENCES source(id),
  kilde_fritekst  TEXT,
  payload         JSONB DEFAULT '{}'::jsonb,
  note            TEXT
);
-- RLS slås til ved oprettelse (deny-all indtil politikker + grants lander i db-rls.sql).
ALTER TABLE profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE suggestion ENABLE ROW LEVEL SECURITY;

CREATE TABLE bookmark (              -- login-eksklusive bogmærker (kun personer), spec 2026-07-06
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  oprettet  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, person_id)
);
ALTER TABLE bookmark ENABLE ROW LEVEL SECURITY;

CREATE TABLE family (                    -- union/partnerskab
  id   BIGINT PRIMARY KEY,
  type TEXT                              -- 'vielse','partnerskab','ugift union'
);

CREATE TABLE family_member (             -- FAMC/FAMS: person i familie med rolle
  family_id BIGINT REFERENCES family(id),
  person_id BIGINT REFERENCES person(id),
  rolle     TEXT NOT NULL,               -- 'partner' | 'barn' | 'adopteret_barn' | 'plejebarn' | 'stedbarn'
                                         --   (barn-subtyper afgør blodslægtskab: kun 'barn' tæller genetisk i finderen; jf. TNG frel/mrel)
  ordinal   INTEGER,                     -- ægteskab 1°/2° for partner
  konfidens TEXT,                        -- 'sikker'|'sandsynlig'|'formodet'|'omstridt' (NULL = uangivet). Omstridte hypoteser med kilder ligger i evidenslaget.
  PRIMARY KEY (family_id, person_id, rolle),
  -- Grafinvariant (Problem 2): højst ÉN fødselsfamilie ('barn'-række) pr. person — lukker "to
  -- modstridende fædre" for ALLE skrive-veje. DEFERRABLE er nødvendig for undo/restore-replay:
  -- red_fortryd_change_set genafspiller versions-events i én transaktion, hvor rækkefølgen kan
  -- have en midlertidig dublet før commit (red_flyt_barn selv er delete-før-insert og rammer det
  -- ikke, men behold DEFERRABLE — ellers knækker restore). NB: ON CONFLICT kan ikke bruge en
  -- deferrable constraint som arbiter → INSERT INTO family_member skal være plain (loaderne er det).
  CONSTRAINT family_member_en_foedselsfamilie
    EXCLUDE USING btree (person_id WITH =) WHERE (rolle = 'barn') DEFERRABLE INITIALLY DEFERRED
);

-- ---------- FAKTA (events/attributter) ----------
CREATE TABLE fact (                      -- "slot": ét forhold om en person/familie
  id           BIGINT PRIMARY KEY,
  subjekt_type TEXT NOT NULL,            -- enhver entitet: 'person','family','place','estate','coat_of_arms' ...
  subjekt_id   BIGINT NOT NULL,
  faktatype    TEXT NOT NULL,            -- 'navn','tilnavn','fødsel','død','floruit','erhverv','titel','dødsårsag'...
  sted_id      BIGINT REFERENCES place(id)
);
-- BEVIDST INGEN ekstra kolonner her (jf. invariant #2 — genbrug mekanismer):
--   * dødsårsag  = eget fact ('dødsårsag') hvor det bærer vægt; ellers narrative/note.
--   * alder-ved-hændelse = udledes af datoer, gemmes ikke separat.
--   * "hvem udførte" (præst v. dåb, monark v. tildeling) = relation (person/org -> fact, rolle 'udførte').
--   * media-ejer / nuværende placering = relation ('ejer' / 'placeret_på' -> ejendom/sted), ikke kolonne på media.

-- ---------- GENERISK RELATION ----------
CREATE TABLE relation (
  id            BIGINT PRIMARY KEY,
  subjekt_type  TEXT NOT NULL,           -- polymorf
  subjekt_id    BIGINT NOT NULL,
  objekt_type   TEXT NOT NULL,           -- polymorf (estate, organisation, media, event, coa, person ...)
  objekt_id     BIGINT NOT NULL,
  rolle         TEXT NOT NULL,           -- 'ejer','afbildet','skabt_af','forfatter','m.a.','deltager'...
  erhvervelsesmaade TEXT,                -- 'født/arvet','tildelt','knyttet_til_ejendom'
  start_min DATE, start_max DATE,        -- fuzzy periode
  end_min   DATE, end_max   DATE,
  period_type TEXT,                      -- 'closed','open_start','open_end','ongoing','floruit','until_event'
  periode_raw TEXT,
  konfidens   TEXT,
  kvalifikator jsonb                     -- fase 4: rolle-kvalifikation, fx {"primaer":true} (portræt-valg, M10); generisk pr. plan Slice 3 — deles med fremtidig region-tagging (bbox) uden ny DDL
);
CREATE UNIQUE INDEX IF NOT EXISTS relation_afbildet_uidx
  ON relation (subjekt_type, subjekt_id, objekt_type, objekt_id)
  WHERE rolle='afbildet';

-- ---------- EVIDENS: PÅSTAND / KONKLUSION / CITATION ----------
CREATE TABLE assertion (                 -- én kildes udsagn om et FACT ELLER en RELATION
  id             BIGINT PRIMARY KEY,
  target_type    TEXT NOT NULL,          -- 'fact' | 'relation'
  target_id      BIGINT NOT NULL,
  vaerdi_tekst   TEXT,                   -- navn, erhverv, titel, stednavn ...
  objekt_type    TEXT,                   -- en påstands VÆRDI kan være en entitet (fx forældrefamilie); polymorf, NULL for tekst-/dato-påstande
  objekt_id      BIGINT,                 -- den påståede entitets id (v1: en family). Ingen hård FK (polymorf-konvention); valideres i RPC
  date_min DATE, date_max DATE,          -- hvis dato-værdi (fuzzy); date_min NULL = åben mod fortiden ('før'), date_max NULL = åben mod fremtiden ('efter')
  date_qualifier TEXT,                   -- RELATION dato↔begivenhed: 'exact','before','after','between','about','floruit','until_event','open_end','ongoing'
  date_certainty TEXT CONSTRAINT assertion_date_certainty_chk CHECK (date_certainty IN ('certain','uncertain','ambiguous')),  -- LÆSE-sikkerhed (ortogonal til qualifier): 'uncertain'=kilden tvivler selv ('147(5?)'), 'ambiguous'=flere lige gyldige tolkninger; NULL=ikke vurderet (≈certain). Navn matcher db-migrations.sql så frisk-build + migration ikke giver duplikat-constraint
  date_raw       TEXT,                   -- oprindelig tekst, fx '† før 1261 (22. aug.)'
  calendar       TEXT DEFAULT 'gregoriansk',  -- 'gregoriansk'|'juliansk'; sat af parseren når en kirkelig mærkedag/juliansk dato er konverteret (revisionssikkerhed)
  uforanderlig   BOOLEAN DEFAULT TRUE
);

CREATE TABLE conclusion (                -- den blåstemplede vurdering ovenpå påstandene
  id                BIGINT PRIMARY KEY,
  target_type       TEXT NOT NULL,       -- 'fact' | 'relation'
  target_id         BIGINT NOT NULL,
  valgt_assertion_id BIGINT REFERENCES assertion(id),
  status            TEXT,                -- 'afklaret','omstridt','forældet'
  blaastemplet_af   TEXT,                -- udgave eller beslutning (proveniens)
  blaastemplet_naar DATE,
  UNIQUE (target_type, target_id)
);

CREATE TABLE citation (
  id           BIGINT PRIMARY KEY,
  assertion_id BIGINT REFERENCES assertion(id),
  source_id    BIGINT REFERENCES source(id),
  side         TEXT,
  citat_tekst  TEXT,                     -- ordret transskriberet kildeuddrag (TNG: citetext) — bevarer det kilden faktisk skriver
  citat_dato   TEXT,                     -- rå dato for citatet/optegnelsen (TNG: citedate)
  kvalitet     TEXT                      -- 'primær','sekundær','tvivlsom' (TNG QUAY 0-3 mapper hertil)
);

-- ---------- TVÆRGÅENDE ----------
CREATE TABLE note (
  id          BIGINT PRIMARY KEY,
  target_type TEXT NOT NULL,             -- polymorf: 'person','family','fact','relation',... (en note kan hænge på ét faktum, jf. TNG notelinks.eventID)
  target_id   BIGINT NOT NULL,
  indhold     TEXT,
  privat      BOOLEAN DEFAULT FALSE      -- GDPR: skjult note (TNG: notelinks.secret)
);

CREATE TABLE narrative (          -- bevaret biografisk prosa (substrat); fakta udtrækkes selektivt ovenpå
  id           BIGINT PRIMARY KEY,
  subjekt_type TEXT NOT NULL,     -- 'person' | 'family' | 'line' ...
  subjekt_id   BIGINT NOT NULL,
  source_id    BIGINT REFERENCES source(id),
  side         TEXT,              -- fx '209-211'
  tekst        TEXT NOT NULL,
  privat       BOOLEAN DEFAULT FALSE   -- GDPR: skjult narrativ (levende-biografi); jf. TNG secret-flag
);

-- FORMIDLINGSLAG (levende-feed fase 2): dateret hændelse fundet i et narrativ.
-- Regenererbar envejs-projektion af prosaen; bærer ingen assertion/conclusion.
-- Kun feed_status er en varig redaktionel dom og bevares ved regenerering.
CREATE TABLE haendelse (
  id             BIGINT PRIMARY KEY,
  subjekt_type   TEXT NOT NULL,
  subjekt_id     BIGINT NOT NULL,
  narrative_id   BIGINT NOT NULL REFERENCES narrative(id) ON DELETE CASCADE,
  noegle         TEXT NOT NULL,
  span_start     INTEGER,
  span_laengde   INTEGER,
  klausul        TEXT NOT NULL,
  kategori       TEXT,
  date_min       DATE,
  date_max       DATE,
  date_qualifier TEXT,
  date_raw       TEXT,
  feed_status    TEXT NOT NULL DEFAULT 'kandidat'
                   CHECK (feed_status IN ('kandidat','interessant','skjult')),
  fact_id        BIGINT REFERENCES fact(id),
  relation_id    BIGINT REFERENCES relation(id),
  pass_version   TEXT,
  UNIQUE (narrative_id, noegle)
);
CREATE INDEX ix_haendelse_subjekt   ON haendelse(subjekt_type, subjekt_id);
CREATE INDEX ix_haendelse_narrative ON haendelse(narrative_id);

INSERT INTO vocab (scheme, code, label) VALUES
  ('haendelse_feed_status','kandidat',   'Umarkeret — må vises som arkiv-kort'),
  ('haendelse_feed_status','interessant','Redaktørens dom: godt feed-stof (boostes)'),
  ('haendelse_feed_status','skjult',     'Aldrig i feed'),
  ('haendelse_kategori','embede',       'Embede/udnævnelse'),
  ('haendelse_kategori','uddannelse',   'Uddannelse/immatrikulation'),
  ('haendelse_kategori','rejse',        'Rejse/udlandsophold'),
  ('haendelse_kategori','krig',         'Krig/militær tjeneste'),
  ('haendelse_kategori','ejendom',      'Ejendom/køb/salg/arv'),
  ('haendelse_kategori','kirke',        'Kirke/kloster/gejstligt'),
  ('haendelse_kategori','hof',          'Hof/ceremoni/hyldning'),
  ('haendelse_kategori','familie',      'Familiebegivenhed'),
  ('haendelse_kategori','personligt',   'Personligt/øvrigt dateret'),
  ('haendelse_kategori','andet',        'Andet')
ON CONFLICT (scheme, code) DO NOTHING;

-- FORMIDLINGSLAG (feed-koncept §3.2): redaktionel minihistorie. ÆGTE redaktionelt
-- indhold (modsat haendelse: IKKE en regenererbar projektion) — versioneres derfor
-- på de rigtige kolonner (fase3-spec §3.7). Bærer INGEN assertion/conclusion og
-- konkurrerer aldrig med evidenslaget; historien FORMIDLER, kilderne står i story_kilde.
CREATE TABLE IF NOT EXISTS story (
  id                  BIGINT PRIMARY KEY,
  subjekt_type        TEXT NOT NULL,
  subjekt_id          BIGINT NOT NULL,
  -- Alle ankre er valgfrie og nulstilles ved sletning: redaktionelt indhold overlever sit anker.
  haendelse_id        BIGINT REFERENCES haendelse(id) ON DELETE SET NULL,
  fact_id             BIGINT REFERENCES fact(id) ON DELETE SET NULL,
  relation_id         BIGINT REFERENCES relation(id) ON DELETE SET NULL,
  historical_event_id BIGINT REFERENCES historical_event(id) ON DELETE SET NULL,
  titel               TEXT,
  tekst               TEXT NOT NULL,
  date_min            DATE,
  date_max            DATE,
  date_qualifier      TEXT,
  date_raw            TEXT,
  status              TEXT NOT NULL DEFAULT 'kladde'
                        CHECK (status IN ('kladde','klar','publiceret','arkiveret')),
  publiceret_dato     DATE,
  oprindelse          TEXT NOT NULL DEFAULT 'redaktoer'
                        CHECK (oprindelse IN ('redaktoer','llm_assisteret')),
  llm_model           TEXT,
  llm_promptversion   TEXT,
  llm_naar            TIMESTAMPTZ,
  skabt_af            UUID NOT NULL DEFAULT auth.uid(),
  godkendt_af         UUID,
  godkendt_naar       TIMESTAMPTZ,
  privat              BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS ix_story_subjekt   ON story(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_story_haendelse ON story(haendelse_id);
CREATE INDEX IF NOT EXISTS ix_story_status    ON story(status);

-- Historien viser altid sine kilder (koncept §3.2 — "transparens er tonen").
CREATE TABLE IF NOT EXISTS story_kilde (
  id        BIGINT PRIMARY KEY,
  story_id  BIGINT NOT NULL REFERENCES story(id) ON DELETE CASCADE,
  source_id BIGINT NOT NULL REFERENCES source(id),
  side      TEXT
);
CREATE INDEX IF NOT EXISTS ix_story_kilde_story ON story_kilde(story_id);

-- Redaktionel kurering af konkrete, stabile feed-kort: pin øverst eller skjul.
-- En afgørelse bærer ingen PII og er derfor offentligt læsbar gennem RLS-laget.
CREATE TABLE IF NOT EXISTS feed_pin (
  id            BIGINT PRIMARY KEY,
  kort_noegle   TEXT NOT NULL UNIQUE,
  handling      TEXT NOT NULL CHECK (handling IN ('pin','skjul')),
  oprettet_af   UUID NOT NULL DEFAULT auth.uid(),
  oprettet_naar TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO vocab (scheme, code, label) VALUES
  ('story_status','kladde',     'Under udarbejdelse — kun redaktion'),
  ('story_status','klar',       'Færdigskrevet, ikke publiceret'),
  ('story_status','publiceret', 'Synlig i feed for publikum'),
  ('story_status','arkiveret',  'Trukket tilbage — den normale slette-vej'),
  ('story_oprindelse','redaktoer',      'Redaktørskrevet'),
  ('story_oprindelse','llm_assisteret', 'LLM-kladde, menneskeligt godkendt (fase 4)')
ON CONFLICT (scheme, code) DO NOTHING;

-- Præsensliste: linje-/gren-overhoved udpeges som redaktionelt fakta (spec
-- docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md §4).
-- Værdi-format: '<ROMERTAL> linje' eller '<ROMERTAL> linje, <N>. gren' — fx 'II linje, 1. gren'.
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','overhoved','Linje-/gren-overhoved — anker for præsenslisten')
ON CONFLICT (scheme, code) DO NOTHING;

-- ---------- CACHE-REGENERERING & TRIGGERS ----------
-- Recompute cache-felter fra personens konklusioner. Læser den VALGTE assertions værdi
-- pr. faktatype. Dato-fakta (fødsel/død) bruger coalesce(date_raw, vaerdi_tekst).
-- Udvidet (udledt-slægtsnavn-design §4.5) til også at sætte visning_efternavn/visning_fuldt_navn.
-- Efternavn-opslaget er fan-out-sikkert: LATERAL sikrer ÉN lineage_effective_slaegtsnavn-kald pr.
-- linje-medlemskab (fremfor to — én for count(DISTINCT), én for min() — som i den oprindelige
-- CTE-form), og resultatet genbruges BÅDE i UPDATE'ets CASE-logik og karantæne-tjekket nedenfor i
-- stedet for at gen-joine person_external_id/lineage en ekstra gang (/simplify-fund, review 19).
CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_n_distinct INT; v_slaegtsnavn TEXT;
BEGIN
  SELECT count(DISTINCT sn.v), min(sn.v) INTO v_n_distinct, v_slaegtsnavn
  FROM person_external_id pei
  JOIN lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
  CROSS JOIN LATERAL (SELECT lineage_effective_slaegtsnavn(l.id) AS v) sn
  WHERE pei.person_id = pid;

  WITH navn_agg AS (
    SELECT
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')  AS navn,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='fødsel') AS foedt,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='død')    AS doed,
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='titel') AS titel
    FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN assertion  a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.subjekt_id = pid
  ),
  final AS (
    SELECT
      navn_agg.navn, navn_agg.foedt, navn_agg.doed, navn_agg.titel,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(v_n_distinct,0) <> 1 THEN NULL
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, v_slaegtsnavn) THEN NULL
        ELSE v_slaegtsnavn
      END AS efternavn,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(v_n_distinct,0) <> 1 THEN navn_agg.navn
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, v_slaegtsnavn) THEN navn_agg.navn
        ELSE navn_agg.navn || ' ' || v_slaegtsnavn
      END AS fuldt
    FROM navn_agg
  )
  UPDATE person p SET
    visning_navn = final.navn, visning_foedt = final.foedt, visning_doed = final.doed,
    visning_titel = final.titel, visning_efternavn = final.efternavn, visning_fuldt_navn = final.fuldt
  FROM final
  WHERE p.id = pid
    AND (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn, p.visning_fuldt_navn)
        IS DISTINCT FROM (final.navn, final.foedt, final.doed, final.titel, final.efternavn, final.fuldt);

  IF v_n_distinct > 1 THEN
    INSERT INTO slaegtsnavn_karantaene(person_id, n_distinct) VALUES (pid, v_n_distinct)
      ON CONFLICT (person_id) DO UPDATE SET n_distinct=excluded.n_distinct, noteret_at=now();
  ELSE
    DELETE FROM slaegtsnavn_karantaene WHERE person_id = pid;  -- selv-helbred hvis tvetydigheden er løst
  END IF;
END $$;

-- Trigger-wrapper: udled berørt person fra conclusion-rækkens fact-target.
CREATE OR REPLACE FUNCTION trg_regen_from_conclusion()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE pid BIGINT;
BEGIN
  SELECT f.subjekt_id INTO pid FROM fact f
    WHERE f.id = coalesce(NEW.target_id, OLD.target_id)
      AND coalesce(NEW.target_type, OLD.target_type)='fact'
      AND f.subjekt_type='person';
  IF pid IS NOT NULL THEN PERFORM regen_person_visning(pid); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_conclusion_regen ON conclusion;
CREATE TRIGGER trg_conclusion_regen
  AFTER INSERT OR UPDATE OR DELETE ON conclusion
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_conclusion();

-- Edits af den VALGTE assertion ændrer cache-værdien uden at conclusion-rækken røres.
CREATE OR REPLACE FUNCTION trg_regen_from_assertion()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE pid BIGINT;
BEGIN
  SELECT f.subjekt_id INTO pid FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    WHERE c.valgt_assertion_id = NEW.id AND f.subjekt_type='person';
  IF pid IS NOT NULL THEN PERFORM regen_person_visning(pid); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_assertion_regen ON assertion;
CREATE TRIGGER trg_assertion_regen
  AFTER UPDATE ON assertion
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_assertion();

-- Udledt-slægtsnavn-invalidation (spec §4.7): linje-medlemskab (person_external_id) og
-- linje-efternavn/-forgrening (lineage) er BEGGE input til visning_efternavn/visning_fuldt_navn,
-- så begge skal trigge regen — "selv-heling ved næste konklusions-edit" er ikke konsistens nok.
CREATE OR REPLACE FUNCTION trg_regen_from_external_id()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN PERFORM regen_person_visning(NEW.person_id); END IF;
  IF TG_OP IN ('DELETE','UPDATE') THEN PERFORM regen_person_visning(OLD.person_id); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_external_id_regen ON person_external_id;
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR DELETE OR UPDATE OF person_id, source_id, linje, nr ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();

-- lineage.slaegtsnavn/parent_lineage_id-ændring (ELLER en frisk INSERT — review 19 H1: en fri
-- --force-reset-genindlæsning opretter lineage-rækkerne FØRSTE gang via INSERT, og uden INSERT i
-- trigger-betingelsen forbliver alle medlemmers cache stille NULL indtil en manuel sweep) regenererer
-- HELE det berørte undertræs medlemmer (lineage_descendants — samme cyklus-sikre walker som
-- skrive-tids cyklus-forebyggelsen). OLD findes ikke ved INSERT — TG_OP tjekkes derfor FØRST.
CREATE OR REPLACE FUNCTION trg_regen_from_lineage()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_lid BIGINT; v_pid BIGINT;
BEGIN
  IF TG_OP = 'INSERT' OR (NEW.slaegtsnavn IS DISTINCT FROM OLD.slaegtsnavn) OR (NEW.parent_lineage_id IS DISTINCT FROM OLD.parent_lineage_id) THEN
    FOR v_lid IN SELECT * FROM lineage_descendants(NEW.id) LOOP
      FOR v_pid IN
        SELECT DISTINCT pei.person_id FROM person_external_id pei
        JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
        WHERE l.id = v_lid
      LOOP
        PERFORM regen_person_visning(v_pid);
      END LOOP;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_regen ON lineage;
CREATE TRIGGER trg_lineage_regen
  AFTER INSERT OR UPDATE OF slaegtsnavn, parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_lineage();

-- ---------- REDAKTIONS-RPC'ER (Task 3) ----------

-- Kalderens rolle (default 'medlem' hvis ingen profil). STABLE; bruger auth.uid().
CREATE OR REPLACE FUNCTION current_rolle()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT coalesce((SELECT rolle FROM profiles WHERE id = auth.uid()), 'medlem');
$$;

-- Tilføj/opdater en oplysning på et fact-slot. Find-or-create fact → assertion →
-- citation → upsert conclusion (peg på den nye assertion). Atomisk (én funktion = én txn).
-- PoC: kilde er fritekst (source_id null, teksten i citat_tekst). Proper source-link senere.
-- Note (id-tildeling): HISTORISK brugte basen eksplicitte BIGINT-PK'er med `max(id)+1` —
-- læs-så-skriv-racen er fjernet 2026-07-31 (db-migrations: IDENTITY Del 1+2): alle bigint-id-
-- tabeller har nu GENERATED BY DEFAULT AS IDENTITY, og RPC'ernes nyeste definitioner
-- (i db-migrations.sql) indsætter via DEFAULT. Funktionerne NEDENFOR i denne fil er ældre
-- versioner der overskrives af migrations-laget ved deploy (schema + migrations køres altid
-- sammen). Loaderen må fortsat sætte eksplicitte id'er, men skal synce sekvenserne bagefter
-- (load_daa.R sekvens-sync før commit). Oprindelig note: derfor `max(id)+1`
-- inde i funktionen. Det er race-følsomt under samtidighed, men acceptabelt i PoC (én redaktør).
-- Migrér til IDENTITY/sekvenser når flerbruger-skrivning aktiveres.
CREATE OR REPLACE FUNCTION red_upsert_fakta(
  p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint; v_concl bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må skrive fakta (din rolle: %)', current_rolle();
  END IF;
  IF p_faktatype = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand / red_vaelg_foraeldre til forældrefamilie';
  END IF;
  PERFORM begin_change_set('red_upsert_fakta', format('Opdaterede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);

  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND faktatype=p_faktatype
    LIMIT 1;
  IF v_fact IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
      RETURNING id INTO v_fact;
  END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;

  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret',
                  blaastemplet_af='Redaktør', blaastemplet_naar=current_date
    RETURNING id INTO v_concl;

  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,
                            'citation_id',v_cit,'conclusion_id',v_concl);
END $$;

-- Operation A: tilføj en OPLYSNING (assertion + citation) til et EKSISTERENDE fact.
-- Rører IKKE conclusion — den nye oplysning er en kandidat; vælg den med red_set_konklusion.
-- (fact-kardinalitet: per-kort "+ tilføj oplysning" målretter dette specifikke fact.)
CREATE OR REPLACE FUNCTION red_tilfoej_oplysning(
  p_fact_id bigint, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF (SELECT faktatype FROM fact WHERE id=p_fact_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand til forældrefamilie-slottet';
  END IF;
  PERFORM begin_change_set('red_tilfoej_oplysning', format('Tilføjede oplysning til fakta %s', p_fact_id), NULL, NULL);
  IF NOT EXISTS (SELECT 1 FROM fact WHERE id = p_fact_id) THEN
    RAISE EXCEPTION 'Fact % findes ikke', p_fact_id;
  END IF;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', p_fact_id, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  RETURN jsonb_build_object('assertion_id', v_assert, 'citation_id', v_cit);
END $$;

-- Operation B: opret et NYT distinkt fact (+ assertion + citation + conclusion). ALTID nyt
-- (modsat red_upsert_fakta's find-or-create) → tillader flere facts pr. faktatype (fx ny titel).
CREATE OR REPLACE FUNCTION red_opret_fakta(
  p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_faktatype = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand / red_vaelg_foraeldre til forældrefamilie';
  END IF;
  PERFORM begin_change_set('red_opret_fakta', format('Oprettede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
    RETURNING id INTO v_fact;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date);
  RETURN jsonb_build_object('fact_id', v_fact, 'assertion_id', v_assert, 'citation_id', v_cit);
END $$;

-- "Gør til konklusion": re-peg conclusion for assertionens fact til denne assertion.
CREATE OR REPLACE FUNCTION red_set_konklusion(p_assertion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_target_type text; v_target_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets konklusion vælges kun via red_vaelg_foraeldre (bevarer projektion/invariant P1)';
  END IF;
  PERFORM begin_change_set('red_set_konklusion', format('Satte konklusion til oplysning %s', p_assertion_id), NULL, NULL);
  SELECT target_type, target_id INTO v_target_type, v_target_id
    FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;
  -- Cycle 02: upsert frem for UPDATE — et fact m. assertions men ingen conclusion (importeret/
  -- delvist) ville ellers give silent no-op (0 rækker) + falsk success.
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_target_type, v_target_id, p_assertion_id,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id = excluded.valgt_assertion_id, blaastemplet_naar = current_date;
END $$;

-- PoC blød redigering: UPDATE assertion direkte (indkapslet — skift til insert-ny senere).
-- Append-baseret edit: bevarer den gamle påstand (invariant #1), opretter ny + re-peger
-- konklusion via INTERN logik (ikke red_set_konklusion-RPC → undgår nested change_set, B7).
-- void → jsonb: kræver DROP FUNCTION før CREATE i db-migrations.sql.
CREATE OR REPLACE FUNCTION red_edit_oplysning(
  p_assertion_id bigint, p_vaerdi text, p_date_raw text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old assertion; v_new bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets påstande redigeres ikke (uforanderlige) — brug red_tilfoej_foraeldre_paastand';
  END IF;
  PERFORM begin_change_set('red_edit_oplysning', format('Rettede oplysning %s', p_assertion_id), NULL, NULL);
  SELECT * INTO v_old FROM assertion WHERE id=p_assertion_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, date_min, date_max,
                        date_qualifier, date_raw, calendar, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), v_old.target_type, v_old.target_id,
            p_vaerdi, v_old.date_min, v_old.date_max, v_old.date_qualifier,
            coalesce(p_date_raw, v_old.date_raw), v_old.calendar, false)
    RETURNING id INTO v_new;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_new, NULL,
            coalesce(p_kilde_fritekst, '(kilde mangler)'))
    RETURNING id INTO v_cit;

  -- intern re-peg (ikke RPC): kun hvis den gamle påstand var den valgte
  UPDATE conclusion SET valgt_assertion_id=v_new, blaastemplet_naar=current_date
    WHERE target_type=v_old.target_type AND target_id=v_old.target_id
      AND valgt_assertion_id=p_assertion_id;
  IF NOT FOUND THEN
    INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_old.target_type, v_old.target_id,
              v_new, 'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id) DO UPDATE SET valgt_assertion_id=v_new, blaastemplet_naar=current_date;
  END IF;

  RETURN jsonb_build_object('ny_assertion_id', v_new, 'citation_id', v_cit);
END $$;

-- PoC blød sletning: DELETE assertion; var den valgt → re-peg konklusion til første
-- tilbageværende oplysning på samme fact (fact-slot bevares).
CREATE OR REPLACE FUNCTION red_slet_oplysning(p_assertion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_target_type text; v_target_id bigint; v_was_chosen boolean; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets påstande slettes ikke (uforanderlige) — skift kanonisk valg med red_vaelg_foraeldre';
  END IF;
  PERFORM begin_change_set('red_slet_oplysning', format('Slettede oplysning %s', p_assertion_id), NULL, NULL);
  SELECT target_type, target_id INTO v_target_type, v_target_id
    FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RETURN; END IF;
  SELECT (valgt_assertion_id = p_assertion_id) INTO v_was_chosen
    FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
  -- VIGTIGT: slip FK'en (conclusion.valgt_assertion_id -> assertion.id) FØR assertion slettes,
  -- ellers fejler DELETE med conclusion_valgt_assertion_id_fkey. Re-peg til første tilbageværende
  -- oplysning (ekskl. den der slettes); ingen tilbage -> drop conclusion. Fact-slot bevares.
  IF coalesce(v_was_chosen,false) THEN
    SELECT id INTO v_next FROM assertion
      WHERE target_type=v_target_type AND target_id=v_target_id AND id <> p_assertion_id
      ORDER BY id LIMIT 1;
    IF v_next IS NULL THEN
      DELETE FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
    ELSE
      UPDATE conclusion SET valgt_assertion_id=v_next
        WHERE target_type=v_target_type AND target_id=v_target_id;
    END IF;
  END IF;
  DELETE FROM citation  WHERE assertion_id = p_assertion_id;
  DELETE FROM assertion WHERE id = p_assertion_id;
END $$;

-- Tilbagetræk HELE et fakta-slots konklusion (fx en "forældre ukendt"-markering): sæt status
-- 'afklaret' → 'tilbagetrukket'. Append-sikkert (påstande røres ikke, invariant #1); læse-gates
-- kræver status='afklaret', så markeringen holder op med at projicere. Re-markering via
-- red_upsert_fakta re-aktiverer (ON CONFLICT → status='afklaret', peger på en frisk påstand).
-- VIGTIGT — hvorfor ikke red_slet_oplysning: den re-peger konklusionen til den ÆLDSTE tilbage-
-- værende påstand på fact'et. Efter Markér → Opdatér (to påstande) → Fjern ville den derfor
-- genoplive den oprindelige markering i stedet for at fjerne den. Retract undgår det (og hele
-- FK-slette-dansen). Fortrydbar (change_set; conclusion er versions-sporet).
CREATE OR REPLACE FUNCTION red_tilbagetraek_fakta(p_fact_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Fail-closed FØR change_set åbnes: intet at tilbagetrække (forkert/tilbagetrukket/ikke-eksisterende
  -- fakta, eller p_fact_id NULL/NaN-serialiseret) → ærlig fejl frem for tomt change_set + falsk succes
  -- (review 27/Codex MEDIUM). Ellers ville et dobbeltklik eller stale id rapportere OK uden effekt.
  IF NOT EXISTS (SELECT 1 FROM conclusion
                 WHERE target_type='fact' AND target_id=p_fact_id AND status='afklaret') THEN
    RAISE EXCEPTION 'Ingen aktiv markering at tilbagetrække på fakta %', p_fact_id;
  END IF;
  PERFORM begin_change_set('red_tilbagetraek_fakta', format('Tilbagetrak markering på fakta %s', p_fact_id), NULL, NULL);
  UPDATE conclusion SET status='tilbagetrukket', blaastemplet_naar=current_date
    WHERE target_type='fact' AND target_id=p_fact_id AND status='afklaret';
END $$;

-- ---------- INDEKSER (relations-/evidens-opslag; UI + traversal) ----------
CREATE INDEX IF NOT EXISTS ix_fammember_person   ON family_member(person_id);
CREATE INDEX IF NOT EXISTS ix_fammember_family   ON family_member(family_id);
CREATE INDEX IF NOT EXISTS ix_extid_linje_nr     ON person_external_id(linje, nr);
CREATE INDEX IF NOT EXISTS ix_extid_person       ON person_external_id(person_id);
CREATE INDEX IF NOT EXISTS ix_lineage_src_kode   ON lineage(source_id, kode);
CREATE INDEX IF NOT EXISTS ix_fact_subjekt       ON fact(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_assertion_target   ON assertion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_conclusion_target  ON conclusion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_citation_assertion ON citation(assertion_id);
CREATE INDEX IF NOT EXISTS ix_note_target        ON note(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_relation_subjekt   ON relation(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_relation_objekt    ON relation(objekt_type, objekt_id);
CREATE INDEX IF NOT EXISTS ix_assertion_objekt   ON assertion(objekt_type, objekt_id) WHERE objekt_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_narrative_subjekt  ON narrative(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_person_visningnavn ON person(visning_navn);

-- --- KUN PostgreSQL/Supabase: fuldtekstindeks på narrativ (kør separat; DuckDB understøtter ikke tsvector) ---
-- ALTER TABLE narrative ADD COLUMN fts tsvector
--   GENERATED ALWAYS AS (to_tsvector('danish', coalesce(tekst,''))) STORED;
-- CREATE INDEX narrative_fts_idx ON narrative USING GIN (fts);

-- ---------- REDAKTIONS-RPC'ER (Task 5) ----------

-- Direkte person-koen-sætter
CREATE OR REPLACE FUNCTION red_set_koen(p_person_id bigint, p_koen text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_koen', format('Satte køn på person %s', p_person_id), 'person', p_person_id);
  UPDATE person SET koen = p_koen WHERE id = p_person_id;  -- CHECK håndhæver vokabular
END $$;

-- Direkte person-privat-sætter
CREATE OR REPLACE FUNCTION red_set_privat(p_person_id bigint, p_privat boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_privat', format('Satte privat-flag på person %s', p_person_id), 'person', p_person_id);
  UPDATE person SET privat = p_privat WHERE id = p_person_id;
END $$;

-- Eneste klient-skrivevej til hændelsesprojektionen: redaktørens feed-dom.
CREATE OR REPLACE FUNCTION red_set_haendelse_status(p_haendelse_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kandidat','interessant','skjult') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig feed-status (kandidat|interessant|skjult)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM haendelse WHERE id=p_haendelse_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Hændelse % findes ikke', p_haendelse_id; END IF;
  PERFORM begin_change_set('red_set_haendelse_status',
    format('Satte feed-status %s på hændelse %s', p_status, p_haendelse_id), v_stype, v_sid);
  UPDATE haendelse SET feed_status=p_status WHERE id=p_haendelse_id;
END $$;

-- Redaktionelle minihistorier + feed-kurering (fase3-spec §3.6): eneste skrivevej.
-- Rolle-gate → validering → begin_change_set → skriv giver dry-run/LIVE og fortryd.
CREATE OR REPLACE FUNCTION red_opret_story(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  PERFORM begin_change_set('red_opret_story',
    format('Oprettede story om %s %s', p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO story (id, subjekt_type, subjekt_id, haendelse_id, fact_id, relation_id,
                     historical_event_id, titel, tekst, date_min, date_max, date_qualifier,
                     date_raw, privat)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM story), p_subjekt_type, p_subjekt_id,
          p_haendelse_id, p_fact_id, p_relation_id, p_historical_event_id,
          p_titel, p_tekst, p_date_min, p_date_max, p_date_qualifier, p_date_raw, p_privat)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_rediger_story(
  p_story_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_rediger_story',
    format('Redigerede story %s', p_story_id), v_stype, v_sid);
  UPDATE story SET titel=p_titel, tekst=p_tekst, haendelse_id=p_haendelse_id,
    fact_id=p_fact_id, relation_id=p_relation_id, historical_event_id=p_historical_event_id,
    date_min=p_date_min, date_max=p_date_max, date_qualifier=p_date_qualifier,
    date_raw=p_date_raw, privat=p_privat
  WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_status(p_story_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kladde','klar','publiceret','arkiveret') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig story-status (kladde|klar|publiceret|arkiveret)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  IF p_status='publiceret'
     AND NOT EXISTS (SELECT 1 FROM story_kilde WHERE story_id=p_story_id) THEN
    RAISE EXCEPTION 'Story % kan ikke publiceres uden mindst én kilde', p_story_id;
  END IF;
  PERFORM begin_change_set('red_set_story_status',
    format('Satte status %s på story %s', p_status, p_story_id), v_stype, v_sid);
  UPDATE story SET status=p_status,
    publiceret_dato=CASE WHEN p_status='publiceret' THEN current_date ELSE publiceret_dato END
  WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_story(p_story_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_slet_story',
    format('Slettede story %s (hård slet — fejloprettelse)', p_story_id), v_stype, v_sid);
  DELETE FROM story WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_kilder(p_story_id bigint, p_kilder jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint; v_k jsonb; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_kilder IS NULL OR jsonb_typeof(p_kilder) <> 'array' THEN
    RAISE EXCEPTION 'p_kilder skal være et jsonb-array af {source_id, side?}';
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_set_story_kilder',
    format('Satte kildeliste på story %s', p_story_id), v_stype, v_sid);
  DELETE FROM story_kilde WHERE story_id=p_story_id;
  SELECT coalesce(max(id),0) INTO v_next FROM story_kilde;
  FOR v_k IN SELECT * FROM jsonb_array_elements(p_kilder) LOOP
    IF v_k->>'source_id' IS NULL
       OR NOT EXISTS (SELECT 1 FROM source WHERE id=(v_k->>'source_id')::bigint) THEN
      RAISE EXCEPTION 'Source % findes ikke', v_k->>'source_id';
    END IF;
    v_next := v_next + 1;
    INSERT INTO story_kilde (id, story_id, source_id, side)
    VALUES (v_next, p_story_id, (v_k->>'source_id')::bigint, v_k->>'side');
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION red_set_feed_pin(p_kort_noegle text, p_handling text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_handling NOT IN ('pin','skjul') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig pin-handling (pin|skjul)', p_handling;
  END IF;
  IF p_kort_noegle IS NULL OR btrim(p_kort_noegle)='' THEN
    RAISE EXCEPTION 'kort_noegle må ikke være tom';
  END IF;
  PERFORM begin_change_set('red_set_feed_pin',
    format('Satte %s på kort %s', p_handling, p_kort_noegle), NULL, NULL);
  INSERT INTO feed_pin (id, kort_noegle, handling)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM feed_pin), p_kort_noegle, p_handling)
  ON CONFLICT (kort_noegle) DO UPDATE
    SET handling=excluded.handling, oprettet_af=auth.uid(), oprettet_naar=now();
END $$;

CREATE OR REPLACE FUNCTION red_fjern_feed_pin(p_kort_noegle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM feed_pin WHERE kort_noegle=p_kort_noegle) THEN
    RAISE EXCEPTION 'Ingen pin/skjul på %', p_kort_noegle;
  END IF;
  PERFORM begin_change_set('red_fjern_feed_pin',
    format('Fjernede kurering af kort %s', p_kort_noegle), NULL, NULL);
  DELETE FROM feed_pin WHERE kort_noegle=p_kort_noegle;
END $$;

-- Direkte person-sletning (og familje-relationer)
-- Cycle 02 H2: FK-sikker cascade. Tidligere slettede den kun family_member+person → fejlede med
-- foreign_key_violation for enhver loadet person (non-cascade FK'er fra person_external_id/profiles/
-- family_member → person). Slet evidens/relationer/notes/narrativ FØR person, i FK-rigtig orden
-- (citation+conclusion FØR assertion, da conclusion.valgt_assertion_id → assertion).
CREATE OR REPLACE FUNCTION red_slet_person(p_person_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_facts bigint[]; v_rels bigint[];
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_person', format('Slettede person %s', p_person_id), 'person', p_person_id);

  -- Fælles skriveorden med OCR-rettelsen: source/external-id → person → evidens.
  -- Sletningen må vente her, før den tager citation/assertion, ellers kan to transaktioner
  -- danne cyklussen external-id→citation / citation→external-id.
  PERFORM 1 FROM source s JOIN person_external_id pei ON pei.source_id=s.id
    WHERE pei.person_id=p_person_id ORDER BY s.id,pei.source_id FOR UPDATE OF s,pei;
  PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE;

  SELECT coalesce(array_agg(id),'{}') INTO v_facts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(array_agg(id),'{}') INTO v_rels FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id);

  UPDATE profiles SET reventlow_person_id = NULL WHERE reventlow_person_id = p_person_id;

  DELETE FROM citation WHERE assertion_id IN (
    SELECT id FROM assertion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                                OR (target_type='relation' AND target_id = ANY(v_rels)));
  DELETE FROM conclusion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM assertion  WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM note WHERE (target_type='person'   AND target_id=p_person_id)
                      OR (target_type='fact'     AND target_id = ANY(v_facts))
                      OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM narrative          WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  DELETE FROM relation           WHERE id = ANY(v_rels);
  DELETE FROM fact               WHERE id = ANY(v_facts);
  DELETE FROM person_external_id WHERE person_id = p_person_id;
  DELETE FROM family_member      WHERE person_id = p_person_id;
  -- review 19 H2: slaegtsnavn_karantaene.person_id har ingen ON DELETE CASCADE — uden denne linje
  -- fejler sletningen for enhver person der har >1 distinkt effektivt efternavn (fan-out).
  DELETE FROM slaegtsnavn_karantaene WHERE person_id = p_person_id;
  DELETE FROM person             WHERE id = p_person_id;
END $$;

-- Upsert narrativ, nøglet på (subjekt_type, subjekt_id, source_id) — én narrativ pr. udgave.
-- p_source_id er den faktiske nøgle (begge app-klienter sender den). side=COALESCE så en
-- udeladt side ikke sletter eksisterende sidereference. NB: gammel 4-arg-signatur droppes i
-- db-migrations.sql (cross-client breaking change; web+mobil opdateret i lockstep).
CREATE OR REPLACE FUNCTION red_upsert_narrativ(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean,
  p_source_id bigint, p_side text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upsert_narrativ', format('Opdaterede narrativ på %s/%s (kilde %s)', p_subjekt_type, p_subjekt_id, p_source_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND source_id IS NOT DISTINCT FROM p_source_id
    ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(id, subjekt_type, subjekt_id, source_id, tekst, side, privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM narrative), p_subjekt_type, p_subjekt_id, p_source_id, p_tekst, p_side, p_privat)
      RETURNING id INTO v_id;
  ELSE
    UPDATE narrative SET tekst=p_tekst, privat=p_privat, side=COALESCE(p_side, side) WHERE id=v_id;
  END IF;
  RETURN v_id;
END $$;

-- Upsert relation (skaber ny relation direkte)
CREATE OR REPLACE FUNCTION red_relation(
  p_subjekt_type text, p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint,
  p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_rolle = 'samme_som' THEN RAISE EXCEPTION 'Brug red_samme_som til identitets-links'; END IF;
  IF p_rolle = 'ikke_samme_som' THEN RAISE EXCEPTION 'Brug red_ikke_samme_som til identitets-afvisning'; END IF;
  -- GDPR-invariant ved fødslen (ikke kun i red_upload_media): en 'afbildet'-relation skal gå
  -- person→media, fordi media_afbilder_skjult/privat KUN scanner (subjekt=person, objekt=media).
  -- En person på objekt-siden ville være usynlig for gatingen → fail-open. Luk det for ALLE kaldere.
  IF p_rolle = 'afbildet' AND p_objekt_type = 'person' THEN
    RAISE EXCEPTION 'afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)';
  END IF;
  PERFORM begin_change_set('red_relation', format('Relation %s: %s/%s → %s/%s', p_rolle, p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id), p_subjekt_type, p_subjekt_id);
  BEGIN
    INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
              p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
      RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    DECLARE v_constraint_name text;
    BEGIN
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
      IF v_constraint_name = 'relation_afbildet_uidx' THEN
        RAISE EXCEPTION 'Mediet er allerede tilknyttet dette subjekt';
      END IF;
      RAISE;
    END;
  END;
  RETURN v_id;
END $$;

-- FK-ORDNET slet af en relations evidens (relationer har assertion+conclusion med
-- target_type='relation' UDEN FK → flad DELETE forældreløser dem). Delt intern helper (ingen
-- change_set/rolle-gate — kalderen ejer dem, B7: undgår nested change_set) så red_slet_relation
-- OG red_fjern_samme_som holder én kilde til FK-ordenen.
CREATE OR REPLACE FUNCTION _delete_relation_evidence(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  -- Gate (sikkerheds-hærdning): SECURITY DEFINER-helper kaldes kun fra gatede red_*-funktioner, men
  -- Supabases default-grants ville ellers eksponere den for anon via PostgREST → uatoriseret sletning
  -- af relations-evidens (kører som ejer, omgår RLS). Gratis her (kalderne er allerede redaktion).
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion (intern relations-slet-helper)'; END IF;
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_relation', format('Slettede relation %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id);
END $$;

-- Polymorf relationsevidens har ingen deklarativ FK. Lås derfor målrækken som en
-- rigtig FK ville gøre: writer-før-delete holder KEY SHARE; delete-før-writer holder
-- UPDATE/DELETE-lock, hvorefter writeren vågner og fejler, fordi rækken er væk.
CREATE OR REPLACE FUNCTION enforce_relation_evidence_target()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.target_type='relation' THEN
    PERFORM 1 FROM relation WHERE id=NEW.target_id FOR KEY SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Relations-evidens kræver eksisterende relation %', NEW.target_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.enforce_relation_evidence_target() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_assertion_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON assertion
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();
CREATE OR REPLACE TRIGGER trg_conclusion_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON conclusion
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();
CREATE OR REPLACE TRIGGER trg_note_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON note
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();

-- Direkte DELETE eller ændring af relationens PK må ikke kunne omgå den polymorfe
-- invariant. Evidensfri id-update er fortsat tilladt til import/undo; de tilsigtede
-- sletteveje bruger _delete_relation_evidence og rydder først evidensen.
CREATE OR REPLACE FUNCTION guard_relation_evidence_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  -- Generisk undo SET'er også PK-kolonnen til dens nuværende værdi.
  IF TG_OP='UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='relation' AND target_id=OLD.id) THEN
    IF TG_OP='UPDATE' THEN
      RAISE EXCEPTION 'Relation % har evidens og id kan ikke ændres', OLD.id;
    END IF;
    RAISE EXCEPTION 'Relation % har evidens og kan ikke slettes direkte', OLD.id;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.guard_relation_evidence_delete() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_relation_evidence_delete
  BEFORE DELETE OR UPDATE OF id ON relation
  FOR EACH ROW EXECUTE FUNCTION guard_relation_evidence_delete();

-- Medieflet må aldrig arve red_slet_relation's tilsigtede "slet relation + evidens"-semantik.
-- Relationens rækkelås serialiserer mod evidens-triggerens KEY SHARE uden at blokere
-- writes til andre relationer. Almindelig red_slet_relation er uændret.
CREATE OR REPLACE FUNCTION red_slet_medierelation_uden_evidens(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_relation relation%ROWTYPE;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- FOR UPDATE konflikter med evidens-triggerens FOR KEY SHARE på præcis denne relation.
  SELECT * INTO v_relation FROM relation WHERE id=p_relation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Relation % findes ikke', p_relation_id; END IF;
  IF NOT (
    (v_relation.rolle='afbildet' AND v_relation.subjekt_type='person'
      AND v_relation.objekt_type='media')
    OR
    (v_relation.rolle='afbildet' AND v_relation.subjekt_type='media'
      AND v_relation.objekt_type IN ('estate','coat_of_arms','lineage'))
  ) THEN
    RAISE EXCEPTION 'Relation % er ikke en kanonisk medie-afbildning', p_relation_id;
  END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=p_relation_id)
     OR EXISTS (SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='relation' AND target_id=p_relation_id) THEN
    RAISE EXCEPTION 'Medierelationen % har evidens og kan ikke fjernes ved blød flet', p_relation_id;
  END IF;
  PERFORM begin_change_set(
    'red_slet_medierelation_uden_evidens',
    format('Fjernede evidensfri medierelation %s ved blød flet', p_relation_id), NULL, NULL
  );
  DELETE FROM relation WHERE id=p_relation_id;
END $$;

REVOKE ALL ON FUNCTION public.red_slet_medierelation_uden_evidens(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.red_slet_medierelation_uden_evidens(bigint) TO authenticated;

-- ============================================================================
-- Redaktionel identitets-sammenkædning (samme_som) — spec 2026-07-02, Codex-3.
-- Invarianten (træer, præcis én sink pr. komponent) håndhæves i triggere, så den gælder ALLE
-- skriveveje (RPC/undo/load-script/manuel), ikke kun red_samme_som.
-- ============================================================================
-- SECURITY DEFINER (2026-08-01): guarden nedenfor kalder _samme_som_gruppe, hvis EXECUTE er
-- revoked fra anon/authenticated. Alle reelle skriveveje går gennem definer-RPC'er og kører
-- allerede som ejer, men uden dette ville en fremtidig ikke-ejer-sti fejle på rettigheder frem
-- for på invarianten. Funktionen skriver intet — den læser og rejser.
CREATE OR REPLACE FUNCTION enforce_samme_som_invariants() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- samme_som er en identitetspåstand med evidens knyttet til relationens stabile id.
    -- En rolle-/endepunkts-UPDATE ville derfor genbruge den gamle evidens til en ny påstand.
    -- Kræv slet+genopret (nyt relations-id) frem for en OLD-ekskluderende graf-guard;
    -- metadata, som ikke ændrer påstandens semantik, kan fortsat opdateres på stedet.
    IF (OLD.rolle = 'samme_som' OR NEW.rolle = 'samme_som')
       AND ROW(OLD.rolle, OLD.subjekt_type, OLD.subjekt_id, OLD.objekt_type, OLD.objekt_id)
           IS DISTINCT FROM
           ROW(NEW.rolle, NEW.subjekt_type, NEW.subjekt_id, NEW.objekt_type, NEW.objekt_id) THEN
      RAISE EXCEPTION 'samme_som: rolle og endepunkter er uforanderlige — brug slet+genopret';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.rolle <> 'samme_som' OR NEW.subjekt_type <> 'person' OR NEW.objekt_type <> 'person' THEN
    RETURN NEW; -- ikke et person→person samme_som — rør ikke
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation')); -- serialisér samme_som-mutationer
  IF NEW.subjekt_id = NEW.objekt_id THEN
    RAISE EXCEPTION 'samme_som: kan ikke linke en person til sig selv';
  END IF;
  -- G3 out-degree ≤ 1: alias peger ikke allerede på en ANDEN kanonisk (multi-sink).
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND subjekt_id = NEW.subjekt_id AND objekt_id <> NEW.objekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede alias for en anden (ville give multi-sink)', NEW.subjekt_id;
  END IF;
  -- G4 alias er ikke en eksisterende kanonisk (sink): ville stille re-roote en komponent.
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND objekt_id = NEW.subjekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede kanonisk for andre — skift retning via fjern+genopret', NEW.subjekt_id;
  END IF;
  -- Unionens to parter skal forblive to FORSKELLIGE personer. Den omvendte rækkefølge af
  -- trg_partner_loft's guard (Codex sol runde 5): dér blokeres "alias tilføjes som part nr. 2",
  -- her blokeres "to parter linkes bagefter". Uden begge er håndhævelsen asymmetrisk — samme
  -- slutresultat, afhængigt af klik-rækkefølgen. Komponenterne læses FØR den nye kant er
  -- indsat (BEFORE-trigger), hvilket er præcis de to sider der ville smelte sammen.
  -- Rettelsen er ikke at afvise identiteten, men at rette unionen først: står de samme person
  -- som gift med sig selv, er unionen forkert, ikke sammenkædningen.
  IF EXISTS (
    SELECT 1 FROM family_member a
    JOIN family_member b ON b.family_id = a.family_id AND b.rolle = 'partner' AND b.person_id <> a.person_id
    WHERE a.rolle = 'partner'
      AND a.person_id IN (SELECT pid FROM _samme_som_gruppe(NEW.subjekt_id))
      AND b.person_id IN (SELECT pid FROM _samme_som_gruppe(NEW.objekt_id))
  ) THEN
    RAISE EXCEPTION 'samme_som: % og % er parter i samme union — ret unionen først, ellers ville personen være gift med sig selv', NEW.subjekt_id, NEW.objekt_id;
  END IF;
  -- (Cyklus kan ikke opstå her: en ny alias→kanonisk-kant lukker kun en cyklus hvis alias er reachable
  -- fra kanonisk, dvs. alias har en indgående kant og dermed er et objekt — hvilket G4 allerede afviser.
  -- G3+G4 håndhæver derfor invarianten fuldt. En eksplicit graf-walk her ville være død kode + kunne
  -- fejle en urelateret insert hvis en cyklus var pre-injiceret via trigger-disabled rå-SQL.)
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_samme_som ON relation;
CREATE TRIGGER trg_enforce_samme_som BEFORE INSERT ON relation
  FOR EACH ROW WHEN (NEW.rolle = 'samme_som') EXECUTE FUNCTION enforce_samme_som_invariants();
DROP TRIGGER IF EXISTS trg_enforce_samme_som_update ON relation;
CREATE TRIGGER trg_enforce_samme_som_update BEFORE UPDATE ON relation
  FOR EACH ROW WHEN (OLD.rolle = 'samme_som' OR NEW.rolle = 'samme_som')
  EXECUTE FUNCTION enforce_samme_som_invariants();

-- Opret et redaktionelt identitets-link. Tynd, evidens-komplet wrapper ovenpå invariant-triggeren.
-- Idempotent på præcis retning (FØR change_set → ingen tom audit ved gentagelse).
CREATE OR REPLACE FUNCTION red_samme_som(p_alias_id bigint, p_objekt_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_alias_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_alias_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_objekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_objekt_id; END IF;
  -- G2 idempotens (præcis retning) FØR begin_change_set.
  SELECT id INTO v_rel FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=p_alias_id AND objekt_id=p_objekt_id LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  -- Kontradiktions-guard (tværudgave-spec §4): parret må ikke samtidig være markeret
  -- ikke_samme_som. At skifte mening er to versionerede trin (fjern afvisningen først).
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='ikke_samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND subjekt_id=least(p_alias_id,p_objekt_id) AND objekt_id=greatest(p_alias_id,p_objekt_id)) THEN
    RAISE EXCEPTION 'samme_som: parret (%,%) er markeret ikke_samme_som — fjern afvisningen først', p_alias_id, p_objekt_id;
  END IF;
  PERFORM begin_change_set('red_samme_som',
    format('Markerede person %s som samme som %s', p_alias_id, p_objekt_id), 'person', p_objekt_id);
  -- Triggeren validerer G0/G3/G4/G5 på denne INSERT.
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_alias_id, 'person', p_objekt_id, 'samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'relation', v_rel, 'samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitetssammenkædning');
  RETURN v_rel;
END $$;

-- Fjern et identitets-link. Genbruger red_slet_relation's KOMPLETTE evidens-sletning (de eksisterende
-- links har citations). Egen change_set (ikke nested).
CREATE OR REPLACE FUNCTION red_fjern_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=p_relation_id AND rolle='samme_som'
                AND subjekt_type='person' AND objekt_type='person') THEN
    RAISE EXCEPTION 'Relation % er ikke et person→person samme_som-link', p_relation_id;
  END IF;
  PERFORM begin_change_set('red_fjern_samme_som', format('Fjernede samme_som-link %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id); -- delt FK-ordnet slet (samme som red_slet_relation)
END $$;

-- ============================================================================
-- Redaktionel identitets-AFVISNING (ikke_samme_som) — tværudgave-spec 2026-07-15 §4.
-- Persisteret "bekræftet FORSKELLIGE personer" så tværudgave-arbejdslisten konvergerer
-- (afviste kandidater dukker ellers op igen ved hver genberegning). Symmetrisk relation,
-- normaliseret som LEAST(id)→GREATEST(id) — ét kanonisk opslag. INGEN citation (manuel
-- redaktionel beslutning; provenans = change_set + blaastemplet_af). Kontradiktions-guarden
-- ligger i RPC-laget, IKKE i en trigger: ingen delt forbruger læser ikke_samme_som (collapse
-- filtrerer på rolle='samme_som'), så et modstridende par degraderer til støj i arbejdslisten,
-- ikke datakorruption. En db-verify-assert fanger drift maskinelt.
-- ============================================================================
CREATE OR REPLACE FUNCTION red_ikke_samme_som(p_a bigint, p_b bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_lo bigint; v_hi bigint; v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Samme advisory-lock som red_samme_som: serialisér de to kontradiktions-guards mod hinanden
  -- (uden den kan concurrent red_samme_som(a,b)+red_ikke_samme_som(a,b) begge passere → dobbelt-rolle).
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF p_a = p_b THEN RAISE EXCEPTION 'ikke_samme_som: kan ikke afvise en person mod sig selv'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_a) THEN RAISE EXCEPTION 'Person % findes ikke', p_a; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_b) THEN RAISE EXCEPTION 'Person % findes ikke', p_b; END IF;
  v_lo := least(p_a, p_b); v_hi := greatest(p_a, p_b);
  -- Idempotens FØR change_set (ingen tom audit ved gentagelse; begge kald-retninger normaliseres).
  SELECT id INTO v_rel FROM relation WHERE rolle='ikke_samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=v_lo AND objekt_id=v_hi LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  -- Kontradiktions-guard: findes et samme_som-link mellem parret (begge retninger) → afvis.
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND ((subjekt_id=p_a AND objekt_id=p_b) OR (subjekt_id=p_b AND objekt_id=p_a))) THEN
    RAISE EXCEPTION 'ikke_samme_som: parret (%,%) er allerede linket som samme_som — fjern linket først', p_a, p_b;
  END IF;
  PERFORM begin_change_set('red_ikke_samme_som',
    format('Markerede person %s og %s som forskellige', v_lo, v_hi), 'person', v_lo);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', v_lo, 'person', v_hi, 'ikke_samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'relation', v_rel, 'ikke_samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitets-afvisning');
  RETURN v_rel;
END $$;

-- Fjern en identitets-afvisning. Egen change_set; genbruger den FK-ordnede evidens-sletning.
CREATE OR REPLACE FUNCTION red_fjern_ikke_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=p_relation_id AND rolle='ikke_samme_som'
                AND subjekt_type='person' AND objekt_type='person') THEN
    RAISE EXCEPTION 'Relation % er ikke et person→person ikke_samme_som-spor', p_relation_id;
  END IF;
  PERFORM begin_change_set('red_fjern_ikke_samme_som', format('Fjernede ikke_samme_som-spor %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id);
END $$;

-- Publicér en udgave: ryd staged for dens egne poster (person_external_id→source)
-- + dens partner-stubs (staged personer i en familie m. et source-scopet medlem;
-- stubs har ingen external_id). Redaktion-gated, revisions-tal returneres.
CREATE OR REPLACE FUNCTION red_publicer_udgave(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n integer;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må publicere en udgave (din rolle: %)', current_rolle();
  END IF;
  UPDATE person p SET staged = false
  WHERE p.staged = true
    AND (EXISTS (SELECT 1 FROM person_external_id pei
                 WHERE pei.person_id = p.id AND pei.source_id = p_source_id)
      OR EXISTS (SELECT 1 FROM family_member fm1
                 JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                 JOIN person_external_id pei ON pei.person_id = fm2.person_id
                   AND pei.source_id = p_source_id
                 WHERE fm1.person_id = p.id));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('publiceret_source', p_source_id, 'personer_afstaget', v_n);
END $$;
REVOKE ALL ON FUNCTION red_publicer_udgave(bigint) FROM PUBLIC, anon, authenticated;
-- 2026-07-24: funktionen har sin egen interne redaktion-gate (som øvrige red_*-RPC'er) —
-- grant'et var uforvarende glemt ved oprettelsen, hvilket gjorde den ukaldbar for alle.
GRANT EXECUTE ON FUNCTION red_publicer_udgave(bigint) TO authenticated;

-- Publicér udvalgte personer (K2 §7.20): ryd staged for netop de valgte + deres familie-
-- partnere (samme partner-stub-inklusion som red_publicer_udgave, blot scopet til udvalget).
CREATE OR REPLACE FUNCTION red_publicer_personer(p_person_ids bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n integer;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må publicere personer (din rolle: %)', current_rolle();
  END IF;
  IF p_person_ids IS NULL OR array_length(p_person_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_person_ids må ikke være tom';
  END IF;
  PERFORM begin_change_set('red_publicer_personer',
    format('Publicerede %s valgt(e) person(er)', array_length(p_person_ids, 1)), NULL, NULL);
  UPDATE person p SET staged = false
  WHERE p.staged = true
    AND (p.id = ANY(p_person_ids)
      OR EXISTS (SELECT 1 FROM family_member fm1
                 JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                 WHERE fm1.person_id = p.id AND fm2.person_id = ANY(p_person_ids)));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('valgte_person_ids', p_person_ids, 'personer_afstaget', v_n);
END $$;

-- Valideret + idempotent tilføj af person↔org/estate-relation (erstatter rå red_relation for UI).
CREATE OR REPLACE FUNCTION red_tilfoej_relation(
  p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint; v_findes boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_tilfoej_relation', format('Relation %s fra person %s', p_rolle, p_subjekt_id), 'person', p_subjekt_id);
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_subjekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_subjekt_id; END IF;
  IF p_objekt_type NOT IN ('organisation','estate') THEN RAISE EXCEPTION 'Ugyldig objekt_type %', p_objekt_type; END IF;
  IF p_objekt_type='organisation' THEN SELECT EXISTS(SELECT 1 FROM organisation WHERE id=p_objekt_id) INTO v_findes;
  ELSE SELECT EXISTS(SELECT 1 FROM estate WHERE id=p_objekt_id) INTO v_findes; END IF;
  IF NOT v_findes THEN RAISE EXCEPTION 'Objekt %/% findes ikke', p_objekt_type, p_objekt_id; END IF;
  SELECT id INTO v_id FROM relation WHERE subjekt_type='person' AND subjekt_id=p_subjekt_id
    AND objekt_type=p_objekt_type AND objekt_id=p_objekt_id AND coalesce(rolle,'')=coalesce(p_rolle,'') LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- 2C-2b familie-redigering -------------------------------------------------
-- Opret partner-union. INGEN auto-dedup (Codex H2): samme par kan gifte sig igen.
-- NB: p_ordinal er UNIONENS sekvensnummer (skrives ens til begge partnere), ikke hver partners
--     individuelle ægteskabstal — per-partner-ordinal er en fremtidig additiv udvidelse (cycle 07 H2).
CREATE OR REPLACE FUNCTION red_opret_union(p_partner_a bigint, p_partner_b bigint, p_type text, p_ordinal int DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fam bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_union', format('Oprettede union (%s) mellem %s og %s', p_type, p_partner_a, p_partner_b), 'person', p_partner_a);
  IF p_partner_a = p_partner_b THEN RAISE EXCEPTION 'Partnere skal være forskellige'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_a) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_a; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_b) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_b; END IF;
  IF p_type NOT IN ('vielse','partnerskab','ugift union') THEN RAISE EXCEPTION 'Ugyldig union-type %', p_type; END IF;
  INSERT INTO family(id, type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family), p_type) RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_a, 'partner', p_ordinal, NULL);
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_b, 'partner', p_ordinal, NULL);
  RETURN v_fam;
END $$;

-- Ret konfidens på et eksisterende familie-link.
CREATE OR REPLACE FUNCTION red_set_familie_konfidens(p_family_id bigint, p_person_id bigint, p_rolle text, p_konfidens text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_familie_konfidens', format('Satte konfidens %s på familie-link %s/%s/%s', p_konfidens, p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  UPDATE family_member SET konfidens=p_konfidens
    WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'Familie-link findes ikke (%, %, %)', p_family_id, p_person_id, p_rolle; END IF;
END $$;

-- Slet ÉT familie-link. INGEN family-entitets-sletning (Codex H1): family bærer facts/notes uden FK.
-- Idempotent: no-op (ingen RAISE) hvis triplen ikke findes — tilsigtet, matcher red_slet_relation/red_slet_person
--   (UI sender altid friskt-hentede triples; cycle 07 H4).
-- Helper (Problem 2, review 30): sikr at barnets forældrefamilie-slot findes og peger afklaret på
-- p_family (via en find-or-created redaktionel assertion). Idempotent; intern (kaldes kun fra gated red_*).
CREATE OR REPLACE FUNCTION _ensure_foraeldrefamilie_redaktionel(p_barn bigint, p_family bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_slot bigint; v_assert bigint;
BEGIN
  -- Gate (review 30/fable): SECURITY DEFINER-helper kaldes kun fra gated red_*-funktioner, men
  -- Supabases default-grants ville ellers eksponere den for anon via PostgREST (uatoriseret
  -- slot-re-peg). Guarden er gratis her (kalderen er allerede redaktion).
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion (intern forældrefamilie-helper)'; END IF;
  SELECT id INTO v_slot FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_barn AND faktatype='forældrefamilie' LIMIT 1;
  IF v_slot IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), 'person', p_barn, 'forældrefamilie') RETURNING id INTO v_slot;
  END IF;
  -- Find KUN en redaktionel (source-løs) assertion for familien — kapr aldrig en source-bunden
  -- rival-/adjudikeret påstand (review 30/Codex #5). Ordnet for determinisme.
  SELECT a.id INTO v_assert FROM assertion a
    WHERE a.target_type='fact' AND a.target_id=v_slot AND a.objekt_type='family' AND a.objekt_id=p_family
      AND NOT EXISTS(SELECT 1 FROM citation c WHERE c.assertion_id=a.id AND c.source_id IS NOT NULL)
    ORDER BY a.id LIMIT 1;
  IF v_assert IS NULL THEN
    INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_slot, 'barn', 'family', p_family, true) RETURNING id INTO v_assert;
    INSERT INTO citation(id, assertion_id, source_id, citat_tekst, kvalitet)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL, '(kilde mangler: strukturel projektion)', 'sekundær');
  END IF;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_slot, v_assert, 'afklaret', 'Redaktør (strukturel)', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret', blaastemplet_naar=current_date;
END $$;

CREATE OR REPLACE FUNCTION red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_familie_link', format('Slettede familie-link %s/%s/%s', p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  -- Slot-retraktion (Problem 2, review 30 B1): en fjernet 'barn'-række må ikke efterlade et
  -- forældreløst afklaret slot. Kun hvis slottet faktisk peger på DEN fjernede familie (red_flyt_barns
  -- interne slet rører intet, da slottet dér allerede peger på til efter red_vaelg_foraeldres re-peg).
  IF p_rolle = 'barn' THEN
    UPDATE conclusion c SET status='tilbagetrukket', blaastemplet_naar=current_date
    FROM fact f, assertion a
    WHERE f.subjekt_type='person' AND f.subjekt_id=p_person_id AND f.faktatype='forældrefamilie'
      AND c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
      AND a.id=c.valgt_assertion_id AND a.objekt_id=p_family_id;
  END IF;
END $$;

-- Identitets-ækvivalens til struktur-guards. samme_som er retningsbestemt (subjekt=alias →
-- objekt=kanonisk) og kan danne kæder; her returneres HELE den uorienterede komponent, så en
-- guard kan sammenligne personer på identitet frem for på rå id. Uden den kan en alias-post for
-- en efterkommer smutte forbi en cyklus-kontrol, og collapseSameAs opdager det først bagefter —
-- som karantæne, ikke som korruption, men det er en fejl der kunne være afvist ved skrivning
-- (Codex sol, 2026-08-01). Cyklus-sikker: UNION (ikke UNION ALL) terminerer på besøgte id'er.
--
-- SECURITY INVOKER, ikke DEFINER (Codex sol runde 2): kaldt fra en gated definer-RPC kører den
-- alligevel som ejer, men kaldt DIREKTE af anon rammer den relation-RLS som den skal. En definer-
-- udgave ville være et oracle: giv et person-id, få id'er fra skjulte samme_som-relationer.
-- EXECUTE revokes desuden eksplicit pr. rolle nedenfor — Supabases default-grants gør PUBLIC-
-- revoke alene utilstrækkelig.
CREATE OR REPLACE FUNCTION _samme_som_gruppe(p_person bigint)
RETURNS TABLE(pid bigint) LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public AS $$
  WITH RECURSIVE grp(pid) AS (
    SELECT p_person
    UNION
    SELECT CASE WHEN r.subjekt_id = g.pid THEN r.objekt_id ELSE r.subjekt_id END
    FROM grp g
    JOIN relation r ON r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
      AND (r.subjekt_id = g.pid OR r.objekt_id = g.pid)
  )
  SELECT pid FROM grp;
$$;
REVOKE EXECUTE ON FUNCTION _samme_som_gruppe(bigint) FROM PUBLIC, anon, authenticated;

-- Tilføj barn til en union. Struktur-guards (Codex H3): barn ≠ partner i samme family;
-- ingen ane-cyklus (recursiv CTE: descendants(barn) må ikke indeholde en partner i family).
-- NB: cyklus-tjekket er pre-INSERT uden lås — to samtidige txn'er kan i teorien hver indsætte den anden
--   som barn og tilsammen lukke en cyklus. Accepteret under projektets single-writer-PoC-antagelse
--   (samme klasse som max(id)+1; cycle 07 Codex H1). Advisory-lock = fremtidig hærdning hvis multi-writer.
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
  -- Fødselsfamilie-prætjek (invariant P1/EXCLUDE): kun én 'barn'-række pr. person. Venlig fejl frem
  -- for rå exclusion_violation. red_flyt_barn er delete-før-insert, så den passerer her (gammel række væk).
  IF p_rolle = 'barn' AND EXISTS(SELECT 1 FROM family_member
       WHERE person_id=p_barn_id AND rolle='barn' AND family_id <> p_family_id) THEN
    RAISE EXCEPTION 'Person % har allerede en fødselsfamilie — brug red_flyt_barn eller forældre-påstands-flowet', p_barn_id;
  END IF;
  -- Cyklus: er en partner i family en efterkommer af barnet? Sammenlignes på samme_som-
  -- komponenter, ikke rå id'er — ellers kunne en alias-post for en ane smutte forbi, og den
  -- spejlede guard i red_tilfoej_partner ville afvise præcis den omvendte operation
  -- (asymmetri fanget af Codex sol runde 2).
  WITH RECURSIVE efterkommere(pid) AS (
    SELECT g.pid FROM _samme_som_gruppe(p_barn_id) g
    UNION
    SELECT g.pid FROM efterkommere e
      JOIN family_member par ON par.person_id = e.pid AND par.rolle = 'partner'
      JOIN family_member b   ON b.family_id = par.family_id
        AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
      JOIN LATERAL _samme_som_gruppe(b.person_id) g ON true
  )
  SELECT EXISTS(
    SELECT 1 FROM family_member fp
    WHERE fp.family_id = p_family_id AND fp.rolle='partner' AND fp.person_id IN (SELECT pid FROM efterkommere)
  ) INTO v_cyklus;
  IF v_cyklus THEN RAISE EXCEPTION 'Cyklus: barn % er ane til en partner i familie %', p_barn_id, p_family_id; END IF;
  -- Dup-guard (PK): no-op hvis linket allerede findes
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
  -- Slot-komplethed (review 30/Codex #1): sikr et AFKLARET slot mod p_family. Dækker nyt barn (intet
  -- slot), delete→re-add (retrakteret slot) og slot der peger forkert. No-op når red_vaelg/red_flyt
  -- allerede pegede slottet på p_family (bevar deres valgte, source-bundne assertion).
  IF p_rolle = 'barn' AND NOT EXISTS(
       SELECT 1 FROM fact f
       JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
       JOIN assertion a ON a.id=c.valgt_assertion_id
       WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie'
         AND a.objekt_id=p_family_id) THEN
    PERFORM _ensure_foraeldrefamilie_redaktionel(p_barn_id, p_family_id);
  END IF;
END $$;


-- To parter pr. union — håndhævet i tabellen, ikke kun i RPC'en (Codex sol runde 2).
-- En RPC-tælling dækkede hverken fortryd-stien (_version_upsert_row skriver rækken direkte
-- tilbage) eller to samtidige kald der hver ser ét eksisterende partner-link. En rækkelås på
-- family (SELECT … FOR UPDATE) serialiserer skrivninger for SAMME familie, så tællingen er
-- pålidelig; låsen er transaktionsbundet og frigives med commit/rollback.
-- Prod havde 0 overtrædelser da invarianten blev indført (654 familier m. 2 parter, 28 m. 1).
CREATE OR REPLACE FUNCTION _tjek_partner_loft() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF NEW.rolle <> 'partner' THEN RETURN NEW; END IF;
  -- BEVIDST INGEN samme_som-advisory-lås her (Codex sol runde 7). Et forsøg på at lukke
  -- krydsracet med den lås inverterede rækkefølgen mod loaderen: load_daa.R tager EXCLUSIVE på
  -- bl.a. relation og flusher family_member FØR relation, mens red_samme_som holder advisory-
  -- låsen og venter på relation — en ægte deadlock-cyklus der kan abortere en hel load.
  -- RESTRISIKO, accepteret: to SAMTIDIGE transaktioner — én der indsætter ELLER omskriver en
  -- partner-række, én der linker to parter som samme person — kan hver overse den andens
  -- ucommittede række og tilsammen committe en selv-union. Det behøver ikke være to redaktører:
  -- én aktør med overlappende transaktioner, eller en anden skrivevej, kan udgøre den ene side.
  -- Samme single-writer-antagelse som red_tilfoej_barns cyklus-tjek allerede hviler på, og
  -- projektionen fanger tilstanden bagefter som karantæne, ikke som stille korruption.
  -- FULD lukning kræver BEGGE dele: at loaderne tager samme advisory-lås før deres LOCK TABLE,
  -- OG at låsen genindføres her. Parkeret samlet, fordi første halvdel rører tre prod-kritiske
  -- load-scripts der ikke kan verificeres uden en rigtig load-kørsel.
  PERFORM 1 FROM family WHERE id = NEW.family_id FOR UPDATE;  -- serialisér samtidige skrivninger for SAMME familie
  -- Ved UPDATE står OLD-rækken stadig i tabellen (BEFORE-trigger) og skal trækkes fra på sin
  -- EGEN nøgle. At udelade "alle rækker med samme nye person_id" ville overafvise en legitim
  -- omskrivning af en eksisterende parts person_id (Codex sol runde 3).
  SELECT count(*) INTO v_n FROM family_member fm
    WHERE fm.family_id = NEW.family_id AND fm.rolle = 'partner'
      AND NOT (TG_OP = 'UPDATE'
               AND fm.family_id = OLD.family_id AND fm.person_id = OLD.person_id AND fm.rolle = OLD.rolle);
  IF v_n >= 2 THEN
    RAISE EXCEPTION 'Familie % ville få % parter — en union har to', NEW.family_id, v_n + 1;
  END IF;
  -- De to parter skal være to FORSKELLIGE personer — også på identitet, ikke kun på id.
  -- Et samme_som-alias for den siddende part ville ellers give en union hvor begge parter
  -- kanoniserer til samme person; projektionen kalder det selv-ægtefælle og karantænerer hele
  -- identitetsgruppen, så en ægte sammenkædning holder op med at folde (Codex sol runde 4).
  -- Kun relevant når familien allerede HAR en part — springes over i det almindelige tilfælde,
  -- så loaderens batch-indsættelser ikke betaler for opslaget på den første partner-række.
  -- Hurtig forudsætning: har NEW.person_id overhovedet en samme_som-kant, hverken som subjekt
  -- eller objekt, er dens komponent = {sig selv}, og et overlap ville kræve en anden partner-række
  -- med præcis samme person_id — udelukket af primærnøglen. Uden dette filter betaler ENHVER
  -- anden-part-indsættelse for en rekursiv CTE (målt: 602 µs/række mod 17 µs).
  IF v_n > 0 AND EXISTS (
    SELECT 1 FROM relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person'
      AND (r.subjekt_id = NEW.person_id OR r.objekt_id = NEW.person_id)
  ) AND EXISTS (
    SELECT 1 FROM family_member fm
    WHERE fm.family_id = NEW.family_id AND fm.rolle = 'partner'
      AND NOT (TG_OP = 'UPDATE'
               AND fm.family_id = OLD.family_id AND fm.person_id = OLD.person_id AND fm.rolle = OLD.rolle)
      AND EXISTS (SELECT 1 FROM _samme_som_gruppe(fm.person_id) a
                  JOIN _samme_som_gruppe(NEW.person_id) b ON b.pid = a.pid)
  ) THEN
    RAISE EXCEPTION 'Person % er samme person som den anden part i familie % (samme_som)', NEW.person_id, NEW.family_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_partner_loft ON family_member;
CREATE TRIGGER trg_partner_loft BEFORE INSERT OR UPDATE ON family_member
  FOR EACH ROW EXECUTE FUNCTION _tjek_partner_loft();

-- Trigger-funktioner skal ikke kunne kaldes som RPC'er. PostgREST afviser ganske vist
-- trigger-returtypen, men Supabases default-grants får dem til at figurere i
-- get_advisors(security) som anon/authenticated-eksekverbare definer-funktioner — og
-- PUBLIC-revoke alene er utilstrækkelig, rollerne har direkte grants.
REVOKE EXECUTE ON FUNCTION _tjek_partner_loft() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION enforce_samme_som_invariants() FROM PUBLIC, anon, authenticated;

-- Tilføj en partner til en EKSISTERENDE union. red_opret_union laver altid en ny familie, så
-- indtil nu kunne en union der manglede sin ene part (fx 1939-loaderens mor-løse børne-familier,
-- 2026-08-01) kun repareres ved at flytte alle børnene væk. Denne funktion reparerer i stedet
-- familien selv.
--
-- Børnenes forældrefamilie-slot peger på FAMILIEN, ikke på forældrene, så en ny partner ændrer
-- ikke slottet — derfor intet _ensure_foraeldrefamilie_redaktionel-kald her (modsat red_tilfoej_barn,
-- hvor barnet skifter familie). Den afledte forældre-mængde i app-laget udvides derimod, hvilket er
-- hele pointen.
--
-- Tre guards ud over de trivielle:
--  * MAX TO PARTER. En union har to parter. Læselaget projicerer kun to (web/src/data/model.ts
--    p1/p2), men afleder forældre af ALLE partner-rækker — en tredje part ville altså blive
--    forælder til børnene uden at kunne ses. Afvises ved skrivning (Codex sol).
--  * CYKLUS, identitets-bevidst. Den nye part må ikke være efterkommer af et barn i familien
--    (parten bliver jo forælder til netop de børn). Sammenligningen sker på samme_som-komponenter,
--    ikke rå id'er, så en alias-post ikke kan smutte udenom.
--  * DUBLET FØR CHANGE_SET. No-op'en ligger foran begin_change_set, så et gentaget kald ikke
--    efterlader et tomt change_set (og en tom fortrydelse).
-- Pre-INSERT uden lås, samme forbehold som red_tilfoej_barn (single-writer-PoC-antagelsen).
CREATE OR REPLACE FUNCTION red_tilfoej_partner(p_family_id bigint, p_person_id bigint, p_ordinal int DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cyklus boolean; v_partnere int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Dublet-no-op FØR change_set'et, så gentagne kald ikke skriver tom historik.
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle='partner') THEN RETURN; END IF;
  PERFORM begin_change_set('red_tilfoej_partner', format('Tilføjede partner %s til familie %s', p_person_id, p_family_id), 'person', p_person_id);
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_person_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_person_id; END IF;
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle<>'partner')
    THEN RAISE EXCEPTION 'Person % er allerede barn i familie % — kan ikke også være partner', p_person_id, p_family_id; END IF;
  -- Venlig fejl før arbejdet; trg_partner_loft er den egentlige invariant og fanger også
  -- fortryd-stien og samtidige kald.
  SELECT count(*) INTO v_partnere FROM family_member WHERE family_id=p_family_id AND rolle='partner';
  IF v_partnere >= 2 THEN
    RAISE EXCEPTION 'Familie % har allerede to parter — en union har to; fjern en part først', p_family_id;
  END IF;
  -- Cyklus: er den nye part (eller nogen den er samme_som) efterkommer af et barn i familien?
  WITH RECURSIVE efterkommere(pid) AS (
    SELECT g.pid FROM family_member b
      JOIN LATERAL _samme_som_gruppe(b.person_id) g ON true
      WHERE b.family_id = p_family_id AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
    UNION
    SELECT g.pid FROM efterkommere e
      JOIN family_member par ON par.person_id = e.pid AND par.rolle = 'partner'
      JOIN family_member b   ON b.family_id = par.family_id
        AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
      JOIN LATERAL _samme_som_gruppe(b.person_id) g ON true
  )
  SELECT EXISTS(
    SELECT 1 FROM efterkommere e JOIN _samme_som_gruppe(p_person_id) k ON k.pid = e.pid
  ) INTO v_cyklus;
  IF v_cyklus THEN RAISE EXCEPTION 'Cyklus: person % er efterkommer af et barn i familie %', p_person_id, p_family_id; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_person_id, 'partner', p_ordinal, NULL);
END $$;


-- Ret ordinal (rækkefølge) på et familie-link. Bruges bl.a. til søskende-visningsrækkefølge
-- (mobile/src/data/load.ts sorterer 'barn'-rækker efter ordinal) når fødselsår er ukendt/
-- upræcist, men den indbyrdes rækkefølge kendes. Samme felt bruges for 'partner'-rækker til
-- ægteskabs-sekvensnummer (red_opret_union) — generisk "sæt ordinal", matcher
-- red_set_familie_konfidens' mønster (2026-07-02).
CREATE OR REPLACE FUNCTION red_set_familie_ordinal(p_family_id bigint, p_person_id bigint, p_rolle text, p_ordinal int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_familie_ordinal', format('Satte ordinal %s på familie-link %s/%s/%s', p_ordinal, p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  UPDATE family_member SET ordinal=p_ordinal
    WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'Familie-link findes ikke (%, %, %)', p_family_id, p_person_id, p_rolle; END IF;
END $$;

-- Flyt et barn fra ét forhold til et andet (fx rettelse af forkert mor/far-par — barnet var
-- registreret under den forkerte af personens flere unioner). Tynd wrapper om
-- red_tilfoej_barn + red_slet_familie_link: genbruger deres cyklus-/partner-guards uændret i
-- stedet for at duplikere dem. begin_change_set() her sikrer ÉT change_set for hele
-- flytningen — de indre kald genbruger det allerede-aktive sæt (verificeret re-entrant, B7/T5b
-- i docs/reviews/09-versionering-hyperlinks-db.md), opretter ikke separate sæt. Ordinal
-- nulstilles bevidst ved flytning (søskende-rækkefølge er unions-specifik); konfidens bevares.
CREATE OR REPLACE FUNCTION red_flyt_barn(p_fra_family_id bigint, p_til_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_konfidens text; v_slot_fact bigint; v_slot_family bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_flyt_barn', format('Flyttede barn %s fra familie %s til familie %s', p_barn_id, p_fra_family_id, p_til_family_id), 'person', p_barn_id);
  IF p_fra_family_id = p_til_family_id THEN RAISE EXCEPTION 'Fra- og til-familie er ens'; END IF;
  SELECT konfidens INTO v_konfidens FROM family_member
    WHERE family_id=p_fra_family_id AND person_id=p_barn_id AND rolle=p_rolle;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barn-link findes ikke (family %, person %, rolle %)', p_fra_family_id, p_barn_id, p_rolle; END IF;
  -- delete-før-insert (Problem 2): red_tilfoej_barns fødselsfamilie-prætjek + EXCLUDE ser én 'barn'-række.
  PERFORM red_slet_familie_link(p_fra_family_id, p_barn_id, p_rolle);
  PERFORM red_tilfoej_barn(p_til_family_id, p_barn_id, p_rolle, v_konfidens);
  -- Slot-vedligehold (invariant P1, review 30): re-etablér slottet til til-familien MEDMINDRE det
  -- allerede peger dertil (red_vaelg_foraeldre re-pegede FØR flyt → bevar dens valgte source-bundne
  -- assertion). Håndterer også retraktion fra det interne red_slet_familie_link + omstridt slot.
  IF p_rolle = 'barn' THEN
    SELECT f.id INTO v_slot_fact FROM fact f
      WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie' LIMIT 1;
    IF v_slot_fact IS NOT NULL THEN
      SELECT a.objekt_id INTO v_slot_family FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
        WHERE c.target_type='fact' AND c.target_id=v_slot_fact AND c.status='afklaret';
      IF v_slot_family IS DISTINCT FROM p_til_family_id THEN
        PERFORM _ensure_foraeldrefamilie_redaktionel(p_barn_id, p_til_family_id);
      END IF;
    END IF;
  END IF;
END $$;

-- ---------- FORÆLDREFAMILIE-SLOT: konkurrerende slægtskabspåstande (Problem 2) ----------
-- Giver 'barn'-slægtskabet det evidenslag fact/relation har: hver udgaves forældre-påstand bevares
-- som assertion (objekt=familie), redaktøren vælger den kanoniske via conclusion, family_member
-- forbliver den kanoniske projektion (nul ændring i læse-laget). Se
-- docs/superpowers/specs/2026-07-15-family-member-konkurrerende-relationer-design.md.

-- Registrér en kildes forældrefamilie-påstand UDEN at ændre det kanoniske valg (Operation A-analog).
CREATE OR REPLACE FUNCTION red_tilfoej_foraeldre_paastand(
  p_barn_id bigint, p_family_id bigint,
  p_source_id bigint DEFAULT NULL, p_side text DEFAULT NULL,
  p_citat text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_fact bigint; v_assert bigint; v_cit bigint;
  v_valgt_family bigint; v_barn_family bigint; v_konflikt boolean := false; v_concl_exists boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion må skrive forældre-påstande (din rolle: %)', current_rolle(); END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_barn_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_barn_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND rolle='partner') THEN
    RAISE EXCEPTION 'Familie % har ingen forælder (partner-medlem) — kan ikke være forældrefamilie', p_family_id; END IF;

  -- Idempotens FØR change_set: samme slot + samme objekt_id + samme citation-source → returnér eksisterende.
  SELECT f.id, a.id, c.id INTO v_fact, v_assert, v_cit
    FROM fact f
    JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family' AND a.objekt_id=p_family_id
    JOIN citation c ON c.assertion_id=a.id AND c.source_id IS NOT DISTINCT FROM p_source_id
    WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie'
    LIMIT 1;
  IF v_assert IS NOT NULL THEN
    RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,'citation_id',v_cit,'konflikt',false,'idempotent',true);
  END IF;

  PERFORM begin_change_set('red_tilfoej_foraeldre_paastand',
    format('Forældrefamilie-påstand: barn %s → familie %s', p_barn_id, p_family_id), 'person', p_barn_id);

  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_barn_id AND faktatype='forældrefamilie' LIMIT 1;
  IF v_fact IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), 'person', p_barn_id, 'forældrefamilie')
      RETURNING id INTO v_fact;
  END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, 'barn', 'family', p_family_id, true)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, side, citat_tekst, kvalitet)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, p_source_id, p_side,
            coalesce(p_citat, p_kilde_fritekst, '(kilde mangler)'),
            CASE WHEN p_source_id IS NOT NULL THEN 'primær' ELSE 'sekundær' END)  -- kildeløs redaktionel påstand er ikke primærkilde
    RETURNING id INTO v_cit;

  SELECT a.objekt_id INTO v_valgt_family
    FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_fact;
  v_concl_exists := EXISTS(SELECT 1 FROM conclusion WHERE target_type='fact' AND target_id=v_fact);
  SELECT family_id INTO v_barn_family FROM family_member WHERE person_id=p_barn_id AND rolle='barn' LIMIT 1;

  IF v_concl_exists THEN
    IF v_valgt_family IS DISTINCT FROM p_family_id THEN
      -- Konflikt: valgt_assertion_id URØRT (TNG-præcedens); markér omstridt + eskalér konfidens (invariant 7).
      v_konflikt := true;
      UPDATE conclusion SET status='omstridt', blaastemplet_naar=current_date
        WHERE target_type='fact' AND target_id=v_fact;
      -- EXCLUDE garanterer højst én 'barn'-række pr. person → intet familie-prædikat/NULL-guard nødvendigt.
      UPDATE family_member SET konfidens='omstridt'
        WHERE person_id=p_barn_id AND rolle='barn';
    END IF;
  ELSE
    IF v_barn_family IS NOT DISTINCT FROM p_family_id THEN
      INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
        VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert, 'afklaret',
                'Redaktør (korroboration)', current_date);
    END IF;
  END IF;

  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,'citation_id',v_cit,'konflikt',v_konflikt);
END $$;

-- Adjudikationen — ét bevidst valg + synkron projektion, i ÉT change_set.
CREATE OR REPLACE FUNCTION red_vaelg_foraeldre(p_assertion_id bigint, p_konfidens text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_barn bigint; v_faktatype text; v_objekt_type text; v_til_family bigint; v_old_family bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  SELECT a.target_id, a.objekt_type, a.objekt_id, f.subjekt_id, f.faktatype
    INTO v_fact, v_objekt_type, v_til_family, v_barn, v_faktatype
    FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact'
    WHERE a.id=p_assertion_id;
  IF v_fact IS NULL THEN RAISE EXCEPTION 'Assertion % findes ikke el. targeter ikke et fact', p_assertion_id; END IF;
  IF v_faktatype <> 'forældrefamilie' OR v_objekt_type IS DISTINCT FROM 'family' THEN
    RAISE EXCEPTION 'Assertion % er ikke en forældrefamilie-påstand', p_assertion_id; END IF;
  IF EXISTS(SELECT 1 FROM fact ff JOIN conclusion cc ON cc.target_type='fact' AND cc.target_id=ff.id AND cc.status='afklaret'
            WHERE ff.subjekt_type='person' AND ff.subjekt_id=v_barn AND ff.faktatype='forældre_ukendt') THEN
    RAISE EXCEPTION 'Barn % er markeret forældre_ukendt — tilbagetræk markeringen først (red_tilbagetraek_fakta)', v_barn; END IF;

  PERFORM begin_change_set('red_vaelg_foraeldre',
    format('Valgte forældrefamilie %s for barn %s', v_til_family, v_barn), 'person', v_barn);

  -- Re-peg conclusion FØR projektionen (så red_flyt_barns slot-vedligehold ikke dobbelt-nedskriver).
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, p_assertion_id, 'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret', blaastemplet_naar=current_date;

  SELECT family_id INTO v_old_family FROM family_member WHERE person_id=v_barn AND rolle='barn' LIMIT 1;
  IF v_old_family IS NULL THEN
    PERFORM red_tilfoej_barn(v_til_family, v_barn);
  ELSIF v_old_family <> v_til_family THEN
    PERFORM red_flyt_barn(v_old_family, v_til_family, v_barn);
  END IF;

  IF p_konfidens IS NOT NULL THEN
    PERFORM red_set_familie_konfidens(v_til_family, v_barn, 'barn', p_konfidens);
  END IF;
END $$;

-- Konflikt-view til redaktions-dashboardet (security_invoker som red_konflikt).
CREATE OR REPLACE VIEW red_foraeldre_konflikt WITH (security_invoker = true) AS
SELECT f.subjekt_id AS person_id, f.id AS fact_id,
       count(DISTINCT a.objekt_id) AS antal_familier,
       count(*)                    AS antal_paastande,
       max(c.status)               AS status
FROM fact f
JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family'
LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie'
GROUP BY f.subjekt_id, f.id
HAVING count(DISTINCT a.objekt_id) > 1;

-- Medlem-forslag til staging (all authenticated)
CREATE OR REPLACE FUNCTION red_suggest(
  p_art text, p_subjekt_type text, p_subjekt_id bigint, p_felt text, p_vaerdi text,
  p_kilde_fritekst text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login kræves for forslag'; END IF;
  INSERT INTO suggestion(forslagsstiller, art, subjekt_type, subjekt_id, felt, vaerdi,
                         kilde_fritekst, payload, note)
    VALUES (auth.uid(), p_art, p_subjekt_type, p_subjekt_id, p_felt, p_vaerdi,
            p_kilde_fritekst, coalesce(p_payload,'{}'::jsonb), p_note)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- =====================================================================
-- REDAKTIONS-DASHBOARD: konflikt-view + slet-preview
-- =====================================================================

-- Konflikt-kø til redaktions-dashboard: ægte kilde-uenighed = >1 DISTINKT værdi
-- INDEN FOR ÉT fact (to kilder uenige om SAMME forhold). Grain er PR. FACT, ikke
-- pr. (person,faktatype): en person kan have FLERE facts af samme type (fx 6 titler
-- gennem livet) — det er legitime distinkte facts, ikke en konflikt (bruger-feedback
-- 2026-06-28, fact-kardinalitet — se decisions.md).
-- security_invoker=true er KRITISK: ellers kører viewet med ejer-rettigheder og omgår RLS
-- på fact/assertion → ville lække private personers konflikter (spec §5, Codex-review høj).
-- v1: kun 'navn'/'titel' (dato-fakta har typisk tom vaerdi_tekst → udeladt, spec §5).
CREATE OR REPLACE VIEW red_konflikt
  WITH (security_invoker = true) AS
-- fact_id sidst: CREATE OR REPLACE VIEW kan kun APPEND kolonner (ikke indsætte midt i).
SELECT f.subjekt_id AS person_id,
       f.faktatype,
       count(DISTINCT a.vaerdi_tekst) AS antal_vaerdier,
       count(*)                       AS antal_oplysninger,
       f.id         AS fact_id
FROM fact f
JOIN assertion a ON a.target_type = 'fact' AND a.target_id = f.id
WHERE f.subjekt_type = 'person'
  AND f.faktatype IN ('navn','titel')
GROUP BY f.subjekt_id, f.faktatype, f.id
HAVING count(DISTINCT a.vaerdi_tekst) > 1;

-- Read-only forhåndsvisning af hvad red_slet_person ville slette. Spejler RPC'ens
-- relations-logik: personen som subjekt ELLER objekt (spec §7, Codex-review høj).
CREATE OR REPLACE FUNCTION red_slet_person_preview(p_person_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rels jsonb; v_nfacts int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT count(*) INTO v_nfacts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_rels FROM (
    SELECT rolle,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id)
  ) r;
  RETURN jsonb_build_object(
    'antal_relationer', jsonb_array_length(v_rels),
    'antal_facts', v_nfacts,
    'relationer', v_rels);
END $$;

-- ============ OPRET-NY-ENTITET (2026-06-29) ============
-- Komposite SECURITY DEFINER opret-RPC'er. id=max+1 (husstil). privat=true default (privatliv).
CREATE OR REPLACE FUNCTION red_opret_person(
  p_navn text, p_koen text DEFAULT NULL, p_levende boolean DEFAULT false,
  p_foedt_raw text DEFAULT NULL, p_doed_raw text DEFAULT NULL, p_titel_raw text DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_person', format('Oprettede person %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  IF p_koen IS NOT NULL AND p_koen NOT IN ('mand','kvinde','ukendt')
    THEN RAISE EXCEPTION 'Ugyldigt køn %', p_koen; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, levende, privat, koen) VALUES (v_id, p_levende, true, p_koen);
  PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn);
  IF nullif(btrim(p_foedt_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw);
  END IF;
  IF nullif(btrim(p_doed_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'død', p_doed_raw, p_date_raw => p_doed_raw);
  END IF;
  IF nullif(btrim(p_titel_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'titel', p_titel_raw);
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_estate(p_navn text, p_slags text DEFAULT NULL, p_sted_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_estate', format('Oprettede ejendom %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM estate);
  INSERT INTO estate(id, navn, slags, sted_id) VALUES (v_id, p_navn, p_slags, p_sted_id);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false, p_aar smallint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_kilde', format('Oprettede kilde %s', p_titel), NULL, NULL);
  IF nullif(btrim(p_titel),'') IS NULL THEN RAISE EXCEPTION 'Titel er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel, udgave, aar, ekstern) VALUES (v_id, p_slags, p_titel, p_udgave, p_aar, p_ekstern);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_organisation(p_navn text, p_slags text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_organisation', format('Oprettede organisation %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM organisation);
  INSERT INTO organisation(id, navn, slags) VALUES (v_id, p_navn, p_slags);
  RETURN v_id;
END $$;

-- ============ MEDIER (mediehåndtering 2026-07-04, Slice 0) ============
-- To-fase upload: Postgres-txn opretter rækken ('kladde'); Storage-upload sker separat
-- (kan ikke dele txn); bekræftelse flipper til 'klar'. RLS + app viser kun 'klar'.
-- maa_publiceres defaulter false → nyoprettet medie er skjult til en redaktør frigiver.
CREATE OR REPLACE FUNCTION red_opret_media(
  p_slags text, p_titel text DEFAULT NULL, p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL,
  p_bucket text DEFAULT 'media', p_storage_path text DEFAULT NULL,
  p_mime text DEFAULT NULL, p_byte_size bigint DEFAULT NULL,
  p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL,
  p_sha256 text DEFAULT NULL, p_original_filnavn text DEFAULT NULL,
  p_rettigheder_status text DEFAULT 'ukendt', p_maa_publiceres boolean DEFAULT false
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_media', format('Oprettede media %s', coalesce(p_titel,p_original_filnavn,'?')), 'media', NULL);
  IF nullif(btrim(p_slags),'') IS NULL THEN RAISE EXCEPTION 'Slags er påkrævet'; END IF;
  -- sha256-dedup: samme bytes må kun registreres som ÉN media-række (genbrug den frem for at
  -- oprette en dublet). Domæne-fejl frem for rå unique_violation (media_sha256_uidx).
  IF p_sha256 IS NOT NULL AND EXISTS (SELECT 1 FROM media WHERE sha256 = p_sha256) THEN
    RAISE EXCEPTION 'Medie med samme indhold findes allerede (sha256=%). Genbrug den eksisterende media-række via red_relation.', p_sha256;
  END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id, slags, titel, kunstner, datering, bucket, storage_path,
                    mime_type, byte_size, bredde, hoejde, sha256, original_filnavn,
                    upload_status, rettigheder_status, maa_publiceres)
    VALUES (v_id, p_slags, p_titel, p_kunstner, p_datering, coalesce(p_bucket,'media'), p_storage_path,
            p_mime, p_byte_size, p_bredde, p_hoejde, p_sha256, p_original_filnavn,
            'kladde', coalesce(p_rettigheder_status,'ukendt'), coalesce(p_maa_publiceres,false));
  RETURN v_id;
END $$;

-- Fase 2: bekræft at bytes er landet i Storage → flip til 'klar'.
CREATE OR REPLACE FUNCTION red_bekraeft_media_upload(
  p_media_id bigint, p_byte_size bigint DEFAULT NULL, p_sha256 text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_bekraeft_media_upload', format('Bekræftede upload af media %s', p_media_id), 'media', p_media_id);
  -- upload_status<>'fjernet'-guard (Slice 0h /simplify-fund): et forsinket/gentaget bekræft-kald må
  -- aldrig genoplive en blødt-slettet række til 'klar' igen.
  UPDATE media SET upload_status='klar',
                   byte_size=coalesce(p_byte_size, byte_size),
                   sha256=coalesce(p_sha256, sha256)
   WHERE id=p_media_id AND upload_status <> 'fjernet';
END $$;

-- Kombineret: opret media + afbildet-relation i ÉT change_set. begin_change_set er re-entrant
-- (B7) → de nestede red_opret_media/red_relation slutter sig til samme sæt (fortrydes samlet).
-- Portræt: sæt p_afbildet_person_id. Objekt-foto (gods/våben): sæt p_objekt_type/p_objekt_id.
CREATE OR REPLACE FUNCTION red_upload_media(
  p_slags text, p_titel text, p_storage_path text, p_mime text,
  p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL,
  p_afbildet_person_id bigint DEFAULT NULL,
  p_objekt_type text DEFAULT NULL, p_objekt_id bigint DEFAULT NULL,
  p_byte_size bigint DEFAULT NULL, p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL,
  p_sha256 text DEFAULT NULL, p_original_filnavn text DEFAULT NULL,
  p_rettigheder_status text DEFAULT 'ukendt', p_maa_publiceres boolean DEFAULT false
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_media bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upload_media', format('Uploadede media %s', coalesce(p_titel,p_original_filnavn,'?')), 'media', NULL);
  v_media := red_opret_media(p_slags, p_titel, p_kunstner, p_datering, 'media', p_storage_path,
                             p_mime, p_byte_size, p_bredde, p_hoejde, p_sha256,
                             p_original_filnavn, p_rettigheder_status, p_maa_publiceres);
  IF p_afbildet_person_id IS NOT NULL THEN
    PERFORM red_relation('person', p_afbildet_person_id, 'media', v_media, 'afbildet');
  END IF;
  IF p_objekt_type IS NOT NULL AND p_objekt_id IS NOT NULL THEN
    -- GDPR-guard: person-afbildning SKAL gå person→media (den retning media_afbilder_skjult/privat
    -- scanner). Objekt-grenen laver media→objekt og ville ellers omgå gatingen for en person.
    IF p_objekt_type = 'person' THEN
      RAISE EXCEPTION 'Brug p_afbildet_person_id til personer (GDPR-gating kræver person→media-retning)';
    END IF;
    PERFORM red_relation('media', v_media, p_objekt_type, p_objekt_id, 'afbildet');
  END IF;
  RETURN v_media;
END $$;

-- Fase 1 filside: redigér mediets kuraterbare metadata efter upload.
-- NULL = uændret; tom streng = ryd feltet (undtagen slags, som er påkrævet).
CREATE OR REPLACE FUNCTION red_opdater_media(
  p_media_id bigint,
  p_titel text DEFAULT NULL,
  p_slags text DEFAULT NULL,
  p_kunstner text DEFAULT NULL,
  p_datering text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opdater_media', format('Opdaterede media %s', p_media_id), 'media', p_media_id);
  IF p_slags IS NOT NULL AND nullif(btrim(p_slags),'') IS NULL THEN
    RAISE EXCEPTION 'Slags kan ikke ryddes';
  END IF;
  UPDATE media SET
    titel = CASE WHEN p_titel IS NULL THEN titel ELSE nullif(btrim(p_titel),'') END,
    slags = CASE WHEN p_slags IS NULL THEN slags ELSE btrim(p_slags) END,
    kunstner = CASE WHEN p_kunstner IS NULL THEN kunstner ELSE nullif(btrim(p_kunstner),'') END,
    datering = CASE WHEN p_datering IS NULL THEN datering ELSE nullif(btrim(p_datering),'') END
  WHERE id = p_media_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
END $$;

-- Fase 1 filside: symmetrisk genopretning af et blødt fjernet medie.
CREATE OR REPLACE FUNCTION red_genopret_media(p_media_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_genopret_media', format('Genoprettede media %s', p_media_id), 'media', p_media_id);
  UPDATE media SET upload_status='klar'
   WHERE id=p_media_id AND upload_status='fjernet';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Kan kun genoprette et fjernet medie'; END IF;
END $$;

-- Sæt/opdater rettigheds-gating + (valgfrit) rig rettigheds-dokumentation som fact på medie-entiteten
-- (Slice 1-brug; gating-kolonnerne virker allerede i Slice 0). Facts går via red_upsert_fakta (re-entrant).
CREATE OR REPLACE FUNCTION red_set_media_rettigheder(
  p_media_id bigint, p_status text, p_maa_publiceres boolean,
  p_licens text DEFAULT NULL, p_kildehenvisning text DEFAULT NULL,
  p_gengivelsestilladelse text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_media_rettigheder', format('Rettigheder for media %s → %s', p_media_id, p_status), 'media', p_media_id);
  UPDATE media SET rettigheder_status=coalesce(p_status, rettigheder_status),
                   maa_publiceres=coalesce(p_maa_publiceres, maa_publiceres)
   WHERE id=p_media_id;
  -- Rig rettigheds-dokumentation som facts (kun de udfyldte). Én løkke frem for tre ens IF-blokke.
  PERFORM red_upsert_fakta('media', p_media_id, r.felt, r.val, p_kilde_fritekst => p_kilde_fritekst)
    FROM (VALUES ('licens', p_licens), ('kildehenvisning', p_kildehenvisning),
                 ('gengivelsestilladelse', p_gengivelsestilladelse)) AS r(felt, val)
    WHERE nullif(btrim(r.val),'') IS NOT NULL;
END $$;

-- Slice 0h: "slet billede" som blødt fjern — upload_status='fjernet' udelukker mediet fra
-- media_rettigheder_ok (kræver 'klar') og dermed al anon/auth-synlighed uden ny RLS-politik.
-- Storage-bytes røres ikke (protect_delete-triggeren kommer aldrig i spil), og media har allerede
-- trg_log_media — ændringen er gratis fortrydbar via den eksisterende redaktionelle historik.
CREATE OR REPLACE FUNCTION red_fjern_media(p_media_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_fjern_media', format('Fjernede media %s', p_media_id), 'media', p_media_id);
  UPDATE media SET upload_status = 'fjernet' WHERE id = p_media_id;
END $$;

-- Registrér en klient-genkodet thumb/medium-variant efter dens bytes er landet i Storage
-- (samme to-trins-idé som red_bekraeft_media_upload, men uden 'kladde'-mellemtilstand: forælderens
-- upload_status gater ALT — en variant-række der findes før forælderen er 'klar' lækker intet).
-- UPSERT på (media_id, tier): et gen-upload (§6.3, ingen backfill — brugeren uploader selv igen)
-- skal opdatere variant-stien i stedet for at fejle på unique-index. IKKE et begin_change_set-kald:
-- media_variant er bevidst uden for versionering (se tabel-kommentar) og skal ikke lægge et tomt,
-- ufortrydbart change_set i redaktørens historik-visning.
CREATE OR REPLACE FUNCTION red_registrer_media_variant(
  p_media_id bigint, p_tier text, p_storage_path text,
  p_mime text DEFAULT NULL, p_byte_size bigint DEFAULT NULL,
  p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tier NOT IN ('thumb','medium') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig variant-tier. ''large'' er media-rækkens egen storage_path, ikke en variant-række.', p_tier;
  END IF;
  INSERT INTO media_variant(id, media_id, tier, storage_path, mime_type, byte_size, bredde, hoejde)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant), p_media_id, p_tier, p_storage_path, p_mime, p_byte_size, p_bredde, p_hoejde)
    ON CONFLICT (media_id, tier) DO UPDATE
      SET storage_path = excluded.storage_path, mime_type = excluded.mime_type,
          byte_size = excluded.byte_size, bredde = excluded.bredde, hoejde = excluded.hoejde
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- Fase 4 (M4): erstat mediets BYTES men behold dets IDENTITET (id, relationer, mentions,
-- rettigheder, bogmærkelinks). Klienten har lagt de nye bytes på NYE sha-stier FØRST
-- (fase 3-pipelinen, idempotent) — dette kald flytter rækkens identitet atomisk over på dem.
-- Gamle objekter overskrives ALDRIG: de bliver forældreløse (media_id_for_object → NULL =
-- fail-closed usynlige) og ryddes af janitorens kategori b efter --frist-dage — DET er
-- fortryd-vinduet (koncept §10.2). Varianter re-registreres INDE i transaktionen (et afbrud
-- må ikke efterlade ny large + gamle thumbs); red_registrer_media_variant åbner bevidst intet
-- eget change_set, så hele erstatningen er ÉT fortrydbart sæt — fortryd-historikken ER
-- filhistorikken (koncept §4.5), ingen media_version-tabel. KENDT begrænsning (B8, spec §3.2):
-- fortryd ruller kun media-rækken tilbage; variant-rækkerne er uversioneret cache og bliver
-- stående på de nye stier (selvopdagende thumb/large-mismatch — afhjælpes ved at erstatte igen).
CREATE OR REPLACE FUNCTION red_erstat_media_fil(
  p_media_id bigint,
  p_storage_path text, p_mime text, p_byte_size bigint,
  p_bredde int, p_hoejde int, p_sha256 text,
  p_original_filnavn text DEFAULT NULL,
  p_varianter jsonb DEFAULT '[]'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_egen_sha text; v_v record;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_storage_path),'') IS NULL THEN RAISE EXCEPTION 'Storage-sti er påkrævet'; END IF;
  IF nullif(btrim(p_sha256),'') IS NULL THEN RAISE EXCEPTION 'sha256 er påkrævet'; END IF;
  SELECT upload_status, sha256 INTO v_status, v_egen_sha FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- 'kladde' færdiggøres via fase 3's genoptag-flow; 'fjernet' genoprettes først.
  IF v_status <> 'klar' THEN RAISE EXCEPTION 'Kan kun erstatte filen på et klart medie'; END IF;
  -- Dedup-guard, to grene (klientens pre-flight fanger begge FØR bytes uploades; dette er race-bagstopperen):
  IF v_egen_sha = p_sha256 THEN RAISE EXCEPTION 'Filen er identisk med den nuværende'; END IF;
  IF EXISTS (SELECT 1 FROM media WHERE sha256 = p_sha256 AND id <> p_media_id) THEN
    RAISE EXCEPTION 'Medie med samme indhold findes allerede (sha256=%). Genbrug den eksisterende media-række via red_relation.', p_sha256;
  END IF;
  PERFORM begin_change_set('red_erstat_media_fil', format('Erstattede filen på media %s', p_media_id), 'media', p_media_id);
  -- Statustjekket er også del af selve UPDATE'ens WHERE (ikke kun den tidlige SELECT
  -- ovenfor): den tidlige SELECT er en billig fast-fail i det almindelige (ikke-race)
  -- tilfælde, men er IKKE i sig selv den autoritative gate — et konkurrerende
  -- red_fjern_media kan committe mellem SELECT og UPDATE (check-then-act race).
  -- Ved at gøre 'klar'-betingelsen atomisk med selve skrivningen lukkes racet.
  UPDATE media SET
    storage_path = p_storage_path, mime_type = p_mime, byte_size = p_byte_size,
    bredde = p_bredde, hoejde = p_hoejde, sha256 = p_sha256,
    original_filnavn = coalesce(nullif(btrim(p_original_filnavn),''), original_filnavn)
  WHERE id = p_media_id AND upload_status = 'klar';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kan kun erstatte filen på et klart medie';
  END IF;
  FOR v_v IN SELECT * FROM jsonb_to_recordset(coalesce(p_varianter,'[]'::jsonb))
      AS x(tier text, storage_path text, mime text, byte_size bigint, bredde int, hoejde int)
  LOOP
    PERFORM red_registrer_media_variant(p_media_id, v_v.tier, v_v.storage_path,
                                        v_v.mime, v_v.byte_size, v_v.bredde, v_v.hoejde);
  END LOOP;
END $$;

-- Fase 4 (M11): read-only forhåndsvisning af udrensning — bekræftelsesdialogens datagrundlag.
-- Kopierer red_slet_person_preview-kontrakten: SECURITY DEFINER, rolle-gated, intet change_set.
-- 'blokeringer' fortæller UI'et præcis hvorfor knappen er grå; 'stier' er samtidig klientens
-- arbejdsliste til Storage-sletningen — preview og udførelse deler ét sandhedsgrundlag.
-- Review 34 (H1/H3): tæller ALLE polymorfe ankre, ikke kun deklarative FK'er — relation
-- (begge retninger), text_mention, fact (rettighedsdokumentation via red_set_media_rettigheder;
-- evidenskæden assertion/citation/conclusion hænger på fact'et og blokeres med det), story og
-- narrative (deres RPC'er validerer ikke det polymorfe mål; haendelse cascader FRA narrative
-- og tælles bevidst ikke selvstændigt), note (defensivt — ingen live skriver i dag) samt
-- suggestion (Codex-review efter H1/H3: red_suggest accepterer ethvert p_subjekt_type/_id fra
-- enhver logget-ind bruger uden FK/CHECK — web-appens degraderingslogik ruter faktisk
-- ikke-redaktion-medlemmers medie-relaterede rettelser gennem red_suggest med
-- p_subjekt_type='media', så en forslags-række anker på et medie er en reel, deterministisk
-- konsekvens af normal app-brug, ikke en race).
-- Review 34 (L1): feltet hedder 'tilknytninger', IKKE 'afbildet' — det rummer enhver rolle.
CREATE OR REPLACE FUNCTION red_udrens_media_preview(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_tilknytninger jsonb; v_mentions jsonb; v_fakta jsonb; v_stories jsonb;
        v_narrativer jsonb; v_noter jsonb; v_forslag jsonb; v_stier jsonb; v_blok text[] := '{}';
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- ALLE relationer (enhver rolle, begge retninger) blokerer — ikke kun 'afbildet'.
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_tilknytninger FROM (
    SELECT id AS relation_id,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_type ELSE subjekt_type END AS modpart_type,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
       OR (objekt_type='media'  AND objekt_id=p_media_id)
    ORDER BY id) r;
  SELECT coalesce(jsonb_agg(m), '[]'::jsonb) INTO v_mentions FROM (
    SELECT kilde_type, kilde_id FROM text_mention
    WHERE maal_type='media' AND maal_id=p_media_id
    ORDER BY kilde_type, kilde_id) m;
  SELECT coalesce(jsonb_agg(f.id ORDER BY f.id), '[]'::jsonb) INTO v_fakta
    FROM fact f WHERE f.subjekt_type='media' AND f.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(s.id ORDER BY s.id), '[]'::jsonb) INTO v_stories
    FROM story s WHERE s.subjekt_type='media' AND s.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(n.id ORDER BY n.id), '[]'::jsonb) INTO v_narrativer
    FROM narrative n WHERE n.subjekt_type='media' AND n.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(t.id ORDER BY t.id), '[]'::jsonb) INTO v_noter
    FROM note t WHERE t.target_type='media' AND t.target_id=p_media_id;
  SELECT coalesce(jsonb_agg(g.id ORDER BY g.id), '[]'::jsonb) INTO v_forslag
    FROM suggestion g WHERE g.subjekt_type='media' AND g.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti, 'media' AS kilde FROM media
      WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path, v.tier FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  IF v_status <> 'fjernet' THEN
    v_blok := v_blok || 'Kan kun udrense et fjernet medie — fjern det først (papirkurven)';
  END IF;
  IF jsonb_array_length(v_tilknytninger) > 0 THEN
    v_blok := v_blok || format('%s tilknytning(er) skal fjernes først', jsonb_array_length(v_tilknytninger));
  END IF;
  IF jsonb_array_length(v_mentions) > 0 THEN
    v_blok := v_blok || format('%s narrativ-omtale(r) skal redigeres ud først', jsonb_array_length(v_mentions));
  END IF;
  IF jsonb_array_length(v_fakta) > 0 THEN
    v_blok := v_blok || format('Mediet har rettighedsdokumentation (%s faktum/fakta) — fjern den først', jsonb_array_length(v_fakta));
  END IF;
  IF jsonb_array_length(v_stories) > 0 THEN
    v_blok := v_blok || format('Mediet er subjekt for %s story/stories — flyt eller slet dem først', jsonb_array_length(v_stories));
  END IF;
  IF jsonb_array_length(v_narrativer) > 0 THEN
    v_blok := v_blok || format('Mediet har %s tilknyttet narrativ(er) — slet dem først', jsonb_array_length(v_narrativer));
  END IF;
  IF jsonb_array_length(v_noter) > 0 THEN
    v_blok := v_blok || format('%s note(r) peger på mediet — fjern dem først', jsonb_array_length(v_noter));
  END IF;
  IF jsonb_array_length(v_forslag) > 0 THEN
    v_blok := v_blok || format('Mediet har %s forslag i kø — afvis eller godkend dem først', jsonb_array_length(v_forslag));
  END IF;
  RETURN jsonb_build_object(
    'upload_status', v_status,
    'kan_udrenses', coalesce(array_length(v_blok,1),0) = 0,
    'blokeringer', to_jsonb(v_blok),
    'antal_tilknytninger', jsonb_array_length(v_tilknytninger),
    'antal_mentions', jsonb_array_length(v_mentions),
    'antal_fakta', jsonb_array_length(v_fakta),
    'antal_stories', jsonb_array_length(v_stories),
    'antal_narrativer', jsonb_array_length(v_narrativer),
    'antal_noter', jsonb_array_length(v_noter),
    'antal_forslag', jsonb_array_length(v_forslag),
    'tilknytninger', v_tilknytninger,
    'mentions', v_mentions,
    'fakta', v_fakta,
    'stories', v_stories,
    'narrativer', v_narrativer,
    'noter', v_noter,
    'forslag', v_forslag,
    'stier', v_stier);
END $$;

-- Fase 4 (M11): den rigtige sletning — række + (returnerede) stier. To-trins: KUN fra 'fjernet'
-- (blødt fjern først, koncept §4.3) og BLOKERET ved ethvert polymorft anker (review 34 H1/H3):
-- relation (begge retninger — ryddes eksplicit først via red_slet_relation /
-- red_slet_medierelation_uden_evidens, som håndterer polymorf evidens; flad DELETE her ville ikke),
-- text_mention (redigeres ud af prosaen manuelt), fact m. subjekt_type='media'
-- (rettighedsdokumentation fra red_set_media_rettigheder — evidenskæden assertion/citation/
-- conclusion hænger på fact'et og ville forældreløses af en flad media-DELETE), story og
-- narrative m. subjekt_type='media' (red_opret_story/red_upsert_narrativ validerer ikke målet;
-- haendelse cascader FRA narrative via ON DELETE CASCADE og kræver INGEN selvstændig kode),
-- note m. target_type='media' (DEFENSIVT — ingen live skriver i dag; red_slet_person-forsigtigheden)
-- samt suggestion m. subjekt_type='media' (Codex-review efter H1/H3: red_suggest — kun gated af
-- auth.uid() IS NOT NULL, ingen rolle-check — accepterer subjekt_type='media' fra ethvert
-- logget-ind medlem; web-appens degraderingslogik ruter faktisk medie-forslag herigennem, så
-- dette er en 7. reel polymorf anker, ikke en teoretisk).
-- Udrens kan derfor aldrig forældreløse evidens eller efterlade friske døde links
-- (red_doede_links-media-grenen er bagstopper for historiske tokens).
-- Review 34 (H2): guard-tjek + slet er kollapset til ÉT atomisk DELETE-statement — de venlige
-- RAISE-guards ovenfor giver præcise domæne-fejl, men den AUTORITATIVE gate er DELETE'ens egne
-- NOT EXISTS-betingelser, som ikke kan skilles fra sletningen af en samtidig skriver (fx
-- red_relation, der INSERT'er blindt). Postgres' standardmønster for check-then-act i en
-- polymorf, FK-fri model uden separate lås-primitiver. Rammer DELETE 0 rækker efter at
-- guardsne passerede, ændrede tilstanden sig undervejs → fail-loud, prøv igen.
-- Storage-sletning er KLIENT-SIDET og sker EFTER dette kald (Postgres-txn og Storage deler ikke
-- transaktion): DB-først garanterer at der aldrig findes en synlig række uden bytes; fejler
-- klientens storage.remove, er objekterne forældreløse = fail-closed usynlige + janitor-kategori-b.
-- media_variant CASCADE'r (uversioneret cache, ikke logget); media-rækken logges som DELETE med
-- foer-snapshot → red_fortryd_change_set kan genskabe RÆKKEN, men hverken varianter eller bytes
-- (dokumenteret, accepteret hazard — UI'et siger "kan ikke reelt fortrydes"; janitor-kategori c opdager).
CREATE OR REPLACE FUNCTION red_udrens_media(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_stier jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  IF v_status <> 'fjernet' THEN RAISE EXCEPTION 'Kan kun udrense et fjernet medie'; END IF;
  -- Venlige, kategori-præcise domæne-fejl (det atomiske DELETE nedenfor er den autoritative gate):
  IF EXISTS (SELECT 1 FROM relation
             WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                OR (objekt_type='media' AND objekt_id=p_media_id)) THEN
    RAISE EXCEPTION 'Mediet har tilknytninger og kan ikke udrenses — fjern dem først';
  END IF;
  IF EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først';
  END IF;
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har rettighedsdokumentation (fakta) og kan ikke udrenses — fjern den først';
  END IF;
  IF EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er subjekt for en story og kan ikke udrenses — flyt eller slet storyen først';
  END IF;
  IF EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har et tilknyttet narrativ og kan ikke udrenses — slet narrativet først';
  END IF;
  IF EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har noter og kan ikke udrenses — fjern dem først';
  END IF;
  IF EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har forslag i kø og kan ikke udrenses — afvis eller godkend dem først';
  END IF;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti FROM media WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  PERFORM begin_change_set('red_udrens_media', format('Udrensede media %s permanent', p_media_id), 'media', p_media_id);
  -- ÉT atomisk statement (H2): check-then-act kan ikke splittes af en samtidig transaktion.
  DELETE FROM media
   WHERE id = p_media_id
     AND upload_status = 'fjernet'
     AND NOT EXISTS (SELECT 1 FROM relation
                     WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                        OR (objekt_type='media' AND objekt_id=p_media_id))
     AND NOT EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=p_media_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mediet kunne ikke udrenses — tilstanden ændrede sig undervejs, prøv igen';
  END IF;
  RETURN jsonb_build_object('stier', v_stier);
END $$;

-- Fase 4 (M10): portræt som redaktionelt VALG — {"primaer":true} på personens afbildet-relation.
-- pickPortrait i læse-lagene prioriterer flaget og degraderer til slags-heuristikken (koncept §4.7).
-- relation_afbildet_uidx garanterer max én relation pr. (person, media)-par, så "sæt flaget på
-- parret" er entydigt. Retningen person→media er GDPR-invariantens (red_relation-guarden) — kun
-- den ene retning scannes. Ingen upload_status-guard: et flag på et senere-fjernet medie er
-- harmløst (læse-lagene ser kun synlige medier) og overlever genopret. p_media_id=NULL rydder
-- valget. relation står i version_pk_registry uden skip-cols → begge UPDATEs logges og fortrydes.
-- Samtidighed (review 34, M1 dismissed): to samtidige kald kan IKKE efterlade to primaer-flag
-- — begin_change_set's eget max(id)+1 på change_set kolliderer FØRST (unique_violation), og
-- taberen ruller hele sit kald tilbage før portræt-logikken nås. Verificeret umuligt, ikke
-- blot usandsynligt; ingen ekstra lås nødvendig.
CREATE OR REPLACE FUNCTION red_saet_portraet(p_person_id bigint, p_media_id bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_saet_portraet',
    CASE WHEN p_media_id IS NULL THEN format('Ryddede portræt-valg for person %s', p_person_id)
         ELSE format('Satte media %s som portræt for person %s', p_media_id, p_person_id) END,
    'person', p_person_id);
  -- Nulstil søskende først (én UPDATE): fjern nøglen; tom jsonb normaliseres til NULL.
  UPDATE relation SET kvalifikator = nullif(kvalifikator - 'primaer', '{}'::jsonb)
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND objekt_type='media' AND rolle='afbildet'
     AND kvalifikator ? 'primaer';
  IF p_media_id IS NOT NULL THEN
    UPDATE relation SET kvalifikator = coalesce(kvalifikator,'{}'::jsonb) || '{"primaer":true}'::jsonb
     WHERE subjekt_type='person' AND subjekt_id=p_person_id
       AND objekt_type='media' AND objekt_id=p_media_id AND rolle='afbildet';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      RAISE EXCEPTION 'Mediet er ikke tilknyttet personen — tilknyt først';
    END IF;
  END IF;
END $$;

-- =====================================================================
--  VERSIONERING + HYPERLINKS (2026-06-30)
--  Additive features: fortryd-bar redaktionel ændringshistorik + hyperlinks.
--  Spec: docs/superpowers/specs/2026-06-30-versionering-og-hyperlinks-design.md
-- =====================================================================

-- ---------- VERSIONERING: PK/skip-kolonne-registry ----------
-- Styrer den generiske log_change-trigger: hvilke kolonner udgør PK (→ row_pk)
-- og hvilke kolonner springes over i snapshot (afledt cache; spec-B8/B11).
CREATE TABLE IF NOT EXISTS version_pk_registry (
  tabel     TEXT PRIMARY KEY,
  pk_cols   TEXT[] NOT NULL,
  skip_cols TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('person',             ARRAY['id'], ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel','visning_efternavn','visning_fuldt_navn']),
  ('person_external_id', ARRAY['person_id','source_id'], '{}'),
  ('import_korrektion',  ARRAY['id'], '{}'),
  ('family',             ARRAY['id'], '{}'),
  ('family_member',      ARRAY['family_id','person_id','rolle'], '{}'),
  ('fact',               ARRAY['id'], '{}'),
  ('relation',           ARRAY['id'], '{}'),
  ('assertion',          ARRAY['id'], '{}'),
  ('conclusion',         ARRAY['id'], '{}'),
  ('citation',           ARRAY['id'], '{}'),
  ('narrative',          ARRAY['id'], '{}'),
  ('haendelse',          ARRAY['id'], ARRAY['subjekt_type','subjekt_id','narrative_id','noegle','span_start','span_laengde','klausul','kategori','date_min','date_max','date_qualifier','date_raw','fact_id','relation_id','pass_version']),
  ('story',              ARRAY['id'], '{}'),
  ('feed_pin',           ARRAY['id'], '{}'),
  ('note',               ARRAY['id'], '{}'),
  ('source',             ARRAY['id'], '{}'),
  ('repository',         ARRAY['id'], '{}'),
  ('place',              ARRAY['id'], '{}'),
  ('organisation',       ARRAY['id'], '{}'),
  ('estate',             ARRAY['id'], '{}'),
  ('media',              ARRAY['id'], '{}'),
  ('historical_event',   ARRAY['id'], '{}'),
  ('coat_of_arms',       ARRAY['id'], '{}'),
  ('lineage',            ARRAY['id'], '{}'),
  ('vocab',              ARRAY['scheme','code'], '{}'),
  ('profiles',           ARRAY['id'], ARRAY['email','rolle'])  -- versionér kun reventlow_person_id-binding (spec §4.3.1)
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;
-- ---------- VERSIONERING: change_set / change_event ----------
CREATE TABLE IF NOT EXISTS change_set (
  id                BIGINT PRIMARY KEY,
  actor_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,  -- frosne felter er autoritative (B3)
  actor_navn        TEXT,
  actor_rolle       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  operation         TEXT,
  summary           TEXT,
  subjekt_type      TEXT,
  subjekt_id        BIGINT,
  subjekt_synlighed TEXT,                       -- frosset: 'offentlig'|'levende'|'privat' (C1-sti)
  reverterer_id     BIGINT REFERENCES change_set(id)  -- dette saet fortroed hvilket (reversal-kaede; M3)
);

CREATE TABLE IF NOT EXISTS change_event (
  id            BIGINT PRIMARY KEY,
  change_set_id BIGINT NOT NULL REFERENCES change_set(id),
  seq           INT NOT NULL,
  tabel         TEXT NOT NULL,
  row_pk        JSONB NOT NULL,
  op            TEXT NOT NULL CHECK (op IN ('INSERT','UPDATE','DELETE')),
  foer          JSONB,
  efter         JSONB
);

CREATE INDEX IF NOT EXISTS ix_change_event_set  ON change_event(change_set_id, seq);
CREATE INDEX IF NOT EXISTS ix_change_set_subjekt ON change_set(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_change_set_revert  ON change_set(reverterer_id);
-- ---------- VERSIONERING: begin_change_set ----------
-- Synligheds-klasse på subjektet, frosset på commit-tid (C1-sti for fremtidig
-- medlems-historik). Kun person har levende/privat; øvrige = 'offentlig'.
CREATE OR REPLACE FUNCTION _subjekt_synlighed(p_type text, p_id bigint)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN p_type='person' THEN (
      SELECT CASE WHEN coalesce(pr.privat,false) THEN 'privat'
                  WHEN coalesce(pr.levende,false) THEN 'levende'
                  ELSE 'offentlig' END
      FROM person pr WHERE pr.id=p_id)
    ELSE 'offentlig' END;
$$;

-- Re-entrant: yderste kald ejer change_set'et; indre kald genbruger det aktive (B7).
CREATE OR REPLACE FUNCTION begin_change_set(
  p_operation text, p_summary text, p_subjekt_type text DEFAULT NULL, p_subjekt_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing text; v_id bigint; v_uid uuid; v_navn text; v_rolle text;
BEGIN
  v_existing := current_setting('app.change_set_id', true);
  IF v_existing IS NOT NULL AND v_existing <> '' THEN
    RETURN v_existing::bigint;  -- genbrug aktivt sæt; opret intet, nulstil intet
  END IF;
  v_uid := auth.uid();
  SELECT coalesce(p.navn, p.email, v_uid::text), p.rolle INTO v_navn, v_rolle
    FROM profiles p WHERE p.id = v_uid;
  v_navn  := coalesce(v_navn, 'ukendt');
  v_rolle := coalesce(v_rolle, 'medlem');
  v_id := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed)
    VALUES (v_id, v_uid, v_navn, v_rolle, p_operation, p_summary,
            p_subjekt_type, p_subjekt_id, _subjekt_synlighed(p_subjekt_type, p_subjekt_id));
  PERFORM set_config('app.change_set_id', v_id::text, true);
  PERFORM set_config('app.change_seq', '0', true);
  RETURN v_id;
END $$;
-- ---------- VERSIONERING: generisk log_change ----------
-- Byg kanonisk row_pk fra registry'ets pk_cols.
CREATE OR REPLACE FUNCTION _row_pk(p_tabel text, p_row jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT coalesce(jsonb_object_agg(k, p_row->k), '{}'::jsonb)
  FROM version_pk_registry r, unnest(r.pk_cols) k
  WHERE r.tabel = p_tabel;
$$;

CREATE OR REPLACE FUNCTION log_change()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  v_cs text; v_seq int; v_skip text[];
  v_foer jsonb; v_efter jsonb; v_old jsonb; v_new jsonb;
BEGIN
  v_cs := current_setting('app.change_set_id', true);
  IF v_cs IS NULL OR v_cs = '' THEN RETURN NULL; END IF;  -- bulk-load-sti: ingen logning

  SELECT skip_cols INTO v_skip FROM version_pk_registry WHERE tabel = TG_TABLE_NAME;
  v_skip := coalesce(v_skip, '{}');

  -- projektion: fjern skip-kolonner (afledt cache; B8)
  v_old := to_jsonb(OLD); v_new := to_jsonb(NEW);  -- serialisér én gang (ingen CSE i PL/pgSQL)
  v_foer  := CASE WHEN TG_OP='INSERT' THEN NULL ELSE (v_old - v_skip) END;
  v_efter := CASE WHEN TG_OP='DELETE' THEN NULL ELSE (v_new - v_skip) END;

  -- no-op-skip: hvis kun skip-kolonner ændrede sig (fx ren cache-regen), log intet
  IF TG_OP='UPDATE' AND v_foer = v_efter THEN RETURN NULL; END IF;

  v_seq := coalesce(nullif(current_setting('app.change_seq', true),''),'0')::int + 1;
  PERFORM set_config('app.change_seq', v_seq::text, true);

  INSERT INTO change_event(id, change_set_id, seq, tabel, row_pk, op, foer, efter)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event),
          v_cs::bigint, v_seq, TG_TABLE_NAME,
          _row_pk(TG_TABLE_NAME, coalesce(v_new, v_old)),
          TG_OP, v_foer, v_efter);
  RETURN NULL;
END $$;

-- Tilknyt log_change-trigger til alle registrerede tabeller (idempotent loop).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tabel FROM version_pk_registry LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_log_%1$s ON %1$I', r.tabel);
    EXECUTE format('CREATE TRIGGER trg_log_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I '
                || 'FOR EACH ROW EXECUTE FUNCTION log_change()', r.tabel);
  END LOOP;
END $$;
-- ---------- VERSIONERING: restore-hjælpere ----------
-- WHERE-klausul fra pk-jsonb med korrekt type-cast pr. kolonne (via udt_name).
CREATE OR REPLACE FUNCTION _version_pk_where(p_tabel text, p_pk jsonb)
RETURNS text LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT string_agg(format('%I = (%L)::%s', c.column_name, p_pk->>c.column_name, c.udt_name), ' AND ')
  FROM version_pk_registry r, unnest(r.pk_cols) k
  JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name=p_tabel AND c.column_name=k
  WHERE r.tabel=p_tabel;
$$;

CREATE OR REPLACE FUNCTION _version_current_row(p_tabel text, p_pk jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE v_skip text[]; v_row jsonb;
BEGIN
  SELECT coalesce(skip_cols,'{}') INTO v_skip FROM version_pk_registry WHERE tabel=p_tabel;
  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk))
    INTO v_row;
  RETURN v_row - v_skip;  -- samme projektion som log_change (NULL - skip = NULL)
END $$;

-- Genskab snapshot-tilstand: opdatér eksisterende række uden at røre skip-kolonner;
-- ved en slettet række bruges INSERT, hvor manglende kolonner får deres DEFAULT.
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_pk_cols text; v_set text; v_cols text; v_exists boolean;
BEGIN
  SELECT string_agg(quote_ident(k),',') INTO v_pk_cols
    FROM version_pk_registry r, unnest(r.pk_cols) k WHERE r.tabel=p_tabel;
  -- Kun kolonner i snapshot'et: INSERT lister dem eksplicit (skip_cols får DEFAULT, ikke NULL),
  -- ON CONFLICT opdaterer kun dem (skip_cols bevares). Undgår NOT NULL-crash på fx profiles.rolle
  -- og rul-tilbage af person.visning_*-cache. review09 H2.
  -- Ekskluder desuden GENERATED ALWAYS-kolonner (fx narrative.fts) — Postgres tillader IKKE en
  -- eksplicit værdi for dem i INSERT/UPDATE, uanset skip_cols; de genberegnes automatisk.
  -- Uden dette fejler fortryd hårdt for enhver tabel med en generated-kolonne (fundet ved
  -- manuel Expo-test 2026-07-01, ikke af statisk review).
  SELECT string_agg(quote_ident(key),','), string_agg(format('%I = excluded.%I', key, key), ',')
    INTO v_cols, v_set
    FROM jsonb_object_keys(p_row) AS key
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      WHERE c.relnamespace = 'public'::regnamespace AND c.relname = p_tabel
        AND a.attname = key AND a.attgenerated = 's'
    );
  -- En UPDATE-fortrydelse har stadig målrækken. Gå direkte til UPDATE, så Postgres ikke
  -- validerer en kunstig, ufuldstændig INSERT-række mod NOT NULL før ON CONFLICT (haendelse
  -- logger bevidst kun id+feed_status; alle regenererbare kolonner er skip_cols).
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE %s)',
                 p_tabel, _version_pk_where(p_tabel, _row_pk(p_tabel, p_row))) INTO v_exists;
  IF v_exists THEN
    EXECUTE format(
      'UPDATE %1$I SET (%2$s) = (SELECT %2$s FROM jsonb_populate_record(null::%1$I, $1)) WHERE %3$s',
      p_tabel, v_cols, _version_pk_where(p_tabel, _row_pk(p_tabel, p_row))) USING p_row;
    RETURN;
  END IF;
  EXECUTE format(
    'INSERT INTO %1$I (%2$s) SELECT %2$s FROM jsonb_populate_record(null::%1$I, $1) ON CONFLICT (%3$s) DO UPDATE SET %4$s',
    p_tabel, v_cols, v_pk_cols, v_set) USING p_row;
END $$;

CREATE OR REPLACE FUNCTION _version_delete_row(p_tabel text, p_pk jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  EXECUTE format('DELETE FROM %I WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk));
END $$;
-- ---------- VERSIONERING: restore ----------
CREATE OR REPLACE FUNCTION red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  ev change_event; v_new_cs bigint; v_orig change_set;
  v_cur jsonb; v_pids bigint[] := '{}'; v_narr bigint[] := '{}'; v_notes bigint[] := '{}';
  v_div int := 0; pid bigint; v_forventet jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT * INTO v_orig FROM change_set WHERE id=p_change_set_id;
  IF v_orig.id IS NULL THEN RAISE EXCEPTION 'FEJL: change_set % findes ikke', p_change_set_id; END IF;
  -- allerede reverteret? (reversal-kæde; M3)
  IF EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=p_change_set_id) THEN
    RAISE EXCEPTION 'FEJL: change_set % er allerede fortrudt', p_change_set_id;
  END IF;

  -- åbn reversal-sæt (re-entrant: triggere fanger ikke restore-DML ind under DET, da vi
  -- bevidst NULLER app.change_set_id under selve inverse — se nedenfor). Vi logger restore
  -- som ÉT change_set uden child-events for ikke at dobbelt-logge; reversal-kæden er sporet.
  PERFORM set_config('app.change_set_id','',true);  -- undgå at inverse-DML re-logges
  v_new_cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed, reverterer_id)
    VALUES (v_new_cs, auth.uid(),
            coalesce((SELECT coalesce(p.navn, p.email, auth.uid()::text) FROM profiles p WHERE p.id=auth.uid()), 'ukendt'),
            current_rolle(), 'fortryd',
            format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
            v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id);

  -- inverse-apply i OMVENDT seq-orden, alt i denne ene transaktion
  FOR ev IN SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq DESC LOOP
    -- optimistisk verifikation (B9): nuværende tilstand skal matche hvad sættet efterlod
    v_cur := _version_current_row(ev.tabel, ev.row_pk);
    -- B9-divergens for ALLE op-typer (review09 H1): DELETE efterlod række ABSENT (NULL),
    -- INSERT/UPDATE efterlod ev.efter. Lukker blind PK-overskrivning ved DELETE-inverse.
    v_forventet := CASE WHEN ev.op='DELETE' THEN NULL ELSE ev.efter END;
    IF v_cur IS DISTINCT FROM v_forventet THEN
      v_div := v_div + 1;
      IF NOT p_force THEN
        RAISE EXCEPTION 'FEJL: nyere ændring rører %/% — afvist (brug force)', ev.tabel, ev.row_pk;
      END IF;
    END IF;
    -- anvend inverse
    IF ev.op='INSERT' THEN
      PERFORM _version_delete_row(ev.tabel, ev.row_pk);
    ELSE  -- DELETE eller UPDATE: genskab foer-tilstand
      PERFORM _version_upsert_row(ev.tabel, ev.foer);
    END IF;
    -- saml berørte for cache/indeks-regen
    IF ev.tabel='person'    THEN v_pids := v_pids || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='conclusion' THEN
      SELECT f.subjekt_id INTO pid FROM fact f
        WHERE f.id=(coalesce(ev.foer,ev.efter)->>'target_id')::bigint AND f.subjekt_type='person';
      IF pid IS NOT NULL THEN v_pids := v_pids || pid; END IF;
    END IF;
    IF ev.tabel='narrative' THEN v_narr := v_narr || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='note'      THEN v_notes := v_notes || (ev.row_pk->>'id')::bigint; END IF;
  END LOOP;

  -- regenerér afledte projektioner ÉN gang (B8 + hyperlinks)
  FOR pid IN SELECT DISTINCT unnest(v_pids) LOOP
    PERFORM regen_person_visning(pid);
  END LOOP;
  -- text_mention regenereres af mention-trigger ved narrativ/note-skrivning (Task 10);
  -- ved restore kalder vi den eksplicit (funktion tilføjes i Task 10):
  PERFORM _regen_mentions_for('narrative', n) FROM unnest(v_narr) n;
  PERFORM _regen_mentions_for('note', n)      FROM unnest(v_notes) n;

  IF v_div > 0 THEN
    UPDATE change_set SET summary = summary || format(' [%s divergenser tvunget]', v_div) WHERE id=v_new_cs;
  END IF;
  RETURN jsonb_build_object('reversal_change_set', v_new_cs, 'divergenser', v_div);
END $$;
-- ---------- HYPERLINKS: token-parser ----------
-- Grammatik (spec §5.1): [[<type>:<id>|<visningstekst>]]
--   type ∈ fast vokabular; id = heltal uden foranstillede nuller; visningstekst vilkårlig
--   (| [ ] escapes som \| \[ \]). Malformet/ukendt type → ignoreres.
CREATE OR REPLACE FUNCTION parse_mentions(p_tekst text)
RETURNS TABLE(maal_type text, maal_id bigint) LANGUAGE sql IMMUTABLE SET search_path=public AS $$
  SELECT m[1] AS maal_type, m[2]::bigint AS maal_id
  FROM regexp_matches(
    coalesce(p_tekst,''),
    -- type-gruppe begrænset til vokabularet; id uden foranstillet nul (0 eller 1-9…)
    '\[\[(person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage):(0|[1-9][0-9]*)\|',
    'g'
  ) AS m;
$$;
-- ---------- HYPERLINKS: text_mention (afledt indeks) ----------
CREATE TABLE IF NOT EXISTS text_mention (
  kilde_type TEXT NOT NULL,            -- 'narrative' | 'note'
  kilde_id   BIGINT NOT NULL,
  maal_type  TEXT NOT NULL,
  maal_id    BIGINT NOT NULL,
  PRIMARY KEY (kilde_type, kilde_id, maal_type, maal_id)
);
CREATE INDEX IF NOT EXISTS ix_text_mention_maal ON text_mention(maal_type, maal_id);

-- Erstat HELE projektionen for én kilde-række (dedup via PK).
CREATE OR REPLACE FUNCTION _regen_mentions_for(p_kilde_type text, p_kilde_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_tekst text;
BEGIN
  DELETE FROM text_mention WHERE kilde_type=p_kilde_type AND kilde_id=p_kilde_id;
  IF p_kilde_type='narrative' THEN SELECT tekst INTO v_tekst FROM narrative WHERE id=p_kilde_id;
  ELSIF p_kilde_type='note'   THEN SELECT indhold INTO v_tekst FROM note WHERE id=p_kilde_id; END IF;
  IF v_tekst IS NULL THEN RETURN; END IF;
  INSERT INTO text_mention(kilde_type, kilde_id, maal_type, maal_id)
    SELECT p_kilde_type, p_kilde_id, maal_type, maal_id FROM parse_mentions(v_tekst)
    ON CONFLICT DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION trg_regen_mentions()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_kilde text := TG_TABLE_NAME;  -- 'narrative' | 'note'
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM text_mention WHERE kilde_type=v_kilde AND kilde_id=OLD.id;
  ELSE
    PERFORM _regen_mentions_for(v_kilde, NEW.id);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_mentions_narrative ON narrative;
CREATE TRIGGER trg_mentions_narrative AFTER INSERT OR UPDATE OR DELETE ON narrative
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();
DROP TRIGGER IF EXISTS trg_mentions_note ON note;
CREATE TRIGGER trg_mentions_note AFTER INSERT OR UPDATE OR DELETE ON note
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();

-- profiles.navn (kilde til frosset actor_navn; spec §6)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS navn TEXT;
-- ---------- VERSIONERING: redaktion-only historik-API (B10) ----------
CREATE OR REPLACE FUNCTION hist_for_subjekt(p_type text, p_id bigint)
RETURNS SETOF change_set LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_set
    WHERE subjekt_type=p_type AND subjekt_id=p_id ORDER BY created_at DESC;
END $$;

CREATE OR REPLACE FUNCTION hist_for_subjekter(p_type text, p_ids bigint[])
RETURNS SETOF change_set LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_set
    WHERE subjekt_type=p_type AND subjekt_id = ANY(p_ids) ORDER BY created_at DESC;
END $$;

CREATE OR REPLACE FUNCTION red_match_personer()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE result jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT jsonb_build_object(
    'persons', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'visning_navn', visning_navn, 'visning_fuldt_navn', visning_fuldt_navn,
      'koen', koen, 'staged', staged
    )) FROM person), '[]'::jsonb),
    'facts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'subjekt_id', subjekt_id, 'faktatype', faktatype
    )) FROM fact
      WHERE subjekt_type='person' AND faktatype IN ('fødsel','død','titel')), '[]'::jsonb),
    'concs', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'target_id', target_id, 'valgt_assertion_id', valgt_assertion_id
    )) FROM conclusion
      WHERE target_type='fact' AND status='afklaret'), '[]'::jsonb),
    'assertions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'date_min', date_min, 'date_max', date_max, 'vaerdi_tekst', vaerdi_tekst
    )) FROM assertion WHERE target_type='fact'), '[]'::jsonb),
    'extIds', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'person_id', person_id, 'source_id', source_id, 'linje', linje, 'nr', nr,
      'slaegtled_lokal', slaegtled_lokal, 'slaegtled_gennem', slaegtled_gennem, 'kuld', kuld
    )) FROM person_external_id), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION hist_events(p_change_set_id bigint)
RETURNS SETOF change_event LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq;
END $$;

-- ---------- EVIDENSIMPORT: ATOMISKE REDAKTIONSAFGØRELSER ----------
CREATE OR REPLACE FUNCTION red_decide_interpretation(
  p_interpretation_id uuid,
  p_expected_version integer,
  p_decision_status text,
  p_evidence jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_current private.interpretation%ROWTYPE;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_new_id uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<1 THEN
    RAISE EXCEPTION 'EVIDENCE_EXPECTED_VERSION_REQUIRED';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_ACTOR_REQUIRED'; END IF;
  IF p_decision_status NOT IN ('accepted','rejected','unresolved','superseded')
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_INVALID';
  END IF;

  SELECT * INTO v_current FROM private.interpretation
   WHERE id=p_interpretation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_NOT_FOUND'; END IF;
  IF v_current.version<>p_expected_version OR EXISTS (
    SELECT 1 FROM private.interpretation newer
     WHERE newer.interpretation_key=v_current.interpretation_key
       AND newer.version>v_current.version
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_VERSION_CONFLICT';
  END IF;

  INSERT INTO private.interpretation(
    id,interpretation_key,version,source_id,source_persona_id,
    interpretation_kind,predicate,value,schema_version,derivation_kind,
    confidence,status,method,model_version,prompt_version,extraction_run_id,
    supersedes_id,decision_evidence,decided_by,decided_by_name,decided_at
  ) VALUES (
    v_new_id,v_current.interpretation_key,v_current.version+1,v_current.source_id,
    v_current.source_persona_id,v_current.interpretation_kind,v_current.predicate,
    v_current.value,v_current.schema_version,v_current.derivation_kind,
    v_current.confidence,p_decision_status,v_current.method,v_current.model_version,
    v_current.prompt_version,v_current.extraction_run_id,v_current.id,p_evidence,
    v_actor,v_actor_name,clock_timestamp()
  );
  INSERT INTO private.interpretation_observation(
    interpretation_id,observation_id,evidence_role,ordinal
  )
  SELECT v_new_id,observation_id,evidence_role,ordinal
    FROM private.interpretation_observation
   WHERE interpretation_id=v_current.id;
  RETURN v_new_id;
END $$;

CREATE OR REPLACE FUNCTION red_promote_interpretation(
  p_interpretation_id uuid,
  p_target_type text,
  p_target_id bigint,
  p_evidence jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_id uuid;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL OR jsonb_typeof(p_evidence)<>'object'
     OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_INVALID';
  END IF;
  INSERT INTO private.interpretation_promotion(
    interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name
  ) VALUES (
    p_interpretation_id,p_target_type,p_target_id,p_evidence,v_actor,v_actor_name
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_decide_source_persona_identity(
  p_source_persona_id uuid,
  p_canonical_person_id bigint,
  p_expected_version integer,
  p_decision_status text,
  p_evidence jsonb
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_current_version integer;
  v_new_version integer;
  v_decided_at timestamptz := clock_timestamp();
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<0 THEN
    RAISE EXCEPTION 'EVIDENCE_EXPECTED_VERSION_REQUIRED';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_ACTOR_REQUIRED'; END IF;
  IF p_decision_status NOT IN ('accepted','rejected','unresolved','superseded')
     OR (p_decision_status='accepted' AND p_canonical_person_id IS NULL)
     OR (p_decision_status='unresolved' AND p_canonical_person_id IS NOT NULL)
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID';
  END IF;

  -- Persona-rækken findes også før første state-række og er derfor den stabile
  -- serialiseringslås for to samtidige initiale afgørelser.
  PERFORM 1 FROM private.source_persona
   WHERE id=p_source_persona_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PERSONA_NOT_FOUND'; END IF;
  SELECT version INTO v_current_version
    FROM private.source_persona_identity
   WHERE source_persona_id=p_source_persona_id FOR UPDATE;
  v_current_version:=coalesce(v_current_version,0);
  IF v_current_version<>p_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected %, current %',
      p_expected_version,v_current_version;
  END IF;
  v_new_version:=v_current_version+1;

  INSERT INTO private.source_persona_identity_event(
    source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at
  ) VALUES (
    p_source_persona_id,p_canonical_person_id,p_decision_status,v_new_version,
    p_evidence,v_actor,v_actor_name,v_decided_at
  );
  INSERT INTO private.source_persona_identity(
    source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at,updated_at
  ) VALUES (
    p_source_persona_id,p_canonical_person_id,p_decision_status,v_new_version,
    p_evidence,v_actor,v_actor_name,v_decided_at,v_decided_at
  )
  ON CONFLICT(source_persona_id) DO UPDATE SET
    canonical_person_id=excluded.canonical_person_id,
    decision_status=excluded.decision_status,
    version=excluded.version,
    evidence=excluded.evidence,
    decided_by=excluded.decided_by,
    decided_by_name=excluded.decided_by_name,
    decided_at=excluded.decided_at,
    updated_at=excluded.updated_at;
  RETURN v_new_version;
END $$;

REVOKE ALL ON FUNCTION red_decide_interpretation(uuid,integer,text,jsonb),
                       red_promote_interpretation(uuid,text,bigint,jsonb),
                       red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_decide_interpretation(uuid,integer,text,jsonb),
                          red_promote_interpretation(uuid,text,bigint,jsonb),
                          red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)
  TO authenticated;

-- Døde links: mentions hvis mål ikke længere findes.
-- Dækker HELE vokabularet i parse_mentions. Tidligere manglede family, place, organisation,
-- source, coat_of_arms og historical_event — et dødt link af de typer blev altså ikke bare
-- ignoreret, det blev rapporteret som "ingen døde links" (Codex sol, 2026-08-01).
CREATE OR REPLACE VIEW red_doede_links WITH (security_invoker = true) AS
SELECT m.* FROM text_mention m
WHERE (m.maal_type='person' AND NOT EXISTS (SELECT 1 FROM person  p WHERE p.id=m.maal_id))
   OR (m.maal_type='estate' AND NOT EXISTS (SELECT 1 FROM estate  e WHERE e.id=m.maal_id))
   OR (m.maal_type='lineage' AND NOT EXISTS (SELECT 1 FROM lineage l WHERE l.id=m.maal_id))
   OR (m.maal_type='media' AND NOT EXISTS (SELECT 1 FROM media md WHERE md.id=m.maal_id))
   OR (m.maal_type='family' AND NOT EXISTS (SELECT 1 FROM family f WHERE f.id=m.maal_id))
   OR (m.maal_type='place' AND NOT EXISTS (SELECT 1 FROM place pl WHERE pl.id=m.maal_id))
   OR (m.maal_type='organisation' AND NOT EXISTS (SELECT 1 FROM organisation o WHERE o.id=m.maal_id))
   OR (m.maal_type='source' AND NOT EXISTS (SELECT 1 FROM source s WHERE s.id=m.maal_id))
   OR (m.maal_type='coat_of_arms' AND NOT EXISTS (SELECT 1 FROM coat_of_arms c WHERE c.id=m.maal_id))
   OR (m.maal_type='historical_event' AND NOT EXISTS (SELECT 1 FROM historical_event h WHERE h.id=m.maal_id));
