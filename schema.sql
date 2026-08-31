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
  id            BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
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
  public_ref     uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
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

CREATE TABLE private.interpretation_promotion_rule_line (
  rule_key   text PRIMARY KEY CHECK (btrim(rule_key)<>''),
  predicate  text NOT NULL UNIQUE CHECK (btrim(predicate)<>''),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (rule_key,predicate)
);

CREATE TABLE private.interpretation_promotion_rule (
  rule_key                      text NOT NULL CHECK (btrim(rule_key)<>''),
  rule_version                  integer NOT NULL CHECK (rule_version>=1),
  predicate                     text NOT NULL CHECK (btrim(predicate)<>''),
  interpretation_kind           text NOT NULL CHECK (interpretation_kind='property'),
  target_type                   text NOT NULL CHECK (target_type='assertion'),
  expected_fact_type            text NOT NULL CHECK (
                                 expected_fact_type IN ('navn','tilnavn','titel','fødsel','død')
                               ),
  value_kind                    text NOT NULL CHECK (value_kind IN ('text','date_raw')),
  requires_persona_identity     boolean NOT NULL DEFAULT true,
  requires_principal_placement  boolean NOT NULL DEFAULT false,
  bulk_eligible                 boolean NOT NULL DEFAULT true,
  status                        text NOT NULL CHECK (status IN ('active','retired')),
  created_at                    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rule_key,rule_version),
  UNIQUE (predicate,rule_version),
  FOREIGN KEY (rule_key,predicate)
    REFERENCES private.interpretation_promotion_rule_line(rule_key,predicate)
);

CREATE TABLE private.interpretation_promotion_authorization (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  preview_hash      text NOT NULL CHECK (preview_hash ~ '^[0-9a-f]{64}$'),
  rule_profile      jsonb NOT NULL CHECK (jsonb_typeof(rule_profile)='object'),
  rule_profile_hash text NOT NULL CHECK (rule_profile_hash ~ '^[0-9a-f]{64}$'),
  request_sha256    text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
  database_identity jsonb NOT NULL CHECK (jsonb_typeof(database_identity)='object'),
  actor_id          uuid NOT NULL,
  nonce             uuid NOT NULL,
  issued_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  consumed_at       timestamptz,
  expires_at        timestamptz NOT NULL,
  status            text NOT NULL DEFAULT 'issued' CHECK (status IN ('issued','consumed','expired')),
  CHECK (expires_at>issued_at),
  CHECK ((status='issued' AND consumed_at IS NULL) OR (status='consumed' AND consumed_at IS NOT NULL)
      OR (status='expired' AND consumed_at IS NULL)),
  UNIQUE (actor_id,nonce),
  UNIQUE (id,preview_hash,rule_profile_hash,actor_id,database_identity)
);
CREATE UNIQUE INDEX interpretation_promotion_authorization_open_scope_uq
  ON private.interpretation_promotion_authorization(database_identity,request_sha256)
  WHERE status='issued';

CREATE TABLE private.interpretation_promotion_batch (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id  uuid NOT NULL UNIQUE,
  rule_profile_hash text NOT NULL CHECK (rule_profile_hash ~ '^[0-9a-f]{64}$'),
  preview_hash      text NOT NULL CHECK (preview_hash ~ '^[0-9a-f]{64}$'),
  database_identity jsonb NOT NULL CHECK (jsonb_typeof(database_identity)='object'),
  promoted_by       uuid NOT NULL,
  promoted_by_name  text NOT NULL CHECK (btrim(promoted_by_name)<>''),
  promoted_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  requested_count   integer NOT NULL CHECK (requested_count>0),
  status            text NOT NULL DEFAULT 'open' CHECK (status IN ('open','finalized')),
  observed_counts   jsonb,
  receipt           jsonb,
  receipt_sha256    text,
  finalized_at      timestamptz,
  CHECK ((status='open' AND observed_counts IS NULL AND receipt IS NULL
          AND receipt_sha256 IS NULL AND finalized_at IS NULL)
      OR (status='finalized' AND observed_counts IS NOT NULL AND receipt IS NOT NULL
          AND receipt_sha256 ~ '^[0-9a-f]{64}$' AND finalized_at IS NOT NULL)),
  FOREIGN KEY (authorization_id,preview_hash,rule_profile_hash,promoted_by,database_identity)
    REFERENCES private.interpretation_promotion_authorization(
      id,preview_hash,rule_profile_hash,actor_id,database_identity
    )
);

INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES
  ('person-name-v1','person.name'),
  ('person-byname-v1','person.byname'),
  ('person-title-v1','person.title'),
  ('person-birth-v1','person.birth'),
  ('person-death-v1','person.death');

INSERT INTO private.interpretation_promotion_rule(
  rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
  value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status
) VALUES
  ('person-name-v1',1,'person.name','property','assertion','navn','text',true,false,true,'active'),
  ('person-byname-v1',1,'person.byname','property','assertion','tilnavn','text',true,false,true,'active'),
  ('person-title-v1',1,'person.title','property','assertion','titel','text',true,false,true,'active'),
  ('person-birth-v1',1,'person.birth','property','assertion','fødsel','date_raw',true,false,true,'active'),
  ('person-death-v1',1,'person.death','property','assertion','død','date_raw',true,false,true,'active');

CREATE VIEW private.interpretation_promotion_rule_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (rule_key) *
  FROM private.interpretation_promotion_rule
 ORDER BY rule_key,rule_version DESC;

CREATE FUNCTION private.add_interpretation_promotion_rule_version(
  p_rule_key text,p_predicate text,p_interpretation_kind text,p_target_type text,
  p_expected_fact_type text,p_value_kind text,p_requires_persona_identity boolean,
  p_requires_principal_placement boolean,p_bulk_eligible boolean,p_status text
) RETURNS integer LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_predicate text; v_version integer;
BEGIN
  SELECT predicate INTO v_predicate
    FROM private.interpretation_promotion_rule_line
   WHERE rule_key=p_rule_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_LINE_NOT_FOUND'; END IF;
  IF v_predicate<>p_predicate THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_PREDICATE_MISMATCH'; END IF;
  SELECT coalesce(max(rule_version),0)+1 INTO v_version
    FROM private.interpretation_promotion_rule WHERE rule_key=p_rule_key;
  INSERT INTO private.interpretation_promotion_rule(
    rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
    value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status
  ) VALUES (p_rule_key,v_version,p_predicate,p_interpretation_kind,p_target_type,
    p_expected_fact_type,p_value_kind,p_requires_persona_identity,
    p_requires_principal_placement,p_bulk_eligible,p_status);
  RETURN v_version;
END $$;

CREATE TABLE private.interpretation_promotion (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interpretation_id   uuid NOT NULL REFERENCES private.interpretation(id),
  rule_key            text,
  rule_version        integer,
  batch_id            uuid NOT NULL CONSTRAINT interpretation_promotion_batch_fk
                      REFERENCES private.interpretation_promotion_batch(id),
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
  UNIQUE (interpretation_id,target_type,target_id),
  CONSTRAINT interpretation_promotion_rule_fk FOREIGN KEY (rule_key,rule_version)
    REFERENCES private.interpretation_promotion_rule(rule_key,rule_version),
  CONSTRAINT interpretation_promotion_rule_pair_check CHECK (
    (rule_key IS NULL AND rule_version IS NULL)
    OR (rule_key IS NOT NULL AND rule_version IS NOT NULL)
  )
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
  CONSTRAINT source_persona_identity_target_check CHECK (
    (decision_status='accepted' AND canonical_person_id IS NOT NULL)
    OR (decision_status<>'accepted' AND canonical_person_id IS NULL)
  ),
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
  CONSTRAINT source_persona_identity_event_target_check CHECK (
    (decision_status='accepted' AND canonical_person_id IS NOT NULL)
    OR (decision_status<>'accepted' AND canonical_person_id IS NULL)
  ),
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
    'interpretation','interpretation_observation','interpretation_promotion_rule_line',
    'interpretation_promotion_rule','interpretation_promotion',
    'source_persona_identity_event'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON private.%I '
      || 'FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation()',
      'trg_'||v_table||'_append_only',v_table
    );
  END LOOP;
  FOREACH v_table IN ARRAY ARRAY[
    'interpretation','interpretation_observation','interpretation_promotion_rule_line',
    'interpretation_promotion_rule',
    'interpretation_promotion_authorization','interpretation_promotion_batch','interpretation_promotion',
    'source_persona_identity','source_persona_identity_event'
  ] LOOP
    EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',v_table);
  END LOOP;
END $$;

REVOKE ALL ON TABLE private.interpretation_current,
                    private.interpretation_promotion_rule_current
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.validate_interpretation_scope(),
                           private.validate_interpretation_observation(),
                           private.assert_interpretation_has_observation(),
                           private.validate_interpretation_promotion(),
                           private.validate_source_persona_identity_event(),
                           private.validate_source_persona_identity_state(),
                           private.assert_identity_state_event_consistency(),
                           private.add_interpretation_promotion_rule_version(
                             text,text,text,text,text,text,boolean,boolean,boolean,text
                           )
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
ALTER TABLE lineage
  ADD CONSTRAINT lineage_id_slaegt_uidx UNIQUE (id,slaegt_id);
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
  UNIQUE (slaegt_id,source_id,kind),
  CONSTRAINT lineage_scheme_id_slaegt_uidx UNIQUE (id,slaegt_id)
);
CREATE UNIQUE INDEX lineage_scheme_slaegt_kind_no_source_uidx
  ON lineage_scheme(slaegt_id,kind) WHERE source_id IS NULL;

CREATE TABLE lineage_scheme_entry (
  id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  scheme_id        bigint NOT NULL,
  slaegt_id        bigint NOT NULL,
  code             text NOT NULL CHECK (btrim(code)<>''),
  label            text NOT NULL CHECK (btrim(label)<>''),
  sort_order       integer NOT NULL CHECK (sort_order>=0),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scheme_id,code),
  UNIQUE (scheme_id,sort_order),
  CONSTRAINT lineage_scheme_entry_id_slaegt_uidx UNIQUE (id,slaegt_id),
  CONSTRAINT lineage_scheme_entry_scheme_slaegt_fkey
    FOREIGN KEY (scheme_id,slaegt_id) REFERENCES lineage_scheme(id,slaegt_id)
);

CREATE TABLE lineage_scheme_entry_lineage (
  entry_id         bigint NOT NULL,
  lineage_id       bigint NOT NULL,
  slaegt_id        bigint NOT NULL,
  relation_kind    text NOT NULL CHECK (relation_kind IN ('canonical','historical_alias','source_only')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entry_id,lineage_id,relation_kind),
  CONSTRAINT lineage_scheme_entry_lineage_entry_slaegt_fkey
    FOREIGN KEY (entry_id,slaegt_id) REFERENCES lineage_scheme_entry(id,slaegt_id),
  CONSTRAINT lineage_scheme_entry_lineage_lineage_slaegt_fkey
    FOREIGN KEY (lineage_id,slaegt_id) REFERENCES lineage(id,slaegt_id)
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
  initial_status         text NOT NULL DEFAULT 'proposed'
                         CHECK (initial_status IN ('proposed','accepted','rejected','superseded')),
  created_at             timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.source_persona_placement (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_persona_id      uuid NOT NULL REFERENCES private.source_persona(id),
  record_placement_id    uuid NOT NULL REFERENCES private.source_record_placement(id),
  placement_role         text NOT NULL CHECK (placement_role IN (
                         'principal_member','co_principal','mentioned_spouse','child_reference')),
  basis_observation_id   uuid NOT NULL REFERENCES private.source_observation(id),
  initial_status         text NOT NULL DEFAULT 'proposed'
                         CHECK (initial_status IN ('proposed','accepted','rejected','superseded')),
  created_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_persona_id,record_placement_id,placement_role)
);

CREATE TABLE private.source_record_placement_decision (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  placement_id    uuid NOT NULL REFERENCES private.source_record_placement(id),
  version         integer NOT NULL CHECK (version>=1),
  decision_status text NOT NULL CHECK (decision_status IN ('proposed','accepted','rejected','superseded')),
  evidence        jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object' AND evidence<>'{}'::jsonb),
  decision_origin text NOT NULL CHECK (decision_origin IN ('ingest','migration','redaction')),
  decided_by      uuid,
  decided_by_name text NOT NULL CHECK (btrim(decided_by_name)<>''),
  decided_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (placement_id,version),
  CHECK (decision_origin<>'redaction' OR decided_by IS NOT NULL)
);

CREATE TABLE private.source_persona_placement_decision (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  placement_id    uuid NOT NULL REFERENCES private.source_persona_placement(id),
  version         integer NOT NULL CHECK (version>=1),
  decision_status text NOT NULL CHECK (decision_status IN ('proposed','accepted','rejected','superseded')),
  evidence        jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object' AND evidence<>'{}'::jsonb),
  decision_origin text NOT NULL CHECK (decision_origin IN ('ingest','migration','redaction')),
  decided_by      uuid,
  decided_by_name text NOT NULL CHECK (btrim(decided_by_name)<>''),
  decided_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (placement_id,version),
  CHECK (decision_origin<>'redaction' OR decided_by IS NOT NULL)
);

CREATE VIEW private.source_record_placement_current
WITH (security_invoker=true) AS
SELECT placement.*,decision.version,decision.decision_status,decision.evidence,
       decision.decision_origin,decision.decided_by,decision.decided_by_name,decision.decided_at
  FROM private.source_record_placement placement
  JOIN (SELECT DISTINCT ON (placement_id) *
          FROM private.source_record_placement_decision
         ORDER BY placement_id,version DESC) decision
    ON decision.placement_id=placement.id;

CREATE VIEW private.source_persona_placement_current
WITH (security_invoker=true) AS
SELECT placement.*,decision.version,decision.decision_status,decision.evidence,
       decision.decision_origin,decision.decided_by,decision.decided_by_name,decision.decided_at
  FROM private.source_persona_placement placement
  JOIN (SELECT DISTINCT ON (placement_id) *
          FROM private.source_persona_placement_decision
         ORDER BY placement_id,version DESC) decision
    ON decision.placement_id=placement.id;

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

CREATE FUNCTION private.validate_placement_decision()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_initial_status text;
  v_previous_status text;
  v_previous_version integer;
  v_record_id uuid;
  v_scheme_entry_id bigint;
  v_record_placement_id uuid;
BEGIN
  IF TG_TABLE_NAME='source_record_placement_decision' THEN
    SELECT initial_status INTO v_initial_status
      FROM private.source_record_placement WHERE id=NEW.placement_id;
    SELECT version,decision_status INTO v_previous_version,v_previous_status
      FROM private.source_record_placement_decision
     WHERE placement_id=NEW.placement_id ORDER BY version DESC LIMIT 1;
  ELSE
    SELECT initial_status INTO v_initial_status
      FROM private.source_persona_placement WHERE id=NEW.placement_id;
    SELECT version,decision_status INTO v_previous_version,v_previous_status
      FROM private.source_persona_placement_decision
     WHERE placement_id=NEW.placement_id ORDER BY version DESC LIMIT 1;
  END IF;
  IF v_initial_status IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_NOT_FOUND';
  END IF;
  IF v_previous_version IS NULL THEN
    IF NEW.version<>1 OR NEW.decision_status<>v_initial_status
       OR NEW.decision_origin NOT IN ('ingest','migration') THEN
      RAISE EXCEPTION 'EVIDENCE_PLACEMENT_INITIAL_DECISION_INVALID';
    END IF;
  ELSIF NEW.version<>v_previous_version+1
     OR NEW.decision_origin<>'redaction'
     OR NOT ((v_previous_status='proposed' AND NEW.decision_status IN ('accepted','rejected'))
          OR (v_previous_status='accepted' AND NEW.decision_status='superseded')) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_TRANSITION_INVALID';
  END IF;
  IF NEW.decision_status='accepted' AND TG_TABLE_NAME='source_record_placement_decision' THEN
    SELECT source_record_id,scheme_entry_id INTO v_record_id,v_scheme_entry_id
      FROM private.source_record_placement WHERE id=NEW.placement_id;
    PERFORM 1 FROM private.source_record WHERE id=v_record_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM private.source_record_placement_current current_placement
                WHERE current_placement.source_record_id=v_record_id
                  AND current_placement.scheme_entry_id=v_scheme_entry_id
                  AND current_placement.id<>NEW.placement_id
                  AND current_placement.decision_status='accepted') THEN
      RAISE EXCEPTION 'EVIDENCE_PLACEMENT_ALREADY_ACCEPTED';
    END IF;
  ELSIF NEW.decision_status='accepted' THEN
    SELECT record_placement_id INTO v_record_placement_id
      FROM private.source_persona_placement WHERE id=NEW.placement_id;
    IF NOT EXISTS (SELECT 1 FROM private.source_record_placement_current
                    WHERE id=v_record_placement_id AND decision_status='accepted') THEN
      RAISE EXCEPTION 'EVIDENCE_RECORD_PLACEMENT_ACCEPTED_REQUIRED';
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION private.require_placement_initial_decision()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF TG_TABLE_NAME='source_record_placement' THEN
    IF NOT EXISTS (SELECT 1 FROM private.source_record_placement_decision
                    WHERE placement_id=NEW.id AND version=1) THEN
      RAISE EXCEPTION 'EVIDENCE_PLACEMENT_INITIAL_DECISION_REQUIRED';
    END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM private.source_persona_placement_decision
                     WHERE placement_id=NEW.id AND version=1) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_INITIAL_DECISION_REQUIRED';
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION private.propose_source_record_placement(
  p_source_record_id uuid,p_scheme_entry_id bigint,p_header_observation_id uuid,
  p_evidence jsonb,p_decided_by_name text DEFAULT 'evidence ingest'
) RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid;
BEGIN
  IF jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb
     OR btrim(coalesce(p_decided_by_name,''))='' THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_PROPOSAL_INVALID';
  END IF;
  INSERT INTO private.source_record_placement(
    source_record_id,scheme_entry_id,header_observation_id,initial_status
  ) VALUES (p_source_record_id,p_scheme_entry_id,p_header_observation_id,'proposed')
  RETURNING id INTO v_id;
  INSERT INTO private.source_record_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by_name
  ) VALUES (v_id,1,'proposed',p_evidence,'ingest',p_decided_by_name);
  RETURN v_id;
END $$;

CREATE FUNCTION private.propose_source_persona_placement(
  p_source_persona_id uuid,p_record_placement_id uuid,p_placement_role text,
  p_basis_observation_id uuid,p_evidence jsonb,p_decided_by_name text DEFAULT 'evidence ingest'
) RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid;
BEGIN
  IF jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb
     OR btrim(coalesce(p_decided_by_name,''))='' THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_PROPOSAL_INVALID';
  END IF;
  INSERT INTO private.source_persona_placement(
    source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status
  ) VALUES (p_source_persona_id,p_record_placement_id,p_placement_role,p_basis_observation_id,'proposed')
  RETURNING id INTO v_id;
  INSERT INTO private.source_persona_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by_name
  ) VALUES (v_id,1,'proposed',p_evidence,'ingest',p_decided_by_name);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_decide_source_record_placement(
  p_placement_id uuid,p_expected_version integer,p_status text,p_evidence jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_actor_name text; v_record_id uuid; v_scheme_entry_id bigint;
  v_current_version integer; v_current_status text; v_new_version integer;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF p_expected_version IS NULL OR p_expected_version<1 THEN RAISE EXCEPTION 'EVIDENCE_EXPECTED_VERSION_REQUIRED'; END IF;
  IF p_status NOT IN ('accepted','rejected','superseded')
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_DECISION_INVALID';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_ACTOR_REQUIRED'; END IF;
  SELECT source_record_id,scheme_entry_id INTO v_record_id,v_scheme_entry_id
    FROM private.source_record_placement WHERE id=p_placement_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PLACEMENT_NOT_FOUND'; END IF;
  PERFORM 1 FROM private.source_record WHERE id=v_record_id FOR UPDATE;
  PERFORM 1 FROM private.source_record_placement WHERE id=p_placement_id FOR UPDATE;
  SELECT version,decision_status INTO v_current_version,v_current_status
    FROM private.source_record_placement_decision WHERE placement_id=p_placement_id
   ORDER BY version DESC LIMIT 1 FOR UPDATE;
  IF v_current_version IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PLACEMENT_INITIAL_DECISION_REQUIRED'; END IF;
  IF v_current_version<>p_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_VERSION_CONFLICT: expected %, current %',p_expected_version,v_current_version;
  END IF;
  IF NOT ((v_current_status='proposed' AND p_status IN ('accepted','rejected'))
       OR (v_current_status='accepted' AND p_status='superseded')) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_TRANSITION_INVALID';
  END IF;
  IF p_status='accepted' AND EXISTS (
    SELECT 1 FROM private.source_record_placement_current current_placement
     WHERE current_placement.source_record_id=v_record_id
       AND current_placement.scheme_entry_id=v_scheme_entry_id
       AND current_placement.id<>p_placement_id
       AND current_placement.decision_status='accepted'
  ) THEN RAISE EXCEPTION 'EVIDENCE_PLACEMENT_ALREADY_ACCEPTED'; END IF;
  v_new_version:=v_current_version+1;
  INSERT INTO private.source_record_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by,decided_by_name
  ) VALUES (p_placement_id,v_new_version,p_status,p_evidence,'redaction',v_actor,v_actor_name);
  RETURN v_new_version;
END $$;

CREATE OR REPLACE FUNCTION red_decide_source_persona_placement(
  p_placement_id uuid,p_expected_version integer,p_status text,p_evidence jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_actor_name text; v_persona_id uuid; v_record_placement_id uuid;
  v_current_version integer; v_current_status text; v_new_version integer;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF p_expected_version IS NULL OR p_expected_version<1 THEN RAISE EXCEPTION 'EVIDENCE_EXPECTED_VERSION_REQUIRED'; END IF;
  IF p_status NOT IN ('accepted','rejected','superseded')
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_DECISION_INVALID';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_ACTOR_REQUIRED'; END IF;
  SELECT source_persona_id,record_placement_id INTO v_persona_id,v_record_placement_id
    FROM private.source_persona_placement WHERE id=p_placement_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PLACEMENT_NOT_FOUND'; END IF;
  PERFORM 1 FROM private.source_persona WHERE id=v_persona_id FOR UPDATE;
  PERFORM 1 FROM private.source_record_placement WHERE id=v_record_placement_id FOR UPDATE;
  PERFORM 1 FROM private.source_persona_placement WHERE id=p_placement_id FOR UPDATE;
  SELECT version,decision_status INTO v_current_version,v_current_status
    FROM private.source_persona_placement_decision WHERE placement_id=p_placement_id
   ORDER BY version DESC LIMIT 1 FOR UPDATE;
  IF v_current_version IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PLACEMENT_INITIAL_DECISION_REQUIRED'; END IF;
  IF v_current_version<>p_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_VERSION_CONFLICT: expected %, current %',p_expected_version,v_current_version;
  END IF;
  IF NOT ((v_current_status='proposed' AND p_status IN ('accepted','rejected'))
       OR (v_current_status='accepted' AND p_status='superseded')) THEN
    RAISE EXCEPTION 'EVIDENCE_PLACEMENT_TRANSITION_INVALID';
  END IF;
  IF p_status='accepted' AND NOT EXISTS (
    SELECT 1 FROM private.source_record_placement_current
     WHERE id=v_record_placement_id AND decision_status='accepted'
  ) THEN RAISE EXCEPTION 'EVIDENCE_RECORD_PLACEMENT_ACCEPTED_REQUIRED'; END IF;
  v_new_version:=v_current_version+1;
  INSERT INTO private.source_persona_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by,decided_by_name
  ) VALUES (p_placement_id,v_new_version,p_status,p_evidence,'redaction',v_actor,v_actor_name);
  RETURN v_new_version;
END $$;

CREATE TRIGGER trg_source_record_placement_validate
  BEFORE INSERT ON private.source_record_placement
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_record_placement();
CREATE TRIGGER trg_source_persona_placement_validate
  BEFORE INSERT ON private.source_persona_placement
  FOR EACH ROW EXECUTE FUNCTION private.validate_source_persona_placement();
CREATE TRIGGER trg_source_record_placement_decision_validate
  BEFORE INSERT ON private.source_record_placement_decision
  FOR EACH ROW EXECUTE FUNCTION private.validate_placement_decision();
CREATE TRIGGER trg_source_persona_placement_decision_validate
  BEFORE INSERT ON private.source_persona_placement_decision
  FOR EACH ROW EXECUTE FUNCTION private.validate_placement_decision();
CREATE CONSTRAINT TRIGGER trg_source_record_placement_has_decision
  AFTER INSERT ON private.source_record_placement DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.require_placement_initial_decision();
CREATE CONSTRAINT TRIGGER trg_source_persona_placement_has_decision
  AFTER INSERT ON private.source_persona_placement DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.require_placement_initial_decision();
CREATE TRIGGER trg_source_record_placement_append_only
  BEFORE UPDATE OR DELETE ON private.source_record_placement
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
CREATE TRIGGER trg_source_persona_placement_append_only
  BEFORE UPDATE OR DELETE ON private.source_persona_placement
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
CREATE TRIGGER trg_source_record_placement_decision_append_only
  BEFORE UPDATE OR DELETE ON private.source_record_placement_decision
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
CREATE TRIGGER trg_source_persona_placement_decision_append_only
  BEFORE UPDATE OR DELETE ON private.source_persona_placement_decision
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();

ALTER TABLE slaegt ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineage_scheme_entry_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_slaegt_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_lineage_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_record_placement ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_persona_placement ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_record_placement_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_persona_placement_decision ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE person_slaegt_membership,person_lineage_membership,
                    private.source_record_placement,private.source_persona_placement,
                    private.source_record_placement_decision,private.source_persona_placement_decision
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.validate_source_record_placement(),
                           private.validate_source_persona_placement(),
                           private.validate_placement_decision(),
                           private.require_placement_initial_decision(),
                           private.propose_source_record_placement(uuid,bigint,uuid,jsonb,text),
                           private.propose_source_persona_placement(uuid,uuid,text,uuid,jsonb,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION red_decide_source_record_placement(uuid,integer,text,jsonb),
                       red_decide_source_persona_placement(uuid,integer,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION red_decide_source_record_placement(uuid,integer,text,jsonb),
                          red_decide_source_persona_placement(uuid,integer,text,jsonb) TO authenticated;

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
  id            BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
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
  id             BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
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
  id                BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  target_type       TEXT NOT NULL,       -- 'fact' | 'relation'
  target_id         BIGINT NOT NULL,
  valgt_assertion_id BIGINT REFERENCES assertion(id),
  status            TEXT,                -- 'afklaret','omstridt','forældet'
  blaastemplet_af   TEXT,                -- udgave eller beslutning (proveniens)
  blaastemplet_naar DATE,
  UNIQUE (target_type, target_id)
);

-- Supabase may grant sequence privileges through owner default privileges.
-- These IDs are allocated only inside owner/SECURITY DEFINER writers.
REVOKE ALL ON SEQUENCE public.relation_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.assertion_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.conclusion_id_seq FROM PUBLIC, anon, authenticated;

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
  id           BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  subjekt_type TEXT NOT NULL,     -- 'person' | 'family' | 'line' ...
  subjekt_id   BIGINT NOT NULL,
  source_id    BIGINT REFERENCES source(id),
  side         TEXT,              -- fx '209-211'
  tekst        TEXT NOT NULL,
  privat       BOOLEAN DEFAULT FALSE   -- GDPR: skjult narrativ (levende-biografi); jf. TNG secret-flag
);

-- ---------- OFFENTLIG KILDERECORD-PUBLIKATION ----------
-- Privat binding med offentlig, tilfældig reference; uforbundne narrativer er legacy.
CREATE TABLE private.narrative_record_publication (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  narrative_id bigint NOT NULL UNIQUE REFERENCES public.narrative(id),
  source_record_id uuid NOT NULL REFERENCES private.source_record(id),
  record_ref uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  record_label text NOT NULL CHECK (btrim(record_label)<>''),
  citation_label text NOT NULL CHECK (btrim(citation_label)<>''),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(), published_at timestamptz
);
CREATE FUNCTION private.validate_narrative_record_publication()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_narrative_source bigint; v_record_source bigint; v_subject_type text;
BEGIN
  SELECT source_id,subjekt_type INTO v_narrative_source,v_subject_type FROM public.narrative WHERE id=NEW.narrative_id;
  SELECT source_id INTO v_record_source FROM private.source_record WHERE id=NEW.source_record_id;
  IF v_narrative_source IS NULL OR v_record_source IS NULL OR v_narrative_source<>v_record_source THEN RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_SOURCE_MISMATCH'; END IF;
  IF v_subject_type<>'person' THEN RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_SUBJECT_INVALID'; END IF;
  IF TG_OP='UPDATE' AND (NEW.narrative_id<>OLD.narrative_id OR NEW.source_record_id<>OLD.source_record_id OR NEW.record_ref<>OLD.record_ref) THEN RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_BINDING_IMMUTABLE'; END IF;
  IF NEW.status='published' AND NEW.published_at IS NULL THEN NEW.published_at:=clock_timestamp(); END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_narrative_record_publication_validate BEFORE INSERT OR UPDATE ON private.narrative_record_publication FOR EACH ROW EXECUTE FUNCTION private.validate_narrative_record_publication();
ALTER TABLE private.narrative_record_publication ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.narrative_record_publication FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION private.validate_narrative_record_publication() FROM PUBLIC,anon,authenticated;

-- C3 adversarial review, fund B4 (2026-08-22): a source_record may carry only one
-- active (draft/published) narrative binding. Declarative, not lock-based, so every
-- writer is protected -- not only the ones that remember to lock private.source_record
-- first. withdrawn bindings are excluded so a fresh binding remains possible after a
-- withdrawal. Backfill check before this index applied to prod: 0 records with >1
-- active binding (verified 2026-08-22; re-verify immediately before the prod migration).
CREATE UNIQUE INDEX narrative_record_publication_active_record_uidx
  ON private.narrative_record_publication (source_record_id)
  WHERE status IN ('draft','published');

-- ---------- DAA 1939 v50: guarded production writer ----------
CREATE TABLE private.reimport_1939_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation text NOT NULL CHECK(operation IN ('reimport','reversal','cutover','name_completion')),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  preview_sha256 text NOT NULL CHECK(preview_sha256 ~ '^[0-9a-f]{64}$'),
  database_identity text NOT NULL CHECK(btrim(database_identity)<>''),
  source_id bigint NOT NULL REFERENCES public.source(id),
  expected_counts jsonb NOT NULL CHECK(jsonb_typeof(expected_counts)='object'),
  authorized_elements jsonb NOT NULL CHECK(jsonb_typeof(authorized_elements)='object'),
  principal_id uuid NOT NULL,
  nonce uuid NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'issued' CHECK(status IN ('issued','consumed','expired')),
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK((status='consumed')=(consumed_at IS NOT NULL))
);

CREATE TABLE private.reimport_1939_write_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id uuid NOT NULL UNIQUE REFERENCES private.reimport_1939_authorization(id),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  preview_sha256 text NOT NULL CHECK(preview_sha256 ~ '^[0-9a-f]{64}$'),
  principal_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','finalized','reversed','activated')),
  expected_counts jsonb NOT NULL CHECK(jsonb_typeof(expected_counts)='object'),
  observed_counts jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_at timestamptz
);
CREATE UNIQUE INDEX reimport_1939_write_batch_manifest_uidx
  ON private.reimport_1939_write_batch(manifest_sha256,preview_sha256,principal_id);

CREATE TABLE private.reimport_1939_write_event (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  batch_id uuid NOT NULL REFERENCES private.reimport_1939_write_batch(id),
  element_id text NOT NULL CHECK(btrim(element_id)<>''),
  operation text NOT NULL CHECK(operation IN ('source_evidence','person_create','canonical_delta','reversal','activation')),
  source_record_key text,
  canonical_person_id bigint,
  payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),
  before_sha256 text,
  after_sha256 text NOT NULL CHECK(after_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(batch_id,element_id)
);

CREATE FUNCTION private.reject_reimport_1939_event_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'REIMPORT_1939_EVENT_APPEND_ONLY'; END $$;
CREATE TRIGGER trg_reimport_1939_event_append_only
  BEFORE UPDATE OR DELETE ON private.reimport_1939_write_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_reimport_1939_event_mutation();

CREATE FUNCTION private.require_reimport_1939_editor()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_actor uuid:=auth.uid();
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'REIMPORT_1939_ROLE_FORBIDDEN';
  END IF;
  RETURN v_actor;
END $$;

CREATE FUNCTION public.red_authorize_1939_v50_reimport(
  p_manifest_sha256 text,p_preview_sha256 text,p_database_identity text,p_source_id bigint,
  p_expected_counts jsonb,p_authorized_elements jsonb,p_nonce uuid,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  IF p_database_identity<>current_database() OR p_expires_at<=clock_timestamp() OR p_expected_counts<>jsonb_build_object(
      'person_creates',coalesce((p_expected_counts->>'person_creates')::int,-1),
      'source_evidence',coalesce((p_expected_counts->>'source_evidence')::int,-1),
      'canonical_delta',coalesce((p_expected_counts->>'canonical_delta')::int,-1))
     OR (p_expected_counts->>'person_creates')::int<0 OR (p_expected_counts->>'source_evidence')::int<0
     OR (p_expected_counts->>'canonical_delta')::int<0
     OR jsonb_typeof(p_authorized_elements)<>'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements))<>
        (p_expected_counts->>'person_creates')::int+(p_expected_counts->>'source_evidence')::int+(p_expected_counts->>'canonical_delta')::int
     OR EXISTS(SELECT 1 FROM jsonb_each(p_authorized_elements) e
               WHERE btrim(e.key)='' OR jsonb_typeof(e.value)<>'object') THEN
    RAISE EXCEPTION 'REIMPORT_1939_AUTHORIZATION_INVALID';
  END IF;
  IF EXISTS(
    SELECT 1 FROM private.reimport_1939_write_batch b
    JOIN private.reimport_1939_authorization a ON a.id=b.authorization_id
    WHERE b.manifest_sha256=p_manifest_sha256 AND b.preview_sha256=p_preview_sha256
      AND b.principal_id=v_actor AND b.status IN ('finalized','activated')
      AND a.authorized_elements IS DISTINCT FROM p_authorized_elements
  ) THEN RAISE EXCEPTION 'REIMPORT_1939_MANIFEST_ELEMENT_DRIFT'; END IF;
  INSERT INTO private.reimport_1939_authorization(operation,manifest_sha256,preview_sha256,
    database_identity,source_id,expected_counts,authorized_elements,principal_id,nonce,expires_at)
  VALUES('reimport',p_manifest_sha256,p_preview_sha256,p_database_identity,p_source_id,
    p_expected_counts,p_authorized_elements,v_actor,p_nonce,p_expires_at) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION public.red_begin_1939_v50_reimport(p_authorization_id uuid,p_manifest_sha256 text,p_preview_sha256 text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_auth private.reimport_1939_authorization%ROWTYPE; v_id uuid; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  SELECT * INTO v_auth FROM private.reimport_1939_authorization WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_auth.operation<>'reimport' OR v_auth.status<>'issued' OR v_auth.expires_at<=clock_timestamp()
     OR v_auth.principal_id<>v_actor OR v_auth.manifest_sha256<>p_manifest_sha256 OR v_auth.preview_sha256<>p_preview_sha256 THEN
    RAISE EXCEPTION 'REIMPORT_1939_AUTHORIZATION_INVALID';
  END IF;
  UPDATE private.reimport_1939_authorization SET status='consumed',consumed_at=clock_timestamp() WHERE id=v_auth.id;
  SELECT b.id INTO v_id FROM private.reimport_1939_write_batch b
  JOIN private.reimport_1939_authorization a ON a.id=b.authorization_id
  WHERE b.manifest_sha256=v_auth.manifest_sha256 AND b.preview_sha256=v_auth.preview_sha256
    AND b.principal_id=v_actor AND b.status='finalized'
    AND b.expected_counts=v_auth.expected_counts AND a.authorized_elements=v_auth.authorized_elements
  ORDER BY b.finalized_at DESC,b.id LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO private.reimport_1939_write_batch(authorization_id,manifest_sha256,preview_sha256,principal_id,expected_counts)
  VALUES(v_auth.id,v_auth.manifest_sha256,v_auth.preview_sha256,v_actor,v_auth.expected_counts) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION private.require_reimport_1939_open_batch(p_batch_id uuid)
RETURNS private.reimport_1939_write_batch LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_batch private.reimport_1939_write_batch%ROWTYPE; v_actor uuid:=private.require_reimport_1939_editor();
BEGIN
  SELECT * INTO v_batch FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.status<>'open' OR v_batch.principal_id<>v_actor THEN RAISE EXCEPTION 'REIMPORT_1939_BATCH_INVALID'; END IF;
  RETURN v_batch;
END $$;

CREATE FUNCTION private.ensure_reimport_1939_source_evidence(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_batch private.reimport_1939_write_batch%ROWTYPE; v_auth private.reimport_1939_authorization%ROWTYPE;
 v_run uuid; v_rendition uuid; v_record uuid; v_occurrence uuid; v_observation uuid; v_mention uuid;
 v_actor uuid:=private.require_reimport_1939_editor(); v_actor_name text; v_span jsonb; v_page jsonb; v_text text;
BEGIN
 v_batch:=private.require_reimport_1939_open_batch(p_batch_id);
 SELECT * INTO v_auth FROM private.reimport_1939_authorization WHERE id=v_batch.authorization_id;
 IF NOT v_auth.authorized_elements ? p_element_id
    OR (v_auth.authorized_elements->p_element_id IS DISTINCT FROM p_payload
        AND v_auth.authorized_elements->p_element_id IS DISTINCT FROM (p_payload-'category')) THEN
   RAISE EXCEPTION 'REIMPORT_1939_ELEMENT_NOT_AUTHORIZED';
 END IF;
 v_span:=p_payload->'source_span'; v_page:=p_payload->'page_evidence'; v_text:=p_payload->>'verbatim_text';
 IF nullif(btrim(p_payload->>'source_record_key'),'') IS NULL OR v_span IS NULL OR v_page IS NULL OR nullif(v_text,'') IS NULL
    OR (v_span->>'char_from')::int<0 OR (v_span->>'char_to')::int<=(v_span->>'char_from')::int
    OR (v_page->>'page_from')::int<1 OR (v_page->>'page_to')::int<(v_page->>'page_from')::int
    OR p_payload->>'rendition_content_sha256' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'REIMPORT_1939_SOURCE_EVIDENCE_INVALID'; END IF;
 SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text) INTO v_actor_name FROM public.profiles WHERE id=v_actor;
 INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
 VALUES(v_auth.source_id,'reimport-1939-v50:'||v_batch.manifest_sha256,'1939-v50-production-write-manifest-v1','production-writer-v1','production-writer-v1',v_batch.manifest_sha256,jsonb_build_object('batch_id',p_batch_id))
 ON CONFLICT(source_id,run_key) DO NOTHING;
 SELECT id INTO v_run FROM private.extraction_run WHERE source_id=v_auth.source_id AND run_key='reimport-1939-v50:'||v_batch.manifest_sha256;
 INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
 VALUES(v_auth.source_id,'daa-1939-calamari-r6-clean','ocr_text',p_payload->>'rendition_content_sha256','{"edition":"1939"}') ON CONFLICT(source_id,rendition_key) DO NOTHING;
 SELECT id INTO v_rendition FROM private.source_rendition WHERE source_id=v_auth.source_id AND rendition_key='daa-1939-calamari-r6-clean';
 IF NOT EXISTS(SELECT 1 FROM private.source_rendition WHERE id=v_rendition AND content_sha256=p_payload->>'rendition_content_sha256') THEN RAISE EXCEPTION 'REIMPORT_1939_RENDITION_DRIFT'; END IF;
 INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_auth.source_id,p_payload->>'source_record_key',coalesce(p_payload->>'category','person'),v_run) ON CONFLICT(source_id,record_key) DO NOTHING;
 SELECT id INTO v_record FROM private.source_record WHERE source_id=v_auth.source_id AND record_key=p_payload->>'source_record_key';
 INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
 VALUES(v_rendition,p_element_id,(v_page->>'page_from')::int,(v_page->>'page_to')::int,(v_span->>'char_from')::int,(v_span->>'char_to')::int,v_text,encode(digest(v_text,'sha256'),'hex'),encode(digest(p_payload::text,'sha256'),'hex'),v_run)
 ON CONFLICT(rendition_id,extraction_run_id,occurrence_key) DO NOTHING;
 SELECT id INTO v_occurrence FROM private.source_record_occurrence WHERE rendition_id=v_rendition AND extraction_run_id=v_run AND occurrence_key=p_element_id;
 INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
 VALUES(v_occurrence,v_record,'accepted',jsonb_build_object('batch_id',p_batch_id,'element_id',p_element_id),1,v_actor,v_actor_name) ON CONFLICT(occurrence_id,source_record_id,version) DO NOTHING;
 INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
 VALUES(v_occurrence,coalesce(p_payload->>'category','person'),(v_page->>'page_from')::int,(v_page->>'page_to')::int,(v_span->>'char_from')::int,(v_span->>'char_to')::int,v_text,'clear','human_reviewed_1939_v50',v_run) RETURNING id INTO v_observation;
 INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
 VALUES(v_observation,coalesce(p_payload->>'category','person'),0,char_length(v_text),v_text,v_run) RETURNING id INTO v_mention;
 RETURN jsonb_build_object('run_id',v_run,'rendition_id',v_rendition,'source_record_id',v_record,'occurrence_id',v_occurrence,'observation_id',v_observation,'mention_id',v_mention);
END $$;

CREATE FUNCTION public.red_apply_1939_v50_source_evidence(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_batch private.reimport_1939_write_batch%ROWTYPE; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  SELECT * INTO v_batch FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.principal_id<>v_actor THEN RAISE EXCEPTION 'REIMPORT_1939_BATCH_INVALID'; END IF;
  IF v_batch.status='finalized' THEN
    IF EXISTS(SELECT 1 FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id AND element_id=p_element_id AND operation='source_evidence' AND payload=p_payload) THEN RETURN; END IF;
    RAISE EXCEPTION 'REIMPORT_1939_ALREADY_APPLIED_DRIFT';
  END IF;
  v_batch:=private.require_reimport_1939_open_batch(p_batch_id);
  IF p_payload->>'disposition'<>'retain_source_only' OR (p_payload-ARRAY['review_subject_id','source_record_key','category','disposition','evidence_sha256','canonical_target','source_span','page_evidence','verbatim_text','legacy_payload','rendition_content_sha256'])<>'{}'::jsonb THEN RAISE EXCEPTION 'REIMPORT_1939_SOURCE_EVIDENCE_INVALID'; END IF;
  PERFORM private.ensure_reimport_1939_source_evidence(p_batch_id,p_element_id,p_payload);
  INSERT INTO private.reimport_1939_write_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES(p_batch_id,p_element_id,'source_evidence',p_payload->>'source_record_key',p_payload,
    encode(digest(p_payload::text,'sha256'),'hex'));
END $$;

CREATE FUNCTION public.red_apply_1939_v50_person_create(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_batch private.reimport_1939_write_batch%ROWTYPE; v_person_id bigint; v_evidence jsonb; v_persona uuid; v_narrative bigint; v_actor uuid; v_actor_name text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  SELECT * INTO v_batch FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.principal_id<>v_actor THEN RAISE EXCEPTION 'REIMPORT_1939_BATCH_INVALID'; END IF;
  IF v_batch.status='finalized' THEN
    SELECT canonical_person_id INTO v_person_id FROM private.reimport_1939_write_event
    WHERE batch_id=p_batch_id AND element_id=p_element_id AND operation='person_create' AND payload=p_payload;
    IF FOUND THEN RETURN v_person_id; END IF;
    RAISE EXCEPTION 'REIMPORT_1939_ALREADY_APPLIED_DRIFT';
  END IF;
  v_batch:=private.require_reimport_1939_open_batch(p_batch_id);
  IF (p_payload-ARRAY['source_record_key','source_id','edition','source_span','page_evidence','verbatim_text','verbatim_sha256','source_persona_id','persona_key','identity_decision_sha256','review_sha256','decision_basis','name','sex','narrative','source_mentions','persona_mention_links','facts','relations','families','uncertainties','staged','rendition_content_sha256'])<>'{}'::jsonb
     OR (p_payload->>'staged')::boolean IS DISTINCT FROM true OR nullif(btrim(p_payload->>'name'),'') IS NULL
     OR (p_payload->>'source_id')::bigint<>((SELECT source_id FROM private.reimport_1939_authorization WHERE id=v_batch.authorization_id))
     OR EXISTS(SELECT 1 FROM public.person_external_id WHERE source_id=(p_payload->>'source_id')::bigint AND record_key=p_payload->>'source_record_key') THEN
    RAISE EXCEPTION 'REIMPORT_1939_PERSON_CREATE_INVALID';
  END IF;
  v_evidence:=private.ensure_reimport_1939_source_evidence(p_batch_id,p_element_id,p_payload||'{"category":"person"}'::jsonb);
  INSERT INTO public.person(staged,visning_navn) VALUES(true,p_payload->>'name') RETURNING id INTO v_person_id;
  INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES(v_person_id,(p_payload->>'source_id')::bigint,p_payload->>'source_record_key');
  v_persona:=(p_payload->>'source_persona_id')::uuid;
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES(v_persona,(p_payload->>'source_id')::bigint,p_payload->>'persona_key',(v_evidence->>'run_id')::uuid);
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES(v_persona,(v_evidence->>'mention_id')::uuid,'primary',1);
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text) INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  PERFORM public.red_decide_source_persona_identity(v_persona,v_person_id,0,'accepted',jsonb_build_object('batch_id',p_batch_id,'decision_sha256',p_payload->>'identity_decision_sha256'));
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',v_person_id,(p_payload->>'source_id')::bigint,(p_payload->'page_evidence'->>'page_from'),p_payload->'narrative'->>'text',false) RETURNING id INTO v_narrative;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status,published_at)
  VALUES(v_narrative,(v_evidence->>'source_record_id')::uuid,p_payload->>'source_record_key','DAA 1939 side '||(p_payload->'page_evidence'->>'page_from'),'draft',NULL);
  INSERT INTO private.reimport_1939_write_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256)
  VALUES(p_batch_id,p_element_id,'person_create',p_payload->>'source_record_key',v_person_id,p_payload,
    encode(digest(jsonb_build_object('person_id',v_person_id,'payload',p_payload)::text,'sha256'),'hex'));
  RETURN v_person_id;
END $$;

CREATE FUNCTION public.red_apply_1939_v50_canonical_delta(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  PERFORM private.require_reimport_1939_open_batch(p_batch_id);
  RAISE EXCEPTION 'REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED';
END $$;

CREATE FUNCTION public.red_finalize_1939_v50_reimport(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_batch private.reimport_1939_write_batch%ROWTYPE; v_counts jsonb; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  SELECT * INTO v_batch FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.principal_id<>v_actor THEN RAISE EXCEPTION 'REIMPORT_1939_BATCH_INVALID'; END IF;
  IF v_batch.status='finalized' THEN
    RETURN jsonb_build_object('batch_id',p_batch_id,'status','already_applied','counts',v_batch.observed_counts);
  END IF;
  v_batch:=private.require_reimport_1939_open_batch(p_batch_id);
  SELECT jsonb_build_object(
    'person_creates',count(*) FILTER(WHERE operation='person_create'),
    'source_evidence',count(*) FILTER(WHERE operation='source_evidence'),
    'canonical_delta',count(*) FILTER(WHERE operation='canonical_delta')) INTO v_counts
  FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id;
  IF v_counts<>v_batch.expected_counts THEN RAISE EXCEPTION 'REIMPORT_1939_FINALIZE_COUNT_MISMATCH'; END IF;
  UPDATE private.reimport_1939_write_batch SET status='finalized',observed_counts=v_counts,finalized_at=clock_timestamp() WHERE id=p_batch_id;
  RETURN jsonb_build_object('batch_id',p_batch_id,'status','finalized','counts',v_counts);
END $$;

CREATE FUNCTION public.red_authorize_1939_v50_reversal(p_batch_id uuid,p_nonce uuid,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_batch private.reimport_1939_write_batch%ROWTYPE; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  SELECT * INTO v_batch FROM private.reimport_1939_write_batch WHERE id=p_batch_id AND status='finalized';
  IF NOT FOUND OR p_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'REIMPORT_1939_REVERSAL_INVALID'; END IF;
  INSERT INTO private.reimport_1939_authorization(operation,manifest_sha256,preview_sha256,database_identity,source_id,expected_counts,authorized_elements,principal_id,nonce,expires_at)
  SELECT 'reversal',b.manifest_sha256,b.preview_sha256,'batch:'||b.id::text,a.source_id,'{}','{}',v_actor,p_nonce,p_expires_at
  FROM private.reimport_1939_write_batch b JOIN private.reimport_1939_authorization a ON a.id=b.authorization_id WHERE b.id=p_batch_id RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION public.red_reverse_1939_v50_reimport(p_batch_id uuid,p_authorization_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_actor uuid; v_run uuid; v_child_id uuid; v_child_count bigint; v_child_status text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
  LOCK TABLE public.fact,public.assertion,public.citation,public.conclusion IN SHARE ROW EXCLUSIVE MODE;
  IF NOT EXISTS(SELECT 1 FROM private.reimport_1939_authorization a JOIN private.reimport_1939_write_batch b ON b.id=p_batch_id WHERE a.id=p_authorization_id AND a.operation='reversal' AND a.status='issued' AND a.principal_id=v_actor AND a.expires_at>clock_timestamp() AND a.database_identity='batch:'||b.id::text AND a.manifest_sha256=b.manifest_sha256 AND a.preview_sha256=b.preview_sha256 AND b.status='finalized') THEN RAISE EXCEPTION 'REIMPORT_1939_REVERSAL_INVALID'; END IF;
  PERFORM 1 FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  SELECT count(*),(array_agg(cb.id ORDER BY cb.id))[1] INTO v_child_count,v_child_id
  FROM private.reimport_1939_write_batch cb JOIN private.reimport_1939_authorization ca ON ca.id=cb.authorization_id
  WHERE ca.operation='name_completion' AND cb.status<>'reversed'
    AND EXISTS(SELECT 1 FROM jsonb_each(ca.authorized_elements->'payloads') j WHERE j.value->>'source_batch_id'=p_batch_id::text);
  IF v_child_count>1 THEN RAISE EXCEPTION 'REIMPORT_1939_NAME_COMPLETION_INVALID'; END IF;
  IF v_child_id IS NOT NULL THEN
    SELECT status INTO v_child_status FROM private.reimport_1939_write_batch WHERE id=v_child_id FOR UPDATE;
    PERFORM 1 FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id ORDER BY person_id FOR UPDATE;
    PERFORM 1 FROM public.person WHERE id IN(SELECT person_id FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id) ORDER BY id FOR UPDATE;
    IF v_child_status<>'finalized'
       OR (SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(DISTINCT person_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(DISTINCT fact_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(DISTINCT assertion_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(DISTINCT citation_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(DISTINCT conclusion_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
       OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id AND operation='person_create')<>8
       OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=v_child_id AND operation='canonical_delta')<>8
       OR EXISTS(SELECT 1 FROM private.reimport_1939_write_event se
         WHERE se.batch_id=p_batch_id AND se.operation='person_create' AND NOT EXISTS(
           SELECT 1 FROM private.reimport_1939_name_completion_result r
           WHERE r.batch_id=v_child_id AND r.source_batch_id=p_batch_id AND r.person_id=se.canonical_person_id))
       OR EXISTS(SELECT 1
         FROM private.reimport_1939_name_completion_result r
         JOIN private.reimport_1939_write_batch cb ON cb.id=r.batch_id
         JOIN private.reimport_1939_authorization ca ON ca.id=cb.authorization_id
         LEFT JOIN private.reimport_1939_write_event ce ON ce.batch_id=r.batch_id AND ce.element_id=r.element_id AND ce.operation='canonical_delta'
         LEFT JOIN private.reimport_1939_write_event se ON se.batch_id=r.source_batch_id AND se.element_id=ca.authorized_elements->'payloads'->r.element_id->>'source_person_create_element_id' AND se.operation='person_create'
         LEFT JOIN private.source_record sr ON sr.id=r.source_record_id
         LEFT JOIN private.source_persona sp ON sp.id=r.source_persona_id
         LEFT JOIN private.source_persona_identity si ON si.source_persona_id=r.source_persona_id AND si.decision_status='accepted'
         LEFT JOIN public.person p ON p.id=r.person_id
         LEFT JOIN public.fact f ON f.id=r.fact_id
         LEFT JOIN public.assertion x ON x.id=r.assertion_id
         LEFT JOIN public.citation c ON c.id=r.citation_id
         LEFT JOIN public.conclusion n ON n.id=r.conclusion_id
         WHERE r.batch_id=v_child_id AND (
           r.source_batch_id<>p_batch_id OR ca.operation<>'name_completion' OR cb.status<>'finalized'
           OR ca.expected_counts<>'{"name_completions":8,"operations":8}'::jsonb OR cb.observed_counts<>ca.expected_counts
           OR ca.authorized_elements->'payloads'->r.element_id IS NULL
           OR r.element_id<>'name-completion:'||(ca.authorized_elements->'payloads'->r.element_id->>'source_record_key')
           OR r.person_id<>(ca.authorized_elements->'payloads'->r.element_id->>'person_id')::bigint
           OR r.source_persona_id<>(ca.authorized_elements->'payloads'->r.element_id->>'source_persona_id')::uuid
           OR r.payload_sha256<>private.reimport_1939_canonical_json_sha256(ca.authorized_elements->'payloads'->r.element_id)
           OR r.result_sha256<>private.reimport_1939_canonical_json_sha256(jsonb_build_object('fact_id',r.fact_id,'assertion_id',r.assertion_id,'citation_id',r.citation_id,'conclusion_id',r.conclusion_id))
           OR ce.id IS NULL OR ce.payload IS DISTINCT FROM ca.authorized_elements->'payloads'->r.element_id
           OR ce.canonical_person_id<>r.person_id OR ce.source_record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key' OR ce.after_sha256<>r.result_sha256
           OR se.id IS NULL OR se.canonical_person_id<>r.person_id OR se.source_record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key'
           OR private.reimport_1939_canonical_json_sha256(se.payload)<>ca.authorized_elements->'payloads'->r.element_id->>'source_payload_sha256'
           OR se.payload->>'name'<>ca.authorized_elements->'payloads'->r.element_id->>'name'
           OR se.payload->>'source_persona_id'<>r.source_persona_id::text
           OR se.payload->'source_span'<>ca.authorized_elements->'payloads'->r.element_id->'source_span'
           OR se.payload->'page_evidence'<>ca.authorized_elements->'payloads'->r.element_id->'page_evidence'
           OR se.payload->>'verbatim_text'<>ca.authorized_elements->'payloads'->r.element_id->>'verbatim_text'
           OR sr.id IS NULL OR sr.source_id<>3 OR sr.record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key'
           OR sp.id IS NULL OR sp.source_id<>3
           OR (SELECT count(*) FROM private.source_persona_identity qi WHERE qi.source_persona_id=r.source_persona_id AND qi.decision_status='accepted') IS DISTINCT FROM 1::bigint
           OR si.canonical_person_id IS DISTINCT FROM r.person_id
           OR p.id IS NULL OR NOT p.staged OR p.visning_navn IS DISTINCT FROM ca.authorized_elements->'payloads'->r.element_id->>'name'
           OR f.id IS NULL OR f.subjekt_type<>'person' OR f.subjekt_id<>r.person_id OR f.faktatype<>'navn'
           OR (SELECT count(*) FROM public.fact nf WHERE nf.subjekt_type='person' AND nf.subjekt_id=r.person_id AND nf.faktatype='navn')<>1
           OR x.id IS NULL OR x.target_type<>'fact' OR x.target_id<>r.fact_id OR x.vaerdi_tekst<>ca.authorized_elements->'payloads'->r.element_id->>'name' OR NOT x.uforanderlig
           OR c.id IS NULL OR c.assertion_id<>r.assertion_id OR c.source_id<>3 OR c.side<>ca.authorized_elements->'payloads'->r.element_id->'page_evidence'->>'page_from' OR c.citat_tekst<>ca.authorized_elements->'payloads'->r.element_id->>'verbatim_text'
           OR n.id IS NULL OR n.target_type<>'fact' OR n.target_id<>r.fact_id OR n.valgt_assertion_id<>r.assertion_id OR n.status<>'afklaret'
         )) THEN RAISE EXCEPTION 'REIMPORT_1939_NAME_COMPLETION_INVALID'; END IF;
    DELETE FROM public.conclusion n USING private.reimport_1939_name_completion_result r WHERE r.batch_id=v_child_id AND n.id=r.conclusion_id;
    DELETE FROM public.citation c USING private.reimport_1939_name_completion_result r WHERE r.batch_id=v_child_id AND c.id=r.citation_id;
    DELETE FROM public.assertion x USING private.reimport_1939_name_completion_result r WHERE r.batch_id=v_child_id AND x.id=r.assertion_id;
    DELETE FROM public.fact f USING private.reimport_1939_name_completion_result r WHERE r.batch_id=v_child_id AND f.id=r.fact_id;
    UPDATE private.reimport_1939_write_batch SET status='reversed' WHERE id=v_child_id AND status='finalized';
  END IF;
  SELECT r.id INTO v_run FROM private.extraction_run r JOIN private.reimport_1939_write_batch b ON r.run_key='reimport-1939-v50:'||b.manifest_sha256 WHERE b.id=p_batch_id;
  DELETE FROM private.narrative_record_publication p USING public.narrative n,private.reimport_1939_write_event e WHERE e.batch_id=p_batch_id AND e.operation='person_create' AND n.subjekt_type='person' AND n.subjekt_id=e.canonical_person_id AND p.narrative_id=n.id;
  DELETE FROM public.narrative n USING private.reimport_1939_write_event e WHERE e.batch_id=p_batch_id AND e.operation='person_create' AND n.subjekt_type='person' AND n.subjekt_id=e.canonical_person_id;
  PERFORM public.red_decide_source_persona_identity(p.id,NULL,1,'superseded',jsonb_build_object('reversed_batch_id',p_batch_id))
  FROM private.source_persona p WHERE p.created_run_id=v_run;
  DELETE FROM public.person_external_id x USING private.reimport_1939_write_event e WHERE e.batch_id=p_batch_id AND e.operation='person_create' AND x.person_id=e.canonical_person_id;
  UPDATE public.person p SET staged=true,status='reimport_1939_reversed' FROM private.reimport_1939_write_event e WHERE e.batch_id=p_batch_id AND e.operation='person_create' AND p.id=e.canonical_person_id;
  UPDATE private.reimport_1939_authorization SET status='consumed',consumed_at=clock_timestamp() WHERE id=p_authorization_id;
  UPDATE private.reimport_1939_write_batch SET status='reversed' WHERE id=p_batch_id AND status='finalized';
  RETURN jsonb_build_object('batch_id',p_batch_id,'status','reversed');
END $$;

CREATE FUNCTION public.red_authorize_1939_v50_cutover(p_batch_id uuid,p_nonce uuid,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_actor uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  IF NOT EXISTS(SELECT 1 FROM private.reimport_1939_write_batch WHERE id=p_batch_id AND status='finalized') OR p_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'REIMPORT_1939_CUTOVER_INVALID'; END IF;
  INSERT INTO private.reimport_1939_authorization(operation,manifest_sha256,preview_sha256,database_identity,source_id,expected_counts,authorized_elements,principal_id,nonce,expires_at)
  SELECT 'cutover',b.manifest_sha256,b.preview_sha256,'batch:'||b.id::text,a.source_id,'{}','{}',v_actor,p_nonce,p_expires_at
  FROM private.reimport_1939_write_batch b JOIN private.reimport_1939_authorization a ON a.id=b.authorization_id WHERE b.id=p_batch_id RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION public.red_activate_1939_v50_batch(p_batch_id uuid,p_authorization_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_actor uuid; v_count bigint; v_child_id uuid; v_child_count bigint; v_child_status text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
  LOCK TABLE public.fact,public.assertion,public.citation,public.conclusion IN SHARE ROW EXCLUSIVE MODE;
  IF NOT EXISTS(SELECT 1 FROM private.reimport_1939_authorization a JOIN private.reimport_1939_write_batch b ON b.id=p_batch_id WHERE a.id=p_authorization_id AND a.operation='cutover' AND a.status='issued' AND a.principal_id=v_actor AND a.expires_at>clock_timestamp() AND a.database_identity='batch:'||b.id::text AND a.manifest_sha256=b.manifest_sha256 AND a.preview_sha256=b.preview_sha256 AND b.status='finalized') THEN RAISE EXCEPTION 'REIMPORT_1939_CUTOVER_INVALID'; END IF;
  PERFORM 1 FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  SELECT count(*),(array_agg(cb.id ORDER BY cb.id))[1] INTO v_child_count,v_child_id
  FROM private.reimport_1939_write_batch cb JOIN private.reimport_1939_authorization ca ON ca.id=cb.authorization_id
  WHERE ca.operation='name_completion' AND cb.status<>'reversed'
    AND EXISTS(SELECT 1 FROM jsonb_each(ca.authorized_elements->'payloads') j WHERE j.value->>'source_batch_id'=p_batch_id::text);
  IF v_child_count<>1 THEN RAISE EXCEPTION 'REIMPORT_1939_NAME_COMPLETION_INVALID'; END IF;
  SELECT status INTO v_child_status FROM private.reimport_1939_write_batch WHERE id=v_child_id FOR UPDATE;
  PERFORM 1 FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id ORDER BY person_id FOR UPDATE;
  PERFORM 1 FROM public.person WHERE id IN(SELECT person_id FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id) ORDER BY id FOR UPDATE;
  IF v_child_status<>'finalized'
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(DISTINCT person_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(DISTINCT fact_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(DISTINCT assertion_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(DISTINCT citation_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(DISTINCT conclusion_id) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_child_id)<>8
     OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id AND operation='person_create')<>8
     OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=v_child_id AND operation='canonical_delta')<>8
     OR EXISTS(SELECT 1 FROM private.reimport_1939_write_event se
       WHERE se.batch_id=p_batch_id AND se.operation='person_create' AND NOT EXISTS(
         SELECT 1 FROM private.reimport_1939_name_completion_result r
         WHERE r.batch_id=v_child_id AND r.source_batch_id=p_batch_id AND r.person_id=se.canonical_person_id))
     OR EXISTS(SELECT 1
       FROM private.reimport_1939_name_completion_result r
       JOIN private.reimport_1939_write_batch cb ON cb.id=r.batch_id
       JOIN private.reimport_1939_authorization ca ON ca.id=cb.authorization_id
       LEFT JOIN private.reimport_1939_write_event ce ON ce.batch_id=r.batch_id AND ce.element_id=r.element_id AND ce.operation='canonical_delta'
       LEFT JOIN private.reimport_1939_write_event se ON se.batch_id=r.source_batch_id AND se.element_id=ca.authorized_elements->'payloads'->r.element_id->>'source_person_create_element_id' AND se.operation='person_create'
       LEFT JOIN private.source_record sr ON sr.id=r.source_record_id
       LEFT JOIN private.source_persona sp ON sp.id=r.source_persona_id
       LEFT JOIN private.source_persona_identity si ON si.source_persona_id=r.source_persona_id AND si.decision_status='accepted'
       LEFT JOIN public.person p ON p.id=r.person_id
       LEFT JOIN public.fact f ON f.id=r.fact_id
       LEFT JOIN public.assertion x ON x.id=r.assertion_id
       LEFT JOIN public.citation c ON c.id=r.citation_id
       LEFT JOIN public.conclusion n ON n.id=r.conclusion_id
       WHERE r.batch_id=v_child_id AND (
         r.source_batch_id<>p_batch_id OR ca.operation<>'name_completion' OR cb.status<>'finalized'
         OR ca.expected_counts<>'{"name_completions":8,"operations":8}'::jsonb OR cb.observed_counts<>ca.expected_counts
         OR ca.authorized_elements->'payloads'->r.element_id IS NULL
         OR r.element_id<>'name-completion:'||(ca.authorized_elements->'payloads'->r.element_id->>'source_record_key')
         OR r.person_id<>(ca.authorized_elements->'payloads'->r.element_id->>'person_id')::bigint
         OR r.source_persona_id<>(ca.authorized_elements->'payloads'->r.element_id->>'source_persona_id')::uuid
         OR r.payload_sha256<>private.reimport_1939_canonical_json_sha256(ca.authorized_elements->'payloads'->r.element_id)
         OR r.result_sha256<>private.reimport_1939_canonical_json_sha256(jsonb_build_object('fact_id',r.fact_id,'assertion_id',r.assertion_id,'citation_id',r.citation_id,'conclusion_id',r.conclusion_id))
         OR ce.id IS NULL OR ce.payload IS DISTINCT FROM ca.authorized_elements->'payloads'->r.element_id
         OR ce.canonical_person_id<>r.person_id OR ce.source_record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key' OR ce.after_sha256<>r.result_sha256
         OR se.id IS NULL OR se.canonical_person_id<>r.person_id OR se.source_record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key'
         OR private.reimport_1939_canonical_json_sha256(se.payload)<>ca.authorized_elements->'payloads'->r.element_id->>'source_payload_sha256'
         OR se.payload->>'name'<>ca.authorized_elements->'payloads'->r.element_id->>'name'
         OR se.payload->>'source_persona_id'<>r.source_persona_id::text
         OR se.payload->'source_span'<>ca.authorized_elements->'payloads'->r.element_id->'source_span'
         OR se.payload->'page_evidence'<>ca.authorized_elements->'payloads'->r.element_id->'page_evidence'
         OR se.payload->>'verbatim_text'<>ca.authorized_elements->'payloads'->r.element_id->>'verbatim_text'
         OR sr.id IS NULL OR sr.source_id<>3 OR sr.record_key<>ca.authorized_elements->'payloads'->r.element_id->>'source_record_key'
         OR sp.id IS NULL OR sp.source_id<>3
         OR (SELECT count(*) FROM private.source_persona_identity qi WHERE qi.source_persona_id=r.source_persona_id AND qi.decision_status='accepted') IS DISTINCT FROM 1::bigint
         OR si.canonical_person_id IS DISTINCT FROM r.person_id
         OR p.id IS NULL OR NOT p.staged OR p.visning_navn IS DISTINCT FROM ca.authorized_elements->'payloads'->r.element_id->>'name'
         OR f.id IS NULL OR f.subjekt_type<>'person' OR f.subjekt_id<>r.person_id OR f.faktatype<>'navn'
         OR (SELECT count(*) FROM public.fact nf WHERE nf.subjekt_type='person' AND nf.subjekt_id=r.person_id AND nf.faktatype='navn')<>1
         OR x.id IS NULL OR x.target_type<>'fact' OR x.target_id<>r.fact_id OR x.vaerdi_tekst<>ca.authorized_elements->'payloads'->r.element_id->>'name' OR NOT x.uforanderlig
         OR c.id IS NULL OR c.assertion_id<>r.assertion_id OR c.source_id<>3 OR c.side<>ca.authorized_elements->'payloads'->r.element_id->'page_evidence'->>'page_from' OR c.citat_tekst<>ca.authorized_elements->'payloads'->r.element_id->>'verbatim_text'
         OR n.id IS NULL OR n.target_type<>'fact' OR n.target_id<>r.fact_id OR n.valgt_assertion_id<>r.assertion_id OR n.status<>'afklaret'
       )) THEN RAISE EXCEPTION 'REIMPORT_1939_NAME_COMPLETION_INVALID'; END IF;
  UPDATE public.person SET staged=false WHERE id IN(SELECT canonical_person_id FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id AND operation='person_create'); GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>8 THEN RAISE EXCEPTION 'REIMPORT_1939_NAME_COMPLETION_INVALID'; END IF;
  UPDATE private.reimport_1939_authorization SET status='consumed',consumed_at=clock_timestamp() WHERE id=p_authorization_id;
  UPDATE private.reimport_1939_write_batch SET status='activated' WHERE id=p_batch_id AND status='finalized';
  RETURN jsonb_build_object('batch_id',p_batch_id,'status','activated','persons_activated',v_count);
END $$;

-- ---------- DAA 1939 v50: source-bound name completion ----------
CREATE TABLE private.reimport_1939_name_completion_result (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES private.reimport_1939_write_batch(id),
  element_id text NOT NULL,
  source_batch_id uuid NOT NULL REFERENCES private.reimport_1939_write_batch(id),
  person_id bigint NOT NULL,
  source_record_id uuid NOT NULL,
  source_persona_id uuid NOT NULL,
  fact_id bigint NOT NULL,
  assertion_id bigint NOT NULL,
  citation_id bigint NOT NULL,
  conclusion_id bigint NOT NULL,
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  result_sha256 text NOT NULL CHECK(result_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(batch_id,element_id),
  UNIQUE(source_batch_id,person_id,source_record_id)
);
CREATE TRIGGER trg_reimport_1939_name_completion_result_append_only
  BEFORE UPDATE OR DELETE ON private.reimport_1939_name_completion_result
  FOR EACH ROW EXECUTE FUNCTION private.reject_reimport_1939_event_mutation();

CREATE FUNCTION private.reimport_1939_canonical_json_sha256(p_value jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog,extensions AS $$
DECLARE v_piece text; v_key text; v_item jsonb;
BEGIN
  CASE jsonb_typeof(p_value)
    WHEN 'object' THEN
      v_piece:='{';
      FOR v_key IN SELECT jsonb_object_keys(p_value) ORDER BY 1 LOOP
        IF v_piece<>'{' THEN v_piece:=v_piece||','; END IF;
        v_piece:=v_piece||to_jsonb(v_key)::text||':'||private.reimport_1939_canonical_json_text(p_value->v_key);
      END LOOP;
      v_piece:=v_piece||'}';
    WHEN 'array' THEN
      v_piece:='[';
      FOR v_item IN SELECT value FROM jsonb_array_elements(p_value) LOOP
        IF v_piece<>'[' THEN v_piece:=v_piece||','; END IF;
        v_piece:=v_piece||private.reimport_1939_canonical_json_text(v_item);
      END LOOP;
      v_piece:=v_piece||']';
    ELSE v_piece:=p_value::text;
  END CASE;
  RETURN encode(digest(convert_to(v_piece,'UTF8'),'sha256'),'hex');
END $$;

CREATE FUNCTION private.reimport_1939_canonical_json_text(p_value jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_piece text; v_key text; v_item jsonb;
BEGIN
  CASE jsonb_typeof(p_value)
    WHEN 'object' THEN
      v_piece:='{';
      FOR v_key IN SELECT jsonb_object_keys(p_value) ORDER BY 1 LOOP
        IF v_piece<>'{' THEN v_piece:=v_piece||','; END IF;
        v_piece:=v_piece||to_jsonb(v_key)::text||':'||private.reimport_1939_canonical_json_text(p_value->v_key);
      END LOOP;
      RETURN v_piece||'}';
    WHEN 'array' THEN
      v_piece:='[';
      FOR v_item IN SELECT value FROM jsonb_array_elements(p_value) LOOP
        IF v_piece<>'[' THEN v_piece:=v_piece||','; END IF;
        v_piece:=v_piece||private.reimport_1939_canonical_json_text(v_item);
      END LOOP;
      RETURN v_piece||']';
    ELSE RETURN p_value::text;
  END CASE;
END $$;

CREATE FUNCTION private.validate_reimport_1939_name_completion(
  p_authorization_id uuid,p_source_batch_id uuid,p_manifest_sha256 text,p_payloads jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE a private.reimport_1939_authorization%ROWTYPE; b private.reimport_1939_write_batch%ROWTYPE;
  sa private.reimport_1939_authorization%ROWTYPE; k text; p jsonb; e private.reimport_1939_write_event%ROWTYPE;
  v_identity jsonb; v_system text:=(pg_control_system()).system_identifier::text; v_record uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
  LOCK TABLE public.fact, public.assertion, public.citation, public.conclusion IN SHARE ROW EXCLUSIVE MODE;
  SELECT * INTO a FROM private.reimport_1939_authorization WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR a.operation<>'name_completion' OR a.status<>'issued' OR a.principal_id<>private.require_reimport_1939_editor()
     OR a.expires_at<=clock_timestamp() OR a.manifest_sha256<>p_manifest_sha256
     OR jsonb_typeof(p_payloads)<>'object' OR a.expected_counts<>'{"name_completions":8,"operations":8}'::jsonb
     OR a.authorized_elements<>jsonb_build_object('payloads',p_payloads,
          'source_manifest_bytes_sha256',a.authorized_elements->>'source_manifest_bytes_sha256',
          'source_manifest_content_sha256',a.authorized_elements->>'source_manifest_content_sha256') THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID';
  END IF;
  BEGIN v_identity:=a.database_identity::jsonb; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID'; END;
  IF v_identity<>jsonb_build_object('database_name',current_database(),'system_identifier',v_system)
     OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_identity) AS t(key))<>ARRAY['database_name','system_identifier'] THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID';
  END IF;
  SELECT * INTO b FROM private.reimport_1939_write_batch WHERE id=p_source_batch_id;
  SELECT * INTO sa FROM private.reimport_1939_authorization WHERE id=b.authorization_id;
  IF NOT FOUND OR b.status<>'finalized' OR sa.operation<>'reimport' OR sa.source_id<>3
     OR b.manifest_sha256<>a.authorized_elements->>'source_manifest_content_sha256'
     OR sa.manifest_sha256<>a.authorized_elements->>'source_manifest_content_sha256'
     OR b.preview_sha256<>sa.preview_sha256
     OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=b.id AND operation='person_create')<>8
     OR (SELECT count(*) FROM jsonb_object_keys(p_payloads))<>8 THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID';
  END IF;
  PERFORM 1 FROM public.person q
    JOIN jsonb_each(p_payloads) j ON q.id=(j.value->>'person_id')::bigint
    ORDER BY q.id FOR UPDATE OF q;
  PERFORM 1 FROM private.source_record sr
    JOIN jsonb_each(p_payloads) j ON sr.source_id=3 AND sr.record_key=j.value->>'source_record_key'
    ORDER BY sr.id FOR UPDATE OF sr;
  PERFORM 1 FROM private.source_persona sp
    JOIN jsonb_each(p_payloads) j ON sp.id=(j.value->>'source_persona_id')::uuid
    ORDER BY sp.id FOR UPDATE OF sp;
  PERFORM 1 FROM private.source_persona_identity si
    JOIN jsonb_each(p_payloads) j ON si.source_persona_id=(j.value->>'source_persona_id')::uuid
    ORDER BY si.source_persona_id FOR UPDATE OF si;
  FOR k,p IN SELECT key,value FROM jsonb_each(p_payloads) LOOP
    IF k<>('name-completion:'||(p->>'source_record_key'))
       OR (p-ARRAY['source_batch_id','source_person_create_element_id','person_id','source_id','edition','source_record_key','source_persona_id','name','source_span','page_evidence','verbatim_text','verbatim_sha256','source_payload_sha256','expected_before','expected_after'])<>'{}'::jsonb
       OR p->>'source_batch_id'<>p_source_batch_id::text OR p->>'source_id'<>'3' OR p->>'edition'<>'1939'
       OR jsonb_typeof(p->'source_span')<>'object' OR jsonb_typeof(p->'page_evidence')<>'object'
       OR p->'expected_before'<>'{"staged":true,"name_cache_empty":true,"name_facts":0}'::jsonb
       OR p->'expected_after'<>'{"name_fact":1,"selected_assertion":1,"daa_1939_citation":1,"conclusion":1}'::jsonb
       OR nullif(btrim(p->>'name'),'') IS NULL OR p->>'source_payload_sha256' !~ '^[0-9a-f]{64}$'
       OR p->>'verbatim_sha256'<>encode(digest(convert_to(p->>'verbatim_text','UTF8'),'sha256'),'hex') THEN
      RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID';
    END IF;
    SELECT * INTO e FROM private.reimport_1939_write_event
      WHERE batch_id=b.id AND element_id=p->>'source_person_create_element_id' AND operation='person_create';
    SELECT id INTO v_record FROM private.source_record WHERE source_id=3 AND record_key=p->>'source_record_key';
    IF NOT FOUND OR e.canonical_person_id<>(p->>'person_id')::bigint OR e.source_record_key<>p->>'source_record_key'
       OR private.reimport_1939_canonical_json_sha256(e.payload)<>p->>'source_payload_sha256'
       OR e.payload->>'source_id'<>'3' OR e.payload->>'source_record_key'<>p->>'source_record_key'
       OR e.payload->>'source_persona_id'<>p->>'source_persona_id' OR e.payload->>'name'<>p->>'name'
       OR e.payload->'source_span'<>p->'source_span' OR e.payload->'page_evidence'<>p->'page_evidence'
       OR e.payload->>'verbatim_text'<>p->>'verbatim_text' OR e.payload->>'verbatim_sha256'<>p->>'verbatim_sha256'
       OR NOT EXISTS(SELECT 1 FROM public.person q WHERE q.id=(p->>'person_id')::bigint AND q.staged AND q.visning_navn IS NULL)
       OR EXISTS(SELECT 1 FROM public.fact f WHERE f.subjekt_type='person' AND f.subjekt_id=(p->>'person_id')::bigint AND f.faktatype='navn')
       OR NOT EXISTS(SELECT 1 FROM private.source_persona sp JOIN private.source_persona_identity si ON si.source_persona_id=sp.id
                     WHERE sp.id=(p->>'source_persona_id')::uuid AND sp.source_id=3
                       AND si.canonical_person_id=(p->>'person_id')::bigint AND si.decision_status='accepted') THEN
      RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_INVALID';
    END IF;
  END LOOP;
END $$;

CREATE FUNCTION public.red_lock_1939_v50_name_completion(p_manifest_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  PERFORM private.require_reimport_1939_editor();
  IF p_manifest_sha256 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_LOCK_INVALID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
END $$;

CREATE FUNCTION public.red_authorize_1939_v50_name_completion(
  p_manifest_sha256 text,p_source_batch_id uuid,p_source_manifest_bytes_sha256 text,
  p_source_manifest_content_sha256 text,p_expected_counts jsonb,p_payloads jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_id uuid; v_actor uuid:=private.require_reimport_1939_editor(); v_system text:=(pg_control_system()).system_identifier::text;
BEGIN
  IF p_manifest_sha256 !~ '^[0-9a-f]{64}$' OR p_source_manifest_bytes_sha256 !~ '^[0-9a-f]{64}$'
     OR p_source_manifest_content_sha256 !~ '^[0-9a-f]{64}$'
     OR p_expected_counts<>'{"name_completions":8,"operations":8}'::jsonb OR jsonb_typeof(p_payloads)<>'object' THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_AUTHORIZATION_INVALID';
  END IF;
  INSERT INTO private.reimport_1939_authorization(operation,manifest_sha256,preview_sha256,database_identity,source_id,expected_counts,authorized_elements,principal_id,nonce,expires_at)
  VALUES('name_completion',p_manifest_sha256,p_source_manifest_content_sha256,
    jsonb_build_object('database_name',current_database(),'system_identifier',v_system)::text,3,p_expected_counts,
    jsonb_build_object('payloads',p_payloads,'source_manifest_bytes_sha256',p_source_manifest_bytes_sha256,
      'source_manifest_content_sha256',p_source_manifest_content_sha256),v_actor,gen_random_uuid(),clock_timestamp()+interval '5 minutes')
  RETURNING id INTO v_id;
  PERFORM private.validate_reimport_1939_name_completion(v_id,p_source_batch_id,p_manifest_sha256,p_payloads);
  RETURN jsonb_build_object('authorization_id',v_id,'database_name',current_database(),'system_identifier',v_system);
END $$;

CREATE FUNCTION public.red_preflight_1939_v50_name_completion(
  p_authorization_id uuid,p_source_batch_id uuid,p_manifest_sha256 text,p_payloads jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE a private.reimport_1939_authorization%ROWTYPE; v_system text:=(pg_control_system()).system_identifier::text;
BEGIN
  PERFORM private.validate_reimport_1939_name_completion(p_authorization_id,p_source_batch_id,p_manifest_sha256,p_payloads);
  SELECT * INTO a FROM private.reimport_1939_authorization WHERE id=p_authorization_id;
  RETURN jsonb_build_object('authorization',jsonb_build_object('authorization_id',a.id,'database_name',current_database(),'system_identifier',v_system),
    'preflight',jsonb_build_object('valid',true,'database_name',current_database(),'system_identifier',v_system,
      'source_batch_id',p_source_batch_id,'manifest_sha256',p_manifest_sha256));
END $$;

CREATE FUNCTION public.red_begin_1939_v50_name_completion(
  p_authorization_id uuid,p_manifest_sha256 text,p_source_batch_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE a private.reimport_1939_authorization%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO a FROM private.reimport_1939_authorization WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR a.operation<>'name_completion' OR a.status<>'issued' OR a.principal_id<>private.require_reimport_1939_editor()
     OR a.expires_at<=clock_timestamp() OR a.manifest_sha256<>p_manifest_sha256
     OR NOT EXISTS(SELECT 1 FROM private.reimport_1939_write_batch WHERE id=p_source_batch_id AND status='finalized') THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_AUTHORIZATION_INVALID';
  END IF;
  UPDATE private.reimport_1939_authorization SET status='consumed',consumed_at=clock_timestamp() WHERE id=a.id;
  INSERT INTO private.reimport_1939_write_batch(authorization_id,manifest_sha256,preview_sha256,principal_id,expected_counts)
  VALUES(a.id,a.manifest_sha256,a.preview_sha256,a.principal_id,a.expected_counts) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION public.red_apply_1939_v50_name_completion(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE b private.reimport_1939_write_batch%ROWTYPE; a private.reimport_1939_authorization%ROWTYPE;
  v_fact bigint; v_assertion bigint; v_citation bigint; v_conclusion bigint; v_record uuid; v_hash text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
  LOCK TABLE public.fact, public.assertion, public.citation, public.conclusion IN SHARE ROW EXCLUSIVE MODE;
  SELECT * INTO b FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR b.status<>'open' OR b.principal_id<>private.require_reimport_1939_editor() THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_BATCH_INVALID'; END IF;
  SELECT * INTO a FROM private.reimport_1939_authorization WHERE id=b.authorization_id;
  IF NOT FOUND OR a.operation<>'name_completion' OR a.authorized_elements->'payloads'->p_element_id IS DISTINCT FROM p_payload THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_INVALID';
  END IF;
  IF EXISTS(SELECT 1 FROM private.reimport_1939_name_completion_result WHERE batch_id=p_batch_id AND element_id=p_element_id) THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_INVALID';
  END IF;
  PERFORM 1 FROM public.person q WHERE q.id=(p_payload->>'person_id')::bigint FOR UPDATE OF q;
  PERFORM 1 FROM private.source_record sr
    WHERE sr.source_id=3 AND sr.record_key=p_payload->>'source_record_key' FOR UPDATE OF sr;
  PERFORM 1 FROM private.source_persona sp
    WHERE sp.id=(p_payload->>'source_persona_id')::uuid FOR UPDATE OF sp;
  PERFORM 1 FROM private.source_persona_identity si
    WHERE si.source_persona_id=(p_payload->>'source_persona_id')::uuid FOR UPDATE OF si;
  SELECT id INTO v_record FROM private.source_record WHERE source_id=3 AND record_key=p_payload->>'source_record_key';
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM private.reimport_1939_write_event e
      JOIN private.reimport_1939_write_batch sb ON sb.id=e.batch_id
      WHERE e.batch_id=(p_payload->>'source_batch_id')::uuid AND sb.status='finalized' AND e.operation='person_create'
        AND e.element_id=p_payload->>'source_person_create_element_id' AND e.canonical_person_id=(p_payload->>'person_id')::bigint
        AND private.reimport_1939_canonical_json_sha256(e.payload)=p_payload->>'source_payload_sha256') THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_INVALID';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.person q
       WHERE q.id=(p_payload->>'person_id')::bigint AND q.staged AND q.visning_navn IS NULL)
     OR EXISTS(SELECT 1 FROM public.fact f
       WHERE f.subjekt_type='person' AND f.subjekt_id=(p_payload->>'person_id')::bigint AND f.faktatype='navn')
     OR NOT EXISTS(SELECT 1 FROM private.source_persona sp
       JOIN private.source_persona_identity si ON si.source_persona_id=sp.id
       WHERE sp.id=(p_payload->>'source_persona_id')::uuid AND sp.source_id=3
         AND si.canonical_person_id=(p_payload->>'person_id')::bigint AND si.decision_status='accepted') THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_INVALID';
  END IF;
  SELECT coalesce(max(id),0)+1 INTO v_fact FROM public.fact;
  SELECT coalesce(max(id),0)+1 INTO v_citation FROM public.citation;
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES(v_fact,'person',(p_payload->>'person_id')::bigint,'navn');
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
    VALUES('fact',v_fact,p_payload->>'name',true) RETURNING id INTO v_assertion;
  INSERT INTO public.citation(id,assertion_id,source_id,side,citat_tekst,kvalitet)
    VALUES(v_citation,v_assertion,3,p_payload->'page_evidence'->>'page_from',p_payload->>'verbatim_text','primær');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status,blaastemplet_af,blaastemplet_naar)
    VALUES('fact',v_fact,v_assertion,'afklaret','DAA 1939 v50 name completion',current_date)
    RETURNING id INTO v_conclusion;
  IF (SELECT visning_navn FROM public.person WHERE id=(p_payload->>'person_id')::bigint) IS DISTINCT FROM p_payload->>'name' THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_CACHE_INVALID';
  END IF;
  v_hash:=private.reimport_1939_canonical_json_sha256(jsonb_build_object('fact_id',v_fact,'assertion_id',v_assertion,'citation_id',v_citation,'conclusion_id',v_conclusion));
  INSERT INTO private.reimport_1939_name_completion_result(batch_id,element_id,source_batch_id,person_id,source_record_id,source_persona_id,fact_id,assertion_id,citation_id,conclusion_id,payload_sha256,result_sha256)
    VALUES(p_batch_id,p_element_id,(p_payload->>'source_batch_id')::uuid,(p_payload->>'person_id')::bigint,v_record,
      (p_payload->>'source_persona_id')::uuid,v_fact,v_assertion,v_citation,v_conclusion,
      private.reimport_1939_canonical_json_sha256(p_payload),v_hash);
  INSERT INTO private.reimport_1939_write_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256)
    VALUES(p_batch_id,p_element_id,'canonical_delta',p_payload->>'source_record_key',(p_payload->>'person_id')::bigint,p_payload,v_hash);
END $$;

CREATE FUNCTION public.red_finalize_1939_v50_name_completion(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE b private.reimport_1939_write_batch%ROWTYPE; v_counts jsonb; v_result_map jsonb;
BEGIN
  SELECT * INTO b FROM private.reimport_1939_write_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR b.principal_id<>private.require_reimport_1939_editor() OR b.status<>'open' THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_BATCH_INVALID'; END IF;
  SELECT jsonb_build_object('name_completions',count(*),'operations',count(*)) INTO v_counts
    FROM private.reimport_1939_name_completion_result WHERE batch_id=p_batch_id;
  IF v_counts<>b.expected_counts OR (SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=p_batch_id AND operation='canonical_delta')<>8
     OR EXISTS(SELECT 1 FROM private.reimport_1939_name_completion_result r
       LEFT JOIN public.fact f ON f.id=r.fact_id AND f.subjekt_type='person' AND f.subjekt_id=r.person_id AND f.faktatype='navn'
       LEFT JOIN public.assertion a ON a.id=r.assertion_id AND a.target_type='fact' AND a.target_id=r.fact_id
       LEFT JOIN public.citation c ON c.id=r.citation_id AND c.assertion_id=r.assertion_id
       LEFT JOIN public.conclusion n ON n.id=r.conclusion_id AND n.target_type='fact' AND n.target_id=r.fact_id AND n.valgt_assertion_id=r.assertion_id
       WHERE f.id IS NULL OR a.id IS NULL OR c.id IS NULL OR n.id IS NULL) THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_FINALIZE_COUNT_MISMATCH';
  END IF;
  SELECT jsonb_object_agg(r.element_id,jsonb_build_object(
    'person_id',r.person_id,'fact_id',r.fact_id,'assertion_id',r.assertion_id,
    'citation_id',r.citation_id,'conclusion_id',r.conclusion_id) ORDER BY r.element_id)
    INTO v_result_map FROM private.reimport_1939_name_completion_result r WHERE r.batch_id=p_batch_id;
  UPDATE private.reimport_1939_write_batch SET status='finalized',observed_counts=v_counts,finalized_at=clock_timestamp() WHERE id=p_batch_id;
  RETURN jsonb_build_object('batch_id',p_batch_id,'status','finalized','counts',v_counts,'result_map',v_result_map);
END $$;

ALTER TABLE private.reimport_1939_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_write_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_write_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_1939_name_completion_result ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reimport_1939_authorization,private.reimport_1939_write_batch,private.reimport_1939_write_event,private.reimport_1939_name_completion_result FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reject_reimport_1939_event_mutation(),private.require_reimport_1939_editor(),private.require_reimport_1939_open_batch(uuid),private.ensure_reimport_1939_source_evidence(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz),public.red_begin_1939_v50_reimport(uuid,text,text),public.red_apply_1939_v50_source_evidence(uuid,text,jsonb),public.red_apply_1939_v50_person_create(uuid,text,jsonb),public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb),public.red_finalize_1939_v50_reimport(uuid),public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz),public.red_reverse_1939_v50_reimport(uuid,uuid),public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz),public.red_activate_1939_v50_batch(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reimport_1939_canonical_json_text(jsonb),private.reimport_1939_canonical_json_sha256(jsonb),private.validate_reimport_1939_name_completion(uuid,uuid,text,jsonb),public.red_lock_1939_v50_name_completion(text),public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb),public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb),public.red_begin_1939_v50_name_completion(uuid,text,uuid),public.red_apply_1939_v50_name_completion(uuid,text,jsonb),public.red_finalize_1939_v50_name_completion(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz),public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz),public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.red_begin_1939_v50_reimport(uuid,text,text),public.red_apply_1939_v50_source_evidence(uuid,text,jsonb),public.red_apply_1939_v50_person_create(uuid,text,jsonb),public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb),public.red_finalize_1939_v50_reimport(uuid),public.red_reverse_1939_v50_reimport(uuid,uuid),public.red_activate_1939_v50_batch(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.red_lock_1939_v50_name_completion(text),public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb),public.red_begin_1939_v50_name_completion(uuid,text,uuid),public.red_apply_1939_v50_name_completion(uuid,text,jsonb),public.red_finalize_1939_v50_name_completion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions(p_person_ids bigint[])
RETURNS TABLE(person_id bigint,record_ref uuid,source_label text,record_label text,narrative_text text,citation_label text,provenance_kind text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT n.subjekt_id,p.record_ref,coalesce(nullif(btrim(s.udgave),''),nullif(btrim(s.titel),''),'DAA-udgave'),p.record_label,n.tekst,p.citation_label,'source_record'::text
  FROM public.narrative n JOIN public.person person ON person.id=n.subjekt_id
  JOIN public.source s ON s.id=n.source_id AND s.slags='DAA-udgave'
  JOIN private.narrative_record_publication p ON p.narrative_id=n.id AND p.status='published'
  WHERE n.subjekt_type='person' AND n.subjekt_id=ANY(p_person_ids) AND coalesce(n.privat,false)=false
    AND person.levende=false AND coalesce(person.privat,false)=false AND coalesce(person.staged,false)=false
  UNION ALL
  SELECT n.subjekt_id,NULL::uuid,coalesce(nullif(btrim(s.udgave),''),nullif(btrim(s.titel),''),'DAA-udgave'),'Overgangsdata'::text,n.tekst,coalesce(nullif(btrim(n.side),''),'')::text,'legacy_narrative'::text
  FROM public.narrative n JOIN public.person person ON person.id=n.subjekt_id
  JOIN public.source s ON s.id=n.source_id AND s.slags='DAA-udgave'
  WHERE n.subjekt_type='person' AND n.subjekt_id=ANY(p_person_ids) AND coalesce(n.privat,false)=false
    AND person.levende=false AND coalesce(person.privat,false)=false AND coalesce(person.staged,false)=false
    AND NOT EXISTS (SELECT 1 FROM private.narrative_record_publication p WHERE p.narrative_id=n.id)
$$;
REVOKE ALL ON FUNCTION public.public_person_bio_source_versions(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_person_bio_source_versions(bigint[]) TO anon,authenticated;

CREATE OR REPLACE FUNCTION red_publicer_narrative_record(
  p_narrative_id bigint,p_source_record_id uuid,p_record_label text,p_citation_label text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_binding private.narrative_record_publication%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  -- C3 adversarial review, fund B4 (2026-08-22): absence cannot be locked with a row
  -- lock. narrative_record_publication is unique on narrative_id and record_ref but NOT
  -- on source_record_id, so FOR UPDATE on a binding that does not exist protects nothing:
  -- a concurrent writer could publish a DIFFERENT narrative for the SAME source record
  -- and both could commit. Serialise on the source record itself, in the same position
  -- as red_apply_reimport_cases' step 5, so the two writers can never take the source
  -- record and the binding rows in opposite order. The declarative
  -- narrative_record_publication_active_record_uidx is the primary guard; this lock is
  -- the lock-discipline half of the same fix.
  PERFORM 1 FROM private.source_record WHERE id = p_source_record_id FOR UPDATE;
  SELECT * INTO v_binding FROM private.narrative_record_publication
    WHERE narrative_id=p_narrative_id FOR UPDATE;
  IF FOUND THEN
    IF v_binding.source_record_id IS DISTINCT FROM p_source_record_id
       OR v_binding.record_label IS DISTINCT FROM p_record_label
       OR v_binding.citation_label IS DISTINCT FROM p_citation_label THEN
      RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_BINDING_MISMATCH';
    END IF;
    IF v_binding.status<>'draft' THEN RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_ALREADY_BOUND'; END IF;
    UPDATE private.narrative_record_publication SET status='published'
      WHERE id=v_binding.id RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (p_narrative_id,p_source_record_id,p_record_label,p_citation_label,'published') RETURNING id INTO v_id;
  RETURN v_id;
END $$;
CREATE OR REPLACE FUNCTION red_tilbagetraek_narrative_record(p_narrative_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  UPDATE private.narrative_record_publication SET status='withdrawn' WHERE narrative_id=p_narrative_id AND status='published';
  IF NOT FOUND THEN RAISE EXCEPTION 'SOURCE_RECORD_PUBLICATION_NOT_PUBLISHED'; END IF;
END $$;
REVOKE ALL ON FUNCTION red_publicer_narrative_record(bigint,uuid,text,text),red_tilbagetraek_narrative_record(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_publicer_narrative_record(bigint,uuid,text,text),red_tilbagetraek_narrative_record(bigint) TO authenticated;

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

-- Medie-metadata (spec docs/superpowers/specs/2026-08-06-medie-metadata-design.md §1).
-- Faktatyper på media-entiteten — ingen kolonner (invariant 2+3). Skrives via red_upsert_fakta.
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','kilde_url',         'Kilde-URL — permalink til billedside hos ekstern kilde'),
  ('faktatype','kilde_institution', 'Kilde-institution / datapartner'),
  ('faktatype','ekstern_objekt_id', 'Institutionens objekt-/inventar-ID'),
  ('faktatype','hentedato',         'Dato mediet blev hentet fra kilden'),
  ('faktatype','fotograf',          'Fotograf af reproduktionen (≠ kunstner/ophavsmand)'),
  ('faktatype','rettighedshaver',   'Rettighedshaver / Rechtewahrnehmung'),
  ('faktatype','kreditlinje',       'Ordret kreditlinje som kilden kræver vist'),
  ('faktatype','beskrivelse',       'Beskrivelse/proveniens-prosa'),
  ('faktatype','alt_tekst',         'Alt-tekst til skærmlæsere'),
  ('faktatype','teknik',            'Teknik/materiale (fx olie på lærred)'),
  ('faktatype','fysiske_maal',      'Fysiske mål (fx 92 × 73 cm)'),
  ('faktatype','datering',          'Datering af værket (fuzzy dato på fact)')
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
-- ID-kontrakt: relation/assertion/conclusion bruger GENERATED BY DEFAULT AS IDENTITY
-- både på clean-slate- og migrationsstien. BY DEFAULT bevarer loaderens mulighed for at
-- sætte eksplicitte id'er; loaderen synkroniserer sekvenserne før commit. Redaktionelle
-- writers allokerer via DEFAULT, så de ikke kan kollidere med hinanden via max(id)+1.
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

  INSERT INTO assertion(target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ('fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;

  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ('fact', v_fact, v_assert,
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
  INSERT INTO assertion(target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ('fact', p_fact_id, p_vaerdi,
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
  INSERT INTO assertion(target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ('fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ('fact', v_fact, v_assert,
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
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES (v_target_type, v_target_id, p_assertion_id,
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

  INSERT INTO assertion(target_type, target_id, vaerdi_tekst, date_min, date_max,
                        date_qualifier, date_raw, calendar, uforanderlig)
    VALUES (v_old.target_type, v_old.target_id,
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
    INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
      VALUES (v_old.target_type, v_old.target_id,
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
DECLARE v_facts bigint[]; v_rels bigint[]; v_contract_version integer;
BEGIN
  -- #152: serialize with the atomic narrative-record cutover before every
  -- existing delete lock. Publication history is append-only, so whole-person
  -- hard delete stays fail-closed until the retention/tombstone design exists.
  PERFORM pg_advisory_xact_lock_shared(
    hashtextextended('daa-narrative-record-contract',0)
  );
  v_contract_version:=public.narrative_record_contract_version();
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF EXISTS (
    SELECT 1
      FROM private.narrative_publication_event event
      JOIN public.narrative narrative ON narrative.id=event.narrative_id
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=p_person_id
  ) THEN
    RAISE EXCEPTION 'PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  PERFORM private.guard_identity_mutation_snapshot();

  -- 2026-08-20: private.source_persona_identity(_event).canonical_person_id har FK mod person
  -- uden ON DELETE, og _event er append-only (kun BEFORE INSERT-trigger). Har personen én gang
  -- været mål for en ACCEPTERET kilde-identifikation, bærer den historiske event stadig id'et,
  -- og sletningen kan aldrig lykkes — heller ikke efter en tilbagetrækning. Vi afviser derfor
  -- tidligt med en forståelig fejl i stedet for at lade en rå FK-violation slippe ud midt i
  -- en halvt udført sletning. Den varige løsning er et arkitekturvalg; se docs/decisions.md.
  IF EXISTS (SELECT 1 FROM private.source_persona_identity_event
               WHERE canonical_person_id = p_person_id)
     OR EXISTS (SELECT 1 FROM private.source_persona_identity
               WHERE canonical_person_id = p_person_id) THEN
    RAISE EXCEPTION 'PERSON_HAR_KILDEIDENTITET: personen er mål for en accepteret kilde-identifikation, og beslutningssporet er uforanderligt. Sletning er ikke mulig — se docs/decisions.md om tombstone-valget.';
  END IF;

  PERFORM begin_change_set('red_slet_person', format('Slettede person %s', p_person_id), 'person', p_person_id);

  -- Fælles skriveorden med OCR-rettelsen: source/external-id → person → evidens.
  -- Sletningen må vente her, før den tager citation/assertion, ellers kan to transaktioner
  -- danne cyklussen external-id→citation / citation→external-id.
  PERFORM 1 FROM source s JOIN person_external_id pei ON pei.source_id=s.id
    WHERE pei.person_id=p_person_id ORDER BY s.id,pei.source_id FOR UPDATE OF s,pei;
  PERFORM private.lock_identity_people(ARRAY[p_person_id]);

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

  -- 2026-08-20: private.narrative_record_publication har FK mod narrative(id) UDEN ON DELETE,
  -- så den blokerede sletningen for alle 551 narrativ-bundne 1939-personer. Bindingen siger
  -- »dette narrativ stammer fra denne kilderecord« — når narrativet går, er udsagnet
  -- meningsløst, så bindingen skal med. private.source_record røres derimod ALDRIG: at
  -- teksten står på siden er stadig sandt. Skema-kvalificeret, fordi SET search_path=public.
  DELETE FROM private.narrative_record_publication WHERE narrative_id IN (
    SELECT id FROM narrative WHERE subjekt_type='person' AND subjekt_id=p_person_id);
  DELETE FROM narrative          WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  -- 2026-08-20: haendelse.relation_id/fact_id har FK uden ON DELETE. relation_id er en PÅVIST
  -- blokering: red_slet_person samler relationer hvor personen er subjekt ELLER objekt, mens
  -- hændelses-loaderen forankrer efter subjekt alene — en relation Q→P kan derfor bære en
  -- hændelse under Q's narrativ, som overlever når P slettes. fact_id tages med for symmetri
  -- (loaderen filtrerer i dag fakta til narrativets egen person, så den sti er ikke påvist).
  -- Hændelseslaget er regenererbart, og begge kolonner er skip-cols i versioneringen, så vi
  -- løsner ankeret i stedet for at slette en anden persons hændelse.
  UPDATE haendelse SET relation_id = NULL WHERE relation_id = ANY(v_rels);
  UPDATE haendelse SET fact_id     = NULL WHERE fact_id     = ANY(v_facts);

  DELETE FROM relation           WHERE id = ANY(v_rels);
  DELETE FROM fact               WHERE id = ANY(v_facts);
  DELETE FROM person_external_id WHERE person_id = p_person_id;
  DELETE FROM family_member      WHERE person_id = p_person_id;
  -- review 19 H2: slaegtsnavn_karantaene.person_id har ingen ON DELETE CASCADE — uden denne linje
  -- fejler sletningen for enhver person der har >1 distinkt effektivt efternavn (fan-out).
  DELETE FROM slaegtsnavn_karantaene WHERE person_id = p_person_id;
  -- 2026-08-20: samme klasse som H2 ovenfor — person_id er NOT NULL uden ON DELETE CASCADE,
  -- så et medlemskab blokerer sletningen. Et medlemskab uden sin person er meningsløst.
  DELETE FROM person_slaegt_membership   WHERE person_id = p_person_id;
  DELETE FROM person_lineage_membership  WHERE person_id = p_person_id;
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
DECLARE v_id bigint; v_contract_version integer;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  v_contract_version:=public.narrative_record_contract_version();
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF v_contract_version>=2 AND p_subjekt_type='person' AND EXISTS(
    SELECT 1 FROM public.source WHERE id=p_source_id AND slags='DAA-udgave'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_REQUIRED';
  END IF;
  PERFORM begin_change_set('red_upsert_narrativ', format('Opdaterede narrativ på %s/%s (kilde %s)', p_subjekt_type, p_subjekt_id, p_source_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND source_id IS NOT DISTINCT FROM p_source_id
    ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(subjekt_type, subjekt_id, source_id, tekst, side, privat)
      VALUES (p_subjekt_type, p_subjekt_id, p_source_id, p_tekst, p_side, p_privat)
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
    INSERT INTO relation(subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
      VALUES (p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
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
  -- Helperen er også en rå intern skrivevej. Den skal derfor selv bevise den globale
  -- identity-låserækkefølge; top-level RPC-gates alene er ikke tilstrækkelige.
  PERFORM private.prelock_identity_relation_delete(p_relation_id);
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_role text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Klassificér uden rækkelås. Identity/absent tager den globale protokol før
  -- change_set; unrelated bevarer repository-ordenen change_set -> relation tuple.
  SELECT rolle INTO v_role FROM relation WHERE id=p_relation_id;
  IF NOT FOUND OR v_role IN ('samme_som','ikke_samme_som') THEN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    PERFORM private.guard_identity_mutation_snapshot();
    PERFORM private.prelock_identity_relation_delete(p_relation_id);
    PERFORM begin_change_set('red_slet_relation', format('Slettede relation %s', p_relation_id), NULL, NULL);
  ELSE
    PERFORM begin_change_set('red_slet_relation', format('Slettede relation %s', p_relation_id), NULL, NULL);
    -- Helperen tager kun tuple-lock. Rolle-drift til identity fejler retry-required;
    -- helperen tager aldrig advisory/generation sent.
    PERFORM private.prelock_identity_relation_delete(p_relation_id);
  END IF;
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
-- En permanent privat tabel bruges som transaktionsbundet bevis mellem prelock-helperen og
-- relationens BEFORE UPDATE-trigger. Rækken indeholder kun den eksakte relationsovergang og
-- de faktisk låste person-id'er. En deferred trigger sletter også et ubrugt bevis ved COMMIT;
-- ved ROLLBACK forsvinder INSERT'en naturligt med transaktionen.
CREATE TABLE IF NOT EXISTS private.identity_mutation_generation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  generation bigint NOT NULL DEFAULT 0,
  guard_transaction_id xid8,
  guard_backend_pid integer
);
INSERT INTO private.identity_mutation_generation(singleton,generation)
VALUES (true,0) ON CONFLICT (singleton) DO NOTHING;
ALTER TABLE private.identity_mutation_generation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.identity_mutation_generation FROM PUBLIC, anon, authenticated;

-- Advisory locks serialize lock acquisition, but do not refresh a REPEATABLE READ snapshot.
-- Updating this shared row after the advisory lock makes a stale RR writer fail with 40001
-- before it evaluates any graph predicate. READ COMMITTED writers see the refreshed state.
CREATE OR REPLACE FUNCTION private.guard_identity_mutation_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, private AS $$
BEGIN
  UPDATE private.identity_mutation_generation
     SET generation = generation + 1,
         guard_transaction_id = pg_catalog.pg_current_xact_id(),
         guard_backend_pid = pg_catalog.pg_backend_pid()
   WHERE singleton;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IDENTITY_MUTATION_GENERATION_MISSING';
  END IF;
END $$;
REVOKE ALL ON FUNCTION private.guard_identity_mutation_snapshot()
  FROM PUBLIC, anon, authenticated;

-- Denne rå tuple-lock/delete-gate tager ALDRIG advisory/generation. Identity eller
-- absent mål kræver i stedet et transaktionsbundet bevis fra en tidligere guard;
-- dermed fejler rolle-drift lukket uden sen låseinversion. Unrelated mål kan låses
-- efter change_set-allokering i repository-ordenen.
CREATE OR REPLACE FUNCTION private.prelock_identity_relation_delete(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_locked_role text; v_has_guard boolean;
BEGIN
  IF public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion';
  END IF;

  SELECT r.rolle INTO v_locked_role
  FROM public.relation r WHERE r.id=p_relation_id FOR UPDATE;
  IF NOT FOUND OR v_locked_role IN ('samme_som','ikke_samme_som') THEN
    SELECT EXISTS (
      SELECT 1 FROM private.identity_mutation_generation g
      WHERE g.singleton
        AND g.guard_transaction_id=pg_catalog.pg_current_xact_id()
        AND g.guard_backend_pid=pg_catalog.pg_backend_pid()
    ) INTO v_has_guard;
    IF NOT v_has_guard THEN
      RAISE EXCEPTION 'IDENTITY_RELATION_DELETE_RETRY_REQUIRED';
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION private.prelock_identity_relation_delete(bigint)
  FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.identity_relation_update_prelock (
  transaction_id xid8 NOT NULL,
  backend_pid integer NOT NULL,
  relation_id bigint NOT NULL,
  current_signature jsonb NOT NULL,
  target_signature jsonb NOT NULL,
  locked_person_ids bigint[] NOT NULL,
  PRIMARY KEY (transaction_id, backend_pid, relation_id)
);
ALTER TABLE private.identity_relation_update_prelock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.identity_relation_update_prelock FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.cleanup_identity_relation_update_prelock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, private AS $$
BEGIN
  DELETE FROM private.identity_relation_update_prelock p
  WHERE p.transaction_id = NEW.transaction_id
    AND p.backend_pid = NEW.backend_pid
    AND p.relation_id = NEW.relation_id;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION private.cleanup_identity_relation_update_prelock()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_identity_relation_update_prelock_cleanup
  ON private.identity_relation_update_prelock;
CREATE CONSTRAINT TRIGGER trg_identity_relation_update_prelock_cleanup
  AFTER INSERT ON private.identity_relation_update_prelock
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.cleanup_identity_relation_update_prelock();

-- Fælles låse-helper for alle identitets-writers og identitetstriggere. Direkte kald er
-- redaktion-gated; trigger-contexten håndhæver samme invariant for rå restore/undo-skrivninger.
CREATE OR REPLACE FUNCTION private.lock_identity_people(p_person_ids bigint[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_expected integer; v_locked integer;
BEGIN
  IF pg_trigger_depth() = 0 AND public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion';
  END IF;
  SELECT count(*) INTO v_expected
  FROM (SELECT DISTINCT x FROM unnest(p_person_ids) x WHERE x IS NOT NULL) q;
  SELECT count(*) INTO v_locked
  FROM (
    SELECT p.id FROM public.person p
    WHERE p.id IN (SELECT DISTINCT x FROM unnest(p_person_ids) x)
    ORDER BY p.id FOR UPDATE
  ) q;
  IF v_expected < 1 OR v_locked <> v_expected THEN
    RAISE EXCEPTION 'IDENTITY_PERSON_NOT_FOUND';
  END IF;
END $$;
REVOKE ALL ON FUNCTION private.lock_identity_people(bigint[]) FROM PUBLIC, anon, authenticated;

-- Global lock order for supported identity UPDATE/undo paths:
-- same_som_mutation -> ascending person rows -> transaction-bound exact prelock record ->
-- relation tuple. Row-triggeren læser kun bevisrækken og tager ingen blokerende prelock.
CREATE OR REPLACE FUNCTION private.prelock_identity_relation_update(
  p_current jsonb, p_target jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE
  v_ids bigint[];
  v_relation_id bigint;
  v_target_relation_id bigint;
  v_current_signature jsonb;
  v_target_signature jsonb;
  v_transaction_id xid8;
  v_backend_pid integer;
BEGIN
  IF public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  PERFORM private.guard_identity_mutation_snapshot();

  v_relation_id := (p_current->>'id')::bigint;
  v_target_relation_id := (p_target->>'id')::bigint;
  IF v_relation_id IS NULL OR v_target_relation_id IS DISTINCT FROM v_relation_id
     OR (coalesce(p_current->>'rolle','') NOT IN ('samme_som','ikke_samme_som')
         AND coalesce(p_target->>'rolle','') NOT IN ('samme_som','ikke_samme_som')) THEN
    RAISE EXCEPTION 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED';
  END IF;

  v_current_signature := jsonb_build_array(
    v_relation_id,p_current->>'rolle',p_current->>'subjekt_type',
    (p_current->>'subjekt_id')::bigint,p_current->>'objekt_type',
    (p_current->>'objekt_id')::bigint
  );
  v_target_signature := jsonb_build_array(
    v_target_relation_id,p_target->>'rolle',p_target->>'subjekt_type',
    (p_target->>'subjekt_id')::bigint,p_target->>'objekt_type',
    (p_target->>'objekt_id')::bigint
  );
  SELECT coalesce(array_agg(x ORDER BY x),'{}'::bigint[]) INTO v_ids
  FROM (
    SELECT DISTINCT x
    FROM (VALUES
      (CASE WHEN p_current->>'subjekt_type'='person' THEN (p_current->>'subjekt_id')::bigint END),
      (CASE WHEN p_current->>'objekt_type'='person' THEN (p_current->>'objekt_id')::bigint END),
      (CASE WHEN p_target->>'subjekt_type'='person' THEN (p_target->>'subjekt_id')::bigint END),
      (CASE WHEN p_target->>'objekt_type'='person' THEN (p_target->>'objekt_id')::bigint END)
    ) ids(x)
    WHERE x IS NOT NULL
  ) sorted_ids;
  PERFORM private.lock_identity_people(v_ids);

  -- Beviset opstår først efter at ALLE eksakte, sorterede personrækker er låst.
  v_transaction_id := pg_catalog.pg_current_xact_id();
  v_backend_pid := pg_catalog.pg_backend_pid();
  DELETE FROM private.identity_relation_update_prelock p
  WHERE p.transaction_id=v_transaction_id
    AND p.backend_pid=v_backend_pid
    AND p.relation_id=v_relation_id;
  INSERT INTO private.identity_relation_update_prelock(
    transaction_id,backend_pid,relation_id,current_signature,target_signature,locked_person_ids
  ) VALUES (
    v_transaction_id,v_backend_pid,v_relation_id,
    v_current_signature,v_target_signature,v_ids
  );
END $$;
REVOKE ALL ON FUNCTION private.prelock_identity_relation_update(jsonb,jsonb)
  FROM PUBLIC, anon, authenticated;

-- SECURITY DEFINER (2026-08-01): guarden nedenfor kalder _samme_som_gruppe, hvis EXECUTE er
-- revoked fra anon/authenticated. Alle reelle skriveveje går gennem definer-RPC'er og kører
-- allerede som ejer, men uden dette ville en fremtidig ikke-ejer-sti fejle på rettigheder frem
-- for på invarianten. Funktionen skriver intet — den læser og rejser.
CREATE OR REPLACE FUNCTION enforce_samme_som_invariants() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_has_exact_prelock boolean;
  v_current_signature jsonb;
  v_target_signature jsonb;
  v_expected_person_ids bigint[];
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
    v_current_signature := jsonb_build_array(
      OLD.id,OLD.rolle,OLD.subjekt_type,OLD.subjekt_id,OLD.objekt_type,OLD.objekt_id
    );
    v_target_signature := jsonb_build_array(
      NEW.id,NEW.rolle,NEW.subjekt_type,NEW.subjekt_id,NEW.objekt_type,NEW.objekt_id
    );
    SELECT coalesce(array_agg(x ORDER BY x),'{}'::bigint[])
      INTO v_expected_person_ids
    FROM (
      SELECT DISTINCT x
      FROM (VALUES
        (CASE WHEN OLD.subjekt_type='person' THEN OLD.subjekt_id END),
        (CASE WHEN OLD.objekt_type='person' THEN OLD.objekt_id END),
        (CASE WHEN NEW.subjekt_type='person' THEN NEW.subjekt_id END),
        (CASE WHEN NEW.objekt_type='person' THEN NEW.objekt_id END)
      ) ids(x)
      WHERE x IS NOT NULL
    ) sorted_ids;
    SELECT EXISTS (
      SELECT 1 FROM private.identity_relation_update_prelock p
      WHERE p.transaction_id=pg_catalog.pg_current_xact_id()
        AND p.backend_pid=pg_catalog.pg_backend_pid()
        AND p.relation_id=OLD.id
        AND p.current_signature=v_current_signature
        AND p.target_signature=v_target_signature
        AND p.locked_person_ids=v_expected_person_ids
    ) INTO v_has_exact_prelock;
    IF NOT v_has_exact_prelock THEN
      RAISE EXCEPTION 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED';
    END IF;
    IF NEW.rolle = 'ikke_samme_som'
       AND NEW.subjekt_type = 'person' AND NEW.objekt_type = 'person' THEN
      IF EXISTS (
        SELECT 1
        FROM public._samme_som_gruppe(NEW.subjekt_id) a
        JOIN public._samme_som_gruppe(NEW.objekt_id) b ON b.pid = a.pid
      ) THEN
        RAISE EXCEPTION 'IDENTITY_COMPONENT_CONTRADICTION: ikke_samme_som overlapper samme_som-komponent';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.rolle NOT IN ('samme_som','ikke_samme_som')
     OR NEW.subjekt_type <> 'person' OR NEW.objekt_type <> 'person' THEN
    RETURN NEW; -- ikke et person→person identitetsforhold — rør ikke
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation')); -- serialisér samme_som-mutationer
  PERFORM private.guard_identity_mutation_snapshot();
  PERFORM private.lock_identity_people(ARRAY[NEW.subjekt_id, NEW.objekt_id]);
  IF NEW.rolle = 'ikke_samme_som' THEN
    IF EXISTS (
      SELECT 1
      FROM public._samme_som_gruppe(NEW.subjekt_id) a
      JOIN public._samme_som_gruppe(NEW.objekt_id) b ON b.pid = a.pid
    ) THEN
      RAISE EXCEPTION 'IDENTITY_COMPONENT_CONTRADICTION: ikke_samme_som overlapper samme_som-komponent';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.subjekt_id = NEW.objekt_id THEN
    RAISE EXCEPTION 'samme_som: kan ikke linke en person til sig selv';
  END IF;
  IF private.identity_components_have_rejection(NEW.subjekt_id, NEW.objekt_id) THEN
    RAISE EXCEPTION 'IDENTITY_COMPONENT_CONTRADICTION: samme_som bridge forbinder afviste komponenter';
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
  FOR EACH ROW WHEN (NEW.rolle IN ('samme_som','ikke_samme_som')) EXECUTE FUNCTION enforce_samme_som_invariants();
DROP TRIGGER IF EXISTS trg_enforce_samme_som_update ON relation;
CREATE TRIGGER trg_enforce_samme_som_update BEFORE UPDATE ON relation
  FOR EACH ROW WHEN (OLD.rolle IN ('samme_som','ikke_samme_som')
                     OR NEW.rolle IN ('samme_som','ikke_samme_som'))
  EXECUTE FUNCTION enforce_samme_som_invariants();

-- Opret et redaktionelt identitets-link. Tynd, evidens-komplet wrapper ovenpå invariant-triggeren.
-- Idempotent på præcis retning (FØR change_set → ingen tom audit ved gentagelse).
CREATE OR REPLACE FUNCTION red_samme_som(p_alias_id bigint, p_objekt_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  PERFORM private.guard_identity_mutation_snapshot();
  PERFORM private.lock_identity_people(ARRAY[p_alias_id, p_objekt_id]);
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
  INSERT INTO relation(subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ('person', p_alias_id, 'person', p_objekt_id, 'samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(target_type, target_id, vaerdi_tekst)
    VALUES ('relation', v_rel, 'samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ('relation', v_rel, v_ass, 'afklaret',
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
  PERFORM private.guard_identity_mutation_snapshot();
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
  PERFORM private.guard_identity_mutation_snapshot();
  PERFORM private.lock_identity_people(ARRAY[p_a, p_b]);
  IF p_a = p_b THEN RAISE EXCEPTION 'ikke_samme_som: kan ikke afvise en person mod sig selv'; END IF;
  v_lo := least(p_a, p_b); v_hi := greatest(p_a, p_b);
  -- Idempotens FØR change_set (ingen tom audit ved gentagelse; begge kald-retninger normaliseres).
  SELECT id INTO v_rel FROM relation WHERE rolle='ikke_samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=v_lo AND objekt_id=v_hi LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  -- Kontradiktions-guard: de to komponenter må ikke overlappe.
  IF EXISTS (
    SELECT 1
    FROM public._samme_som_gruppe(p_a) a
    JOIN public._samme_som_gruppe(p_b) b ON b.pid = a.pid
  ) THEN
    RAISE EXCEPTION 'IDENTITY_COMPONENT_CONTRADICTION: ikke_samme_som overlapper samme_som-komponent';
  END IF;
  PERFORM begin_change_set('red_ikke_samme_som',
    format('Markerede person %s og %s som forskellige', v_lo, v_hi), 'person', v_lo);
  INSERT INTO relation(subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ('person', v_lo, 'person', v_hi, 'ikke_samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(target_type, target_id, vaerdi_tekst)
    VALUES ('relation', v_rel, 'ikke_samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ('relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitets-afvisning');
  RETURN v_rel;
END $$;

-- Fjern en identitets-afvisning. Egen change_set; genbruger den FK-ordnede evidens-sletning.
CREATE OR REPLACE FUNCTION red_fjern_ikke_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  PERFORM private.guard_identity_mutation_snapshot();
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
  INSERT INTO relation(subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ('person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
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
    INSERT INTO assertion(target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
      VALUES ('fact', v_slot, 'barn', 'family', p_family, true) RETURNING id INTO v_assert;
    INSERT INTO citation(id, assertion_id, source_id, citat_tekst, kvalitet)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL, '(kilde mangler: strukturel projektion)', 'sekundær');
  END IF;
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ('fact', v_slot, v_assert, 'afklaret', 'Redaktør (strukturel)', current_date)
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

CREATE OR REPLACE FUNCTION private.identity_components_have_rejection(
  p_left bigint, p_right bigint
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
BEGIN
  IF pg_trigger_depth() = 0 AND public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion';
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.relation r
    WHERE r.rolle = 'ikke_samme_som'
      AND r.subjekt_type = 'person' AND r.objekt_type = 'person'
      AND (
        (r.subjekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_left))
         AND r.objekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_right)))
        OR
        (r.objekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_left))
         AND r.subjekt_id IN (SELECT pid FROM public._samme_som_gruppe(p_right)))
      )
  );
END
$$;
REVOKE ALL ON FUNCTION private.identity_components_have_rejection(bigint,bigint) FROM PUBLIC, anon, authenticated;

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

  INSERT INTO assertion(target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
    VALUES ('fact', v_fact, 'barn', 'family', p_family_id, true)
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
      INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
        VALUES ('fact', v_fact, v_assert, 'afklaret',
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
  INSERT INTO conclusion(target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ('fact', v_fact, p_assertion_id, 'afklaret', 'Redaktør', current_date)
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
DECLARE
  v_rels jsonb;
  v_nfacts int;
  v_nnarr int;
  v_nbind int;
  v_nmedlem int;
  v_nevents int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT count(*) INTO v_nfacts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  -- 2026-08-20: preview rapporterede kun fakta og relationer, så redaktøren kunne ikke se at
  -- en biografi og dens kildebinding fulgte med. Skema-kvalificeret (SET search_path=public).
  SELECT count(*) INTO v_nnarr FROM narrative
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT count(*) INTO v_nbind FROM private.narrative_record_publication p
    JOIN narrative n ON n.id = p.narrative_id
    WHERE n.subjekt_type='person' AND n.subjekt_id=p_person_id;
  SELECT count(*) INTO v_nevents
    FROM private.narrative_publication_event event
    JOIN narrative n ON n.id=event.narrative_id
   WHERE n.subjekt_type='person' AND n.subjekt_id=p_person_id;
  SELECT (SELECT count(*) FROM person_slaegt_membership  WHERE person_id=p_person_id)
       + (SELECT count(*) FROM person_lineage_membership WHERE person_id=p_person_id)
    INTO v_nmedlem;
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
    'antal_narrativer', v_nnarr,
    'antal_bindinger', v_nbind,
    'antal_medlemskaber', v_nmedlem,
    'antal_publication_events', v_nevents,
    'sletning_blokeret', v_nevents>0,
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
  ('story_kilde',        ARRAY['id'], '{}'),  -- red_set_story_kilder kører DELETE+INSERT her (#127)
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
  ('profiles',           ARRAY['id'], ARRAY['email','rolle']),  -- versionér kun reventlow_person_id-binding (spec §4.3.1)
  -- 2026-08-20: red_slet_person rydder nu medlemskaberne (person_id NOT NULL uden cascade
  -- blokerede sletningen). Uden registrering ville den sletning være ufortrydelig: fortryd
  -- ville give personen tilbage uden dens slægts- og linjetilhør.
  ('person_slaegt_membership',  ARRAY['person_id','slaegt_id'],  '{}'),
  ('person_lineage_membership', ARRAY['person_id','lineage_id'], '{}')
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

-- ---------- DAA 1939 v50 C3: generic reimport case ledger ----------
-- Deliberately GENERIC naming (not "1939_v50_c3"-scoped): parametrised on source_id +
-- phase so that a later phase extends the phase vocabulary with a migration, not new
-- tables (issue #153). This is a separate, structurally similar family, NOT a rename
-- of private.reimport_1939_* above -- that family is untouched.
--
-- private.require_reimport_1939_editor() and private.reimport_1939_canonical_json_sha256()
-- (defined above) are reused as-is by the RPCs this ledger supports (Task 6): both are
-- already generic in behaviour despite their family-scoped names -- the role gate is
-- public.current_rolle()='redaktion' and the hash helper is plain jsonb canonicalisation,
-- neither is 1939-specific. Duplicating them under a generic name would be exactly the
-- kind of new debt the naming decision above exists to avoid.
--
-- Composite foreign keys below (batch->authorization, event->batch) each carry
-- (source_id,phase) alongside the referenced id, mirroring the existing
-- private.source_record -> private.extraction_run pattern (schema.sql:467-478). This
-- declaratively guarantees a batch/event can never point at a parent row scoped to a
-- different source or phase than its own -- the same "prefer declarative over lock
-- discipline alone" reasoning as the B4 index above.
CREATE TABLE private.reimport_case_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id bigint NOT NULL REFERENCES public.source(id),
  phase text NOT NULL CHECK (phase IN ('c3')),
  operation text NOT NULL CHECK (operation IN ('apply','reversal')),
  manifest_sha256 text NOT NULL CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  preview_sha256 text NOT NULL CHECK (preview_sha256 ~ '^[0-9a-f]{64}$'),
  approval_sha256 text NOT NULL CHECK (approval_sha256 ~ '^[0-9a-f]{64}$'),
  decisions_sha256 text NOT NULL CHECK (decisions_sha256 ~ '^[0-9a-f]{64}$'),
  state_sha256 text NOT NULL CHECK (state_sha256 ~ '^[0-9a-f]{64}$'),
  text_bundle_sha256 text NOT NULL CHECK (text_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  database_name text NOT NULL CHECK (btrim(database_name)<>''),
  system_identifier text NOT NULL CHECK (btrim(system_identifier)<>''),
  expected_counts jsonb NOT NULL CHECK (jsonb_typeof(expected_counts)='object'),
  authorized_elements jsonb NOT NULL CHECK (jsonb_typeof(authorized_elements)='object'),
  principal_id uuid NOT NULL,
  nonce uuid NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'issued' CHECK (status IN ('issued','consumed','expired')),
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT reimport_case_authorization_consumed_has_timestamp
    CHECK ((status='consumed')=(consumed_at IS NOT NULL)),
  CONSTRAINT reimport_case_authorization_id_source_phase_uk UNIQUE (id,source_id,phase)
);

CREATE TABLE private.reimport_case_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id uuid NOT NULL UNIQUE,
  source_id bigint NOT NULL REFERENCES public.source(id),
  phase text NOT NULL CHECK (phase IN ('c3')),
  operation text NOT NULL CHECK (operation IN ('apply','reversal')),
  manifest_sha256 text NOT NULL CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  preview_sha256 text NOT NULL CHECK (preview_sha256 ~ '^[0-9a-f]{64}$'),
  principal_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','finalized','reversed')),
  expected_counts jsonb NOT NULL CHECK (jsonb_typeof(expected_counts)='object'),
  observed_counts jsonb CHECK (observed_counts IS NULL OR jsonb_typeof(observed_counts)='object'),
  change_set_id bigint REFERENCES public.change_set(id),
  reversal_batch_id uuid REFERENCES private.reimport_case_batch(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_at timestamptz,
  CONSTRAINT reimport_case_batch_reversed_has_reversal
    CHECK ((status='reversed')=(reversal_batch_id IS NOT NULL)),
  CONSTRAINT reimport_case_batch_id_source_phase_uk UNIQUE (id,source_id,phase),
  CONSTRAINT reimport_case_batch_authorization_source_phase_fk
    FOREIGN KEY (authorization_id,source_id,phase)
    REFERENCES private.reimport_case_authorization(id,source_id,phase)
);
CREATE UNIQUE INDEX reimport_case_batch_manifest_uidx
  ON private.reimport_case_batch(source_id,phase,manifest_sha256,preview_sha256,principal_id);

CREATE TABLE private.reimport_case_event (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  batch_id uuid NOT NULL,
  source_id bigint NOT NULL REFERENCES public.source(id),
  phase text NOT NULL CHECK (phase IN ('c3')),
  element_id text NOT NULL CHECK (btrim(element_id)<>''),
  action text NOT NULL CHECK (action IN ('identity_different','record_assign','record_no_publication')),
  payload_schema_version text NOT NULL CHECK (payload_schema_version='c3-apply-v1'),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object'),
  before_sha256 text CHECK (before_sha256 IS NULL OR before_sha256 ~ '^[0-9a-f]{64}$'),
  after_sha256 text NOT NULL CHECK (after_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT reimport_case_event_batch_element_uk UNIQUE (batch_id,element_id),
  CONSTRAINT reimport_case_event_batch_source_phase_fk
    FOREIGN KEY (batch_id,source_id,phase)
    REFERENCES private.reimport_case_batch(id,source_id,phase)
);

CREATE FUNCTION private.reject_reimport_case_event_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'REIMPORT_CASE_EVENT_APPEND_ONLY'; END $$;
CREATE TRIGGER trg_reimport_case_event_append_only
  BEFORE UPDATE OR DELETE ON private.reimport_case_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_reimport_case_event_mutation();

ALTER TABLE private.reimport_case_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_case_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reimport_case_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reimport_case_authorization,private.reimport_case_batch,private.reimport_case_event FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.reject_reimport_case_event_mutation() FROM PUBLIC,anon,authenticated;

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
DECLARE v_pk_cols text; v_set text; v_cols text; v_exists boolean; v_current jsonb;
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
  v_current := _version_current_row(p_tabel, _row_pk(p_tabel, p_row));
  v_exists := v_current IS NOT NULL;
  IF v_exists THEN
    IF p_tabel = 'relation'
       AND (v_current->>'rolle' IN ('samme_som','ikke_samme_som')
            OR p_row->>'rolle' IN ('samme_som','ikke_samme_som')) THEN
      PERFORM private.prelock_identity_relation_update(v_current,p_row);
    END IF;
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
  IF p_tabel='relation' THEN
    PERFORM private.prelock_identity_relation_delete((p_pk->>'id')::bigint);
  END IF;
  EXECUTE format('DELETE FROM %I WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk));
END $$;
-- ---------- VERSIONERING: restore ----------
CREATE OR REPLACE FUNCTION red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  ev change_event; v_new_cs bigint; v_orig change_set;
  v_cur jsonb; v_pids bigint[] := '{}'; v_narr bigint[] := '{}'; v_notes bigint[] := '{}';
  v_div int := 0; pid bigint; v_forventet jsonb; v_contract_version integer;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  v_contract_version:=public.narrative_record_contract_version();
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Publication writers hold ACCESS EXCLUSIVE while allocating their audit
  -- set and appending its event. Take the weakest conflicting table lock before
  -- the dedicated-routing predicate so the predicate cannot race an uncommitted
  -- event. ACCESS SHARE remains compatible with ordinary legacy writers and
  -- preserves their identity-advisory -> change_set ordering.
  LOCK TABLE public.change_set IN ACCESS SHARE MODE;
  IF EXISTS (
    SELECT 1
    FROM private.narrative_publication_event
    WHERE change_set_id = p_change_set_id
  ) OR (
    v_contract_version >= 2
    AND EXISTS (
      SELECT 1
      FROM public.change_event ce
      WHERE ce.change_set_id = p_change_set_id
        AND ce.tabel = 'narrative'
        AND ce.row_pk ? 'id'
        AND (
          EXISTS (
            SELECT 1
            FROM private.narrative_publication_event npe
            WHERE npe.narrative_id = (ce.row_pk->>'id')::bigint
          )
          OR EXISTS (
            SELECT 1
            FROM private.narrative_legacy_publication nlp
            WHERE nlp.narrative_id = (ce.row_pk->>'id')::bigint
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED';
  END IF;
  SELECT * INTO v_orig FROM change_set WHERE id=p_change_set_id;
  IF v_orig.id IS NULL THEN RAISE EXCEPTION 'FEJL: change_set % findes ikke', p_change_set_id; END IF;
  -- allerede reverteret? (reversal-kæde; M3)
  IF EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=p_change_set_id) THEN
    RAISE EXCEPTION 'FEJL: change_set % er allerede fortrudt', p_change_set_id;
  END IF;

  -- Forudscan HELE sættet før reversal-audit eller inverse DML. Hvis nogen inverse
  -- operation kan indsætte, opdatere eller slette en identitetsrelation, tages den
  -- fælles advisory+generation-protokol én gang i den globale rækkefølge.
  IF EXISTS (
    SELECT 1 FROM change_event ce
    WHERE ce.change_set_id=p_change_set_id AND ce.tabel='relation' AND (
      p_force OR CASE ce.op
        WHEN 'INSERT' THEN ce.efter->>'rolle' IN ('samme_som','ikke_samme_som')
        WHEN 'DELETE' THEN ce.foer->>'rolle' IN ('samme_som','ikke_samme_som')
        WHEN 'UPDATE' THEN ce.foer->>'rolle' IN ('samme_som','ikke_samme_som')
                            OR ce.efter->>'rolle' IN ('samme_som','ikke_samme_som')
        ELSE false
      END)
  ) THEN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    PERFORM private.guard_identity_mutation_snapshot();
  END IF;

  -- åbn reversal-sæt (re-entrant: triggere fanger ikke restore-DML ind under DET, da vi
  -- bevidst NULLER app.change_set_id under selve inverse — se nedenfor). Vi logger restore
  -- som ÉT change_set uden child-events for ikke at dobbelt-logge; reversal-kæden er sporet.
  PERFORM set_config('app.change_set_id','',true);  -- undgå at inverse-DML re-logges
  IF pg_get_serial_sequence('public.change_set','id') IS NULL THEN
    v_new_cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
    INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                           subjekt_type, subjekt_id, subjekt_synlighed, reverterer_id)
      VALUES (v_new_cs, auth.uid(),
              coalesce((SELECT coalesce(p.navn, p.email, auth.uid()::text) FROM profiles p WHERE p.id=auth.uid()), 'ukendt'),
              current_rolle(), 'fortryd',
              format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
              v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id);
  ELSE
    INSERT INTO change_set(actor_id, actor_navn, actor_rolle, operation, summary,
                           subjekt_type, subjekt_id, subjekt_synlighed, reverterer_id)
      VALUES (auth.uid(),
              coalesce((SELECT coalesce(p.navn, p.email, auth.uid()::text) FROM profiles p WHERE p.id=auth.uid()), 'ukendt'),
              current_rolle(), 'fortryd',
              format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
              v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id)
      RETURNING id INTO v_new_cs;
  END IF;

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
REVOKE ALL ON FUNCTION red_slet_relation(bigint), red_fortryd_change_set(bigint,boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION red_slet_relation(bigint), red_fortryd_change_set(bigint,boolean)
  TO authenticated;
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
     OR (p_decision_status<>'accepted' AND p_canonical_person_id IS NOT NULL)
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID';
  END IF;

  -- Persona-rækken findes også før første state-række og er derfor den stabile
  -- serialiseringslås for to samtidige initiale afgørelser.
  PERFORM 1 FROM private.source_persona
   WHERE id=p_source_persona_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PERSONA_NOT_FOUND'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private.source_persona_mention
     WHERE persona_id=p_source_persona_id
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED';
  END IF;
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

-- Privat kø til menneskelig identitetsafgørelse. Kilden forekommer her, men
-- ingen af disse RPC'er er en offentlig projektion eller skriver i person.
CREATE OR REPLACE FUNCTION red_source_persona_queue(
  p_status text DEFAULT NULL, p_source_id bigint DEFAULT NULL,
  p_cursor uuid DEFAULT NULL, p_page_size integer DEFAULT 50
) RETURNS TABLE(
  source_persona_id uuid, source_id bigint, persona_key text,
  decision_status text, version integer, canonical_person_id bigint, mention_count bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('proposed','accepted','rejected','unresolved','superseded') THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_STATUS_INVALID';
  END IF;
  RETURN QUERY
  SELECT persona.id,persona.source_id,persona.persona_key,
         coalesce(identity_state.decision_status,'proposed'),coalesce(identity_state.version,0),
         identity_state.canonical_person_id,count(persona_mention.mention_id)
    FROM private.source_persona persona
    LEFT JOIN private.source_persona_identity identity_state ON identity_state.source_persona_id=persona.id
    LEFT JOIN private.source_persona_mention persona_mention ON persona_mention.persona_id=persona.id
   WHERE (p_source_id IS NULL OR persona.source_id=p_source_id)
     AND (p_cursor IS NULL OR persona.id>p_cursor)
     AND (p_status IS NULL OR coalesce(identity_state.decision_status,'proposed')=p_status)
   GROUP BY persona.id,identity_state.decision_status,identity_state.version,identity_state.canonical_person_id
   ORDER BY persona.id
   LIMIT greatest(1,least(coalesce(p_page_size,50),100));
END $$;

CREATE OR REPLACE FUNCTION red_source_persona_detail(p_source_persona_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  SELECT jsonb_build_object(
    'persona',jsonb_build_object('source_persona_id',persona.id,'source_id',persona.source_id,
      'persona_key',persona.persona_key,'decision_status',coalesce(identity_state.decision_status,'proposed'),
      'version',coalesce(identity_state.version,0),'canonical_person_id',identity_state.canonical_person_id),
    'mentions',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'mention_kind',mention.mention_kind,'mention_role',persona_mention.mention_role,
      'verbatim_text',mention.verbatim_text,'observation_kind',observation.observation_kind,
      'page_from',observation.page_from,'page_to',observation.page_to,
      'text_versions',coalesce((SELECT jsonb_agg(jsonb_build_object('version',text_version.version,
        'verbatim_text',text_version.verbatim_text,'preferred',text_version.is_preferred)
        ORDER BY text_version.version) FROM private.source_observation_text text_version
        WHERE text_version.observation_id=observation.id),'[]'::jsonb))
      ORDER BY persona_mention.ordinal)
      FROM private.source_persona_mention persona_mention
      JOIN private.source_mention mention ON mention.id=persona_mention.mention_id
      JOIN private.source_observation observation ON observation.id=mention.observation_id
      WHERE persona_mention.persona_id=persona.id),'[]'::jsonb),
    'placements',coalesce((SELECT jsonb_agg(jsonb_build_object('placement_role',persona_placement.placement_role,
      'printed_number',record_placement.printed_number,'generation_label_raw',record_placement.generation_label_raw))
      FROM private.source_persona_placement_current persona_placement
      JOIN private.source_record_placement_current record_placement ON record_placement.id=persona_placement.record_placement_id
      WHERE persona_placement.source_persona_id=persona.id
        AND persona_placement.decision_status='accepted'
        AND record_placement.decision_status='accepted'),'[]'::jsonb),
    -- Bevarer også modstridende/tvivlsomme fortolkninger som læsbar kontekst.
    'interpretations',coalesce((SELECT jsonb_agg(jsonb_build_object('predicate',interpretation.predicate,
      'value',interpretation.value,'status',interpretation.status,'confidence',interpretation.confidence,
      'derivation_kind',interpretation.derivation_kind) ORDER BY interpretation.created_at)
      FROM private.interpretation interpretation
      WHERE interpretation.source_persona_id=persona.id),'[]'::jsonb)
  ) INTO v_result
  FROM private.source_persona persona
  LEFT JOIN private.source_persona_identity identity_state ON identity_state.source_persona_id=persona.id
  WHERE persona.id=p_source_persona_id;
  IF v_result IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PERSONA_NOT_FOUND'; END IF;
  RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION red_source_persona_history(p_source_persona_id uuid)
RETURNS TABLE(version integer,decision_status text,canonical_person_id bigint,evidence jsonb,decided_by_name text,decided_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.source_persona WHERE id=p_source_persona_id) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_NOT_FOUND';
  END IF;
  RETURN QUERY SELECT event.version,event.decision_status,event.canonical_person_id,
    event.evidence,event.decided_by_name,event.decided_at
  FROM private.source_persona_identity_event event
  WHERE event.source_persona_id=p_source_persona_id ORDER BY event.version;
END $$;

-- Ét semantisk API for UI'et. "different" har med vilje intet kanonisk mål:
-- det er en kildeintern afvisning, ikke en påstand om en alternativ person.
CREATE OR REPLACE FUNCTION red_afgoer_source_persona(
  p_source_persona_id uuid, p_expected_version integer, p_action text,
  p_canonical_person_id bigint, p_note text
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_status text; v_version integer;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF p_action NOT IN ('same','different','unresolved')
     OR nullif(btrim(p_note),'') IS NULL
     OR (p_action='same' AND p_canonical_person_id IS NULL)
     OR (p_action<>'same' AND p_canonical_person_id IS NOT NULL) THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID';
  END IF;
  -- En afgørelse uden en observeret kildemention er aldrig tilladt.
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention WHERE persona_id=p_source_persona_id) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED';
  END IF;
  v_status:=CASE p_action WHEN 'same' THEN 'accepted' WHEN 'different' THEN 'rejected' ELSE 'unresolved' END;
  v_version:=red_decide_source_persona_identity(
    p_source_persona_id,p_canonical_person_id,p_expected_version,v_status,
    jsonb_build_object('note',btrim(p_note),'action',p_action,'basis','visible_source_persona_detail')
  );
  RETURN v_version;
END $$;

REVOKE ALL ON FUNCTION red_decide_interpretation(uuid,integer,text,jsonb),
                       red_promote_interpretation(uuid,text,bigint,jsonb),
                       red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb),
                       red_source_persona_queue(text,bigint,uuid,integer),
                       red_source_persona_detail(uuid),red_source_persona_history(uuid),
                       red_afgoer_source_persona(uuid,integer,text,bigint,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_decide_interpretation(uuid,integer,text,jsonb),
                          red_promote_interpretation(uuid,text,bigint,jsonb),
                          red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb),
                          red_source_persona_queue(text,bigint,uuid,integer),
                          red_source_persona_detail(uuid),red_source_persona_history(uuid),
                          red_afgoer_source_persona(uuid,integer,text,bigint,text)
  TO authenticated;

-- ---------- EVIDENS-PROMOTION: VALIDERET PREVIEW OG ATOMISK BATCH ----------
-- Det private resultat er en ren kontraktkontrol. Den opretter eller ændrer
-- aldrig kanonisk genealogi; den finder alene eksisterende assertions.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION private.validate_interpretation_promotion_items(
  p_items jsonb,p_lock boolean DEFAULT false
) RETURNS TABLE(
  item_ordinal integer,interpretation_id uuid,target_type text,target_id bigint,
  eligible boolean,rule_key text,rule_version integer,reason_code text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_ITEMS_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_items) AS element(item)
     WHERE jsonb_typeof(element.item)<>'object'
        OR (SELECT array_agg(key ORDER BY key)
              FROM jsonb_object_keys(element.item) AS key)
             IS DISTINCT FROM ARRAY['interpretation_id','target_id','target_type']
        OR jsonb_typeof(element.item->'interpretation_id')<>'string'
        OR coalesce(element.item->>'interpretation_id','') !~*
             '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR jsonb_typeof(element.item->'target_type')<>'string'
        OR element.item->>'target_type'<>'assertion'
        OR jsonb_typeof(element.item->'target_id')<>'number'
        OR coalesce(element.item->>'target_id','') !~ '^-?[0-9]+$'
        OR length(element.item->>'target_id')>19
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_ITEMS_INVALID';
  END IF;

  -- Låseordenen følger de eksisterende writers: current fortolkning først
  -- (red_decide_interpretation låser kun denne), derefter source_persona og
  -- identity-state (red_decide_source_persona_identitys rækkefølge), så
  -- append-only placement og til sidst kanonisk assertion/fact. De gennemsete
  -- kanoniske writers tager ingen af de private låse, så der findes ingen
  -- modsat cyklus i den relevante writerflade. Ukendte UUID'er bevares som
  -- fail-closed output.
  IF p_lock THEN
    PERFORM 1
      FROM private.interpretation interpretation
     WHERE interpretation.id=ANY(ARRAY(
       SELECT current_interpretation.id
         FROM private.interpretation_current current_interpretation
         JOIN private.interpretation requested
           ON requested.interpretation_key=current_interpretation.interpretation_key
        WHERE requested.id=ANY(ARRAY(
          SELECT (element.item->>'interpretation_id')::uuid
            FROM jsonb_array_elements(p_items) AS element(item)
        ))
     ))
     ORDER BY interpretation.id FOR UPDATE;
    PERFORM 1
      FROM private.interpretation_promotion_rule_line rule_line
     WHERE rule_line.predicate=ANY(ARRAY(
       SELECT current_interpretation.predicate
         FROM private.interpretation_current current_interpretation
         JOIN private.interpretation requested
           ON requested.interpretation_key=current_interpretation.interpretation_key
        WHERE requested.id=ANY(ARRAY(
          SELECT (element.item->>'interpretation_id')::uuid
            FROM jsonb_array_elements(p_items) AS element(item)
        ))
     ))
     ORDER BY rule_line.rule_key FOR UPDATE;
    PERFORM 1
      FROM private.source_persona persona
     WHERE persona.id=ANY(ARRAY(
       SELECT current_interpretation.source_persona_id
         FROM private.interpretation_current current_interpretation
         JOIN private.interpretation requested
           ON requested.interpretation_key=current_interpretation.interpretation_key
        WHERE requested.id=ANY(ARRAY(
          SELECT (element.item->>'interpretation_id')::uuid
            FROM jsonb_array_elements(p_items) AS element(item)
        ))
     ))
     ORDER BY persona.id FOR UPDATE;
    PERFORM 1
      FROM private.source_persona_identity identity_state
     WHERE identity_state.source_persona_id=ANY(ARRAY(
       SELECT current_interpretation.source_persona_id
         FROM private.interpretation_current current_interpretation
         JOIN private.interpretation requested
           ON requested.interpretation_key=current_interpretation.interpretation_key
        WHERE requested.id=ANY(ARRAY(
          SELECT (element.item->>'interpretation_id')::uuid
            FROM jsonb_array_elements(p_items) AS element(item)
        ))
     ))
     ORDER BY identity_state.source_persona_id FOR UPDATE;
    PERFORM 1
      FROM private.source_persona_placement placement
     WHERE placement.source_persona_id=ANY(ARRAY(
       SELECT current_interpretation.source_persona_id
         FROM private.interpretation_current current_interpretation
         JOIN private.interpretation requested
           ON requested.interpretation_key=current_interpretation.interpretation_key
        WHERE requested.id=ANY(ARRAY(
          SELECT (element.item->>'interpretation_id')::uuid
            FROM jsonb_array_elements(p_items) AS element(item)
        ))
     ))
     ORDER BY placement.source_persona_id,placement.record_placement_id,placement.placement_role
       FOR SHARE;
    PERFORM 1
      FROM public.assertion assertion
     WHERE assertion.id=ANY(ARRAY(
       SELECT (element.item->>'target_id')::bigint
         FROM jsonb_array_elements(p_items) AS element(item)
     ))
     ORDER BY assertion.id FOR SHARE;
    PERFORM 1
      FROM public.fact fact
     WHERE fact.id=ANY(ARRAY(
       SELECT assertion.target_id
         FROM public.assertion assertion
        WHERE assertion.id=ANY(ARRAY(
          SELECT (element.item->>'target_id')::bigint
            FROM jsonb_array_elements(p_items) AS element(item)
        )) AND assertion.target_type='fact'
     ))
     ORDER BY fact.id FOR SHARE;
  END IF;

  RETURN QUERY
  WITH parsed AS (
    SELECT ordinal::integer AS item_ordinal,
           (element.item->>'interpretation_id')::uuid AS interpretation_id,
           element.item->>'target_type' AS target_type,
           (element.item->>'target_id')::bigint AS target_id,
           count(*) OVER (
             PARTITION BY (element.item->>'interpretation_id')::uuid,
                          element.item->>'target_type',(element.item->>'target_id')::bigint
           ) AS duplicate_count
      FROM jsonb_array_elements(p_items) WITH ORDINALITY AS element(item,ordinal)
  ), checked AS (
    SELECT parsed.*,requested.id AS requested_id,current_interpretation.id AS current_id,
           current_interpretation.status,current_interpretation.predicate,
           current_interpretation.interpretation_kind,current_interpretation.value,
           rule.rule_key,rule.rule_version,rule.expected_fact_type,rule.value_kind,
           rule.requires_persona_identity,rule.requires_principal_placement,rule.bulk_eligible,
           identity_state.canonical_person_id,
           assertion.id AS assertion_id,assertion.vaerdi_tekst,assertion.date_raw,
           fact.id AS fact_id,fact.subjekt_type,fact.subjekt_id,fact.faktatype,
           EXISTS (
             SELECT 1 FROM private.interpretation_observation observation
              WHERE observation.interpretation_id=current_interpretation.id
           ) AS has_observation,
           EXISTS (
             SELECT 1 FROM private.source_persona_placement_current placement
              WHERE placement.source_persona_id=current_interpretation.source_persona_id
                AND placement.decision_status='accepted'
                AND placement.placement_role IN ('principal_member','co_principal')
           ) AS has_principal_placement,
           EXISTS (
             SELECT 1 FROM private.interpretation_promotion promotion
              WHERE promotion.interpretation_id=current_interpretation.id
                AND promotion.target_type=parsed.target_type
                AND promotion.target_id=parsed.target_id
           ) AS already_promoted
      FROM parsed
      LEFT JOIN private.interpretation requested ON requested.id=parsed.interpretation_id
      LEFT JOIN private.interpretation_current current_interpretation
        ON current_interpretation.interpretation_key=requested.interpretation_key
      LEFT JOIN private.interpretation_promotion_rule_current rule
        ON rule.predicate=current_interpretation.predicate
       AND rule.interpretation_kind=current_interpretation.interpretation_kind
       AND rule.target_type=parsed.target_type
       AND rule.status='active'
      LEFT JOIN private.source_persona_identity identity_state
        ON identity_state.source_persona_id=current_interpretation.source_persona_id
       AND identity_state.decision_status='accepted'
      LEFT JOIN public.assertion assertion
        ON assertion.id=parsed.target_id AND assertion.target_type='fact'
      LEFT JOIN public.fact fact ON fact.id=assertion.target_id
  )
  SELECT validated.item_ordinal,validated.interpretation_id,validated.target_type,validated.target_id,
         validated.reason_code IS NULL AS eligible,validated.rule_key,validated.rule_version,
         validated.reason_code
    FROM (
      SELECT checked.*,
        CASE
          WHEN checked.requested_id IS NULL THEN 'EVIDENCE_INTERPRETATION_NOT_FOUND'
          WHEN checked.current_id IS NULL OR checked.current_id<>checked.interpretation_id
            THEN 'EVIDENCE_INTERPRETATION_NOT_CURRENT'
          WHEN checked.status<>'accepted' THEN 'EVIDENCE_INTERPRETATION_NOT_ACCEPTED'
          WHEN checked.rule_key IS NULL THEN 'EVIDENCE_PROMOTION_RULE_NOT_ACTIVE'
          WHEN NOT checked.has_observation THEN 'EVIDENCE_INTERPRETATION_OBSERVATION_REQUIRED'
          WHEN checked.requires_persona_identity AND checked.canonical_person_id IS NULL
            THEN 'EVIDENCE_PROMOTION_IDENTITY_REQUIRED'
          WHEN checked.requires_principal_placement AND NOT checked.has_principal_placement
            THEN 'EVIDENCE_PROMOTION_PRINCIPAL_PLACEMENT_REQUIRED'
          WHEN checked.assertion_id IS NULL OR checked.fact_id IS NULL THEN 'EVIDENCE_PROMOTION_TARGET_NOT_FOUND'
          WHEN checked.requires_persona_identity
             AND (checked.subjekt_type<>'person' OR checked.subjekt_id<>checked.canonical_person_id)
            THEN 'EVIDENCE_PROMOTION_IDENTITY_MISMATCH'
          WHEN checked.faktatype<>checked.expected_fact_type THEN 'EVIDENCE_PROMOTION_FACT_TYPE_MISMATCH'
          WHEN checked.value_kind='text' AND lower(btrim(normalize(checked.value #>> '{}',NFC)))
               IS DISTINCT FROM lower(btrim(normalize(checked.vaerdi_tekst,NFC)))
            THEN 'EVIDENCE_PROMOTION_VALUE_MISMATCH'
          WHEN checked.value_kind='date_raw' AND lower(btrim(normalize(checked.value #>> '{}',NFC)))
               IS DISTINCT FROM lower(btrim(normalize(checked.date_raw,NFC)))
            THEN 'EVIDENCE_PROMOTION_VALUE_MISMATCH'
          WHEN jsonb_array_length(p_items)>1 AND NOT checked.bulk_eligible
            THEN 'EVIDENCE_PROMOTION_BULK_NOT_ELIGIBLE'
          WHEN checked.duplicate_count>1 THEN 'EVIDENCE_PROMOTION_DUPLICATE_ITEM'
          WHEN checked.already_promoted THEN 'EVIDENCE_PROMOTION_ALREADY_PROMOTED'
          ELSE NULL
        END AS reason_code
      FROM checked
    ) validated
   ORDER BY validated.item_ordinal;
END $$;

CREATE OR REPLACE FUNCTION private.canonical_interpretation_promotion_items(p_items jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT coalesce(jsonb_agg(item ORDER BY (item->>'interpretation_id')::uuid,
    item->>'target_type',(item->>'target_id')::bigint),'[]'::jsonb)
    FROM jsonb_array_elements(p_items) item
$$;

CREATE OR REPLACE FUNCTION private.preview_interpretation_promotions(
  p_items jsonb,p_lock boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_items jsonb; v_hash text; v_envelope jsonb; v_request jsonb;
BEGIN
  v_request:=private.canonical_interpretation_promotion_items(p_items);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'interpretation_id',checked.interpretation_id,'target_type',checked.target_type,
      'target_id',checked.target_id,'eligible',checked.eligible,
      'rule_key',checked.rule_key,'rule_version',checked.rule_version,
      'reason_code',checked.reason_code
    ) ORDER BY checked.item_ordinal),'[]'::jsonb)
    INTO v_items
    FROM private.validate_interpretation_promotion_items(v_request,p_lock) checked;
  v_envelope:=jsonb_build_object(
    'contract','interpretation-promotion-preview-v1',
    'request',v_request,
    'validated_items',v_items
  );
  v_hash:=encode(digest(v_envelope::text,'sha256'),'hex');
  RETURN jsonb_build_object('preview_hash',v_hash,'items',v_items);
END $$;

CREATE OR REPLACE FUNCTION red_preview_interpretation_promotions(
  p_items jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  RETURN private.preview_interpretation_promotions(p_items,false);
END $$;

CREATE OR REPLACE FUNCTION private.interpretation_promotion_profile(p_preview jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE v_rules jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rule_key',item->>'rule_key','rule_version',(item->>'rule_version')::integer
    ) ORDER BY item->>'rule_key',(item->>'rule_version')::integer),'[]'::jsonb)
    INTO v_rules
    FROM jsonb_array_elements(p_preview->'items') AS item;
  RETURN jsonb_build_object(
    'contract','interpretation-promotion-profile-v2',
    'preview_hash',p_preview->>'preview_hash','rule_profile',v_rules
  );
END $$;

CREATE OR REPLACE FUNCTION private.validate_interpretation_promotion_profile(p_profile jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
  IF jsonb_typeof(p_profile)<>'object'
     OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_profile) key)
          IS DISTINCT FROM ARRAY['contract','preview_hash','rule_profile']
     OR p_profile->>'contract'<>'interpretation-promotion-profile-v2'
     OR coalesce(p_profile->>'preview_hash','') !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(p_profile->'rule_profile')<>'array'
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_profile->'rule_profile') item
       WHERE jsonb_typeof(item)<>'object'
          OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) key)
               IS DISTINCT FROM ARRAY['rule_key','rule_version']
          OR jsonb_typeof(item->'rule_key')<>'string'
          OR nullif(btrim(item->>'rule_key'),'') IS NULL
          OR jsonb_typeof(item->'rule_version')<>'number'
          OR coalesce(item->>'rule_version','') !~ '^[1-9][0-9]*$'
     ) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_PROFILE_INVALID';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION private.interpretation_promotion_database_identity()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('database_name',current_database(),
    'system_identifier',(pg_control_system()).system_identifier::text)
$$;

CREATE OR REPLACE FUNCTION private.interpretation_promotion_batch_state(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_batch private.interpretation_promotion_batch%ROWTYPE; v_links jsonb; v_state_sha text;
BEGIN
  SELECT * INTO v_batch FROM private.interpretation_promotion_batch WHERE id=p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_BATCH_NOT_FOUND'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'promotion_id',p.id,'batch_id',p.batch_id,'authorization_id',p.evidence->>'authorization_id',
    'preview_hash',p.evidence->>'preview_hash','evidence',p.evidence,'promoted_by',p.promoted_by,
    'promoted_by_name',p.promoted_by_name,'interpretation_id',p.interpretation_id,'target_type',p.target_type,'target_id',p.target_id,
    'rule_key',p.rule_key,'rule_version',p.rule_version,
    'assertion',jsonb_build_object('id',a.id,'target_type',a.target_type,'target_id',a.target_id,
      'value',a.vaerdi_tekst,'date_raw',a.date_raw),
    'fact',jsonb_build_object('id',f.id,'subject_type',f.subjekt_type,'subject_id',f.subjekt_id,
      'fact_type',f.faktatype)
  ) ORDER BY p.interpretation_id,p.target_type,p.target_id),'[]'::jsonb) INTO v_links
    FROM private.interpretation_promotion p
    LEFT JOIN public.assertion a ON a.id=p.target_id
    LEFT JOIN public.fact f ON f.id=a.target_id WHERE p.batch_id=p_batch_id;
  v_state_sha:=encode(digest(jsonb_build_object(
    'schema','interpretation-promotion-postverify-v1','batch_id',p_batch_id,'links',v_links
  )::text,'sha256'),'hex');
  RETURN jsonb_build_object(
    'receipt_sha256',v_batch.receipt_sha256,'profile_sha256',v_batch.rule_profile_hash,
    'input_identity',jsonb_build_object('contract','interpretation-promotion-request-v1',
      'preview_hash',v_batch.preview_hash,'request_sha256',(
        SELECT request_sha256 FROM private.interpretation_promotion_authorization WHERE id=v_batch.authorization_id
      )),
    'database_identity',private.interpretation_promotion_database_identity(),
    'operation_id',v_batch.id::text,
    'verified_state',jsonb_build_object('schema','interpretation-promotion-postverify-v1','sha256',v_state_sha)
  );
END $$;

CREATE OR REPLACE FUNCTION red_authorize_interpretation_promotions(
  p_items jsonb,p_preview_hash text,p_nonce uuid,p_expires_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_preview jsonb; v_reason text; v_profile jsonb; v_profile_hash text;
  v_request_sha text; v_database_identity jsonb:=private.interpretation_promotion_database_identity();
  v_existing private.interpretation_promotion_authorization%ROWTYPE; v_nonce_found boolean; v_id uuid;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF p_nonce IS NULL OR p_expires_at<=clock_timestamp() OR coalesce(p_preview_hash,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZATION_INVALID';
  END IF;
  SELECT * INTO v_existing FROM private.interpretation_promotion_authorization
    WHERE actor_id=v_actor AND nonce=p_nonce FOR UPDATE;
  v_nonce_found:=FOUND;
  IF v_nonce_found AND v_existing.status<>'issued' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_NONCE_CONFLICT';
  END IF;
  v_preview:=private.preview_interpretation_promotions(p_items,false);
  IF v_preview->>'preview_hash'<>p_preview_hash THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_PREVIEW_STALE'; END IF;
  SELECT item->>'reason_code' INTO v_reason FROM jsonb_array_elements(v_preview->'items') item
    WHERE coalesce((item->>'eligible')::boolean,false)=false ORDER BY (item->>'interpretation_id')::uuid LIMIT 1;
  IF v_reason IS NOT NULL THEN RAISE EXCEPTION '%',v_reason; END IF;
  v_profile:=private.interpretation_promotion_profile(v_preview);
  PERFORM private.validate_interpretation_promotion_profile(v_profile);
  v_profile_hash:=encode(digest(v_profile::text,'sha256'),'hex');
  v_request_sha:=encode(digest(jsonb_build_object(
    'contract','interpretation-promotion-request-v1','items',private.canonical_interpretation_promotion_items(p_items)
  )::text,'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-evidence-promotion-authorization:'||v_request_sha,0));
  IF v_nonce_found THEN
    IF v_existing.status='issued' AND v_existing.expires_at>clock_timestamp()
       AND v_existing.preview_hash=p_preview_hash AND v_existing.rule_profile_hash=v_profile_hash
       AND v_existing.request_sha256=v_request_sha AND v_existing.database_identity=v_database_identity THEN
      RETURN v_existing.id;
    END IF;
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_NONCE_CONFLICT';
  END IF;
  UPDATE private.interpretation_promotion_authorization SET status='expired'
   WHERE database_identity=v_database_identity AND request_sha256=v_request_sha
     AND status='issued' AND expires_at<=clock_timestamp();
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion_authorization a
      WHERE a.database_identity=v_database_identity AND a.request_sha256=v_request_sha
        AND ((a.status='issued' AND a.expires_at>clock_timestamp()) OR a.status='consumed')) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_SCOPE_ALREADY_AUTHORIZED';
  END IF;
  INSERT INTO private.interpretation_promotion_authorization(
    preview_hash,rule_profile,rule_profile_hash,request_sha256,database_identity,
    actor_id,nonce,expires_at
  ) VALUES (p_preview_hash,v_profile,v_profile_hash,v_request_sha,v_database_identity,
            v_actor,p_nonce,p_expires_at) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_promote_interpretations_batch(
  p_items jsonb,p_preview_hash text,p_authorization_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_actor_name text; v_auth private.interpretation_promotion_authorization%ROWTYPE;
  v_preview jsonb; v_reason text; v_profile jsonb; v_profile_hash text; v_request_sha text;
  v_database_identity jsonb:=private.interpretation_promotion_database_identity(); v_batch_id uuid;
  v_counts jsonb; v_receipt jsonb; v_receipt_sha text; v_state jsonb;
  v_expected_targets jsonb; v_actual_targets jsonb;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF p_authorization_id IS NULL OR coalesce(p_preview_hash,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZATION_INVALID';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text) INTO v_actor_name
    FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_INVALID'; END IF;
  v_request_sha:=encode(digest(jsonb_build_object(
    'contract','interpretation-promotion-request-v1','items',private.canonical_interpretation_promotion_items(p_items)
  )::text,'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-evidence-promotion-writer',0));
  SELECT * INTO v_auth FROM private.interpretation_promotion_authorization WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_auth.actor_id<>v_actor OR v_auth.database_identity<>v_database_identity
     OR v_auth.preview_hash<>p_preview_hash OR v_auth.request_sha256<>v_request_sha THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZATION_INVALID';
  END IF;
  IF v_auth.status='consumed' THEN
    SELECT id INTO v_batch_id FROM private.interpretation_promotion_batch
      WHERE authorization_id=v_auth.id AND status='finalized';
    IF v_batch_id IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_NONCE_CONSUMED'; END IF;
    RETURN (SELECT receipt FROM private.interpretation_promotion_batch WHERE id=v_batch_id);
  END IF;
  IF v_auth.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZATION_EXPIRED'; END IF;
  PERFORM private.validate_interpretation_promotion_profile(v_auth.rule_profile);
  v_preview:=private.preview_interpretation_promotions(p_items,true);
  IF v_preview->>'preview_hash'<>p_preview_hash THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_PREVIEW_STALE'; END IF;
  v_profile:=private.interpretation_promotion_profile(v_preview);
  v_profile_hash:=encode(digest(v_profile::text,'sha256'),'hex');
  IF v_auth.rule_profile_hash<>v_profile_hash OR v_auth.rule_profile<>v_profile THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_PROFILE_STALE';
  END IF;
  SELECT item->>'reason_code' INTO v_reason FROM jsonb_array_elements(v_preview->'items') item
    WHERE coalesce((item->>'eligible')::boolean,false)=false ORDER BY (item->>'interpretation_id')::uuid LIMIT 1;
  IF v_reason IS NOT NULL THEN RAISE EXCEPTION '%',v_reason; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'interpretation_id',item->>'interpretation_id','target_type',item->>'target_type','target_id',item->>'target_id',
      'assertion',jsonb_build_object('id',a.id,'target_type',a.target_type,'target_id',a.target_id,
        'value',a.vaerdi_tekst,'date_raw',a.date_raw),
      'fact',jsonb_build_object('id',f.id,'subject_type',f.subjekt_type,'subject_id',f.subjekt_id,'fact_type',f.faktatype)
    ) ORDER BY item->>'interpretation_id',item->>'target_type',item->>'target_id'),'[]'::jsonb)
    INTO v_expected_targets
    FROM jsonb_array_elements(v_preview->'items') item
    LEFT JOIN public.assertion a ON a.id=(item->>'target_id')::bigint
    LEFT JOIN public.fact f ON f.id=a.target_id;
  INSERT INTO private.interpretation_promotion_batch(
    authorization_id,rule_profile_hash,preview_hash,database_identity,promoted_by,promoted_by_name,requested_count
  ) VALUES (v_auth.id,v_profile_hash,p_preview_hash,v_database_identity,v_actor,v_actor_name,
            jsonb_array_length(v_preview->'items')) RETURNING id INTO v_batch_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'batch_id',v_batch_id,'authorization_id',v_auth.id::text,'preview_hash',p_preview_hash,
      'evidence',jsonb_build_object('promotion_kind','validated_rule','preview_hash',p_preview_hash,'authorization_id',v_auth.id::text),
      'promoted_by',v_actor,'promoted_by_name',v_actor_name,
      'interpretation_id',item->>'interpretation_id','target_type',item->>'target_type','target_id',item->>'target_id',
      'assertion',jsonb_build_object('id',a.id,'target_type',a.target_type,'target_id',a.target_id,
        'value',a.vaerdi_tekst,'date_raw',a.date_raw),
      'fact',jsonb_build_object('id',f.id,'subject_type',f.subjekt_type,'subject_id',f.subjekt_id,'fact_type',f.faktatype)
    ) ORDER BY item->>'interpretation_id',item->>'target_type',item->>'target_id'),'[]'::jsonb)
    INTO v_expected_targets FROM jsonb_array_elements(v_preview->'items') item
    LEFT JOIN public.assertion a ON a.id=(item->>'target_id')::bigint
    LEFT JOIN public.fact f ON f.id=a.target_id;
  INSERT INTO private.interpretation_promotion(
    interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,promoted_by,promoted_by_name
  ) SELECT (item->>'interpretation_id')::uuid,item->>'rule_key',(item->>'rule_version')::integer,
      v_batch_id,item->>'target_type',(item->>'target_id')::bigint,
      jsonb_build_object('promotion_kind','validated_rule','preview_hash',p_preview_hash,
        'authorization_id',v_auth.id::text),v_actor,v_actor_name
    FROM jsonb_array_elements(v_preview->'items') item;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'batch_id',p.batch_id,'authorization_id',p.evidence->>'authorization_id',
      'preview_hash',p.evidence->>'preview_hash','evidence',p.evidence,'promoted_by',p.promoted_by,
      'promoted_by_name',p.promoted_by_name,'interpretation_id',p.interpretation_id::text,'target_type',p.target_type,'target_id',p.target_id::text,
      'assertion',jsonb_build_object('id',a.id,'target_type',a.target_type,'target_id',a.target_id,
        'value',a.vaerdi_tekst,'date_raw',a.date_raw),
      'fact',jsonb_build_object('id',f.id,'subject_type',f.subjekt_type,'subject_id',f.subjekt_id,'fact_type',f.faktatype)
    ) ORDER BY p.interpretation_id,p.target_type,p.target_id),'[]'::jsonb)
    INTO v_actual_targets FROM private.interpretation_promotion p
    LEFT JOIN public.assertion a ON a.id=p.target_id LEFT JOIN public.fact f ON f.id=a.target_id
    WHERE p.batch_id=v_batch_id;
  IF v_actual_targets IS DISTINCT FROM v_expected_targets THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_POSTVERIFY_TARGET_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_preview->'items') item WHERE NOT EXISTS (
      SELECT 1 FROM private.interpretation_promotion p WHERE p.batch_id=v_batch_id
        AND p.interpretation_id=(item->>'interpretation_id')::uuid AND p.target_type=item->>'target_type'
        AND p.target_id=(item->>'target_id')::bigint AND p.rule_key=item->>'rule_key'
        AND p.rule_version=(item->>'rule_version')::integer
    )) OR EXISTS (SELECT 1 FROM private.interpretation_promotion p WHERE p.batch_id=v_batch_id AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_preview->'items') item
       WHERE p.interpretation_id=(item->>'interpretation_id')::uuid AND p.target_type=item->>'target_type'
         AND p.target_id=(item->>'target_id')::bigint AND p.rule_key=item->>'rule_key'
         AND p.rule_version=(item->>'rule_version')::integer
    )) THEN RAISE EXCEPTION 'EVIDENCE_PROMOTION_POSTVERIFY_LINK_DRIFT'; END IF;
  SELECT jsonb_build_object('requested',v.requested_count,'promotions',count(p.id)) INTO v_counts
    FROM private.interpretation_promotion_batch v LEFT JOIN private.interpretation_promotion p ON p.batch_id=v.id
   WHERE v.id=v_batch_id GROUP BY v.requested_count;
  IF (v_counts->>'requested') IS DISTINCT FROM (v_counts->>'promotions') THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_POSTVERIFY_COUNT_DRIFT';
  END IF;
  UPDATE private.interpretation_promotion_authorization SET status='consumed',consumed_at=clock_timestamp()
    WHERE id=v_auth.id AND status='issued';
  v_state:=private.interpretation_promotion_batch_state(v_batch_id);
  v_receipt:=jsonb_build_object(
    'receipt_schema','interpretation-promotion-receipt-v1','profile_sha256',v_profile_hash,
    'mode','historical','terminal_status','finalized',
    'input_identity',v_state->'input_identity','database_identity',v_database_identity,
    'authorization_identity',jsonb_build_object('mode','single_use_database_authorization',
      'authority_id',v_auth.id::text,'actor_id',v_actor::text,'nonce',v_auth.nonce::text),
    'operation_id',v_batch_id::text,'observed_counts',v_counts,'verified_state',v_state->'verified_state'
  );
  v_receipt_sha:=encode(digest(v_receipt::text,'sha256'),'hex');
  UPDATE private.interpretation_promotion_batch SET status='finalized',observed_counts=v_counts,
    receipt=v_receipt,receipt_sha256=v_receipt_sha,finalized_at=clock_timestamp() WHERE id=v_batch_id;
  v_state:=private.interpretation_promotion_batch_state(v_batch_id);
  IF v_state->>'receipt_sha256'<>v_receipt_sha OR v_state->>'profile_sha256'<>v_profile_hash
     OR v_state->'input_identity' IS DISTINCT FROM v_receipt->'input_identity'
     OR v_state->'database_identity' IS DISTINCT FROM v_receipt->'database_identity'
     OR v_state->>'operation_id'<>v_receipt->>'operation_id'
     OR v_state->'verified_state' IS DISTINCT FROM v_receipt->'verified_state' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_POSTVERIFY_RECEIPT_DRIFT';
  END IF;
  RETURN v_receipt;
END $$;

CREATE OR REPLACE FUNCTION private.guard_interpretation_promotion_authorization_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status<>'issued' OR NEW.status NOT IN ('consumed','expired')
     OR (NEW.status='consumed' AND NEW.consumed_at IS NULL)
     OR (NEW.status='expired' AND NEW.consumed_at IS NOT NULL)
     OR (to_jsonb(NEW)-ARRAY['status','consumed_at']) IS DISTINCT FROM
        (to_jsonb(OLD)-ARRAY['status','consumed_at']) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZATION_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private.guard_interpretation_promotion_batch_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.status<>'open' OR NEW.status<>'finalized'
     OR NEW.observed_counts IS NULL OR NEW.receipt IS NULL OR NEW.receipt_sha256 !~ '^[0-9a-f]{64}$'
     OR NEW.finalized_at IS NULL
     OR (to_jsonb(NEW)-ARRAY['status','observed_counts','receipt','receipt_sha256','finalized_at'])
          IS DISTINCT FROM
        (to_jsonb(OLD)-ARRAY['status','observed_counts','receipt','receipt_sha256','finalized_at']) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_BATCH_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_interpretation_promotion_authorization_append_only
  BEFORE UPDATE OR DELETE ON private.interpretation_promotion_authorization
  FOR EACH ROW EXECUTE FUNCTION private.guard_interpretation_promotion_authorization_mutation();
CREATE TRIGGER trg_interpretation_promotion_batch_append_only
  BEFORE UPDATE OR DELETE ON private.interpretation_promotion_batch
  FOR EACH ROW EXECUTE FUNCTION private.guard_interpretation_promotion_batch_mutation();

CREATE OR REPLACE FUNCTION private.guard_interpretation_promotion_insert()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,private AS $$
BEGIN
  IF NEW.batch_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.interpretation_promotion_batch b
    JOIN private.interpretation_promotion_authorization a ON a.id=b.authorization_id
     WHERE b.id=NEW.batch_id AND b.status='open' AND a.status='issued'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_AUTHORIZED_BATCH_REQUIRED';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_interpretation_promotion_authorized_batch
  BEFORE INSERT ON private.interpretation_promotion
  FOR EACH ROW EXECUTE FUNCTION private.guard_interpretation_promotion_insert();

-- Den tidligere brede enkeltrække-RPC opfylder ikke v1-kontrakten og må derfor
-- ikke være en klientvej. Alle nye manuelle og bulk-promotions går gennem batch-RPC'en.
REVOKE EXECUTE ON FUNCTION private.validate_interpretation_promotion_items(jsonb,boolean),
                           private.preview_interpretation_promotions(jsonb,boolean),
                           private.canonical_interpretation_promotion_items(jsonb),
                           private.interpretation_promotion_profile(jsonb),
                           private.validate_interpretation_promotion_profile(jsonb),
                           private.interpretation_promotion_database_identity(),
                           private.interpretation_promotion_batch_state(uuid),
                           private.guard_interpretation_promotion_authorization_mutation(),
                           private.guard_interpretation_promotion_batch_mutation()
                           ,private.guard_interpretation_promotion_insert()
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION red_promote_interpretation(uuid,text,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
DROP FUNCTION IF EXISTS public.red_promote_interpretation(uuid,text,bigint,jsonb);
DROP FUNCTION IF EXISTS public.red_promote_interpretations_batch(jsonb,text);
REVOKE ALL ON FUNCTION red_preview_interpretation_promotions(jsonb),
                       red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz),
                       red_promote_interpretations_batch(jsonb,text,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_preview_interpretation_promotions(jsonb),
                          red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz),
                          red_promote_interpretations_batch(jsonb,text,uuid)
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

-- ---------- GENEREL ENTITETSBESKRIVELSE (Evidensimport Task 8) ----------
-- Redaktionel, versioneret prosa om en kanonisk entitet. Den ordrette kildeprosa
-- bliver i private.source_observation; denne tabel er ikke en fjerde råtekst-kopi.
CREATE TABLE entity_description (
  id            bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  subjekt_type  text NOT NULL,
  subjekt_id    bigint NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('overview','history','caption','blazon_explanation')),
  language_code text NOT NULL DEFAULT 'da' CHECK (btrim(language_code)<>''),
  tekst         text NOT NULL CHECK (btrim(tekst)<>''),
  status        text NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','approved','published','archived')),
  privat        boolean NOT NULL DEFAULT false,
  version       integer NOT NULL DEFAULT 1 CHECK (version>=1),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Kildekoblingen går bevidst fra det private evidenslag til den offentlige,
-- redaktionelle beskrivelse. Dermed eksponerer public.entity_description aldrig
-- private source_record-identifikatorer.
CREATE TABLE private.entity_description_source (
  description_id  bigint NOT NULL REFERENCES public.entity_description(id) ON DELETE CASCADE,
  source_record_id uuid NOT NULL REFERENCES private.source_record(id),
  citation_note   text,
  PRIMARY KEY (description_id,source_record_id)
);

CREATE OR REPLACE FUNCTION validate_entity_description_subject()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
  IF (NEW.subjekt_type='person' AND EXISTS (SELECT 1 FROM public.person WHERE id=NEW.subjekt_id))
     OR (NEW.subjekt_type='slaegt' AND EXISTS (SELECT 1 FROM public.slaegt WHERE id=NEW.subjekt_id))
     OR (NEW.subjekt_type='lineage' AND EXISTS (SELECT 1 FROM public.lineage WHERE id=NEW.subjekt_id))
     OR (NEW.subjekt_type='coat_of_arms' AND EXISTS (SELECT 1 FROM public.coat_of_arms WHERE id=NEW.subjekt_id))
     OR (NEW.subjekt_type='media' AND EXISTS (SELECT 1 FROM public.media WHERE id=NEW.subjekt_id))
     OR (NEW.subjekt_type='estate' AND EXISTS (SELECT 1 FROM public.estate WHERE id=NEW.subjekt_id)) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'ENTITY_DESCRIPTION_SUBJECT_INVALID';
END $$;

CREATE TRIGGER trg_entity_description_subject
  BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON entity_description
  FOR EACH ROW EXECUTE FUNCTION validate_entity_description_subject();

INSERT INTO version_pk_registry (tabel,pk_cols,skip_cols)
VALUES ('entity_description',ARRAY['id'],'{}')
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols,skip_cols=excluded.skip_cols;
DROP TRIGGER IF EXISTS trg_log_entity_description ON entity_description;
CREATE TRIGGER trg_log_entity_description AFTER INSERT OR UPDATE OR DELETE ON entity_description
  FOR EACH ROW EXECUTE FUNCTION log_change();

ALTER TABLE entity_description ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.entity_description_source ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.entity_description_source FROM PUBLIC,anon,authenticated;

-- ===== 2026-08-23: DAA 1939 v50 fase C3 -- atomic apply RPCs (Task 6) =====
-- ============================================================================
-- DAA 1939 v50 fase C3: atomic, hash-bound apply RPCs (Task 6)
-- ============================================================================
-- Generic reimport_case_* surface (see the ledger DDL above): parametrised on
-- source_id + phase, never on edition. The three public entry points are the
-- only client-visible surface; everything privileged lives in private.
--
-- Reuse, not reinvention: private.require_reimport_1939_editor() is the role
-- gate and private.reimport_1939_canonical_json_sha256() is the canonical
-- payload hasher for both families -- both are already generic in behaviour
-- despite their family-scoped names.
--
-- Deterministic lock order -- TEN steps, not eight (apply AND the reversal in
-- Task 7 use exactly this order; the numbering keeps the spec's 1-8 and adds
-- the two steps that were introduced with the code but originally left out of
-- this comment, which is why 0 and 2.5 are numbered the way they are):
--   0. set lock_timeout / statement_timeout, then refuse a foreign change set
--      (before ANY lock wait: lock_timeout is re-read at every acquisition, so
--      its position is what bounds step 1 itself)
--   1. pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))
--   2. actor/profile/role gate
--   2.5 the authorization row itself, FOR UPDATE (and, in the commit-unknown
--      branch, its batch row immediately after -- still inside 2.5)
--   3. pg_advisory_xact_lock(hashtext('samme_som_mutation'))
--   4. every involved person row, ascending id
--   5. source records, ascending uuid
--   6. narratives, ascending id
--   7. existing binding rows, ascending narrative_id
--   8. identity relations, ascending id -- and, in the reversal only, their
--      conclusion rows then their assertion rows, each ascending id, which is
--      the order _delete_relation_evidence already touches them in
-- ============================================================================

-- ---------- private state probes (single source of truth for preview+apply) --

-- Measured source-record state for one (source_id, record_key).
-- match_count is the number of occurrences whose CURRENT (highest-version)
-- anchor decision for this record is 'accepted'. Zero accepted occurrences is
-- fatal rather than reportable: the R preview wrapper's contract requires a
-- 64-hex verbatim_sha256 and a non-empty side on every row, and neither has a
-- truthful value when nothing is anchored. A count > 1 IS reportable (the
-- wrapper fails closed on match_count <> 1), so the deterministic first
-- occurrence supplies the measured values.
CREATE OR REPLACE FUNCTION private.reimport_case_source_record_state(
  p_source_id bigint, p_record_key text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_count integer; v_text text; v_page integer;
BEGIN
  SELECT id INTO v_id FROM private.source_record
   WHERE source_id=p_source_id AND record_key=p_record_key;
  IF v_id IS NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_RECORD_MISSING'; END IF;
  WITH current_anchor AS (
    SELECT DISTINCT ON (ae.occurrence_id) ae.occurrence_id, ae.decision_status
      FROM private.source_record_anchor_event ae
     WHERE ae.source_record_id=v_id
     ORDER BY ae.occurrence_id, ae.version DESC
  )
  SELECT count(*) INTO v_count FROM current_anchor WHERE decision_status='accepted';
  IF v_count=0 THEN RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_RECORD_UNANCHORED'; END IF;
  WITH current_anchor AS (
    SELECT DISTINCT ON (ae.occurrence_id) ae.occurrence_id, ae.decision_status
      FROM private.source_record_anchor_event ae
     WHERE ae.source_record_id=v_id
     ORDER BY ae.occurrence_id, ae.version DESC
  )
  SELECT o.verbatim_text, o.page_from INTO v_text, v_page
    FROM current_anchor a
    JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
   WHERE a.decision_status='accepted'
   ORDER BY o.page_from, o.char_from, o.id
   LIMIT 1;
  RETURN jsonb_build_object(
    'source_record_id', v_id,
    'match_count', v_count,
    'verbatim_sha256', encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'side', v_page::text);
END $$;

-- Measured narrative state for one (source_id, person). Exactly one logical row
-- is allowed (fund M2): more than one is terminal drift, because red_upsert_narrativ's
-- ORDER BY id LIMIT 1 would silently pick a row the manifest never measured.
CREATE OR REPLACE FUNCTION private.reimport_case_narrative_state(
  p_source_id bigint, p_person_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_count integer; v_id bigint; v_privat boolean; v_tekst text; v_side text;
BEGIN
  SELECT count(*) INTO v_count FROM public.narrative
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND source_id IS NOT DISTINCT FROM p_source_id;
  IF v_count>1 THEN RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_AMBIGUOUS'; END IF;
  IF v_count=0 THEN
    RETURN jsonb_build_object('narrative_id',NULL,'privat',false,'old_text',NULL,
                              'old_sha256',NULL,'side',NULL);
  END IF;
  SELECT id, coalesce(privat,false), tekst, side INTO v_id, v_privat, v_tekst, v_side
    FROM public.narrative
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND source_id IS NOT DISTINCT FROM p_source_id;
  RETURN jsonb_build_object(
    'narrative_id', v_id, 'privat', v_privat, 'old_text', v_tekst,
    'old_sha256', encode(sha256(convert_to(v_tekst,'UTF8')),'hex'),
    'side', v_side);
END $$;

-- Measured publication-binding state for one source record.
-- The fund-B4 partial unique index guarantees at most one active (draft|published)
-- binding per source record, so the ORDER BY below is a determinism belt, not a choice.
CREATE OR REPLACE FUNCTION private.reimport_case_binding_state(
  p_source_record_id uuid, p_target_narrative_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_row private.narrative_record_publication%ROWTYPE; v_person bigint; v_status text;
BEGIN
  SELECT * INTO v_row FROM private.narrative_record_publication
   WHERE source_record_id=p_source_record_id AND status IN ('draft','published')
   ORDER BY narrative_id LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', CASE WHEN EXISTS(SELECT 1 FROM private.narrative_record_publication
                                  WHERE source_record_id=p_source_record_id)
                     THEN 'withdrawn' ELSE 'absent' END,
      'binding_person_id', NULL);
  END IF;
  SELECT n.subjekt_id INTO v_person FROM public.narrative n WHERE n.id=v_row.narrative_id;
  IF v_row.status='published' THEN v_status:='published';
  ELSIF p_target_narrative_id IS NOT NULL AND v_row.narrative_id=p_target_narrative_id
    THEN v_status:='draft_same_record';
  ELSE v_status:='draft_other_record';
  END IF;
  RETURN jsonb_build_object('status',v_status,'binding_person_id',v_person);
END $$;

-- ---------- selection / element structural validators ----------------------

-- Validates the p_selection argument of red_preview_reimport_cases. Structure
-- only: no cardinality is hard-coded here (the phase's own five-case shape is
-- enforced by the offline finalizer and by the authorization's expected_counts),
-- so a later phase can reuse the same contract.
CREATE OR REPLACE FUNCTION private.validate_reimport_case_selection(p_selection jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path=pg_catalog AS $$
DECLARE v_case jsonb; v_record jsonb; v_case_ids text[]:='{}'; v_rids text[]:='{}'; v_keys text[]:='{}';
BEGIN
  IF jsonb_typeof(p_selection)<>'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_selection))<>2
     OR p_selection->>'schema_version'<>'1939-v50-c3-apply-selection-v1'
     OR jsonb_typeof(p_selection->'cases')<>'array'
     OR jsonb_array_length(p_selection->'cases')<1 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
  END IF;
  FOR v_case IN SELECT * FROM jsonb_array_elements(p_selection->'cases') LOOP
    IF jsonb_typeof(v_case)<>'object'
       OR (SELECT count(*) FROM jsonb_object_keys(v_case))<>3
       OR coalesce(btrim(v_case->>'case_id'),'')=''
       OR jsonb_typeof(v_case->'identity_pair')<>'object'
       OR (SELECT count(*) FROM jsonb_object_keys(v_case->'identity_pair'))<>1
       OR jsonb_typeof(v_case->'identity_pair'->'person_ids')<>'array'
       OR jsonb_array_length(v_case->'identity_pair'->'person_ids')<>2
       OR jsonb_typeof(v_case->'identity_pair'->'person_ids'->0)<>'number'
       OR jsonb_typeof(v_case->'identity_pair'->'person_ids'->1)<>'number'
       OR (v_case->'identity_pair'->'person_ids'->>0)::bigint
          >= (v_case->'identity_pair'->'person_ids'->>1)::bigint
       OR jsonb_typeof(v_case->'records')<>'array'
       OR jsonb_array_length(v_case->'records')<1 THEN
      RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
    END IF;
    IF v_case->>'case_id' = ANY(v_case_ids) THEN
      RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
    END IF;
    v_case_ids := v_case_ids || (v_case->>'case_id');
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_case->'records') LOOP
      IF jsonb_typeof(v_record)<>'object'
         OR coalesce(btrim(v_record->>'rid'),'')=''
         OR coalesce(btrim(v_record->>'record_key'),'')='' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
      END IF;
      IF v_record->>'action'='assign' THEN
        IF (SELECT count(*) FROM jsonb_object_keys(v_record))<>6
           OR jsonb_typeof(v_record->'target_person_id')<>'number'
           OR (v_record->>'raw_sha256') !~ '^[0-9a-f]{64}$'
           OR (v_record->>'normalized_sha256') !~ '^[0-9a-f]{64}$' THEN
          RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
        END IF;
      ELSIF v_record->>'action'='no_publication' THEN
        IF (SELECT count(*) FROM jsonb_object_keys(v_record))<>3 THEN
          RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
        END IF;
      ELSE
        RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
      END IF;
      IF v_record->>'rid' = ANY(v_rids) OR v_record->>'record_key' = ANY(v_keys) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_SELECTION_INVALID';
      END IF;
      v_rids := v_rids || (v_record->>'rid');
      v_keys := v_keys || (v_record->>'record_key');
    END LOOP;
  END LOOP;
END $$;

-- Validates the authorized element map: exactly the manifest's stable element
-- IDs ("case:<case_id>" for an identity decision, "case:<case_id>:rid:<rid>"
-- for a record decision), each with a fully typed payload. Purely structural
-- and self-consistent (no database lookups), so authorize and apply can run it
-- over the same bytes and never disagree.
CREATE OR REPLACE FUNCTION private.validate_reimport_case_elements(
  p_elements jsonb, p_counts jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path=pg_catalog AS $$
DECLARE
  v_key text; v_payload jsonb; v_before jsonb;
  v_identity integer:=0; v_assign integer:=0; v_no_pub integer:=0;
  v_case_ids text[]:='{}';
BEGIN
  IF jsonb_typeof(p_elements)<>'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_elements))<1 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
  END IF;
  FOR v_key, v_payload IN SELECT e.key, e.value FROM jsonb_each(p_elements) e ORDER BY e.key LOOP
    IF jsonb_typeof(v_payload)<>'object' OR coalesce(btrim(v_payload->>'case_id'),'')='' THEN
      RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
    END IF;
    v_before := v_payload->'before_state';
    IF v_payload->>'action'='different' THEN
      IF v_key <> 'case:'||(v_payload->>'case_id')
         OR (SELECT count(*) FROM jsonb_object_keys(v_payload))<>4
         OR jsonb_typeof(v_payload->'person_ids')<>'array'
         OR jsonb_array_length(v_payload->'person_ids')<>2
         OR jsonb_typeof(v_payload->'person_ids'->0)<>'number'
         OR jsonb_typeof(v_payload->'person_ids'->1)<>'number'
         OR (v_payload->'person_ids'->>0)::bigint >= (v_payload->'person_ids'->>1)::bigint
         OR jsonb_typeof(v_before)<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before))<>2
         OR jsonb_typeof(v_before->'component_overlap')<>'boolean'
         OR jsonb_typeof(v_before->'existing_rejection')<>'boolean'
         OR (v_before->>'component_overlap')::boolean THEN
        RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
      END IF;
      IF v_payload->>'case_id' = ANY(v_case_ids) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
      END IF;
      v_case_ids := v_case_ids || (v_payload->>'case_id');
      v_identity := v_identity + 1;
    ELSIF v_payload->>'action'='assign' THEN
      IF v_key <> 'case:'||(v_payload->>'case_id')||':rid:'||coalesce(v_payload->>'rid','')
         OR (SELECT count(*) FROM jsonb_object_keys(v_payload))<>13
         OR coalesce(btrim(v_payload->>'rid'),'')=''
         OR coalesce(btrim(v_payload->>'record_key'),'')=''
         OR jsonb_typeof(v_payload->'target_person_id')<>'number'
         OR NOT (jsonb_typeof(v_payload->'target_narrative_id') IN ('number','null'))
         OR jsonb_typeof(v_payload->'normalized_text')<>'string'
         OR (v_payload->>'normalized_sha256') !~ '^[0-9a-f]{64}$'
         OR encode(sha256(convert_to(v_payload->>'normalized_text','UTF8')),'hex')
            <> (v_payload->>'normalized_sha256')
         OR coalesce(btrim(v_payload->>'record_label'),'')=''
         OR coalesce(btrim(v_payload->>'citation_label'),'')=''
         OR coalesce(btrim(v_payload->>'side'),'')=''
         OR jsonb_typeof(v_payload->'privat')<>'boolean'
         OR (v_payload->>'privat')::boolean
         OR jsonb_typeof(v_before)<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before))<>3 THEN
        RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
      END IF;
      IF jsonb_typeof(v_before->'source_record')<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before->'source_record'))<>3
         OR jsonb_typeof(v_before->'source_record'->'match_count')<>'number'
         OR (v_before->'source_record'->>'match_count')::integer<>1
         OR (v_before->'source_record'->>'verbatim_sha256') !~ '^[0-9a-f]{64}$'
         OR (v_before->'source_record'->>'side') <> (v_payload->>'side')
         OR jsonb_typeof(v_before->'target_narrative')<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before->'target_narrative'))<>4
         OR (v_before->'target_narrative'->'person_id') IS DISTINCT FROM (v_payload->'target_person_id')
         OR (v_before->'target_narrative'->'narrative_id') IS DISTINCT FROM (v_payload->'target_narrative_id')
         OR jsonb_typeof(v_before->'target_narrative'->'privat')<>'boolean'
         OR (v_before->'target_narrative'->>'privat')::boolean
         OR NOT (
              (jsonb_typeof(v_payload->'target_narrative_id')='null'
                AND jsonb_typeof(v_before->'target_narrative'->'old_sha256')='null')
              OR (jsonb_typeof(v_payload->'target_narrative_id')='number'
                AND (v_before->'target_narrative'->>'old_sha256') ~ '^[0-9a-f]{64}$'))
         OR jsonb_typeof(v_before->'binding')<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before->'binding'))<>2
         OR NOT (v_before->'binding'->>'status' IN ('absent','draft_same_record'))
         OR NOT (
              (v_before->'binding'->>'status'='absent'
                AND jsonb_typeof(v_before->'binding'->'binding_person_id')='null')
              OR (v_before->'binding'->>'status'='draft_same_record'
                AND (v_before->'binding'->'binding_person_id')
                    IS NOT DISTINCT FROM (v_payload->'target_person_id'))) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
      END IF;
      v_assign := v_assign + 1;
    ELSIF v_payload->>'action'='no_publication' THEN
      -- Controller ruling 1: the no_publication threshold is exactly 'absent',
      -- matching the already-shipped offline finalizer, so a manifest that
      -- passed that gate is guaranteed to pass this one.
      IF v_key <> 'case:'||(v_payload->>'case_id')||':rid:'||coalesce(v_payload->>'rid','')
         OR (SELECT count(*) FROM jsonb_object_keys(v_payload))<>5
         OR coalesce(btrim(v_payload->>'rid'),'')=''
         OR coalesce(btrim(v_payload->>'record_key'),'')=''
         OR jsonb_typeof(v_before)<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before))<>2
         OR jsonb_typeof(v_before->'source_record')<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before->'source_record'))<>3
         OR (v_before->'source_record'->>'verbatim_sha256') !~ '^[0-9a-f]{64}$'
         OR coalesce(btrim(v_before->'source_record'->>'side'),'')=''
         OR jsonb_typeof(v_before->'binding')<>'object'
         OR (SELECT count(*) FROM jsonb_object_keys(v_before->'binding'))<>2
         OR v_before->'binding'->>'status'<>'absent'
         OR jsonb_typeof(v_before->'binding'->'binding_person_id')<>'null' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
      END IF;
      v_no_pub := v_no_pub + 1;
    ELSE
      RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
    END IF;
  END LOOP;

  -- Every record element must belong to a case that also carries its identity
  -- element: a record decision without its case's identity decision would be a
  -- half-applied case, which the spec forbids ("apply-enhed = hele sagen").
  IF EXISTS (
    SELECT 1 FROM jsonb_each(p_elements) e
     WHERE e.value->>'action' IN ('assign','no_publication')
       AND NOT (p_elements ? ('case:'||(e.value->>'case_id')))
  ) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_ELEMENTS_INVALID';
  END IF;

  IF (p_counts->>'identity_events')::integer IS DISTINCT FROM v_identity
     OR (p_counts->>'assign_events')::integer IS DISTINCT FROM v_assign
     OR (p_counts->>'no_publication_events')::integer IS DISTINCT FROM v_no_pub THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_MISMATCH';
  END IF;
END $$;

-- Validates the expected-counts contract. approvals_* are the gateway's
-- attestation of the human text approval (the database only ever sees the
-- approval file's SHA-256, never its contents) -- they are hash-bound here so a
-- later reconciliation can prove WHICH attestation authorised the batch, not so
-- the database can re-derive it.
CREATE OR REPLACE FUNCTION private.validate_reimport_case_counts(p_counts jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path=pg_catalog AS $$
DECLARE v_key text;
BEGIN
  IF jsonb_typeof(p_counts)<>'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_counts))<>7 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_INVALID';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['cases','identity_events','assign_events',
                               'no_publication_events','events',
                               'approvals_approved','approvals_unresolved'] LOOP
    IF jsonb_typeof(p_counts->v_key) IS DISTINCT FROM 'number'
       OR (p_counts->>v_key) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_INVALID';
    END IF;
  END LOOP;
  IF (p_counts->>'cases')::integer<1
     OR (p_counts->>'cases')::integer<>(p_counts->>'identity_events')::integer
     OR (p_counts->>'events')::integer<>(p_counts->>'identity_events')::integer
                                       +(p_counts->>'assign_events')::integer
                                       +(p_counts->>'no_publication_events')::integer
     OR (p_counts->>'approvals_unresolved')::integer<>0
     OR (p_counts->>'approvals_approved')::integer<>(p_counts->>'assign_events')::integer THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_INVALID';
  END IF;
END $$;

-- ---------- public: read-only preview ---------------------------------------

-- Fund H1: this RPC is the ONLY state oracle for the phase. The R exporter
-- validates and byte-publishes this answer; it never re-derives domain state
-- with SQL of its own, so no second implementation can diverge.
-- STABLE and mutation-free by construction.
CREATE OR REPLACE FUNCTION public.red_preview_reimport_cases(
  p_source_id bigint, p_phase text, p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_identity_pairs jsonb; v_source_records jsonb; v_target_narratives jsonb;
  v_bindings jsonb; v_source_anchors jsonb; v_identity_components jsonb;
  v_missing bigint;
BEGIN
  PERFORM private.require_reimport_1939_editor();
  IF p_phase<>'c3' THEN RAISE EXCEPTION 'REIMPORT_CASE_PHASE_UNSUPPORTED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.source WHERE id=p_source_id) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_MISSING';
  END IF;
  PERFORM private.validate_reimport_case_selection(p_selection);

  -- Every referenced person must exist before any identity-component probing.
  SELECT min(pid) INTO v_missing FROM (
    SELECT (c->'identity_pair'->'person_ids'->>0)::bigint AS pid
      FROM jsonb_array_elements(p_selection->'cases') c
    UNION
    SELECT (c->'identity_pair'->'person_ids'->>1)::bigint
      FROM jsonb_array_elements(p_selection->'cases') c
    UNION
    SELECT (r->>'target_person_id')::bigint
      FROM jsonb_array_elements(p_selection->'cases') c,
           jsonb_array_elements(c->'records') r
     WHERE r->>'action'='assign'
  ) q WHERE NOT EXISTS(SELECT 1 FROM public.person p WHERE p.id=q.pid);
  IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_PERSON_MISSING'; END IF;

  SELECT jsonb_agg(x.item ORDER BY x.case_id) INTO v_identity_pairs FROM (
    SELECT c->>'case_id' AS case_id, jsonb_build_object(
      'case_id', c->>'case_id',
      'person_ids', c->'identity_pair'->'person_ids',
      'component_overlap', EXISTS(
        SELECT 1 FROM public._samme_som_gruppe((c->'identity_pair'->'person_ids'->>0)::bigint) a
        JOIN public._samme_som_gruppe((c->'identity_pair'->'person_ids'->>1)::bigint) b ON b.pid=a.pid),
      'existing_rejection', EXISTS(
        SELECT 1 FROM public.relation r
         WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
           AND r.subjekt_id=(c->'identity_pair'->'person_ids'->>0)::bigint
           AND r.objekt_id=(c->'identity_pair'->'person_ids'->>1)::bigint)
    ) AS item
    FROM jsonb_array_elements(p_selection->'cases') c
  ) x;

  SELECT jsonb_agg(x.item ORDER BY x.rid) INTO v_source_records FROM (
    SELECT r->>'rid' AS rid, jsonb_build_object(
      'rid', r->>'rid', 'record_key', r->>'record_key',
      'match_count', (s.state->>'match_count')::integer,
      'verbatim_sha256', s.state->>'verbatim_sha256',
      'side', s.state->>'side') AS item
    FROM jsonb_array_elements(p_selection->'cases') c,
         jsonb_array_elements(c->'records') r,
         LATERAL (SELECT private.reimport_case_source_record_state(p_source_id, r->>'record_key') AS state) s
  ) x;

  SELECT jsonb_agg(x.item ORDER BY x.rid) INTO v_target_narratives FROM (
    SELECT r->>'rid' AS rid, jsonb_build_object(
      'rid', r->>'rid',
      'person_id', (r->>'target_person_id')::bigint,
      'narrative_id', n.state->'narrative_id',
      'privat', n.state->'privat',
      'old_text', n.state->'old_text',
      'old_sha256', n.state->'old_sha256') AS item
    FROM jsonb_array_elements(p_selection->'cases') c,
         jsonb_array_elements(c->'records') r,
         LATERAL (SELECT private.reimport_case_narrative_state(
                    p_source_id, (r->>'target_person_id')::bigint) AS state) n
    WHERE r->>'action'='assign'
  ) x;

  SELECT jsonb_agg(x.item ORDER BY x.record_key) INTO v_bindings FROM (
    SELECT r->>'record_key' AS record_key, jsonb_build_object(
      'record_key', r->>'record_key',
      'status', b.state->>'status',
      'binding_person_id', b.state->'binding_person_id') AS item
    FROM jsonb_array_elements(p_selection->'cases') c,
         jsonb_array_elements(c->'records') r,
         LATERAL (SELECT private.reimport_case_source_record_state(p_source_id, r->>'record_key') AS state) s,
         LATERAL (SELECT CASE WHEN r->>'action'='assign'
                    THEN (private.reimport_case_narrative_state(
                            p_source_id,(r->>'target_person_id')::bigint)->>'narrative_id')::bigint
                    END AS target_narrative_id) t,
         LATERAL (SELECT private.reimport_case_binding_state(
                    (s.state->>'source_record_id')::uuid, t.target_narrative_id) AS state) b
  ) x;

  -- Informational, forwarded to the human review surface and hash-bound through
  -- the preview's canonical bytes. Fund H2's live-guard fields are measured here
  -- so text drift and person-flag drift both invalidate the manifest; the
  -- authoritative live guard runs in red_apply_reimport_cases under row locks.
  SELECT jsonb_agg(x.item ORDER BY x.rid) INTO v_source_anchors FROM (
    SELECT r->>'rid' AS rid, jsonb_build_object(
      'rid', r->>'rid', 'record_key', r->>'record_key',
      'source_record_id', s.state->>'source_record_id',
      'match_count', (s.state->>'match_count')::integer,
      'side', s.state->>'side') AS item
    FROM jsonb_array_elements(p_selection->'cases') c,
         jsonb_array_elements(c->'records') r,
         LATERAL (SELECT private.reimport_case_source_record_state(p_source_id, r->>'record_key') AS state) s
  ) x;

  SELECT jsonb_agg(x.item ORDER BY x.case_id) INTO v_identity_components FROM (
    SELECT c->>'case_id' AS case_id, jsonb_build_object(
      'case_id', c->>'case_id',
      'persons', (
        SELECT jsonb_agg(jsonb_build_object(
                 'person_id', p.id,
                 'levende', coalesce(p.levende,false),
                 'privat', coalesce(p.privat,false),
                 'staged', coalesce(p.staged,false),
                 'component_size', (SELECT count(*) FROM public._samme_som_gruppe(p.id))
               ) ORDER BY p.id)
        FROM public.person p
        WHERE p.id IN ((c->'identity_pair'->'person_ids'->>0)::bigint,
                       (c->'identity_pair'->'person_ids'->>1)::bigint))
    ) AS item
    FROM jsonb_array_elements(p_selection->'cases') c
  ) x;

  RETURN jsonb_build_object(
    'database_name', current_database(),
    'system_identifier', (pg_control_system()).system_identifier::text,
    'identity_pairs', coalesce(v_identity_pairs,'[]'::jsonb),
    'source_records', coalesce(v_source_records,'[]'::jsonb),
    'target_narratives', coalesce(v_target_narratives,'[]'::jsonb),
    'bindings', coalesce(v_bindings,'[]'::jsonb),
    'source_anchors', coalesce(v_source_anchors,'[]'::jsonb),
    'identity_components', coalesce(v_identity_components,'[]'::jsonb));
END $$;

-- ---------- public: expiring authorization ----------------------------------

-- Two-step principal split, mirroring the existing 1939 writer: this function is
-- granted to service_role only; red_apply_reimport_cases is granted to
-- authenticated only. Both still require the SAME redaktion principal through
-- private.require_reimport_1939_editor() -- role membership is the gateway, the
-- JWT subject is the actor.
CREATE OR REPLACE FUNCTION public.red_authorize_reimport_cases(
  p_source_id bigint, p_phase text, p_operation text,
  p_manifest_sha256 text, p_preview_sha256 text, p_approval_sha256 text,
  p_decisions_sha256 text, p_state_sha256 text, p_text_bundle_sha256 text,
  p_database_name text, p_system_identifier text,
  p_expected_counts jsonb, p_authorized_elements jsonb,
  p_nonce uuid, p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_id uuid; v_actor uuid;
        v_existing private.reimport_case_authorization%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  IF p_phase<>'c3' THEN RAISE EXCEPTION 'REIMPORT_CASE_PHASE_UNSUPPORTED'; END IF;
  IF p_operation NOT IN ('apply','reversal')
     OR p_manifest_sha256 !~ '^[0-9a-f]{64}$' OR p_preview_sha256 !~ '^[0-9a-f]{64}$'
     OR p_approval_sha256 !~ '^[0-9a-f]{64}$' OR p_decisions_sha256 !~ '^[0-9a-f]{64}$'
     OR p_state_sha256 !~ '^[0-9a-f]{64}$' OR p_text_bundle_sha256 !~ '^[0-9a-f]{64}$'
     OR p_nonce IS NULL OR p_expires_at IS NULL OR p_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  -- Fund B1: database name and system identifier are two separate, separately
  -- comparable fields, so a rehearsal-bound artefact fails closed against
  -- production and vice versa.
  IF p_database_name IS DISTINCT FROM current_database()
     OR p_system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.source WHERE id=p_source_id) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_MISSING';
  END IF;
  PERFORM private.validate_reimport_case_counts(p_expected_counts);
  PERFORM private.validate_reimport_case_elements(p_authorized_elements,p_expected_counts);
  IF (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements))
     <> (p_expected_counts->>'events')::integer THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_MISMATCH';
  END IF;

  -- Nonce is the commit-unknown handle: the exact same request returns the exact
  -- same authorization id; anything else under the same nonce is terminal.
  SELECT * INTO v_existing FROM private.reimport_case_authorization WHERE nonce=p_nonce;
  IF FOUND THEN
    IF v_existing.source_id=p_source_id AND v_existing.phase=p_phase
       AND v_existing.operation=p_operation
       AND v_existing.manifest_sha256=p_manifest_sha256
       AND v_existing.preview_sha256=p_preview_sha256
       AND v_existing.approval_sha256=p_approval_sha256
       AND v_existing.decisions_sha256=p_decisions_sha256
       AND v_existing.state_sha256=p_state_sha256
       AND v_existing.text_bundle_sha256=p_text_bundle_sha256
       AND v_existing.database_name=p_database_name
       AND v_existing.system_identifier=p_system_identifier
       AND v_existing.expected_counts=p_expected_counts
       AND v_existing.authorized_elements=p_authorized_elements
       AND v_existing.principal_id=v_actor THEN
      RETURN v_existing.id;
    END IF;
    RAISE EXCEPTION 'REIMPORT_CASE_NONCE_CONFLICT';
  END IF;

  -- Fund B6: an already finalized batch for the same artefact chain pins the
  -- element map; a second authorization may not silently change it.
  IF EXISTS(
    SELECT 1 FROM private.reimport_case_batch b
    JOIN private.reimport_case_authorization a ON a.id=b.authorization_id
    WHERE b.source_id=p_source_id AND b.phase=p_phase AND b.operation=p_operation
      AND b.manifest_sha256=p_manifest_sha256 AND b.preview_sha256=p_preview_sha256
      AND b.principal_id=v_actor AND b.status='finalized'
      AND (a.authorized_elements IS DISTINCT FROM p_authorized_elements
           OR a.expected_counts IS DISTINCT FROM p_expected_counts)
  ) THEN RAISE EXCEPTION 'REIMPORT_CASE_MANIFEST_ELEMENT_DRIFT'; END IF;

  INSERT INTO private.reimport_case_authorization(
    source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
    expected_counts,authorized_elements,principal_id,nonce,expires_at)
  VALUES (p_source_id,p_phase,p_operation,p_manifest_sha256,p_preview_sha256,p_approval_sha256,
    p_decisions_sha256,p_state_sha256,p_text_bundle_sha256,p_database_name,p_system_identifier,
    p_expected_counts,p_authorized_elements,v_actor,p_nonce,p_expires_at)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---------- private: batch receipt ------------------------------------------

-- Only IDs, counts, hashes and status. No narrative prose ever leaves here.
CREATE OR REPLACE FUNCTION private.reimport_case_receipt(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_batch private.reimport_case_batch%ROWTYPE; v_elements jsonb;
BEGIN
  SELECT * INTO v_batch FROM private.reimport_case_batch WHERE id=p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REIMPORT_CASE_BATCH_INVALID'; END IF;
  SELECT jsonb_agg(jsonb_build_object(
           'element_id', e.element_id, 'action', e.action,
           'payload_schema_version', e.payload_schema_version,
           'result', e.payload->'result',
           'before_sha256', e.before_sha256, 'after_sha256', e.after_sha256)
         ORDER BY e.element_id)
    INTO v_elements
    FROM private.reimport_case_event e WHERE e.batch_id=p_batch_id;
  RETURN jsonb_build_object(
    'schema_version','c3-apply-receipt-v1',
    'batch_id', v_batch.id, 'authorization_id', v_batch.authorization_id,
    'source_id', v_batch.source_id, 'phase', v_batch.phase, 'operation', v_batch.operation,
    'status', v_batch.status, 'change_set_id', v_batch.change_set_id,
    'manifest_sha256', v_batch.manifest_sha256, 'preview_sha256', v_batch.preview_sha256,
    'expected_counts', v_batch.expected_counts, 'observed_counts', v_batch.observed_counts,
    'elements', coalesce(v_elements,'[]'::jsonb));
END $$;

-- ---------- private: exact-ID narrative writer (fund M2) --------------------

-- red_upsert_narrativ selects on (subjekt_type,subjekt_id,source_id) with
-- ORDER BY id LIMIT 1 and never receives the manifest's narrative id, so a
-- duplicate logical row would send the write to the wrong row (issue #152).
-- C3 writes against the LOCKED, MEASURED id instead and asserts both
-- (a) exactly one logical row exists and (b) the written id is the manifest's.
CREATE OR REPLACE FUNCTION private.write_reimport_case_narrative(
  p_narrative_id bigint, p_person_id bigint, p_source_id bigint,
  p_tekst text, p_privat boolean, p_side text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_count integer; v_id bigint;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  SELECT count(*) INTO v_count FROM public.narrative
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND source_id IS NOT DISTINCT FROM p_source_id;
  IF p_narrative_id IS NULL THEN
    IF v_count<>0 THEN RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_DRIFT'; END IF;
    v_id := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
    INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
      VALUES (v_id,'person',p_person_id,p_source_id,p_tekst,p_side,p_privat);
    RETURN v_id;
  END IF;
  IF v_count<>1 THEN RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_AMBIGUOUS'; END IF;
  UPDATE public.narrative
     SET tekst=p_tekst, privat=p_privat, side=p_side
   WHERE id=p_narrative_id AND subjekt_type='person' AND subjekt_id=p_person_id
     AND source_id IS NOT DISTINCT FROM p_source_id
   RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_DRIFT'; END IF;
  RETURN v_id;
END $$;

-- ---------- public: one-call atomic apply -----------------------------------

CREATE OR REPLACE FUNCTION public.red_apply_reimport_cases(
  p_authorization_id uuid, p_manifest_sha256 text, p_approval_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid; v_auth private.reimport_case_authorization%ROWTYPE;
  v_batch private.reimport_case_batch%ROWTYPE; v_batch_id uuid;
  v_elements jsonb; v_key text; v_payload jsonb; v_before jsonb;
  v_person_ids bigint[]; v_record_ids uuid[]; v_narrative_ids bigint[];
  v_written_narratives bigint[]:='{}';
  v_change_set bigint; v_state jsonb; v_binding jsonb;
  v_record_id uuid; v_narrative_id bigint; v_relation_id bigint;
  v_outcome text; v_binding_id uuid; v_binding_row private.narrative_record_publication%ROWTYPE;
  v_identity integer:=0; v_assign integer:=0; v_no_pub integer:=0; v_events integer;
  v_result jsonb; v_after jsonb; v_bad bigint;
BEGIN
  -- ===== lock order step 0: unbounded cutover gate, then version =============
  -- No function-local lock_timeout may cap this first wait: an old call queued
  -- behind a committed cutover must wake and return the exact version error.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;

  -- ===== lock order step 0.5: timeouts for subsequent family/domain locks =====
  -- lock_timeout is re-read at every lock acquisition, so setting it here keeps
  -- the existing 5s bound on the production-writer and domain locks without
  -- changing the cutover gate's required wake-and-recheck contract.
  -- statement_timeout, by contrast, is bound by PostgreSQL at statement start,
  -- and this function body IS the running statement, so no in-function
  -- assignment can ever bound this call; it only affects later statements in
  -- the same transaction. A gateway (Task 8) must therefore issue its own
  -- SET LOCAL statement_timeout on its connection before calling apply.
  PERFORM set_config('lock_timeout','5s',true);
  PERFORM set_config('statement_timeout','120s',true);
  -- The shared cutover gate above is the first transaction lock. Only after
  -- its version recheck may this guard or an existing C3 lock run.
  -- The batch must own its change set. begin_change_set RETURNS an already
  -- active app.change_set_id instead of opening a new one, so a caller that
  -- left a foreign change set open would silently enrol every write below into
  -- it -- and Task 7's reversal, which feeds reimport_case_batch.change_set_id
  -- to red_fortryd_change_set, would then undo more than this batch. Fail
  -- closed: apply must be the first and only statement in its transaction.
  IF btrim(coalesce(current_setting('app.change_set_id',true),'')) <> '' THEN
    RAISE EXCEPTION 'REIMPORT_CASE_FOREIGN_CHANGE_SET';
  END IF;

  -- ===== lock order step 1: global production-writer lock ====================
  -- What this lock actually protects, stated precisely: it serialises C3
  -- applies (and Task 7's reversals, which must take the same key) against EACH
  -- OTHER. It does NOT serialise them against the existing 1939 writer family,
  -- which takes hashtextextended('daa-1939-v50-name-completion',0) -- a
  -- different key. Only Task 9's loader/post-load integration (its Step 0) can
  -- bring the two families under one key; until then this lock must not be read
  -- as protection against that family.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0));
  -- ===== lock order step 2: actor / profile / role gate ======================
  v_actor := private.require_reimport_1939_editor();

  -- ===== lock order step 2.5: the authorization row itself ===================
  -- Part of the deterministic order, not an aside: the authorization row is
  -- locked between the role gate and the samme_som advisory lock, so two
  -- concurrent applies of the same authorization serialise here. Task 7 must
  -- take it in this same position (its sibling reimport_case_batch lock in the
  -- commit-unknown branch below is taken immediately after, still inside 2.5).
  SELECT * INTO v_auth FROM private.reimport_case_authorization
   WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_auth.phase<>'c3' OR v_auth.operation<>'apply'
     OR v_auth.principal_id<>v_actor
     OR v_auth.manifest_sha256 IS DISTINCT FROM p_manifest_sha256
     OR v_auth.approval_sha256 IS DISTINCT FROM p_approval_sha256 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  IF v_auth.database_name IS DISTINCT FROM current_database()
     OR v_auth.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH';
  END IF;

  -- Commit-unknown replay: an already consumed authorization with a finalized
  -- batch returns that exact receipt BEFORE any domain state is re-derived.
  -- Validating first would re-measure state that has legitimately moved on
  -- since the successful apply and turn a success into terminal drift.
  IF v_auth.status='consumed' THEN
    SELECT * INTO v_batch FROM private.reimport_case_batch
     WHERE authorization_id=v_auth.id FOR UPDATE;
    IF FOUND AND v_batch.status='finalized' THEN
      RETURN private.reimport_case_receipt(v_batch.id);
    END IF;
    -- A deliberately reversed batch is NOT anomalous state, and must not hide
    -- inside the token the spec routes to manual audit. Task 7 flips a reversed
    -- batch's status away from 'finalized', so a late retry of the original
    -- apply authorization lands here; it gets its own token so a gateway can
    -- tell "this work was withdrawn on purpose" from "this authorization is in
    -- a partial or unexplained state".
    IF FOUND AND v_batch.status='reversed' THEN
      RAISE EXCEPTION 'REIMPORT_CASE_BATCH_REVERSED';
    END IF;
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_ALREADY_CONSUMED';
  END IF;
  IF v_auth.status<>'issued' OR v_auth.expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;

  v_elements := v_auth.authorized_elements;
  PERFORM private.validate_reimport_case_counts(v_auth.expected_counts);
  PERFORM private.validate_reimport_case_elements(v_elements,v_auth.expected_counts);

  -- ===== lock order step 3: samme_som mutation lock ==========================
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));

  -- ===== lock order step 4: all involved person rows, ascending id ===========
  SELECT array_agg(DISTINCT pid ORDER BY pid) INTO v_person_ids FROM (
    SELECT (e.value->'person_ids'->>0)::bigint AS pid FROM jsonb_each(v_elements) e
     WHERE e.value->>'action'='different'
    UNION
    SELECT (e.value->'person_ids'->>1)::bigint FROM jsonb_each(v_elements) e
     WHERE e.value->>'action'='different'
    UNION
    SELECT (e.value->>'target_person_id')::bigint FROM jsonb_each(v_elements) e
     WHERE e.value->>'action'='assign'
  ) q;
  PERFORM private.lock_identity_people(v_person_ids);

  -- Fund H2 live guard, under the person row locks. All involved persons are in
  -- scope: identity-pair persons as well as assign targets. Verified against the
  -- phase's own five approved cases (none carries staged/privat), so the
  -- fail-closed reading of the fund costs nothing here.
  SELECT min(p.id) INTO v_bad FROM public.person p
   WHERE p.id = ANY(v_person_ids)
     AND (coalesce(p.levende,false) OR coalesce(p.privat,false) OR coalesce(p.staged,false));
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_PERSON_NOT_PUBLISHABLE'; END IF;

  -- ===== lock order step 5: source records, ascending uuid ===================
  SELECT array_agg(DISTINCT sr.id ORDER BY sr.id) INTO v_record_ids
    FROM jsonb_each(v_elements) e
    JOIN private.source_record sr
      ON sr.source_id=v_auth.source_id AND sr.record_key=e.value->>'record_key'
   WHERE e.value->>'action' IN ('assign','no_publication');
  IF v_record_ids IS NULL
     OR array_length(v_record_ids,1) <> (v_auth.expected_counts->>'assign_events')::integer
                                      + (v_auth.expected_counts->>'no_publication_events')::integer THEN
    RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_RECORD_MISSING';
  END IF;
  PERFORM 1 FROM (
    SELECT sr.id FROM private.source_record sr
     WHERE sr.id = ANY(v_record_ids) ORDER BY sr.id FOR UPDATE) q;

  -- ===== lock order step 6: narratives, ascending id =========================
  SELECT array_agg(DISTINCT nid ORDER BY nid) INTO v_narrative_ids FROM (
    SELECT (e.value->>'target_narrative_id')::bigint AS nid FROM jsonb_each(v_elements) e
     WHERE e.value->>'action'='assign' AND jsonb_typeof(e.value->'target_narrative_id')='number'
  ) q;
  IF v_narrative_ids IS NOT NULL THEN
    PERFORM 1 FROM (
      SELECT n.id FROM public.narrative n
       WHERE n.id = ANY(v_narrative_ids) ORDER BY n.id FOR UPDATE) q;
  END IF;

  -- ===== lock order step 7: existing binding rows, ascending narrative_id ====
  PERFORM 1 FROM (
    SELECT b.id FROM private.narrative_record_publication b
     WHERE b.source_record_id = ANY(v_record_ids) ORDER BY b.narrative_id FOR UPDATE) q;

  -- ===== lock order step 8: identity relations/evidence, ascending id ========
  PERFORM 1 FROM (
    SELECT r.id FROM public.relation r
     WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
       AND (r.subjekt_id = ANY(v_person_ids) OR r.objekt_id = ANY(v_person_ids))
     ORDER BY r.id FOR UPDATE) q;

  -- ===== validate ALL cases before the first domain write ====================
  FOR v_key, v_payload IN SELECT e.key, e.value FROM jsonb_each(v_elements) e ORDER BY e.key LOOP
    v_before := v_payload->'before_state';
    IF v_payload->>'action'='different' THEN
      IF EXISTS(SELECT 1
                  FROM public._samme_som_gruppe((v_payload->'person_ids'->>0)::bigint) a
                  JOIN public._samme_som_gruppe((v_payload->'person_ids'->>1)::bigint) b ON b.pid=a.pid) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_IDENTITY_COMPONENT_DRIFT';
      END IF;
      IF EXISTS(SELECT 1 FROM public.relation r
                 WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
                   AND r.subjekt_id=(v_payload->'person_ids'->>0)::bigint
                   AND r.objekt_id=(v_payload->'person_ids'->>1)::bigint)
         <> (v_before->>'existing_rejection')::boolean THEN
        RAISE EXCEPTION 'REIMPORT_CASE_IDENTITY_DRIFT';
      END IF;
    ELSE
      v_state := private.reimport_case_source_record_state(v_auth.source_id, v_payload->>'record_key');
      IF (v_state->>'verbatim_sha256') IS DISTINCT FROM (v_before->'source_record'->>'verbatim_sha256')
         OR (v_state->>'side') IS DISTINCT FROM (v_before->'source_record'->>'side')
         OR (v_state->>'match_count')::integer <> 1 THEN
        RAISE EXCEPTION 'REIMPORT_CASE_SOURCE_RECORD_DRIFT';
      END IF;
      v_record_id := (v_state->>'source_record_id')::uuid;
      IF v_payload->>'action'='assign' THEN
        v_narrative_id := (v_payload->>'target_narrative_id')::bigint;
        v_result := private.reimport_case_narrative_state(
                      v_auth.source_id,(v_payload->>'target_person_id')::bigint);
        IF (v_result->'narrative_id') IS DISTINCT FROM (v_before->'target_narrative'->'narrative_id')
           OR (v_result->'old_sha256') IS DISTINCT FROM (v_before->'target_narrative'->'old_sha256')
           OR (v_result->>'privat')::boolean <> (v_before->'target_narrative'->>'privat')::boolean THEN
          RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_DRIFT';
        END IF;
        -- Fund H3: haendelse is a text-derived one-way projection with no
        -- regeneration trigger, so a narrative rewrite would silently strand it.
        -- Measured 0 rows in the whole base; apply therefore REQUIRES it empty.
        IF v_narrative_id IS NOT NULL
           AND EXISTS(SELECT 1 FROM public.haendelse h WHERE h.narrative_id=v_narrative_id) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_HAENDELSE_PRESENT';
        END IF;
        IF EXISTS(SELECT 1 FROM public.haendelse h
                   WHERE h.subjekt_type='person'
                     AND h.subjekt_id=(v_payload->>'target_person_id')::bigint) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_HAENDELSE_PRESENT';
        END IF;
      ELSE
        v_narrative_id := NULL;
      END IF;
      v_binding := private.reimport_case_binding_state(v_record_id, v_narrative_id);
      IF (v_binding->>'status') IS DISTINCT FROM (v_before->'binding'->>'status')
         OR (v_binding->'binding_person_id') IS DISTINCT FROM (v_before->'binding'->'binding_person_id') THEN
        RAISE EXCEPTION 'REIMPORT_CASE_BINDING_DRIFT';
      END IF;
      IF v_payload->>'action'='no_publication' AND v_binding->>'status'<>'absent' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_BINDING_ACTIVE_FOR_NO_PUBLICATION';
      END IF;
    END IF;
  END LOOP;

  -- ===== consume authorization, open the batch, open the change set ==========
  UPDATE private.reimport_case_authorization
     SET status='consumed', consumed_at=clock_timestamp() WHERE id=v_auth.id;
  INSERT INTO private.reimport_case_batch(
    authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
    principal_id,expected_counts)
  VALUES (v_auth.id,v_auth.source_id,v_auth.phase,'apply',v_auth.manifest_sha256,
    v_auth.preview_sha256,v_actor,v_auth.expected_counts)
  RETURNING id INTO v_batch_id;

  v_change_set := public.begin_change_set(
    'red_apply_reimport_cases','Anvendte fem godkendte C3-sager',NULL,NULL);

  -- ===== apply every action under the one change set =========================
  FOR v_key, v_payload IN SELECT e.key, e.value FROM jsonb_each(v_elements) e ORDER BY e.key LOOP
    v_before := v_payload->'before_state';
    IF v_payload->>'action'='different' THEN
      v_outcome := CASE WHEN (v_before->>'existing_rejection')::boolean THEN 'reused' ELSE 'created' END;
      -- red_ikke_samme_som is re-entrant here: it re-takes the samme_som advisory
      -- lock and the same person row locks we already hold, reuses our change set,
      -- and returns the existing relation unchanged when one is already present.
      v_relation_id := public.red_ikke_samme_som(
        (v_payload->'person_ids'->>0)::bigint,(v_payload->'person_ids'->>1)::bigint);
      v_after := jsonb_build_object('relation_id',v_relation_id,'outcome',v_outcome);
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_key,'identity_different','c3-apply-v1',
        jsonb_build_object('case_id',v_payload->>'case_id',
          'person_ids',v_payload->'person_ids','before_state',v_before,'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_before),
        private.reimport_1939_canonical_json_sha256(v_after));
      v_identity := v_identity + 1;

    ELSIF v_payload->>'action'='assign' THEN
      v_state := private.reimport_case_source_record_state(v_auth.source_id, v_payload->>'record_key');
      v_record_id := (v_state->>'source_record_id')::uuid;
      v_narrative_id := private.write_reimport_case_narrative(
        (v_payload->>'target_narrative_id')::bigint,
        (v_payload->>'target_person_id')::bigint, v_auth.source_id,
        v_payload->>'normalized_text', false, v_payload->>'side');
      IF jsonb_typeof(v_payload->'target_narrative_id')='number'
         AND v_narrative_id <> (v_payload->>'target_narrative_id')::bigint THEN
        RAISE EXCEPTION 'REIMPORT_CASE_NARRATIVE_DRIFT';
      END IF;
      v_written_narratives := v_written_narratives || v_narrative_id;

      -- Binding: only 'absent' (insert) or an exact same-record draft (promote).
      -- Written inline rather than through red_publicer_narrative_record so the
      -- drift taxonomy stays inside this phase's own token namespace and so
      -- Step 4b's two-session proof keeps testing that RPC's own lock.
      SELECT * INTO v_binding_row FROM private.narrative_record_publication
       WHERE narrative_id=v_narrative_id FOR UPDATE;
      IF FOUND THEN
        IF v_before->'binding'->>'status'<>'draft_same_record'
           OR v_binding_row.status<>'draft'
           OR v_binding_row.source_record_id<>v_record_id
           OR v_binding_row.record_label IS DISTINCT FROM v_payload->>'record_label'
           OR v_binding_row.citation_label IS DISTINCT FROM v_payload->>'citation_label' THEN
          RAISE EXCEPTION 'REIMPORT_CASE_BINDING_DRIFT';
        END IF;
        UPDATE private.narrative_record_publication SET status='published'
         WHERE id=v_binding_row.id RETURNING id INTO v_binding_id;
      ELSE
        IF v_before->'binding'->>'status'<>'absent' THEN
          RAISE EXCEPTION 'REIMPORT_CASE_BINDING_DRIFT';
        END IF;
        INSERT INTO private.narrative_record_publication(
          narrative_id,source_record_id,record_label,citation_label,status)
        VALUES (v_narrative_id,v_record_id,v_payload->>'record_label',
                v_payload->>'citation_label','published')
        RETURNING id INTO v_binding_id;
      END IF;

      v_after := jsonb_build_object(
        'narrative_id',v_narrative_id,'source_record_id',v_record_id,
        'binding_id',v_binding_id,'binding_status','published',
        'binding_before_kind',v_before->'binding'->>'status',
        'narrative_sha256',v_payload->>'normalized_sha256');
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_key,'record_assign','c3-apply-v1',
        jsonb_build_object('case_id',v_payload->>'case_id','rid',v_payload->>'rid',
          'record_key',v_payload->>'record_key',
          'target_person_id',v_payload->'target_person_id',
          'before_state',v_before,'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_before),
        private.reimport_1939_canonical_json_sha256(v_after));
      v_assign := v_assign + 1;

    ELSE
      -- no_publication: no domain mutation at all; only the durable event with
      -- the proven absence of an active binding (re-proved here under the locks).
      v_state := private.reimport_case_source_record_state(v_auth.source_id, v_payload->>'record_key');
      v_record_id := (v_state->>'source_record_id')::uuid;
      IF private.reimport_case_binding_state(v_record_id,NULL)->>'status'<>'absent' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_BINDING_ACTIVE_FOR_NO_PUBLICATION';
      END IF;
      v_after := jsonb_build_object(
        'source_record_id',v_record_id,'binding_status','absent','outcome','no_publication');
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_key,'record_no_publication','c3-apply-v1',
        jsonb_build_object('case_id',v_payload->>'case_id','rid',v_payload->>'rid',
          'record_key',v_payload->>'record_key','before_state',v_before,'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_before),
        private.reimport_1939_canonical_json_sha256(v_after));
      v_no_pub := v_no_pub + 1;
    END IF;
  END LOOP;

  -- ===== verify the exact after-state before the receipt is finalized ========
  FOR v_key, v_payload IN SELECT e.key, e.value FROM jsonb_each(v_elements) e ORDER BY e.key LOOP
    IF v_payload->>'action'='different' THEN
      IF NOT EXISTS(
        SELECT 1 FROM public.relation r
        JOIN public.conclusion c ON c.target_type='relation' AND c.target_id=r.id
        JOIN public.assertion a ON a.id=c.valgt_assertion_id
         WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
           AND r.subjekt_id=(v_payload->'person_ids'->>0)::bigint
           AND r.objekt_id=(v_payload->'person_ids'->>1)::bigint) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_AFTER_STATE_INVALID';
      END IF;
    ELSIF v_payload->>'action'='assign' THEN
      v_state := private.reimport_case_source_record_state(v_auth.source_id, v_payload->>'record_key');
      IF NOT EXISTS(
        SELECT 1 FROM public.narrative n
        JOIN private.narrative_record_publication b ON b.narrative_id=n.id
         WHERE n.subjekt_type='person'
           AND n.subjekt_id=(v_payload->>'target_person_id')::bigint
           AND n.source_id=v_auth.source_id
           AND coalesce(n.privat,false)=false
           AND n.side=v_payload->>'side'
           AND encode(sha256(convert_to(n.tekst,'UTF8')),'hex')=v_payload->>'normalized_sha256'
           AND b.source_record_id=(v_state->>'source_record_id')::uuid
           AND b.status='published'
           AND b.record_label=v_payload->>'record_label'
           AND b.citation_label=v_payload->>'citation_label') THEN
        RAISE EXCEPTION 'REIMPORT_CASE_AFTER_STATE_INVALID';
      END IF;
    ELSE
      v_state := private.reimport_case_source_record_state(v_auth.source_id, v_payload->>'record_key');
      IF private.reimport_case_binding_state((v_state->>'source_record_id')::uuid,NULL)->>'status'<>'absent' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_AFTER_STATE_INVALID';
      END IF;
    END IF;
  END LOOP;

  -- Fund H2: the live-guard fields must still hold after the writes; a
  -- concurrent flip would otherwise leave a "published" receipt behind an
  -- empty public projection.
  SELECT min(p.id) INTO v_bad FROM public.person p
   WHERE p.id = ANY(v_person_ids)
     AND (coalesce(p.levende,false) OR coalesce(p.privat,false) OR coalesce(p.staged,false));
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_PERSON_NOT_PUBLISHABLE'; END IF;

  -- Fund M2 (c): no narrative row outside the batch's own target set may appear
  -- in this change set. Scoped to tabel='narrative' -- relation/assertion/
  -- conclusion rows legitimately appear here, written by red_ikke_samme_som.
  IF EXISTS(
    SELECT 1 FROM public.change_event ce
     WHERE ce.change_set_id=v_change_set AND ce.tabel='narrative'
       AND NOT ((ce.row_pk->>'id')::bigint = ANY(v_written_narratives))) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_CHANGE_SCOPE_DRIFT';
  END IF;

  -- Exact observed counts, then finalize.
  SELECT count(*) INTO v_events FROM private.reimport_case_event WHERE batch_id=v_batch_id;
  IF v_identity <> (v_auth.expected_counts->>'identity_events')::integer
     OR v_assign <> (v_auth.expected_counts->>'assign_events')::integer
     OR v_no_pub <> (v_auth.expected_counts->>'no_publication_events')::integer
     OR v_events <> (v_auth.expected_counts->>'events')::integer THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_MISMATCH';
  END IF;

  UPDATE private.reimport_case_batch
     SET status='finalized', finalized_at=clock_timestamp(), change_set_id=v_change_set,
         observed_counts=jsonb_build_object(
           'cases',(v_auth.expected_counts->>'cases')::integer,
           'identity_events',v_identity,'assign_events',v_assign,
           'no_publication_events',v_no_pub,'events',v_events,
           'narratives_written',coalesce(array_length(v_written_narratives,1),0),
           'source_records',coalesce(array_length(v_record_ids,1),0),
           'persons',coalesce(array_length(v_person_ids,1),0))
   WHERE id=v_batch_id;

  RETURN private.reimport_case_receipt(v_batch_id);
END $$;

-- ---------- ACLs -------------------------------------------------------------
REVOKE ALL ON FUNCTION private.reimport_case_source_record_state(bigint,text),
  private.reimport_case_narrative_state(bigint,bigint),
  private.reimport_case_binding_state(uuid,bigint),
  private.validate_reimport_case_selection(jsonb),
  private.validate_reimport_case_elements(jsonb,jsonb),
  private.validate_reimport_case_counts(jsonb),
  private.reimport_case_receipt(uuid),
  private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_preview_reimport_cases(bigint,text,jsonb),
  public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz),
  public.red_apply_reimport_cases(uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_preview_reimport_cases(bigint,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.red_apply_reimport_cases(uuid,text,text) TO authenticated;

-- ===== 2026-08-23: DAA 1939 v50 fase C3 -- exact-after batch reversal (Task 7) =====
-- ============================================================================
-- DAA 1939 v50 fase C3: exact-after reversal of an applied batch (Task 7)
-- ============================================================================
-- Reversal is its OWN batch (fund B5), never a status flip on the applied one:
-- it carries its own authorization, nonce, expected/observed counts, change set
-- and receipt, and the applied batch points at it through reversal_batch_id.
-- Two consequences that motivated the shape: reversal events would otherwise
-- collide with apply events on UNIQUE(batch_id,element_id), and without its own
-- nonce a commit-unknown reversal could not be told apart from one that never
-- started.
--
-- The deterministic lock order is the SAME ten steps apply uses (0,1,2,2.5,3,
-- 4,5,6,7,8); step 8 is extended with the identity evidence rows, in the order
-- _delete_relation_evidence already touches them (relation -> conclusion ->
-- assertion), so the two paths cannot invert against each other.
--
-- Reuse, not reinvention: private.require_reimport_1939_editor() gates the
-- role, private.reimport_1939_canonical_json_sha256() hashes every payload,
-- private.reimport_case_receipt()/_binding_state() are the same oracles apply
-- uses, and public.red_fortryd_change_set() does the narrative and identity
-- undo through the shared version ledger rather than through a second,
-- divergent implementation.
-- ============================================================================

-- ---------- private: the single reversal oracle ------------------------------
-- Fund H1 one level down: authorize and reverse must never derive the plan
-- differently, so both call this and nothing else. It answers "is this batch
-- reversible, and exactly what would reversing it do?" from the append-only
-- event ledger alone -- no domain state is read here, so the plan is stable
-- from authorization until the reversal's own CAS re-derives it.
--
-- The batch receipt's own hash is deliberately NOT part of the plan: they are
-- two independent artefacts pinned by two independent tokens. Nesting one in
-- the other would make the inner one's token unreachable -- an injected event
-- would report as receipt drift, or a tampered receipt as plan drift.
CREATE OR REPLACE FUNCTION private.reimport_case_reversal_plan(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE v_batch private.reimport_case_batch%ROWTYPE; v_events jsonb; v_counts jsonb;
BEGIN
  SELECT * INTO v_batch FROM private.reimport_case_batch WHERE id=p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REIMPORT_CASE_BATCH_INVALID'; END IF;
  IF v_batch.phase<>'c3' OR v_batch.operation<>'apply'
     OR v_batch.status<>'finalized' OR v_batch.reversal_batch_id IS NOT NULL
     OR v_batch.change_set_id IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_CASE_BATCH_NOT_REVERSIBLE';
  END IF;
  -- The web fortryd panel is prod-live, so a human can undo the batch's change
  -- set out of band. Caught here, in the shared oracle, rather than inside
  -- red_fortryd_change_set -- which would raise its own Danish free-text error
  -- AFTER reversal had already deleted binding rows.
  IF EXISTS(SELECT 1 FROM public.change_set WHERE reverterer_id=v_batch.change_set_id) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_CHANGE_SET_ALREADY_REVERSED';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
           'event_id', e.id, 'element_id', e.element_id, 'action', e.action,
           'payload', e.payload, 'before_sha256', e.before_sha256,
           'after_sha256', e.after_sha256)
         ORDER BY e.element_id)
    INTO v_events
    FROM private.reimport_case_event e WHERE e.batch_id=p_batch_id;
  IF v_events IS NULL THEN RAISE EXCEPTION 'REIMPORT_CASE_BATCH_NOT_REVERSIBLE'; END IF;

  SELECT jsonb_build_object(
           'events', count(*),
           'identity_events', count(*) FILTER (WHERE e->>'action'='identity_different'),
           'assign_events', count(*) FILTER (WHERE e->>'action'='record_assign'),
           'no_publication_events', count(*) FILTER (WHERE e->>'action'='record_no_publication'),
           'identity_created', count(*) FILTER (
             WHERE e->>'action'='identity_different' AND e->'payload'->'result'->>'outcome'='created'),
           'identity_reused', count(*) FILTER (
             WHERE e->>'action'='identity_different' AND e->'payload'->'result'->>'outcome'='reused'),
           'bindings_deleted', count(*) FILTER (
             WHERE e->>'action'='record_assign'
               AND e->'payload'->'before_state'->'binding'->>'status'='absent'),
           'bindings_restored', count(*) FILTER (
             WHERE e->>'action'='record_assign'
               AND e->'payload'->'before_state'->'binding'->>'status'='draft_same_record'),
           'narratives_deleted', count(*) FILTER (
             WHERE e->>'action'='record_assign'
               AND jsonb_typeof(e->'payload'->'before_state'->'target_narrative'->'narrative_id')='null'),
           'narratives_restored', count(*) FILTER (
             WHERE e->>'action'='record_assign'
               AND jsonb_typeof(e->'payload'->'before_state'->'target_narrative'->'narrative_id')='number'))
    INTO v_counts
    FROM jsonb_array_elements(v_events) e;

  RETURN jsonb_build_object(
    'schema_version','c3-reversal-plan-v1',
    'batch_id', v_batch.id, 'authorization_id', v_batch.authorization_id,
    'source_id', v_batch.source_id, 'phase', v_batch.phase,
    'change_set_id', v_batch.change_set_id,
    'manifest_sha256', v_batch.manifest_sha256, 'preview_sha256', v_batch.preview_sha256,
    'counts', v_counts, 'events', v_events);
END $$;

-- ---------- public: expiring reversal authorization --------------------------
-- Same principal split as apply: service_role authorises, authenticated
-- reverses; both still require the same redaktion subject.
CREATE OR REPLACE FUNCTION public.red_authorize_reimport_case_reversal(
  p_batch_id uuid, p_receipt_sha256 text, p_nonce uuid, p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid;
  v_batch private.reimport_case_batch%ROWTYPE;
  v_auth private.reimport_case_authorization%ROWTYPE;
  v_existing private.reimport_case_authorization%ROWTYPE;
  v_plan jsonb; v_plan_sha text; v_receipt_sha text; v_elements jsonb; v_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;
  v_actor:=private.require_reimport_1939_editor();
  IF p_batch_id IS NULL OR p_receipt_sha256 !~ '^[0-9a-f]{64}$'
     OR p_nonce IS NULL OR p_expires_at IS NULL OR p_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  SELECT * INTO v_batch FROM private.reimport_case_batch WHERE id=p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REIMPORT_CASE_BATCH_INVALID'; END IF;
  SELECT * INTO v_auth FROM private.reimport_case_authorization WHERE id=v_batch.authorization_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID'; END IF;
  -- Fund B1, both fields separately: a batch carried into another database (a
  -- restored dump, a rehearsal copy) must not be reversible there.
  IF v_auth.database_name IS DISTINCT FROM current_database()
     OR v_auth.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH';
  END IF;

  -- Nonce is the commit-unknown handle, exactly as for apply -- and it is
  -- looked up BEFORE the plan and the receipt are derived, because neither
  -- derivation survives the reversal this authorization goes on to permit: the
  -- plan oracle refuses a batch that is already 'reversed', and the applied
  -- batch's receipt stops hashing to the approved value the moment its status
  -- flips inside that very JSON. A caller whose connection dropped on the
  -- original authorize call must still be able to repeat it, so the replay is
  -- decided against what was STORED when the authorization was created --
  -- never against a fresh re-derivation. manifest_sha256 IS that stored
  -- receipt hash (see the INSERT below), so comparing the caller's
  -- p_receipt_sha256 to it is the same commitment as before, just taken from
  -- the ledger instead of from the live batch.
  SELECT * INTO v_existing FROM private.reimport_case_authorization WHERE nonce=p_nonce;
  IF FOUND THEN
    IF v_existing.operation='reversal' AND v_existing.source_id=v_batch.source_id
       AND v_existing.phase=v_batch.phase
       AND v_existing.manifest_sha256=p_receipt_sha256
       AND v_existing.preview_sha256=v_batch.preview_sha256
       AND v_existing.principal_id=v_actor
       AND (SELECT count(*) FROM jsonb_object_keys(v_existing.authorized_elements))=1
       AND (v_existing.authorized_elements->('batch:'||p_batch_id::text)) IS NOT NULL THEN
      RETURN v_existing.id;
    END IF;
    RAISE EXCEPTION 'REIMPORT_CASE_NONCE_CONFLICT';
  END IF;

  v_plan := private.reimport_case_reversal_plan(p_batch_id);
  v_receipt_sha := private.reimport_1939_canonical_json_sha256(
                     private.reimport_case_receipt(p_batch_id));
  IF v_receipt_sha IS DISTINCT FROM p_receipt_sha256 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_RECEIPT_DRIFT';
  END IF;
  v_plan_sha := private.reimport_1939_canonical_json_sha256(v_plan);
  v_elements := jsonb_build_object('batch:'||p_batch_id::text, jsonb_build_object(
    'action','reverse_batch','batch_id',p_batch_id,
    'receipt_sha256',v_receipt_sha,'plan_sha256',v_plan_sha,
    'event_ids',(SELECT jsonb_agg(e->'event_id' ORDER BY (e->>'event_id')::bigint)
                   FROM jsonb_array_elements(v_plan->'events') e)));

  -- manifest_sha256 of a reversal IS the receipt hash of the batch it reverses:
  -- that receipt is the artefact a human approved, and it keeps
  -- reimport_case_batch_manifest_uidx (which does NOT include operation) from
  -- colliding with the applied batch while still giving exactly one reversal
  -- batch per receipt per principal.
  INSERT INTO private.reimport_case_authorization(
    source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
    expected_counts,authorized_elements,principal_id,nonce,expires_at)
  VALUES (v_batch.source_id,v_batch.phase,'reversal',v_receipt_sha,v_batch.preview_sha256,
    v_auth.approval_sha256,v_auth.decisions_sha256,v_auth.state_sha256,v_auth.text_bundle_sha256,
    current_database(),(pg_control_system()).system_identifier::text,
    v_plan->'counts',v_elements,v_actor,p_nonce,p_expires_at)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---------- public: one-call atomic reversal ---------------------------------
CREATE OR REPLACE FUNCTION public.red_reverse_reimport_cases(
  p_authorization_id uuid, p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_actor uuid; v_auth private.reimport_case_authorization%ROWTYPE;
  v_orig private.reimport_case_batch%ROWTYPE;
  v_batch private.reimport_case_batch%ROWTYPE; v_batch_id uuid;
  v_element jsonb; v_plan jsonb; v_plan_sha text; v_receipt_sha text;
  v_event jsonb; v_payload jsonb;
  v_before jsonb; v_result jsonb; v_after jsonb;
  v_person_ids bigint[]; v_record_ids uuid[]; v_narrative_ids bigint[]; v_relation_ids bigint[];
  v_change_set bigint; v_rev_change_set bigint; v_fortryd jsonb;
  v_binding_row private.narrative_record_publication%ROWTYPE;
  v_narr public.narrative%ROWTYPE;
  v_rel_id bigint; v_narrative_id bigint; v_record_id uuid; v_binding_id uuid;
  v_identity integer:=0; v_assign integer:=0; v_no_pub integer:=0;
  v_bind_del integer:=0; v_bind_restored integer:=0;
  v_rel_deleted integer:=0; v_rel_kept integer:=0;
  v_narr_deleted integer:=0; v_narr_restored integer:=0; v_events integer;
BEGIN
  -- ===== lock order step 0: unbounded cutover gate, then version =============
  -- Same unbounded first-wait contract as apply: after a committed cutover the
  -- call must wake and return the exact legacy-writer error.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'; END IF;

  -- ===== lock order step 0.5: timeouts for subsequent family/domain locks =====
  -- The
  -- change-set guard's motive differs, though: reversal never opens a change
  -- set of its own, but red_fortryd_change_set deliberately clears
  -- app.change_set_id and never restores it, so a caller that had one open
  -- would silently stop logging everything it did afterwards. One server-side
  -- call, one transaction -- fail closed on anything else.
  PERFORM set_config('lock_timeout','5s',true);
  PERFORM set_config('statement_timeout','120s',true);
  -- The shared cutover gate above is the first transaction lock. Only after
  -- its version recheck may this guard or an existing C3 lock run.
  IF btrim(coalesce(current_setting('app.change_set_id',true),'')) <> '' THEN
    RAISE EXCEPTION 'REIMPORT_CASE_FOREIGN_CHANGE_SET';
  END IF;

  -- ===== lock order step 1: global production-writer lock ====================
  -- The SAME key apply takes, so an apply and a reversal can never interleave.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0));
  -- ===== lock order step 2: actor / profile / role gate ======================
  v_actor := private.require_reimport_1939_editor();

  -- ===== lock order step 2.5: the authorization row, then the batches ========
  SELECT * INTO v_auth FROM private.reimport_case_authorization
   WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_auth.phase<>'c3' OR v_auth.operation<>'reversal'
     OR v_auth.principal_id<>v_actor THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  v_element := v_auth.authorized_elements->('batch:'||p_batch_id::text);
  IF v_element IS NULL OR (SELECT count(*) FROM jsonb_object_keys(v_auth.authorized_elements))<>1
     OR v_element->>'action'<>'reverse_batch'
     OR (v_element->>'batch_id')::uuid IS DISTINCT FROM p_batch_id THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  IF v_auth.database_name IS DISTINCT FROM current_database()
     OR v_auth.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH';
  END IF;

  -- Commit-unknown replay: a consumed authorization with a finalized reversal
  -- batch returns that exact receipt BEFORE any state is re-derived -- the
  -- applied batch is 'reversed' by then and every CAS below would (correctly,
  -- but uselessly) turn a success into terminal drift.
  IF v_auth.status='consumed' THEN
    SELECT * INTO v_batch FROM private.reimport_case_batch
     WHERE authorization_id=v_auth.id FOR UPDATE;
    IF FOUND AND v_batch.status='finalized' THEN
      RETURN private.reimport_case_receipt(v_batch.id);
    END IF;
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_ALREADY_CONSUMED';
  END IF;
  IF v_auth.status<>'issued' OR v_auth.expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'REIMPORT_CASE_AUTHORIZATION_INVALID';
  END IF;
  SELECT * INTO v_orig FROM private.reimport_case_batch WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_orig.source_id<>v_auth.source_id OR v_orig.phase<>v_auth.phase THEN
    RAISE EXCEPTION 'REIMPORT_CASE_BATCH_INVALID';
  END IF;

  -- ===== reversal CAS: everything is proven BEFORE the first mutation ========
  -- Re-derive the plan under the locks and require it byte-identical to the
  -- authorised one. The plan carries every event id and payload, so that one
  -- comparison IS the spec's "C3-event-ID-set og payloadhashes"; the receipt
  -- hash right after it is the spec's "den finalized batchkvittering".
  v_plan := private.reimport_case_reversal_plan(p_batch_id);
  -- Two artefacts, two tokens, checked in this order: the plan (the batch's own
  -- event ledger) names an injected or missing event, the receipt names a
  -- tampered batch header. Because neither hash is nested in the other, both
  -- tokens stay reachable and each says which artefact actually moved.
  v_plan_sha := private.reimport_1939_canonical_json_sha256(v_plan);
  IF v_plan_sha IS DISTINCT FROM (v_element->>'plan_sha256') THEN
    RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_PLAN_DRIFT';
  END IF;
  v_receipt_sha := private.reimport_1939_canonical_json_sha256(
                     private.reimport_case_receipt(p_batch_id));
  IF v_receipt_sha IS DISTINCT FROM v_auth.manifest_sha256
     OR v_receipt_sha IS DISTINCT FROM (v_element->>'receipt_sha256') THEN
    RAISE EXCEPTION 'REIMPORT_CASE_RECEIPT_DRIFT';
  END IF;
  IF v_plan->'counts' IS DISTINCT FROM v_auth.expected_counts THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_MISMATCH';
  END IF;
  v_change_set := (v_plan->>'change_set_id')::bigint;

  -- ===== lock order step 3: samme_som mutation lock ==========================
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));

  -- ===== lock order step 4: all involved person rows, ascending id ===========
  SELECT array_agg(DISTINCT pid ORDER BY pid) INTO v_person_ids FROM (
    SELECT (e->'payload'->'person_ids'->>0)::bigint AS pid
      FROM jsonb_array_elements(v_plan->'events') e WHERE e->>'action'='identity_different'
    UNION
    SELECT (e->'payload'->'person_ids'->>1)::bigint
      FROM jsonb_array_elements(v_plan->'events') e WHERE e->>'action'='identity_different'
    UNION
    SELECT (e->'payload'->>'target_person_id')::bigint
      FROM jsonb_array_elements(v_plan->'events') e WHERE e->>'action'='record_assign'
  ) q;
  PERFORM private.lock_identity_people(v_person_ids);
  -- Deliberately NO fund-H2 publishability guard here: reversal REMOVES
  -- published content, so a person that has since been flagged levende/privat/
  -- staged must not be able to block the withdrawal of their own text.

  -- ===== lock order step 5: source records, ascending uuid ===================
  SELECT array_agg(DISTINCT rid ORDER BY rid) INTO v_record_ids FROM (
    SELECT (e->'payload'->'result'->>'source_record_id')::uuid AS rid
      FROM jsonb_array_elements(v_plan->'events') e
     WHERE e->>'action' IN ('record_assign','record_no_publication')
  ) q;
  IF v_record_ids IS NOT NULL THEN
    PERFORM 1 FROM (
      SELECT sr.id FROM private.source_record sr
       WHERE sr.id = ANY(v_record_ids) ORDER BY sr.id FOR UPDATE) q;
  END IF;

  -- ===== lock order step 6: narratives, ascending id =========================
  -- Union of the batch's assign targets and every narrative row the change set
  -- itself touched: red_fortryd_change_set will write exactly the latter.
  SELECT array_agg(DISTINCT nid ORDER BY nid) INTO v_narrative_ids FROM (
    SELECT (e->'payload'->'result'->>'narrative_id')::bigint AS nid
      FROM jsonb_array_elements(v_plan->'events') e WHERE e->>'action'='record_assign'
    UNION
    SELECT (ce.row_pk->>'id')::bigint FROM public.change_event ce
     WHERE ce.change_set_id=v_change_set AND ce.tabel='narrative'
  ) q;
  IF v_narrative_ids IS NOT NULL THEN
    PERFORM 1 FROM (
      SELECT n.id FROM public.narrative n
       WHERE n.id = ANY(v_narrative_ids) ORDER BY n.id FOR UPDATE) q;
  END IF;

  -- ===== lock order step 7: existing binding rows, ascending narrative_id ====
  IF v_record_ids IS NOT NULL THEN
    PERFORM 1 FROM (
      SELECT b.id FROM private.narrative_record_publication b
       WHERE b.source_record_id = ANY(v_record_ids) ORDER BY b.narrative_id FOR UPDATE) q;
  END IF;

  -- ===== lock order step 8: identity relations, then their evidence ==========
  -- Extended beyond apply's step 8 (which only ever created these rows):
  -- reversal DELETES conclusion and assertion rows, so it locks them too --
  -- relation, then conclusion, then assertion, which is the order
  -- _delete_relation_evidence already touches them in, so the two paths cannot
  -- invert against each other.
  PERFORM 1 FROM (
    SELECT r.id FROM public.relation r
     WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
       AND (r.subjekt_id = ANY(v_person_ids) OR r.objekt_id = ANY(v_person_ids))
     ORDER BY r.id FOR UPDATE) q;
  SELECT array_agg(DISTINCT rid ORDER BY rid) INTO v_relation_ids FROM (
    SELECT (e->'payload'->'result'->>'relation_id')::bigint AS rid
      FROM jsonb_array_elements(v_plan->'events') e WHERE e->>'action'='identity_different'
  ) q;
  IF v_relation_ids IS NOT NULL THEN
    PERFORM 1 FROM (
      SELECT c.id FROM public.conclusion c
       WHERE c.target_type='relation' AND c.target_id = ANY(v_relation_ids)
       ORDER BY c.id FOR UPDATE) q;
    PERFORM 1 FROM (
      SELECT a.id FROM public.assertion a
       WHERE a.target_type='relation' AND a.target_id = ANY(v_relation_ids)
       ORDER BY a.id FOR UPDATE) q;
  END IF;

  -- ===== exact-after CAS on live domain state, still before any mutation =====
  -- (a) the whole version ledger: every row the change set left behind must
  -- still look exactly as it left it. This is red_fortryd_change_set's own B9
  -- guard, hoisted in front of the first mutation so its failure can never
  -- arrive after binding rows are already gone.
  -- Only the LAST event per (tabel,row_pk) describes what the set left behind;
  -- an earlier event for the same row was already superseded inside the set, so
  -- comparing it would be stricter than B9 and would fail a healthy batch.
  IF EXISTS(
    SELECT 1 FROM (
      SELECT DISTINCT ON (ce.tabel,ce.row_pk) ce.tabel, ce.row_pk, ce.op, ce.efter
        FROM public.change_event ce
       WHERE ce.change_set_id=v_change_set
       ORDER BY ce.tabel, ce.row_pk, ce.seq DESC) last_ce
     WHERE public._version_current_row(last_ce.tabel,last_ce.row_pk)
           IS DISTINCT FROM (CASE WHEN last_ce.op='DELETE' THEN NULL ELSE last_ce.efter END)) THEN
    RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_STATE_DRIFT';
  END IF;

  FOR v_event IN SELECT value FROM jsonb_array_elements(v_plan->'events') ORDER BY value->>'element_id' LOOP
    v_payload := v_event->'payload';
    v_result := v_payload->'result';
    IF v_event->>'action'='identity_different' THEN
      v_rel_id := (v_result->>'relation_id')::bigint;
      IF NOT EXISTS(
        SELECT 1 FROM public.relation r
        JOIN public.conclusion c ON c.target_type='relation' AND c.target_id=r.id
        JOIN public.assertion a ON a.id=c.valgt_assertion_id
         WHERE r.id=v_rel_id AND r.rolle='ikke_samme_som'
           AND r.subjekt_type='person' AND r.objekt_type='person'
           AND r.subjekt_id=(v_payload->'person_ids'->>0)::bigint
           AND r.objekt_id=(v_payload->'person_ids'->>1)::bigint) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_IDENTITY_DRIFT';
      END IF;
      -- created|reused is not taken on trust from the event: the discriminator
      -- is whether the relation's INSERT is in the batch's OWN change set.
      -- red_ikke_samme_som returns before begin_change_set when the edge is
      -- already there, so a reused relation has no change_event -- and
      -- red_fortryd_change_set will therefore leave it standing, which is
      -- exactly what the spec requires ("reversal ma kun fjerne created").
      IF EXISTS(SELECT 1 FROM public.change_event ce
                 WHERE ce.change_set_id=v_change_set AND ce.tabel='relation'
                   AND ce.op='INSERT' AND (ce.row_pk->>'id')::bigint=v_rel_id)
         <> (v_result->>'outcome'='created') THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_IDENTITY_DRIFT';
      END IF;
    ELSIF v_event->>'action'='record_assign' THEN
      v_narrative_id := (v_result->>'narrative_id')::bigint;
      SELECT * INTO v_narr FROM public.narrative WHERE id=v_narrative_id;
      IF NOT FOUND OR v_narr.subjekt_type<>'person'
         OR v_narr.subjekt_id<>(v_payload->>'target_person_id')::bigint
         OR v_narr.source_id IS DISTINCT FROM v_orig.source_id
         OR coalesce(v_narr.privat,false)
         OR encode(sha256(convert_to(v_narr.tekst,'UTF8')),'hex')
            IS DISTINCT FROM (v_result->>'narrative_sha256') THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_NARRATIVE_DRIFT';
      END IF;
      -- Fund H3, mirrored: haendelse is a text-derived projection with no
      -- regeneration trigger, so restoring (or deleting) the narrative under
      -- one would silently strand it. Apply required this empty; so does
      -- reversal.
      IF EXISTS(SELECT 1 FROM public.haendelse h WHERE h.narrative_id=v_narrative_id)
         OR EXISTS(SELECT 1 FROM public.haendelse h
                    WHERE h.subjekt_type='person'
                      AND h.subjekt_id=(v_payload->>'target_person_id')::bigint) THEN
        RAISE EXCEPTION 'REIMPORT_CASE_HAENDELSE_PRESENT';
      END IF;
      SELECT * INTO v_binding_row FROM private.narrative_record_publication
       WHERE id=(v_result->>'binding_id')::uuid;
      IF NOT FOUND OR v_binding_row.status<>'published'
         OR v_binding_row.narrative_id<>v_narrative_id
         OR v_binding_row.source_record_id<>(v_result->>'source_record_id')::uuid THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_BINDING_DRIFT';
      END IF;
    ELSE
      IF private.reimport_case_binding_state(
           (v_result->>'source_record_id')::uuid,NULL)->>'status'<>'absent' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_BINDING_DRIFT';
      END IF;
    END IF;
  END LOOP;

  -- ===== consume the authorization and open the reversal batch ===============
  UPDATE private.reimport_case_authorization
     SET status='consumed', consumed_at=clock_timestamp() WHERE id=v_auth.id;
  INSERT INTO private.reimport_case_batch(
    authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
    principal_id,expected_counts)
  VALUES (v_auth.id,v_auth.source_id,v_auth.phase,'reversal',v_auth.manifest_sha256,
    v_auth.preview_sha256,v_actor,v_auth.expected_counts)
  RETURNING id INTO v_batch_id;

  -- ===== bindings first: they are NOT in the version registry ================
  -- private.narrative_record_publication carries no log_change trigger, so the
  -- change-set undo below cannot touch it -- and it must go first regardless,
  -- because narrative_id is a plain FK with no ON DELETE: a narrative the batch
  -- created cannot be removed while its binding still points at it.
  FOR v_event IN SELECT value FROM jsonb_array_elements(v_plan->'events') ORDER BY value->>'element_id' LOOP
    CONTINUE WHEN v_event->>'action'<>'record_assign';
    v_result := v_event->'payload'->'result';
    v_binding_id := (v_result->>'binding_id')::uuid;
    IF v_event->'payload'->'before_state'->'binding'->>'status'='absent' THEN
      DELETE FROM private.narrative_record_publication WHERE id=v_binding_id;
      v_bind_del := v_bind_del + 1;
    ELSE
      -- Restoring the draft's ORIGINAL values, not an approximation:
      -- validate_narrative_record_publication stamps published_at only when a
      -- row becomes 'published', nothing else ever writes it, and no shipped
      -- writer creates a draft with it set -- so NULL is the value apply
      -- overwrote. record_label/citation_label/record_ref were never touched
      -- (the trigger forbids changing the binding identity on UPDATE, and apply
      -- required the labels to match exactly before promoting).
      UPDATE private.narrative_record_publication
         SET status='draft', published_at=NULL WHERE id=v_binding_id;
      v_bind_restored := v_bind_restored + 1;
    END IF;
  END LOOP;

  -- ===== narratives and batch-created identity rows: shared change-set undo ==
  -- One call, non-force. Its own B9 guard is a second net behind the CAS above;
  -- p_force is never true -- the phase offers no force bypass.
  v_fortryd := public.red_fortryd_change_set(v_change_set,false);
  v_rev_change_set := (v_fortryd->>'reversal_change_set')::bigint;
  IF v_rev_change_set IS NULL OR (v_fortryd->>'divergenser')::integer<>0 THEN
    RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_STATE_DRIFT';
  END IF;

  -- ===== verify the exact BEFORE-state has been restored =====================
  -- Reversal events reuse the applied event's element_id (they live in a
  -- different batch, so UNIQUE(batch_id,element_id) is untouched) and the SAME
  -- payload_schema_version literal 'c3-apply-v1'. That literal is a family
  -- version, not a per-shape schema -- it already labels three structurally
  -- different apply payloads -- and reimport_case_event's CHECK pins it to
  -- exactly one value. A reversal event is told apart by its batch's
  -- operation='reversal' and by its own reversed_batch_id/reverses_event_id.
  FOR v_event IN SELECT value FROM jsonb_array_elements(v_plan->'events') ORDER BY value->>'element_id' LOOP
    v_payload := v_event->'payload';
    v_before := v_payload->'before_state';
    v_result := v_payload->'result';
    IF v_event->>'action'='identity_different' THEN
      v_rel_id := (v_result->>'relation_id')::bigint;
      IF v_result->>'outcome'='created' THEN
        IF EXISTS(SELECT 1 FROM public.relation WHERE id=v_rel_id)
           OR EXISTS(SELECT 1 FROM public.conclusion
                      WHERE target_type='relation' AND target_id=v_rel_id)
           OR EXISTS(SELECT 1 FROM public.assertion
                      WHERE target_type='relation' AND target_id=v_rel_id) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_rel_deleted := v_rel_deleted + 1;
        v_after := jsonb_build_object('relation_id',v_rel_id,'outcome','deleted',
          'reversed_batch_id',p_batch_id,'reverses_event_id',v_event->'event_id');
      ELSE
        -- The reused edge predates the batch and must survive it untouched.
        IF NOT EXISTS(
          SELECT 1 FROM public.relation r
          JOIN public.conclusion c ON c.target_type='relation' AND c.target_id=r.id
          JOIN public.assertion a ON a.id=c.valgt_assertion_id
           WHERE r.id=v_rel_id AND r.rolle='ikke_samme_som'
             AND r.subjekt_id=(v_payload->'person_ids'->>0)::bigint
             AND r.objekt_id=(v_payload->'person_ids'->>1)::bigint) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_rel_kept := v_rel_kept + 1;
        v_after := jsonb_build_object('relation_id',v_rel_id,'outcome','kept',
          'reversed_batch_id',p_batch_id,'reverses_event_id',v_event->'event_id');
      END IF;
      v_identity := v_identity + 1;
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_event->>'element_id',
        'identity_different','c3-apply-v1',
        jsonb_build_object('reversed_batch_id',p_batch_id,
          'reverses_event_id',v_event->'event_id','case_id',v_payload->>'case_id',
          'person_ids',v_payload->'person_ids','before_state',v_result,
          'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_result),
        private.reimport_1939_canonical_json_sha256(v_after));

    ELSIF v_event->>'action'='record_assign' THEN
      v_narrative_id := (v_result->>'narrative_id')::bigint;
      v_record_id := (v_result->>'source_record_id')::uuid;
      IF jsonb_typeof(v_before->'target_narrative'->'narrative_id')='null' THEN
        -- The batch created this narrative: the undo must have removed it.
        IF EXISTS(SELECT 1 FROM public.narrative WHERE id=v_narrative_id)
           OR EXISTS(SELECT 1 FROM public.narrative
                      WHERE subjekt_type='person'
                        AND subjekt_id=(v_payload->>'target_person_id')::bigint
                        AND source_id IS NOT DISTINCT FROM v_orig.source_id) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_narr_deleted := v_narr_deleted + 1;
        v_after := jsonb_build_object('narrative_id',NULL,'narrative_sha256',NULL);
      ELSE
        SELECT * INTO v_narr FROM public.narrative WHERE id=v_narrative_id;
        IF NOT FOUND
           OR v_narr.id IS DISTINCT FROM (v_before->'target_narrative'->>'narrative_id')::bigint
           OR coalesce(v_narr.privat,false)
              IS DISTINCT FROM (v_before->'target_narrative'->>'privat')::boolean
           OR encode(sha256(convert_to(v_narr.tekst,'UTF8')),'hex')
              IS DISTINCT FROM (v_before->'target_narrative'->>'old_sha256') THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_narr_restored := v_narr_restored + 1;
        v_after := jsonb_build_object('narrative_id',v_narrative_id,
          'narrative_sha256',v_before->'target_narrative'->>'old_sha256');
      END IF;
      IF v_before->'binding'->>'status'='absent' THEN
        IF private.reimport_case_binding_state(v_record_id,NULL)->>'status'<>'absent'
           OR EXISTS(SELECT 1 FROM private.narrative_record_publication
                      WHERE id=(v_result->>'binding_id')::uuid) THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_after := v_after||jsonb_build_object('binding_id',NULL,'binding_status','absent',
          'outcome','binding_deleted');
      ELSE
        SELECT * INTO v_binding_row FROM private.narrative_record_publication
         WHERE id=(v_result->>'binding_id')::uuid;
        IF NOT FOUND OR v_binding_row.status<>'draft'
           OR v_binding_row.published_at IS NOT NULL
           OR v_binding_row.narrative_id<>v_narrative_id
           OR v_binding_row.source_record_id<>v_record_id THEN
          RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
        END IF;
        v_after := v_after||jsonb_build_object('binding_id',v_binding_row.id,
          'binding_status','draft','outcome','binding_restored');
      END IF;
      v_after := v_after||jsonb_build_object('source_record_id',v_record_id,
        'reversed_batch_id',p_batch_id,'reverses_event_id',v_event->'event_id');
      v_assign := v_assign + 1;
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_event->>'element_id',
        'record_assign','c3-apply-v1',
        jsonb_build_object('reversed_batch_id',p_batch_id,
          'reverses_event_id',v_event->'event_id','case_id',v_payload->>'case_id',
          'rid',v_payload->>'rid','record_key',v_payload->>'record_key',
          'target_person_id',v_payload->'target_person_id',
          'before_state',v_result,'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_result),
        private.reimport_1939_canonical_json_sha256(v_after));

    ELSE
      v_record_id := (v_result->>'source_record_id')::uuid;
      IF private.reimport_case_binding_state(v_record_id,NULL)->>'status'<>'absent' THEN
        RAISE EXCEPTION 'REIMPORT_CASE_REVERSAL_AFTER_STATE_INVALID';
      END IF;
      v_no_pub := v_no_pub + 1;
      v_after := jsonb_build_object('source_record_id',v_record_id,
        'binding_status','absent','outcome','no_change',
        'reversed_batch_id',p_batch_id,'reverses_event_id',v_event->'event_id');
      INSERT INTO private.reimport_case_event(
        batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
        before_sha256,after_sha256)
      VALUES (v_batch_id,v_auth.source_id,v_auth.phase,v_event->>'element_id',
        'record_no_publication','c3-apply-v1',
        jsonb_build_object('reversed_batch_id',p_batch_id,
          'reverses_event_id',v_event->'event_id','case_id',v_payload->>'case_id',
          'rid',v_payload->>'rid','record_key',v_payload->>'record_key',
          'before_state',v_result,'result',v_after),
        private.reimport_1939_canonical_json_sha256(v_result),
        private.reimport_1939_canonical_json_sha256(v_after));
    END IF;
  END LOOP;

  -- ===== mark the applied batch reversed, then finalize this one =============
  UPDATE private.reimport_case_batch
     SET status='reversed', reversal_batch_id=v_batch_id
   WHERE id=p_batch_id;

  SELECT count(*) INTO v_events FROM private.reimport_case_event WHERE batch_id=v_batch_id;
  IF v_identity <> (v_auth.expected_counts->>'identity_events')::integer
     OR v_assign <> (v_auth.expected_counts->>'assign_events')::integer
     OR v_no_pub <> (v_auth.expected_counts->>'no_publication_events')::integer
     OR v_events <> (v_auth.expected_counts->>'events')::integer
     OR v_rel_deleted <> (v_auth.expected_counts->>'identity_created')::integer
     OR v_rel_kept <> (v_auth.expected_counts->>'identity_reused')::integer
     OR v_bind_del <> (v_auth.expected_counts->>'bindings_deleted')::integer
     OR v_bind_restored <> (v_auth.expected_counts->>'bindings_restored')::integer
     OR v_narr_deleted <> (v_auth.expected_counts->>'narratives_deleted')::integer
     OR v_narr_restored <> (v_auth.expected_counts->>'narratives_restored')::integer THEN
    RAISE EXCEPTION 'REIMPORT_CASE_COUNTS_MISMATCH';
  END IF;

  UPDATE private.reimport_case_batch
     SET status='finalized', finalized_at=clock_timestamp(), change_set_id=v_rev_change_set,
         observed_counts=jsonb_build_object(
           'events',v_events,'identity_events',v_identity,'assign_events',v_assign,
           'no_publication_events',v_no_pub,
           'identity_created',v_rel_deleted,'identity_reused',v_rel_kept,
           'bindings_deleted',v_bind_del,'bindings_restored',v_bind_restored,
           'narratives_deleted',v_narr_deleted,'narratives_restored',v_narr_restored,
           'reversed_batch_id',p_batch_id)
   WHERE id=v_batch_id;

  RETURN private.reimport_case_receipt(v_batch_id);
END $$;

-- ---------- ACLs -------------------------------------------------------------
REVOKE ALL ON FUNCTION private.reimport_case_reversal_plan(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz),
  public.red_reverse_reimport_cases(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.red_reverse_reimport_cases(uuid,uuid) TO authenticated;

-- =====================================================================
-- 2026-08-29: #152 — additive narrative publication event foundation
-- =====================================================================

CREATE OR REPLACE FUNCTION public.narrative_record_contract_version()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$ SELECT 1 $$;

CREATE TABLE private.narrative_legacy_publication (
  legacy_publication_ref uuid NOT NULL,
  narrative_id bigint NOT NULL,
  source_id bigint NOT NULL,
  baseline_state jsonb NOT NULL,
  baseline_sha256 text NOT NULL,
  status text NOT NULL,
  latest_event_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT narrative_legacy_publication_pkey
    PRIMARY KEY (legacy_publication_ref),
  CONSTRAINT narrative_legacy_publication_narrative_id_key
    UNIQUE (narrative_id),
  CONSTRAINT narrative_legacy_publication_status_check
    CHECK (status IN ('grandfathered_publication','withdrawn','migrated')),
  CONSTRAINT narrative_legacy_publication_baseline_state_object_check
    CHECK (jsonb_typeof(baseline_state)='object'),
  CONSTRAINT narrative_legacy_publication_baseline_sha256_check
    CHECK (baseline_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT narrative_legacy_publication_narrative_id_fkey
    FOREIGN KEY (narrative_id) REFERENCES public.narrative(id),
  CONSTRAINT narrative_legacy_publication_source_id_fkey
    FOREIGN KEY (source_id) REFERENCES public.source(id)
);

CREATE TABLE private.narrative_publication_event (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  change_set_id bigint NOT NULL,
  stream_ref uuid NOT NULL,
  stream_version integer NOT NULL,
  event_type text NOT NULL,
  binding_id uuid,
  narrative_id bigint NOT NULL,
  source_id bigint NOT NULL,
  source_record_id uuid,
  legacy_publication_ref uuid,
  decision_basis text NOT NULL,
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  before_state_sha256 text NOT NULL,
  after_state_sha256 text NOT NULL,
  reversed_event_id uuid,
  decided_by uuid,
  decided_by_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT narrative_publication_event_pkey PRIMARY KEY (id),
  CONSTRAINT narrative_publication_event_stream_version_key
    UNIQUE (stream_ref,stream_version),
  CONSTRAINT narrative_publication_event_event_type_check CHECK (
    event_type IN (
      'baseline','draft_created','draft_updated','draft_discarded','published',
      'published_revision','revalidated','withdrawn','legacy_migrated',
      'legacy_withdrawn','reversal'
    )
  ),
  CONSTRAINT narrative_publication_event_stream_version_check
    CHECK (stream_version >= 1),
  CONSTRAINT narrative_publication_event_decision_basis_check
    CHECK (btrim(decision_basis)<>''),
  CONSTRAINT narrative_publication_event_decided_by_name_check
    CHECK (btrim(decided_by_name)<>''),
  CONSTRAINT narrative_publication_event_before_state_object_check
    CHECK (jsonb_typeof(before_state)='object'),
  CONSTRAINT narrative_publication_event_after_state_object_check
    CHECK (jsonb_typeof(after_state)='object'),
  CONSTRAINT narrative_publication_event_before_state_sha256_check
    CHECK (before_state_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT narrative_publication_event_after_state_sha256_check
    CHECK (after_state_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT narrative_publication_event_target_check CHECK (
    (
      binding_id IS NOT NULL
      AND source_record_id IS NOT NULL
      AND legacy_publication_ref IS NULL
    ) OR (
      binding_id IS NULL
      AND source_record_id IS NULL
      AND legacy_publication_ref IS NOT NULL
    )
  ),
  CONSTRAINT narrative_publication_event_reversal_reference_check CHECK (
    (event_type='reversal')=(reversed_event_id IS NOT NULL)
  ),
  CONSTRAINT narrative_publication_event_stream_target_check CHECK (
    stream_ref=coalesce(binding_id,legacy_publication_ref)
  ),
  CONSTRAINT narrative_publication_event_change_set_id_fkey
    FOREIGN KEY (change_set_id) REFERENCES public.change_set(id),
  CONSTRAINT narrative_publication_event_binding_id_fkey
    FOREIGN KEY (binding_id) REFERENCES private.narrative_record_publication(id),
  CONSTRAINT narrative_publication_event_narrative_id_fkey
    FOREIGN KEY (narrative_id) REFERENCES public.narrative(id),
  CONSTRAINT narrative_publication_event_source_id_fkey
    FOREIGN KEY (source_id) REFERENCES public.source(id),
  CONSTRAINT narrative_publication_event_source_record_id_fkey
    FOREIGN KEY (source_record_id) REFERENCES private.source_record(id),
  CONSTRAINT narrative_publication_event_legacy_publication_ref_fkey
    FOREIGN KEY (legacy_publication_ref)
    REFERENCES private.narrative_legacy_publication(legacy_publication_ref),
  CONSTRAINT narrative_publication_event_reversed_event_id_fkey
    FOREIGN KEY (reversed_event_id) REFERENCES private.narrative_publication_event(id)
);

ALTER TABLE private.narrative_legacy_publication
  ADD CONSTRAINT narrative_legacy_publication_latest_event_id_fkey
  FOREIGN KEY (latest_event_id) REFERENCES private.narrative_publication_event(id);

CREATE INDEX narrative_publication_event_change_set_idx
  ON private.narrative_publication_event(change_set_id);
CREATE INDEX narrative_publication_event_binding_idx
  ON private.narrative_publication_event(binding_id) WHERE binding_id IS NOT NULL;
CREATE INDEX narrative_publication_event_narrative_idx
  ON private.narrative_publication_event(narrative_id);
CREATE INDEX narrative_publication_event_source_idx
  ON private.narrative_publication_event(source_id);
CREATE INDEX narrative_publication_event_source_record_idx
  ON private.narrative_publication_event(source_record_id)
  WHERE source_record_id IS NOT NULL;
CREATE INDEX narrative_publication_event_legacy_idx
  ON private.narrative_publication_event(legacy_publication_ref)
  WHERE legacy_publication_ref IS NOT NULL;
CREATE INDEX narrative_publication_event_reversed_idx
  ON private.narrative_publication_event(reversed_event_id)
  WHERE reversed_event_id IS NOT NULL;
CREATE INDEX narrative_legacy_publication_source_idx
  ON private.narrative_legacy_publication(source_id);
CREATE INDEX narrative_legacy_publication_latest_event_idx
  ON private.narrative_legacy_publication(latest_event_id)
  WHERE latest_event_id IS NOT NULL;

CREATE FUNCTION private.validate_narrative_publication_event()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
DECLARE
  v_latest_version integer;
  v_reversed_stream uuid;
  v_reversed_version integer;
  v_target_narrative bigint;
  v_target_source bigint;
  v_target_record uuid;
  v_narrative_source bigint;
  v_record_source bigint;
BEGIN
  IF NEW.binding_id IS NOT NULL THEN
    SELECT binding.narrative_id,binding.source_record_id,
           narrative.source_id,record.source_id
      INTO v_target_narrative,v_target_record,v_narrative_source,v_record_source
      FROM private.narrative_record_publication binding
      JOIN public.narrative narrative ON narrative.id=binding.narrative_id
      JOIN private.source_record record ON record.id=binding.source_record_id
     WHERE binding.id=NEW.binding_id;
    IF NOT FOUND
       OR v_target_narrative IS DISTINCT FROM NEW.narrative_id
       OR v_target_record IS DISTINCT FROM NEW.source_record_id
       OR v_narrative_source IS DISTINCT FROM NEW.source_id
       OR v_record_source IS DISTINCT FROM NEW.source_id THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TARGET_IDENTITY_INVALID';
    END IF;
  ELSE
    SELECT legacy.narrative_id,legacy.source_id,narrative.source_id
      INTO v_target_narrative,v_target_source,v_narrative_source
      FROM private.narrative_legacy_publication legacy
      JOIN public.narrative narrative ON narrative.id=legacy.narrative_id
     WHERE legacy.legacy_publication_ref=NEW.legacy_publication_ref;
    IF NOT FOUND
       OR v_target_narrative IS DISTINCT FROM NEW.narrative_id
       OR v_target_source IS DISTINCT FROM NEW.source_id
       OR v_narrative_source IS DISTINCT FROM NEW.source_id THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TARGET_IDENTITY_INVALID';
    END IF;
  END IF;

  SELECT max(event.stream_version)
    INTO v_latest_version
    FROM private.narrative_publication_event event
   WHERE event.stream_ref=NEW.stream_ref;
  IF NEW.stream_version IS DISTINCT FROM coalesce(v_latest_version,0)+1 THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_STREAM_VERSION_INVALID';
  END IF;

  IF NEW.reversed_event_id IS NOT NULL THEN
    SELECT event.stream_ref,event.stream_version
      INTO v_reversed_stream,v_reversed_version
      FROM private.narrative_publication_event event
     WHERE event.id=NEW.reversed_event_id;
    IF NOT FOUND
       OR v_reversed_stream IS DISTINCT FROM NEW.stream_ref
       OR v_reversed_version>=NEW.stream_version THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_TARGET_INVALID';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE FUNCTION private.reject_narrative_publication_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY';
END
$$;

CREATE FUNCTION private.validate_narrative_legacy_publication()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
DECLARE
  v_latest private.narrative_publication_event%ROWTYPE;
  v_narrative_source bigint;
BEGIN
  SELECT narrative.source_id
    INTO v_narrative_source
    FROM public.narrative narrative
   WHERE narrative.id=NEW.narrative_id;
  IF NOT FOUND OR v_narrative_source IS DISTINCT FROM NEW.source_id THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_TARGET_IDENTITY_INVALID';
  END IF;

  IF TG_OP='UPDATE' AND (
    NEW.legacy_publication_ref IS DISTINCT FROM OLD.legacy_publication_ref
    OR NEW.narrative_id IS DISTINCT FROM OLD.narrative_id
    OR NEW.source_id IS DISTINCT FROM OLD.source_id
    OR NEW.baseline_state IS DISTINCT FROM OLD.baseline_state
    OR NEW.baseline_sha256 IS DISTINCT FROM OLD.baseline_sha256
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_BASELINE_IMMUTABLE';
  END IF;

  IF NEW.latest_event_id IS NOT NULL THEN
    SELECT event.*
      INTO v_latest
      FROM private.narrative_publication_event event
     WHERE event.id=NEW.latest_event_id;
    IF NOT FOUND
       OR v_latest.legacy_publication_ref IS DISTINCT FROM NEW.legacy_publication_ref
       OR v_latest.narrative_id IS DISTINCT FROM NEW.narrative_id
       OR v_latest.source_id IS DISTINCT FROM NEW.source_id
       OR EXISTS (
         SELECT 1
           FROM private.narrative_publication_event later
          WHERE later.stream_ref=NEW.legacy_publication_ref
            AND later.stream_version>v_latest.stream_version
       ) THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_LATEST_EVENT_INVALID';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_narrative_publication_event_validate
  BEFORE INSERT ON private.narrative_publication_event
  FOR EACH ROW EXECUTE FUNCTION private.validate_narrative_publication_event();
CREATE TRIGGER trg_narrative_publication_event_append_only
  BEFORE UPDATE OR DELETE ON private.narrative_publication_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_narrative_publication_event_mutation();
CREATE TRIGGER trg_narrative_legacy_publication_validate
  BEFORE INSERT OR UPDATE ON private.narrative_legacy_publication
  FOR EACH ROW EXECUTE FUNCTION private.validate_narrative_legacy_publication();

ALTER TABLE private.narrative_publication_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.narrative_legacy_publication ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.narrative_publication_event,
  private.narrative_legacy_publication
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.validate_narrative_publication_event(),
  private.reject_narrative_publication_event_mutation(),
  private.validate_narrative_legacy_publication()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.narrative_record_contract_version()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.narrative_record_contract_version()
  TO anon,authenticated,service_role;


-- =====================================================================
-- 2026-08-31: #153 Task 4A -- retired V1 and private V3 evidence ledger
-- =====================================================================
-- V1 remains queryable only as historical ledger data.  Its public writer
-- signatures are deliberately retained as fail-closed tombstones, rather than
-- dropped, so a stale gateway can never silently find a mutating fallback.
CREATE OR REPLACE FUNCTION private.reject_source_scoped_replace_v1_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED';
END
$$;

CREATE OR REPLACE FUNCTION public.red_authorize_source_scoped_replace(
  p_database_name text,p_system_identifier text,p_actor_id uuid,p_nonce uuid,
  p_manifest jsonb,p_dry_run_sha256 text,p_ownership_sha256 text,p_expires_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED';
END
$$;

CREATE OR REPLACE FUNCTION public.red_apply_source_scoped_replace(
  p_authorization_id uuid,p_manifest jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED';
END
$$;

CREATE OR REPLACE FUNCTION public.red_verify_source_scoped_replace(
  p_authorization_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED';
END
$$;

-- The V3 source-operation ledger is deliberately separate from V1.  The
-- deployment FK is added together with the deployment registry in Task 4B;
-- the UUID column exists now so every later authorization can bind it.
CREATE TABLE private.source_scoped_replace_v3_attestation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id bigint NOT NULL REFERENCES public.source(id),
  source_record_id uuid NOT NULL REFERENCES private.source_record(id),
  source_persona_id uuid NOT NULL REFERENCES private.source_persona(id),
  canonical_person_id bigint NOT NULL REFERENCES public.person(id),
  attestation_sha256 text NOT NULL CHECK (attestation_sha256 ~ '^[0-9a-f]{64}$'),
  attestation jsonb NOT NULL CHECK (jsonb_typeof(attestation)='object'),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (source_record_id,source_persona_id,canonical_person_id,attestation_sha256)
);

CREATE TABLE private.source_scoped_replace_v3_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deployment_id uuid NOT NULL,
  deployment_sha256 text NOT NULL CHECK (deployment_sha256 ~ '^[0-9a-f]{64}$'),
  database_name text NOT NULL CHECK (btrim(database_name)<>''),
  system_identifier text NOT NULL CHECK (btrim(system_identifier)<>''),
  actor_id uuid NOT NULL,
  nonce uuid NOT NULL UNIQUE,
  source_id bigint NOT NULL REFERENCES public.source(id),
  manifest jsonb NOT NULL CHECK (jsonb_typeof(manifest)='object'),
  manifest_semantic_sha256 text NOT NULL CHECK (manifest_semantic_sha256 ~ '^[0-9a-f]{64}$'),
  dry_run_semantic_sha256 text NOT NULL CHECK (dry_run_semantic_sha256 ~ '^[0-9a-f]{64}$'),
  ownership_semantic_sha256 text NOT NULL CHECK (ownership_semantic_sha256 ~ '^[0-9a-f]{64}$'),
  artifact_sha256 text NOT NULL CHECK (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE private.source_scoped_replace_v3_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id uuid NOT NULL UNIQUE REFERENCES private.source_scoped_replace_v3_authorization(id),
  receipt jsonb NOT NULL CHECK (jsonb_typeof(receipt)='object'),
  receipt_sha256 text NOT NULL CHECK (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  committed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE private.source_scoped_replace_v3_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES private.source_scoped_replace_v3_batch(id),
  event_type text NOT NULL CHECK (event_type IN ('draft_created','draft_updated')),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object'),
  state_sha256 text NOT NULL CHECK (state_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE private.source_scoped_replace_v3_manifest_artifact (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id uuid NOT NULL REFERENCES private.source_scoped_replace_v3_authorization(id),
  artifact_kind text NOT NULL CHECK (artifact_kind IN ('manifest','dry_run','ownership','writer_snapshot')),
  artifact_sha256 text NOT NULL CHECK (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  artifact jsonb NOT NULL CHECK (jsonb_typeof(artifact) IN ('object','array')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (authorization_id,artifact_kind)
);

CREATE TABLE private.source_scoped_evidence_v3_chain (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id bigint NOT NULL REFERENCES public.source(id),
  source_record_id uuid NOT NULL REFERENCES private.source_record(id),
  source_record_key text NOT NULL CHECK (btrim(source_record_key)<>''),
  source_persona_id uuid NOT NULL REFERENCES private.source_persona(id),
  canonical_person_id bigint NOT NULL REFERENCES public.person(id),
  chain_key text NOT NULL CHECK (chain_key ~ '^[0-9a-f]{64}$'),
  created_by_batch uuid REFERENCES private.source_scoped_replace_v3_batch(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (source_id,chain_key)
);

CREATE TABLE private.source_scoped_evidence_v3_revision (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_chain(id),
  revision integer NOT NULL CHECK (revision>=1),
  predecessor_revision_id uuid REFERENCES private.source_scoped_evidence_v3_revision(id),
  fact_id bigint REFERENCES public.fact(id),
  revision_kind text NOT NULL CHECK (revision_kind IN ('content','tombstone')),
  chain_sha256 text NOT NULL CHECK (chain_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_semantic_sha256 text NOT NULL CHECK (manifest_semantic_sha256 ~ '^[0-9a-f]{64}$'),
  created_by_batch uuid REFERENCES private.source_scoped_replace_v3_batch(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (chain_id,revision),
  UNIQUE (id,chain_id),
  CHECK ((revision_kind='content' AND fact_id IS NOT NULL)
         OR (revision_kind='tombstone' AND fact_id IS NULL)),
  CHECK ((revision=1 AND predecessor_revision_id IS NULL)
         OR (revision>1 AND predecessor_revision_id IS NOT NULL)),
  FOREIGN KEY (predecessor_revision_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id)
);

CREATE TABLE private.source_scoped_evidence_v3_member (
  revision_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_revision(id),
  member_kind text NOT NULL CHECK (member_kind IN ('fact','assertion','citation')),
  member_key text NOT NULL CHECK (btrim(member_key)<>''),
  fact_id bigint REFERENCES public.fact(id),
  assertion_id bigint REFERENCES public.assertion(id),
  citation_id bigint REFERENCES public.citation(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (revision_id,member_kind,member_key),
  CHECK (num_nonnulls(fact_id,assertion_id,citation_id)=1),
  CHECK ((member_kind='fact' AND fact_id IS NOT NULL)
         OR (member_kind='assertion' AND assertion_id IS NOT NULL)
         OR (member_kind='citation' AND citation_id IS NOT NULL))
);
CREATE UNIQUE INDEX source_scoped_evidence_v3_member_fact_uidx
  ON private.source_scoped_evidence_v3_member(fact_id) WHERE fact_id IS NOT NULL;
CREATE UNIQUE INDEX source_scoped_evidence_v3_member_assertion_uidx
  ON private.source_scoped_evidence_v3_member(assertion_id) WHERE assertion_id IS NOT NULL;
CREATE UNIQUE INDEX source_scoped_evidence_v3_member_citation_uidx
  ON private.source_scoped_evidence_v3_member(citation_id) WHERE citation_id IS NOT NULL;

CREATE TABLE private.source_scoped_evidence_v3_publication (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_chain(id),
  revision_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_revision(id),
  decision text NOT NULL CHECK (decision IN ('adopt_baseline','publish','supersede','withdraw')),
  decision_state_sha256 text NOT NULL CHECK (decision_state_sha256 ~ '^[0-9a-f]{64}$'),
  decision_payload jsonb NOT NULL CHECK (jsonb_typeof(decision_payload)='object'),
  decided_by uuid NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  supersedes_publication_id uuid,
  UNIQUE (id,chain_id),
  FOREIGN KEY (revision_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id),
  FOREIGN KEY (supersedes_publication_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_publication(id,chain_id)
);

CREATE TABLE private.source_scoped_evidence_v3_chain_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_chain(id),
  event_type text NOT NULL CHECK (event_type IN (
    'source_revision_created','eligible','published','superseded','withdrawn'
  )),
  predecessor_state_sha256 text CHECK (predecessor_state_sha256 IS NULL OR predecessor_state_sha256 ~ '^[0-9a-f]{64}$'),
  after_state_sha256 text NOT NULL CHECK (after_state_sha256 ~ '^[0-9a-f]{64}$'),
  revision_id uuid,
  publication_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (id,chain_id),
  FOREIGN KEY (revision_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id),
  FOREIGN KEY (publication_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_publication(id,chain_id)
);

CREATE TABLE private.source_scoped_evidence_v3_chain_state (
  chain_id uuid PRIMARY KEY REFERENCES private.source_scoped_evidence_v3_chain(id),
  head_revision_id uuid,
  visible_revision_id uuid,
  state_version integer NOT NULL CHECK (state_version>=1),
  state_sha256 text NOT NULL CHECK (state_sha256 ~ '^[0-9a-f]{64}$'),
  last_event_id uuid NOT NULL UNIQUE,
  FOREIGN KEY (head_revision_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id),
  FOREIGN KEY (visible_revision_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id),
  FOREIGN KEY (last_event_id,chain_id)
    REFERENCES private.source_scoped_evidence_v3_chain_event(id,chain_id)
);

CREATE OR REPLACE FUNCTION private.enforce_source_scoped_evidence_v3_revision_predecessor()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog,private
AS $$
BEGIN
  IF NEW.revision>1 AND NOT EXISTS (
    SELECT 1
      FROM private.source_scoped_evidence_v3_revision predecessor
     WHERE predecessor.id=NEW.predecessor_revision_id
       AND predecessor.chain_id=NEW.chain_id
       AND predecessor.revision=NEW.revision-1
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PREDECESSOR_INVALID';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_source_scoped_evidence_v3_revision_predecessor
  BEFORE INSERT ON private.source_scoped_evidence_v3_revision
  FOR EACH ROW EXECUTE FUNCTION private.enforce_source_scoped_evidence_v3_revision_predecessor();

CREATE OR REPLACE FUNCTION private.reject_source_scoped_evidence_v3_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_APPEND_ONLY';
END
$$;

CREATE TRIGGER trg_source_scoped_replace_v3_attestation_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_replace_v3_attestation
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_replace_v3_batch_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_replace_v3_batch
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_replace_v3_event_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_replace_v3_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_replace_v3_manifest_artifact_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_replace_v3_manifest_artifact
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_chain_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_chain
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_revision_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_revision
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_member_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_member
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_publication_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_publication
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_chain_event_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_chain_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();

ALTER TABLE private.source_scoped_replace_v3_attestation ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_v3_manifest_artifact ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_publication ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_chain_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.source_scoped_replace_v3_attestation,
  private.source_scoped_replace_v3_authorization,
  private.source_scoped_replace_v3_batch,private.source_scoped_replace_v3_event,
  private.source_scoped_replace_v3_manifest_artifact,private.source_scoped_evidence_v3_chain,
  private.source_scoped_evidence_v3_revision,private.source_scoped_evidence_v3_member,
  private.source_scoped_evidence_v3_publication,private.source_scoped_evidence_v3_chain_event,
  private.source_scoped_evidence_v3_chain_state
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.reject_source_scoped_replace_v1_mutation(),
  private.reject_source_scoped_evidence_v3_mutation(),
  private.enforce_source_scoped_evidence_v3_revision_predecessor(),
  public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),
  public.red_verify_source_scoped_replace(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

-- =====================================================================
-- 2026-08-30: #153 Task 4 -- source-scoped replace adapter ledger
-- =====================================================================

CREATE TABLE private.source_scoped_replace_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  database_name text NOT NULL CHECK (btrim(database_name)<>''),
  system_identifier text NOT NULL CHECK (btrim(system_identifier)<>''),
  actor_id uuid NOT NULL,
  nonce uuid NOT NULL UNIQUE,
  source_id bigint NOT NULL REFERENCES public.source(id),
  manifest jsonb NOT NULL CHECK (jsonb_typeof(manifest)='object'),
  manifest_sha256 text NOT NULL CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  dry_run_sha256 text NOT NULL CHECK (dry_run_sha256 ~ '^[0-9a-f]{64}$'),
  ownership_sha256 text NOT NULL CHECK (ownership_sha256 ~ '^[0-9a-f]{64}$'),
  element_scope jsonb NOT NULL CHECK (jsonb_typeof(element_scope)='array'),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.source_scoped_replace_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  authorization_id uuid NOT NULL UNIQUE REFERENCES private.source_scoped_replace_authorization(id),
  receipt jsonb NOT NULL CHECK (jsonb_typeof(receipt)='object'),
  receipt_sha256 text NOT NULL CHECK (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  committed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.source_scoped_replace_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES private.source_scoped_replace_batch(id),
  element_id bigint NOT NULL,
  person_id bigint NOT NULL,
  source_id bigint NOT NULL REFERENCES public.source(id),
  record_key text NOT NULL CHECK (btrim(record_key)<>''),
  event_type text NOT NULL CHECK (event_type IN ('draft_created','draft_updated')),
  text_sha256 text NOT NULL CHECK (text_sha256 ~ '^[0-9a-f]{64}$'),
  state_sha256 text NOT NULL CHECK (state_sha256 ~ '^[0-9a-f]{64}$'),
  UNIQUE(batch_id,element_id)
);

CREATE OR REPLACE FUNCTION private.source_scoped_replace_manifest_sha256(p_manifest jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT encode(extensions.digest(p_manifest::text,'sha256'),'hex')
$$;

CREATE OR REPLACE FUNCTION private.validate_source_scoped_replace_manifest(p_manifest jsonb)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE v_source_id bigint; v_op jsonb; v_key text;
BEGIN
  IF jsonb_typeof(p_manifest)<>'object'
     OR (p_manifest-ARRAY['schema','source_id','record_keys','input_sha256','dry_run_sha256',
                          'ownership_sha256','expected_counts','policy_decisions','narrative_operations',
                          'source_operations'])<>'{}'::jsonb
     OR p_manifest->>'schema'<>'source-scoped-replace-v1'
     OR (p_manifest->>'source_id') !~ '^[1-9][0-9]*$'
     OR jsonb_typeof(p_manifest->'record_keys')<>'array'
     OR jsonb_typeof(p_manifest->'narrative_operations')<>'array'
     OR jsonb_typeof(p_manifest->'source_operations')<>'array'
     OR jsonb_typeof(p_manifest->'expected_counts')<>'object'
     OR jsonb_typeof(p_manifest->'policy_decisions')<>'object' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_MANIFEST_INVALID';
  END IF;
  v_source_id:=(p_manifest->>'source_id')::bigint;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_manifest->'record_keys') key
             WHERE key.value='' OR key.value IS NULL)
     OR (SELECT count(*) FROM jsonb_array_elements_text(p_manifest->'record_keys'))
        <> (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(p_manifest->'record_keys')) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_RECORD_SCOPE_INVALID';
  END IF;
  FOR v_op IN SELECT value FROM jsonb_array_elements(p_manifest->'narrative_operations') LOOP
    IF jsonb_typeof(v_op)<>'object'
       OR (v_op-ARRAY['element_id','person_id','source_id','record_key','text','text_sha256','expected_state_sha256'])<>'{}'::jsonb
       OR (v_op->>'element_id') !~ '^[1-9][0-9]*$'
       OR (v_op->>'person_id') !~ '^[1-9][0-9]*$'
       OR (v_op->>'source_id')::bigint IS DISTINCT FROM v_source_id
       OR coalesce(v_op->>'record_key','')=''
       OR coalesce(v_op->>'text','')=''
       OR coalesce(v_op->>'text_sha256','') !~ '^[0-9a-f]{64}$'
       OR coalesce(v_op->>'expected_state_sha256','') !~ '^[0-9a-f]{64}$'
       OR v_op->>'text_sha256' IS DISTINCT FROM encode(extensions.digest(v_op->>'text','sha256'),'hex')
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_manifest->'record_keys') key
                      WHERE key.value=v_op->>'record_key') THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_NARRATIVE_OPERATION_INVALID';
    END IF;
  END LOOP;
  FOR v_op IN SELECT value FROM jsonb_array_elements(p_manifest->'source_operations') LOOP
    IF jsonb_typeof(v_op)<>'object'
       OR (v_op-ARRAY['action','record_key'])<>'{}'::jsonb
       OR v_op->>'action'<>'replace_owned_facts'
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_manifest->'record_keys') key
                      WHERE key.value=v_op->>'record_key') THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_SOURCE_OPERATION_INVALID';
    END IF;
  END LOOP;
  RETURN v_source_id;
END $$;

CREATE OR REPLACE FUNCTION public.red_authorize_source_scoped_replace(
  p_database_name text,p_system_identifier text,p_actor_id uuid,p_nonce uuid,
  p_manifest jsonb,p_dry_run_sha256 text,p_ownership_sha256 text,p_expires_at timestamptz
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_source_id bigint; v_auth uuid; v_scope jsonb; v_manifest_sha256 text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_CONTRACT_INACTIVE'; END IF;
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' OR auth.uid() IS DISTINCT FROM p_actor_id THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_ROLE_FORBIDDEN';
  END IF;
  IF p_nonce IS NULL OR p_expires_at<=clock_timestamp() OR p_database_name IS DISTINCT FROM current_database()
     OR p_system_identifier IS DISTINCT FROM (SELECT system_identifier::text FROM pg_control_system()) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_AUTHORIZATION_INVALID';
  END IF;
  v_source_id:=private.validate_source_scoped_replace_manifest(p_manifest);
  v_manifest_sha256:=private.source_scoped_replace_manifest_sha256(p_manifest);
  IF p_dry_run_sha256 IS DISTINCT FROM p_manifest->>'dry_run_sha256'
     OR p_ownership_sha256 IS DISTINCT FROM p_manifest->>'ownership_sha256' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_HASH_DRIFT';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-source-scoped-replace:'||v_source_id::text,0));
  SELECT coalesce(jsonb_agg(value ORDER BY (value->>'element_id')::bigint),'[]'::jsonb)
    INTO v_scope FROM jsonb_array_elements(p_manifest->'narrative_operations');
  INSERT INTO private.source_scoped_replace_authorization(
    database_name,system_identifier,actor_id,nonce,source_id,manifest,manifest_sha256,
    dry_run_sha256,ownership_sha256,element_scope,expires_at
  ) VALUES (p_database_name,p_system_identifier,p_actor_id,p_nonce,v_source_id,p_manifest,
            v_manifest_sha256,p_dry_run_sha256,p_ownership_sha256,v_scope,p_expires_at)
  RETURNING id INTO v_auth;
  RETURN v_auth;
EXCEPTION WHEN unique_violation THEN
  SELECT id INTO v_auth FROM private.source_scoped_replace_authorization
   WHERE nonce=p_nonce AND actor_id=p_actor_id AND manifest_sha256=v_manifest_sha256
     AND database_name=p_database_name AND system_identifier=p_system_identifier;
  IF v_auth IS NULL THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_NONCE_REPLAY'; END IF;
  RETURN v_auth;
END $$;

CREATE OR REPLACE FUNCTION public.red_apply_source_scoped_replace(
  p_authorization_id uuid,p_manifest jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_auth private.source_scoped_replace_authorization%ROWTYPE; v_batch private.source_scoped_replace_batch%ROWTYPE;
        v_op jsonb; v_before jsonb; v_result jsonb; v_event_type text; v_events jsonb:='[]'::jsonb; v_receipt jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  SELECT * INTO v_auth FROM private.source_scoped_replace_authorization WHERE id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM v_auth.actor_id
     OR v_auth.database_name IS DISTINCT FROM current_database()
     OR v_auth.system_identifier IS DISTINCT FROM (SELECT system_identifier::text FROM pg_control_system())
     OR v_auth.expires_at<=clock_timestamp()
     OR private.source_scoped_replace_manifest_sha256(p_manifest) IS DISTINCT FROM v_auth.manifest_sha256
     OR p_manifest IS DISTINCT FROM v_auth.manifest THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_AUTHORIZATION_INVALID';
  END IF;
  SELECT * INTO v_batch FROM private.source_scoped_replace_batch WHERE authorization_id=v_auth.id;
  IF FOUND THEN RETURN v_batch.receipt; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-source-scoped-replace:'||v_auth.source_id::text,0));
  PERFORM 1 FROM public.person person WHERE person.id IN (
    SELECT (value->>'person_id')::bigint FROM jsonb_array_elements(v_auth.element_scope)
  ) ORDER BY person.id FOR UPDATE;
  IF (SELECT count(*) FROM public.person person WHERE person.id IN (
    SELECT (value->>'person_id')::bigint FROM jsonb_array_elements(v_auth.element_scope)
  )) <> jsonb_array_length(v_auth.element_scope) THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_PERSON_SCOPE_INVALID'; END IF;
  PERFORM 1 FROM private.source_record record WHERE record.source_id=v_auth.source_id
    AND record.record_key IN (SELECT value FROM jsonb_array_elements_text(v_auth.manifest->'record_keys'))
    ORDER BY record.id FOR UPDATE;
  IF (SELECT count(*) FROM private.source_record record WHERE record.source_id=v_auth.source_id
    AND record.record_key IN (SELECT value FROM jsonb_array_elements_text(v_auth.manifest->'record_keys')))
    <> jsonb_array_length(v_auth.manifest->'record_keys') THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_RECORD_SCOPE_INVALID'; END IF;
  FOR v_op IN SELECT value FROM jsonb_array_elements(v_auth.element_scope) ORDER BY (value->>'element_id')::bigint LOOP
    v_before:=private.narrative_record_state((v_op->>'person_id')::bigint,v_auth.source_id,v_op->>'record_key',true);
    IF v_before->>'state_sha256' IS DISTINCT FROM v_op->>'expected_state_sha256' THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_STATE_STALE'; END IF;
    v_result:=private.mutate_person_narrative_record('upsert',(v_op->>'person_id')::bigint,v_auth.source_id,
      v_op->>'record_key',v_op->>'text',false,v_op->>'expected_state_sha256');
    SELECT event_type INTO v_event_type FROM private.narrative_publication_event
     WHERE id=(v_result->>'event_id')::uuid;
    IF v_event_type NOT IN ('draft_created','draft_updated') THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_NON_DRAFT_EVENT'; END IF;
    v_events:=v_events || jsonb_build_array(jsonb_build_object('element_id',v_op->>'element_id','person_id',v_op->>'person_id',
      'record_key',v_op->>'record_key','event_type',v_event_type,'text_sha256',v_op->>'text_sha256',
      'state_sha256',v_result->>'state_sha256'));
  END LOOP;
  IF current_setting('app.source_scoped_replace_fault',true)='after_source_writes' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_FAULT_INJECTED';
  END IF;
  v_receipt:=jsonb_build_object('schema','source-scoped-replace-receipt-v1','authorization_id',v_auth.id,
    'manifest_sha256',v_auth.manifest_sha256,'database_name',v_auth.database_name,
    'system_identifier',v_auth.system_identifier,'actor_id',v_auth.actor_id,'events',v_events,
    'terminal_status','committed');
  INSERT INTO private.source_scoped_replace_batch(authorization_id,receipt,receipt_sha256)
    VALUES(v_auth.id,v_receipt,private.source_scoped_replace_manifest_sha256(v_receipt)) RETURNING * INTO v_batch;
  INSERT INTO private.source_scoped_replace_event(batch_id,element_id,person_id,source_id,record_key,event_type,text_sha256,state_sha256)
    SELECT v_batch.id,(value->>'element_id')::bigint,(value->>'person_id')::bigint,v_auth.source_id,
      value->>'record_key',value->>'event_type',value->>'text_sha256',value->>'state_sha256'
    FROM jsonb_array_elements(v_events);
  UPDATE private.source_scoped_replace_authorization SET consumed_at=clock_timestamp() WHERE id=v_auth.id;
  RETURN v_receipt;
END $$;

CREATE OR REPLACE FUNCTION public.red_verify_source_scoped_replace(p_authorization_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_batch private.source_scoped_replace_batch%ROWTYPE;
BEGIN
  SELECT batch.* INTO v_batch FROM private.source_scoped_replace_batch batch
   JOIN private.source_scoped_replace_authorization authz ON authz.id=batch.authorization_id
   WHERE batch.authorization_id=p_authorization_id AND auth.uid()=authz.actor_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_RECEIPT_NOT_FOUND'; END IF;
  RETURN jsonb_build_object('receipt',v_batch.receipt,'receipt_sha256',v_batch.receipt_sha256,
    'database_name',current_database(),'system_identifier',(SELECT system_identifier::text FROM pg_control_system()));
END $$;

ALTER TABLE private.source_scoped_replace_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.source_scoped_replace_authorization,private.source_scoped_replace_batch,
  private.source_scoped_replace_event FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.source_scoped_replace_manifest_sha256(jsonb),
  private.validate_source_scoped_replace_manifest(jsonb),
  public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),public.red_verify_source_scoped_replace(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.apply_narrative_record_cutover(
  p_record_candidates_raw text,p_legacy_candidates_raw text,
  p_record_manifest_raw text,p_legacy_manifest_raw text,
  p_inventory_raw text,p_approval_raw text,
  p_nonce uuid,p_expected_database_name text,
  p_expected_system_identifier text
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_record_candidates jsonb;
  v_legacy_candidates jsonb;
  v_record_manifest jsonb;
  v_legacy_manifest jsonb;
  v_inventory jsonb;
  v_approval jsonb;
  v_record_candidates_sha text;
  v_legacy_candidates_sha text;
  v_record_manifest_sha text;
  v_legacy_manifest_sha text;
  v_inventory_sha text;
  v_approval_sha text;
  v_database_name text;
  v_system_identifier text;
  v_candidate_record_ids jsonb;
  v_manifest_record_ids jsonb;
  v_candidate_legacy_ids jsonb;
  v_keep_ids jsonb;
  v_hide_ids jsonb;
  v_live jsonb;
  v_expected jsonb;
  v_live_accepted_identity_count bigint;
  v_live_blocked_record_count bigint;
  v_row jsonb;
  v_state jsonb;
  v_state_sha text;
  v_editor jsonb;
  v_event_id uuid;
  v_change_set_id bigint;
  v_change_sequence regclass;
  v_change_sequence_last bigint;
  v_change_sequence_called boolean;
  v_change_sequence_floor bigint;
  v_change_set_max bigint;
  v_record_results jsonb:='[]'::jsonb;
  v_legacy_results jsonb:='[]'::jsonb;
  v_sequence regclass;
  v_sequence_before bigint;
  v_sequence_floor bigint;
  v_sequence_after bigint;
  v_max_narrative bigint;
  v_max_change_event bigint;
  v_max_publication_event bigint;
  v_result jsonb;
  v_result_sha text;
BEGIN
  IF p_nonce IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_NONCE_REQUIRED';
  END IF;
  IF p_record_candidates_raw IS NULL OR p_legacy_candidates_raw IS NULL
     OR p_record_manifest_raw IS NULL OR p_legacy_manifest_raw IS NULL
     OR p_inventory_raw IS NULL OR p_approval_raw IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_RAW_ARTIFACT_REQUIRED';
  END IF;

  -- Hash the six raw UTF-8 arguments before parsing. Receipt/recovery identity is
  -- the byte identity, never a reserialized jsonb value.
  v_record_candidates_sha:=encode(
    extensions.digest(convert_to(p_record_candidates_raw,'UTF8'),'sha256'),'hex');
  v_legacy_candidates_sha:=encode(
    extensions.digest(convert_to(p_legacy_candidates_raw,'UTF8'),'sha256'),'hex');
  v_record_manifest_sha:=encode(
    extensions.digest(convert_to(p_record_manifest_raw,'UTF8'),'sha256'),'hex');
  v_legacy_manifest_sha:=encode(
    extensions.digest(convert_to(p_legacy_manifest_raw,'UTF8'),'sha256'),'hex');
  v_inventory_sha:=encode(
    extensions.digest(convert_to(p_inventory_raw,'UTF8'),'sha256'),'hex');
  v_approval_sha:=encode(
    extensions.digest(convert_to(p_approval_raw,'UTF8'),'sha256'),'hex');
  BEGIN
    v_record_candidates:=p_record_candidates_raw::jsonb;
    v_legacy_candidates:=p_legacy_candidates_raw::jsonb;
    v_record_manifest:=p_record_manifest_raw::jsonb;
    v_legacy_manifest:=p_legacy_manifest_raw::jsonb;
    v_inventory:=p_inventory_raw::jsonb;
    v_approval:=p_approval_raw::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CUTOVER_ARTIFACT_JSON_INVALID';
  END;

  IF v_record_candidates->>'schema_version'<>'narrative-record-baseline-candidates-v1'
     OR v_legacy_candidates->>'schema_version'<>'narrative-legacy-baseline-candidates-v1'
     OR v_record_manifest->>'schema_version'<>'narrative-record-baseline-manifest-v1'
     OR v_legacy_manifest->>'schema_version'<>'narrative-legacy-baseline-manifest-v1'
     OR v_inventory->>'schema_version'<>'narrative-record-cutover-inventory-v1'
     OR v_approval->>'schema_version'<>'narrative-record-cutover-approval-v1'
     OR jsonb_typeof(v_record_candidates->'rows')<>'array'
     OR jsonb_typeof(v_legacy_candidates->'rows')<>'array'
     OR jsonb_typeof(v_record_manifest->'rows')<>'array'
     OR jsonb_typeof(v_legacy_manifest->'rows')<>'array' THEN
    RAISE EXCEPTION 'CUTOVER_ARTIFACT_SCHEMA_INVALID';
  END IF;

  SELECT current_database(),(pg_control_system()).system_identifier::text
    INTO v_database_name,v_system_identifier;
  IF p_expected_database_name IS DISTINCT FROM v_database_name
     OR p_expected_system_identifier IS DISTINCT FROM v_system_identifier THEN
    RAISE EXCEPTION 'CUTOVER_DATABASE_IDENTITY_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM (VALUES
        (v_record_candidates->'database'),(v_legacy_candidates->'database'),
        (v_record_manifest->'database'),(v_legacy_manifest->'database'),
        (v_inventory->'database'),(v_approval->'database')
      ) artifact(database)
     WHERE artifact.database IS DISTINCT FROM jsonb_build_object(
       'database_name',v_database_name,'system_identifier',v_system_identifier
     )
  ) THEN
    RAISE EXCEPTION 'CUTOVER_ARTIFACT_DATABASE_IDENTITY_MISMATCH';
  END IF;
  IF v_record_manifest->>'record_candidates_sha256' IS DISTINCT FROM
       v_record_candidates_sha
     OR v_legacy_manifest->>'legacy_candidates_sha256' IS DISTINCT FROM
       v_legacy_candidates_sha
     OR v_approval #>> '{input_hashes,record_candidates_sha256}' IS DISTINCT FROM
       v_record_candidates_sha
     OR v_approval #>> '{input_hashes,legacy_candidates_sha256}' IS DISTINCT FROM
       v_legacy_candidates_sha
     OR v_approval #>> '{input_hashes,record_manifest_sha256}' IS DISTINCT FROM
       v_record_manifest_sha
     OR v_approval #>> '{input_hashes,legacy_manifest_sha256}' IS DISTINCT FROM
       v_legacy_manifest_sha
     OR v_approval #>> '{input_hashes,inventory_sha256}' IS DISTINCT FROM
       v_inventory_sha THEN
    RAISE EXCEPTION 'CUTOVER_ARTIFACT_HASH_MISMATCH';
  END IF;

  SELECT coalesce(jsonb_agg(row->'binding_id' ORDER BY row->>'binding_id'),'[]'::jsonb),
         coalesce(jsonb_agg(row-'row_sha256' ORDER BY row->>'binding_id'),'[]'::jsonb)
    INTO v_candidate_record_ids,v_expected
    FROM jsonb_array_elements(v_record_candidates->'rows') row;
  SELECT coalesce(jsonb_agg(row->'binding_id' ORDER BY row->>'binding_id'),'[]'::jsonb),
         coalesce(jsonb_agg(row-'row_sha256' ORDER BY row->>'binding_id'),'[]'::jsonb)
    INTO v_manifest_record_ids,v_live
    FROM jsonb_array_elements(v_record_manifest->'rows') row;
  IF v_manifest_record_ids IS DISTINCT FROM v_candidate_record_ids
     OR v_live IS DISTINCT FROM v_expected
     OR v_approval->'record_approved_ids' IS DISTINCT FROM v_candidate_record_ids THEN
    RAISE EXCEPTION 'CUTOVER_RECORD_MANIFEST_IDENTITY_MISMATCH';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'binding_id',row->'binding_id','row_sha256',row->'row_sha256'
         ) ORDER BY row->>'binding_id'),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_record_candidates->'rows') row;
  IF v_approval->'record_approved_rows' IS DISTINCT FROM v_expected
     OR jsonb_array_length(v_candidate_record_ids)<>
        (SELECT count(DISTINCT row->>'binding_id')
           FROM jsonb_array_elements(v_record_candidates->'rows') row) THEN
    RAISE EXCEPTION 'CUTOVER_RECORD_APPROVAL_IDENTITY_MISMATCH';
  END IF;

  SELECT coalesce(jsonb_agg(row->'narrative_id' ORDER BY (row->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_candidate_legacy_ids
    FROM jsonb_array_elements(v_legacy_candidates->'rows') row;
  SELECT coalesce(jsonb_agg(row->'narrative_id' ORDER BY (row->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_keep_ids
    FROM jsonb_array_elements(v_legacy_manifest->'rows') row;
  v_hide_ids:=coalesce(v_approval->'legacy_hide_ids','[]'::jsonb);
  IF v_approval->'legacy_keep_ids' IS DISTINCT FROM v_keep_ids
     OR jsonb_array_length(v_candidate_legacy_ids)<>
        (SELECT count(DISTINCT (row->>'narrative_id')::bigint)
           FROM jsonb_array_elements(v_legacy_candidates->'rows') row)
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_keep_ids) keep
       JOIN jsonb_array_elements(v_hide_ids) hide ON keep=hide
     )
     OR (SELECT coalesce(jsonb_agg(value ORDER BY (value #>> '{}')::bigint),'[]'::jsonb)
           FROM (
             SELECT value FROM jsonb_array_elements(v_keep_ids)
             UNION ALL
             SELECT value FROM jsonb_array_elements(v_hide_ids)
           ) partition_rows) IS DISTINCT FROM v_candidate_legacy_ids THEN
    RAISE EXCEPTION 'CUTOVER_LEGACY_PARTITION_INVALID';
  END IF;
  SELECT coalesce(jsonb_agg(candidate ORDER BY (candidate->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_legacy_candidates->'rows') candidate
   WHERE candidate->'narrative_id' IN (SELECT value FROM jsonb_array_elements(v_keep_ids));
  IF v_legacy_manifest->'rows' IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'CUTOVER_LEGACY_MANIFEST_IDENTITY_MISMATCH';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'narrative_id',row->'narrative_id',
           'legacy_publication_ref',row->'legacy_publication_ref',
           'row_sha256',row->'row_sha256'
         ) ORDER BY (row->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_legacy_manifest->'rows') row;
  IF v_approval->'legacy_keep_rows' IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'CUTOVER_LEGACY_KEEP_ROWS_MISMATCH';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'narrative_id',row->'narrative_id','row_sha256',row->'row_sha256'
         ) ORDER BY (row->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_legacy_candidates->'rows') row
   WHERE row->'narrative_id' IN (SELECT value FROM jsonb_array_elements(v_hide_ids));
  IF v_approval->'legacy_hide_rows' IS DISTINCT FROM v_expected
     OR (v_approval #>> '{counts,record_approved}')::integer<>
          jsonb_array_length(v_candidate_record_ids)
     OR (v_approval #>> '{counts,legacy_candidates}')::integer<>
          jsonb_array_length(v_candidate_legacy_ids)
     OR (v_approval #>> '{counts,legacy_keep}')::integer<>jsonb_array_length(v_keep_ids)
     OR (v_approval #>> '{counts,legacy_hide}')::integer<>jsonb_array_length(v_hide_ids) THEN
    RAISE EXCEPTION 'CUTOVER_APPROVAL_COUNTS_OR_HIDE_ROWS_MISMATCH';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'source_id',source_count.source_id,
           'record_candidates',source_count.record_candidates,
           'legacy_candidates',source_count.legacy_candidates
         ) ORDER BY source_count.source_id),'[]'::jsonb)
    INTO v_expected
    FROM (
      SELECT candidate.source_id,
             count(*) FILTER (WHERE candidate.kind='record')::integer AS record_candidates,
             count(*) FILTER (WHERE candidate.kind='legacy')::integer AS legacy_candidates
        FROM (
          SELECT (row->>'source_id')::bigint AS source_id,'record'::text AS kind
            FROM jsonb_array_elements(v_record_candidates->'rows') row
          UNION ALL
          SELECT (row->>'source_id')::bigint,'legacy'::text
            FROM jsonb_array_elements(v_legacy_candidates->'rows') row
        ) candidate
       GROUP BY candidate.source_id
    ) source_count;
  IF v_inventory->'record_candidate_ids' IS DISTINCT FROM v_candidate_record_ids
     OR v_inventory->'legacy_candidate_ids' IS DISTINCT FROM v_candidate_legacy_ids
     OR v_inventory->'counts_by_source' IS DISTINCT FROM v_expected
     OR jsonb_typeof(v_inventory->'accepted_identity_count')<>'number'
     OR jsonb_typeof(v_inventory->'identity_blocked_record_count')<>'number'
     OR (v_inventory->>'accepted_identity_count')::bigint<0
     OR (v_inventory->>'identity_blocked_record_count')::bigint<0
     OR v_inventory->'classified_direct_readers' IS DISTINCT FROM jsonb_build_array(
       jsonb_build_object('path','mobile/src/data/about.ts','classification','non_person_control'),
       jsonb_build_object('path','mobile/src/data/haendelser.ts','classification','rls_gated_metadata'),
       jsonb_build_object('path','mobile/src/data/load.ts','classification','v2_public_rpc'),
       jsonb_build_object('path','mobile/src/data/presensLinjer.ts','classification','non_person_control'),
       jsonb_build_object('path','mobile/src/data/publicBioVersions.ts','classification','v2_public_rpc'),
       jsonb_build_object('path','mobile/src/data/redaktionRead.ts','classification','v2_editor_rpc'),
       jsonb_build_object('path','web/src/data/feedAux.ts','classification','v2_public_rpc'),
       jsonb_build_object('path','web/src/data/haendelser.ts','classification','rls_gated_metadata'),
       jsonb_build_object('path','web/src/data/presensLinjer.ts','classification','non_person_control'),
       jsonb_build_object('path','web/src/data/public.ts','classification','v2_public_rpc'),
       jsonb_build_object('path','web/src/data/redaktionRead.ts','classification','v2_editor_rpc')
     ) THEN
    RAISE EXCEPTION 'CUTOVER_INVENTORY_IDENTITY_MISMATCH';
  END IF;

  -- The exclusive gate is acquired before version/live-state validation. The
  -- table locks freeze both existing rows and absence sets through commit.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'CUTOVER_CONTRACT_VERSION_NOT_ONE';
  END IF;
  IF EXISTS (SELECT 1 FROM private.narrative_record_cutover_receipt
              WHERE nonce=p_nonce) THEN
    RAISE EXCEPTION 'CUTOVER_NONCE_ALREADY_USED';
  END IF;
  LOCK TABLE private.narrative_record_publication,
    private.narrative_legacy_publication,
    private.narrative_publication_event IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.narrative,public.change_set IN SHARE ROW EXCLUSIVE MODE;
  -- Canonical publication state also depends on source evidence, current
  -- placements/identity, labels and person policy. SHARE conflicts with every
  -- INSERT/UPDATE/DELETE writer while allowing the cutover's read-only measure.
  LOCK TABLE private.source_record,
    private.source_record_occurrence,
    private.source_rendition,
    private.source_record_anchor_event,
    private.source_record_placement,
    private.source_record_placement_decision,
    private.source_persona,
    private.source_persona_placement,
    private.source_persona_placement_decision,
    private.source_persona_identity_event,
    private.source_persona_identity,
    private.source_record_revision_event,
    public.person,public.source,public.lineage_scheme_entry,public.haendelse
    IN SHARE MODE;

  SELECT count(*)::bigint INTO v_live_accepted_identity_count
    FROM private.source_persona_identity identity_state
    JOIN private.source_persona persona
      ON persona.id=identity_state.source_persona_id
    JOIN public.source source ON source.id=persona.source_id
   WHERE source.slags='DAA-udgave'
     AND identity_state.decision_status='accepted';
  SELECT count(*)::bigint INTO v_live_blocked_record_count
    FROM private.source_record record
    JOIN public.source source ON source.id=record.source_id
   WHERE source.slags='DAA-udgave'
     AND (SELECT count(DISTINCT identity_state.canonical_person_id)
            FROM private.source_record_placement_current record_placement
            JOIN private.source_persona_placement_current persona_placement
              ON persona_placement.record_placement_id=record_placement.id
            JOIN private.source_persona_identity identity_state
              ON identity_state.source_persona_id=persona_placement.source_persona_id
           WHERE record_placement.source_record_id=record.id
             AND record_placement.decision_status='accepted'
             AND persona_placement.decision_status='accepted'
             AND persona_placement.placement_role IN ('principal_member','co_principal')
             AND identity_state.decision_status='accepted')<>1;
  IF v_live_accepted_identity_count IS DISTINCT FROM
       (v_inventory->>'accepted_identity_count')::bigint
     OR v_live_blocked_record_count IS DISTINCT FROM
       (v_inventory->>'identity_blocked_record_count')::bigint THEN
    RAISE EXCEPTION 'CUTOVER_INVENTORY_LIVE_DRIFT';
  END IF;

  SELECT coalesce(jsonb_agg(live.value ORDER BY live.binding_id),'[]'::jsonb)
    INTO v_live
    FROM (
      SELECT binding.id::text AS binding_id,jsonb_build_object(
           'binding_id',binding.id::text,
           'narrative_id',narrative.id,
           'person_id',narrative.subjekt_id,
           'source_id',narrative.source_id,
           'source_kind',source.slags,
           'source_record_id',record.id::text,
           'record_key',record.record_key,
           'status',binding.status,
           'record_label',binding.record_label,
           'citation_label',binding.citation_label,
           'publication_state_sha256',encode(extensions.digest(
             private.narrative_publication_state(
               narrative.subjekt_id,narrative.source_id,record.record_key
             )::text,'sha256'),'hex'),
           'narrative_text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
           'binding_match_count',count(*) OVER (PARTITION BY narrative.id)
         ) AS value
        FROM private.narrative_record_publication binding
        JOIN public.narrative narrative ON narrative.id=binding.narrative_id
        JOIN private.source_record record ON record.id=binding.source_record_id
        JOIN public.source source ON source.id=narrative.source_id
       WHERE source.slags='DAA-udgave'
    ) live;
  SELECT coalesce(jsonb_agg(row-'row_sha256' ORDER BY row->>'binding_id'),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_record_candidates->'rows') row;
  IF v_live IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'CUTOVER_RECORD_LIVE_SET_DRIFT';
  END IF;

  SELECT coalesce(jsonb_agg(narrative.id ORDER BY narrative.id),'[]'::jsonb)
    INTO v_live
    FROM public.narrative narrative
    JOIN public.person person
      ON person.id=narrative.subjekt_id AND narrative.subjekt_type='person'
    JOIN public.source source
      ON source.id=narrative.source_id AND source.slags='DAA-udgave'
   WHERE coalesce(narrative.privat,false)=false
     AND person.levende=false
     AND coalesce(person.privat,false)=false
     AND coalesce(person.staged,false)=false
     AND NOT EXISTS (SELECT 1 FROM private.narrative_record_publication binding
                      WHERE binding.narrative_id=narrative.id)
     AND NOT EXISTS (SELECT 1 FROM private.narrative_legacy_publication legacy
                      WHERE legacy.narrative_id=narrative.id);
  IF v_live IS DISTINCT FROM v_candidate_legacy_ids THEN
    RAISE EXCEPTION 'CUTOVER_LEGACY_LIVE_SET_DRIFT';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'legacy_publication_ref',row->>'legacy_publication_ref',
           'narrative_id',narrative.id,
           'person_id',narrative.subjekt_id,
           'source_id',narrative.source_id,
           'source_kind',source.slags,
           'narrative_text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
           'baseline_sha256',encode(extensions.digest(
             private.narrative_legacy_candidate_publication_state(
               narrative.id,narrative.source_id,(row->>'legacy_publication_ref')::uuid
             )::text,'sha256'),'hex'),
           'binding_match_count',0
         ) ORDER BY narrative.id),'[]'::jsonb)
    INTO v_live
    FROM jsonb_array_elements(v_legacy_candidates->'rows') row
    JOIN public.narrative narrative ON narrative.id=(row->>'narrative_id')::bigint
    JOIN public.source source ON source.id=narrative.source_id;
  SELECT coalesce(jsonb_agg(row-'row_sha256' ORDER BY (row->>'narrative_id')::bigint),'[]'::jsonb)
    INTO v_expected
    FROM jsonb_array_elements(v_legacy_candidates->'rows') row;
  IF v_live IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'CUTOVER_LEGACY_BASELINE_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM private.narrative_publication_event event
     WHERE event.binding_id IN (
       SELECT (row->>'binding_id')::uuid
         FROM jsonb_array_elements(v_record_manifest->'rows') row
     )
  ) THEN
    RAISE EXCEPTION 'CUTOVER_RECORD_STREAM_NOT_EMPTY';
  END IF;

  LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;
  v_change_sequence:=pg_get_serial_sequence('public.change_set','id')::regclass;
  IF v_change_sequence IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_CHANGE_SET_SEQUENCE_MISSING';
  END IF;
  EXECUTE format('SELECT last_value::bigint,is_called FROM %s',v_change_sequence)
    INTO v_change_sequence_last,v_change_sequence_called;
  SELECT coalesce(max(change_set.id),0) INTO v_change_set_max
    FROM public.change_set change_set;
  v_change_sequence_floor:=greatest(
    CASE WHEN v_change_sequence_called
         THEN v_change_sequence_last+1 ELSE v_change_sequence_last END,
    v_change_set_max+1
  );
  EXECUTE format(
    'ALTER SEQUENCE %s RESTART WITH %s',v_change_sequence,v_change_sequence_floor
  );
  INSERT INTO public.change_set(
    actor_navn,actor_rolle,operation,summary,subjekt_synlighed
  ) VALUES (
    'Narrative record cutover','system',
    'narrative_record_contract_cutover',
    format('Narrative record contract cutover %s',p_nonce),'offentlig'
  ) RETURNING id INTO v_change_set_id;

  FOR v_row IN
    SELECT row FROM jsonb_array_elements(v_record_manifest->'rows') row
     ORDER BY row->>'binding_id'
  LOOP
    SELECT private.narrative_publication_state(
             narrative.subjekt_id,narrative.source_id,record.record_key
           )
      INTO v_state
      FROM private.narrative_record_publication binding
      JOIN public.narrative narrative ON narrative.id=binding.narrative_id
      JOIN private.source_record record ON record.id=binding.source_record_id
     WHERE binding.id=(v_row->>'binding_id')::uuid;
    v_state_sha:=encode(extensions.digest(v_state::text,'sha256'),'hex');
    IF v_state_sha IS DISTINCT FROM v_row->>'publication_state_sha256' THEN
      RAISE EXCEPTION 'CUTOVER_RECORD_BASELINE_HASH_DRIFT';
    END IF;
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      v_change_set_id,(v_row->>'binding_id')::uuid,1,'baseline',
      (v_row->>'binding_id')::uuid,(v_row->>'narrative_id')::bigint,
      (v_row->>'source_id')::bigint,(v_row->>'source_record_id')::uuid,
      format('Godkendt baseline ved contract cutover %s',p_nonce),
      v_state,v_state,v_state_sha,v_state_sha,'Narrative record cutover'
    ) RETURNING id INTO v_event_id;
    v_editor:=private.narrative_record_state(
      (v_row->>'person_id')::bigint,(v_row->>'source_id')::bigint,
      v_row->>'record_key',false
    );
    IF v_editor->>'latest_event_id' IS DISTINCT FROM v_event_id::text
       OR v_editor->>'publication_state_sha256' IS DISTINCT FROM v_state_sha THEN
      RAISE EXCEPTION 'CUTOVER_RECORD_POSTSTATE_MISMATCH';
    END IF;
    v_record_results:=v_record_results||jsonb_build_array(jsonb_build_object(
      'binding_id',v_row->>'binding_id','narrative_id',v_row->'narrative_id',
      'event_id',v_event_id,'publication_state_sha256',v_state_sha,
      'state_sha256',v_editor->>'state_sha256'
    ));
  END LOOP;

  FOR v_row IN
    SELECT row FROM jsonb_array_elements(v_legacy_manifest->'rows') row
     ORDER BY (row->>'narrative_id')::bigint
  LOOP
    v_state:=private.narrative_legacy_candidate_publication_state(
      (v_row->>'narrative_id')::bigint,(v_row->>'source_id')::bigint,
      (v_row->>'legacy_publication_ref')::uuid
    );
    v_state_sha:=encode(extensions.digest(v_state::text,'sha256'),'hex');
    IF v_state_sha IS DISTINCT FROM v_row->>'baseline_sha256' THEN
      RAISE EXCEPTION 'CUTOVER_LEGACY_BASELINE_HASH_DRIFT';
    END IF;
    INSERT INTO private.narrative_legacy_publication(
      legacy_publication_ref,narrative_id,source_id,baseline_state,
      baseline_sha256,status
    ) VALUES (
      (v_row->>'legacy_publication_ref')::uuid,
      (v_row->>'narrative_id')::bigint,(v_row->>'source_id')::bigint,
      v_state,v_state_sha,'grandfathered_publication'
    );
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,
      legacy_publication_ref,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      v_change_set_id,(v_row->>'legacy_publication_ref')::uuid,1,'baseline',
      (v_row->>'narrative_id')::bigint,(v_row->>'source_id')::bigint,
      (v_row->>'legacy_publication_ref')::uuid,
      format('Godkendt grandfathered baseline ved contract cutover %s',p_nonce),
      v_state,v_state,v_state_sha,v_state_sha,'Narrative record cutover'
    ) RETURNING id INTO v_event_id;
    UPDATE private.narrative_legacy_publication legacy
       SET latest_event_id=v_event_id
     WHERE legacy.legacy_publication_ref=(v_row->>'legacy_publication_ref')::uuid;
    v_editor:=private.narrative_legacy_state(
      (v_row->>'legacy_publication_ref')::uuid,false
    );
    IF v_editor->>'latest_event_id' IS DISTINCT FROM v_event_id::text
       OR v_editor->>'publication_state_sha256' IS DISTINCT FROM v_state_sha
       OR v_editor->>'baseline_matches' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'CUTOVER_LEGACY_POSTSTATE_MISMATCH';
    END IF;
    v_legacy_results:=v_legacy_results||jsonb_build_array(jsonb_build_object(
      'legacy_publication_ref',v_row->>'legacy_publication_ref',
      'narrative_id',v_row->'narrative_id','event_id',v_event_id,
      'publication_state_sha256',v_state_sha,
      'state_sha256',v_editor->>'state_sha256'
    ));
  END LOOP;

  v_sequence:=pg_get_serial_sequence('public.narrative','id')::regclass;
  IF v_sequence IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_NARRATIVE_SEQUENCE_MISSING';
  END IF;
  EXECUTE format('SELECT last_value::bigint FROM %s',v_sequence)
    INTO v_sequence_before;
  SELECT coalesce(max(narrative.id),0) INTO v_max_narrative
    FROM public.narrative narrative;
  SELECT coalesce(max(greatest(
           CASE WHEN event.row_pk->>'id' ~ '^[0-9]+$'
                THEN (event.row_pk->>'id')::bigint ELSE 0 END,
           CASE WHEN event.foer->>'id' ~ '^[0-9]+$'
                THEN (event.foer->>'id')::bigint ELSE 0 END,
           CASE WHEN event.efter->>'id' ~ '^[0-9]+$'
                THEN (event.efter->>'id')::bigint ELSE 0 END
         )),0)
    INTO v_max_change_event
    FROM public.change_event event
   WHERE event.tabel='narrative';
  SELECT coalesce(max(event.narrative_id),0) INTO v_max_publication_event
    FROM private.narrative_publication_event event;
  v_sequence_floor:=greatest(
    v_sequence_before,v_max_narrative,v_max_change_event,v_max_publication_event
  )+1;
  -- ALTER SEQUENCE RESTART is transactional; setval is not and would make the
  -- gateway's real rollback mode leak sequence state outside the rollback.
  EXECUTE format('ALTER SEQUENCE %s RESTART WITH %s',v_sequence,v_sequence_floor);
  EXECUTE format('SELECT last_value::bigint FROM %s',v_sequence)
    INTO v_sequence_after;
  IF v_sequence_after<v_sequence_before OR v_sequence_after<>v_sequence_floor THEN
    RAISE EXCEPTION 'CUTOVER_NARRATIVE_SEQUENCE_NOT_MONOTONE';
  END IF;

  v_result:=jsonb_build_object(
    'nonce',p_nonce,'database',jsonb_build_object(
      'database_name',v_database_name,'system_identifier',v_system_identifier),
    'contract_version_before',1,'contract_version_after',2,
    'change_set_id',v_change_set_id,
    'record_events',v_record_results,'legacy_events',v_legacy_results,
    'legacy_hidden_ids',v_hide_ids,
    'sequence',jsonb_build_object(
      'before',v_sequence_before,'floor',v_sequence_floor,'after',v_sequence_after),
    'input_hashes',jsonb_build_object(
      'record_candidates_sha256',v_record_candidates_sha,
      'legacy_candidates_sha256',v_legacy_candidates_sha,
      'record_manifest_sha256',v_record_manifest_sha,
      'legacy_manifest_sha256',v_legacy_manifest_sha,
      'inventory_sha256',v_inventory_sha,'approval_sha256',v_approval_sha)
  );
  v_result_sha:=encode(extensions.digest(v_result::text,'sha256'),'hex');
  INSERT INTO private.narrative_record_cutover_receipt(
    nonce,record_candidates_sha256,legacy_candidates_sha256,
    record_manifest_sha256,legacy_manifest_sha256,inventory_sha256,approval_sha256,
    database_name,system_identifier,sequence_before,sequence_floor,sequence_after,
    result,result_sha256
  ) VALUES (
    p_nonce,v_record_candidates_sha,v_legacy_candidates_sha,
    v_record_manifest_sha,v_legacy_manifest_sha,v_inventory_sha,v_approval_sha,
    v_database_name,v_system_identifier,v_sequence_before,v_sequence_floor,
    v_sequence_after,v_result,v_result_sha
  );

  PERFORM private.apply_narrative_record_contract_acl(2);
  -- Version is deliberately the final write in the cutover transaction.
  UPDATE private.narrative_record_contract contract
     SET version=2,changed_at=clock_timestamp()
   WHERE contract.singleton AND contract.version=1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CUTOVER_CONTRACT_VERSION_UPDATE_FAILED';
  END IF;
  RETURN v_result;
END
$$;

REVOKE ALL ON FUNCTION private.apply_narrative_record_cutover(
  text,text,text,text,text,text,uuid,text,text
) FROM PUBLIC,anon,authenticated,service_role;

-- =====================================================================
-- 2026-08-29: #152 Task 2 — canonical narrative publication read model
-- =====================================================================

CREATE INDEX narrative_record_publication_record_state_idx
  ON private.narrative_record_publication(source_record_id,status,created_at,id);
CREATE INDEX source_record_anchor_event_record_state_idx
  ON private.source_record_anchor_event(
    source_record_id,occurrence_id,version DESC,created_at DESC,id DESC
  );
CREATE INDEX source_record_placement_record_state_idx
  ON private.source_record_placement(source_record_id,id);
CREATE INDEX source_persona_placement_record_state_idx
  ON private.source_persona_placement(record_placement_id,source_persona_id,id);
CREATE INDEX source_persona_identity_person_state_idx
  ON private.source_persona_identity(canonical_person_id,source_persona_id)
  WHERE decision_status='accepted';
CREATE INDEX source_record_revision_event_successor_state_idx
  ON private.source_record_revision_event(
    successor_record_id,predecessor_record_id,relation_kind,version DESC
  );

CREATE OR REPLACE FUNCTION private.narrative_record_labels(
  p_source_record_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_source_label text;
  v_record_key text;
  v_record_order integer;
  v_page_label text;
  v_record_label text;
  v_citation_label text;
  v_binding_record_label text;
  v_binding_citation_label text;
  v_placement_count integer;
BEGIN
  SELECT coalesce(source.udgave,source.titel),record.record_key
    INTO v_source_label,v_record_key
    FROM private.source_record record
    JOIN public.source source ON source.id=record.source_id
   WHERE record.id=p_source_record_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_NOT_FOUND';
  END IF;

  SELECT min(interval.page_from),
         string_agg(interval.page_label,', ' ORDER BY interval.page_from,interval.page_to)
    INTO v_record_order,v_page_label
    FROM (
      SELECT DISTINCT occurrence.page_from,occurrence.page_to,
             CASE WHEN occurrence.page_from=occurrence.page_to
                  THEN occurrence.page_from::text
                  ELSE occurrence.page_from::text||'-'||occurrence.page_to::text
              END AS page_label
        FROM private.source_record_anchor_current anchor
        JOIN private.source_record_occurrence occurrence
          ON occurrence.id=anchor.occurrence_id
       WHERE anchor.source_record_id=p_source_record_id
         AND anchor.decision_status='accepted'
    ) interval;

  SELECT count(*),min(entry.label)
    INTO v_placement_count,v_record_label
    FROM private.source_record_placement_current placement
    JOIN public.lineage_scheme_entry entry ON entry.id=placement.scheme_entry_id
   WHERE placement.source_record_id=p_source_record_id
     AND placement.decision_status='accepted';
  IF v_placement_count<>1 THEN
    v_record_label:=v_record_key;
  END IF;
  v_citation_label:=CASE WHEN v_page_label IS NULL THEN NULL
                         ELSE v_source_label||', s. '||v_page_label END;

  SELECT binding.record_label,binding.citation_label
    INTO v_binding_record_label,v_binding_citation_label
    FROM private.narrative_record_publication binding
   WHERE binding.source_record_id=p_source_record_id
     AND binding.status IN ('draft','published')
   ORDER BY binding.created_at,binding.id
   LIMIT 1;
  IF FOUND THEN
    v_record_label:=v_binding_record_label;
    v_citation_label:=v_binding_citation_label;
  END IF;

  RETURN jsonb_build_object(
    'record_order',v_record_order,
    'record_label',v_record_label,
    'citation_label',v_citation_label,
    'side',v_page_label
  );
END
$$;

CREATE OR REPLACE FUNCTION private.narrative_publication_state(
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_record private.source_record%ROWTYPE;
  v_source_year integer;
  v_source_label text;
  v_anchors jsonb;
  v_placements jsonb;
  v_identities jsonb;
  v_identity_people jsonb;
  v_identity_count integer;
  v_identity_matches boolean;
  v_revisions jsonb;
  v_provenance jsonb;
  v_provenance_sha256 text;
  v_binding private.narrative_record_publication%ROWTYPE;
  v_binding_person_id bigint;
  v_binding_source_id bigint;
  v_binding_json jsonb;
  v_narrative_json jsonb;
  v_labels jsonb;
  v_authority_kind text;
  v_eligibility_status text;
  v_blocking_reason text;
  v_publication_status text;
  v_person_levende boolean;
  v_person_private boolean;
  v_person_staged boolean;
  v_narrative_private boolean;
  v_person_publication_allowed boolean;
  v_narrative_publication_allowed boolean;
  v_policy jsonb;
  v_has_haendelse boolean;
  v_has_anchor boolean;
BEGIN
  SELECT * INTO v_record
    FROM private.source_record record
   WHERE record.source_id=p_source_id AND record.record_key=p_record_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_NOT_FOUND';
  END IF;

  SELECT source.aar::integer,coalesce(source.udgave,source.titel)
    INTO v_source_year,v_source_label
    FROM public.source source
   WHERE source.id=p_source_id;
  SELECT person.levende,coalesce(person.privat,false),
         coalesce(person.staged,false)
    INTO v_person_levende,v_person_private,v_person_staged
    FROM public.person person
   WHERE person.id=p_person_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_NOT_FOUND';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'anchor_event_id',anchor.id,
           'anchor_version',anchor.version,
           'occurrence_id',occurrence.id,
           'rendition_id',rendition.id,
           'rendition_content_sha256',rendition.content_sha256,
           'page_from',occurrence.page_from,
           'page_to',occurrence.page_to,
           'physical_fingerprint',occurrence.physical_fingerprint,
           'structural_fingerprint',occurrence.structural_fingerprint
         ) ORDER BY occurrence.page_from,occurrence.page_to,occurrence.id,anchor.id),'[]'::jsonb),
         count(*)>0
    INTO v_anchors,v_has_anchor
    FROM private.source_record_anchor_current anchor
    JOIN private.source_record_occurrence occurrence ON occurrence.id=anchor.occurrence_id
    JOIN private.source_rendition rendition ON rendition.id=occurrence.rendition_id
   WHERE anchor.source_record_id=v_record.id
     AND anchor.decision_status='accepted';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'record_placement_id',placement.id,
           'placement_version',placement.version,
           'scheme_entry_id',placement.scheme_entry_id,
           'scheme_entry_label',entry.label,
           'printed_number',placement.printed_number,
           'generation_local',placement.generation_local,
           'generation_global',placement.generation_global,
           'generation_label_raw',placement.generation_label_raw,
           'kuld_label',placement.kuld_label,
           'section_path',to_jsonb(placement.section_path)
         ) ORDER BY entry.sort_order,placement.id),'[]'::jsonb)
    INTO v_placements
    FROM private.source_record_placement_current placement
    JOIN public.lineage_scheme_entry entry ON entry.id=placement.scheme_entry_id
   WHERE placement.source_record_id=v_record.id
     AND placement.decision_status='accepted';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'source_persona_id',identity_row.source_persona_id,
           'persona_placement_id',identity_row.persona_placement_id,
           'placement_role',identity_row.placement_role,
           'placement_version',identity_row.placement_version,
           'canonical_person_id',identity_row.canonical_person_id,
           'identity_version',identity_row.identity_version
         ) ORDER BY identity_row.canonical_person_id,identity_row.placement_role,
                    identity_row.source_persona_id,identity_row.persona_placement_id),'[]'::jsonb)
    INTO v_identities
    FROM (
      SELECT persona_placement.source_persona_id,
             persona_placement.id AS persona_placement_id,
             persona_placement.placement_role,
             persona_placement.version AS placement_version,
             identity_state.canonical_person_id,
             identity_state.version AS identity_version
        FROM private.source_persona_placement_current persona_placement
        JOIN private.source_record_placement_current record_placement
          ON record_placement.id=persona_placement.record_placement_id
        JOIN private.source_persona_identity identity_state
          ON identity_state.source_persona_id=persona_placement.source_persona_id
       WHERE record_placement.source_record_id=v_record.id
         AND record_placement.decision_status='accepted'
         AND persona_placement.decision_status='accepted'
         AND persona_placement.placement_role IN ('principal_member','co_principal')
         AND identity_state.decision_status='accepted'
    ) identity_row;

  SELECT coalesce(jsonb_agg(person_id ORDER BY person_id),'[]'::jsonb),count(*),
         count(*)=1 AND min(person_id)=p_person_id
    INTO v_identity_people,v_identity_count,v_identity_matches
    FROM (
      SELECT DISTINCT (identity_item->>'canonical_person_id')::bigint AS person_id
        FROM jsonb_array_elements(v_identities) identity_item
    ) people;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'revision_event_id',revision.id,
           'revision_version',revision.version,
           'relation_kind',revision.relation_kind,
           'predecessor_record_id',revision.predecessor_record_id,
           'successor_record_id',revision.successor_record_id
         ) ORDER BY revision.relation_kind,revision.predecessor_record_id,
                    revision.successor_record_id),'[]'::jsonb)
    INTO v_revisions
    FROM private.source_record_revision_current revision
   WHERE revision.decision_status='accepted'
     AND (revision.predecessor_record_id=v_record.id
          OR revision.successor_record_id=v_record.id);

  v_provenance:=jsonb_build_object(
    'anchors',v_anchors,
    'placements',v_placements,
    'identities',v_identities,
    'revisions',v_revisions
  );
  v_provenance_sha256:=encode(extensions.digest(v_provenance::text,'sha256'),'hex');
  v_labels:=private.narrative_record_labels(v_record.id);

  SELECT binding.*
    INTO v_binding
    FROM private.narrative_record_publication binding
   WHERE binding.source_record_id=v_record.id
     AND binding.status IN ('draft','published')
   ORDER BY binding.created_at,binding.id
   LIMIT 1;

  IF FOUND THEN
    SELECT narrative.subjekt_id,narrative.source_id
      INTO v_binding_person_id,v_binding_source_id
      FROM public.narrative narrative
     WHERE narrative.id=v_binding.narrative_id;
    v_binding_json:=jsonb_build_object(
      'binding_id',v_binding.id,
      'narrative_id',v_binding.narrative_id,
      'binding_person_id',v_binding_person_id,
      'status',v_binding.status,
      'record_label',v_binding.record_label,
      'citation_label',v_binding.citation_label,
      'published_at',CASE WHEN v_binding.published_at IS NULL THEN NULL
        ELSE to_char(
          v_binding.published_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        ) END
    );
    SELECT jsonb_build_object(
             'narrative_id',narrative.id,
             'text',narrative.tekst,
             'text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
             'private',coalesce(narrative.privat,false),
             'side',narrative.side,
             'has_haendelse',EXISTS(
               SELECT 1 FROM public.haendelse event WHERE event.narrative_id=narrative.id
             )
           ),coalesce(narrative.privat,false),EXISTS(
             SELECT 1 FROM public.haendelse event WHERE event.narrative_id=narrative.id
           )
      INTO v_narrative_json,v_narrative_private,v_has_haendelse
      FROM public.narrative narrative
     WHERE narrative.id=v_binding.narrative_id;
  ELSE
    v_binding_json:=NULL;
    v_narrative_json:=NULL;
    v_narrative_private:=NULL;
    v_has_haendelse:=false;
  END IF;

  IF v_binding.id IS NOT NULL
     AND (v_binding_person_id IS DISTINCT FROM p_person_id
          OR v_binding_source_id IS DISTINCT FROM p_source_id) THEN
    v_authority_kind:='conflicting_active_binding';
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT';
  ELSIF NOT v_has_anchor THEN
    v_authority_kind:='missing_anchor';
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_RECORD_ANCHOR_REQUIRED';
  ELSIF v_binding.id IS NOT NULL AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_identity_people) item
     WHERE (item #>> '{}')::bigint<>p_person_id
  ) THEN
    v_authority_kind:='conflicting_identity';
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_RECORD_IDENTITY_CONFLICT';
  ELSIF v_binding.id IS NOT NULL THEN
    v_authority_kind:='existing_exact_binding';
    v_eligibility_status:='eligible';
    v_blocking_reason:=NULL;
  ELSIF v_identity_matches THEN
    v_authority_kind:='accepted_identity';
    v_eligibility_status:='eligible';
    v_blocking_reason:=NULL;
  ELSIF v_identity_count=0 THEN
    v_authority_kind:='missing_identity';
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_RECORD_IDENTITY_REQUIRED';
  ELSE
    v_authority_kind:='ambiguous_identity';
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_RECORD_IDENTITY_AMBIGUOUS';
  END IF;

  IF v_binding.id IS NOT NULL AND v_binding_person_id=p_person_id THEN
    v_publication_status:=v_binding.status;
  ELSIF EXISTS (
    SELECT 1
      FROM private.narrative_record_publication withdrawn_binding
      JOIN public.narrative withdrawn_narrative
        ON withdrawn_narrative.id=withdrawn_binding.narrative_id
     WHERE withdrawn_binding.source_record_id=v_record.id
       AND withdrawn_binding.status='withdrawn'
       AND withdrawn_narrative.subjekt_type='person'
       AND withdrawn_narrative.subjekt_id=p_person_id
       AND withdrawn_narrative.source_id=p_source_id
  ) THEN
    v_publication_status:='withdrawn';
  ELSE
    v_publication_status:='none';
  END IF;

  v_person_publication_allowed:=v_person_levende IS FALSE
                                AND NOT v_person_private
                                AND NOT v_person_staged;
  v_narrative_publication_allowed:=v_narrative_json IS NOT NULL
                                   AND NOT coalesce(v_narrative_private,true);
  v_policy:=jsonb_build_object(
    'person_levende',v_person_levende,
    'person_private',v_person_private,
    'person_staged',v_person_staged,
    'narrative_private',v_narrative_private,
    'person_publication_allowed',v_person_publication_allowed,
    'narrative_publication_allowed',v_narrative_publication_allowed,
    'publication_allowed',v_person_publication_allowed
                          AND v_narrative_publication_allowed
  );

  RETURN jsonb_build_object(
    'target',jsonb_build_object(
      'person_id',p_person_id,
      'source_id',p_source_id,
      'record_key',p_record_key,
      'source_record_id',v_record.id,
      'source_record_ref',v_record.public_ref
    ),
    'source',jsonb_build_object(
      'source_year',v_source_year,
      'source_label',v_source_label
    ),
    'provenance',v_provenance,
    'provenance_sha256',v_provenance_sha256,
    'authority',jsonb_build_object(
      'kind',v_authority_kind,
      'identity_people',v_identity_people,
      'eligibility_status',v_eligibility_status,
      'blocking_reason',v_blocking_reason
    ),
    'binding',v_binding_json,
    'narrative',v_narrative_json,
    'publication_status',v_publication_status,
    'labels',v_labels,
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',v_has_haendelse
  );
END
$$;

CREATE OR REPLACE FUNCTION private.narrative_record_state(
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text,
  p_lock boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_record_id uuid;
  v_publication_state jsonb;
  v_publication_state_sha256 text;
  v_active_binding_id uuid;
  v_selected_binding_id uuid;
  v_withdrawn_history jsonb;
  v_latest private.narrative_publication_event%ROWTYPE;
  v_publication_status text;
  v_text_editable boolean;
  v_allowed_actions jsonb;
  v_eligibility_status text;
  v_blocking_reason text;
  v_published_text_sha256 text;
  v_publication_allowed boolean;
  v_editor_state jsonb;
BEGIN
  SELECT record.id INTO v_record_id
    FROM private.source_record record
   WHERE record.source_id=p_source_id AND record.record_key=p_record_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_NOT_FOUND';
  END IF;

  IF p_lock THEN
    PERFORM record.id FROM private.source_record record
     WHERE record.id=v_record_id FOR UPDATE;
    -- Legacy person-policy writers open their audit set before updating person.
    -- After the record-first absence owner, block the legacy allocator before
    -- its max(id)+1 read, then lock person. This makes both writer families use
    -- one compatible audit-before-person order without a stale allocation.
    LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;
    -- levende/privat/staged are part of the semantic policy hash. Serialize
    -- those flags after the record-first absence owner and before projection.
    PERFORM person.id FROM public.person person
     WHERE person.id=p_person_id FOR UPDATE;
    PERFORM binding.id FROM private.narrative_record_publication binding
     WHERE binding.source_record_id=v_record_id
     ORDER BY binding.id FOR UPDATE;
    PERFORM event.id
      FROM private.narrative_publication_event event
     WHERE event.source_record_id=v_record_id
     ORDER BY event.stream_ref,event.stream_version,event.id FOR UPDATE;
    PERFORM narrative.id
      FROM public.narrative narrative
      JOIN private.narrative_record_publication binding
        ON binding.narrative_id=narrative.id
     WHERE binding.source_record_id=v_record_id
     ORDER BY narrative.id FOR UPDATE OF narrative;
    PERFORM anchor.id
      FROM private.source_record_anchor_event anchor
     WHERE anchor.source_record_id=v_record_id
     ORDER BY anchor.occurrence_id,anchor.version,anchor.id FOR UPDATE;
    PERFORM occurrence.id
      FROM private.source_record_occurrence occurrence
      JOIN private.source_record_anchor_current anchor
        ON anchor.occurrence_id=occurrence.id
     WHERE anchor.source_record_id=v_record_id
     ORDER BY occurrence.id FOR UPDATE OF occurrence;
    PERFORM rendition.id
      FROM private.source_rendition rendition
      JOIN private.source_record_occurrence occurrence
        ON occurrence.rendition_id=rendition.id
      JOIN private.source_record_anchor_current anchor
        ON anchor.occurrence_id=occurrence.id
     WHERE anchor.source_record_id=v_record_id
     ORDER BY rendition.id FOR UPDATE OF rendition;
    PERFORM persona.id
      FROM private.source_persona persona
      JOIN private.source_persona_placement persona_placement
        ON persona_placement.source_persona_id=persona.id
      JOIN private.source_record_placement placement
        ON placement.id=persona_placement.record_placement_id
     WHERE placement.source_record_id=v_record_id
     ORDER BY persona.id FOR UPDATE OF persona;
    PERFORM placement.id FROM private.source_record_placement placement
     WHERE placement.source_record_id=v_record_id ORDER BY placement.id FOR UPDATE;
    PERFORM decision.id
      FROM private.source_record_placement_decision decision
      JOIN private.source_record_placement placement ON placement.id=decision.placement_id
     WHERE placement.source_record_id=v_record_id
     ORDER BY decision.placement_id,decision.version,decision.id FOR UPDATE OF decision;
    PERFORM persona_placement.id
      FROM private.source_persona_placement persona_placement
      JOIN private.source_record_placement placement
        ON placement.id=persona_placement.record_placement_id
     WHERE placement.source_record_id=v_record_id
     ORDER BY persona_placement.id FOR UPDATE OF persona_placement;
    PERFORM identity_state.source_persona_id
      FROM private.source_persona_identity identity_state
      JOIN private.source_persona_placement persona_placement
        ON persona_placement.source_persona_id=identity_state.source_persona_id
      JOIN private.source_record_placement placement
        ON placement.id=persona_placement.record_placement_id
     WHERE placement.source_record_id=v_record_id
     ORDER BY identity_state.source_persona_id FOR UPDATE OF identity_state;
    PERFORM revision.id FROM private.source_record_revision_event revision
     WHERE revision.predecessor_record_id=v_record_id
        OR revision.successor_record_id=v_record_id
     ORDER BY revision.id FOR UPDATE;
  END IF;

  v_publication_state:=private.narrative_publication_state(
    p_person_id,p_source_id,p_record_key
  );
  v_publication_state_sha256:=encode(
    extensions.digest(v_publication_state::text,'sha256'),'hex'
  );
  v_active_binding_id:=(v_publication_state #>> '{binding,binding_id}')::uuid;

  -- stream_version is local to one binding and cannot order replacement
  -- streams. Prefer the active stream; after withdrawal/discard order stream
  -- heads by server-owned change-set allocation, never by transaction-start
  -- binding timestamps. Event/id tie breakers keep the result deterministic.
  IF v_active_binding_id IS NOT NULL THEN
    v_selected_binding_id:=v_active_binding_id;
  ELSE
    SELECT binding.id INTO v_selected_binding_id
      FROM private.narrative_record_publication binding
      JOIN public.narrative narrative ON narrative.id=binding.narrative_id
      JOIN LATERAL (
        SELECT event.created_at,event.change_set_id,event.id
          FROM private.narrative_publication_event event
         WHERE event.binding_id=binding.id
         ORDER BY event.stream_version DESC,event.id DESC
         LIMIT 1
      ) stream_head ON true
     WHERE binding.source_record_id=v_record_id
       AND binding.status='withdrawn'
       AND narrative.subjekt_type='person'
       AND narrative.subjekt_id=p_person_id
       AND narrative.source_id=p_source_id
     ORDER BY stream_head.change_set_id DESC,stream_head.created_at DESC,
              stream_head.id DESC,binding.id DESC
     LIMIT 1;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'binding_id',binding.id,
           'narrative_id',binding.narrative_id,
           'status',binding.status,
           'text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
           'record_label',binding.record_label,
           'citation_label',binding.citation_label,
           'created_at',to_char(
             binding.created_at AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
           )
         ) ORDER BY binding.created_at,binding.id),'[]'::jsonb)
    INTO v_withdrawn_history
    FROM private.narrative_record_publication binding
    JOIN public.narrative narrative ON narrative.id=binding.narrative_id
   WHERE binding.source_record_id=v_record_id
     AND binding.status='withdrawn'
     AND narrative.subjekt_type='person'
     AND narrative.subjekt_id=p_person_id
     AND narrative.source_id=p_source_id;

  SELECT event.* INTO v_latest
    FROM private.narrative_publication_event event
    JOIN private.narrative_record_publication binding ON binding.id=event.binding_id
    JOIN public.narrative narrative ON narrative.id=binding.narrative_id
   WHERE binding.source_record_id=v_record_id
     AND narrative.subjekt_type='person'
     AND narrative.subjekt_id=p_person_id
     AND narrative.source_id=p_source_id
     AND event.binding_id=v_selected_binding_id
   ORDER BY event.stream_version DESC,event.created_at DESC,event.id DESC
   LIMIT 1;

  v_publication_status:=v_publication_state->>'publication_status';
  v_eligibility_status:=v_publication_state #>> '{authority,eligibility_status}';
  v_blocking_reason:=v_publication_state #>> '{authority,blocking_reason}';
  v_publication_allowed:=coalesce((
    v_publication_state #>> '{publication_policy,publication_allowed}'
  )::boolean,false);
  IF v_publication_status='published'
     AND (v_latest.id IS NULL
          OR v_latest.after_state_sha256 IS DISTINCT FROM v_publication_state_sha256) THEN
    v_publication_status:='stale_published';
  END IF;

  IF v_blocking_reason IS NOT NULL THEN
    v_text_editable:=false;
    v_allowed_actions:='[]'::jsonb;
  ELSIF v_publication_status IN ('none','withdrawn') THEN
    v_text_editable:=true;
    v_allowed_actions:='["create_draft"]'::jsonb;
  ELSIF v_publication_status='draft' THEN
    v_text_editable:=true;
    v_allowed_actions:=CASE WHEN v_publication_allowed
      THEN '["save_draft","discard_draft","publish"]'::jsonb
      ELSE '["save_draft","discard_draft"]'::jsonb END;
  ELSIF v_publication_status='published' THEN
    v_text_editable:=v_publication_allowed
                     AND NOT (v_publication_state->>'has_haendelse')::boolean;
    v_allowed_actions:=CASE WHEN NOT v_publication_allowed
      THEN '["withdraw"]'::jsonb WHEN v_text_editable
      THEN '["publish_revision","withdraw"]'::jsonb
      ELSE '["withdraw"]'::jsonb END;
  ELSIF v_publication_status='stale_published' THEN
    v_text_editable:=false;
    v_allowed_actions:=CASE WHEN v_publication_allowed
      THEN '["revalidate","withdraw"]'::jsonb
      ELSE '["withdraw"]'::jsonb END;
  ELSE
    v_text_editable:=false;
    v_allowed_actions:='[]'::jsonb;
  END IF;

  IF v_publication_status IN ('published','stale_published') THEN
    v_published_text_sha256:=v_latest.after_state #>> '{narrative,text_sha256}';
  ELSE
    v_published_text_sha256:=NULL;
  END IF;

  v_editor_state:=jsonb_build_object(
    'publication_state',v_publication_state,
    'publication_state_sha256',v_publication_state_sha256,
    'withdrawn_history',v_withdrawn_history,
    'latest_event_id',v_latest.id,
    'latest_event_type',v_latest.event_type,
    'latest_event_version',v_latest.stream_version,
    'latest_before_state_sha256',v_latest.before_state_sha256,
    'latest_after_state_sha256',v_latest.after_state_sha256,
    'publication_status',v_publication_status,
    'text_editable',v_text_editable,
    'allowed_actions',v_allowed_actions,
    'eligibility_status',v_eligibility_status,
    'blocking_reason',v_blocking_reason,
    'published_text_sha256',v_published_text_sha256
  );
  RETURN v_editor_state||jsonb_build_object(
    'state_sha256',encode(extensions.digest(v_editor_state::text,'sha256'),'hex')
  );
END
$$;

CREATE OR REPLACE FUNCTION private.narrative_legacy_publication_state(
  p_legacy_publication_ref uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_state jsonb;
  v_policy jsonb;
  v_person_levende boolean;
  v_person_private boolean;
  v_person_staged boolean;
  v_narrative_private boolean;
  v_has_haendelse boolean;
BEGIN
  SELECT person.levende,coalesce(person.privat,false),
         coalesce(person.staged,false),coalesce(narrative.privat,false),
         EXISTS(SELECT 1 FROM public.haendelse event WHERE event.narrative_id=narrative.id)
    INTO v_person_levende,v_person_private,v_person_staged,
         v_narrative_private,v_has_haendelse
    FROM private.narrative_legacy_publication legacy
    JOIN public.narrative narrative ON narrative.id=legacy.narrative_id
    JOIN public.person person
      ON person.id=narrative.subjekt_id AND narrative.subjekt_type='person'
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_NOT_FOUND';
  END IF;

  v_policy:=jsonb_build_object(
    'person_levende',v_person_levende,
    'person_private',v_person_private,
    'person_staged',v_person_staged,
    'narrative_private',v_narrative_private,
    'person_publication_allowed',v_person_levende IS FALSE
                                 AND NOT v_person_private
                                 AND NOT v_person_staged,
    'narrative_publication_allowed',NOT v_narrative_private,
    'publication_allowed',v_person_levende IS FALSE
                          AND NOT v_person_private
                          AND NOT v_person_staged
                          AND NOT v_narrative_private
  );

  SELECT jsonb_build_object(
           'target',jsonb_build_object(
             'legacy_publication_ref',legacy.legacy_publication_ref,
             'narrative_id',narrative.id,
             'person_id',narrative.subjekt_id,
             'source_id',legacy.source_id
           ),
           'source',jsonb_build_object(
             'source_year',source.aar::integer,
             'source_label',coalesce(source.udgave,source.titel)
           ),
           'narrative',jsonb_build_object(
             'narrative_id',narrative.id,
             'text',narrative.tekst,
             'text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
             'private',coalesce(narrative.privat,false),
             'side',narrative.side,
             'has_haendelse',v_has_haendelse
           ),
           'publication_policy',v_policy,
           'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
           'has_haendelse',v_has_haendelse
         )
    INTO v_state
    FROM private.narrative_legacy_publication legacy
    JOIN public.narrative narrative ON narrative.id=legacy.narrative_id
    JOIN public.source source ON source.id=legacy.source_id
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;
  RETURN v_state;
END
$$;

CREATE OR REPLACE FUNCTION private.narrative_legacy_state(
  p_legacy_publication_ref uuid,
  p_lock boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_legacy private.narrative_legacy_publication%ROWTYPE;
  v_latest private.narrative_publication_event%ROWTYPE;
  v_publication_state jsonb;
  v_publication_state_sha256 text;
  v_baseline_matches boolean;
  v_withdrawal_event_id uuid;
  v_withdrawn_history jsonb;
  v_publication_status text;
  v_allowed_actions jsonb;
  v_eligibility_status text;
  v_blocking_reason text;
  v_editor_state jsonb;
BEGIN
  SELECT * INTO v_legacy
    FROM private.narrative_legacy_publication legacy
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_NOT_FOUND';
  END IF;

  IF p_lock THEN
    PERFORM legacy.legacy_publication_ref
      FROM private.narrative_legacy_publication legacy
     WHERE legacy.legacy_publication_ref=p_legacy_publication_ref FOR UPDATE;
    PERFORM event.id FROM private.narrative_publication_event event
     WHERE event.legacy_publication_ref=p_legacy_publication_ref
     ORDER BY event.stream_version,event.id FOR UPDATE;
    PERFORM narrative.id FROM public.narrative narrative
     WHERE narrative.id=v_legacy.narrative_id FOR UPDATE;
  END IF;

  v_publication_state:=private.narrative_legacy_publication_state(
    p_legacy_publication_ref
  );
  v_publication_state_sha256:=encode(
    extensions.digest(v_publication_state::text,'sha256'),'hex'
  );
  v_baseline_matches:=v_legacy.baseline_state=v_publication_state
                      AND v_legacy.baseline_sha256=encode(
                        extensions.digest(v_legacy.baseline_state::text,'sha256'),'hex'
                      );
  SELECT event.* INTO v_latest
    FROM private.narrative_publication_event event
   WHERE event.legacy_publication_ref=p_legacy_publication_ref
   ORDER BY event.stream_version DESC,event.created_at DESC,event.id DESC LIMIT 1;
  SELECT event.id INTO v_withdrawal_event_id
    FROM private.narrative_publication_event event
   WHERE event.legacy_publication_ref=p_legacy_publication_ref
     AND event.event_type='legacy_withdrawn'
   ORDER BY event.stream_version DESC,event.id DESC LIMIT 1;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'event_id',event.id,
           'event_type',event.event_type,
           'stream_version',event.stream_version,
           'after_state_sha256',event.after_state_sha256
         ) ORDER BY event.stream_version,event.id),'[]'::jsonb)
    INTO v_withdrawn_history
    FROM private.narrative_publication_event event
   WHERE event.legacy_publication_ref=p_legacy_publication_ref
     AND event.event_type='legacy_withdrawn';

  IF v_legacy.status IN ('withdrawn','migrated') THEN
    v_publication_status:='withdrawn';
    v_allowed_actions:='[]'::jsonb;
    v_eligibility_status:=v_legacy.status;
    v_blocking_reason:=NULL;
  ELSIF NOT v_baseline_matches THEN
    v_publication_status:='stale_published';
    v_allowed_actions:='[]'::jsonb;
    v_eligibility_status:='blocked';
    v_blocking_reason:='NARRATIVE_LEGACY_BASELINE_DRIFT';
  ELSE
    v_publication_status:='published';
    v_allowed_actions:='["withdraw_legacy"]'::jsonb;
    v_eligibility_status:='eligible';
    v_blocking_reason:=NULL;
  END IF;

  v_editor_state:=jsonb_build_object(
    'publication_state',v_publication_state,
    'publication_state_sha256',v_publication_state_sha256,
    'ledger_status',v_legacy.status,
    'baseline_sha256',v_legacy.baseline_sha256,
    'baseline_matches',v_baseline_matches,
    'withdrawal_event_id',v_withdrawal_event_id,
    'withdrawn_history',v_withdrawn_history,
    'latest_event_id',v_latest.id,
    'latest_event_type',v_latest.event_type,
    'latest_event_version',v_latest.stream_version,
    'latest_before_state_sha256',v_latest.before_state_sha256,
    'latest_after_state_sha256',v_latest.after_state_sha256,
    'publication_status',v_publication_status,
    'text_editable',false,
    'allowed_actions',v_allowed_actions,
    'eligibility_status',v_eligibility_status,
    'blocking_reason',v_blocking_reason,
    'published_text_sha256',CASE WHEN v_publication_status IN ('published','stale_published')
      THEN v_legacy.baseline_state #>> '{narrative,text_sha256}' ELSE NULL END
  );
  RETURN v_editor_state||jsonb_build_object(
    'state_sha256',encode(extensions.digest(v_editor_state::text,'sha256'),'hex')
  );
END
$$;

REVOKE ALL ON FUNCTION private.narrative_record_labels(uuid),
  private.narrative_publication_state(bigint,bigint,text),
  private.narrative_record_state(bigint,bigint,text,boolean),
  private.narrative_legacy_publication_state(uuid),
  private.narrative_legacy_state(uuid,boolean)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.red_person_narrative_records(
  p_person_id bigint
) RETURNS TABLE(
  person_id bigint,
  source_id bigint,
  source_year integer,
  source_label text,
  provenance_kind text,
  record_key text,
  source_record_ref uuid,
  legacy_publication_ref uuid,
  record_order integer,
  record_label text,
  citation_label text,
  narrative_id bigint,
  narrative_text text,
  narrative_private boolean,
  narrative_side text,
  publication_status text,
  text_editable boolean,
  allowed_actions jsonb,
  withdrawn_history jsonb,
  latest_event_version integer,
  published_text_sha256 text,
  eligibility_status text,
  blocking_reason text,
  state_sha256 text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ROLE_FORBIDDEN';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT record.id,record.source_id,record.record_key
      FROM private.source_record record
     WHERE EXISTS (
       SELECT 1
         FROM private.narrative_record_publication binding
         JOIN public.narrative narrative ON narrative.id=binding.narrative_id
        WHERE binding.source_record_id=record.id
          AND narrative.subjekt_type='person'
          AND narrative.subjekt_id=p_person_id
          AND narrative.source_id=record.source_id
     )
    UNION
    SELECT DISTINCT record.id,record.source_id,record.record_key
      FROM private.source_record record
      JOIN private.source_record_anchor_current anchor
        ON anchor.source_record_id=record.id AND anchor.decision_status='accepted'
      JOIN private.source_record_placement_current record_placement
        ON record_placement.source_record_id=record.id
       AND record_placement.decision_status='accepted'
      JOIN private.source_persona_placement_current persona_placement
        ON persona_placement.record_placement_id=record_placement.id
       AND persona_placement.decision_status='accepted'
       AND persona_placement.placement_role IN ('principal_member','co_principal')
      JOIN private.source_persona_identity identity_state
        ON identity_state.source_persona_id=persona_placement.source_persona_id
       AND identity_state.decision_status='accepted'
       AND identity_state.canonical_person_id=p_person_id
  ), measured AS (
    SELECT candidate.id,candidate.source_id,candidate.record_key,
           private.narrative_record_state(
             p_person_id,candidate.source_id,candidate.record_key,false
           ) AS state
      FROM candidates candidate
  )
  SELECT p_person_id,
         measured.source_id,
         (measured.state #>> '{publication_state,source,source_year}')::integer,
         measured.state #>> '{publication_state,source,source_label}',
         'source_record'::text,
         measured.record_key,
         (measured.state #>> '{publication_state,target,source_record_ref}')::uuid,
         NULL::uuid,
         (measured.state #>> '{publication_state,labels,record_order}')::integer,
         measured.state #>> '{publication_state,labels,record_label}',
         measured.state #>> '{publication_state,labels,citation_label}',
         CASE WHEN measured.state->>'blocking_reason'=
                        'NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
              THEN NULL::bigint
              ELSE (measured.state #>> '{publication_state,narrative,narrative_id}')::bigint
          END,
         CASE WHEN measured.state->>'blocking_reason'=
                        'NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
              THEN NULL::text
              ELSE measured.state #>> '{publication_state,narrative,text}'
          END,
         CASE WHEN measured.state->>'blocking_reason'=
                        'NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
              THEN NULL::boolean
              ELSE (measured.state #>> '{publication_state,narrative,private}')::boolean
          END,
         CASE WHEN measured.state->>'blocking_reason'=
                        'NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
              THEN NULL::text
              ELSE measured.state #>> '{publication_state,narrative,side}'
          END,
         measured.state->>'publication_status',
         (measured.state->>'text_editable')::boolean,
         measured.state->'allowed_actions',
         coalesce((
           SELECT jsonb_agg(jsonb_build_object(
                    'narrative_id',item->'narrative_id',
                    'status',item->'status',
                    'text_sha256',item->'text_sha256',
                    'record_label',item->'record_label',
                    'citation_label',item->'citation_label',
                    'created_at',item->'created_at'
                  ) ORDER BY item->>'created_at',item->>'narrative_id')
             FROM jsonb_array_elements(measured.state->'withdrawn_history') item
         ),'[]'::jsonb),
         (measured.state->>'latest_event_version')::integer,
         measured.state->>'published_text_sha256',
         measured.state->>'eligibility_status',
         measured.state->>'blocking_reason',
         measured.state->>'state_sha256'
    FROM measured
   ORDER BY (measured.state #>> '{publication_state,labels,record_order}')::integer
              NULLS LAST,
            measured.record_key;

  RETURN QUERY
  WITH measured AS (
    SELECT legacy.legacy_publication_ref,legacy.created_at,
           private.narrative_legacy_state(
             legacy.legacy_publication_ref,false
           ) AS state
      FROM private.narrative_legacy_publication legacy
      JOIN public.narrative narrative ON narrative.id=legacy.narrative_id
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=p_person_id
  )
  SELECT p_person_id,
         (measured.state #>> '{publication_state,target,source_id}')::bigint,
         (measured.state #>> '{publication_state,source,source_year}')::integer,
         measured.state #>> '{publication_state,source,source_label}',
         'grandfathered_legacy'::text,
         NULL::text,
         NULL::uuid,
         measured.legacy_publication_ref,
         NULL::integer,
         'Overgangsdata — kildepost ikke fastlagt'::text,
         (measured.state #>> '{publication_state,source,source_label}')
           ||CASE WHEN nullif(
                     measured.state #>> '{publication_state,narrative,side}',''
                   ) IS NULL THEN ''
                 ELSE ', s. '||(
                   measured.state #>> '{publication_state,narrative,side}'
                 ) END,
         (measured.state #>> '{publication_state,narrative,narrative_id}')::bigint,
         measured.state #>> '{publication_state,narrative,text}',
         (measured.state #>> '{publication_state,narrative,private}')::boolean,
         measured.state #>> '{publication_state,narrative,side}',
         measured.state->>'publication_status',
         (measured.state->>'text_editable')::boolean,
         measured.state->'allowed_actions',
         measured.state->'withdrawn_history',
         (measured.state->>'latest_event_version')::integer,
         measured.state->>'published_text_sha256',
         measured.state->>'eligibility_status',
         measured.state->>'blocking_reason',
         measured.state->>'state_sha256'
    FROM measured
   ORDER BY measured.created_at,measured.legacy_publication_ref;
END
$$;

CREATE OR REPLACE FUNCTION public.red_person_narrative_publication_history(
  p_person_id bigint
) RETURNS TABLE(
  event_id uuid,
  change_set_id bigint,
  stream_version integer,
  event_type text,
  source_record_ref uuid,
  legacy_publication_ref uuid,
  before_state_sha256 text,
  after_state_sha256 text,
  before_text text,
  after_text text,
  decided_by_name text,
  created_at timestamptz,
  can_reverse boolean,
  blocking_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ROLE_FORBIDDEN';
  END IF;

  RETURN QUERY
  WITH measured AS (
    SELECT event.*,record.public_ref AS safe_source_record_ref,
           CASE WHEN event.source_record_id IS NOT NULL
                THEN private.narrative_record_state(
                  p_person_id,event.source_id,record.record_key,false
                )
                ELSE private.narrative_legacy_state(
                  event.legacy_publication_ref,false
                )
            END AS state
      FROM private.narrative_publication_event event
      JOIN public.narrative narrative ON narrative.id=event.narrative_id
      LEFT JOIN private.source_record record ON record.id=event.source_record_id
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=p_person_id
  ), classified AS (
    SELECT measured.*,
           measured.state->>'publication_state_sha256' AS current_state_sha256,
           measured.state->>'blocking_reason' AS current_blocking_reason,
           EXISTS(
             SELECT 1 FROM private.narrative_publication_event later
              WHERE later.stream_ref=measured.stream_ref
                AND later.stream_version>measured.stream_version
           ) AS has_later_event,
           EXISTS(
             SELECT 1 FROM private.narrative_publication_event reversal
              WHERE reversal.reversed_event_id=measured.id
           ) AS has_reversal
      FROM measured
  ), reversible AS (
    SELECT classified.*,
           CASE
             WHEN classified.event_type='baseline'
               THEN 'NARRATIVE_PUBLICATION_EVENT_BASELINE_NOT_REVERSIBLE'
             WHEN classified.event_type='reversal'
               THEN 'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE'
             WHEN classified.event_type NOT IN (
                    'draft_created','draft_updated','draft_discarded','published',
                    'published_revision','revalidated','withdrawn','legacy_withdrawn'
                  )
               THEN 'NARRATIVE_PUBLICATION_EVENT_NOT_REVERSIBLE'
             WHEN classified.has_reversal
               THEN 'NARRATIVE_PUBLICATION_EVENT_ALREADY_REVERSED'
             WHEN classified.has_later_event
               THEN 'NARRATIVE_PUBLICATION_EVENT_NOT_LATEST'
             WHEN classified.current_state_sha256 IS DISTINCT FROM
                    classified.after_state_sha256
               THEN 'NARRATIVE_PUBLICATION_EVENT_STATE_DRIFT'
             WHEN classified.current_blocking_reason IS NOT NULL
               THEN classified.current_blocking_reason
             ELSE NULL
            END AS reversal_blocking_reason
      FROM classified
  )
  SELECT reversible.id,
         reversible.change_set_id,
         reversible.stream_version,
         reversible.event_type,
         reversible.safe_source_record_ref,
         reversible.legacy_publication_ref,
         reversible.before_state_sha256,
         reversible.after_state_sha256,
         reversible.before_state #>> '{narrative,text}',
         reversible.after_state #>> '{narrative,text}',
         reversible.decided_by_name,
         reversible.created_at,
         reversible.reversal_blocking_reason IS NULL,
         reversible.reversal_blocking_reason
    FROM reversible
   ORDER BY reversible.created_at,reversible.id;
END
$$;

REVOKE ALL ON FUNCTION public.red_person_narrative_records(bigint),
  public.red_person_narrative_publication_history(bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_person_narrative_records(bigint),
  public.red_person_narrative_publication_history(bigint)
  TO authenticated;

-- =====================================================================
-- 2026-08-29: #152 Task 3 — record-keyed narrative mutation kernel
-- =====================================================================

CREATE OR REPLACE FUNCTION private.mutate_person_narrative_record(
  p_operation text,
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text,
  p_text text,
  p_private boolean,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_actor uuid;
  v_actor_name text;
  v_before_editor jsonb;
  v_before_publication jsonb;
  v_after_editor jsonb;
  v_after_publication jsonb;
  v_before_hash text;
  v_after_hash text;
  v_status text;
  v_blocking_reason text;
  v_source_record_id uuid;
  v_source_record_ref uuid;
  v_binding_id uuid;
  v_narrative_id bigint;
  v_labels jsonb;
  v_latest_event private.narrative_publication_event%ROWTYPE;
  v_event_id uuid;
  v_event_type text;
  v_stream_version integer;
  v_change_set_id bigint;
  v_decision_basis text;
BEGIN
  -- The shared contract gate is deliberately the first lock in every writer.
  PERFORM pg_advisory_xact_lock_shared(
    hashtextextended('daa-narrative-record-contract',0)
  );
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_INACTIVE';
  END IF;

  v_actor:=auth.uid();
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ROLE_FORBIDDEN';
  END IF;
  IF p_operation NOT IN (
    'upsert','publish','revise','revalidate','discard','withdraw'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_OPERATION_INVALID';
  END IF;

  -- Task 2 owns record resolution and the complete record-first lock order.
  v_before_editor:=private.narrative_record_state(
    p_person_id,p_source_id,p_record_key,true
  );
  IF p_expected_state_sha256 IS NULL
     OR p_expected_state_sha256 !~ '^[0-9a-f]{64}$'
     OR p_expected_state_sha256 IS DISTINCT FROM
          v_before_editor->>'state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_STALE';
  END IF;

  v_before_publication:=v_before_editor->'publication_state';
  v_before_hash:=v_before_editor->>'publication_state_sha256';
  v_status:=v_before_editor->>'publication_status';
  v_blocking_reason:=v_before_editor->>'blocking_reason';
  IF v_blocking_reason IS NOT NULL THEN
    RAISE EXCEPTION '%',v_blocking_reason;
  END IF;

  v_source_record_id:=(
    v_before_publication #>> '{target,source_record_id}'
  )::uuid;
  v_source_record_ref:=(
    v_before_publication #>> '{target,source_record_ref}'
  )::uuid;
  v_binding_id:=(
    v_before_publication #>> '{binding,binding_id}'
  )::uuid;
  v_narrative_id:=(
    v_before_publication #>> '{narrative,narrative_id}'
  )::bigint;
  v_labels:=v_before_publication->'labels';
  SELECT event.* INTO v_latest_event
    FROM private.narrative_publication_event event
   WHERE event.id=(v_before_editor->>'latest_event_id')::uuid;

  -- Validate the complete transition before opening its audit set. A rejected
  -- call therefore cannot leave an empty change set behind.
  IF p_operation='upsert' THEN
    IF p_text IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TEXT_REQUIRED';
    END IF;
    IF p_private IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVACY_REQUIRED';
    END IF;
    IF v_status='published' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLISHED_REQUIRES_REVISION';
    ELSIF v_status='stale_published' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_STALE';
    ELSIF v_status='draft' THEN
      v_event_type:='draft_updated';
    ELSIF v_status IN ('none','withdrawn') THEN
      v_event_type:='draft_created';
    ELSE
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
  ELSIF p_operation='publish' THEN
    IF v_status<>'draft' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
    IF NOT coalesce((
      v_before_publication #>> '{publication_policy,publication_allowed}'
    )::boolean,false) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED';
    END IF;
    v_event_type:='published';
  ELSIF p_operation='revise' THEN
    IF p_text IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TEXT_REQUIRED';
    END IF;
    IF coalesce((v_before_publication->>'has_haendelse')::boolean,false) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT';
    END IF;
    IF v_status='stale_published' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_STALE';
    ELSIF v_status<>'published' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
    IF NOT coalesce((
      v_before_publication #>> '{publication_policy,publication_allowed}'
    )::boolean,false) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED';
    END IF;
    v_event_type:='published_revision';
  ELSIF p_operation='revalidate' THEN
    IF v_status<>'stale_published' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
    IF NOT coalesce((
      v_before_publication #>> '{publication_policy,publication_allowed}'
    )::boolean,false) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED';
    END IF;
    IF v_latest_event.id IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_EVENT_MISSING';
    END IF;
    IF v_before_publication #>> '{narrative,text_sha256}' IS DISTINCT FROM
       v_latest_event.after_state #>> '{narrative,text_sha256}' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_TEXT_DRIFT';
    END IF;
    v_event_type:='revalidated';
  ELSIF p_operation='discard' THEN
    IF v_status<>'draft' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
    v_event_type:='draft_discarded';
  ELSIF p_operation='withdraw' THEN
    IF v_status NOT IN ('published','stale_published') THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TRANSITION_INVALID';
    END IF;
    v_event_type:='withdrawn';
  END IF;

  IF v_before_hash IS DISTINCT FROM encode(
       extensions.digest(v_before_publication::text,'sha256'),'hex'
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PRESTATE_HASH_MISMATCH';
  END IF;

  -- A nested caller could otherwise make begin_change_set reuse an unrelated
  -- audit set. The Task-2 lock owner has already serialized change-set
  -- allocation before person-policy rows, following the global writer order.
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_FOREIGN_CHANGE_SET';
  END IF;
  v_decision_basis:=CASE v_event_type
    WHEN 'draft_created' THEN 'Oprettede record-bundet narrativkladde'
    WHEN 'draft_updated' THEN 'Opdaterede record-bundet narrativkladde'
    WHEN 'draft_discarded' THEN 'Kasserede record-bundet narrativkladde'
    WHEN 'published' THEN 'Publicerede record-bundet narrativ'
    WHEN 'published_revision' THEN 'Publicerede revideret record-bundet narrativ'
    WHEN 'revalidated' THEN 'Revaliderede record-bundet narrativpublicering'
    WHEN 'withdrawn' THEN 'Tilbagetrak record-bundet narrativpublicering'
  END;
  v_change_set_id:=public.begin_change_set(
    'narrative_record_'||v_event_type,
    format('%s: person %s, source %s, record %s',
      v_decision_basis,p_person_id,p_source_id,p_record_key),
    'person',p_person_id
  );

  -- Perform exactly the projection mutation selected above, after the change
  -- set is active so narrative INSERT/UPDATE is captured by change_event.
  IF v_event_type='draft_updated' THEN
    UPDATE public.narrative narrative
       SET tekst=p_text,privat=p_private
     WHERE narrative.id=v_narrative_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISSING';
    END IF;
  ELSIF v_event_type='draft_created' THEN
    INSERT INTO public.narrative(
      subjekt_type,subjekt_id,source_id,side,tekst,privat
    ) VALUES (
      'person',p_person_id,p_source_id,v_labels->>'side',p_text,p_private
    ) RETURNING id INTO v_narrative_id;
    INSERT INTO private.narrative_record_publication(
      narrative_id,source_record_id,record_label,citation_label,status
    ) VALUES (
      v_narrative_id,v_source_record_id,v_labels->>'record_label',
      v_labels->>'citation_label','draft'
    ) RETURNING id INTO v_binding_id;
  ELSIF v_event_type='published' THEN
    UPDATE private.narrative_record_publication binding
       SET status='published'
     WHERE binding.id=v_binding_id AND binding.status='draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISMATCH';
    END IF;
  ELSIF v_event_type='published_revision' THEN
    UPDATE public.narrative narrative
       SET tekst=p_text
     WHERE narrative.id=v_narrative_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISSING';
    END IF;
  ELSIF v_event_type='draft_discarded' THEN
    UPDATE private.narrative_record_publication binding
       SET status='withdrawn'
     WHERE binding.id=v_binding_id AND binding.status='draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISMATCH';
    END IF;
  ELSIF v_event_type='withdrawn' THEN
    UPDATE private.narrative_record_publication binding
       SET status='withdrawn'
     WHERE binding.id=v_binding_id AND binding.status='published';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISMATCH';
    END IF;
  END IF;

  v_after_publication:=private.narrative_publication_state(
    p_person_id,p_source_id,p_record_key
  );
  v_after_hash:=encode(
    extensions.digest(v_after_publication::text,'sha256'),'hex'
  );
  SELECT coalesce(nullif(btrim(profile.navn),''),
                  nullif(btrim(profile.email),''),v_actor::text)
    INTO v_actor_name
    FROM public.profiles profile
   WHERE profile.id=v_actor;
  v_actor_name:=coalesce(v_actor_name,v_actor::text);
  SELECT coalesce(max(event.stream_version),0)+1
    INTO v_stream_version
    FROM private.narrative_publication_event event
   WHERE event.stream_ref=v_binding_id;
  INSERT INTO private.narrative_publication_event(
    change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
    source_id,source_record_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name
  ) VALUES (
    v_change_set_id,v_binding_id,v_stream_version,v_event_type,v_binding_id,
    v_narrative_id,p_source_id,v_source_record_id,v_decision_basis,
    v_before_publication,v_after_publication,v_before_hash,v_after_hash,
    v_actor,v_actor_name
  ) RETURNING id INTO v_event_id;

  v_after_editor:=private.narrative_record_state(
    p_person_id,p_source_id,p_record_key,false
  );
  IF v_after_editor->>'latest_event_id' IS DISTINCT FROM v_event_id::text
     OR v_after_editor->>'publication_state_sha256' IS DISTINCT FROM v_after_hash
     OR v_after_editor->>'latest_before_state_sha256' IS DISTINCT FROM v_before_hash
     OR v_after_editor->>'latest_after_state_sha256' IS DISTINCT FROM v_after_hash
     OR v_after_editor->'publication_state' IS DISTINCT FROM v_after_publication THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EVENT_APPEND_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'person_id',p_person_id,
    'source_id',p_source_id,
    'record_key',p_record_key,
    'source_record_ref',v_source_record_ref,
    'event_id',v_event_id,
    'narrative_id',v_narrative_id,
    'status',v_after_editor->>'publication_status',
    'publication_state_sha256',v_after_hash,
    'state_sha256',v_after_editor->>'state_sha256'
  );
END
$$;

CREATE OR REPLACE FUNCTION public.red_upsert_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,
  p_tekst text,p_privat boolean,p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'upsert',p_person_id,p_source_id,p_record_key,p_tekst,p_privat,
    p_expected_state_sha256
  )
$$;

CREATE OR REPLACE FUNCTION public.red_publicer_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'publish',p_person_id,p_source_id,p_record_key,NULL,NULL,
    p_expected_state_sha256
  )
$$;

CREATE OR REPLACE FUNCTION public.red_revider_publiceret_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,p_tekst text,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'revise',p_person_id,p_source_id,p_record_key,p_tekst,NULL,
    p_expected_state_sha256
  )
$$;

CREATE OR REPLACE FUNCTION public.red_revalider_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'revalidate',p_person_id,p_source_id,p_record_key,NULL,NULL,
    p_expected_state_sha256
  )
$$;

CREATE OR REPLACE FUNCTION public.red_kasser_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'discard',p_person_id,p_source_id,p_record_key,NULL,NULL,
    p_expected_state_sha256
  )
$$;

CREATE OR REPLACE FUNCTION public.red_tilbagetraek_person_narrative_record(
  p_person_id bigint,p_source_id bigint,p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$
  SELECT private.mutate_person_narrative_record(
    'withdraw',p_person_id,p_source_id,p_record_key,NULL,NULL,
    p_expected_state_sha256
  )
$$;

REVOKE ALL ON FUNCTION
  private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text),
  public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text),
  public.red_publicer_person_narrative_record(bigint,bigint,text,text),
  public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text),
  public.red_revalider_person_narrative_record(bigint,bigint,text,text),
  public.red_kasser_person_narrative_record(bigint,bigint,text,text),
  public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- =====================================================================
-- 2026-08-29: #152 Task 4 — withdrawal and dedicated event reversal
-- =====================================================================

CREATE OR REPLACE FUNCTION private.withdraw_legacy_narrative(
  p_legacy_publication_ref uuid,
  p_expected_state_sha256 text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_actor uuid;
  v_actor_name text;
  v_before_editor jsonb;
  v_before_publication jsonb;
  v_after_editor jsonb;
  v_after_publication jsonb;
  v_before_hash text;
  v_after_hash text;
  v_legacy private.narrative_legacy_publication%ROWTYPE;
  v_event_id uuid;
  v_stream_version integer;
  v_change_set_id bigint;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(
    hashtextextended('daa-narrative-record-contract',0)
  );
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_INACTIVE';
  END IF;

  v_actor:=auth.uid();
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ROLE_FORBIDDEN';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason)='' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_WITHDRAWAL_REASON_REQUIRED';
  END IF;

  -- Legacy writers serialize audit allocation first, then preserve the
  -- ledger -> stream events -> narrative row order owned by Task 2.
  LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;
  v_before_editor:=private.narrative_legacy_state(
    p_legacy_publication_ref,true
  );
  IF p_expected_state_sha256 IS NULL
     OR p_expected_state_sha256 !~ '^[0-9a-f]{64}$'
     OR p_expected_state_sha256 IS DISTINCT FROM
          v_before_editor->>'state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_STALE';
  END IF;

  SELECT legacy.* INTO STRICT v_legacy
    FROM private.narrative_legacy_publication legacy
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;
  IF v_legacy.status='withdrawn' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_ALREADY_WITHDRAWN';
  ELSIF v_legacy.status<>'grandfathered_publication' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_TRANSITION_INVALID';
  END IF;
  IF NOT coalesce((v_before_editor->>'baseline_matches')::boolean,false) THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_BASELINE_DRIFT';
  END IF;

  v_before_publication:=v_before_editor->'publication_state';
  v_before_hash:=v_before_editor->>'publication_state_sha256';
  IF v_before_hash IS DISTINCT FROM encode(
       extensions.digest(v_before_publication::text,'sha256'),'hex'
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PRESTATE_HASH_MISMATCH';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_FOREIGN_CHANGE_SET';
  END IF;

  v_change_set_id:=public.begin_change_set(
    'narrative_record_legacy_withdrawn',
    format('Tilbagetrak legacy-narrativ %s: %s',
      p_legacy_publication_ref,p_reason),
    'person',(v_before_publication #>> '{target,person_id}')::bigint
  );
  UPDATE private.narrative_legacy_publication legacy
     SET status='withdrawn'
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref
     AND legacy.status='grandfathered_publication';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_PROJECTION_MISMATCH';
  END IF;

  v_after_publication:=private.narrative_legacy_publication_state(
    p_legacy_publication_ref
  );
  v_after_hash:=encode(
    extensions.digest(v_after_publication::text,'sha256'),'hex'
  );
  SELECT coalesce(nullif(btrim(profile.navn),''),
                  nullif(btrim(profile.email),''),v_actor::text)
    INTO v_actor_name
    FROM public.profiles profile
   WHERE profile.id=v_actor;
  v_actor_name:=coalesce(v_actor_name,v_actor::text);
  SELECT coalesce(max(event.stream_version),0)+1
    INTO v_stream_version
    FROM private.narrative_publication_event event
   WHERE event.stream_ref=p_legacy_publication_ref;
  INSERT INTO private.narrative_publication_event(
    change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,
    legacy_publication_ref,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name
  ) VALUES (
    v_change_set_id,p_legacy_publication_ref,v_stream_version,
    'legacy_withdrawn',v_legacy.narrative_id,v_legacy.source_id,
    p_legacy_publication_ref,p_reason,v_before_publication,v_after_publication,
    v_before_hash,v_after_hash,v_actor,v_actor_name
  ) RETURNING id INTO v_event_id;
  UPDATE private.narrative_legacy_publication legacy
     SET latest_event_id=v_event_id
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;

  v_after_editor:=private.narrative_legacy_state(
    p_legacy_publication_ref,false
  );
  IF v_after_editor->>'latest_event_id' IS DISTINCT FROM v_event_id::text
     OR v_after_editor->>'publication_state_sha256' IS DISTINCT FROM v_after_hash
     OR v_after_editor->>'ledger_status' IS DISTINCT FROM 'withdrawn'
     OR v_after_editor->'publication_state' IS DISTINCT FROM v_after_publication THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_WITHDRAWAL_EVENT_APPEND_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'legacy_publication_ref',p_legacy_publication_ref,
    'event_id',v_event_id,
    'narrative_id',v_legacy.narrative_id,
    'source_id',v_legacy.source_id,
    'status',v_after_editor->>'publication_status',
    'publication_state_sha256',v_after_hash,
    'state_sha256',v_after_editor->>'state_sha256'
  );
END
$$;

CREATE OR REPLACE FUNCTION private.reverse_narrative_publication_event(
  p_event_id uuid,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_actor uuid;
  v_actor_name text;
  v_target private.narrative_publication_event%ROWTYPE;
  v_predecessor private.narrative_publication_event%ROWTYPE;
  v_person_id bigint;
  v_record_key text;
  v_source_record_ref uuid;
  v_before_editor jsonb;
  v_before_publication jsonb;
  v_live_hash text;
  v_after_editor jsonb;
  v_after_publication jsonb;
  v_after_hash text;
  v_event_after_state jsonb;
  v_event_after_hash text;
  v_event_id uuid;
  v_stream_version integer;
  v_change_set_id bigint;
  v_would_publish boolean;
  v_binding_status text;
  v_binding_record_label text;
  v_binding_citation_label text;
  v_binding_published_at timestamptz;
  v_narrative_text text;
  v_narrative_private boolean;
  v_narrative_side text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(
    hashtextextended('daa-narrative-record-contract',0)
  );
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_INACTIVE';
  END IF;

  v_actor:=auth.uid();
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ROLE_FORBIDDEN';
  END IF;
  SELECT event.* INTO v_target
    FROM private.narrative_publication_event event
   WHERE event.id=p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_NOT_FOUND';
  END IF;
  SELECT narrative.subjekt_id INTO v_person_id
    FROM public.narrative narrative
   WHERE narrative.id=v_target.narrative_id
     AND narrative.subjekt_type='person';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TARGET_INVALID';
  END IF;

  IF v_target.source_record_id IS NOT NULL THEN
    SELECT record.record_key,record.public_ref
      INTO v_record_key,v_source_record_ref
      FROM private.source_record record
     WHERE record.id=v_target.source_record_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TARGET_INVALID';
    END IF;
    v_before_editor:=private.narrative_record_state(
      v_person_id,v_target.source_id,v_record_key,true
    );
  ELSE
    -- The record path owns record -> audit ordering; legacy has no record
    -- absence owner and therefore takes audit allocation before its ledger.
    LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;
    v_before_editor:=private.narrative_legacy_state(
      v_target.legacy_publication_ref,true
    );
  END IF;

  IF p_expected_state_sha256 IS NULL
     OR p_expected_state_sha256 !~ '^[0-9a-f]{64}$'
     OR p_expected_state_sha256 IS DISTINCT FROM
          v_before_editor->>'state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_STALE';
  END IF;
  SELECT event.* INTO STRICT v_target
    FROM private.narrative_publication_event event
   WHERE event.id=p_event_id;
  SELECT event.* INTO v_predecessor
    FROM private.narrative_publication_event event
   WHERE event.stream_ref=v_target.stream_ref
     AND event.stream_version<v_target.stream_version
   ORDER BY event.stream_version DESC,event.id DESC
   LIMIT 1;
  IF v_target.event_type='baseline' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_BASELINE_NOT_REVERSIBLE';
  ELSIF v_target.event_type='reversal' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE';
  ELSIF EXISTS (
    SELECT 1 FROM private.narrative_publication_event reversal
     WHERE reversal.reversed_event_id=v_target.id
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_ALREADY_REVERSED';
  ELSIF v_before_editor->>'latest_event_id' IS DISTINCT FROM v_target.id::text
        OR EXISTS (
          SELECT 1 FROM private.narrative_publication_event later
           WHERE later.stream_ref=v_target.stream_ref
             AND later.stream_version>v_target.stream_version
        ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_NOT_LATEST';
  ELSIF v_target.event_type NOT IN (
    'draft_created','draft_updated','draft_discarded','published',
    'published_revision','revalidated','withdrawn','legacy_withdrawn'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_NOT_REVERSIBLE';
  END IF;

  v_before_publication:=v_before_editor->'publication_state';
  v_live_hash:=v_before_editor->>'publication_state_sha256';
  v_would_publish:=v_target.event_type IN (
    'published_revision','revalidated','withdrawn','legacy_withdrawn'
  );
  IF v_would_publish AND (
       NOT coalesce((
         v_target.before_state #>> '{publication_policy,publication_allowed}'
       )::boolean,false)
       OR EXISTS (
         SELECT 1 FROM public.person person
          WHERE person.id=v_person_id
            AND (person.levende IS NOT FALSE
                 OR coalesce(person.privat,false)
                 OR coalesce(person.staged,false))
       )
       OR EXISTS (
         SELECT 1 FROM public.narrative narrative
          WHERE narrative.id=v_target.narrative_id
            AND coalesce(narrative.privat,false)
       )
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_POLICY_BLOCKED';
  END IF;
  IF v_live_hash IS DISTINCT FROM v_target.after_state_sha256
     OR v_before_publication IS DISTINCT FROM v_target.after_state THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_STATE_DRIFT';
  END IF;
  IF v_target.before_state_sha256 IS DISTINCT FROM encode(
       extensions.digest(v_target.before_state::text,'sha256'),'hex'
     ) OR v_target.after_state_sha256 IS DISTINCT FROM encode(
       extensions.digest(v_target.after_state::text,'sha256'),'hex'
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_HASH_MISMATCH';
  END IF;
  IF v_target.event_type='legacy_withdrawn' AND (
       v_before_editor->>'ledger_status' IS DISTINCT FROM 'withdrawn'
       OR NOT coalesce((v_before_editor->>'baseline_matches')::boolean,false)
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_BASELINE_DRIFT';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_FOREIGN_CHANGE_SET';
  END IF;

  v_change_set_id:=public.begin_change_set(
    'narrative_record_reversal',
    format('Fortrød narrativpubliceringshændelse %s',p_event_id),
    'person',v_person_id
  );

  IF v_target.event_type='legacy_withdrawn' THEN
    UPDATE private.narrative_legacy_publication legacy
       SET status='grandfathered_publication'
     WHERE legacy.legacy_publication_ref=v_target.legacy_publication_ref
       AND legacy.status='withdrawn';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_PROJECTION_MISMATCH';
    END IF;
  ELSIF v_target.event_type='draft_created' THEN
    UPDATE private.narrative_record_publication binding
       SET status='withdrawn'
     WHERE binding.id=v_target.binding_id
       AND binding.status='draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISMATCH';
    END IF;
  ELSE
    v_binding_status:=v_target.before_state #>> '{binding,status}';
    v_binding_record_label:=v_target.before_state #>> '{binding,record_label}';
    v_binding_citation_label:=v_target.before_state #>> '{binding,citation_label}';
    v_binding_published_at:=CASE
      WHEN v_target.before_state #>> '{binding,published_at}' IS NULL THEN NULL
      ELSE (v_target.before_state #>> '{binding,published_at}')::timestamptz
    END;
    v_narrative_text:=v_target.before_state #>> '{narrative,text}';
    v_narrative_private:=(v_target.before_state #>> '{narrative,private}')::boolean;
    v_narrative_side:=v_target.before_state #>> '{narrative,side}';
    IF v_binding_status IS NULL OR v_narrative_text IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_BEFORE_STATE_INVALID';
    END IF;
    UPDATE private.narrative_record_publication binding
       SET status=v_binding_status,
           record_label=v_binding_record_label,
           citation_label=v_binding_citation_label,
           published_at=v_binding_published_at
     WHERE binding.id=v_target.binding_id
       AND (binding.status,binding.record_label,binding.citation_label,
            binding.published_at) IS DISTINCT FROM
           (v_binding_status,v_binding_record_label,v_binding_citation_label,
            v_binding_published_at);
    UPDATE public.narrative narrative
       SET tekst=v_narrative_text,privat=v_narrative_private,
           side=v_narrative_side
     WHERE narrative.id=v_target.narrative_id
       AND (narrative.tekst,coalesce(narrative.privat,false),narrative.side)
           IS DISTINCT FROM
           (v_narrative_text,v_narrative_private,v_narrative_side);
  END IF;

  IF v_target.source_record_id IS NOT NULL THEN
    v_after_publication:=private.narrative_publication_state(
      v_person_id,v_target.source_id,v_record_key
    );
  ELSE
    v_after_publication:=private.narrative_legacy_publication_state(
      v_target.legacy_publication_ref
    );
  END IF;
  v_after_hash:=encode(
    extensions.digest(v_after_publication::text,'sha256'),'hex'
  );
  IF v_target.event_type NOT IN ('draft_created','revalidated')
     AND (v_after_publication IS DISTINCT FROM v_target.before_state
          OR v_after_hash IS DISTINCT FROM v_target.before_state_sha256) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_RESTORE_MISMATCH';
  END IF;
  IF v_target.event_type='draft_created' AND NOT EXISTS (
    SELECT 1
      FROM private.narrative_record_publication binding
      JOIN public.narrative narrative ON narrative.id=binding.narrative_id
     WHERE binding.id=v_target.binding_id
       AND binding.narrative_id=v_target.narrative_id
       AND binding.status='withdrawn'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_RESTORE_MISMATCH';
  END IF;
  IF v_target.event_type='revalidated'
     AND v_after_publication IS DISTINCT FROM v_target.after_state THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_RESTORE_MISMATCH';
  END IF;

  -- Usually the target's semantic before-state is the restored authority. A
  -- revalidation, or a withdrawal entered from stale_published, did not have a
  -- matching predecessor attestation: reversing it must restore that older
  -- attestation, not silently turn current provenance drift into a fresh
  -- publication decision. The projection itself still restores target.before.
  v_event_after_state:=v_target.before_state;
  v_event_after_hash:=v_target.before_state_sha256;
  IF v_target.event_type IN ('revalidated','withdrawn')
     AND v_predecessor.id IS NOT NULL
     AND v_predecessor.after_state_sha256 IS DISTINCT FROM
           v_target.before_state_sha256 THEN
    IF v_predecessor.after_state_sha256 IS DISTINCT FROM encode(
         extensions.digest(v_predecessor.after_state::text,'sha256'),'hex'
       ) THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_HASH_MISMATCH';
    END IF;
    v_event_after_state:=v_predecessor.after_state;
    v_event_after_hash:=v_predecessor.after_state_sha256;
  END IF;
  SELECT coalesce(nullif(btrim(profile.navn),''),
                  nullif(btrim(profile.email),''),v_actor::text)
    INTO v_actor_name
    FROM public.profiles profile
   WHERE profile.id=v_actor;
  v_actor_name:=coalesce(v_actor_name,v_actor::text);
  SELECT coalesce(max(event.stream_version),0)+1
    INTO v_stream_version
    FROM private.narrative_publication_event event
   WHERE event.stream_ref=v_target.stream_ref;
  INSERT INTO private.narrative_publication_event(
    change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
    source_id,source_record_id,legacy_publication_ref,decision_basis,
    before_state,after_state,before_state_sha256,after_state_sha256,
    reversed_event_id,decided_by,decided_by_name
  ) VALUES (
    v_change_set_id,v_target.stream_ref,v_stream_version,'reversal',
    v_target.binding_id,v_target.narrative_id,v_target.source_id,
    v_target.source_record_id,v_target.legacy_publication_ref,
    format('Fortrød narrativpubliceringshændelse %s',p_event_id),
    v_before_publication,v_event_after_state,v_live_hash,v_event_after_hash,
    v_target.id,v_actor,v_actor_name
  ) RETURNING id INTO v_event_id;
  IF v_target.legacy_publication_ref IS NOT NULL THEN
    UPDATE private.narrative_legacy_publication legacy
       SET latest_event_id=v_event_id
     WHERE legacy.legacy_publication_ref=v_target.legacy_publication_ref;
  END IF;

  IF v_target.source_record_id IS NOT NULL THEN
    v_after_editor:=private.narrative_record_state(
      v_person_id,v_target.source_id,v_record_key,false
    );
  ELSE
    v_after_editor:=private.narrative_legacy_state(
      v_target.legacy_publication_ref,false
    );
  END IF;
  IF v_after_editor->>'latest_event_id' IS DISTINCT FROM v_event_id::text THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_REVERSAL_EVENT_APPEND_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'person_id',v_person_id,
    'source_id',v_target.source_id,
    'source_record_ref',v_source_record_ref,
    'legacy_publication_ref',v_target.legacy_publication_ref,
    'event_id',v_event_id,
    'reversed_event_id',v_target.id,
    'narrative_id',v_target.narrative_id,
    'status',v_after_editor->>'publication_status',
    'publication_state_sha256',v_after_hash,
    'state_sha256',v_after_editor->>'state_sha256'
  );
END
$$;

CREATE OR REPLACE FUNCTION public.red_tilbagetraek_legacy_narrative(
  p_legacy_publication_ref uuid,
  p_expected_state_sha256 text,
  p_begrundelse text
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
  SELECT private.withdraw_legacy_narrative(
    p_legacy_publication_ref,p_expected_state_sha256,p_begrundelse
  )
$$;

CREATE OR REPLACE FUNCTION public.red_fortryd_person_narrative_publication_event(
  p_event_id uuid,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
  SELECT private.reverse_narrative_publication_event(
    p_event_id,p_expected_state_sha256
  )
$$;

REVOKE ALL ON FUNCTION
  private.withdraw_legacy_narrative(uuid,text,text),
  private.reverse_narrative_publication_event(uuid,text),
  public.red_tilbagetraek_legacy_narrative(uuid,text,text),
  public.red_fortryd_person_narrative_publication_event(uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- =====================================================================
-- 2026-08-29: #152 Task 5 — event-gated public narrative reads
-- =====================================================================

CREATE OR REPLACE FUNCTION public.person_daa_narrative_publication_allowed(
  p_narrative_id bigint
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_narrative public.narrative%ROWTYPE;
  v_source_kind text;
  v_binding private.narrative_record_publication%ROWTYPE;
  v_record private.source_record%ROWTYPE;
  v_legacy private.narrative_legacy_publication%ROWTYPE;
  v_event private.narrative_publication_event%ROWTYPE;
  v_state jsonb;
  v_state_sha256 text;
BEGIN
  SELECT narrative.* INTO v_narrative
    FROM public.narrative narrative
   WHERE narrative.id=p_narrative_id;
  IF NOT FOUND
     OR coalesce(v_narrative.privat,false)
     OR NOT public.entitet_offentlig(
       v_narrative.subjekt_type,v_narrative.subjekt_id
     ) THEN
    RETURN false;
  END IF;

  -- Version 1 is deliberately identical to the historical narrative RLS gate.
  IF public.narrative_record_contract_version()<2 THEN
    RETURN true;
  END IF;

  SELECT source.slags INTO v_source_kind
    FROM public.source source WHERE source.id=v_narrative.source_id;
  IF v_narrative.subjekt_type IS DISTINCT FROM 'person'
     OR v_source_kind IS DISTINCT FROM 'DAA-udgave' THEN
    RETURN true;
  END IF;

  SELECT binding.* INTO v_binding
    FROM private.narrative_record_publication binding
   WHERE binding.narrative_id=p_narrative_id;
  IF FOUND THEN
    IF v_binding.status IS DISTINCT FROM 'published' THEN
      RETURN false;
    END IF;
    SELECT record.* INTO v_record
      FROM private.source_record record
     WHERE record.id=v_binding.source_record_id;
    IF NOT FOUND OR v_record.source_id IS DISTINCT FROM v_narrative.source_id THEN
      RETURN false;
    END IF;
    SELECT event.* INTO v_event
      FROM private.narrative_publication_event event
     WHERE event.binding_id=v_binding.id
     ORDER BY event.stream_version DESC,event.id DESC
     LIMIT 1;
    IF NOT FOUND
       OR v_event.stream_ref IS DISTINCT FROM v_binding.id
       OR v_event.narrative_id IS DISTINCT FROM p_narrative_id
       OR v_event.source_id IS DISTINCT FROM v_narrative.source_id
       OR v_event.source_record_id IS DISTINCT FROM v_binding.source_record_id
       OR v_event.legacy_publication_ref IS NOT NULL THEN
      RETURN false;
    END IF;
    v_state:=private.narrative_publication_state(
      v_narrative.subjekt_id,v_narrative.source_id,v_record.record_key
    );
    v_state_sha256:=encode(
      extensions.digest(v_state::text,'sha256'),'hex'
    );
    RETURN v_event.after_state_sha256=encode(
             extensions.digest(v_event.after_state::text,'sha256'),'hex'
           )
       AND v_event.after_state_sha256=v_state_sha256
       AND v_event.after_state=v_state
       AND v_state->>'publication_status'='published'
       AND (v_state #>> '{publication_policy,publication_allowed}')::boolean;
  END IF;

  SELECT legacy.* INTO v_legacy
    FROM private.narrative_legacy_publication legacy
   WHERE legacy.narrative_id=p_narrative_id;
  IF NOT FOUND
     OR v_legacy.status IS DISTINCT FROM 'grandfathered_publication'
     OR v_legacy.source_id IS DISTINCT FROM v_narrative.source_id
     OR v_legacy.latest_event_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT event.* INTO v_event
    FROM private.narrative_publication_event event
   WHERE event.legacy_publication_ref=v_legacy.legacy_publication_ref
   ORDER BY event.stream_version DESC,event.id DESC
   LIMIT 1;
  IF NOT FOUND
     OR v_event.id IS DISTINCT FROM v_legacy.latest_event_id
     OR v_event.stream_ref IS DISTINCT FROM v_legacy.legacy_publication_ref
     OR v_event.binding_id IS NOT NULL
     OR v_event.source_record_id IS NOT NULL
     OR v_event.narrative_id IS DISTINCT FROM p_narrative_id
     OR v_event.source_id IS DISTINCT FROM v_narrative.source_id THEN
    RETURN false;
  END IF;
  v_state:=private.narrative_legacy_publication_state(
    v_legacy.legacy_publication_ref
  );
  v_state_sha256:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  RETURN v_legacy.baseline_sha256=encode(
           extensions.digest(v_legacy.baseline_state::text,'sha256'),'hex'
         )
     AND v_legacy.baseline_sha256=v_state_sha256
     AND v_legacy.baseline_state=v_state
     AND v_event.after_state_sha256=encode(
           extensions.digest(v_event.after_state::text,'sha256'),'hex'
         )
     AND v_event.after_state_sha256=v_state_sha256
     AND v_event.after_state=v_state
     AND (v_state #>> '{publication_policy,publication_allowed}')::boolean;
EXCEPTION WHEN OTHERS THEN
  -- Public eligibility is a fail-closed boolean capability. Any malformed or
  -- ambiguous semantic state remains private instead of leaking an exception.
  RETURN false;
END
$$;

CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions_v2(
  p_person_ids bigint[]
) RETURNS TABLE(
  person_id bigint,
  source_id bigint,
  source_year integer,
  record_order integer,
  source_record_ref uuid,
  source_label text,
  record_label text,
  narrative_text text,
  citation_label text,
  provenance_kind text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  IF public.narrative_record_contract_version()<2 THEN
    RETURN QUERY
    WITH public_rows AS (
      SELECT narrative.subjekt_id AS row_person_id,
             narrative.source_id AS row_source_id,
             source.aar::integer AS row_source_year,
             (labels #>> '{record_order}')::integer AS row_record_order,
             record.public_ref AS row_source_record_ref,
             coalesce(
               nullif(btrim(source.udgave),''),
               nullif(btrim(source.titel),''),'DAA-udgave'
             ) AS row_source_label,
             binding.record_label AS row_record_label,
             narrative.tekst AS row_narrative_text,
             binding.citation_label AS row_citation_label,
             'source_record'::text AS row_provenance_kind,
             0 AS row_kind
        FROM public.narrative narrative
        JOIN public.source source
          ON source.id=narrative.source_id AND source.slags='DAA-udgave'
        JOIN private.narrative_record_publication binding
          ON binding.narrative_id=narrative.id AND binding.status='published'
        JOIN private.source_record record ON record.id=binding.source_record_id
        CROSS JOIN LATERAL private.narrative_record_labels(record.id)
          AS label_state(labels)
       WHERE narrative.subjekt_type='person'
         AND narrative.subjekt_id=ANY(p_person_ids)
         AND public.person_daa_narrative_publication_allowed(narrative.id)
      UNION ALL
      SELECT narrative.subjekt_id,narrative.source_id,source.aar::integer,NULL::integer,
             NULL::uuid,
             coalesce(
               nullif(btrim(source.udgave),''),
               nullif(btrim(source.titel),''),'DAA-udgave'
             ),
             'Overgangsdata'::text,narrative.tekst,
             coalesce(nullif(btrim(narrative.side),''),'')::text,
             'legacy_narrative'::text,1
        FROM public.narrative narrative
        JOIN public.source source
          ON source.id=narrative.source_id AND source.slags='DAA-udgave'
       WHERE narrative.subjekt_type='person'
         AND narrative.subjekt_id=ANY(p_person_ids)
         AND public.person_daa_narrative_publication_allowed(narrative.id)
         AND NOT EXISTS (
           SELECT 1 FROM private.narrative_record_publication binding
            WHERE binding.narrative_id=narrative.id
         )
    )
    SELECT row_person_id,row_source_id,row_source_year,row_record_order,
           row_source_record_ref,row_source_label,row_record_label,
           row_narrative_text,row_citation_label,row_provenance_kind
      FROM public_rows
     ORDER BY row_source_year DESC NULLS LAST,row_source_id,row_kind,
              row_record_order NULLS LAST,row_record_label,row_source_record_ref;
    RETURN;
  END IF;

  RETURN QUERY
  WITH public_rows AS (
    SELECT (event.after_state #>> '{target,person_id}')::bigint AS row_person_id,
           (event.after_state #>> '{target,source_id}')::bigint AS row_source_id,
           (event.after_state #>> '{source,source_year}')::integer AS row_source_year,
           (event.after_state #>> '{labels,record_order}')::integer AS row_record_order,
           (event.after_state #>> '{target,source_record_ref}')::uuid
             AS row_source_record_ref,
           event.after_state #>> '{source,source_label}' AS row_source_label,
           event.after_state #>> '{labels,record_label}' AS row_record_label,
           event.after_state #>> '{narrative,text}' AS row_narrative_text,
           event.after_state #>> '{labels,citation_label}' AS row_citation_label,
           'source_record'::text AS row_provenance_kind,
           0 AS row_kind,
           (event.after_state #>> '{target,source_record_ref}')::uuid
             AS row_stable_tiebreak
      FROM public.narrative narrative
      JOIN public.source source
        ON source.id=narrative.source_id AND source.slags='DAA-udgave'
      JOIN private.narrative_record_publication binding
        ON binding.narrative_id=narrative.id
      JOIN LATERAL (
        SELECT publication_event.after_state
          FROM private.narrative_publication_event publication_event
         WHERE publication_event.binding_id=binding.id
         ORDER BY publication_event.stream_version DESC,publication_event.id DESC
         LIMIT 1
      ) event ON true
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=ANY(p_person_ids)
       AND public.person_daa_narrative_publication_allowed(narrative.id)
    UNION ALL
    SELECT (event.after_state #>> '{target,person_id}')::bigint,
           (event.after_state #>> '{target,source_id}')::bigint,
           (event.after_state #>> '{source,source_year}')::integer,
           NULL::integer,NULL::uuid,
           event.after_state #>> '{source,source_label}',
           'Overgangsdata'::text,
           event.after_state #>> '{narrative,text}',
           (event.after_state #>> '{source,source_label}')
             ||CASE
                 WHEN nullif(event.after_state #>> '{narrative,side}','') IS NULL
                   THEN ''
                 ELSE ', s. '||(event.after_state #>> '{narrative,side}')
               END,
           'legacy_narrative'::text,1,legacy.legacy_publication_ref
      FROM public.narrative narrative
      JOIN public.source source
        ON source.id=narrative.source_id AND source.slags='DAA-udgave'
      JOIN private.narrative_legacy_publication legacy
        ON legacy.narrative_id=narrative.id
      JOIN private.narrative_publication_event event
        ON event.id=legacy.latest_event_id
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=ANY(p_person_ids)
       AND public.person_daa_narrative_publication_allowed(narrative.id)
  )
  SELECT row_person_id,row_source_id,row_source_year,row_record_order,
         row_source_record_ref,row_source_label,row_record_label,
         row_narrative_text,row_citation_label,row_provenance_kind
    FROM public_rows
   ORDER BY row_source_year DESC NULLS LAST,row_source_id,row_kind,
            row_record_order NULLS LAST,row_record_label,row_source_record_ref,
            row_stable_tiebreak;
END
$$;

CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions(
  p_person_ids bigint[]
) RETURNS TABLE(
  person_id bigint,
  record_ref uuid,
  source_label text,
  record_label text,
  narrative_text text,
  citation_label text,
  provenance_kind text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
BEGIN
  IF public.narrative_record_contract_version()<2 THEN
    RETURN QUERY
    SELECT narrative.subjekt_id,binding.record_ref,
           coalesce(
             nullif(btrim(source.udgave),''),
             nullif(btrim(source.titel),''),'DAA-udgave'
           ),
           binding.record_label,narrative.tekst,binding.citation_label,
           'source_record'::text
      FROM public.narrative narrative
      JOIN public.person person ON person.id=narrative.subjekt_id
      JOIN public.source source
        ON source.id=narrative.source_id AND source.slags='DAA-udgave'
      JOIN private.narrative_record_publication binding
        ON binding.narrative_id=narrative.id AND binding.status='published'
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=ANY(p_person_ids)
       AND coalesce(narrative.privat,false)=false
       AND person.levende=false
       AND coalesce(person.privat,false)=false
       AND coalesce(person.staged,false)=false
       AND public.person_daa_narrative_publication_allowed(narrative.id)
    UNION ALL
    SELECT narrative.subjekt_id,NULL::uuid,
           coalesce(
             nullif(btrim(source.udgave),''),
             nullif(btrim(source.titel),''),'DAA-udgave'
           ),
           'Overgangsdata'::text,narrative.tekst,
           coalesce(nullif(btrim(narrative.side),''),'')::text,
           'legacy_narrative'::text
      FROM public.narrative narrative
      JOIN public.person person ON person.id=narrative.subjekt_id
      JOIN public.source source
        ON source.id=narrative.source_id AND source.slags='DAA-udgave'
     WHERE narrative.subjekt_type='person'
       AND narrative.subjekt_id=ANY(p_person_ids)
       AND coalesce(narrative.privat,false)=false
       AND person.levende=false
       AND coalesce(person.privat,false)=false
       AND coalesce(person.staged,false)=false
       AND public.person_daa_narrative_publication_allowed(narrative.id)
       AND NOT EXISTS (
         SELECT 1 FROM private.narrative_record_publication binding
          WHERE binding.narrative_id=narrative.id
       );
    RETURN;
  END IF;

  RETURN QUERY
  SELECT narrative.subjekt_id,binding.record_ref,
         event.after_state #>> '{source,source_label}',
         event.after_state #>> '{labels,record_label}',
         event.after_state #>> '{narrative,text}',
         event.after_state #>> '{labels,citation_label}',
         'source_record'::text
    FROM public.narrative narrative
    JOIN public.source source
      ON source.id=narrative.source_id AND source.slags='DAA-udgave'
    JOIN private.narrative_record_publication binding
      ON binding.narrative_id=narrative.id
    JOIN LATERAL (
      SELECT publication_event.after_state
        FROM private.narrative_publication_event publication_event
       WHERE publication_event.binding_id=binding.id
       ORDER BY publication_event.stream_version DESC,publication_event.id DESC
       LIMIT 1
    ) event ON true
   WHERE narrative.subjekt_type='person'
     AND narrative.subjekt_id=ANY(p_person_ids)
     AND public.person_daa_narrative_publication_allowed(narrative.id)
  UNION ALL
  SELECT narrative.subjekt_id,NULL::uuid,
         event.after_state #>> '{source,source_label}',
         'Overgangsdata'::text,
         event.after_state #>> '{narrative,text}',
         coalesce(nullif(event.after_state #>> '{narrative,side}',''),'')::text,
         'legacy_narrative'::text
    FROM public.narrative narrative
    JOIN public.source source
      ON source.id=narrative.source_id AND source.slags='DAA-udgave'
    JOIN private.narrative_legacy_publication legacy
      ON legacy.narrative_id=narrative.id
    JOIN private.narrative_publication_event event
      ON event.id=legacy.latest_event_id
   WHERE narrative.subjekt_type='person'
     AND narrative.subjekt_id=ANY(p_person_ids)
     AND public.person_daa_narrative_publication_allowed(narrative.id);
END
$$;

REVOKE ALL ON FUNCTION
  public.person_daa_narrative_publication_allowed(bigint),
  public.public_person_bio_source_versions(bigint[]),
  public.public_person_bio_source_versions_v2(bigint[])
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.person_daa_narrative_publication_allowed(bigint),
  public.public_person_bio_source_versions(bigint[]),
  public.public_person_bio_source_versions_v2(bigint[])
  TO anon,authenticated;

-- =====================================================================
-- 2026-08-29: #152 Task 7 — atomic narrative contract cutover
-- =====================================================================

CREATE TABLE private.narrative_record_contract (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  version integer NOT NULL CHECK (version IN (1,2)),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private.narrative_record_contract(singleton,version)
VALUES (true,1);

CREATE OR REPLACE FUNCTION public.narrative_record_contract_version()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
  SELECT contract.version
    FROM private.narrative_record_contract contract
   WHERE contract.singleton
$$;

CREATE OR REPLACE FUNCTION private.narrative_legacy_candidate_publication_state(
  p_narrative_id bigint,
  p_source_id bigint,
  p_legacy_publication_ref uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_state jsonb;
  v_policy jsonb;
  v_person_levende boolean;
  v_person_private boolean;
  v_person_staged boolean;
  v_narrative_private boolean;
  v_has_haendelse boolean;
BEGIN
  SELECT person.levende,coalesce(person.privat,false),
         coalesce(person.staged,false),coalesce(narrative.privat,false),
         EXISTS(SELECT 1 FROM public.haendelse event
                 WHERE event.narrative_id=narrative.id)
    INTO v_person_levende,v_person_private,v_person_staged,
         v_narrative_private,v_has_haendelse
    FROM public.narrative narrative
    JOIN public.person person
      ON person.id=narrative.subjekt_id AND narrative.subjekt_type='person'
   WHERE narrative.id=p_narrative_id
     AND narrative.source_id=p_source_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_CANDIDATE_NOT_FOUND';
  END IF;

  v_policy:=jsonb_build_object(
    'person_levende',v_person_levende,
    'person_private',v_person_private,
    'person_staged',v_person_staged,
    'narrative_private',v_narrative_private,
    'person_publication_allowed',v_person_levende IS FALSE
                                 AND NOT v_person_private
                                 AND NOT v_person_staged,
    'narrative_publication_allowed',NOT v_narrative_private,
    'publication_allowed',v_person_levende IS FALSE
                          AND NOT v_person_private
                          AND NOT v_person_staged
                          AND NOT v_narrative_private
  );

  SELECT jsonb_build_object(
           'target',jsonb_build_object(
             'legacy_publication_ref',p_legacy_publication_ref,
             'narrative_id',narrative.id,
             'person_id',narrative.subjekt_id,
             'source_id',p_source_id
           ),
           'source',jsonb_build_object(
             'source_year',source.aar::integer,
             'source_label',coalesce(source.udgave,source.titel)
           ),
           'narrative',jsonb_build_object(
             'narrative_id',narrative.id,
             'text',narrative.tekst,
             'text_sha256',encode(extensions.digest(narrative.tekst,'sha256'),'hex'),
             'private',coalesce(narrative.privat,false),
             'side',narrative.side,
             'has_haendelse',v_has_haendelse
           ),
           'publication_policy',v_policy,
           'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
           'has_haendelse',v_has_haendelse
         )
    INTO v_state
    FROM public.narrative narrative
    JOIN public.source source ON source.id=p_source_id
   WHERE narrative.id=p_narrative_id
     AND narrative.source_id=p_source_id;
  RETURN v_state;
END
$$;

CREATE OR REPLACE FUNCTION private.narrative_legacy_publication_state(
  p_legacy_publication_ref uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
DECLARE
  v_narrative_id bigint;
  v_source_id bigint;
BEGIN
  SELECT legacy.narrative_id,legacy.source_id
    INTO v_narrative_id,v_source_id
    FROM private.narrative_legacy_publication legacy
   WHERE legacy.legacy_publication_ref=p_legacy_publication_ref;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_NOT_FOUND';
  END IF;
  RETURN private.narrative_legacy_candidate_publication_state(
    v_narrative_id,v_source_id,p_legacy_publication_ref
  );
END
$$;

CREATE TABLE private.narrative_record_cutover_receipt (
  nonce uuid PRIMARY KEY,
  record_candidates_sha256 text NOT NULL CHECK (record_candidates_sha256 ~ '^[0-9a-f]{64}$'),
  legacy_candidates_sha256 text NOT NULL CHECK (legacy_candidates_sha256 ~ '^[0-9a-f]{64}$'),
  record_manifest_sha256 text NOT NULL CHECK (record_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  legacy_manifest_sha256 text NOT NULL CHECK (legacy_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  inventory_sha256 text NOT NULL CHECK (inventory_sha256 ~ '^[0-9a-f]{64}$'),
  approval_sha256 text NOT NULL CHECK (approval_sha256 ~ '^[0-9a-f]{64}$'),
  database_name text NOT NULL CHECK (btrim(database_name)<>''),
  system_identifier text NOT NULL CHECK (btrim(system_identifier)<>''),
  sequence_before bigint NOT NULL,
  sequence_floor bigint NOT NULL,
  sequence_after bigint NOT NULL,
  result jsonb NOT NULL CHECK (jsonb_typeof(result)='object'),
  result_sha256 text NOT NULL CHECK (result_sha256 ~ '^[0-9a-f]{64}$'),
  committed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION private.reject_narrative_record_cutover_receipt_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'NARRATIVE_RECORD_CUTOVER_RECEIPT_APPEND_ONLY';
END
$$;
CREATE TRIGGER trg_narrative_record_cutover_receipt_append_only
  BEFORE UPDATE OR DELETE ON private.narrative_record_cutover_receipt
  FOR EACH ROW EXECUTE FUNCTION private.reject_narrative_record_cutover_receipt_mutation();

ALTER TABLE private.narrative_record_contract ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.narrative_record_cutover_receipt ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION private.apply_narrative_record_contract_acl(
  p_version integer
) RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$
DECLARE
  v_signature text;
  v_new text[]:=ARRAY[
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
    'public.red_fortryd_person_narrative_publication_event(uuid,text)'
  ];
  v_legacy_authenticated text[]:=ARRAY[
    'public.red_publicer_narrative_record(bigint,uuid,text,text)',
    'public.red_tilbagetraek_narrative_record(bigint)',
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_apply_reimport_cases(uuid,text,text)',
    'public.red_reverse_reimport_cases(uuid,uuid)'
  ];
  v_legacy_service text[]:=ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'
  ];
BEGIN
  IF p_version NOT IN (1,2) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_ACL_VERSION_INVALID';
  END IF;
  FOREACH v_signature IN ARRAY v_new||v_legacy_authenticated||v_legacy_service LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_ACL_SIGNATURE_MISSING: %',v_signature;
    END IF;
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',
      v_signature
    );
  END LOOP;
  IF p_version=1 THEN
    FOREACH v_signature IN ARRAY v_legacy_authenticated LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature);
    END LOOP;
    FOREACH v_signature IN ARRAY v_legacy_service LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',v_signature);
    END LOOP;
  ELSE
    FOREACH v_signature IN ARRAY v_new LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature);
    END LOOP;
  END IF;
END
$$;

REVOKE ALL ON TABLE private.narrative_record_contract,
  private.narrative_record_cutover_receipt
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  private.narrative_legacy_candidate_publication_state(bigint,bigint,uuid),
  private.reject_narrative_record_cutover_receipt_mutation(),
  private.apply_narrative_record_contract_acl(integer)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.narrative_record_contract_version()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.narrative_record_contract_version()
  TO anon,authenticated,service_role;

-- #153 Task 4A: this late override follows the historical V1 implementation
-- and every historical ACL grant above.
CREATE OR REPLACE FUNCTION public.red_authorize_source_scoped_replace(
  p_database_name text,p_system_identifier text,p_actor_id uuid,p_nonce uuid,
  p_manifest jsonb,p_dry_run_sha256 text,p_ownership_sha256 text,p_expires_at timestamptz
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$ BEGIN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED'; END $$;
CREATE OR REPLACE FUNCTION public.red_apply_source_scoped_replace(
  p_authorization_id uuid,p_manifest jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $$ BEGIN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED'; END $$;
CREATE OR REPLACE FUNCTION public.red_verify_source_scoped_replace(
  p_authorization_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $$ BEGIN RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_V1_RETIRED'; END $$;
CREATE TRIGGER trg_source_scoped_replace_authorization_v1_retired
  BEFORE INSERT OR UPDATE OR DELETE ON private.source_scoped_replace_authorization
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_replace_v1_mutation();
CREATE TRIGGER trg_source_scoped_replace_batch_v1_retired
  BEFORE INSERT OR UPDATE OR DELETE ON private.source_scoped_replace_batch
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_replace_v1_mutation();
CREATE TRIGGER trg_source_scoped_replace_event_v1_retired
  BEFORE INSERT OR UPDATE OR DELETE ON private.source_scoped_replace_event
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_replace_v1_mutation();
ALTER TABLE private.source_scoped_replace_authorization ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_replace_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_replace_authorization,
  private.source_scoped_replace_batch,private.source_scoped_replace_event
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz),
  public.red_apply_source_scoped_replace(uuid,jsonb),public.red_verify_source_scoped_replace(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE private.source_scoped_evidence_v3_migration_receipt (
  contract_version text PRIMARY KEY,
  contract_sha256 text NOT NULL CHECK (contract_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.source_scoped_evidence_v3_migration_receipt ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_evidence_v3_migration_receipt
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_task4a_contract_sha256()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,private,extensions
AS $$
  SELECT encode(extensions.digest(jsonb_build_object(
    'schema','source-scoped-evidence-v3-task4a-v1',
    'columns',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'table',n.nspname||'.'||c.relname,'position',a.attnum,'name',a.attname,
      'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
      'identity',a.attidentity,'generated',a.attgenerated,
      'default',pg_get_expr(d.adbin,d.adrelid)
    ) ORDER BY n.nspname,c.relname,a.attnum),'[]'::jsonb)
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
       LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname='private'
        AND c.relname=ANY(ARRAY[
          'source_scoped_replace_authorization','source_scoped_replace_batch','source_scoped_replace_event',
          'source_scoped_replace_v3_attestation','source_scoped_replace_v3_authorization','source_scoped_replace_v3_batch','source_scoped_replace_v3_event','source_scoped_replace_v3_manifest_artifact',
          'source_scoped_evidence_v3_chain','source_scoped_evidence_v3_revision','source_scoped_evidence_v3_member','source_scoped_evidence_v3_publication','source_scoped_evidence_v3_chain_event','source_scoped_evidence_v3_chain_state','source_scoped_evidence_v3_migration_receipt'
        ])),
    'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'table',n.nspname||'.'||c.relname,'name',co.conname,
      'definition',pg_get_constraintdef(co.oid,true)) ORDER BY n.nspname,c.relname,co.conname),'[]'::jsonb)
      FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private' AND c.relname=ANY(ARRAY[
        'source_scoped_replace_authorization','source_scoped_replace_batch','source_scoped_replace_event',
        'source_scoped_replace_v3_attestation','source_scoped_replace_v3_authorization','source_scoped_replace_v3_batch','source_scoped_replace_v3_event','source_scoped_replace_v3_manifest_artifact',
        'source_scoped_evidence_v3_chain','source_scoped_evidence_v3_revision','source_scoped_evidence_v3_member','source_scoped_evidence_v3_publication','source_scoped_evidence_v3_chain_event','source_scoped_evidence_v3_chain_state','source_scoped_evidence_v3_migration_receipt'
      ])),
    'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'table',n.nspname||'.'||c.relname,'name',ic.relname,
      'definition',pg_get_indexdef(ic.oid)
    ) ORDER BY n.nspname,c.relname,ic.relname),'[]'::jsonb)
      FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
       JOIN pg_class ic ON ic.oid=i.indexrelid
      WHERE n.nspname='private' AND c.relname=ANY(ARRAY[
        'source_scoped_replace_authorization','source_scoped_replace_batch','source_scoped_replace_event',
        'source_scoped_replace_v3_attestation','source_scoped_replace_v3_authorization','source_scoped_replace_v3_batch','source_scoped_replace_v3_event','source_scoped_replace_v3_manifest_artifact',
        'source_scoped_evidence_v3_chain','source_scoped_evidence_v3_revision','source_scoped_evidence_v3_member','source_scoped_evidence_v3_publication','source_scoped_evidence_v3_chain_event','source_scoped_evidence_v3_chain_state','source_scoped_evidence_v3_migration_receipt'
      ])),
    'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object('table',n.nspname||'.'||c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid,true)) ORDER BY n.nspname,c.relname,t.tgname),'[]'::jsonb)
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname='private'
        AND (c.relname LIKE 'source_scoped_replace%' OR c.relname LIKE 'source_scoped_evidence_v3%')),
    'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
      'acl',coalesce(p.proacl,acldefault('f',p.proowner))::text
    ) ORDER BY p.oid::regprocedure::text),'[]'::jsonb)
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname='public' AND p.proname IN ('red_authorize_source_scoped_replace','red_apply_source_scoped_replace','red_verify_source_scoped_replace'))
         OR (n.nspname='private' AND p.proname IN ('reject_source_scoped_replace_v1_mutation','reject_source_scoped_evidence_v3_mutation','enforce_source_scoped_evidence_v3_revision_predecessor'))),
    'acl',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'object',n.nspname||'.'||c.relname,'acl',coalesce(c.relacl,'{}'::aclitem[])::text,
      'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity
    ) ORDER BY n.nspname,c.relname),'[]'::jsonb)
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private'
        AND (c.relname LIKE 'source_scoped_replace%' OR c.relname LIKE 'source_scoped_evidence_v3%'))
  )::text,'sha256'),'hex')
$$;
REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_task4a_contract_sha256()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_source_scoped_evidence_v3_migration_receipt_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_migration_receipt
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
INSERT INTO private.source_scoped_evidence_v3_migration_receipt(contract_version,contract_sha256)
VALUES ('source-scoped-evidence-v3-task4a-v1',private.source_scoped_evidence_v3_task4a_contract_sha256());

-- #153 Task 4B: inventory and deployment are private, append-only capabilities.
CREATE TABLE private.source_scoped_evidence_contract_inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schema_contract_version text NOT NULL CHECK (btrim(schema_contract_version)<>''),
  catalog_definition_sha256 text NOT NULL CHECK (catalog_definition_sha256 ~ '^[0-9a-f]{64}$'),
  reader_probe_source_sha256 text NOT NULL CHECK (reader_probe_source_sha256 ~ '^[0-9a-f]{64}$'),
  consumer_probe_source_sha256 text NOT NULL CHECK (consumer_probe_source_sha256 ~ '^[0-9a-f]{64}$'),
  writer_probe_source_sha256 text NOT NULL CHECK (writer_probe_source_sha256 ~ '^[0-9a-f]{64}$'),
  inventory_result_sha256 text NOT NULL CHECK (inventory_result_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(schema_contract_version,catalog_definition_sha256,reader_probe_source_sha256,
         consumer_probe_source_sha256,writer_probe_source_sha256,inventory_result_sha256)
);

CREATE TABLE private.source_scoped_evidence_v3_deployment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id uuid NOT NULL REFERENCES private.source_scoped_evidence_contract_inventory(id),
  repository_tree_id text NOT NULL CHECK (btrim(repository_tree_id)<>''),
  repository_writer_artifact_sha256 text NOT NULL CHECK (repository_writer_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  schema_contract_version text NOT NULL CHECK (btrim(schema_contract_version)<>''),
  database_name text NOT NULL CHECK (btrim(database_name)<>''),
  system_identifier text NOT NULL CHECK (btrim(system_identifier)<>''),
  registered_by uuid NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  deployment_sha256 text NOT NULL UNIQUE CHECK (deployment_sha256 ~ '^[0-9a-f]{64}$')
);
ALTER TABLE private.source_scoped_replace_v3_authorization
  ADD CONSTRAINT source_scoped_replace_v3_authorization_deployment_fk
  FOREIGN KEY (deployment_id) REFERENCES private.source_scoped_evidence_v3_deployment(id);

-- A view's dependencies are rooted in its rewrite rule rather than its
-- pg_class row.  Keep the whole relevant pg_depend closure in every entry;
-- function bodies remain separately hashed because PL/pgSQL dependencies are
-- deliberately incomplete in PostgreSQL's catalog.
CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_dependency_edges(
  p_classid oid,p_object_id oid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  WITH RECURSIVE roots(classid,objid) AS (
    SELECT p_classid,p_object_id
    UNION
    SELECT 'pg_rewrite'::regclass::oid,rewrite.oid
      FROM pg_rewrite rewrite
     WHERE p_classid='pg_class'::regclass::oid
       AND rewrite.ev_class=p_object_id
  ), closure(classid,objid) AS (
    SELECT classid,objid FROM roots
    UNION
    SELECT dependency.refclassid,dependency.refobjid
      FROM closure parent
      JOIN pg_depend dependency
        ON dependency.classid=parent.classid AND dependency.objid=parent.objid
  ), edges AS (
    SELECT DISTINCT dependency.classid::regclass::text AS dependent_class,
           dependency.objid AS dependent_oid,
           dependency.objsubid AS dependent_subid,
           dependency.refclassid::regclass::text AS referenced_class,
           dependency.refobjid AS referenced_oid,
           dependency.refobjsubid AS referenced_subid,
           dependency.deptype AS dependency_type
      FROM closure parent
      JOIN pg_depend dependency
        ON dependency.classid=parent.classid AND dependency.objid=parent.objid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'dependent_class',dependent_class,'dependent_oid',dependent_oid,
    'dependent_subid',dependent_subid,'referenced_class',referenced_class,
    'referenced_oid',referenced_oid,'referenced_subid',referenced_subid,
    'dependency_type',dependency_type
  ) ORDER BY dependent_class,dependent_oid,dependent_subid,referenced_class,
             referenced_oid,referenced_subid,dependency_type),'[]'::jsonb)
  FROM edges;
$$;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_catalog_definition_sha256()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private,extensions AS $$
  WITH entries AS (
    SELECT n.nspname AS table_schema,c.relname AS table_name,co.conname,
      jsonb_build_object(
        'table_schema',n.nspname,'table_name',c.relname,'constraint_name',co.conname,
        'column_pairs',(
          SELECT coalesce(jsonb_agg(jsonb_build_object(
            'table_column',local_column.attname,'model_column',model_column.attname
          ) ORDER BY keys.ordinality),'[]'::jsonb)
          FROM unnest(co.conkey,co.confkey) WITH ORDINALITY AS keys(local_attnum,model_attnum,ordinality)
          JOIN pg_attribute local_column ON local_column.attrelid=co.conrelid
            AND local_column.attnum=keys.local_attnum
          JOIN pg_attribute model_column ON model_column.attrelid=co.confrelid
            AND model_column.attnum=keys.model_attnum
        ),
        'on_update',CASE co.confupdtype WHEN 'a' THEN 'no_action' WHEN 'r' THEN 'restrict'
          WHEN 'c' THEN 'cascade' WHEN 'n' THEN 'set_null' WHEN 'd' THEN 'set_default' END,
        'on_delete',CASE co.confdeltype WHEN 'a' THEN 'no_action' WHEN 'r' THEN 'restrict'
          WHEN 'c' THEN 'cascade' WHEN 'n' THEN 'set_null' WHEN 'd' THEN 'set_default' END,
        'deferrable',co.condeferrable,'initially_deferred',co.condeferred,
        'validated',co.convalidated
      ) AS entry
    FROM pg_constraint co
    JOIN pg_class c ON c.oid=co.conrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE co.contype='f'
      AND co.confrelid IN ('public.fact'::regclass,'public.assertion'::regclass,'public.citation'::regclass)
  )
  SELECT encode(extensions.digest(coalesce(jsonb_agg(entry ORDER BY table_schema,table_name,conname),'[]'::jsonb)::text,'sha256'),'hex')
  FROM entries;
$$;

-- This is intentionally a closed superset.  A new public view/RPC or any
-- SECURITY DEFINER function is an inventory change even when pg_depend cannot
-- see a PL/pgSQL read through a helper or dynamic SQL.
CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_reader_probe()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private,extensions AS $$
  WITH security_surface AS MATERIALIZED (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'relation',n.nspname||'.'||c.relname,'kind',c.relkind,
      'acl',coalesce(c.relacl,acldefault('r',c.relowner))::text,
      'rls_enabled',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
      'reloptions',coalesce(to_jsonb(c.reloptions),'[]'::jsonb),
      'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name',policy.polname,'command',policy.polcmd,'roles',policy.polroles,
        'using',pg_get_expr(policy.polqual,policy.polrelid),
        'with_check',pg_get_expr(policy.polwithcheck,policy.polrelid)
      ) ORDER BY policy.polname),'[]'::jsonb) FROM pg_policy policy WHERE policy.polrelid=c.oid)
    ) ORDER BY n.nspname,c.relname),'[]'::jsonb) AS relations
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m')
  ), entries AS (
    SELECT 'reader_view'::text AS kind,n.nspname AS object_schema,c.relname AS object_name,c.oid AS object_oid,
      encode(extensions.digest(convert_to(pg_get_viewdef(c.oid,true),'UTF8'),'sha256'),'hex') AS definition_sha256,
      private.source_scoped_evidence_v3_dependency_edges('pg_class'::regclass::oid,c.oid) AS dependency_edges,
      'all'::text AS member_kind,
      jsonb_build_object('object_acl',coalesce(c.relacl,acldefault('r',c.relowner))::text,
        'rls_enabled',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
        'security_barrier',coalesce(c.reloptions @> ARRAY['security_barrier=true'],false),
        'security_invoker',coalesce(c.reloptions @> ARRAY['security_invoker=true'],false),
        'relation_security_surface',security.relations,
        'classification',CASE WHEN c.reloptions @> ARRAY['security_invoker=true']
          THEN 'rls_gated' ELSE 'editorial_exception' END) AS guard
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN security_surface security
    WHERE n.nspname='public' AND c.relkind IN ('v','m')
    UNION ALL
    SELECT 'reader_routine',n.nspname,p.proname,p.oid,
      encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),
      private.source_scoped_evidence_v3_dependency_edges('pg_proc'::regclass::oid,p.oid),
      'all',jsonb_build_object('routine_acl',coalesce(p.proacl,acldefault('f',p.proowner))::text,
        'security_definer',p.prosecdef,
        'public_execute',EXISTS (
          SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) privilege
           WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE'
        ),
        'relation_security_surface',security.relations,
        'classification',CASE WHEN p.prosecdef THEN 'editorial_exception' ELSE 'rls_gated' END)
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN security_surface security
    WHERE p.prokind IN ('f','p') AND (n.nspname='public' OR p.prosecdef)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'kind',kind,'object_schema',object_schema,'object_name',object_name,'object_oid',object_oid,
    'definition_sha256',definition_sha256,'dependency_edges',dependency_edges,
    'member_kind',member_kind,'guard',guard
  ) ORDER BY kind,object_schema,object_name,object_oid),'[]'::jsonb)
  FROM entries;
$$;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_consumer_probe()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private,extensions AS $$
  WITH candidate_tables AS (
    SELECT c.oid,n.nspname,c.relname,c.relrowsecurity
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
       AND c.oid NOT IN ('public.fact'::regclass,'public.assertion'::regclass,'public.citation'::regclass)
       AND c.relname NOT LIKE 'source_scoped_evidence_v3_%'
       AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0
                     AND NOT a.attisdropped AND a.attname IN (
                       'fact_id','assertion_id','citation_id','valgt_assertion_id','target_type','target_id',
                       'subjekt_type','subjekt_id','objekt_type','objekt_id'))
  ), entries AS (
    SELECT 'consumer'::text AS kind,nspname AS object_schema,relname AS object_name,oid AS object_oid,
      encode(extensions.digest(convert_to(jsonb_build_object(
        'schema',nspname,'table',relname,
        'columns',(SELECT coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod)) ORDER BY a.attnum),'[]'::jsonb)
                    FROM pg_attribute a WHERE a.attrelid=candidate_tables.oid AND a.attnum>0 AND NOT a.attisdropped
                      AND a.attname IN ('fact_id','assertion_id','citation_id','valgt_assertion_id','target_type','target_id','subjekt_type','subjekt_id','objekt_type','objekt_id'))
      )::text,'UTF8'),'sha256'),'hex') AS definition_sha256,
      private.source_scoped_evidence_v3_dependency_edges('pg_class'::regclass::oid,oid) AS dependency_edges,
      'all'::text AS member_kind,
      jsonb_build_object('rls_enabled',relrowsecurity,
        'candidate_pairs',jsonb_strip_nulls(jsonb_build_array(
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='fact_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('member_kind','fact','id_column','fact_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='assertion_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('member_kind','assertion','id_column','assertion_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='citation_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('member_kind','citation','id_column','citation_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='valgt_assertion_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('member_kind','assertion','id_column','valgt_assertion_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='target_type' AND a.attnum>0 AND NOT a.attisdropped)
                      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='target_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('type_column','target_type','id_column','target_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='subjekt_type' AND a.attnum>0 AND NOT a.attisdropped)
                      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='subjekt_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('type_column','subjekt_type','id_column','subjekt_id') END,
          CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='objekt_type' AND a.attnum>0 AND NOT a.attisdropped)
                      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=oid AND a.attname='objekt_id' AND a.attnum>0 AND NOT a.attisdropped) THEN jsonb_build_object('type_column','objekt_type','id_column','objekt_id') END
        )),
        'consumer_guard_triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'name',trigger.tgname,'definition',pg_get_triggerdef(trigger.oid,true)
        ) ORDER BY trigger.tgname),'[]'::jsonb)
          FROM pg_trigger trigger
         WHERE trigger.tgrelid=candidate_tables.oid AND NOT trigger.tgisinternal
           AND trigger.tgfoid=to_regprocedure('private.reject_source_scoped_evidence_v3_consumer_mutation()'))) AS guard
    FROM candidate_tables
    UNION ALL
    SELECT 'bound_member_guard',n.nspname,c.relname,c.oid,
      encode(extensions.digest(convert_to(pg_get_triggerdef(trigger.oid,true),'UTF8'),'sha256'),'hex'),
      private.source_scoped_evidence_v3_dependency_edges('pg_class'::regclass::oid,c.oid),
      c.relname,jsonb_build_object('trigger_name',trigger.tgname,
        'trigger_definition',pg_get_triggerdef(trigger.oid,true),
        'trigger_function',trigger.tgfoid::regprocedure::text)
      FROM pg_trigger trigger JOIN pg_class c ON c.oid=trigger.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE NOT trigger.tgisinternal
       AND trigger.tgfoid=to_regprocedure('private.reject_source_scoped_evidence_v3_bound_member_mutation()')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'kind',kind,'object_schema',object_schema,'object_name',object_name,'object_oid',object_oid,
    'definition_sha256',definition_sha256,'dependency_edges',dependency_edges,
    'member_kind',member_kind,'guard',guard
  ) ORDER BY kind,object_schema,object_name,object_oid),'[]'::jsonb)
  FROM entries;
$$;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_writer_probe()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,private,extensions
AS $$
DECLARE
  v_unclassified regprocedure;
  v_result jsonb;
BEGIN
  SELECT p.oid::regprocedure INTO v_unclassified
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_language language ON language.oid=p.prolang
   WHERE n.nspname IN ('public','private')
     AND p.prokind IN ('f','p')
     AND language.lanname='plpgsql'
     AND pg_get_functiondef(p.oid) ~ '(?i)\mEXECUTE\M'
     AND p.oid NOT IN (
       'private.apply_narrative_record_contract_acl(integer)'::regprocedure,
       'private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)'::regprocedure,
       'public._version_current_row(text,jsonb)'::regprocedure,
       'public._version_delete_row(text,jsonb)'::regprocedure,
       'public._version_upsert_row(text,jsonb)'::regprocedure
     )
   ORDER BY p.oid::regprocedure::text
   LIMIT 1;
  IF v_unclassified IS NOT NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_UNCLASSIFIED_DYNAMIC_SQL';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'kind','writer','object_schema',n.nspname,'object_name',p.proname,'object_oid',p.oid,
    'definition_sha256',encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),
    'dependency_edges',private.source_scoped_evidence_v3_dependency_edges('pg_proc'::regclass::oid,p.oid),
    'member_kind','all','guard',jsonb_build_object(
      'security_definer',p.prosecdef,
      'dynamic_sql_allowlist',CASE
        WHEN p.oid IN (
          'public._version_current_row(text,jsonb)'::regprocedure,
          'public._version_delete_row(text,jsonb)'::regprocedure,
          'public._version_upsert_row(text,jsonb)'::regprocedure
        ) THEN jsonb_build_object('mode','version_pk_registry','model_targets',(
          SELECT coalesce(jsonb_agg(registry.tabel ORDER BY registry.tabel),'[]'::jsonb)
            FROM public.version_pk_registry registry
           WHERE registry.tabel IN ('fact','assertion','citation')
        ))
        WHEN pg_get_functiondef(p.oid) ~ '(?i)\mEXECUTE\M'
          THEN jsonb_build_object('mode','explicit','model_targets','[]'::jsonb)
        ELSE jsonb_build_object('mode','not_applicable','model_targets','[]'::jsonb)
      END
    )
  ) ORDER BY n.nspname,p.proname,p.oid),'[]'::jsonb)
    INTO v_result
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private')
     AND p.prokind IN ('f','p')
     AND (
       (pg_get_functiondef(p.oid) ~ '(?i)\m(INSERT|UPDATE|DELETE|COPY)\M'
        AND pg_get_functiondef(p.oid) ~ '(?i)\m(fact|assertion|citation)\M')
       OR p.oid IN (
         'public._version_current_row(text,jsonb)'::regprocedure,
         'public._version_delete_row(text,jsonb)'::regprocedure,
         'public._version_upsert_row(text,jsonb)'::regprocedure
       )
       OR pg_get_functiondef(p.oid) ~ '(?i)\mEXECUTE\M'
     );
  RETURN v_result;
END
$$;

CREATE OR REPLACE FUNCTION private.refresh_source_scoped_evidence_contract_inventory(
  p_schema_contract_version text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,private,extensions
AS $$
DECLARE
  v_catalog text;
  v_reader jsonb;
  v_consumer jsonb;
  v_writer jsonb;
  v_reader_source text;
  v_consumer_source text;
  v_writer_source text;
  v_result text;
  v_id uuid;
BEGIN
  IF p_schema_contract_version IS NULL OR btrim(p_schema_contract_version)='' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_INVENTORY_VERSION_INVALID';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('source-scoped-evidence-v3-inventory:'||p_schema_contract_version));
  v_catalog:=private.source_scoped_evidence_v3_catalog_definition_sha256();
  v_reader:=private.source_scoped_evidence_v3_reader_probe();
  v_consumer:=private.source_scoped_evidence_v3_consumer_probe();
  v_writer:=private.source_scoped_evidence_v3_writer_probe();
  v_reader_source:=encode(extensions.digest(convert_to(pg_get_functiondef(
    'private.source_scoped_evidence_v3_reader_probe()'::regprocedure),'UTF8'),'sha256'),'hex');
  v_consumer_source:=encode(extensions.digest(convert_to(pg_get_functiondef(
    'private.source_scoped_evidence_v3_consumer_probe()'::regprocedure),'UTF8'),'sha256'),'hex');
  v_writer_source:=encode(extensions.digest(convert_to(pg_get_functiondef(
    'private.source_scoped_evidence_v3_writer_probe()'::regprocedure),'UTF8'),'sha256'),'hex');
  v_result:=encode(extensions.digest(jsonb_build_object(
    'schema','source-scoped-evidence-v3-inventory-result-v1',
    'entries',(
      SELECT coalesce(jsonb_agg(entry ORDER BY entry->>'kind',entry->>'object_schema',entry->>'object_name',
                                          (entry->>'object_oid')::oid),'[]'::jsonb)
        FROM (
          SELECT jsonb_build_object('kind','catalog','object_schema','pg_catalog','object_name','fact-assertion-citation-fks',
            'object_oid',0,'definition_sha256',v_catalog,'dependency_edges','[]'::jsonb,'member_kind','all','guard',
            jsonb_build_object('foreign_key_contract','complete')) AS entry
          UNION ALL SELECT value FROM jsonb_array_elements(v_reader)
          UNION ALL SELECT value FROM jsonb_array_elements(v_consumer)
          UNION ALL SELECT value FROM jsonb_array_elements(v_writer)
          UNION ALL SELECT jsonb_build_object('kind','probe','object_schema','private','object_name','source_scoped_evidence_v3_reader_probe',
            'object_oid','private.source_scoped_evidence_v3_reader_probe()'::regprocedure::oid,
            'definition_sha256',v_reader_source,'dependency_edges',private.source_scoped_evidence_v3_dependency_edges(
              'pg_proc'::regclass::oid,'private.source_scoped_evidence_v3_reader_probe()'::regprocedure::oid),
            'member_kind','all','guard',jsonb_build_object('probe','reader'))
          UNION ALL SELECT jsonb_build_object('kind','probe','object_schema','private','object_name','source_scoped_evidence_v3_consumer_probe',
            'object_oid','private.source_scoped_evidence_v3_consumer_probe()'::regprocedure::oid,
            'definition_sha256',v_consumer_source,'dependency_edges',private.source_scoped_evidence_v3_dependency_edges(
              'pg_proc'::regclass::oid,'private.source_scoped_evidence_v3_consumer_probe()'::regprocedure::oid),
            'member_kind','all','guard',jsonb_build_object('probe','consumer'))
          UNION ALL SELECT jsonb_build_object('kind','probe','object_schema','private','object_name','source_scoped_evidence_v3_writer_probe',
            'object_oid','private.source_scoped_evidence_v3_writer_probe()'::regprocedure::oid,
            'definition_sha256',v_writer_source,'dependency_edges',private.source_scoped_evidence_v3_dependency_edges(
              'pg_proc'::regclass::oid,'private.source_scoped_evidence_v3_writer_probe()'::regprocedure::oid),
            'member_kind','all','guard',jsonb_build_object('probe','writer'))
        ) all_entries
    )
  )::text,'sha256'),'hex');
  SELECT id INTO v_id
    FROM private.source_scoped_evidence_contract_inventory
   WHERE schema_contract_version=p_schema_contract_version
     AND catalog_definition_sha256=v_catalog
     AND reader_probe_source_sha256=v_reader_source
     AND consumer_probe_source_sha256=v_consumer_source
     AND writer_probe_source_sha256=v_writer_source
     AND inventory_result_sha256=v_result;
  IF v_id IS NULL THEN
    INSERT INTO private.source_scoped_evidence_contract_inventory(
      schema_contract_version,catalog_definition_sha256,reader_probe_source_sha256,
      consumer_probe_source_sha256,writer_probe_source_sha256,inventory_result_sha256
    ) VALUES (
      p_schema_contract_version,v_catalog,v_reader_source,v_consumer_source,v_writer_source,v_result
    ) RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END
$$;

CREATE OR REPLACE FUNCTION private.register_source_scoped_evidence_v3_deployment(
  p_inventory_id uuid,p_repository_tree_id text,p_repository_writer_artifact_sha256 text,
  p_schema_contract_version text,p_database_name text,p_system_identifier text,p_registered_by uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private,extensions AS $$
DECLARE
  v_id uuid;
  v_registered_at timestamptz:=clock_timestamp();
  v_hash text;
  v_gateway_actor constant uuid:='b6677b31-4c1a-5a82-91e4-e9f439eb4236'::uuid;
BEGIN
  IF p_inventory_id IS NULL OR p_repository_tree_id IS NULL OR btrim(p_repository_tree_id)=''
     OR p_repository_writer_artifact_sha256 !~ '^[0-9a-f]{64}$'
     OR p_schema_contract_version IS NULL OR btrim(p_schema_contract_version)=''
     OR session_user<>'daa_source_scoped_evidence_gateway'
     OR p_registered_by IS DISTINCT FROM v_gateway_actor
     OR p_database_name<>current_database()
     OR p_system_identifier<>(pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_DEPLOYMENT_INVALID';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4b-v2'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4b_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_DEPLOYMENT_UNCERTIFIED';
  END IF;
  IF p_inventory_id IS DISTINCT FROM private.refresh_source_scoped_evidence_contract_inventory(
       p_schema_contract_version
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_INVENTORY_DRIFT';
  END IF;
  v_hash:=encode(extensions.digest(jsonb_build_object('schema','source-scoped-evidence-v3-deployment-v1',
    'inventory_id',p_inventory_id,'repository_tree_id',p_repository_tree_id,
    'repository_writer_artifact_sha256',p_repository_writer_artifact_sha256,
    'schema_contract_version',p_schema_contract_version,'database_name',p_database_name,
    'system_identifier',p_system_identifier,'registered_by',p_registered_by,
    'registered_at',v_registered_at)::text,'sha256'),'hex');
  INSERT INTO private.source_scoped_evidence_v3_deployment(
    inventory_id,repository_tree_id,repository_writer_artifact_sha256,schema_contract_version,
    database_name,system_identifier,registered_by,registered_at,deployment_sha256
  ) VALUES (p_inventory_id,p_repository_tree_id,p_repository_writer_artifact_sha256,p_schema_contract_version,
    p_database_name,p_system_identifier,p_registered_by,v_registered_at,v_hash) RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

DO $source_scoped_evidence_v3_deployer_role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_source_scoped_evidence_deployer') THEN
    CREATE ROLE daa_source_scoped_evidence_deployer NOLOGIN NOINHERIT NOBYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_source_scoped_evidence_gateway') THEN
    CREATE ROLE daa_source_scoped_evidence_gateway LOGIN NOINHERIT NOBYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
  END IF;
  IF EXISTS (
       SELECT 1 FROM pg_roles
        WHERE rolname='daa_source_scoped_evidence_deployer'
          AND (rolcanlogin OR rolinherit OR rolbypassrls OR rolsuper
               OR rolcreatedb OR rolcreaterole OR rolreplication)
     )
     OR EXISTS (
       SELECT 1 FROM pg_roles
        WHERE rolname='daa_source_scoped_evidence_gateway'
          AND (NOT rolcanlogin OR rolinherit OR rolbypassrls OR rolsuper
               OR rolcreatedb OR rolcreaterole OR rolreplication)
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_ROLE_INVALID';
  END IF;
  GRANT daa_source_scoped_evidence_deployer TO daa_source_scoped_evidence_gateway
    WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
END
$source_scoped_evidence_v3_deployer_role$;

CREATE OR REPLACE FUNCTION private.reject_source_scoped_evidence_v3_bound_member_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,private
AS $$
DECLARE v_member_kind text:=TG_TABLE_NAME;
BEGIN
  IF EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_member member
     WHERE member.member_kind=v_member_kind
       AND ((v_member_kind='fact' AND member.fact_id=OLD.id)
         OR (v_member_kind='assertion' AND member.assertion_id=OLD.id)
         OR (v_member_kind='citation' AND member.citation_id=OLD.id))
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_BOUND_MEMBER_MUTATION';
  END IF;
  IF TG_OP='UPDATE' THEN RETURN NEW; END IF;
  RETURN OLD;
END
$$;

CREATE OR REPLACE FUNCTION private.reject_source_scoped_evidence_v3_consumer_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,private
AS $$
DECLARE v_payload jsonb:=to_jsonb(NEW);
BEGIN
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('fact',v_payload->>'fact_id'),('assertion',v_payload->>'assertion_id'),('assertion',v_payload->>'valgt_assertion_id'),
      ('citation',v_payload->>'citation_id'),(v_payload->>'target_type',v_payload->>'target_id'),
      (v_payload->>'subjekt_type',v_payload->>'subjekt_id'),
      (v_payload->>'objekt_type',v_payload->>'objekt_id')
    ) AS candidate(member_kind,member_id)
    JOIN private.source_scoped_evidence_v3_member member
      ON member.member_kind=candidate.member_kind AND candidate.member_id ~ '^[0-9]+$'
     AND ((candidate.member_kind='fact' AND member.fact_id=candidate.member_id::bigint)
       OR (candidate.member_kind='assertion' AND member.assertion_id=candidate.member_id::bigint)
       OR (candidate.member_kind='citation' AND member.citation_id=candidate.member_id::bigint))
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CONSUMER_MUTATION';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_source_scoped_evidence_v3_fact_bound_member
  BEFORE UPDATE OR DELETE ON public.fact FOR EACH ROW
  EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_bound_member_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_assertion_bound_member
  BEFORE UPDATE OR DELETE ON public.assertion FOR EACH ROW
  EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_bound_member_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_citation_bound_member
  BEFORE UPDATE OR DELETE ON public.citation FOR EACH ROW
  EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_bound_member_mutation();
-- Attach the guard to the same catalog-discovered surface that the inventory
-- hashes.  A newly introduced table is therefore both a deployment-blocking
-- inventory drift and, once explicitly classified, protected by this trigger.
DO $source_scoped_evidence_v3_consumer_guards$
DECLARE v_relation record; v_trigger record; v_name text;
BEGIN
  FOR v_trigger IN
    SELECT n.nspname,c.relname,t.tgname
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE NOT t.tgisinternal
       AND t.tgfoid='private.reject_source_scoped_evidence_v3_consumer_mutation()'::regprocedure
  LOOP
    EXECUTE format('DROP TRIGGER %I ON %I.%I',v_trigger.tgname,v_trigger.nspname,v_trigger.relname);
  END LOOP;
  FOR v_relation IN
    SELECT n.nspname,c.relname,c.oid
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
       AND c.oid NOT IN ('public.fact'::regclass,'public.assertion'::regclass,'public.citation'::regclass)
       AND NOT (n.nspname='private' AND c.relname LIKE 'source_scoped_evidence_v3_%')
       AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0
                     AND NOT a.attisdropped AND a.attname IN (
                       'fact_id','assertion_id','citation_id','valgt_assertion_id','target_type','target_id',
                       'subjekt_type','subjekt_id','objekt_type','objekt_id'))
  LOOP
    v_name:=format('trg_source_scoped_evidence_v3_consumer_%s',v_relation.oid);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_consumer_mutation()',
      v_name,v_relation.nspname,v_relation.relname);
  END LOOP;
END
$source_scoped_evidence_v3_consumer_guards$;

CREATE TRIGGER trg_source_scoped_evidence_contract_inventory_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_contract_inventory
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
CREATE TRIGGER trg_source_scoped_evidence_v3_deployment_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_v3_deployment
  FOR EACH ROW EXECUTE FUNCTION private.reject_source_scoped_evidence_v3_mutation();
ALTER TABLE private.source_scoped_evidence_contract_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.source_scoped_evidence_v3_deployment ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_evidence_contract_inventory,private.source_scoped_evidence_v3_deployment
  FROM PUBLIC,anon,authenticated,service_role,daa_source_scoped_evidence_deployer,daa_source_scoped_evidence_gateway;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.fact,public.assertion,public.citation
  FROM anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_catalog_definition_sha256(),
  private.source_scoped_evidence_v3_reader_probe(),private.source_scoped_evidence_v3_consumer_probe(),
  private.source_scoped_evidence_v3_writer_probe(),
  private.refresh_source_scoped_evidence_contract_inventory(text),
  private.reject_source_scoped_evidence_v3_bound_member_mutation(),
  private.reject_source_scoped_evidence_v3_consumer_mutation(),
  private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role,daa_source_scoped_evidence_gateway;
REVOKE ALL ON SCHEMA private FROM daa_source_scoped_evidence_deployer,daa_source_scoped_evidence_gateway;
GRANT USAGE ON SCHEMA private TO daa_source_scoped_evidence_deployer;
GRANT EXECUTE ON FUNCTION private.register_source_scoped_evidence_v3_deployment(
  uuid,text,text,text,text,text,uuid
) TO daa_source_scoped_evidence_deployer;

-- The Task 4B receipt closes the additive migration: it covers the exact
-- relations, routines, guards and ACL boundary that an authorization relies
-- on.  The helper source itself is asserted by the executable verifier.
CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_task4b_contract_sha256()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private,extensions AS $$
  SELECT encode(extensions.digest(jsonb_build_object(
    'schema','source-scoped-evidence-v3-task4b-v2',
    'private_schema_acl',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'grantee',coalesce(grantee.rolname,'PUBLIC'),'privilege',acl.privilege_type,
        'grantable',acl.is_grantable,'grantor',grantor.rolname
      ) ORDER BY coalesce(grantee.rolname,'PUBLIC'),acl.privilege_type,acl.is_grantable,grantor.rolname),'[]'::jsonb)
      FROM pg_namespace ns CROSS JOIN LATERAL aclexplode(coalesce(ns.nspacl,acldefault('n',ns.nspowner))) acl
      JOIN pg_roles grantor ON grantor.oid=acl.grantor
      LEFT JOIN pg_roles grantee ON grantee.oid=acl.grantee
     WHERE ns.nspname='private'),
    'relations',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'relation',n.nspname||'.'||c.relname,
      'columns',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'position',a.attnum,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
        'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
        'default',pg_get_expr(d.adbin,d.adrelid)
      ) ORDER BY a.attnum),'[]'::jsonb)
        FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
       WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
      'acl',coalesce(c.relacl,'{}'::aclitem[])::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity
    ) ORDER BY n.nspname,c.relname),'[]'::jsonb)
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname IN (
       'source_scoped_evidence_contract_inventory','source_scoped_evidence_v3_deployment','source_scoped_evidence_v3_migration_receipt')),
    'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'relation',n.nspname||'.'||c.relname,'name',co.conname,'definition',pg_get_constraintdef(co.oid,true)
    ) ORDER BY n.nspname,c.relname,co.conname),'[]'::jsonb)
      FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE (n.nspname='private' AND c.relname IN ('source_scoped_evidence_contract_inventory','source_scoped_evidence_v3_deployment'))
        OR co.conname='source_scoped_replace_v3_authorization_deployment_fk'),
    'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
      'acl',coalesce(p.proacl,acldefault('f',p.proowner))::text
    ) ORDER BY p.oid::regprocedure::text),'[]'::jsonb)
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='private' AND p.proname IN (
       'source_scoped_evidence_v3_dependency_edges','source_scoped_evidence_v3_catalog_definition_sha256',
       'source_scoped_evidence_v3_reader_probe','source_scoped_evidence_v3_consumer_probe',
       'source_scoped_evidence_v3_writer_probe','refresh_source_scoped_evidence_contract_inventory',
       'register_source_scoped_evidence_v3_deployment','reject_source_scoped_evidence_v3_bound_member_mutation',
       'reject_source_scoped_evidence_v3_consumer_mutation')),
    'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'relation',n.nspname||'.'||c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid,true)
    ) ORDER BY n.nspname,c.relname,t.tgname),'[]'::jsonb)
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE NOT t.tgisinternal AND (
       t.tgfoid='private.reject_source_scoped_evidence_v3_bound_member_mutation()'::regprocedure OR
       t.tgfoid='private.reject_source_scoped_evidence_v3_consumer_mutation()'::regprocedure OR
       (n.nspname='private' AND c.relname IN ('source_scoped_evidence_contract_inventory','source_scoped_evidence_v3_deployment')))),
    'gateway_roles',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name',rolname,'login',rolcanlogin,'inherit',rolinherit,
        'bypassrls',rolbypassrls,'superuser',rolsuper,'createdb',rolcreatedb,
        'createrole',rolcreaterole,'replication',rolreplication
      ) ORDER BY rolname),'[]'::jsonb)
      FROM pg_roles
      WHERE rolname IN ('daa_source_scoped_evidence_deployer','daa_source_scoped_evidence_gateway')),
    'gateway_membership',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'inherit',membership.inherit_option,'set',membership.set_option,'admin',membership.admin_option
      ) ORDER BY membership.roleid,membership.member),'[]'::jsonb)
      FROM pg_auth_members membership
       WHERE membership.roleid='daa_source_scoped_evidence_deployer'::regrole
       AND membership.member='daa_source_scoped_evidence_gateway'::regrole
    )
  )::text,'sha256'),'hex')
$$;
REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_task4b_contract_sha256()
  FROM PUBLIC,anon,authenticated,service_role;

-- Task 4A's v1 receipt is the immutable pre-Task-4B snapshot.  The broad
-- historical projection legitimately gains Task 4B objects, so preserve v1
-- and bind the post-addition projection in a distinct immutable v2 receipt.
DO $source_scoped_evidence_v3_task4a_receipt_transition$
DECLARE v_v1 text; v_v2 text; v_actual text;
BEGIN
  SELECT contract_sha256 INTO v_v1
    FROM private.source_scoped_evidence_v3_migration_receipt
   WHERE contract_version='source-scoped-evidence-v3-task4a-v1';
  v_actual:=private.source_scoped_evidence_v3_task4a_contract_sha256();
  IF v_v1 IS NULL OR v_v1 IS NOT DISTINCT FROM v_actual THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4A_RECEIPT_TRANSITION_INVALID';
  END IF;
  SELECT contract_sha256 INTO v_v2
    FROM private.source_scoped_evidence_v3_migration_receipt
   WHERE contract_version='source-scoped-evidence-v3-task4a-v2';
  IF v_v2 IS NULL THEN
    INSERT INTO private.source_scoped_evidence_v3_migration_receipt(contract_version,contract_sha256)
      VALUES ('source-scoped-evidence-v3-task4a-v2',v_actual);
  ELSIF v_v2 IS DISTINCT FROM v_actual THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4A_RECEIPT_V2_DRIFT';
  END IF;
END
$source_scoped_evidence_v3_task4a_receipt_transition$;

REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_dependency_edges(oid,oid)
  FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.source_scoped_evidence_v3_migration_receipt(contract_version,contract_sha256)
VALUES ('source-scoped-evidence-v3-task4b-v2',private.source_scoped_evidence_v3_task4b_contract_sha256())
ON CONFLICT (contract_version) DO NOTHING;
DO $source_scoped_evidence_v3_task4b_receipt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4b-v2'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4b_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4B_RECEIPT_DRIFT';
  END IF;
END
$source_scoped_evidence_v3_task4b_receipt$;

-- #153 Task 4C: PostgreSQL requires EXECUTE on a function referenced by a
-- view.  Keep private V3 state non-oracular by expressing binding relation-
-- ally in DB-owned views, never through a parameterised state function.
DO $source_scoped_evidence_v3_visibility_views$
BEGIN
  IF to_regprocedure('public.entitet_offentlig(text,bigint)') IS NULL THEN
    EXECUTE 'CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_fact_ids WITH (security_barrier=true) AS SELECT NULL::bigint AS id WHERE false';
    EXECUTE 'CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_assertion_ids WITH (security_barrier=true) AS SELECT NULL::bigint AS id WHERE false';
    EXECUTE 'CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_citation_ids WITH (security_barrier=true) AS SELECT NULL::bigint AS id WHERE false';
  ELSE
    EXECUTE $visibility_views$
      CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_fact_ids
        WITH (security_barrier=true) AS
      SELECT fact.id FROM public.fact fact
       WHERE public.entitet_offentlig(fact.subjekt_type,fact.subjekt_id)
         AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member WHERE member.member_kind='fact' AND member.fact_id=fact.id)
              OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id WHERE member.member_kind='fact' AND member.fact_id=fact.id AND state.visible_revision_id=revision.id));
      CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_assertion_ids
        WITH (security_barrier=true) AS
      SELECT assertion.id FROM public.assertion assertion
       WHERE ((assertion.target_type='fact' AND EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids visible_fact WHERE visible_fact.id=assertion.target_id))
           OR (assertion.target_type='relation' AND EXISTS (SELECT 1 FROM public.relation relation WHERE relation.id=assertion.target_id AND public.entitet_offentlig(relation.subjekt_type,relation.subjekt_id) AND public.entitet_offentlig(relation.objekt_type,relation.objekt_id))))
         AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member WHERE member.member_kind='assertion' AND member.assertion_id=assertion.id)
              OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id WHERE member.member_kind='assertion' AND member.assertion_id=assertion.id AND state.visible_revision_id=revision.id));
      CREATE OR REPLACE VIEW public.source_scoped_evidence_visible_citation_ids
        WITH (security_barrier=true) AS
      SELECT citation.id FROM public.citation citation
        JOIN public.assertion assertion ON assertion.id=citation.assertion_id
       WHERE EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids visible_assertion WHERE visible_assertion.id=citation.assertion_id)
         AND (NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member WHERE member.member_kind='citation' AND member.citation_id=citation.id)
              OR EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_member member JOIN private.source_scoped_evidence_v3_revision revision ON revision.id=member.revision_id JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=revision.chain_id WHERE member.member_kind='citation' AND member.citation_id=citation.id AND state.visible_revision_id=revision.id));
    $visibility_views$;
  END IF;
END
$source_scoped_evidence_v3_visibility_views$;
REVOKE ALL ON TABLE public.source_scoped_evidence_visible_fact_ids,
  public.source_scoped_evidence_visible_assertion_ids,
  public.source_scoped_evidence_visible_citation_ids
  FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE public.source_scoped_evidence_visible_fact_ids,
  public.source_scoped_evidence_visible_assertion_ids,
  public.source_scoped_evidence_visible_citation_ids TO anon,authenticated;

-- #153 Task 4C: chain state is a projection of append-only events.  The
-- trigger writes it only after the event row exists, preserving its composite
-- FK to last_event_id while serialising each chain with FOR UPDATE.
CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_chain_state_sha256(
  p_chain_id uuid,p_head_revision_id uuid,p_visible_revision_id uuid,
  p_state_version integer,p_last_event_id uuid
) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,extensions AS $$
  SELECT encode(extensions.digest(jsonb_build_object(
    'schema','source-scoped-evidence-v3-chain-state-v1',
    'chain_id',p_chain_id::text,'head_revision_id',p_head_revision_id::text,
    'visible_revision_id',p_visible_revision_id::text,
    'state_version',p_state_version,'last_event_id',p_last_event_id::text
  )::text,'sha256'),'hex')
$$;

CREATE OR REPLACE FUNCTION private.enforce_source_scoped_evidence_v3_chain_state_write()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_chain_event event
        WHERE event.id=NEW.last_event_id AND event.chain_id=NEW.chain_id
          AND event.after_state_sha256=NEW.state_sha256
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION';
  END IF;
  IF TG_OP='UPDATE' AND NEW.last_event_id IS NOT DISTINCT FROM OLD.last_event_id THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION';
  END IF;
  IF NEW.state_sha256 IS DISTINCT FROM private.source_scoped_evidence_v3_chain_state_sha256(
       NEW.chain_id,NEW.head_revision_id,NEW.visible_revision_id,NEW.state_version,NEW.last_event_id
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_HASH_INVALID';
  END IF;
  IF NEW.head_revision_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_revision revision
        WHERE revision.id=NEW.head_revision_id AND revision.chain_id=NEW.chain_id
     ) OR (NEW.visible_revision_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_revision revision
        WHERE revision.id=NEW.visible_revision_id AND revision.chain_id=NEW.chain_id
          AND revision.revision_kind='content'
     )) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_SCOPE_INVALID';
  END IF;
  IF TG_OP='UPDATE' AND (
       NEW.state_version<>OLD.state_version+1
       OR NOT EXISTS (
         SELECT 1 FROM private.source_scoped_evidence_v3_chain_event event
          WHERE event.id=NEW.last_event_id AND event.chain_id=NEW.chain_id
            AND event.predecessor_state_sha256 IS NOT DISTINCT FROM OLD.state_sha256
       )
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.enforce_source_scoped_evidence_v3_chain_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  v_head uuid; v_visible uuid; v_version integer; v_publication text; v_has_state boolean;
BEGIN
  PERFORM 1 FROM private.source_scoped_evidence_v3_chain chain WHERE chain.id=NEW.chain_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_CHAIN_NOT_FOUND'; END IF;
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state state
   WHERE state.chain_id=NEW.chain_id FOR UPDATE;
  v_has_state:=FOUND;
  IF NEW.event_type='source_revision_created' THEN
    IF NEW.publication_id IS NOT NULL
       OR (NOT v_has_state AND NEW.predecessor_state_sha256 IS NOT NULL)
       OR (v_has_state AND NEW.predecessor_state_sha256 IS DISTINCT FROM v_state.state_sha256) THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM private.source_scoped_evidence_v3_revision revision
       WHERE revision.id=NEW.revision_id AND revision.chain_id=NEW.chain_id
         AND ((NOT v_has_state AND revision.revision=1)
              OR (v_has_state AND revision.predecessor_revision_id=v_state.head_revision_id))
    ) THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID'; END IF;
    v_head:=NEW.revision_id; v_visible:=v_state.visible_revision_id;
  ELSE
    IF NOT v_has_state OR NEW.predecessor_state_sha256 IS DISTINCT FROM v_state.state_sha256 THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_STALE_STATE';
    END IF;
    v_head:=v_state.head_revision_id; v_visible:=v_state.visible_revision_id;
    SELECT publication.decision INTO v_publication FROM private.source_scoped_evidence_v3_publication publication
     WHERE publication.id=NEW.publication_id AND publication.chain_id=NEW.chain_id;
    IF NEW.event_type='eligible' THEN
      IF NEW.publication_id IS NOT NULL OR NEW.revision_id IS DISTINCT FROM v_head THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID'; END IF;
    ELSIF NEW.event_type='published' THEN
      IF v_visible IS NOT NULL OR NEW.revision_id IS DISTINCT FROM v_head OR v_publication<>'publish' THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID'; END IF;
      v_visible:=v_head;
    ELSIF NEW.event_type='superseded' THEN
      IF v_visible IS NULL OR v_visible=NEW.revision_id OR NEW.revision_id IS DISTINCT FROM v_head OR v_publication<>'supersede' THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID'; END IF;
      v_visible:=v_head;
    ELSIF NEW.event_type='withdrawn' THEN
      IF v_visible IS NULL OR NEW.revision_id IS DISTINCT FROM v_head OR v_publication<>'withdraw' OR NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_revision revision WHERE revision.id=v_head AND revision.revision_kind='tombstone') THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID'; END IF;
      v_visible:=NULL;
    ELSE RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID';
    END IF;
  END IF;
  v_version:=coalesce(v_state.state_version,0)+1;
  IF NEW.after_state_sha256 IS DISTINCT FROM private.source_scoped_evidence_v3_chain_state_sha256(NEW.chain_id,v_head,v_visible,v_version,NEW.id) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_HASH_INVALID';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.project_source_scoped_evidence_v3_chain_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
BEGIN
  INSERT INTO private.source_scoped_evidence_v3_chain_state(
    chain_id,head_revision_id,visible_revision_id,state_version,state_sha256,last_event_id
  ) SELECT NEW.chain_id,NEW.revision_id,
      CASE WHEN NEW.event_type IN ('published','superseded') THEN NEW.revision_id
           WHEN NEW.event_type='withdrawn' THEN NULL ELSE state.visible_revision_id END,
      coalesce(state.state_version,0)+1,NEW.after_state_sha256,NEW.id
    FROM (SELECT NEW.chain_id) input
    LEFT JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=input.chain_id
  ON CONFLICT (chain_id) DO UPDATE SET
    head_revision_id=CASE WHEN NEW.event_type='source_revision_created' THEN NEW.revision_id ELSE private.source_scoped_evidence_v3_chain_state.head_revision_id END,
    visible_revision_id=EXCLUDED.visible_revision_id,
    state_version=EXCLUDED.state_version,state_sha256=EXCLUDED.state_sha256,last_event_id=EXCLUDED.last_event_id;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_source_scoped_evidence_v3_chain_state_guard
  BEFORE INSERT OR UPDATE OR DELETE ON private.source_scoped_evidence_v3_chain_state
  FOR EACH ROW EXECUTE FUNCTION private.enforce_source_scoped_evidence_v3_chain_state_write();
CREATE TRIGGER trg_source_scoped_evidence_v3_chain_event_transition
  BEFORE INSERT ON private.source_scoped_evidence_v3_chain_event
  FOR EACH ROW EXECUTE FUNCTION private.enforce_source_scoped_evidence_v3_chain_event();
CREATE TRIGGER trg_source_scoped_evidence_v3_chain_event_project
  AFTER INSERT ON private.source_scoped_evidence_v3_chain_event
  FOR EACH ROW EXECUTE FUNCTION private.project_source_scoped_evidence_v3_chain_event();
REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_chain_state_sha256(uuid,uuid,uuid,integer,uuid),
  private.enforce_source_scoped_evidence_v3_chain_state_write(),
  private.enforce_source_scoped_evidence_v3_chain_event(),
  private.project_source_scoped_evidence_v3_chain_event()
  FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.source_scoped_evidence_v3_migration_receipt(contract_version,contract_sha256)
VALUES ('source-scoped-evidence-v3-task4a-v3',private.source_scoped_evidence_v3_task4a_contract_sha256())
ON CONFLICT (contract_version) DO NOTHING;
DO $source_scoped_evidence_v3_task4c_receipt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v3'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4a_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TASK4C_RECEIPT_DRIFT';
  END IF;
END
$source_scoped_evidence_v3_task4c_receipt$;

-- #153 Task 4C: publication uses its own single-use authorization ledger.
-- Its name intentionally stays outside Task 4A's frozen V3 relation prefix;
-- the ledger is protected by its own append-only trigger and ACL instead.
CREATE TABLE private.source_scoped_evidence_publication_v3_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_chain(id),
  revision_id uuid NOT NULL,
  deployment_id uuid NOT NULL REFERENCES private.source_scoped_evidence_v3_deployment(id),
  deployment_sha256 text NOT NULL CHECK (deployment_sha256 ~ '^[0-9a-f]{64}$'),
  expected_state_sha256 text NOT NULL CHECK (expected_state_sha256 ~ '^[0-9a-f]{64}$'),
  decision_payload jsonb NOT NULL CHECK (jsonb_typeof(decision_payload)='object'),
  decision_payload_sha256 text NOT NULL CHECK (decision_payload_sha256 ~ '^[0-9a-f]{64}$'),
  actor_id uuid NOT NULL, nonce uuid NOT NULL UNIQUE, expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  receipt jsonb CONSTRAINT source_scoped_evidence_pub_auth_receipt_json_ck
    CHECK (receipt IS NULL OR jsonb_typeof(receipt)='object'),
  receipt_sha256 text CONSTRAINT source_scoped_evidence_pub_auth_receipt_hash_ck
    CHECK (receipt_sha256 IS NULL OR receipt_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT source_scoped_evidence_pub_auth_receipt_pair_ck
    CHECK ((receipt IS NULL)=(receipt_sha256 IS NULL)),
  FOREIGN KEY (revision_id,chain_id) REFERENCES private.source_scoped_evidence_v3_revision(id,chain_id)
);
CREATE OR REPLACE FUNCTION private.enforce_source_scoped_evidence_publication_v3_authorization_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,extensions AS $$
BEGIN
  IF TG_OP='DELETE' OR OLD.consumed_at IS NOT NULL OR NEW.consumed_at IS NULL
     OR NEW.receipt IS NULL OR NEW.receipt_sha256 IS NULL
     OR NEW.receipt_sha256 IS DISTINCT FROM encode(extensions.digest(NEW.receipt::text,'sha256'),'hex')
     OR (to_jsonb(NEW)-ARRAY['consumed_at','receipt','receipt_sha256'])
          IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['consumed_at','receipt','receipt_sha256']) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_APPEND_ONLY';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_source_scoped_evidence_pub_auth_append_only
  BEFORE UPDATE OR DELETE ON private.source_scoped_evidence_publication_v3_authorization
  FOR EACH ROW EXECUTE FUNCTION private.enforce_source_scoped_evidence_publication_v3_authorization_mutation();
ALTER TABLE private.source_scoped_evidence_publication_v3_authorization ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.source_scoped_evidence_publication_v3_authorization
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.enforce_source_scoped_evidence_publication_v3_authorization_mutation()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_publication_decision_sha256(
  p_payload jsonb
) RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,extensions
AS $$
  SELECT encode(extensions.digest(p_payload::text,'sha256'),'hex')
$$;

-- Task 4C publication decisions have a deliberately closed payload.  The
-- second-stage RPC must receive these exact canonical bytes again; accepting
-- an open-ended "reason" object would make the human approval unauditable.
CREATE OR REPLACE FUNCTION private.validate_source_scoped_evidence_v3_publication_decision(
  p_chain_id uuid,p_revision_id uuid,p_deployment_id uuid,p_expected_state_sha256 text,
  p_decision_payload jsonb
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,private
AS $$
DECLARE v_decision text;
BEGIN
  IF p_expected_state_sha256 !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(p_decision_payload)<>'object'
     OR NOT (p_decision_payload ?& ARRAY[
       'schema','chain_id','revision_id','deployment_id','deployment_sha256',
       'expected_state_sha256','decision','rationale'
     ])
     OR (p_decision_payload - ARRAY[
       'schema','chain_id','revision_id','deployment_id','deployment_sha256',
       'expected_state_sha256','decision','rationale'
     ]) <> '{}'::jsonb
     OR p_decision_payload->>'schema'<>'source-scoped-evidence-v3-publication-decision-v1'
     OR p_decision_payload->>'chain_id' IS DISTINCT FROM p_chain_id::text
     OR p_decision_payload->>'revision_id' IS DISTINCT FROM p_revision_id::text
     OR p_decision_payload->>'deployment_id' IS DISTINCT FROM p_deployment_id::text
     OR p_decision_payload->>'expected_state_sha256' IS DISTINCT FROM p_expected_state_sha256
     OR p_decision_payload->>'deployment_sha256' !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(p_decision_payload->>'rationale'),'') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DECISION_INVALID';
  END IF;
  v_decision:=p_decision_payload->>'decision';
  IF v_decision NOT IN ('publish','supersede','withdraw') THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DECISION_INVALID';
  END IF;
  RETURN v_decision;
END
$$;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_publication_consumer_exists(
  p_revision_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,public,private
AS $$
  WITH members AS (
    SELECT member.member_kind,coalesce(member.fact_id,member.assertion_id,member.citation_id) AS member_id
      FROM private.source_scoped_evidence_v3_member member
     WHERE member.revision_id=p_revision_id
  )
  SELECT EXISTS (
    SELECT 1 FROM public.conclusion conclusion JOIN members member
      ON (member.member_kind='assertion' AND conclusion.valgt_assertion_id=member.member_id)
      OR (conclusion.target_type=member.member_kind AND conclusion.target_id=member.member_id)
    UNION ALL
    SELECT 1 FROM public.note note JOIN members member
      ON note.target_type=member.member_kind AND note.target_id=member.member_id
    UNION ALL
    SELECT 1 FROM public.relation relation JOIN members member
      ON (relation.subjekt_type=member.member_kind AND relation.subjekt_id=member.member_id)
      OR (relation.objekt_type=member.member_kind AND relation.objekt_id=member.member_id)
    UNION ALL
    SELECT 1 FROM public.haendelse event JOIN members member
      ON (member.member_kind='fact' AND event.fact_id=member.member_id)
      OR (event.subjekt_type=member.member_kind AND event.subjekt_id=member.member_id)
    UNION ALL
    SELECT 1 FROM public.story story JOIN members member
      ON (member.member_kind='fact' AND story.fact_id=member.member_id)
      OR (story.subjekt_type=member.member_kind AND story.subjekt_id=member.member_id)
    UNION ALL
    SELECT 1 FROM public.change_set change_set JOIN members member
      ON change_set.subjekt_type=member.member_kind AND change_set.subjekt_id=member.member_id
    UNION ALL
    SELECT 1 FROM public.entity_description description JOIN members member
      ON description.subjekt_type=member.member_kind AND description.subjekt_id=member.member_id
    UNION ALL
    SELECT 1 FROM public.narrative narrative JOIN members member
      ON narrative.subjekt_type=member.member_kind AND narrative.subjekt_id=member.member_id
    UNION ALL
    SELECT 1 FROM public.suggestion suggestion JOIN members member
      ON suggestion.subjekt_type=member.member_kind AND suggestion.subjekt_id=member.member_id
    UNION ALL
    SELECT 1 FROM private.interpretation_promotion promotion JOIN members member
      ON promotion.target_type=member.member_kind AND promotion.target_id=member.member_id
    UNION ALL
    SELECT 1 FROM private.reimport_1939_name_completion_result completion JOIN members member
      ON (member.member_kind='fact' AND completion.fact_id=member.member_id)
      OR (member.member_kind='assertion' AND completion.assertion_id=member.member_id)
      OR (member.member_kind='citation' AND completion.citation_id=member.member_id)
  )
$$;

CREATE OR REPLACE FUNCTION public.red_authorize_source_scoped_evidence_publication_v3(
  p_chain_id uuid,p_revision_id uuid,p_deployment_id uuid,p_expected_state_sha256 text,
  p_decision_payload jsonb,p_nonce uuid,p_expires_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog,public,private,extensions
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_deployment private.source_scoped_evidence_v3_deployment%ROWTYPE;
  v_chain private.source_scoped_evidence_v3_chain%ROWTYPE;
  v_revision private.source_scoped_evidence_v3_revision%ROWTYPE;
  v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  v_decision text;
  v_id uuid;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_ROLE_FORBIDDEN';
  END IF;
  IF p_chain_id IS NULL OR p_revision_id IS NULL OR p_deployment_id IS NULL
     OR p_nonce IS NULL OR p_expires_at IS NULL OR p_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
  END IF;
  v_decision:=private.validate_source_scoped_evidence_v3_publication_decision(
    p_chain_id,p_revision_id,p_deployment_id,p_expected_state_sha256,p_decision_payload
  );
  SELECT * INTO v_deployment
    FROM private.source_scoped_evidence_v3_deployment deployment
   WHERE deployment.id=p_deployment_id;
  IF NOT FOUND
     OR v_deployment.deployment_sha256 IS DISTINCT FROM p_decision_payload->>'deployment_sha256'
     OR v_deployment.database_name IS DISTINCT FROM current_database()
     OR v_deployment.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DEPLOYMENT_INVALID';
  END IF;
  IF v_deployment.inventory_id IS DISTINCT FROM private.refresh_source_scoped_evidence_contract_inventory(
       v_deployment.schema_contract_version
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_INVENTORY_DRIFT';
  END IF;

  -- Shared order: narrative contract, source record, audit allocation, person,
  -- #152 evidence anchors, then V3 chain/model/ledger.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  SELECT * INTO v_chain FROM private.source_scoped_evidence_v3_chain chain
   WHERE chain.id=p_chain_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_SCOPE_INVALID'; END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('daa-source-scoped-replace:'||v_chain.source_id::text,0)
  );
  -- #152 owns the complete record-first lock map. Reusing its locked state
  -- projection prevents publication from silently omitting a shared resource.
  PERFORM private.narrative_record_state(
    v_chain.canonical_person_id,v_chain.source_id,v_chain.source_record_key,true
  );
  SELECT * INTO v_chain FROM private.source_scoped_evidence_v3_chain chain
   WHERE chain.id=p_chain_id FOR UPDATE;
  SELECT * INTO v_revision FROM private.source_scoped_evidence_v3_revision revision
   WHERE revision.id=p_revision_id AND revision.chain_id=v_chain.id FOR UPDATE;
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state state
   WHERE state.chain_id=v_chain.id FOR UPDATE;
  IF NOT FOUND
     OR v_state.state_sha256 IS DISTINCT FROM p_expected_state_sha256
     OR v_state.head_revision_id IS DISTINCT FROM p_revision_id
     OR NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_chain_event event
        WHERE event.id=v_state.last_event_id AND event.event_type='eligible'
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.source_record record
        WHERE record.id=v_chain.source_record_id AND record.source_id=v_chain.source_id
          AND record.record_key=v_chain.source_record_key
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.source_persona persona
        JOIN private.source_persona_placement_current persona_placement
          ON persona_placement.source_persona_id=persona.id
        JOIN private.source_record_placement_current record_placement
          ON record_placement.id=persona_placement.record_placement_id
        JOIN private.source_persona_identity identity_state
          ON identity_state.source_persona_id=persona.id
        WHERE persona.id=v_chain.source_persona_id AND persona.source_id=v_chain.source_id
          AND record_placement.source_record_id=v_chain.source_record_id
          AND record_placement.decision_status='accepted'
          AND persona_placement.decision_status='accepted'
          AND identity_state.decision_status='accepted'
          AND identity_state.canonical_person_id=v_chain.canonical_person_id
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_STALE';
  END IF;
  IF (v_decision='publish' AND (v_revision.revision_kind<>'content' OR v_state.visible_revision_id IS NOT NULL))
     OR (v_decision='supersede' AND (v_revision.revision_kind<>'content' OR v_state.visible_revision_id IS NULL
          OR v_state.visible_revision_id=v_revision.id))
     OR (v_decision='withdraw' AND (v_revision.revision_kind<>'tombstone' OR v_state.visible_revision_id IS NULL)) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_TRANSITION_INVALID';
  END IF;
  IF EXISTS (SELECT 1 FROM private.source_scoped_evidence_publication_v3_authorization auth_row
              WHERE auth_row.nonce=p_nonce) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_NONCE_REPLAY';
  END IF;
  INSERT INTO private.source_scoped_evidence_publication_v3_authorization(
    chain_id,revision_id,deployment_id,deployment_sha256,expected_state_sha256,
    decision_payload,decision_payload_sha256,actor_id,nonce,expires_at
  ) VALUES (
    p_chain_id,p_revision_id,p_deployment_id,v_deployment.deployment_sha256,p_expected_state_sha256,
    p_decision_payload,private.source_scoped_evidence_v3_publication_decision_sha256(p_decision_payload),
    v_actor,p_nonce,p_expires_at
  ) RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_NONCE_REPLAY';
END
$$;

CREATE OR REPLACE FUNCTION public.red_publish_source_scoped_evidence_revision_v3(
  p_authorization_id uuid,p_decision_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog,public,private,extensions
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_authorization private.source_scoped_evidence_publication_v3_authorization%ROWTYPE;
  v_deployment private.source_scoped_evidence_v3_deployment%ROWTYPE;
  v_chain private.source_scoped_evidence_v3_chain%ROWTYPE;
  v_revision private.source_scoped_evidence_v3_revision%ROWTYPE;
  v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  v_decision text;
  v_publication_id uuid;
  v_event_id uuid:=gen_random_uuid();
  v_event_type text;
  v_next_visible uuid;
  v_next_hash text;
  v_supersedes_publication_id uuid;
  v_receipt jsonb;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_ROLE_FORBIDDEN';
  END IF;
  SELECT * INTO v_authorization
    FROM private.source_scoped_evidence_publication_v3_authorization authorization_row
   WHERE authorization_row.id=p_authorization_id;
  IF NOT FOUND OR v_authorization.actor_id IS DISTINCT FROM v_actor
     OR v_authorization.decision_payload IS DISTINCT FROM p_decision_payload
     OR v_authorization.decision_payload_sha256 IS DISTINCT FROM
          private.source_scoped_evidence_v3_publication_decision_sha256(p_decision_payload) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
  END IF;
  IF v_authorization.consumed_at IS NOT NULL THEN
    IF v_authorization.receipt IS NULL
       OR v_authorization.receipt_sha256 IS DISTINCT FROM encode(extensions.digest(v_authorization.receipt::text,'sha256'),'hex') THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
    END IF;
    RETURN v_authorization.receipt;
  END IF;
  IF v_authorization.expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
  END IF;
  v_decision:=private.validate_source_scoped_evidence_v3_publication_decision(
    v_authorization.chain_id,v_authorization.revision_id,v_authorization.deployment_id,
    v_authorization.expected_state_sha256,p_decision_payload
  );
  SELECT * INTO v_deployment FROM private.source_scoped_evidence_v3_deployment deployment
   WHERE deployment.id=v_authorization.deployment_id;
  IF NOT FOUND OR v_deployment.deployment_sha256 IS DISTINCT FROM v_authorization.deployment_sha256
     OR v_deployment.database_name IS DISTINCT FROM current_database()
     OR v_deployment.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text
     OR v_deployment.inventory_id IS DISTINCT FROM private.refresh_source_scoped_evidence_contract_inventory(
          v_deployment.schema_contract_version
        ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DEPLOYMENT_INVALID';
  END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  SELECT * INTO v_chain FROM private.source_scoped_evidence_v3_chain chain
   WHERE chain.id=v_authorization.chain_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_SCOPE_INVALID'; END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('daa-source-scoped-replace:'||v_chain.source_id::text,0)
  );
  -- Use the same complete #152 prelock before V3 chain/model/ledger locks.
  PERFORM private.narrative_record_state(
    v_chain.canonical_person_id,v_chain.source_id,v_chain.source_record_key,true
  );
  SELECT * INTO v_chain FROM private.source_scoped_evidence_v3_chain chain
   WHERE chain.id=v_authorization.chain_id FOR UPDATE;
  SELECT * INTO v_revision FROM private.source_scoped_evidence_v3_revision revision
   WHERE revision.id=v_authorization.revision_id AND revision.chain_id=v_chain.id FOR UPDATE;
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state state
   WHERE state.chain_id=v_chain.id FOR UPDATE;
  IF v_revision.revision_kind='content' THEN
    PERFORM 1 FROM private.source_scoped_evidence_v3_member member
     WHERE member.revision_id=v_revision.id ORDER BY member.member_kind,member.member_key FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_STALE';
    END IF;
  END IF;
  IF v_state.state_sha256 IS DISTINCT FROM v_authorization.expected_state_sha256
     OR v_state.head_revision_id IS DISTINCT FROM v_revision.id
     OR NOT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_chain_event event
                     WHERE event.id=v_state.last_event_id AND event.event_type='eligible')
     OR NOT EXISTS (
       SELECT 1 FROM private.source_persona persona
        JOIN private.source_persona_placement_current persona_placement
          ON persona_placement.source_persona_id=persona.id
        JOIN private.source_record_placement_current record_placement
          ON record_placement.id=persona_placement.record_placement_id
        JOIN private.source_persona_identity identity_state
          ON identity_state.source_persona_id=persona.id
        WHERE persona.id=v_chain.source_persona_id AND persona.source_id=v_chain.source_id
          AND record_placement.source_record_id=v_chain.source_record_id
          AND record_placement.decision_status='accepted'
          AND persona_placement.decision_status='accepted'
          AND identity_state.decision_status='accepted'
          AND identity_state.canonical_person_id=v_chain.canonical_person_id
     ) THEN
    -- The shared chain locks intentionally precede the terminal authorization
    -- lock. A concurrent replay can therefore observe the successor state
    -- before it reaches that lock; return the immutable, hash-verified receipt
    -- once the first caller has consumed this exact authorization.
    SELECT * INTO v_authorization
      FROM private.source_scoped_evidence_publication_v3_authorization authorization_row
     WHERE authorization_row.id=p_authorization_id FOR UPDATE;
    IF v_authorization.consumed_at IS NOT NULL THEN
      IF v_authorization.receipt IS NULL
         OR v_authorization.receipt_sha256 IS DISTINCT FROM encode(extensions.digest(v_authorization.receipt::text,'sha256'),'hex') THEN
        RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
      END IF;
      RETURN v_authorization.receipt;
    END IF;
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_STALE';
  END IF;
  IF v_decision IN ('supersede','withdraw')
     AND private.source_scoped_evidence_v3_publication_consumer_exists(v_state.visible_revision_id) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_CONSUMER_NO_GO';
  END IF;
  IF v_decision='publish' AND v_revision.revision_kind='content' AND v_state.visible_revision_id IS NULL THEN
    v_event_type:='published'; v_next_visible:=v_revision.id;
  ELSIF v_decision='supersede' AND v_revision.revision_kind='content' AND v_state.visible_revision_id IS NOT NULL THEN
    v_event_type:='superseded'; v_next_visible:=v_revision.id;
  ELSIF v_decision='withdraw' AND v_revision.revision_kind='tombstone' AND v_state.visible_revision_id IS NOT NULL THEN
    v_event_type:='withdrawn'; v_next_visible:=NULL;
  ELSE
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_TRANSITION_INVALID';
  END IF;
  IF v_decision='supersede' THEN
    SELECT event.publication_id INTO v_supersedes_publication_id
      FROM private.source_scoped_evidence_v3_chain_event event
     WHERE event.chain_id=v_chain.id
       AND event.revision_id=v_state.visible_revision_id
       AND event.event_type IN ('published','superseded')
     ORDER BY event.created_at DESC,event.id DESC
     LIMIT 1;
    IF v_supersedes_publication_id IS NULL THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_STALE';
    END IF;
  END IF;
  -- Authorisation is deliberately locked last: the preceding calls own the
  -- shared #152 lock map, while this row is only the terminal single-use
  -- ledger.  A concurrent first caller therefore yields its stored receipt.
  SELECT * INTO v_authorization
    FROM private.source_scoped_evidence_publication_v3_authorization authorization_row
   WHERE authorization_row.id=p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_authorization.actor_id IS DISTINCT FROM v_actor
     OR v_authorization.decision_payload IS DISTINCT FROM p_decision_payload
     OR v_authorization.decision_payload_sha256 IS DISTINCT FROM
          private.source_scoped_evidence_v3_publication_decision_sha256(p_decision_payload) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
  END IF;
  IF v_authorization.consumed_at IS NOT NULL THEN
    IF v_authorization.receipt IS NULL
       OR v_authorization.receipt_sha256 IS DISTINCT FROM encode(extensions.digest(v_authorization.receipt::text,'sha256'),'hex') THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
    END IF;
    RETURN v_authorization.receipt;
  END IF;
  IF v_authorization.expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID';
  END IF;
  v_next_hash:=private.source_scoped_evidence_v3_chain_state_sha256(
    v_chain.id,v_revision.id,v_next_visible,v_state.state_version+1,v_event_id
  );
  INSERT INTO private.source_scoped_evidence_v3_publication(
    chain_id,revision_id,decision,decision_state_sha256,decision_payload,decided_by,supersedes_publication_id
  ) VALUES (
    v_chain.id,v_revision.id,v_decision,v_state.state_sha256,p_decision_payload,v_actor,
    v_supersedes_publication_id
  ) RETURNING id INTO v_publication_id;
  INSERT INTO private.source_scoped_evidence_v3_chain_event(
    id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id,publication_id
  ) VALUES (
    v_event_id,v_chain.id,v_event_type,v_state.state_sha256,v_next_hash,v_revision.id,v_publication_id
  );
  v_receipt:=jsonb_build_object(
    'schema','source-scoped-evidence-v3-publication-receipt-v1',
    'authorization_id',v_authorization.id,'publication_id',v_publication_id,
    'chain_id',v_chain.id,'revision_id',v_revision.id,'decision',v_decision,
    'decision_payload_sha256',v_authorization.decision_payload_sha256,
    'deployment_id',v_deployment.id,'deployment_sha256',v_deployment.deployment_sha256,
    'database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text,
    'before_state_sha256',v_state.state_sha256,'after_state_sha256',v_next_hash
  );
  UPDATE private.source_scoped_evidence_publication_v3_authorization
     SET consumed_at=clock_timestamp(),receipt=v_receipt,
         receipt_sha256=encode(extensions.digest(v_receipt::text,'sha256'),'hex')
   WHERE id=v_authorization.id;
  RETURN v_receipt;
END
$$;

REVOKE ALL ON FUNCTION
  private.source_scoped_evidence_v3_publication_decision_sha256(jsonb),
  private.validate_source_scoped_evidence_v3_publication_decision(uuid,uuid,uuid,text,jsonb),
  private.source_scoped_evidence_v3_publication_consumer_exists(uuid),
  public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamptz),
  public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamptz),
  public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_task4c_contract_sha256()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,private,extensions
AS $$
  SELECT encode(extensions.digest(jsonb_build_object(
    'schema','source-scoped-evidence-v3-task4c-v5',
    'table',(
      SELECT jsonb_build_object(
        'columns',coalesce(jsonb_agg(jsonb_build_object(
          'position',attribute.attnum,'name',attribute.attname,
          'type',format_type(attribute.atttypid,attribute.atttypmod),
          'not_null',attribute.attnotnull,'default',pg_get_expr(default_value.adbin,default_value.adrelid)
        ) ORDER BY attribute.attnum),'[]'::jsonb),
        'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'name',constraint_row.conname,'definition',pg_get_constraintdef(constraint_row.oid,true)
        ) ORDER BY constraint_row.conname),'[]'::jsonb)
          FROM pg_constraint constraint_row
         WHERE constraint_row.conrelid='private.source_scoped_evidence_publication_v3_authorization'::regclass),
        'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'name',trigger.tgname,'definition',pg_get_triggerdef(trigger.oid,true)
        ) ORDER BY trigger.tgname),'[]'::jsonb)
          FROM pg_trigger trigger
         WHERE trigger.tgrelid='private.source_scoped_evidence_publication_v3_authorization'::regclass
           AND NOT trigger.tgisinternal),
        'acl',coalesce((SELECT relation.relacl::text FROM pg_class relation
                         WHERE relation.oid='private.source_scoped_evidence_publication_v3_authorization'::regclass),'{}')
      )
        FROM pg_attribute attribute
        LEFT JOIN pg_attrdef default_value
          ON default_value.adrelid=attribute.attrelid AND default_value.adnum=attribute.attnum
       WHERE attribute.attrelid='private.source_scoped_evidence_publication_v3_authorization'::regclass
         AND attribute.attnum>0 AND NOT attribute.attisdropped
    ),
    'state_projection',(SELECT jsonb_build_object(
      'relations',coalesce(jsonb_agg(jsonb_build_object(
        'name',relation.relname,'columns',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'position',attribute.attnum,'name',attribute.attname,
          'type',format_type(attribute.atttypid,attribute.atttypmod),
          'not_null',attribute.attnotnull
        ) ORDER BY attribute.attnum),'[]'::jsonb) FROM pg_attribute attribute
         WHERE attribute.attrelid=relation.oid AND attribute.attnum>0 AND NOT attribute.attisdropped),
        'rls',relation.relrowsecurity,'force_rls',relation.relforcerowsecurity,
        'acl',coalesce(relation.relacl,'{}'::aclitem[])::text
      ) ORDER BY relation.relname),'[]'::jsonb),
      'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'relation',relation.relname,'name',trigger.tgname,'definition',pg_get_triggerdef(trigger.oid,true)
      ) ORDER BY relation.relname,trigger.tgname),'[]'::jsonb) FROM pg_trigger trigger
        JOIN pg_class relation ON relation.oid=trigger.tgrelid
       WHERE relation.oid=ANY(ARRAY[
         'private.source_scoped_evidence_v3_chain_state'::regclass,
         'private.source_scoped_evidence_v3_chain_event'::regclass
       ]) AND NOT trigger.tgisinternal)
    ) FROM pg_class relation WHERE relation.oid=ANY(ARRAY[
      'private.source_scoped_evidence_v3_chain_state'::regclass,
      'private.source_scoped_evidence_v3_chain_event'::regclass
    ])),
    'visibility_views',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name',relation.relname,'definition',pg_get_viewdef(relation.oid,true),
      'options',relation.reloptions,'acl',coalesce(relation.relacl,'{}'::aclitem[])::text
    ) ORDER BY relation.relname),'[]'::jsonb) FROM pg_class relation
     WHERE relation.oid=ANY(ARRAY[
       'public.source_scoped_evidence_visible_fact_ids'::regclass,
       'public.source_scoped_evidence_visible_assertion_ids'::regclass,
       'public.source_scoped_evidence_visible_citation_ids'::regclass
     ])),
    'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'signature',routine.oid::regprocedure::text,
      'definition',CASE
        WHEN routine.proname=ANY(ARRAY[
          'source_scoped_evidence_v3_chain_state_sha256',
          'enforce_source_scoped_evidence_v3_chain_state_write',
          'enforce_source_scoped_evidence_v3_chain_event',
          'project_source_scoped_evidence_v3_chain_event'
        ]) THEN regexp_replace(pg_get_functiondef(routine.oid),'[[:space:]]+',' ','g')
        ELSE pg_get_functiondef(routine.oid)
      END,
      'acl',coalesce(routine.proacl,acldefault('f',routine.proowner))::text
    ) ORDER BY routine.oid::regprocedure::text),'[]'::jsonb)
      FROM pg_proc routine
      JOIN pg_namespace namespace ON namespace.oid=routine.pronamespace
     WHERE (namespace.nspname='private' AND routine.proname=ANY(ARRAY[
              'enforce_source_scoped_evidence_publication_v3_authorization_mutation',
              'source_scoped_evidence_v3_publication_decision_sha256',
              'validate_source_scoped_evidence_v3_publication_decision',
              'source_scoped_evidence_v3_publication_consumer_exists',
              'source_scoped_evidence_v3_chain_state_sha256',
              'enforce_source_scoped_evidence_v3_chain_state_write',
              'enforce_source_scoped_evidence_v3_chain_event',
              'project_source_scoped_evidence_v3_chain_event'
            ]))
        OR (namespace.nspname='public' AND routine.proname=ANY(ARRAY[
              'red_authorize_source_scoped_evidence_publication_v3',
              'red_publish_source_scoped_evidence_revision_v3'
            ])))
  )::text,'sha256'),'hex')
$$;
REVOKE ALL ON FUNCTION private.source_scoped_evidence_v3_task4c_contract_sha256()
  FROM PUBLIC,anon,authenticated,service_role;
