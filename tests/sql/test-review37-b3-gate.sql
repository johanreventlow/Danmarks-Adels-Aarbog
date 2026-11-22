-- Review 37 blok 3 (S4): billed-gaten følger familiens synlighed — prøvet som rigtige kaldere (gæst = anon uden uid,
-- uden_profil/medlem = authenticated, redaktion = authenticated med redaktørprofil) gennem tabel-RLS'en, ikke kun som
-- ejer. Medlemstieren bruger samme media-politik som gæsten (media_synlig_anon), så en familie med et privat medlem
-- skjules også for medlemmer. Dokumenterer desuden S3 (uden for blok 3): et billede af en familie UDEN medlemmer er
-- synligt, fordi family_offentlig er sand for den. Kører på en base med schema.sql + db-rls.sql (frisk eller opgraderet).
-- Syntetiske negative id'er; alt rulles tilbage. Forvent: NOTICE "OK: review37 b3 gate — gæst/medlem/redaktion".
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

DO $fix$
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat) VALUES
    (-938001,true,false),   -- levende
    (-938002,false,false),  -- afdød, offentlig
    (-938003,false,true),   -- afdød, privat
    (-938004,false,false);  -- afdød, offentlig
  INSERT INTO family(id,type) VALUES (-938011,'vielse'),(-938012,'vielse'),(-938013,'vielse'),(-938014,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES
    (-938011,-938001,'partner'),(-938011,-938002,'partner'),   -- familie med levende medlem
    (-938012,-938003,'partner'),(-938012,-938004,'partner'),   -- familie med privat medlem
    (-938013,-938002,'partner'),(-938013,-938004,'partner');   -- offentlig familie; -938014 er medlemsløs
  -- Frigivne billeder (rettighedsgaten åben), så kun afbildet-gaten afgør synligheden.
  INSERT INTO media(id,maa_publiceres,upload_status,storage_path) VALUES
    (-938021,true,'klar','r37b3/lev.jpg'),(-938022,true,'klar','r37b3/priv.jpg'),
    (-938023,true,'klar','r37b3/off.jpg'),(-938024,true,'klar','r37b3/tom.jpg');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-938031,'media',-938021,'family',-938011,'afbildet'),(-938032,'media',-938022,'family',-938012,'afbildet'),
    (-938033,'media',-938023,'family',-938013,'afbildet'),(-938034,'media',-938024,'family',-938014,'afbildet');
  -- Et faktum på hvert billede (fotograf o.l.) følger billedets synlighed via entitet_offentlig.
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-938041,'media',-938021,'fotograf'),(-938042,'media',-938022,'fotograf'),
    (-938043,'media',-938023,'fotograf'),(-938044,'media',-938024,'fotograf');
END $fix$;

DO $t$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('levende_medlem',-938021,-938031,-938041,0),
      ('privat_medlem',-938022,-938032,-938042,0),
      ('offentlig_familie',-938023,-938033,-938043,1),
      ('medlemsloes_familie_S3',-938024,-938034,-938044,1)) x(navn,mid,rid,fid,ikke_red) LOOP
    PERFORM pg_temp.km_forvent('billede '||r.navn,format('SELECT 1 FROM public.media WHERE id=%s',r.mid),r.ikke_red,1);
    -- Selve koblingen (media → family) er en relation; den følger både billedets og familiens synlighed.
    PERFORM pg_temp.km_forvent('kobling '||r.navn,format('SELECT 1 FROM public.relation WHERE id=%s',r.rid),r.ikke_red,1);
    PERFORM pg_temp.km_forvent('faktum '||r.navn,format('SELECT 1 FROM public.fact WHERE id=%s',r.fid),r.ikke_red,1);
    PERFORM pg_temp.km_forvent('sti '||r.navn,
      format('SELECT 1 WHERE public.media_object_synlig_anon(%L)',(SELECT storage_path FROM public.media WHERE id=r.mid)),
      r.ikke_red,r.ikke_red);
  END LOOP;
  -- Den ellers synlige familie bliver skjult, når et medlem bliver levende — billedet følger med.
  UPDATE public.person SET levende=true WHERE id=-938004;
  PERFORM pg_temp.km_forvent('billede offentlig_familie efter levende',
    'SELECT 1 FROM public.media WHERE id=-938023',0,1);
  RAISE NOTICE 'OK: review37 b3 gate — gæst/medlem/redaktion (familie med levende/privat medlem skjult, offentlig og medlemsløs synlig)';
END $t$;
ROLLBACK;
