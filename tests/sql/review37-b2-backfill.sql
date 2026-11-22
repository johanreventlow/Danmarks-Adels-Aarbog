-- Review 37 blok 2 (#397 D1/D3): backfill af visningscachen og kontrol af præcis det forventede delta.
-- Køres EFTER blokken review37-b2 i samme transaktion, med før-billedet fra review37-b2-backfill-foer.sql:
--   psql -1 -v forventet=<antal> -f tests/sql/review37-b2-backfill-foer.sql -f <blok> -f tests/sql/review37-b2-backfill.sql
-- Prod (målt læse-kun 22/11): forventet=504 — personer med medlemskab og uden linjekode får visning_efternavn; 0 nye i
-- karantæne, 0 skifter navn, og D3 (bogens orden for navn/fødsel/død) ændrer 0 visninger.
-- 1) Kandidaterne: alle med et 'member'-medlemskab (D1) og alle med flere afklarede navne/fødsler/dødsfald (D3).
-- 2) regen_person_visning på kandidaterne i id-orden (fast låserækkefølge); listen over ændrede personer udskrives.
-- 3) Kontrol (fejler med R37B2_BACKFILL_* og ruller alt tilbage): ændrede ⊆ kandidater; hver ændret person har kun
--    fået visning_efternavn (fra NULL) og visning_fuldt_navn = navn + efternavn, har et medlemskab og ingen linjekode;
--    navn, fødsel, død, titel og floruit uændrede for alle; karantænen, change_set og change_event uændrede; antallet =
--    forventet; og en prøve-regen af ALLE andre personer (rulles tilbage) ændrer intet, dvs. kandidatmængden er
--    fuldstændig og der er ingen anden drift under den nye regel.
\set ON_ERROR_STOP on
SELECT set_config('r37b2.forventet', :'forventet', true) IS NOT NULL AS forventet_sat;

CREATE TEMP TABLE r37b2_kandidat ON COMMIT DROP AS
  SELECT plm.person_id AS id FROM public.person_lineage_membership plm WHERE plm.role = 'member'
  UNION
  SELECT f.subjekt_id FROM public.fact f
    JOIN public.conclusion c ON c.target_type = 'fact' AND c.target_id = f.id AND c.status = 'afklaret'
   WHERE f.subjekt_type = 'person' AND f.faktatype IN ('navn','fødsel','død')
   GROUP BY f.subjekt_id, f.faktatype HAVING count(*) > 1;

SELECT count(*) AS regenereret FROM (
  SELECT public.regen_person_visning(k.id) FROM r37b2_kandidat k JOIN public.person p ON p.id = k.id ORDER BY k.id) s;

CREATE TEMP TABLE r37b2_aendret ON COMMIT DROP AS
  SELECT f.id, f.visning_efternavn AS foer_efternavn, p.visning_efternavn AS efter_efternavn,
         f.visning_fuldt_navn AS foer_fuldt, p.visning_fuldt_navn AS efter_fuldt
    FROM r37b2_foer f JOIN public.person p ON p.id = f.id
   WHERE (f.visning_navn, f.visning_foedt, f.visning_doed, f.visning_titel, f.visning_efternavn, f.visning_fuldt_navn,
          f.visning_floruit)
         IS DISTINCT FROM (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn,
                           p.visning_fuldt_navn, p.visning_floruit);

-- Før/efter pr. ændret id (runnerens log).
SELECT id, foer_efternavn, efter_efternavn, foer_fuldt, efter_fuldt FROM r37b2_aendret ORDER BY id;

DO $r37b2$
DECLARE n bigint; v_forventet bigint := current_setting('r37b2.forventet')::bigint;
BEGIN
  IF (SELECT count(*) FROM public.person) <> (SELECT count(*) FROM r37b2_foer)
     OR EXISTS (SELECT 1 FROM r37b2_foer f WHERE NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id = f.id)) THEN
    RAISE EXCEPTION 'R37B2_BACKFILL_PERSONMAENGDE: personrækker kom til eller forsvandt';
  END IF;
  SELECT count(*) INTO n FROM r37b2_aendret a WHERE NOT EXISTS (SELECT 1 FROM r37b2_kandidat k WHERE k.id = a.id);
  IF n > 0 THEN RAISE EXCEPTION 'R37B2_BACKFILL_UDEN_FOR_KANDIDATER: % personer', n; END IF;
  SELECT count(*) INTO n FROM r37b2_foer f JOIN public.person p ON p.id = f.id
   WHERE (f.visning_navn, f.visning_foedt, f.visning_doed, f.visning_titel, f.visning_floruit)
         IS DISTINCT FROM (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_floruit);
  IF n > 0 THEN RAISE EXCEPTION 'R37B2_BACKFILL_ANDRE_KOLONNER: navn/fødsel/død/titel/floruit ændret for % personer', n; END IF;
  SELECT count(*) INTO n FROM r37b2_aendret a JOIN public.person p ON p.id = a.id
   WHERE a.foer_efternavn IS NOT NULL OR a.efter_efternavn IS NULL
      OR a.efter_fuldt IS DISTINCT FROM (p.visning_navn || ' ' || a.efter_efternavn)
      OR a.efter_efternavn IS DISTINCT FROM (SELECT min(public.lineage_effective_slaegtsnavn(plm.lineage_id))
                                               FROM public.person_lineage_membership plm
                                              WHERE plm.person_id = a.id AND plm.role = 'member')
      OR EXISTS (SELECT 1 FROM public.person_external_id pei
                   JOIN public.lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
                  WHERE pei.person_id = a.id);
  IF n > 0 THEN RAISE EXCEPTION 'R37B2_BACKFILL_IKKE_MEDLEMSKABSNAVN: % ændrede personer er ikke »medlemskab uden linjekode får efternavn«', n; END IF;
  IF EXISTS (SELECT person_id, n_distinct FROM public.slaegtsnavn_karantaene
             EXCEPT SELECT person_id, n_distinct FROM r37b2_karantaene_foer)
     OR EXISTS (SELECT person_id, n_distinct FROM r37b2_karantaene_foer
                EXCEPT SELECT person_id, n_distinct FROM public.slaegtsnavn_karantaene) THEN
    RAISE EXCEPTION 'R37B2_BACKFILL_KARANTAENE: slaegtsnavn_karantaene ændret';
  END IF;
  IF (SELECT (n_cs, n_ce) FROM r37b2_tal_foer)
     IS DISTINCT FROM ((SELECT count(*) FROM public.change_set), (SELECT count(*) FROM public.change_event)) THEN
    RAISE EXCEPTION 'R37B2_BACKFILL_HISTORIK: change_set/change_event ændret';
  END IF;
  SELECT count(*) INTO n FROM r37b2_aendret;
  IF n <> v_forventet THEN RAISE EXCEPTION 'R37B2_BACKFILL_ANTAL: % ændrede personer, forventet %', n, v_forventet; END IF;
  -- Prøve: regen af alle ikke-kandidater må intet ændre (rulles tilbage via undtagelsen).
  BEGIN
    PERFORM public.regen_person_visning(p.id) FROM public.person p
      WHERE NOT EXISTS (SELECT 1 FROM r37b2_kandidat k WHERE k.id = p.id) ORDER BY p.id;
    SELECT count(*) INTO n FROM r37b2_foer f JOIN public.person p ON p.id = f.id
     WHERE NOT EXISTS (SELECT 1 FROM r37b2_kandidat k WHERE k.id = f.id)
       AND (f.visning_navn, f.visning_foedt, f.visning_doed, f.visning_titel, f.visning_efternavn, f.visning_fuldt_navn,
            f.visning_floruit)
           IS DISTINCT FROM (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn,
                             p.visning_fuldt_navn, p.visning_floruit);
    RAISE EXCEPTION 'R37B2_PROEVE:%', n;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'R37B2_PROEVE:%' THEN n := split_part(SQLERRM, ':', 2)::bigint; ELSE RAISE; END IF;
  END;
  IF n > 0 THEN RAISE EXCEPTION 'R37B2_BACKFILL_DRIFT_UDEN_FOR_KANDIDATER: % personer ville ændres af en fuld regen', n; END IF;
  RAISE NOTICE 'OK: review37 b2 backfill — % personer fik efternavn fra medlemskab; intet andet ændret', v_forventet;
END $r37b2$;
