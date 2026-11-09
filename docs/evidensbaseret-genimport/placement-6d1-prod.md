# Færdigbevis: trin 6d-1 i prod — 1939's placements og medlemskaber (2026-11-09)

Spec: `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §8. Plan:
`docs/superpowers/plans/2026-11-08-trin6d1-placement-medlemskab.md` Task 10. Runbook: `docs/runbooks/trin6d1-prod.md`.
Kun antal, nøgler og hashes; ingen tekst eller værdier.

## Forløb

| Trin | Resultat |
|---|---|
| Repo | `main` `997a033c` (merge af PR #310 ved head `5c381c0d`; træet identisk med grenens head). DDL-blokkens sha `217b3f44…`, `db-rls.sql` `e63c2182…` = de fastlåste |
| `maal` (før) | `fase=foer entries=1 placements=0 persona=0 ledger_mapped=0 ledger_retained=576 memberships=0 published=563 stale=0`, `KOORD_2018_20=99a5a2de…`, `KOORD_SRC=2136dfc0…` = fastlåst fra prod-dumpet `1653c8f7…`; 3,4 s |
| `anon` (før) | koordinat-RPC'en 3 × 1.113 rækker: 574 / 531 / 526 ms |
| Dump før DDL | `daa-prod-20261109160931-6d1.dump`, sha `9cb98602…`, age `cd91ec4e…`, SFTP-rundtur ok; restore-hash `8c6f5f17…`, 0 forældreløse, vindue `f4229ef0…` (136 linjer), `change_set_max` 3049 |
| DDL (GO `c8f09536`) | `T6D1_VINDUE_OK sammenligning=eksakt linjer=136`, `T6D1_APPLY_DDL_OK tilstand=ddl blok=217b3f44ce29fd84`, 14,0 s |
| Grants og lint | runneren: grant-matrixen `---------xxx` (de fire private funktioner uden EXECUTE for anon/authenticated; promotions-RPC'en kun authenticated; koordinat-RPC'en begge). `get_advisors` ikke kørt (MCP'en er logget ind på en anden organisation). Blokken opretter ingen tabeller, views eller triggere (RLS- og default-ACL-tjek gælder ikke); alle seks funktioner har fast `search_path`, også de to `SECURITY DEFINER` |
| `maal` (ddl) | `fase=ddl … corroborated=0 conflict=2`, KOORD-hashes uændrede (kørt af `apply-ddl`). Den tredje `conflict` efter data er 1939's medlemskab for 137↔937 (åben backlog, decisions 2026-11-09) |
| Dump før data | `daa-prod-20261109162937-6d1.dump`, sha `9e628a58…`, age `0748e114…`, SFTP-rundtur ok; restore-hash og vindue = før-dumpets (DDL'en rører kun funktioner), `change_set_max` 3049. Fortrydelsens grundlag |
| Data (GO `79609895`) | `T6D1_PAKKE_OK filer=7 headers=138 entries=8`, vindue eksakt; `T6D1_CEREMONI_TID saetninger=574 maks_s=21.6 sum_s=122.2` (stand-in 12,7 / 44,7 s; faktor ≈2,7); `PLC_OK` = den fastlåste linje; `T6D1_APPLY_DATA_OK fase=data tal=8,528,528,528,48,528,563,0,441,3`, 129 s |
| `verify` | `T6D1_VERIFY_OK tal=8,528,528,528,48,528,563,0,441,3 koord=99a5a2de04b1b921 koord_src=2136dfc066fd41d7` |
| `anon` (efter) | 3 × 1.113 rækker: 1.285 / 1.244 / 1.260 ms (verify: 1.231 ms) |

Fulde B1-hashes: `database-current-state.md` §24.

## Spec §8

- **Placement:** 528 af kilde 3's 592 records har accepteret record-placement, og alle 528 har persona-placement
  (`principal_member`) med accepteret identitet. Uafhængig genberegning fra de bundne filer (runbookens formel over
  `manifest1939.json` + `approvals1939.json`): 528 = 414 `machine_ok` + 114 via kort. 138 overskrifter som
  observationer (8 linje, 57 slægtled, 73 kuld), 8 entries i linjeskemaet, 102 placements med menneskebekræftede
  niveauer.
- **De 64 uden placement** (målt på stand-in `6d1c`, se nedenfor): 21 records med personpost men uden
  hovedperson-persona (6d-2), 8 uden personpost (6 `structural_context`, 2 `cross_reference`), 35 med persona (32 med
  accepteret identitet, 3 uden). Efter manifestets årsager: 53 uden nummereret post (heraf 27 i oversigtszonerne, PDF
  504-505/508-509), 7 ikke parret, 3 ikke alignet, 1 nummer tabt i renditionen. Spec'ens »37 uden nummereret post« var
  målt før oversigtszonerne og raw.txt-revisionen (decisions 2026-11-08 pkt. 3 og 2026-11-09).
- **Overskrifter og invarianter:** 0 placements uden overskrift — ceremonien stopper ellers før skrivningen
  (`PLC_PRE_HEADERS`) og efter (`PLC_POST_NEAREST`: `placement_header_violations(3)=0`). Manifestets 5 invarianter er
  sande (`PLC_PRE_INVARIANTS`). Kort: 21 gruppekort (102 poster), alle godkendt; 20 strukturkort; 14 record-godkendelser.
- **Publiceringer:** 0 `stale_published` for kilde 3 før (`maal`) og efter (`verify`); 528 revalideret; 563
  publicerede før og efter.
- **Ledger:** alle 576 legacy-rækker for kilde 3 har disposition: 528 `mapped` (version 2, med ceremoniens placement;
  koblingen via identitet) og 48 `retained_legacy`. De 48 er 5c-1's uændrede version 1: ceremonien skriver kun en ny
  version, når dispositionen skifter, så planens grund (`ingen_identitet` → `parkeret_gren` → `ingen_nummereret_post`
  → `ingen_placement`) er beregnet og kontrolleret i transaktionen, men ikke gemt for dem.
- **B6 (afledt):** `membership_component_states()` giver 441 `corroborated` (alle med to kilder), 3 `conflict`, 212
  `single` og 224 `none` (målt på `6d1c`; `corroborated`/`conflict` også i prods `verify`). Eksempel: komponent 1 =
  personerne 1 og 924, linje 1; person 1 har medlemskab fra kilde 1 (2018-20), person 924 fra kilde 3 (1939).
- **2018-20 uændret:** `KOORD_2018_20` er `99a5a2de…` i alle tre faser. Ceremoniens 11 paritetshashes (andre kilders
  placements, medlemskaber, publiceringstilstand og ledger; redaktørens og læserens fem læsere; koordinaterne) var ens
  før og efter (`PLC_POST_PARITET`), ellers var intet committet.
- **Læseren for 1939:** `KOORD_SRC` uændret (afgørelse 4: 1939's numre er gruppelokale, så læseren viser legacy indtil
  6e).
- **Tid:** koordinat-RPC'en som anon 526-574 ms før → 1.231-1.285 ms efter (anon-grænse 3 s; forventet
  1,45-1,57 s). Webben henter den én gang ved indlæsning. Faktalæseren er ikke ændret af 6d-1.

**Målt på stand-in `6d1c`:** de 64 uplaceredes fordeling, `single`/`none` og B6-eksemplet. `6d1c` er bygget fra
prod-dumpet `1653c8f7…` og kørt med samme pakke; dens `maal` efter data er byte-ens med prods `verify`-linje (alle ti
tal og begge KOORD-hashes), og `PLC_OK` er den samme fastlåste linje.

## Frys og fortrydelse

Frysen gik fra dumpet før DDL til `verify`. Vinduesvagten var eksakt grøn før DDL og før data, og `change_set_max`
var 3049 ved begge dumps. Fortrydelse er nu kun mulig ved restore af data-dumpet (og derefter DDL-dumpet), så længe der
ikke er skrevet andet i prod; `fortryd` stopper selv ellers. Kendt begrænsning: et bogmærke eller en tilmelding,
skrevet mellem vinduestjekket og restoren, går tabt (runnerreview fund 2); fortryd derfor kun under meldt frys.

## Ikke gjort

- `get_advisors` (MCP'en er på en anden organisation); erstattet af runnerens grant-kontrol og blokkens lint ovenfor.
- Personsidens kald pr. person er ikke tidsmålt i prod. Ceremoniens paritet viser, at biografi- og familielæserne er
  byte-ens, og faktalæseren er uændret; kun koordinat-RPC'en er blevet dyrere (målt). 6e gør den billigere.
- Grunden for de 48 `retained_legacy` er ikke gemt (se Ledger).
- Konfliktkortet 137↔937 og de 3 `conflict`-komponenter er åben backlog (decisions 2026-11-09); intet er skrevet.
