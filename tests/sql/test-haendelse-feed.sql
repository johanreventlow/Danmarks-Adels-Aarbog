-- Review 37 Y3: public.public_haendelse_feed (spec 2026-11-21 §4.2 og færdigbevis §6.0-0a, 4).
-- Kører i én transaktion, der rulles tilbage. Publiceringsgaten erstattes inde i transaktionen af en tællende stub,
-- så testen styrer, hvilke narrativer der er tilladt, og kan tælle gate-kald. Sammenligningen med RLS er ægte:
-- narrative.anon_read kalder samme gate, og haendelse.anon_read/auth_read/redaktion_read er uændrede.
-- Alle roller får gæsternes regel (projektejeren 2026-11-21); redaktørens bredere tabeladgang (redaktion_read) bruges
-- kun som kontrol af, at feedet bevidst er snævrere end tabellen for redaktøren.
-- Integration med den rigtige gate: test-narrative-record-contract.sql (Task 5, review 37 Y3).
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO public, private, extensions, pg_catalog;

CREATE SCHEMA feedtest;
CREATE TABLE feedtest.tilladt(narrative_id bigint PRIMARY KEY);
CREATE FUNCTION feedtest.kald() RETURNS integer LANGUAGE sql AS
  $$ SELECT coalesce(nullif(current_setting('feedtest.gate_kald',true),''),'0')::integer $$;
CREATE FUNCTION feedtest.nulstil() RETURNS void LANGUAGE sql AS
  $$ SELECT set_config('feedtest.gate_kald','0',true) $$;
GRANT USAGE ON SCHEMA feedtest TO anon,authenticated;
GRANT EXECUTE ON FUNCTION feedtest.kald(),feedtest.nulstil() TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.person_daa_narrative_publication_allowed(p_narrative_id bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $stub$
BEGIN
  PERFORM set_config('feedtest.gate_kald',(feedtest.kald()+1)::text,true);
  RETURN EXISTS (SELECT 1 FROM feedtest.tilladt t WHERE t.narrative_id=p_narrative_id);
END
$stub$;

-- Fixtur. Narrativ-id'erne er valgt, så det skjulte narrativ (-93970090) kommer FØRST i cursor-ordenen.
INSERT INTO public.person(id,levende,privat,staged) VALUES
  (-93970001,false,false,false),   -- offentlig
  (-93970002,true,false,false),    -- levende: ikke offentlig
  (-93970003,false,false,false);   -- offentlig
INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES
  (-93970011,'test','Feedtest A','Feedtest A-udgave',1939),
  (-93970012,'test','Feedtest B','Feedtest B-udgave',2018),
  (-93970013,'test','Feedtest C (kun skjult)','Feedtest C-udgave',2019);
INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat) VALUES
  (-93970090,'person',-93970001,-93970013,'Skjult narrativ','90',false),
  (-93970050,'person',-93970001,-93970011,'Blandet narrativ','50',false),
  (-93970040,'person',-93970003,-93970012,'Andet narrativ','40',false),
  (-93970030,'person',-93970003,-93970012,'Tredje narrativ','30',false),
  (-93970020,'person',-93970001,-93970011,'Fjerde narrativ','20',false);
INSERT INTO feedtest.tilladt VALUES (-93970050),(-93970040),(-93970030),(-93970020);
INSERT INTO public.haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status) VALUES
  -- Skjult narrativ: ingen rækker må komme med (gate), men det må ikke stoppe bladringen.
  (-93970901,'person',-93970001,-93970090,'h901','Skjult narrativ 1','kandidat'),
  (-93970902,'person',-93970001,-93970090,'h902','Skjult narrativ 2','interessant'),
  -- Blandet narrativ (§6.0): én tilladt række, én skjult række, én med ikke-offentligt subjekt, én ikke-person.
  (-93970501,'person',-93970001,-93970050,'h501','Tilladt','kandidat'),
  (-93970502,'person',-93970001,-93970050,'h502','Skjult status','skjult'),
  (-93970503,'person',-93970002,-93970050,'h503','Levende subjekt','kandidat'),
  (-93970504,'source',-93970011,-93970050,'h504','Ikke-person','kandidat'),
  (-93970505,'person',-93970001,-93970050,'h505','Tilladt 2','interessant'),
  (-93970401,'person',-93970003,-93970040,'h401','Andet 1','kandidat'),
  (-93970402,'person',-93970003,-93970040,'h402','Andet 2','kandidat'),
  (-93970403,'person',-93970003,-93970040,'h403','Andet 3','kandidat'),
  (-93970301,'person',-93970003,-93970030,'h301','Tredje 1','kandidat'),
  (-93970201,'person',-93970001,-93970020,'h201','Fjerde 1','kandidat');

-- En redaktør og et almindeligt medlem.
INSERT INTO auth.users(id,email) VALUES
  ('00000000-0000-0000-0000-0000000093a1','feedtest-red@test.invalid'),
  ('00000000-0000-0000-0000-0000000093a2','feedtest-medlem@test.invalid')
  ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles(id,rolle,email) VALUES
  ('00000000-0000-0000-0000-0000000093a1','redaktion','feedtest-red@test.invalid'),
  ('00000000-0000-0000-0000-0000000093a2','medlem','feedtest-medlem@test.invalid')
  ON CONFLICT (id) DO UPDATE SET rolle=excluded.rolle;

-- Bladrer til naeste er null. Returnerer kaldene som rækker (kun fixturens id'er tæller).
CREATE FUNCTION feedtest.bladr(p_max_n integer,p_max_r integer)
RETURNS TABLE(kald integer,ids bigint[],naeste text,narrativer bigint[],kilder bigint[],gate_kald integer)
LANGUAGE plpgsql AS $bladr$
DECLARE v_cursor text; v_side jsonb; v_kald integer:=0;
BEGIN
  LOOP
    v_kald:=v_kald+1;
    IF v_kald>200 THEN RAISE EXCEPTION 'FEEDTEST_BLADRING_STOPPER_IKKE'; END IF;
    PERFORM feedtest.nulstil();
    v_side:=public.public_haendelse_feed(v_cursor,p_max_n,p_max_r);
    kald:=v_kald;
    ids:=ARRAY(SELECT (r->>'id')::bigint FROM jsonb_array_elements(v_side->'rows') r);
    naeste:=v_side->>'naeste';
    narrativer:=ARRAY(SELECT (n->>'id')::bigint FROM jsonb_array_elements(v_side->'narrativer') n);
    kilder:=ARRAY(SELECT (s->>'id')::bigint FROM jsonb_array_elements(v_side->'sources') s);
    gate_kald:=feedtest.kald();
    RETURN NEXT;
    EXIT WHEN v_side->'naeste'='null'::jsonb;
    v_cursor:=v_side->>'naeste';
  END LOOP;
END
$bladr$;
GRANT EXECUTE ON FUNCTION feedtest.bladr(integer,integer) TO anon,authenticated;
CREATE TEMP TABLE feedtest_resultat(rolle text,max_n integer,max_r integer,kald integer,ids bigint[],
  naeste text,narrativer bigint[],kilder bigint[],gate_kald integer) ON COMMIT DROP;
GRANT ALL ON feedtest_resultat TO anon,authenticated;

-- Gæst (anon uden JWT), medlem og redaktør; tre lofter, deriblandt det mindste (1 narrativ / 1 række).
DO $bladring$
DECLARE v_rolle text; v_sub text; v_l integer[];
BEGIN
  FOREACH v_l SLICE 1 IN ARRAY ARRAY[[1,1],[1,2],[2,3],[150,1000]] LOOP
    FOR v_rolle,v_sub IN VALUES ('anon',''),('medlem','00000000-0000-0000-0000-0000000093a2'),
                               ('redaktion','00000000-0000-0000-0000-0000000093a1') LOOP
      PERFORM set_config('request.jwt.claim.sub',v_sub,true);
      IF v_rolle='anon' THEN SET LOCAL ROLE anon; ELSE SET LOCAL ROLE authenticated; END IF;
      INSERT INTO feedtest_resultat SELECT v_rolle,v_l[1],v_l[2],b.* FROM feedtest.bladr(v_l[1],v_l[2]) b;
      RESET ROLE;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','',true);
END
$bladring$;

-- §4: samlet bladring = præcis gæstens RLS-mængde for alle roller, uden dubletter. §6.0: rækkefiltre pr. række.
DO $samme_som_rls$
DECLARE v_rolle text; v_sub text; v_rls bigint[]; v_feed bigint[]; v_alle bigint; v_forskellige bigint; v_l record;
  v_rolle_rls bigint[];
  v_forventet_anon bigint[]:=ARRAY[-93970505,-93970501,-93970403,-93970402,-93970401,-93970301,-93970201];
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  v_rls:=ARRAY(SELECT h.id FROM public.haendelse h
                WHERE h.subjekt_type='person' AND h.id BETWEEN -93970999 AND -93970001 ORDER BY h.id);
  RESET ROLE;
  IF v_rls IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(v_forventet_anon) x) THEN
    RAISE EXCEPTION 'FEEDTEST_FIXTUR_RLS_UVENTET: %',v_rls;
  END IF;
  FOR v_rolle,v_sub IN VALUES ('anon',''),('medlem','00000000-0000-0000-0000-0000000093a2'),
                             ('redaktion','00000000-0000-0000-0000-0000000093a1') LOOP
    PERFORM set_config('request.jwt.claim.sub',v_sub,true);
    IF v_rolle='anon' THEN SET LOCAL ROLE anon; ELSE SET LOCAL ROLE authenticated; END IF;
    v_rolle_rls:=ARRAY(SELECT h.id FROM public.haendelse h
                        WHERE h.subjekt_type='person' AND h.id BETWEEN -93970999 AND -93970001 ORDER BY h.id);
    RESET ROLE;
    FOR v_l IN SELECT DISTINCT max_n,max_r FROM feedtest_resultat WHERE rolle=v_rolle LOOP
      SELECT array_agg(i ORDER BY i),count(*),count(DISTINCT i) INTO v_feed,v_alle,v_forskellige
        FROM feedtest_resultat r,unnest(r.ids) i
       WHERE r.rolle=v_rolle AND r.max_n=v_l.max_n AND r.max_r=v_l.max_r AND i BETWEEN -93970999 AND -93970001;
      IF v_feed IS DISTINCT FROM v_rls OR v_alle<>v_forskellige THEN
        RAISE EXCEPTION 'FEEDTEST_IKKE_SAMME_SOM_RLS: % %/% feed=% rls=% (% rækker, % forskellige)',
          v_rolle,v_l.max_n,v_l.max_r,v_feed,v_rls,v_alle,v_forskellige;
      END IF;
    END LOOP;
    -- Kontrol: medlemmet har gæstens tabelmængde; redaktøren ser mere i tabellen (redaktion_read), men ikke i feedet.
    IF (v_rolle='medlem' AND v_rolle_rls IS DISTINCT FROM v_rls)
       OR (v_rolle='redaktion' AND cardinality(v_rolle_rls)<>11) THEN
      RAISE EXCEPTION 'FEEDTEST_FIXTUR_ROLLE_UVENTET: % %',v_rolle,v_rolle_rls;
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','',true);
  -- narrativer/sources nævner kun de returnerede rækkers narrativer og kilder (aldrig det skjulte narrativ/kilde C).
  IF EXISTS (SELECT 1 FROM feedtest_resultat WHERE -93970090=ANY(narrativer) OR -93970013=ANY(kilder))
     OR EXISTS (SELECT 1 FROM feedtest_resultat r WHERE cardinality(r.ids)=0
                 AND (cardinality(r.narrativer)>0 OR cardinality(r.kilder)>0))
     OR EXISTS (SELECT 1 FROM feedtest_resultat r,unnest(r.narrativer) n
                 WHERE NOT EXISTS (SELECT 1 FROM public.haendelse h WHERE h.id=ANY(r.ids) AND h.narrative_id=n)) THEN
    RAISE EXCEPTION 'FEEDTEST_METADATA_UDEN_RAEKKE';
  END IF;
  RAISE NOTICE 'OK: Y3 bladring = gæstens RLS-mængde for anon, medlem og redaktør; ingen dubletter; metadata kun for returnerede rækker';
END
$samme_som_rls$;

-- §4: en bid, hvor alle kandidater afvises, har rows=[] og naeste sat og efterfølges af en tilladt bid.
-- §4.2: gaten kaldes én gang pr. forskelligt narrativ i bidden (for alle roller); lofterne binder.
DO $tom_bid_og_gate$
DECLARE v record;
BEGIN
  SELECT * INTO STRICT v FROM feedtest_resultat WHERE rolle='anon' AND max_n=1 AND max_r=2 AND kald=1;
  IF cardinality(v.ids)<>0 OR v.naeste IS NULL OR v.gate_kald<>1 THEN
    RAISE EXCEPTION 'FEEDTEST_TOM_BID_FORKERT: %',to_jsonb(v);
  END IF;
  SELECT * INTO STRICT v FROM feedtest_resultat WHERE rolle='anon' AND max_n=1 AND max_r=2 AND kald=2;
  IF cardinality(v.ids)=0 THEN RAISE EXCEPTION 'FEEDTEST_TOM_BID_IKKE_EFTERFULGT: %',to_jsonb(v); END IF;
  -- Sidste kald har naeste=null; alle andre har naeste sat.
  IF EXISTS (SELECT 1 FROM feedtest_resultat r WHERE (r.naeste IS NULL) <> (r.kald=(SELECT max(x.kald)
               FROM feedtest_resultat x WHERE x.rolle=r.rolle AND x.max_n=r.max_n AND x.max_r=r.max_r))) THEN
    RAISE EXCEPTION 'FEEDTEST_NAESTE_FORKERT';
  END IF;
  IF EXISTS (SELECT 1 FROM feedtest_resultat r WHERE r.gate_kald>r.max_n OR (cardinality(r.ids)>0 AND r.gate_kald=0))
     OR EXISTS (SELECT 1 FROM feedtest_resultat r WHERE cardinality(r.ids)>r.max_r) THEN
    RAISE EXCEPTION 'FEEDTEST_LOFT_ELLER_GATE_OVERSKREDET';
  END IF;
  -- Ét kald med plads til alt: gaten kaldes præcis én gang pr. narrativ (5), ikke pr. række (12).
  IF EXISTS (SELECT 1 FROM feedtest_resultat x WHERE x.max_n=150 AND x.max_r=1000
              AND (x.gate_kald<>5 OR x.naeste IS NOT NULL)) THEN
    RAISE EXCEPTION 'FEEDTEST_GATE_PR_NARRATIV';
  END IF;
  -- Et narrativ kan deles over to kald (max 2 rækker; det blandede narrativ har 5 kandidater).
  IF (SELECT count(*) FROM feedtest_resultat r WHERE r.rolle='anon' AND r.max_n=1 AND r.max_r=2
        AND EXISTS (SELECT 1 FROM unnest(r.ids) i WHERE i BETWEEN -93970505 AND -93970501))<2 THEN
    RAISE EXCEPTION 'FEEDTEST_NARRATIV_IKKE_DELT';
  END IF;
  RAISE NOTICE 'OK: Y3 tom bid efterfølges, naeste kun null til sidst, gate pr. narrativ, lofter binder';
END
$tom_bid_og_gate$;

-- §6.0a: mærket er uigennemsigtigt; ændret, fremmed eller klartekst-mærke afvises; ugyldige lofter afvises.
DO $maerke$
DECLARE v_naeste text; v_fejl text; v_ok boolean; v_kandidat text; v_n integer; v_fremmed text;
BEGIN
  -- Bygges som ejer (API-rollerne har ikke nødvendigvis USAGE på extensions lokalt).
  v_fremmed:=replace(encode(extensions.pgp_sym_encrypt('{"v":1,"n":-93970050,"i":-93970505}',repeat('0',64),
    'cipher-algo=aes256'),'base64'),E'\n','');
  SET LOCAL ROLE anon;
  v_naeste:=public.public_haendelse_feed(NULL,1,2)->>'naeste';
  IF v_naeste IS NULL THEN RAISE EXCEPTION 'FEEDTEST_MAERKE_MANGLER'; END IF;
  -- Ingen fixtur-id i klartekst, og mærket er ikke base64 af JSON.
  IF v_naeste ~ '9397' OR v_naeste ~ '"n"' THEN RAISE EXCEPTION 'FEEDTEST_MAERKE_KLARTEKST'; END IF;
  BEGIN
    PERFORM convert_from(decode(v_naeste,'base64'),'UTF8')::jsonb;
    RAISE EXCEPTION 'FEEDTEST_MAERKE_ER_JSON';
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
    IF v_fejl='FEEDTEST_MAERKE_ER_JSON' THEN RAISE; END IF;
  END;
  FOREACH v_kandidat IN ARRAY ARRAY[
    -- ét tegn ændret midt i mærket
    overlay(v_naeste PLACING CASE WHEN substr(v_naeste,20,1)='A' THEN 'B' ELSE 'A' END FROM 20 FOR 1),
    -- afkortet
    left(v_naeste,length(v_naeste)-8),
    -- klartekst-position (base64 af gyldig cursor-JSON)
    encode(convert_to('{"v":1,"n":-93970050,"i":-93970505}','UTF8'),'base64'),
    -- fremmed nøgle, gyldig form
    v_fremmed,
    'ikke base64 !',''
  ] LOOP
    BEGIN
      PERFORM public.public_haendelse_feed(v_kandidat,1,2);
      RAISE EXCEPTION 'FEEDTEST_MAERKE_ACCEPTERET: %',left(v_kandidat,24);
    EXCEPTION WHEN others THEN
      GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
      IF v_fejl IS DISTINCT FROM 'FEED_CURSOR_INVALID' THEN RAISE; END IF;
    END;
  END LOOP;
  FOR v_n IN SELECT unnest(ARRAY[0,201,-1]) LOOP
    BEGIN
      PERFORM public.public_haendelse_feed(NULL,v_n,10);
      RAISE EXCEPTION 'FEEDTEST_LOFT_ACCEPTERET: %',v_n;
    EXCEPTION WHEN others THEN
      GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
      IF v_fejl IS DISTINCT FROM 'FEED_LIMIT_INVALID' THEN RAISE; END IF;
    END;
  END LOOP;
  FOR v_n IN SELECT unnest(ARRAY[0,2001]) LOOP
    BEGIN
      PERFORM public.public_haendelse_feed(NULL,10,v_n);
      RAISE EXCEPTION 'FEEDTEST_LOFT_ACCEPTERET: %',v_n;
    EXCEPTION WHEN others THEN
      GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
      IF v_fejl IS DISTINCT FROM 'FEED_LIMIT_INVALID' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM public.public_haendelse_feed(NULL,NULL,10);
    RAISE EXCEPTION 'FEEDTEST_LOFT_ACCEPTERET: NULL';
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
    IF v_fejl IS DISTINCT FROM 'FEED_LIMIT_INVALID' THEN RAISE; END IF;
  END;
  -- Nøglen kan ikke læses af API-rollerne.
  v_ok:=false;
  BEGIN
    PERFORM 1 FROM private.feed_cursor_noegle;
  EXCEPTION WHEN insufficient_privilege THEN v_ok:=true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'FEEDTEST_NOEGLE_LAESBAR'; END IF;
  RESET ROLE;
  -- Rotation: et gammelt mærke bliver ugyldigt.
  UPDATE private.feed_cursor_noegle SET noegle=encode(extensions.gen_random_bytes(32),'hex') WHERE id=1;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.public_haendelse_feed(v_naeste,1,2);
    RAISE EXCEPTION 'FEEDTEST_ROTERET_MAERKE_ACCEPTERET';
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
    IF v_fejl IS DISTINCT FROM 'FEED_CURSOR_INVALID' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: Y3 bladremærke uigennemsigtigt, manipulation/fremmed/klartekst/rotation afvist, lofter valideret';
END
$maerke$;

-- Rækkefelterne er dem, klienten læser i dag (web/src/data/haendelser.ts).
DO $felter$
DECLARE v_noegler text[];
BEGIN
  SET LOCAL ROLE anon;
  SELECT array_agg(k ORDER BY k) INTO v_noegler
    FROM jsonb_object_keys((public.public_haendelse_feed()->'rows')->0) k;
  RESET ROLE;
  IF v_noegler IS DISTINCT FROM ARRAY['date_max','date_min','date_qualifier','date_raw','fact_id','feed_status','id',
       'kategori','klausul','narrative_id','relation_id','subjekt_id'] THEN
    RAISE EXCEPTION 'FEEDTEST_FELTER: %',v_noegler;
  END IF;
  RAISE NOTICE 'OK: Y3 rækkefelter som klientens læsning';
END
$felter$;

\echo OK test-haendelse-feed
ROLLBACK;
