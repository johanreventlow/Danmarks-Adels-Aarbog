# Runbook: trin 6d-1 i prod — 1939's placements og medlemskaber

Spec: `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md`. Plan:
`docs/superpowers/plans/2026-11-08-trin6d1-placement-medlemskab.md` (Task 9-10). Beslutninger: `docs/decisions.md`
2026-11-08 (opdeling, B6, Gate A) og 2026-11-09 (oversigtszoner, kortrunden, generalprøven).
Runner: `~/.private/5ab-overfoersel/33-trin6d1.sh` med `33-trin6d1-vindue.sql` (aldrig i repoet). Den kaldes via
`/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 33-trin6d1.sh <handling>` fra operatørens cwd. De bundne input ligger
i `~/.private/6d1/` (7 filer, 0600, sha'erne fastlåst i runneren): `manifest1939.json`, `linje-approvals2.json`,
`linjeark2.txt`, `linjeark2-token.txt` (genrenderet 9/11 efter Codex' fund 2 med de uændrede svar; de forrige er
`*.f1.*`), `approvals1939.json` (efter `cf3ef35a`; den forrige er `approvals1939.f1.json`),
`svar-model2.json`, `kort-undtagelser.txt`. Runneren tjekker også kæden mellem dem (mapping → linjeark og token;
approvals → manifest, modelsvar og kort-token; manifestets regelversion og invarianter). Alle linjer er kun antal,
koder og hashes. Prod-skrivning (`apply-*`, `fortryd`) sker kun i projektejerens shell med `--jeg-mener-det --go
<kode>`. Hovedcheckouten skal være ren og stå på den commit, GO er bundet til (`main` efter merge).

## To ceremonier

1. **DDL** (blok `-- ===== trin 6d-1: placement og medlemskab for flere kilder =====` + `db-rls.sql` i én transaktion,
   `lock_timeout 5s`). Kun `CREATE OR REPLACE FUNCTION` + `REVOKE/GRANT`; to nye funktioner
   (`private.membership_component_states()`, `private.placement_human_header_levels(bigint)`), fire ændrede. Kontrol efter: grant-matrixen `---------xxx` (fire private funktioner uden EXECUTE
   for anon/authenticated; promotions-RPC'en kun authenticated; koordinat-RPC'en begge).
2. **Data** (`apply-data`): ét kald af `placement_ceremoni.sql` (src=3, `helpost_kind=person`,
   `expect_laeser_1939=uaendret`) i ÉN transaktion under egen `statement_timeout=15min`: linjeskema (8 entries),
   138 overskrifter, 528 record- og 528 persona-placements, ledger, 528 medlemskaber via promotions-RPC'en og
   revalidering af 528 publicerede biografier. Ingen genoptagelse: en fejl ruller alt tilbage.

## Rækkefølge

| Trin | Handling | Forventet (generalprøven 9/11, stand-in `6d1a`) |
|---|---|---|
| 0 | `maal` | `T6D1_MAAL fase=foer entries=1 placements=0 persona=0 ledger_mapped=0 ledger_retained=576 memberships=0 published=563 stale=0 corroborated=na conflict=na KOORD_2018_20=99a5a2de… KOORD_SRC=2136dfc0…`, `T6D1_MAAL_OK tilstand=foer` |
| 0b | `anon` | 3 × `T6D1_ANON_KOORD raekker=1113 ms=…` (prod 9/11: 563-612 ms) |
| 1 | `dump` | `DUMP_6D1_OK tilstand=foer`, `EKSTERN_6D1_OK … rundtur=ok`, `DUMP_6D1_MAAL_OK … vindue_linjer=136`, `DAA_T6D1_DUMP=…` |
| 2 | `go-ddl` → projektejeren `apply-ddl --jeg-mener-det --go <kode>` | `T6D1_VINDUE_OK sammenligning=eksakt linjer=136`, `T6D1_APPLY_DDL_OK tilstand=ddl blok=217b3f44ce29fd84` |
| 3 | advisors (`get_advisors` security + performance, læse-kun) | ingen nye fund ud over de kendte |
| 4 | `maal` | `fase=ddl … corroborated=0 conflict=2`, KOORD-hashes uændrede |
| 5 | `dump` | `DUMP_6D1_OK tilstand=ddl` (data-dumpet; fortrydelsens grundlag) |
| 6 | `go-data` | `manifest=5e09d1ecc37e2615 mapping=89cbc9e132e61be8 approvals=860038261115b6cb kort=aa8ee91437deac93`, `GO_6D1_DATA_KODE=…` |
| 7 | projektejeren `apply-data --jeg-mener-det --go <kode>` | se næste tabel |
| 8 | `verify` | `T6D1_VERIFY_OK tal=8,528,528,528,48,528,563,0,441,3`, `T6D1_ANON_KOORD … ms=…` |
| 9 | `anon` | 3 målinger efter (forventet ≈1,45-1,57 s; færdigbevisets før/efter) |

`apply-data`'s linjer:

| Linje | Betydning |
|---|---|
| `T6D1_PAKKE_OK filer=7 headers=138 entries=8` | pakken og kæden mellem filerne |
| `T6D1_VINDUE_OK sammenligning=eksakt linjer=136` | intet i `public`/`private` er ændret siden data-dumpet |
| `T6D1_DATA_START fase=ddl published=563 koord=99a5a2de04b1b921` | |
| `T6D1_CEREMONI_TID saetninger=574 maks_s=12.7 sum_s=44.7` (stand-in) | `\timing` fra ceremonien |
| `PLC_OK entries=8 headers=138 placements=528 persona=528 ledger_mapped=528 memberships=528 revalideret=528 corroborated=441 conflict=3 human_levels=102` | ceremoniens kvittering (fastlåst) |
| `T6D1_APPLY_DATA_OK fase=data tal=8,528,528,528,48,528,563,0,441,3 koord=99a5a2de04b1b921 koord_src=2136dfc066fd41d7` | 2018-20's og 1939's læserrækker byte-ens |

**Tid.** Ceremoniens langsomste sætning er 12,7 s på stand-in. Med den værste skrive-faktor, der er målt (6c-2:
≈27) giver det ≈5,7 min, under ceremoniens 15 min; hele ceremonien ≈45 s × 27 ≈ 20 min. Læsefaktoren for
koordinat-RPC'en er målt direkte: 2,5-2,7 (prod 563-612 ms mod stand-in 225 ms før 6d-1). `maal`'s `sekunder=` (prod
3,0 / stand-in 0,6) indeholder rundture og er ikke en faktor for enkeltsætninger.

## Fastlåste værdier og deres uafhængige kilder

Runneren afviser prod, hvis en fastlåst værdi mangler (`T6D1_IKKE_FASTLAAST`; kun `anon` og `dump-kopi` er undtaget).
Tallene er ceremoniens egne på stand-in'en, men hvert er sammenholdt med en kilde uden for ceremonien:

| Værdi | Uafhængig kilde |
|---|---|
| placements 528 | manifest + approvals genberegnet: 414 `machine_ok` + 114 via kort (kortrundens 529 − henvisningsposten) |
| persona / memberships 528 | ≤ 534 (spec §8); 0 placerede records uden accepteret identitet (de 24 uden ligger blandt de 64 uplacerede) |
| bindings / revalideret 528 | publicerede bindinger på den genberegnede mængde |
| ledger 528 + 48 | = 576 legacy-rækker (spec §8) |
| human_levels 102 | manifestets placerede poster med `human_header_levels` |
| headers 138, entries 8, published 563 | manifest, mapping, `maal` i fase ddl (afledes også af runneren og sammenlignes) |
| corroborated 441, conflict 3 | kun ceremoniens tal; konflikterne er gennemgået (decisions 2026-11-09) |

Genberegningen af de placerede records (til færdigbeviset): en record placeres, når den er `machine_ok`, eller når
alle dens gruppekort står i `approvals1939.json`'s `gruppekort` og dens øvrige årsager (ud over
`overskrift_ikke_fundet:*`) enten er ingen eller dækket af en record-godkendelse i `approvals`:

```python
S = {p['record_key'] for p in m['placements'] if p['status'] == 'machine_ok' or (
       all(c['id'] in gk for c in p.get('gruppekort') or []) and
       (not [r for r in p['reasons'] if not r.startswith('overskrift_ikke_fundet:')] or p['record_key'] in ak))}
# m = manifest1939.json; gk = {g['id'] for g in a['gruppekort']}; ak = {x['record_key'] for x in a['approvals']}
```

**Efter Codex-review og merge:** `T6D1_BLOK` (og `T6D1_RLS`) genpinnes, hvis reviewet rører DDL-blokken eller
`db-rls.sql`; ændres `placement_ceremoni.sql`, køres data-generalprøven igen. Alle `go-*` laves på ny efter merge
(commit indgår i koden), og hovedcheckouten skal stå på `main`.

Afviger `maal` i trin 0 (`MAAL_6D1_UKENDT`), er prod ændret siden dumpet `1653c8f7…`: ny `dump-kopi`, ny `standin`,
generalprøven igen, fastlås igen. Prod røres ikke.

## Vindue og frys

Frys fra `dump` (trin 1) til `verify` (trin 8): ingen redaktionelle skrivninger i prod. **Fortryd kun under en meldt frys:** vinduestjekket står lige før markøren, men fra det til restoren (ACL-trin og selve restoren, sekunder til minutter) kan et medlems bogmærke eller tilmelding stadig nå at blive skrevet og så slettes (kendt begrænsning, runnerreview 9/11 fund 2; gælder også 32). Runneren kontrollerer:
`change_set` må ikke vokse mellem dump og `apply-*`, og vinduesaftrykket (én linje pr. tabel/sekvens, antal + hash)
skal være eksakt som ved dumpet før `apply-ddl` og `apply-data`. I `fortryd` undtages kun ceremoniens egne
tabeller/sekvenser (målt på `6d1a`):

- DDL: `public.change_event_id_seq public.change_set_id_seq public.lineage_scheme_entry_id_seq`. Målt på den rene
  stand-in `6d1c` giver DDL → data → fortryd-data intet ud over foer-dumpet (`-`); de tre sekvenser undtages bevidst,
  fordi en tilbagerullet data-ceremoni rykker dem (`6d1a`), og fortryd-DDL ellers ikke kunne køre bagefter. Tabellerne
  sammenlignes stadig; kun `nextval` uden committede rækker skjules.
- Data: 18 tabeller/sekvenser: `private.extraction_run`, `legacy_placement_disposition`,
  `narrative_publication_event`, `source_observation`, `source_persona_placement(_decision)`,
  `source_record_occurrence`, `source_record_placement(_decision)`, `public.change_event(_id_seq)`,
  `change_set(_id_seq)`, `lineage_scheme_entry(_id_seq)`, `lineage_scheme_entry_lineage`,
  `person_lineage_membership`, `person_slaegt_membership`. `public.bookmark`/`profiles` sammenlignes altid.

## Stoppunkter

| Stop | Tilstand | Udgang |
|---|---|---|
| `DDL_6D1 fejlede` | rullet tilbage | ret årsagen; ny GO |
| `T6D1_DATA_FASE` / `T6D1_DATA_FAERDIG` | intet kørt | data kræver fase ddl med de fastlåste tal; gentaget data stopper her, før ceremoniens `PLC_PRE_FASE` |
| `T6D1_CEREMONI_FEJL (PLC_PRE_…)` | intet skrevet | prod afviger fra stand-in'en: ny `dump-kopi` og generalprøve |
| `T6D1_CEREMONI_FEJL (… ); IKKE committet (fase ddl)` | runneren har målt fasen efter fejlen: alt rullet tilbage, men sekvenserne er rykket | næste `apply-data` stopper på `T6D1_VINDUE_BRUDT_FOER_DATA` (kun `…_seq`): `dump` igen og ny GO (bevist på `6d1a` 9/11) |
| `T6D1_CEREMONI_FEJL_EFTER_COMMIT` | committet (fase data); fejlen kom efter COMMIT (fx forbindelsesbrud under slut-optællingerne) | `verify`; ellers `fortryd` |
| `T6D1_CEREMONI_UAFKLARET` | fasen kunne ikke måles efter fejlen | `maal` før alt andet |
| `T6D1_CEREMONI_INGEN_OK` | rc 0 uden `PLC_OK` | `maal`; se ceremoni-mappen |
| `T6D1_EFTER_DATA` / `T6D1_EFTER_DATA_STALE` | committet, tallene passer ikke | `fortryd` (bruger rå fase) |
| `T6D1_VINDUE_BRUDT_FOER_DDL` / `…_FOER_DATA` | intet kørt | noget er skrevet siden dumpet (`afvigende.txt`: kun navne); afklar, `dump` igen, ny GO |
| `T6D1_VINDUE_BRUDT` (fortryd) | intet restoret, ingen markør | en restore ville slette skrivninger efter dumpet (typisk `public.bookmark`); projektejeren afgør, runneren har ingen tilsidesættelse |
| `T6D1_FORTRYD_CS_IKKE_CEREMONIENS` / `T6D1_FORTRYD_CS_EFTER_DDL` | intet restoret, ingen markør | change_sets siden dumpet, som ikke er ceremoniens (også projektejerens egne rettelser): en restore ville slette dem; projektejeren afgør |
| `T6D1_FORTRYD_DDL_UKENDT_OBJEKT` / `T6D1_FORTRYD_KATALOG_AENDRET` | intet droppet/restoret | kataloget rummer andet end 6d-1's to nye funktioner (DDL) eller er ændret siden data-dumpet |
| `T6D1_PAKKE_SHA` / `T6D1_PAKKE_KAEDE` | intet kørt | en bundet fil er ændret efter GO |
| `T6D1_FORTRYD_IGANG` | en fortrydelse er påbegyndt | som 6c-3: gennemfør med samme dump; markøren flyttes manuelt efter `maal` |

## Fortrydelse

`DAA_T6D1_DUMP=<kvittering> koer.zsh 33-trin6d1.sh go-fortryd` → projektejeren `fortryd --jeg-mener-det --go <kode>`.
Fortrydelsen kræver, at alle change_sets efter dumpet er ceremoniens egne (ét linjeskema-anker `placement-ceremoni (GO …)`, ét medlemskab og revalideringer, alle med transaktionens `created_at`; efter foer-dumpet: ingen), og at kataloget er uændret siden data-dumpet. Data = restore af data-dumpet (fase ddl); DDL = katalogdiffens nye funktioner droppes + restore af foer-dumpet +
`db-rls.sql` (kun efter data er fortrudt). Efter: ACL, default-ACL, katalog og restore-hash som dumpet, KOORD
uændret (`T6D1_FORTRYD_OK`). Manuel fortrydelse af én persons medlemskab: 5c-1's `red_reverse_placement_membership`
(komponenttilstanden genberegnes).

## Kendte følger

- 1939's rækker i `public_person_source_coordinates` forbliver `legacy_external_id` til 6e (afgørelse 4: 1939 har
  ikke entydige `(entry, nummer)`); `KOORD_SRC` er uændret.
- Koordinat-RPC'en bliver ≈2,5× langsommere (decisions 2026-11-09 pkt. 4; accepteret, rettes i 6e). Web henter den
  i to sider (1113 rækker); hver side er sin egen sætning under anon-grænsen på 3 s, men indlæsningen venter på
  begge. Overskrider et kald grænsen, fanger web fejlen (`console.warn '[loadModel] public_person_source_coordinates
  utilgængelig — linjer/kilder degraderet'`), og læseren viser personer uden linje- og kildekoordinater. Prod-dagens
  stikprøve i browseren: en 2018-20-person viser sin linje og sit nummer, og konsollen har ingen sådan advarsel.
- Én ny `conflict`-komponent (137↔937) registreres som konfliktkort; intet skrives om den.
- 64 records placeres ikke: 37 uden nummereret post (heraf 27 i oversigtszonerne), 24 uden accepteret identitet, de
  ubesvarede/afviste kort og henvisningsposten.

## Generalprøven 9/11

- `6d1a` (`daa5ab_ddl_standin_20261109131019_6d1a`, fra `dump-kopi` `1653c8f7…`): DDL → iteration af data-
  forventningerne (de tre fund i decisions 2026-11-09 rettet undervejs) → data → `verify` → fortryd-data → fortryd-DDL
  (undtagelseslisterne målt) → fuld ren kørsel med alle værdier fastlåst (ingen `T6D1_FASTLAAS`): `maal` → `dump` →
  forkert GO (`GO_MISMATCH`) → `apply-ddl` → `dump` → `apply-data` (47 s) → gentaget data (`T6D1_DATA_FAERDIG`) →
  `verify`. Derefter: ændret mapping efter GO → `T6D1_PAKKE_SHA` (filen lagt tilbage, sha verificeret); et bogmærke
  efter data-dumpet → `fortryd` stoppede med `T6D1_VINDUE_BRUDT` (kun `public.bookmark`, ingen markør); fjernet →
  fortryd-data `T6D1_FORTRYD_OK`. `6d1a` står i fase `ddl`.
- `6d1b` (`daa5ab_ddl_standin_20261109141130_6d1b`, samme dump): lokal før-måling af anon-tiden (225 ms); DDL; en
  placeret persona fik ny accepteret identitet → `PLC_PRE_MEMBERSHIP_OVERLAP` (erstatningspersonen havde
  medlemskab), med en person uden medlemskab → `PLC_PRE_IDENTITY n=1`; begge uden skrivning (fase `ddl`). `6d1b` er
  manipuleret (`decided_by_name='generalproeve'`) og må aldrig bruges som kilde til noget.
- `6d1c` (`daa5ab_ddl_standin_20261109142426_6d1c`, samme dump): den rene vej med alle værdier fastlåst — `dump` →
  `apply-ddl` → `dump` → `apply-data` (samme tal) → fortryd-data → vinduet målt eksakt mod foer-dumpet (`-`) →
  fortryd-DDL `T6D1_FORTRYD_OK tilstand=foer` (2 funktioner droppet). `6d1c` står i fase `foer`.

## Codex-review 9/11 (Task 10 trin 1)

`gpt-6.1-sol` over hele grenens diff: NO-GO med tre fund, alle dømt nødvendige af Opus og rettet efter projektejerens
ja: linjearket kontrolleres mod det aktuelle manifest (`0677d50c`, `SHEET_STALE`), kortsvarene bindes til opslaget
(`d6ef694c`, `KORT_OPSLAG_AENDRET`/`KORT_SVAR_SIDE`; `approvals` kræver nu `--records-json` og `--rendition-text`), og
slægtledskort bekræfter fraværet af en gruppe, når kuld undtages (`8d83de12`). Målt på de aktuelle filer: de 57
genbrugte modelsvar har byte-ens opslag; ingen poster har kuld-undtagelsen; linjearket fra 8/11 afveg kun i tre
fordelingstal (+1). Arket er genrenderet med de samme svar (mappingens entries uændrede, ny pin `89cbc9e1…`);
`approvals1939.json` genberegnes byte-ens. Den rene stand-in `6d1c` gav derefter samme tal (`PLC_OK` uændret).

**Runnerreview 9/11.** `gpt-6.1-sol` over `33-trin6d1.sh` (+ `lib.zsh`, sammenlignet med 32): NO-GO med fire fund,
dømt af Opus og rettet efter projektejerens ja (kun i den private runner): (1) fortrydelsen godtog change_sets fra
ceremoniens egen aktør → kræver nu, at de er ceremoniens (`T6D1_FORTRYD_CS_*`) og at kataloget er uændret; (2)
vinduestjekket flyttet lige før markøren, resten kendt begrænsning (ovenfor); (3) DDL-fortrydelsen droppede alle nye
funktioner → fastlåst liste med præcis de to; (4) en fejl efter ceremoniens COMMIT blev meldt som tilbagerulning →
fasen måles og meldes. Prøvet på `6d1c`: egen rettelse efter data → `T6D1_FORTRYD_CS_IKKE_CEREMONIENS` uden markør,
fjernet → fortryd OK; ceremoni med fejl før COMMIT → »IKKE committet (fase ddl)«, efter COMMIT →
`T6D1_CEREMONI_FEJL_EFTER_COMMIT` (fase data) og fortryd-data OK; fremmed funktion → `T6D1_FORTRYD_DDL_UKENDT_OBJEKT`
uden drop, fjernet → fortryd-DDL OK (2 funktioner); til sidst en fuld ren kørsel med samme tal. `6d1c` står i fase data.
