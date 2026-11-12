-- Læse-kun kandidatliste til §4.3's datoversioner (spec 2026-11-02 §4.3; ceremoni 3, første halvdel): kildens aktuelle
-- datoforslag, som normaliseringsreglen ændrer (standard dato-markoer-v1). Afgrænsningen står i normaliser_kandidat_liste.sql.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] [-v regel=dato-markoer-v1|dato-markoer-v2] -f normaliser_kandidater.sql
-- Udskrift (kun antal, id'er, versioner og en hash; ingen værdier):
--   T6C2_NORMALISER antal=<n> kandidater_sha256=<hex>
--   <interpretation_id>|<version>   én pr. linje, stigende på interpretation_id (uuid-orden)
-- kandidater_sha256 er sha256 over listen '<interpretation_id>:<version>,…' i samme orden (UTF-8; tom liste: sha256
-- af ''). Bliver en kandidats værdi tom efter reglen, stopper scriptet med NORMALISER_VAERDI_TOM (kun antallet):
-- RPC'en ville afvise den i ceremonien.
-- Kilden kommer fra -v source_id (standard 3); den står aldrig fast i koden. Reglen kommer fra -v regel (standard
-- dato-markoer-v1, så ældre kald er uændrede; ukendt regel stopper med NORMALISER_REGEL_UKENDT). Kræver 6c-2b
-- (og 6c-2b's v2-tilføjelse for dato-markoer-v2).
--
-- Runnerkontrakt (ceremoni 3, før linjeskift-v1). GO-pakken bærer reglen, listen (daa.normaliser_kandidater-formen) og
-- kandidater_sha256. Er listen tom, springes (b)-(d) over. I skrive-transaktionen:
--   (a) sæt daa.normaliser_kilde = kilden og daa.normaliser_regel = GO-pakkens regel, \ir normaliser_kandidat_liste.sql, og RAISE, hvis daa.normaliser_kandidater
--       ikke er identisk med GO-pakkens liste, eller daa.normaliser_kandidater_sha256 afviger fra GO-pakkens sha.
--   (b) opret ÉN private.extraction_run-række til ceremonien og sæt daa.extraction_run_id til dens id
--       (red_normaliser_forslag kræver en række med forslagets source_id; ellers NORMALISERING_KOERSEL_MANGLER).
--       Køres som forbindelsens ejerrolle, før SET LOCAL ROLE authenticated (authenticated har ingen adgang til
--       private). Kræver ikke request.jwt.claim.sub: tabellen har ingen trigger. Alle syv kolonner er NOT NULL og
--       ikke-tomme; input_sha256 skal være 64 hex-tegn. run_key bærer listens sha, så rækken er bundet til GO-listen,
--       og UNIQUE(source_id, run_key) afviser en anden kørsel på samme liste. Præcis (testen kører blokken ordret):
-- [koersel]
-- INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,
--                                    manifest)
-- SELECT current_setting('daa.normaliser_kilde')::bigint,
--        'normalisering:'||current_setting('daa.normaliser_regel')||':'||current_setting('daa.normaliser_kandidater_sha256'),
--        'normalisering-v1','red_normaliser_forslag',current_setting('daa.normaliser_regel'),
--        current_setting('daa.normaliser_kandidater_sha256'),
--        jsonb_build_object('regel',current_setting('daa.normaliser_regel'),'antal',current_setting('daa.normaliser_antal')::int,
--                           'kandidater_sha256',current_setting('daa.normaliser_kandidater_sha256'))
-- RETURNING id AS normaliser_run_id \gset
-- SELECT set_config('daa.extraction_run_id',:'normaliser_run_id',true) \g /dev/null
-- [/koersel]
--   (c) sæt request.jwt.claim.sub til redaktørens auth-uid (RPC'ens rollegate: auth.uid() og
--       current_rolle()='redaktion'), SET LOCAL ROLE authenticated, og pr. element i listens rækkefølge to krav:
--         (1) SELECT set_config('app.change_set_id','',true) \g /dev/null umiddelbart før HVERT kald.
--             begin_change_set genbruger et aktivt sæt, så én fortrydelse ellers kunne rulle alle versionerne
--             tilbage. red_normaliser_forslag åbner i dag intet change_set; nulstillingen kræves alligevel, så
--             kontrakten ikke afhænger af det.
--         (2) kvitteringen kasseres (\g /dev/null, eller PERFORM i en DO-blok): dens foer/efter bærer værdierne.
--         SELECT public.red_normaliser_forslag('<interpretation_id>'::uuid,<version>,<GO-pakkens regel>) \g /dev/null
--       Derefter RESET ROLE.
--   (d) efterkontrol i samme transaktion: RAISE, medmindre hvert element har en ny aktuel version (version+1,
--       supersedes_id = elementet) med method 'deterministisk-normalisering:'||daa.normaliser_regel og ceremoniens
--       extraction_run_id. Præcis (testen kører blokken ordret; daa.normaliser_go = GO-pakkens liste):
-- [efterkontrol]
-- DO $nk$
-- DECLARE n_liste bigint; n_ok bigint;
-- BEGIN
--   SELECT count(*), count(c.id) INTO n_liste, n_ok
--     FROM unnest(string_to_array(nullif(current_setting('daa.normaliser_go'),''),',')) e(p)
--     JOIN private.interpretation o ON o.id = split_part(e.p,':',1)::uuid
--                                   AND o.version = split_part(e.p,':',2)::int
--     LEFT JOIN private.interpretation_current c
--       ON c.interpretation_key = o.interpretation_key AND c.supersedes_id = o.id AND c.version = o.version+1
--      AND c.method = 'deterministisk-normalisering:'||current_setting('daa.normaliser_regel')
--      AND c.extraction_run_id = current_setting('daa.extraction_run_id')::uuid;
--   IF n_liste <> coalesce(array_length(string_to_array(nullif(current_setting('daa.normaliser_go'),''),','),1),0)
--      OR n_ok <> n_liste THEN
--     RAISE EXCEPTION 'NORMALISER_EFTERKONTROL: % af % elementer har en ny version', n_ok, n_liste;
--   END IF;
-- END $nk$;
-- [/efterkontrol]
\set QUIET on
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\if :{?source_id} \else \set source_id 3 \endif
\if :{?regel} \else \set regel dato-markoer-v1 \endif
BEGIN READ ONLY;
SELECT set_config('daa.normaliser_kilde',:'source_id',true) \g /dev/null
SELECT set_config('daa.normaliser_regel',:'regel',true) \g /dev/null
\ir normaliser_kandidat_liste.sql
DO $gate$
BEGIN
  IF current_setting('daa.normaliser_tomme')::bigint > 0 THEN
    RAISE EXCEPTION 'NORMALISER_VAERDI_TOM: % kandidater bliver tomme', current_setting('daa.normaliser_tomme');
  END IF;
END $gate$;
SELECT format('T6C2_NORMALISER antal=%s kandidater_sha256=%s', current_setting('daa.normaliser_antal'),
              current_setting('daa.normaliser_kandidater_sha256'));
SELECT replace(u.p,':','|')
  FROM unnest(string_to_array(nullif(current_setting('daa.normaliser_kandidater'),''),',')) WITH ORDINALITY u(p,o)
 ORDER BY u.o;
ROLLBACK;
