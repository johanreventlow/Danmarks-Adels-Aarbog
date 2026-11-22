-- Review 37 blok 2 (#397 D1/D3): før-billedet til backfillens kontrol. Køres i SAMME transaktion som blokken og
-- tests/sql/review37-b2-backfill.sql, FØR blokken: psql -1 -f review37-b2-backfill-foer.sql -f <blok> -f
-- review37-b2-backfill.sql -v forventet=<antal>. Ændrer intet; temp-tabellerne forsvinder ved transaktionens slut.
\set ON_ERROR_STOP on
CREATE TEMP TABLE r37b2_foer ON COMMIT DROP AS
  SELECT id, visning_navn, visning_foedt, visning_doed, visning_titel, visning_efternavn, visning_fuldt_navn,
         visning_floruit
    FROM public.person;
CREATE TEMP TABLE r37b2_karantaene_foer ON COMMIT DROP AS
  SELECT person_id, n_distinct FROM public.slaegtsnavn_karantaene;
CREATE TEMP TABLE r37b2_tal_foer ON COMMIT DROP AS
  SELECT (SELECT count(*) FROM public.change_set) AS n_cs, (SELECT count(*) FROM public.change_event) AS n_ce;
