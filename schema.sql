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
  repository_id BIGINT REFERENCES repository(id)
);

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
  slaegtled_lokal  INTEGER,                -- slægtled lokalt i linjen (1,2,3… fra grenens start)
  slaegtled_gennem INTEGER,                -- gennemgående slægtled (parentes-tallet i bogen)
  kuld             TEXT,                    -- børne-gruppe-markør (romertal) inde i grenen; proveniens + gruppering
  PRIMARY KEY (person_id, source_id)
);

CREATE TABLE lineage (                   -- SLÆGTSLINJE / GREN (fx Reventlows fem linjer)
  id        BIGINT PRIMARY KEY,
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
  UNIQUE (source_id, kode)
  -- Resten af (b) kræver INGEN skema-ændring — den rider på de polymorfe evidens-tabeller:
  --   * fact     subjekt_type='lineage'  → adling, floruit, alternative navne m. evidens
  --   * relation lineage→coat_of_arms / →source / person→lineage (konfidens på medlemskab)
  -- En linje der adles → ny lineage-række + relation rolle='gren_af' til moderlinjen
  --   (parent_lineage_id er den hurtige FK; 'gren_af'-relationen bærer evidens/konfidens).
  -- Jf. datamodel-oversigt §5/§9.
);

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
  konfidens   TEXT
);

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
-- Note (id-tildeling): basen bruger eksplicitte BIGINT-PK'er (ikke IDENTITY) — derfor `max(id)+1`
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
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
            p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
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

-- ============================================================================
-- Redaktionel identitets-sammenkædning (samme_som) — spec 2026-07-02, Codex-3.
-- Invarianten (træer, præcis én sink pr. komponent) håndhæves i en TRIGGER, så den gælder ALLE
-- insert-veje (RPC/undo/load-script/manuel), ikke kun red_samme_som.
-- ============================================================================
CREATE OR REPLACE FUNCTION enforce_samme_som_invariants() RETURNS trigger
LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.rolle <> 'samme_som' OR NEW.subjekt_type <> 'person' OR NEW.objekt_type <> 'person' THEN
    RETURN NEW; -- ikke et person→person samme_som — rør ikke
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation')); -- serialisér samme_som-inserts
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
  -- (Cyklus kan ikke opstå her: en ny alias→kanonisk-kant lukker kun en cyklus hvis alias er reachable
  -- fra kanonisk, dvs. alias har en indgående kant og dermed er et objekt — hvilket G4 allerede afviser.
  -- G3+G4 håndhæver derfor invarianten fuldt. En eksplicit graf-walk her ville være død kode + kunne
  -- fejle en urelateret insert hvis en cyklus var pre-injiceret via trigger-disabled rå-SQL.)
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_samme_som ON relation;
CREATE TRIGGER trg_enforce_samme_som BEFORE INSERT ON relation
  FOR EACH ROW WHEN (NEW.rolle = 'samme_som') EXECUTE FUNCTION enforce_samme_som_invariants();

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
  -- Cyklus: er en partner i family en efterkommer af barnet?
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
  v_media := red_opret_media(p_slags, p_titel, NULL, NULL, 'media', p_storage_path,
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
  ('family',             ARRAY['id'], '{}'),
  ('family_member',      ARRAY['family_id','person_id','rolle'], '{}'),
  ('fact',               ARRAY['id'], '{}'),
  ('relation',           ARRAY['id'], '{}'),
  ('assertion',          ARRAY['id'], '{}'),
  ('conclusion',         ARRAY['id'], '{}'),
  ('citation',           ARRAY['id'], '{}'),
  ('narrative',          ARRAY['id'], '{}'),
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

-- Upsert til nøjagtig snapshot-tilstand. Manglende (skip-)kolonner → NULL (cache regenereres efter).
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_pk_cols text; v_set text; v_cols text;
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

CREATE OR REPLACE FUNCTION hist_events(p_change_set_id bigint)
RETURNS SETOF change_event LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq;
END $$;

-- Døde links: mentions hvis mål ikke længere findes (kun person/estate/lineage vist; udvid efter behov).
CREATE OR REPLACE VIEW red_doede_links WITH (security_invoker = true) AS
SELECT m.* FROM text_mention m
WHERE (m.maal_type='person' AND NOT EXISTS (SELECT 1 FROM person  p WHERE p.id=m.maal_id))
   OR (m.maal_type='estate' AND NOT EXISTS (SELECT 1 FROM estate  e WHERE e.id=m.maal_id))
   OR (m.maal_type='lineage' AND NOT EXISTS (SELECT 1 FROM lineage l WHERE l.id=m.maal_id));
