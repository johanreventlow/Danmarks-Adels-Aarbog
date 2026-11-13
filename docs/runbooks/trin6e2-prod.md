# Runbook: trin 6e-2 i prod — kildeetiket, sidekort og koordinater

Spec: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` §6, §8 og §12. Plan:
`docs/superpowers/plans/2026-11-13-trin6e2-kildeetiket-koordinater.md` (Task 10-11). Beslutning: `docs/decisions.md`
2026-11-13 (6e-2's kildeetiket).
Runner: `~/.private/5ab-overfoersel/40-trin6e2.sh` med `40-trin6e2-vindue.sql` (aldrig i repoet). Den kaldes via
`/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 40-trin6e2.sh <handling>` fra operatørens cwd. Alle linjer er kun
antal, koder og hashes; ceremoniens før/efter-linjer (`ETK_LINJE`) står kun i 0600-filen. Prod-skrivning (`apply-*`,
`fortryd*`) sker kun i projektejerens shell med `--jeg-mener-det --go <kode>`. Hovedcheckouten skal være ren og stå på
den commit, GO er bundet til (`main` efter merge).

**`koer.zsh` (løst 13/11):** `koer.zsh` godtog kun scriptnavne `^[0-3][0-9]-…`, så `40-trin6e2.sh` blev afvist.
Prod har brug for `koer.zsh`, fordi den sætter `DAA_EXPECTED_TARGET` og gemmer `DAA_T6E2_DUMP`. Controlleren har
udvidet reglen til `^[0-4][0-9]-`. `koer.zsh` er GO-bundet i alle runnere, så ældre runneres GO-koder er ændret og skal
laves på ny, hvis de bruges igen.

## To ceremonier

1. **DDL** (`apply-ddl`): blok `-- ===== trin 6e-2: kildeetiket, sidekort og koordinater =====` (sidst i
   `db-migrations.sql`, 651 linjer) + `db-rls.sql` i én transaktion, `lock_timeout 5s`. Ikke kun `CREATE OR REPLACE`:
   - `ALTER TABLE public.source ADD COLUMN sidekort jsonb` + CHECK `source_sidekort_gyldigt`.
   - Ændret CHECK `narrative_record_publication_record_label_check` (tillader tom postdel `''`).
   - `DROP` + `CREATE` af `public.public_person_source_coordinates()` (ny returtype med `printed_page`), samme
     `REVOKE`/`GRANT`.
   - 8 nye funktioner: `private.sidekort_gyldigt(jsonb)`, `public.source_trykt_side(bigint,text)`,
     `public.side_trykt(public.citation)`, `private.linje_kode(text,text)`, `private.record_key_uden_bognoegle(text)`,
     `private.narrative_record_wanted_labels_ex(uuid,boolean)`, `private.narrative_record_wanted_labels(uuid)`,
     `private.membership_current_set()`.
   - 4 ændrede: `private.narrative_record_labels(uuid)`, `private.validate_reimport_case_elements(jsonb,jsonb)`,
     `public.public_person_source_coordinates()`, `public.public_person_facts(bigint[])`.

   Lige før DDL'en gemmer runneren fortrydelsens snapshot (`fortryd-ddl-<stamp>/fortryd.sql` + `snapshot.json`).
   Kontrol efter:
   - grant-matrixen `--xxxx------------xxxx`;
   - katalogdiffen mod foer-dumpet er præcis DDL'ens 15 objekter (`T6E2_DDL_KATALOG_DIFF`);
   - vinduet afviger kun i `public.source` (rækkernes form får `"sidekort": null`).
2. **Data** (`apply-data`): ét kald af `etiket_ceremoni.sql` (src=3) i ÉN transaktion under egen
   `statement_timeout=15min`. Ceremonien skriver:
   - kildens sidekort (`sidekort_1939.json`);
   - linjeskemaets 5 rettede etiketter (`linjeetiketter_6e2.json`);
   - 561 bindingers `record_label`/`citation_label`, heraf 33 med tom postdel;
   - revalidering af de 561.

   2 bindinger for staged personer springes over. Ingen genoptagelse: en fejl ruller alt tilbage. Aktøren skal være
   projektejerens redaktionsprofil, og den skal findes i `auth.users` (runneren tjekker begge dele: `T6E2_AKTOER`).

## Rækkefølge

| Trin | Handling | Forventet |
|---|---|---|
| 1 | **Web-deploy (Del B)**: PR `feat/trin6e2-klient` merget og deployet (Vercel) | Klienten viser prod korrekt før DDL (Task 8). Browserens stikprøve: Conrad 392 og 1198 åbner, og konsollen har ingen fejl. |
| 2 | `go-ddl` | `GO_6E2_DDL_KODE=…` (binder commit, blokkens og filernes sha, runneren, `40-trin6e2-vindue.sql`, `lib.zsh`, `koer.zsh`, `rollback-preflight.sql`) |
| 3 | `maal` | `T6E2_MAAL fase=foer KOORD_ANDRE=66e9afd9… ETIKETTER_ANDRE=d97decc7… BINDINGER_RECORD=561 SPRUNGET=2 UDEN_PLACEMENT=33 STALE=0 BIO_OFFENTLIGE=1100 FAKTA_BUNDNE=2264 FAMILIEKILDER=06e71a11… SKEMA_ETIKETTER=83c4e28d…`, `T6E2_MAAL_OK tilstand=foer` |
| 3b | `anon` | `T6E2_ANON raekker=1000,111,1 koord_s1_ms=… koord_s2_ms=… bio392_ms=…` (prod før; median af 3) |
| 4 | `dump` | `DUMP_6E2_OK tilstand=foer`, `EKSTERN_6E2_OK … rundtur=ok`, `DAA_T6E2_DUMP=…` |
| 5 | advisors (security + performance, læse-kun) | Spec §6: Supabase-MCP ser ikke DAA-projektet, så det er den statiske ækvivalent. Ingen nye fund ud over de kendte. |
| 6 | projektejeren `apply-ddl --jeg-mener-det --go <kode>` | i rækkefølge: `T6E2_VINDUE_AFVIGER sammenligning=eksakt navne=-`, `T6E2_VINDUE_OK sammenligning=eksakt`, `B1_6E2_OK tilstand=foer …`, `T6E2_SNAPSHOT_OK … funktioner=4 nye=8`, `T6E2_VINDUE_AFVIGER sammenligning=ddl navne=public.source`, `T6E2_VINDUE_OK sammenligning=ddl`, `T6E2_APPLY_DDL_OK tilstand=ddl blok=5fed142013780f29 katalog=ok fortryd_ddl=…`. Før snapshottet kræves kataloget lig foer-dumpets (`T6E2_KATALOG_FOER_DDL`), og `db-rls.sql` køres som sha-tjekket kopi. |
| 7 | `maal` | `fase=ddl`; andre kilders hashes uændrede (runneren stopper ellers) |
| 8 | advisors | som trin 5 |
| 9 | `dump` | `DUMP_6E2_OK tilstand=ddl` (data-dumpet; fortrydelsens grundlag) |
| 10 | `go-data` | `sidekort=cd013e9c420e22e1 etiketter=5c34881f25dc4350 ceremoni=d39c4208b97a9f53 maal=b0424077ab73c004`, `GO_6E2_DATA_KODE=…` |
| 11 | projektejeren `apply-data --jeg-mener-det --go <kode>` | se næste tabel |
| 12 | `maal` | `fase=data … BINDINGER_RECORD=0 SPRUNGET=2 UDEN_PLACEMENT=0 STALE=0 BIO_OFFENTLIGE=1100 FAKTA_BUNDNE=2264` |
| 13 | `vindue` | `T6E2_CS_OK ceremoniens=561 fremmede=0`, `T6E2_VINDUE_AFVIGER sammenligning=data navne=private.narrative_publication_event,private.narrative_record_publication,public.change_set,public.change_set_id_seq,public.lineage_scheme_entry,public.source`, `T6E2_VINDUE_OK` |
| 13b | `anon` | 3 målinger efter; koordinat-RPC'en ≤ 0,6 s pr. kald, Conrads biografi inden for 209-487 ms (spec §8) |
| 14 | browsertjek | se nedenfor |

`apply-data`'s linjer:

| Linje | Betydning |
|---|---|
| `T6E2_VINDUE_OK sammenligning=eksakt` | intet i `public`/`private` er ændret siden data-dumpet |
| `T6E2_DATA_START fase=ddl bindinger=561 sprunget=2 tomme=33 entries=5 bio=1100 fakta=2264 andre=66e9afd96e1b/d97decc71a36` | forventningerne afledt af `maal` og etiketfilen, lig de fastlåste |
| `T6E2_CEREMONI_TID saetninger=… maks_s=… sum_s=…` | `\timing` fra ceremonien |
| `ETK_OK bindinger=561 tomme=33 entries=5 revalideret=561 sprunget=2 stale=0 koord_andre=66e9afd96e1b201a55c3984c0c1d66a3 etiketter_andre=d97decc71a3621127abb3f8122d8ed7a` | ceremoniens kvittering (fastlåst) |
| `T6E2_ETK_LINJER antal=5` | én før/efter-linje pr. rettet entry (kun i 0600-filen) |
| `T6E2_CS_OK ceremoniens=561 fremmede=0` | alle change_sets efter dumpet er ceremoniens (561, én `created_at`, aktøren) |
| `T6E2_VINDUE_AFVIGER sammenligning=data navne=…` + `T6E2_VINDUE_OK sammenligning=data` | rækker afviger kun i ceremoniens 6 tabeller/sekvenser |
| `T6E2_APPLY_DATA_OK fase=data tal=0,2,0,0,1100,2264,… andre=…` | andre kilders koordinater og etiketter byte-ens |

Ceremoniens tre filer (`etiket_ceremoni.sql` og de to json) kopieres til kørselsmappen, sha-tjekkes mod de fastlåste
værdier og køres som kopier; det samme gælder `maal_trin6e2.sql` ved hver måling og `db-rls.sql` i `apply-ddl` og
`fortryd`.

**Tid.** Generalprøven 13/11 på `daa5ab_ddl_standin_20261113150400_g1` (prods timeouts, `statement_timeout='2min'`):
- ceremonien 30 s i alt, langsomste sætning 11,5 s. Med den værste målte skrive-faktor (≈27, 6c-2) giver det ≈5,2 min
  for den langsomste sætning, under ceremoniens 15 min;
- `anon` efter data: koordinat-RPC'en 96 ms pr. kald (før DDL 558 ms), Conrads biografi (392) 23 ms;
- data-`fortryd`: `T6E2_FORTRYD_OK` med `restore_fejl=5` (de kendte `current_rolle`/`media_object_synlig_anon`-linjer +
  advarslen; vurderet godkendt); `fortryd-ddl`: `T6E2_FORTRYD_DDL_OK`, derefter `maal` fase foer.

På en t6e2_-testkopi uden stand-in'ens timeouts tog DDL'en 0,13 s.

## Fastlåste værdier og deres kilder

Runneren afviser prod, hvis en fastlåst værdi mangler (`T6E2_IKKE_FASTLAAST`; kun `anon`, `vindue` og `dump-kopi` er
undtaget).

| Værdi | Kilde |
|---|---|
| blok `5fed1420…`, `db-rls.sql` `a21d5034…` (= prods, uændret siden 78afc145), `etiket_ceremoni.sql` `d39c4208…`, `maal_trin6e2.sql` `b0424077…`, `sidekort_1939.json` `cd013e9c…`, `linjeetiketter_6e2.json` `5c34881f…` | commit `e2620a3d`; genpinnes, hvis review eller merge ændrer filen |
| `KOORD_ANDRE` `66e9afd9…`, `ETIKETTER_ANDRE` `d97decc7…` | Task 9's forventning = `maal foer` på stand-in-kopien; ens i alle faser |
| 561 / 2 / 33 / 1100 / 2264 | `maal foer` på stand-in-kopien (Task 9: 563 − 2 staged); afledes igen af `maal` i fase ddl |
| entries 5 | etiketfilens længde (spec §12.5) |
| `M[foer]` | `maal foer` på `daa5ab_ddl_standin_20261113070325_6e2t` (Task 10) |
| `M[ddl]` (= `M[foer]`), `M[data]` (`0 2 0 0 1100 2264 75186593… f0cb8884…`) | generalprøven 13/11 (`…_g1`) |
| grant-matrix `--xxxx------------xxxx`, katalogdiffen (15 objekter), vindueslisterne | målt på en t6e2_-kopi af stand-in'en (Task 10); generalprøven bekræfter. Matrixen afhænger ikke af forbindelsens rolle: `db-rls.sql` l. 43 tager EXECUTE på alle private funktioner i samme transaktion, `postgres` har ingen default-ACL i `private`, og de offentlige har eksplicit `REVOKE`/`GRANT` |

**Efter Codex-review og merge:** `T6E2_BLOK` og filernes sha'er genpinnes, hvis reviewet rører filerne; ændres
`etiket_ceremoni.sql`, køres data-generalprøven igen. Alle `go-*` laves på ny efter merge (commit indgår i koden), og
hovedcheckouten skal stå på `main`.

Afviger `maal` i trin 3 (`MAAL_6E2_UKENDT`), er prod ændret siden stand-in-dumpet: ny `dump-kopi`, ny `standin`,
generalprøven igen og fastlåsning igen. Prod røres ikke.

## Kendte vinduer

- **Mellem DDL og data** viser »Kilde i Aarbogen« 1939's **PDF-side** (fx »s. 541« for Conrad 1198), fordi
  `public_person_source_coordinates()` giver `printed_page` gennem `source_trykt_side`, og kildens sidekort først
  kommer med data. Vinduet skal være minutter: trin 7-11 køres i ét stræk.
- **En fuld genkørsel af `db-migrations.sql`** (fx en fremtidig deploy, der kører hele filen) serverer kortvarigt den
  gamle koordinat-RPC uden `printed_page`. Ældre blokke (6d-1 og før) dropper den nye signatur og genskaber den gamle,
  og 6e-2-blokken sidst i filen genskaber den nye (Task 3). Klienten tåler den manglende kolonne (Task 5). Runneren
  kører kun 6e-2-blokken, så prod-ceremonien har ikke vinduet.

## Vindue og frys

Der er frys fra `dump` (trin 4) til `vindue` (trin 13): ingen redaktionelle skrivninger i prod. **Fortryd data kun
under en meldt frys.** Fra vinduestjekket til restoren kan et medlems bogmærke stadig nå at blive skrevet og så slettes
(6d-1's kendte begrænsning).

Runneren kontrollerer:
- `change_set` må ikke vokse mellem dump og `apply-*`;
- vinduesaftrykket (én linje pr. tabel/sekvens, antal + hash) skal være eksakt som ved dumpet før `apply-ddl` og
  `apply-data`.

Tilladte afvigelser:
- **DDL:** `public.source` + `public.change_set_id_seq`.
- **Data:** `private.narrative_publication_event`, `private.narrative_record_publication`, `public.change_set(_id_seq)`,
  `public.lineage_scheme_entry` og `public.source`.
- **fortryd-ddl:** efter tilbagerulningen kun `public.change_set_id_seq`.

`change_event` er aldrig tilladt: ceremonien skriver ingen. `public.bookmark` og `profiles` sammenlignes altid.
`T6E2_VINDUE_AFVIGER` udskriver altid den målte mængde, også når den er tilladt.

## Stoppunkter

| Stop | Tilstand | Udgang |
|---|---|---|
| `DDL_6E2 fejlede` | rullet tilbage | ret årsagen; ny GO |
| `T6E2_KATALOG_FOER_DDL` / `T6E2_FOER_DDL_NYE` / `…_AENDREDE` | intet kørt | kataloget er ændret siden foer-dumpet; afklar, `dump` igen, ny GO |
| `DDL_6E2_NOTIFY` | DDL'en er **committet**, PostgREST har ikke fået `reload schema` | send `NOTIFY pgrst, 'reload schema'` manuelt; derefter `maal` |
| `T6E2_EFTER_DDL*`, `T6E2_DDL_GRANTS`, `T6E2_EFTER_DDL_VINDUE` | DDL'en er **committet** | `maal`; afklar; ellers `fortryd-ddl` |
| `T6E2_DDL_KATALOG` | DDL'en er **committet**, men kataloget er andet end DDL'ens 15 objekter | `fortryd-ddl` vil også stoppe (samme katalogvagt): **nødudgangen** nedenfor |
| `T6E2_DATA_FASE` / `T6E2_DATA_FAERDIG` | intet kørt | data kræver fase ddl med de fastlåste tal; gentaget data stopper her, før ceremoniens `ETK_PRE_FASE` |
| `T6E2_AKTOER` | intet kørt | aktørfilen peger ikke på en redaktionsprofil i `auth.users` |
| `T6E2_FIL_SHA` / `T6E2_BLOK` / `GO_MISMATCH` | intet kørt | en bundet fil er ændret efter fastlåsning eller GO |
| `T6E2_CEREMONI_FEJL (ETK_PRE_…)` | intet skrevet | prod afviger fra stand-in'en: ny `dump-kopi` og generalprøve |
| `T6E2_CEREMONI_FEJL (…); IKKE committet (fase ddl…)` | alt rullet tilbage, men `change_set_id_seq` kan være rykket | næste `apply-data` stopper på `T6E2_VINDUE_BRUDT_FOER_DATA`: `dump` igen (GO-data binder ikke dumpet, så samme GO gælder) |
| `T6E2_CEREMONI_FEJL_EFTER_COMMIT` | committet (fase data) | `maal` og `vindue`; ellers `fortryd` |
| `T6E2_CEREMONI_UAFKLARET` / `T6E2_CEREMONI_INGEN_OK` | ukendt | `maal` før alt andet |
| `T6E2_EFTER_DATA*` / `T6E2_ETK_OK` / `T6E2_ETK_LINJER` | committet, tallene passer ikke | `fortryd` (bruger rå fase) |
| `T6E2_EFTER_DATA_CS` / `T6E2_EFTER_DATA_VINDUE` / `T6E2_VINDUE_CS` | committet; der er fremmede change_sets eller rækker uden for ceremoniens tabeller efter data-dumpet | afklar med `afvigende.txt` (kun navne); en `fortryd` ville slette dem og stopper selv |
| `T6E2_VINDUE_BRUDT_FOER_DDL` | intet kørt | noget er skrevet siden dumpet (`afvigende.txt`: kun navne); afklar, `dump` igen, ny GO |
| `T6E2_VINDUE_BRUDT_FOER_DATA` | intet kørt | som ovenfor; `dump` igen (GO-data binder ikke dumpet, så samme GO gælder) |
| `T6E2_VINDUE_BRUDT` (fortryd) | intet restoret, ingen markør | en restore ville slette skrivninger efter dumpet; projektejeren afgør |
| `T6E2_FORTRYD_CS_IKKE_CEREMONIENS` | intet restoret, ingen markør | change_sets siden dumpet, som ikke er ceremoniens revalideringer |
| `T6E2_FORTRYD_DDL_KATALOG` / `…_SIDEKORT` / `…_TOM_ETIKET` / `…_TILSTAND` | intet rørt | kataloget rummer andet end DDL'ens objekter, eller data er ikke fortrudt |
| `T6E2_FORTRYD_DDL_ACL` / `…_DEFAULT_ACL` / `…_KATALOG_EFTER` / `T6E2_EFTER_FORTRYD_DDL` | fortryd-ddl er **committet** | beviset holdt ikke: se mappen; nødudgangen nedenfor |
| `T6E2_FORTRYD_DDL_VINDUE` | fortryd-ddl er **committet**; katalog, ACL og fase er som foer-dumpet, men rækker afviger | undersøg `afvigende.txt` (skrivninger efter dumpet); **ingen restore** |
| `T6E2_FORTRYD_DDL_NOTIFY` / `T6E2_FORTRYD_NOTIFY` | fortrydelsen er **committet**, PostgREST har ikke fået `reload schema` | send `NOTIFY pgrst, 'reload schema'` manuelt; derefter `maal` |
| `T6E2_FORTRYD_RESTORE_FEJL` / `T6E2_FORTRYD_RLS` / øvrige stop efter markøren | data-restoren er påbegyndt; markøren står | gennemfør med samme dump; markøren flyttes manuelt efter `maal` |
| `T6E2_FORTRYD_IGANG` | en data-fortrydelse er påbegyndt (markøren står) | blokerer alle skrivende handlinger, også en ny `fortryd`, `fortryd-ddl`, `apply-*` og `go-*`; kun `maal`, `anon` og `vindue` kører. Gennemfør med samme dump; markøren flyttes manuelt efter `maal` |

## Fortrydelse

**Web (Del B):** redeploy af forrige build i Vercel. Klienten tåler både før og efter DDL, så web kan fortrydes
uafhængigt af DB.

**Data** (fase data → ddl): `koer.zsh --saet DAA_T6E2_DUMP=<kvittering for data-dumpet>` (normalt allerede gemt af
`dump` i trin 9), så `koer.zsh 40-trin6e2.sh go-fortryd` → projektejeren `fortryd --jeg-mener-det --go <kode>`.
- Kræver, at alle change_sets efter dumpet er ceremoniens: `narrative_record_revalidated`, én `created_at`, præcis 561
  stk., aktøren er ceremoniens. Med 0 change_sets kræves fase data (ellers er der intet at fortryde).
- Kræver, at kataloget er uændret siden data-dumpet.
- Derefter: restore af data-dumpet (`--clean --if-exists`, `private`+`public`), skema-default-ACL, `ANALYZE`,
  `db-rls.sql` (uændret = prods) og grant-afstemning mod dumpets.
- Efter: ACL, default-ACL, katalog og restore-hash som dumpet, fase ddl, andre kilders koordinater uændrede
  (`T6E2_FORTRYD_OK`).

**DDL** (fase ddl → foer; kun efter data er fortrudt): `koer.zsh 40-trin6e2.sh go-fortryd-ddl` → projektejeren
`fortryd-ddl --jeg-mener-det --go <kode>`. Ingen restore. I stedet køres snapshottet fra `apply-ddl` (gemt i
`~/.private/5ab-overfoersel/prod/6e2/fortryd-ddl-<stamp>/`, GO-bundet sammen med foer-dumpets kvittering) i ÉN
transaktion:
- `DROP CONSTRAINT source_sidekort_gyldigt` og `DROP COLUMN sidekort`;
- den gamle CHECK genskabes fra `pg_get_constraintdef`;
- den nye koordinat-RPC droppes, og de 4 ændrede funktioner genskabes fra `pg_get_functiondef`;
- deres grants sættes som før;
- de 8 nye funktioner droppes.

Vagter før: fase ddl, intet sidekort i nogen kilde, ingen tom `record_label` (`btrim(record_label)=''`), og kataloget afviger fra foer-dumpet i
præcis DDL'ens 15 objekter. Bevis efter: katalog (P) og ACL (P+L) som foer-dumpet (grants afstemmes som
sikkerhedsnet), `maal` fase foer, vinduet som foer-dumpet. Øvet på en t6e2_-kopi af stand-in'en 13/11: katalog P, ACL P
og vinduet byte-ens efter, `maal` fase foer.

Hvorfor ikke 6d-1's vej (drop + restore af foer-dumpet):
- DDL'en ændrer ingen rækker.
- Restoren er ikke atomisk, sletter skrivninger efter dumpet og har kendte fejlklasser.
- CHECK'en på `public.source` afhænger af den nye `private.sidekort_gyldigt`, så 6d-1's »drop nye funktioner før
  restoren« stopper.
- `db-rls.sql` er uændret siden grenens base, så ingen ældre version skal genanvendes.

**Nødudgang** (kun hvis `fortryd-ddl` ikke kan gennemføres), manuelt under frys, i samme rækkefølge som runnerens
`fortryd`:
1. `ALTER TABLE public.source DROP CONSTRAINT source_sidekort_gyldigt` (først, ellers kan `sidekort_gyldigt` ikke
   droppes).
2. Drop de 8 nye funktioner.
3. Skema-default-ACL ryddes for forbindelsens rolle i `public`/`private` før restoren (lib's `apply_schema_default_acl`
   med `-` som mål), så restoren ikke giver anon/authenticated rettigheder via default privileges.
4. `pg_restore --clean --if-exists --no-owner --schema=private --schema=public` af foer-dumpet; fejllisten vurderes
   (kun de kendte `current_rolle`/`media_object_synlig_anon`-linjer).
5. Skema-default-ACL genskabes fra foer-dumpets `acl.txt` (`apply_schema_default_acl` med `acl.txt` som mål).
6. `ANALYZE` (med `statement_timeout='15min'`).
7. `db-rls.sql` i én transaktion.
8. Grant-afstemning mod foer-dumpets `acl.txt` (`reconcile_grants`).
9. `NOTIFY pgrst, 'reload schema'`.
10. Kontrol: ACL (P+L), katalog P og restore-hash som foer-dumpet, `maal` fase foer.

**Stand-in-artefakt:** en stand-in uden `$USER`'s globale default-ACL (`ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON
FUNCTIONS FROM PUBLIC`) får rækken af DDL'ens `db-rls.sql`. Så stopper `fortryd-ddl` på `T6E2_FORTRYD_DDL_DEFAULT_ACL`.
Prod har rækken for `postgres` i forvejen. Stand-in'en `…_6e2` har `postgres`' række, men mangler `$USER`'s (målt
13/11). Generalprøven sætter derfor rækken eksplicit som `$USER` på sin kopi og bekræfter den i ACL-fingeraftrykket
(`L|d|<user>|-|f|<user>|EXECUTE`), før foer-dumpet tages.

## Ændring i historiske scripts

Task 3 ændrede DDL-markøren i 6d-1's historiske `placement_ceremoni.sql` og `maal_trin6d1.sql`
(`'printed_number IS NULL'` → `'count(DISTINCT (d.scheme_entry_id,'`, commit `d8429081`). Det var nødvendigt, for 6e-2
fjernede NULL-filteret i koordinat-RPC'ens kildegate, og CI kører 6d-1's tests mod det nye skema. Den version, der blev
kørt i prod 9/11, ligger i git (`git show d8429081^:.claude/skills/daa-extract/scripts/placement_ceremoni.sql`). Det
noteres også i changelog.

## De 2 oversprungne staged

Af kildens 563 publicerede bindinger med `record-`-etiket tilhører 2 staged personer uden placement. Revalideringen
afviser dem (`POLICY_BLOCKED`). Ceremonien springer dem over efter 6d-1's præcedens (`placement_ceremoni.sql:539-541`)
og tæller dem som `sprunget=2`. Efterbetingelsen kræver dem byte-ens (etiketter, seneste hændelse, publiceringsstatus).
De beholder record-etiket og PDF-side, indtil de bliver offentlige. Backlog: de får etiket, når de bliver offentlige.
Afgørelse A (Task 9, 13/11) skal stå i `docs/decisions.md` under 2026-11-13; posten skrives sammen med færdigbeviset,
hvis den ikke allerede er der. Færdigbevisets tal er derfor 561 genpublicerede (heraf 33 tomme) og 2 sprunget, ikke
spec §8's 563/35.

## Browsertjek (som anon mod prod; spec §8 + §12.4)

Efter trin 13. På hver tjekket side: ingen `record-` eller `legacy-source:` i DOM'en.

- **Conrad 1198** (1939, ingen placement): »DAA 1939, s. 52« (PDF 541). Bundne fakta viser s. 52-53.
- **Conrad 392** (V-1):
  - åbner på V-1 med 2018-20's fakta;
  - navn, født, titel og død vises én gang hver;
  - »✓ også i DAA 1939« ved født, titel og død;
  - tryk på 1939 viser 1939's fakta med »DAA 1939, s. 52« og 2018-20 som note;
  - »Kilde i Aarbogen« viser »V. Den grevelige linje af 1673, nr. 1«.
- **1093 → 149** (placeret, sammenfoldet 1939-person):
  - 1939-visningen har etiket og linje fra placement;
  - »Kilde i Aarbogen« viser »II. Linjen Gallentin, s. 36, nr. 3«;
  - B6 viser »✓ også i DAA 1939 (II. Linjen Gallentin)«.
- **Linjenavne:** III lyder »… Ziesendorf.« i læseren. Stammeafsnittene hedder »A. Den holstenske Linje.« og »B. Den
  ældre meklenborgske Linje.«. »Kilde i Aarbogen« viser linjens navn for begge udgaver.
- **Ingen 1939-side over 92** i DOM'en (Task 8: højeste viste 1939-side er 90).
- **En 1939-person uden 2018-20-modpart:** ingen vælger, 1939's fakta og læsbar etiket.
- **Uenighed og konflikt:** en reel uenighed viser »… skriver: …«; konfliktkomponenten 137↔937 viser »placerer i«.
- **Stikprøve:** 5 placerede 1939-personer slået op i bogen på den viste side og det viste nr.
- **Tal (fra runneren):**
  - koordinat-RPC'en som anon ≤ 0,6 s pr. kald (`anon`, trin 13b);
  - Conrads biografikald (392) inden for 209-487 ms;
  - andre kilders koordinater og etiketter byte-ens (`ETK_OK` og `maal`);
  - `stale_published` 0.

## Generalprøven 13/11

Kørt af controlleren fra operatørens cwd på `daa5ab_ddl_standin_20261113150400_g1` med `statement_timeout='2min'`
(efter at `koer.zsh`-reglen var udvidet):
- go-ddl → maal → anon → dump → apply-ddl → maal ddl → dump → go-data → apply-data (`ETK_OK` 561/33/2) → maal data →
  vindue → anon;
- data-`fortryd` → `T6E2_FORTRYD_OK` (`restore_fejl=5`), `fortryd-ddl` → `T6E2_FORTRYD_DDL_OK`, `maal` fase foer;
- `M[ddl]` og `M[data]` fastlåst fra kørslen; tider og anon under »Tid« ovenfor.

Negativer, der stoppede som forventet: manglende flag, forkert GO (`GO_MISMATCH`), ændret json efter GO
(`T6E2_FIL_SHA`) og gentaget data (`T6E2_DATA_FAERDIG`).

Efter generalprøven fik runneren review-rettelserne (sha-tjekkede kopier af de eksekverede filer, katalogvagt før DDL,
change_set- og vinduesvagt efter data og i `vindue`, data-`fortryd` kræver ceremoniens 561 eller fase data). `maal` på
`…_g1` (fase data) gav derefter `T6E2_MAAL_OK tilstand=data`.

Negativer:
- forkert GO (`GO_MISMATCH`);
- manglende flag;
- gentaget `apply-data` (`T6E2_DATA_FAERDIG`);
- ændret json efter GO (`T6E2_FIL_SHA`/`GO_MISMATCH`);
- vinduesvagten: et bogmærke efter data-dumpet → `fortryd` stopper med `T6E2_VINDUE_BRUDT`.

Til sidst `fortryd` → `fortryd-ddl` → fuld ren kørsel med alle værdier fastlåst.
