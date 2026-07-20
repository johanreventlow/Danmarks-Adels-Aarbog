-- =====================================================================
--  db-verify-media.sql — FOKUSERET medie-verifikation til Supabase SQL Editor
--  (mediehåndtering Slice 0). Udtræk af db-verify.sql's Task 8 + 12 + 12b.
--
--  HVORFOR denne fil: hele db-verify.sql indeholder ældre happy-path-tasks der
--  kalder redaktør-RPC'er (fx red_slet_oplysning, Task 4). I SQL Editoren er
--  auth.uid()=NULL → current_rolle()='medlem', så de RAISE'r 'Kun redaktion'.
--  Det er en KENDT begrænsning (se db-verify.sql header), ikke en medie-fejl.
--  Disse tre tasks bruger SET LOCAL ROLE anon/authenticated og kræver INGEN
--  redaktør-kontekst — de verificerer gating + storage-politikker rent.
--
--  Forudsætning: db-migrations.sql + db-rls.sql kørt, og (til Task 12b) en
--  privat 'media'-bucket oprettet. Alle blokke seeder negative-id testrækker
--  og rydder selv op i én transaktion.
--  Forvent 6 NOTICE'er: 'OK: media-gating', 'OK: media rettigheds-gating',
--  'OK: storage.objects-politikker' (12b springes over hvis bucket mangler), 'OK: media_variant ...'.
-- =====================================================================

-- ===== Task 8: media afbildet-gating (anon) =====
-- Forvent: NOTICE "OK: media-gating ...". Seeder negative-id testrækker og rydder selv op.
-- Kører faktisk som rolle 'anon' (SET LOCAL ROLE) for at RAMME RLS — SQL Editor er ellers
-- ejer/bypass. Hele blokken er ét DO = én transaktion; rejser den, rulles seed-rækkerne tilbage.
-- Verificerer fail-closed-reglen: afdød afbildet → synlig, levende afbildet → skjult,
-- objekt uden afbildet-person → synlig.
DO $$
DECLARE vis_dead int; vis_live int; vis_obj int;
BEGIN
  -- ryd evt. rester fra et afbrudt løb
  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-901,-902,-903);
  DELETE FROM person   WHERE id IN (-901,-902);

  INSERT INTO person(id, levende, privat) VALUES (-901, false, false), (-902, true, false);
  -- maa_publiceres=true + upload_status='klar' på alle: isolér afbildet-gatingen fra rettigheds-gatingen
  -- (rettigheder testes separat i Task 12).
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status) VALUES
    (-901,'foto','portræt-afdød',      true,'klar'),
    (-902,'foto','portræt-levende',    true,'klar'),
    (-903,'segl','objekt-uden-person', true,'klar');
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle) VALUES
    (-901,'person',-901,'media',-901,'afbildet'),
    (-902,'person',-902,'media',-902,'afbildet');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_dead FROM media WHERE id = -901;
  SELECT count(*) INTO vis_live FROM media WHERE id = -902;
  SELECT count(*) INTO vis_obj  FROM media WHERE id = -903;
  RESET ROLE;

  IF vis_dead = 1 AND vis_live = 0 AND vis_obj = 1 THEN
    RAISE NOTICE 'OK: media-gating (afdød synlig, levende skjult, objekt synligt)';
  ELSE
    RAISE EXCEPTION 'media-gating FEJL: afdød=% (vent 1), levende=% (vent 0), objekt=% (vent 1)',
      vis_dead, vis_live, vis_obj;
  END IF;

  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-901,-902,-903);
  DELETE FROM person   WHERE id IN (-901,-902);
END $$;

-- ===== Task 15: fase 3 upload-alder + unik afbildet-tilknytning =====
-- Direkte seed-DML: created_at skal default-udfyldes, men forblive NULL-bar for
-- præ-fase-3-rækker. Kun identiske afbildet-relationer er dubletter; ejer-relationer
-- må fortsat kunne gentages.
DO $$
BEGIN
  DELETE FROM relation WHERE id IN (-951,-952,-953,-954);
  DELETE FROM media WHERE id=-951;

  IF (SELECT is_nullable
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='media' AND column_name='created_at')
     IS DISTINCT FROM 'YES' THEN
    RAISE EXCEPTION 'media.created_at skal være NULL-bar';
  END IF;

  INSERT INTO media(id,slags,titel) VALUES (-951,'foto','fase-3-created-at-test');
  IF (SELECT created_at FROM media WHERE id=-951) IS NULL THEN
    RAISE EXCEPTION 'media.created_at-default blev ikke udfyldt';
  END IF;

  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES (-951,'person',-951,'media',-951,'afbildet');
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES (-952,'person',-951,'media',-951,'afbildet');
    RAISE EXCEPTION 'identisk afbildet-relation blev accepteret';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-953,'person',-951,'media',-951,'ejer'),
    (-954,'person',-951,'media',-951,'ejer');
  IF (SELECT count(*) FROM relation WHERE id IN (-953,-954)) <> 2 THEN
    RAISE EXCEPTION 'partial-indexet afviste identiske ejer-relationer';
  END IF;

  DELETE FROM relation WHERE id IN (-951,-952,-953,-954);
  DELETE FROM media WHERE id=-951;
  RAISE NOTICE 'OK: media created_at-default/NULL-bar + partiel afbildet-unikhed';
END $$;

-- ===== Task 15b: blød medieflet bevarer relationsevidens atomisk =====
-- Hele blokken rulles tilbage. Den nye RPC skal afvise evidens, slette en evidensfri
-- kanonisk medierelation og må ikke ændre red_slet_relation's eksisterende semantik.
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-000000000961';
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_uid,'media-merge-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','media-merge-verify@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  PERFORM set_config('app.change_set_id','',true);

  INSERT INTO person(id,levende,privat) VALUES (-961,false,false);
  INSERT INTO media(id,slags,titel,upload_status) VALUES
    (-961,'foto','flet-evidens','fjernet'),
    (-962,'foto','flet-uden-evidens','fjernet'),
    (-963,'foto','almindelig-slet','fjernet'),
    (-964,'foto','evidensfri-id-update','fjernet');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-961,'person',-961,'media',-961,'afbildet'),
    (-962,'person',-961,'media',-962,'afbildet'),
    (-963,'person',-961,'media',-963,'afbildet'),
    (-964,'person',-961,'media',-964,'afbildet');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES
    (-961,'relation',-961,'bevar mig'), (-963,'relation',-963,'slet mig som hidtil');
  INSERT INTO citation(id,assertion_id,citat_tekst) VALUES
    (-961,-961,'bevar citation'), (-963,-963,'slet citation');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-961,'relation',-961,-961,'afklaret'), (-963,'relation',-963,-963,'afklaret');
  INSERT INTO note(id,target_type,target_id,indhold) VALUES
    (-961,'relation',-961,'bevar note'), (-963,'relation',-963,'slet note');

  BEGIN
    PERFORM red_slet_medierelation_uden_evidens(-961);
    RAISE EXCEPTION 'evidensbærende medierelation blev slettet';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%har evidens%' THEN RAISE; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM relation WHERE id=-961)
     OR NOT EXISTS (SELECT 1 FROM assertion WHERE id=-961)
     OR NOT EXISTS (SELECT 1 FROM citation WHERE id=-961)
     OR NOT EXISTS (SELECT 1 FROM conclusion WHERE id=-961)
     OR NOT EXISTS (SELECT 1 FROM note WHERE id=-961) THEN
    RAISE EXCEPTION 'atomisk medieflet mistede relation eller evidens';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_medierelation_uden_evidens(-962);
  IF EXISTS (SELECT 1 FROM relation WHERE id=-962) THEN
    RAISE EXCEPTION 'evidensfri medierelation blev ikke slettet';
  END IF;

  -- Invarianten skal gælde på ALLE DML-veje, ikke kun i soft-unlink-RPC'en:
  -- ny/ompeget polymorf evidens må aldrig kunne lande på en slettet relation.
  BEGIN
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst)
      VALUES (-962,'relation',-962,'må ikke blive orphan');
    RAISE EXCEPTION 'assertion accepterede en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO conclusion(id,target_type,target_id,status)
      VALUES (-962,'relation',-962,'afklaret');
    RAISE EXCEPTION 'conclusion accepterede en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO note(id,target_type,target_id,indhold)
      VALUES (-962,'relation',-962,'må ikke blive orphan');
    RAISE EXCEPTION 'note accepterede en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE assertion SET target_id=-962 WHERE id=-961;
    RAISE EXCEPTION 'assertion kunne ompeges til en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE conclusion SET target_id=-962 WHERE id=-961;
    RAISE EXCEPTION 'conclusion kunne ompeges til en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE note SET target_id=-962 WHERE id=-961;
    RAISE EXCEPTION 'note kunne ompeges til en manglende relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relations-evidens kræver eksisterende relation %' THEN RAISE; END IF;
  END;

  -- Direkte relation-DELETE må heller ikke omgå polymorf evidens. Den ordinære
  -- RPC nedenfor skal fortsat lykkes, fordi helperen sletter evidensen først.
  BEGIN
    DELETE FROM relation WHERE id=-961;
    RAISE EXCEPTION 'direkte relation-DELETE forældreløste evidens';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relation % har evidens og kan ikke slettes direkte' THEN RAISE; END IF;
  END;

  -- En relation-PK er del af den polymorfe reference. Evidensbærende id-update
  -- skal derfor fail-loud; evidensfri id-update forbliver tilladt til import/undo.
  BEGIN
    UPDATE relation SET id=-971 WHERE id=-961;
    RAISE EXCEPTION 'relation-id kunne ompeges væk fra sin evidens';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Relation % har evidens og id kan ikke ændres' THEN RAISE; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM relation WHERE id=-961)
     OR NOT EXISTS (SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=-961) THEN
    RAISE EXCEPTION 'afvist relation-id-update bevarede ikke relation/evidens';
  END IF;

  -- Undo-upsertens generiske SET-liste indeholder PK'en, selv når værdien er
  -- uændret. Den vej må fortsat kunne opdatere øvrige felter på evidensrelationen.
  UPDATE relation SET id=id, konfidens='sikker' WHERE id=-961;
  IF (SELECT konfidens FROM relation WHERE id=-961) IS DISTINCT FROM 'sikker' THEN
    RAISE EXCEPTION 'no-op relation-id blokerede undo-kompatibel feltopdatering';
  END IF;

  UPDATE relation SET id=-972 WHERE id=-964;
  IF EXISTS (SELECT 1 FROM relation WHERE id=-964)
     OR NOT EXISTS (SELECT 1 FROM relation WHERE id=-972) THEN
    RAISE EXCEPTION 'evidensfri relation-id-update blev ikke bevaret som tilladt';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_relation(-963);
  IF EXISTS (SELECT 1 FROM relation WHERE id=-963)
     OR EXISTS (SELECT 1 FROM assertion WHERE id=-963)
     OR EXISTS (SELECT 1 FROM citation WHERE id=-963)
     OR EXISTS (SELECT 1 FROM conclusion WHERE id=-963)
     OR EXISTS (SELECT 1 FROM note WHERE id=-963) THEN
    RAISE EXCEPTION 'red_slet_relation bevarede ikke sin eksisterende evidenssletning';
  END IF;

  IF has_function_privilege('anon','public.red_slet_medierelation_uden_evidens(bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_slet_medierelation_uden_evidens(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'forkerte EXECUTE-privilegier på medieflet-RPC';
  END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: atomisk medieflet bevarer evidens; almindelig relationsslet er uændret (rullet tilbage)';
  ELSE
    RAISE;
  END IF;
END $$;



-- ===== Task 12: media rettigheds-gating + storage.objects-mapping (mediehåndtering 2026-07-04) =====
-- Verificerer den ANDEN gating-dimension (copyright/publikation), ortogonal til afbildet-gatingen:
--   · objekt-foto, maa_publiceres=false → SKJULT for anon OG medlem, men SYNLIGT for redaktion
--   · objekt-foto, maa_publiceres=true men upload_status='kladde' → SKJULT (kun 'klar' publiceres)
--   · objekt-foto, maa_publiceres=true + 'klar' → SYNLIGT for anon
-- Plus storage-objekt→media-mappingen (media_id_for_object) inkl. forældreløst objekt → fail-closed.
DO $$
DECLARE vis_spaerret int; vis_kladde int; vis_klar int; vis_red int;
        map_hit bigint; map_orphan bigint; ok_orphan boolean;
BEGIN
  DELETE FROM media WHERE id IN (-911,-912,-913);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-911,'segl','objekt-spaerret', false,'klar',   'media','test/spaerret.jpg'),
    (-912,'segl','objekt-kladde',   true, 'kladde', 'media','test/kladde.jpg'),
    (-913,'segl','objekt-klar',     true, 'klar',   'media','test/klar.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_spaerret FROM media WHERE id = -911;
  SELECT count(*) INTO vis_kladde   FROM media WHERE id = -912;
  SELECT count(*) INTO vis_klar     FROM media WHERE id = -913;
  RESET ROLE;

  IF NOT (vis_spaerret = 0 AND vis_kladde = 0 AND vis_klar = 1) THEN
    RAISE EXCEPTION 'rettigheds-gating FEJL (anon): spaerret=% (vent 0), kladde=% (vent 0), klar=% (vent 1)',
      vis_spaerret, vis_kladde, vis_klar;
  END IF;

  -- objekt→media-mapping: kendt sti resolver, ukendt (forældreløs) → NULL → rettigheder_ok=false
  SELECT public.media_id_for_object('test/klar.jpg')        INTO map_hit;
  SELECT public.media_id_for_object('findes/ikke.jpg')      INTO map_orphan;
  SELECT public.media_rettigheder_ok(public.media_id_for_object('findes/ikke.jpg')) INTO ok_orphan;
  IF map_hit IS DISTINCT FROM -913 OR map_orphan IS NOT NULL OR ok_orphan IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'storage-mapping FEJL: hit=% (vent -913), orphan=% (vent NULL), orphan_ok=% (vent false)',
      map_hit, map_orphan, ok_orphan;
  END IF;

  DELETE FROM media WHERE id IN (-911,-912,-913);
  RAISE NOTICE 'OK: media rettigheds-gating (spærret/kladde skjult, klar synlig) + storage-mapping (forældreløs fail-closed)';
END $$;


-- ===== Task 12b: storage.objects-POLITIKKER under faktiske roller (ikke kun helper-kald) =====
-- Task 12 tester media-TABELLEN + helperne. Denne blok udøver de rigtige storage.objects-politikker
-- (media_obj_anon/auth) ved at indsætte objekt-rækker og læse dem under SET LOCAL ROLE — så en
-- fail-open-politik (OR i stedet for AND, manglende rettigheds-gate, eller manglende bucket-guard)
-- rejser her. Springes over hvis der ikke findes en 'media'-bucket (lokalt/pre-provisionering).
--
-- OBS (fundet 2026-07-05, mod rigtig prod): ægte Supabase har en storage.protect_delete()-trigger
-- der blokerer DIREKTE DELETE FROM storage.objects ("brug Storage API'et i stedet") — vores lokale
-- Postgres-teststub har den IKKE, så dette Task passerer lokalt men fejler uændret mod rigtig
-- Supabase på selve oprydnings-DELETE'en. Sanktioneret escape-ventil (Supabases egen, ikke en
-- workaround): `SET LOCAL storage.allow_delete_query = 'true';` som FØRSTE linje i DO-blokken —
-- kun for varigheden af denne transaktion. Tilføj den bevidst selv hvis du kører dette i SQL
-- Editoren; den er UDELADT her fordi en direkte delete-bypass på en produktions-storage-tabel
-- er en beslutning kun du bør tage eksplicit, ikke noget der skal ligge klar til at køre stiltiende.
DO $$
DECLARE has_bucket boolean; vis_klar int; vis_spaerret int; vis_orphan int; vis_klar_auth int; vis_spaerret_auth int;
BEGIN
  SELECT EXISTS(SELECT 1 FROM storage.buckets WHERE id='media') INTO has_bucket;
  IF NOT has_bucket THEN
    RAISE NOTICE 'SPRINGER OVER Task 12b (storage.objects-politikker): ingen media-bucket — opret den for fuld dækning';
    RETURN;
  END IF;
  DELETE FROM storage.objects WHERE bucket_id='media' AND name IN ('test/klar.jpg','test/spaerret.jpg','test/orphan.jpg');
  DELETE FROM media WHERE id IN (-921,-922);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-921,'segl','obj-klar',    true, 'klar','media','test/klar.jpg'),
    (-922,'segl','obj-spaerret',false,'klar','media','test/spaerret.jpg');
  INSERT INTO storage.objects(bucket_id, name) VALUES
    ('media','test/klar.jpg'), ('media','test/spaerret.jpg'), ('media','test/orphan.jpg'); -- orphan = ingen media-række

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_klar     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  SELECT count(*) INTO vis_orphan   FROM storage.objects WHERE bucket_id='media' AND name='test/orphan.jpg';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO vis_klar_auth     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret_auth FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  RESET ROLE;

  IF NOT (vis_klar=1 AND vis_spaerret=0 AND vis_orphan=0 AND vis_klar_auth=1 AND vis_spaerret_auth=0) THEN
    RAISE EXCEPTION 'storage.objects-gating FEJL: anon(klar=% [1], spaerret=% [0], orphan=% [0]), medlem(klar=% [1], spaerret=% [0])',
      vis_klar, vis_spaerret, vis_orphan, vis_klar_auth, vis_spaerret_auth;
  END IF;

  DELETE FROM storage.objects WHERE bucket_id='media' AND name IN ('test/klar.jpg','test/spaerret.jpg','test/orphan.jpg');
  DELETE FROM media WHERE id IN (-921,-922);
  RAISE NOTICE 'OK: storage.objects-politikker (klar synlig anon+medlem; spærret + forældreløs skjult for begge)';
END $$;


-- ===== Task 13: media_variant — arver forælderens gating + storage-mapping (billedstørrelser/
-- lightbox 2026-07-05, Slice B1) =====
-- Verificerer at en variant-række (thumb/medium) ALDRIG er synlig uafhængigt af sin media-forælder:
--   · forælder 'klar'+maa_publiceres   → variant synlig for anon
--   · forælder 'fjernet' (blødt slettet) → variant SKJULT, selvom variant-rækken selv er uændret
-- Plus at media_id_for_object nu resolver BÅDE base-media-stier og variant-stier korrekt.
DO $$
DECLARE vis_klar int; vis_fjernet int; map_variant bigint; map_base bigint;
BEGIN
  DELETE FROM media_variant WHERE id IN (-931,-932);
  DELETE FROM media WHERE id IN (-931,-932);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-931,'foto','med-thumb-klar',   true,'klar',   'media','test/base-klar.jpg'),
    (-932,'foto','med-thumb-fjernet',true,'fjernet','media','test/base-fjernet.jpg');
  INSERT INTO media_variant(id, media_id, tier, storage_path) VALUES
    (-931,-931,'thumb','test/thumb-klar.jpg'),
    (-932,-932,'thumb','test/thumb-fjernet.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_klar    FROM media_variant WHERE id = -931;
  SELECT count(*) INTO vis_fjernet FROM media_variant WHERE id = -932;
  RESET ROLE;

  IF NOT (vis_klar = 1 AND vis_fjernet = 0) THEN
    RAISE EXCEPTION 'media_variant-gating FEJL: klar-forælder=% (vent 1), fjernet-forælder=% (vent 0)',
      vis_klar, vis_fjernet;
  END IF;

  -- media_id_for_object: variant-sti → forælderens media_id; base-sti fortsat uændret.
  SELECT public.media_id_for_object('test/thumb-klar.jpg') INTO map_variant;
  SELECT public.media_id_for_object('test/base-klar.jpg')  INTO map_base;
  IF map_variant IS DISTINCT FROM -931 OR map_base IS DISTINCT FROM -931 THEN
    RAISE EXCEPTION 'media_id_for_object FEJL: variant-sti→% (vent -931), base-sti→% (vent -931)',
      map_variant, map_base;
  END IF;

  DELETE FROM media_variant WHERE id IN (-931,-932);
  DELETE FROM media WHERE id IN (-931,-932);
  RAISE NOTICE 'OK: media_variant arver forælderens gating (klar synlig, fjernet skjult) + media_id_for_object løser begge stityper';
END $$;

-- ===== Task 14: genopret-cyklus bevarer fail-closed RLS-gating =====
-- Afdød afbildet person + variant sikrer, at både GDPR-, rettigheds- og variantgating
-- følger forældermediet gennem klar → fjernet → klar.
DO $$
DECLARE vis_media_foer int; vis_variant_foer int;
        vis_media_fjernet int; vis_variant_fjernet int;
        vis_media_genoprettet int; vis_variant_genoprettet int;
BEGIN
  DELETE FROM relation WHERE id=-941;
  DELETE FROM media_variant WHERE id=-941;
  DELETE FROM media WHERE id=-941;
  DELETE FROM person WHERE id=-941;

  INSERT INTO person(id,levende,privat) VALUES (-941,false,false);
  INSERT INTO media(id,slags,titel,maa_publiceres,upload_status,bucket,storage_path)
    VALUES (-941,'foto','genopret-test',true,'klar','media','test/genopret.jpg');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES (-941,'person',-941,'media',-941,'afbildet');
  INSERT INTO media_variant(id,media_id,tier,storage_path)
    VALUES (-941,-941,'thumb','test/genopret-thumb.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_media_foer FROM media WHERE id=-941;
  SELECT count(*) INTO vis_variant_foer FROM media_variant WHERE id=-941;
  RESET ROLE;

  UPDATE media SET upload_status='fjernet' WHERE id=-941;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_media_fjernet FROM media WHERE id=-941;
  SELECT count(*) INTO vis_variant_fjernet FROM media_variant WHERE id=-941;
  RESET ROLE;

  UPDATE media SET upload_status='klar' WHERE id=-941;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_media_genoprettet FROM media WHERE id=-941;
  SELECT count(*) INTO vis_variant_genoprettet FROM media_variant WHERE id=-941;
  RESET ROLE;

  IF NOT (
    vis_media_foer=1 AND vis_variant_foer=1
    AND vis_media_fjernet=0 AND vis_variant_fjernet=0
    AND vis_media_genoprettet=1 AND vis_variant_genoprettet=1
  ) THEN
    RAISE EXCEPTION 'genopret-gating FEJL: før media/variant=%/% [1/1], fjernet=%/% [0/0], genoprettet=%/% [1/1]',
      vis_media_foer, vis_variant_foer,
      vis_media_fjernet, vis_variant_fjernet,
      vis_media_genoprettet, vis_variant_genoprettet;
  END IF;

  DELETE FROM relation WHERE id=-941;
  DELETE FROM media_variant WHERE id=-941;
  DELETE FROM media WHERE id=-941;
  DELETE FROM person WHERE id=-941;
  RAISE NOTICE 'OK: media + variant genopret-cyklus er fail-closed';
END $$;
