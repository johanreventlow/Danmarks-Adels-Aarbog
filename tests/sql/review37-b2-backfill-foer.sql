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
-- Uafhængig forudsigelse af D1-deltaet (læser kun den nuværende cache, ikke den nye regen): personer med navn og uden
-- efternavn, uden linjekode, hvis 'member'-medlemskaber giver præcis ét slægtsnavn, som navnet ikke allerede slutter på.
CREATE TEMP TABLE r37b2_forudsagt ON COMMIT DROP AS
  SELECT p.id, m.navne[1] AS efternavn
    FROM public.person p
    CROSS JOIN LATERAL (SELECT array_agg(DISTINCT public.lineage_effective_slaegtsnavn(plm.lineage_id)) FILTER (
                                 WHERE public.lineage_effective_slaegtsnavn(plm.lineage_id) IS NOT NULL) AS navne
                          FROM public.person_lineage_membership plm
                         WHERE plm.person_id = p.id AND plm.role = 'member') m
   WHERE p.visning_navn IS NOT NULL AND p.visning_efternavn IS NULL AND cardinality(m.navne) = 1
     AND NOT public.slaegtsnavn_suffiks_match(p.visning_navn, m.navne[1])
     AND NOT EXISTS (SELECT 1 FROM public.person_external_id pei
                       JOIN public.lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
                      WHERE pei.person_id = p.id);
