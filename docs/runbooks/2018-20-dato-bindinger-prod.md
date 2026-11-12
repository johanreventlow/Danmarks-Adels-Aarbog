# Runbook — 2018-20's fødsler og dødsfald bundet til bogens post (tre ceremonier)

Spec: `docs/superpowers/specs/2026-11-12-2018-20-dato-bindinger-design.md` (§4, §6, §7). Plan:
`docs/superpowers/plans/2026-11-12-2018-20-dato-bindinger.md` Task 5-6. Forbilleder: `docs/runbooks/trin6c2-prod.md`
(ceremoni 3a og 4) og 6d-3's vinduesvagt.

Kort sagt: efter de tre ceremonier viser læseren »DAA 2018-20, s. N · <post>« ved 334 fødsler (i dag 67) og 330
dødsfald (i dag 88). Det sker kun for de 509 forslag, der efter markørfjernelsen er lig databasens påstand, og kun efter
projektejerens stikprøve på 20. De 59 SKRIVEMAADE og 15 NO_FACT står `proposed` uden afgørelse. Ingen gyldig binding fra
før går tabt; det kontrolleres som en nøglet liste.

| Ceremoni | Hvad | Skriver |
|---|---|---|
| `ddl` | Blok `-- ===== dato-markoer-v2: markør pr. prædikat =====` + `db-rls.sql` i **én** transaktion | DDL: ny regelfunktion, `red_normaliser_forslag` udvidet med v2 |
| `n` | `red_normaliser_forslag(…, 'dato-markoer-v2')` på den bundne kandidatliste (565) | nye forslagsversioner (kilde 1) |
| `k` | Kontrolværktøjet v2 med `--predikater person.birth,person.death --kun-stikproeve`: kort (kun stikprøven) → svar → flet → GO → afgørelser og bindinger → uafhængig verify | 509 afgørelser + 509 bindinger |

Runneren er privat: `~/.private/5ab-overfoersel/38-dato-bindinger.sh` med `38-dato-vindue.sql`, 5c-2's `lib.zsh`,
`koer.zsh` og `rollback-preflight.sql`. Projektejeren kører alt, der rører prod, fra egen shell. AI-sessionen læser kun
linjer med tal, koder og hashes. Kortsiden (posttekst, også om levende personer) åbnes kun af projektejeren.

## Forudsætninger

- `main` er checket ud rent i `/Users/johanreventlow/TypeScript/danmarksadelsaarbog` (i prod bruger `lib.zsh` altid
  den mappe). Koden er på `main` fra PR #322 (`743787f3`). GO-koderne binder commit'en og de bundne repo-filer
  (`db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, målingen, kandidat-SQL'en, kontrollens SQL og værktøjer,
  kortværktøjet, fingeraftrykkene). Hovedmappen deles med andre sessioner: tjek `git status` og `git branch
  --show-current` før hver GO (memory »shared-workdir branch-race«).
- Runneren har fastlåst blokkens og `db-rls.sql`'s sha (`DATO_BLOK` `a030a85f…`, `DATO_RLS` `a21d5034…`), kandidat-
  listen (565, `NORM_SHA` `f1e6d2e3…`), målingens tal i alle fire tilstande og de tabelsæt, ceremonierne må ændre
  (`VINDUE_N`, `VINDUE_K`). I prod stopper runneren med `DATO_IKKE_FASTLAAST`, hvis en værdi mangler. Ændres en bundet
  fil efter øvelsen (fx efter Codex' diffreview), tømmes den berørte pin, og øvelsen køres igen på en frisk stand-in.
- **Forbindelsens rolle** er Supabase's `postgres` via Session pooleren (`~/.Renviron`). Den skal eje alt i
  private+public (fortrydelsen) og især `private.interpretation` og `private.interpretation_promotion` (ceremoni `k` kører
  `ANALYZE` på dem; `DATO_EJER` tjekker det læse-kun).
- `DAA_EXPECTED_TARGET` står i `prod/go-env.txt`. Aktøren læses fra `b2/aktoer.txt` (0600, sha'en tjekkes) og printes
  aldrig. age-nøglen (`~/.private/age/daa-dump.key`) og SFTP-miljøet (`~/.private/sftp-dump.env`) som ved 6c-2.
- **Ingen redigering i prod fra hvert dump til dets ceremoni, og fra ceremonien til den er godkendt.** Vinduesvagten
  håndhæver det: dumpet tager et rækkeaftryk af alle tabeller i public/private (`38-dato-vindue.sql`: tabel, antal,
  sha). `apply-*` kræver basens rækker lig dumpets aftryk. Lige efter hver skrivning tages et nyt aftryk, som kun må
  afvige i ceremoniens målte tabeller; ellers bliver markøren `skridt-<dump>.igang` stående, og `fortryd` stopper (så en
  restore aldrig sletter fx en læsers bogmærke). Sekvenser sammenlignes ikke.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 38-dato-bindinger.sh …`. `koer.zsh` gemmer
runnerens `DAA_`-linjer (`DAA_DATO_DUMP`, `DAA_DATO_KONTROL`) i `prod/go-env.txt`; den seneste linje vinder. Skrivende
handlinger kræver `--jeg-mener-det --go <kode>`. Hver GO-kode binder ceremoniens navn, målet, commit'en og filerne.

Målingen (`maal_dato_bindinger.sql`) afgør tilstanden efter basens indhold: `foer` (ingen v2-funktion), `ddl`
(funktionen findes, ingen v2-række i kilde 1), `n` (v2-versioner, ingen accepteret) og `k`. Tallene skal desuden være
de fastlåste; ellers er tilstanden `ukendt` (`MAAL_DATO_UKENDT`), og intet skrivende kører.

### 0. Udgangspunkt

1. `maal` → `DATO_MAAL_OK tilstand=foer`, tal `0,0,0,568,15,0,0,67,88,1759`, bindingshash `fa08bb8a…`. **Notér
   sekunderne**: målingen kalder `public_person_facts` for alle personer og er umålt i prod (stand-in: 6 s).
2. `vejb` → `DATO_VEJB_OK tilstand=foer … stoerste_median_ms=…` og `DATO_VEJB_KOLD_OK` (før-tallet i prod).

### Ceremoni `ddl`

1. `dump` → `DUMP_DATO_OK tilstand=foer …`, `EKSTERN_DATO_OK … rundtur=ok`, `DUMP_DATO_MAAL_OK … vindue=…`,
   `DAA_DATO_DUMP=…`.
2. `go-ddl` → `GO_DATO_DDL_KODE=<8 hex>`. Projektejeren skriver `GO dato-ddl <kode>`.
3. `apply-ddl --jeg-mener-det --go <kode>`: vinduet mod dumpet; writerens definition og ACL gemmes i
   `prod/dato/fortryd-ddl-<stempel>/` (fortrydelsens mål); blok + `db-rls.sql` i én transaktion med `lock_timeout` 5 s;
   `NOTIFY pgrst`; målingen skal give `ddl`; `db-verify.sql`'s v2-blok køres læse-kun (`OK: dato-markoer-v2`); vinduet
   igen (DDL'en ændrer ingen rækker). → `DATO_APPLY_DDL_OK tilstand=ddl blok=a030a85f… verify=ok`.
4. Security Advisor (`get_advisors`), memory »kør get_advisors efter DDL«.

### Ceremoni `n` (dato-markoer-v2)

1. `dump` → `tilstand=ddl`.
2. `forbered-n` → `DATO_FORBERED_N_OK T6C2_NORMALISER antal=565 kandidater_sha256=f1e6d2e3…`. Afviger antal eller sha,
   stopper runneren (`DATO_NORM_ANTAL`/`DATO_NORM_SHA`): listen er ikke øvelsens; stop og forklar.
3. `go-n` → `GO dato-n <kode>`.
4. `apply-n --jeg-mener-det --go <kode>`: vinduet mod ddl-dumpet; én transaktion: regel og kilde sættes, listen
   genberegnes og skal være GO-listen (`NORMALISER_GO_DRIFT`), én `extraction_run`, 565 × `red_normaliser_forslag` med
   nulstillet ændringssæt, efterkontrol. Aftrykket efter må kun afvige i `private.extraction_run`,
   `private.interpretation` og `private.interpretation_observation`.
   → `DATO_APPLY_N_OK tilstand=n versioner=565 tal=565,509,0,59,15,0,0,67,88,1759`.

### Ceremoni `k` (kontrol v2, kun stikprøven)

Dumpet tages **efter** svarene (skridt 4): det er fortrydelsens mål for `apply-k`, og `apply-*` kræver et dump, der højst
er 12 timer gammelt.

1. `kort` (læse-kun; tilstand `n`; ejer-tjek) → kontrolmappen `prod/dato/kontrol-<stempel>/`: klassifikation og
   rækkeeksport (kildescope 1), planen (`--predikater person.birth,person.death --kun-stikproeve --strata-ubekraeftet 0
   --strata-oevrige 20`; alle 2018-20-personas har tom identitets-outcome, så hele stikprøven er »øvrige«), konteksten og
   kortsiden. → `DATO_KORT_OK personas=18 sider=1 …` og `PLAN_V2_OK … stikprøve=20 … maskinkandidater=489 ark_felter=20
   personas=18 praedikater=person.birth,person.death udeladt=59` (runneren kræver stikprøve, maskinkandidater,
   ark_felter, udeladt og prædikaterne præcis), `DAA_DATO_KONTROL=…`.
   Stikprøven trækkes efter versions-id'erne, som `apply-n` opretter tilfældigt; prods 18 personas er derfor ikke
   øvelsens, og antallet kan variere lidt (runneren låser kun 20/489/20/59).
2. **Projektejeren** åbner `kort/kort-1.html`, svarer `-` for hver persona og `B` (eller `D`/`V`) for hvert af de 20
   felter og gemmer svarfilen (JSON). Ét svar, der ikke er `B`, stopper ceremonien allerede ved `go-k`
   (`DATO_GEN_SQL (SAMPLE_FAILED)`); intet skrives (spec §4.2 pkt. 4).
3. `flet <svar.json>` → `DATO_FLET_OK svar=1 ark_sha256=… linjer=61`. Arket kan kun flettes én gang pr. kontrolmappe.
4. `dump` → `tilstand=n` (bindingslisten gemmes i dumpets målmappe; den er grundlaget for den nøglede sammenligning).
5. `go-k` genererer ceremoniens SQL og verify fra plan + ark og binder kontrolmappens filer → `GO dato-k <kode>`.
6. `apply-k --jeg-mener-det --go <kode>`: vinduet mod n-dumpet; ejer-tjek; SQL'en genereres igen og skal være byte-ens
   med den bundne; ceremonien med `statement_timeout` 30 min; aftrykket efter må kun afvige i `private.interpretation`,
   `private.interpretation_observation`, `private.interpretation_promotion` og `private.interpretation_promotion_batch`;
   verify læse-kun (`udeladt_proposed=59` kræves); målingen med bindingslisten: ingen binding fra n-dumpet tabt, præcis
   509 nye. → `DATO_APPLY_K_OK unresolved=0 rettelser=0 afgoerelser=0 stikproeve=20 maskine=489 bundet=509
   verify=bundet=509 p_personas=0 udeladt_proposed=59 bindinger=tabt:0,nye:509 tal=565,0,0,59,15,509,509,334,330,2268`.
7. `verify` → `DATO_VERIFY_OK … bindinger=tabt:0,nye:509` (kan gentages; læse-kun).
8. `vejb` → median ≤ 1.000 ms for hver af de 10 tungeste og 0 kolde timeouts (`DATO_VEJB_KOLD_OK`). Over grænsen:
   stop og `fortryd` med n-dumpet (spec §6).
9. Læsertjek som `anon` (spec §7, plan Task 6 step 3) og status (plan Task 6 step 4).

## Varighed og prods tidsgrænse

Prods `statement_timeout` er 2 min for login-rollen og 3 s for `anon`. Runneren sætter `statement_timeout='30min'` på
sessionen for målingen, eksporterne, ceremonierne og verify. Stand-in-tal fra øvelsen 2026-11-12
(`…_20261112154600_dato`, prod-dump b9a0503d, ICU, prods timeouts, `ANALYZE`); skønnene bruger 6c-2's faktorer (27× for
små RPC-kald, 3× for store læsninger, ~20× for alt, der binder pr. række) og er usikre. Stand-in-tid er ikke prod-tid.

| Skridt | Stand-in | Skøn i prod |
|---|---|---|
| `maal` (`foer`-`n` / `k`) | 5,8-6,4 s / 7,3 s | umålt; under 5 min (måles i skridt 0) |
| `vejb` (5 kald × 10 personer; median, største) | 219 ms (`foer`), 286 ms (`k`) | kriterium ≤ 1.000 ms |
| `dump` inkl. mål (vindue, restore-hash, katalog, ACL) | 27 s | dump ca. 2,5 min + mål |
| `apply-ddl` (blok) / `fortryd-ddl` | 0,1 s / 6-8 s inkl. mål | sekunder (6d-2a's DDL: 25 s) |
| `forbered-n` / `apply-n` (565 RPC-kald) | ikke timet (få sekunder) / 0,4 s (21 s inkl. vagter) | ≤ 1 min / ca. 15 s + vagter |
| `kort`: eksporter / kontekst | 43-46 s / 0,5 s | **2-15 min** / ≤ 10 s |
| `apply-k`: ceremonien / verify / i alt | 27 s / 12 s / 62 s | ca. 5-10 min / 2-4 min (enkeltsætninger kan overstige 2 min; derfor 30 min) |
| `fortryd`: restore / efterarbejde | 3,3-3,7 s / 14 s | minutter |

## Stoppunkter

Alle `STOPPORT:`-linjer stopper uden at skrive yderligere. Hvor langt man er nået, læses af `maal`.

| Hvor | Tilstand bagefter | Gør |
|---|---|---|
| Før en skrivning (`GO_MISMATCH`, `DUMP_DATO_MANGLER`, `DUMP_DATO_TILSTAND`, `DUMP_DATO_FOR_GAMMELT`, `B1_EKSTERN_*`, `DATO_FOER_*`, `DATO_VINDUE_BRUDT_FOER_*`, `DATO_BLOK`, `DATO_RLS`, `DATO_EJER`, `DATO_N_KOERT`, `DATO_K_KOERT`) | uændret; intet skrevet | Ret årsagen (nyt `dump` i rette tilstand, ny GO, hvis filer er ændret) og kør skridtet igen. `DATO_VINDUE_BRUDT_FOER_*` betyder, at prod er skrevet siden dumpet: tag dumpet igen |
| `DATO_IKKE_FASTLAAST`, `MAAL_DATO_UKENDT` | uændret | Runneren mangler en øvet værdi, eller prods tal er ikke stand-in'ens. Ingen prod-kørsel; find forskellen (fx en redaktørs afgørelse i kilde 1 siden 12/11) og øv igen på en frisk stand-in |
| I en ceremonis transaktion (`DDL_DATO fejlede`, `CEREMONI_N/K fejlede`; koden står i linjen, fx `NORMALISER_GO_DRIFT`, `MACHINE_NOT_MATCH`, `PLAN_KILDE_AFVIGER`) | rullet tilbage; runneren har kontrolleret, at rækkerne er dumpets, og fjernet markøren | Basen har ændret sig siden GO, eller arket afviser. Ny `forbered-n`/`kort` og ny GO |
| `DATO_FEJL_MED_AENDRINGER` | rullet tilbage, men rækker afviger fra dumpet; markøren står | Nogen har skrevet under ceremonien. Projektejeren afgør; ingen restore uden at fjerne markøren bevidst |
| `go-k`: `DATO_GEN_SQL (SAMPLE_FAILED)` | uændret | Et stikprøvesvar er ikke `B`. Spec §4.2 pkt. 4: del 1 stopper; projektejeren afgør, om der skal undersøges, før en ny `kort` |
| `forbered-n` (`DATO_NORM_*`), `kort` (`DATO_PLAN_*`, `DATO_KONTROL_EKSPORT_*`, `DATO_KORT_HTML`), `flet` (`DATO_FLET (<kode>)`, `DATO_ARK_FINDES`) | uændret; læse-kun | Ret og kør igen; nye svar kræver en ny `kort`. `DATO_PLAN_TAL` betyder, at klassifikationen ikke er øvelsens: stop og forklar |
| Efter commit: `DDL_DATO_NOTIFY` | DDL committet | Kør `maal`; står den i `ddl`: kør `NOTIFY pgrst, 'reload schema'` manuelt og fortsæt |
| Efter commit: `DATO_EFTER_*`, `DATO_EFTER_DDL_VERIFY`, `DATO_VERIFY_K`, `DATO_BINDINGER_TABT`, `DATO_BINDINGER_NYE` | ceremonien er committet | Kør `maal`. Forkerte tal, fejlende verify eller en tabt binding: **fortrydelsestilfælde** (nedenfor) |
| Efter commit: `DATO_FREMMED_SKRIVNING` | ceremonien er committet; aftrykket viser en skrivning uden for ceremoniens tabeller; markøren står | `fortryd` stopper (`DATO_MARKOER`), for en restore ville slette den fremmede skrivning. Projektejeren afgør (se »Fremmed skrivning« nedenfor) |
| `vejb` efter `k`: `VEJB_OVER_GRAENSEN` / `VEJB_KOLD_FEJL` | `k` er committet | Stop; `fortryd` med n-dumpet |
| `fortryd`: `DATO_MARKOER`, `DATO_FORTRYD_TILSTAND`, `DATO_VINDUE_BRUDT*`, `DATO_FORTRYD_FREMMEDE_AENDRINGER`, `DATO_FORTRYD_KATALOG_AENDRET`, `DATO_FORTRYD_LAAS`, `DATO_FORTRYD_EFTER_MANGLER` | uændret; ingen restore | Nogen har skrevet siden ceremonien, eller basen står ikke lige efter den. Projektejeren afgør |
| `fortryd`: `DATO_FORTRYD_RESTORE_FEJL` eller en efterkontrol (`DATO_FORTRYD_ACL`, `_KATALOG`, `_RESTORE_HASH`, `_VINDUE`, `DATO_EFTER_FORTRYD`) | restoren er kørt; markøren `fortryd-<dump>.igang` står | Alle handlinger ud over `maal`, `vejb` og `verify` er spærret. Undersøg `restore.err`; markøren flyttes kun efter projektejerens afgørelse |
| `fortryd-ddl`: `DATO_FORTRYD_DDL_TILSTAND`, `DATO_FORTRYD_DDL_V2_RAEKKER` | uændret | DDL'en fortrydes kun, når ingen kilde har en v2-række: fortryd `n` (og `k`) først |

`GO_MISMATCH` viser den kode, filerne svarer til nu. Brug den ikke uden at have tjekket, hvad der er ændret siden GO.

## Fortrydelse (spec §6)

- **`k` og `n`:** restore af dumpet, taget lige før ceremonien.
  1. `koer.zsh --saet DAA_DATO_DUMP=<kvittering>`, hvis det ikke er det seneste dump
     (`prod/dato/daa-prod-<stempel>-dato.dump.receipt.json`; `tilstand` står i kvitteringen).
  2. `go-fortryd` → GO-filen viser `fortryd dump_tilstand=<ddl|n> dump_sha256=…` → `GO dato-fortryd <kode>`.
  3. `fortryd --jeg-mener-det --go <kode>`: basen skal stå lige efter ceremonien (`ddl`→`n`, `n`→`k`), basens rækker skal
     være det godkendte aftryk efter ceremonien (`efter-<n|k>-<dump>.txt`), ingen markør, ingen fremmede `change_set`,
     ingen låse, kataloget som dumpets; vinduet igen lige før markøren; markøren sættes; skema-defaults ryddes;
     `pg_restore --clean --if-exists --no-owner` af private+public (de kendte fejl om `current_rolle()`/
     `media_object_synlig_anon(text)`); defaults genskabes; `ANALYZE`; `db-rls.sql`; grants afstemmes; `NOTIFY pgrst`;
     efterkontrol af grants, default-rettigheder, katalog, forældreløse rækker, restore-hash, rækkeaftryk og målingen
     (tilstand, tal og bindingshash som dumpets). → `DATO_FORTRYD_OK tilstand=<ddl|n> … acl=som_dump katalog=som_dump`.
  4. Kæden går baglæns (`k` → `n` → `ddl`), ét dump ad gangen; ceremonien kan derefter køres igen fra sit `dump`.
- **`ddl`:** `go-fortryd-ddl` → `GO dato-fortryd-ddl <kode>` → `fortryd-ddl --jeg-mener-det --go <kode>`. Kun i tilstand
  `ddl` og kun, når `private.interpretation` i **ingen** kilde har v2's method (tjekkes igen i transaktionen). Én
  transaktion: writerens gemte definition (`CREATE OR REPLACE` bevarer grants) og `DROP FUNCTION
  private.normaliser_dato_markoer_v2(text,text)`; `NOTIFY pgrst`; efterkontrol: tilstand `foer`, writerens definition
  byte-ens med snapshottet og ACL som snapshottets. Ingen restore. `db-rls.sql` er uændret af grenen, så den skal ikke
  rulles tilbage (memory »fortryd-DDL: db-rls før grenen«).

**Fremmed skrivning.** Står markøren efter `DATO_FREMMED_SKRIVNING`, er ceremonien committet, og en anden har skrevet
lige efter. Øvet genopretning (stand-in, 12/11): den fremmede skrivning fjernes eller accepteres efter projektejerens
afgørelse; derefter tages et nyt aftryk med `38-dato-vindue.sql` som `efter-k-<dump>.txt`, det kontrolleres, at det kun
afviger fra dumpets aftryk i `VINDUE_K`, og markøren fjernes. Først derefter kan `fortryd` køre. Accepteres skrivningen,
fortrydes ceremonien ikke ved restore (den ville slette skrivningen).

## Forventede tal

Fastlåst i runneren fra øvelsen 12/11 (stand-in'en er en kopi af prod, så tallene gælder prod, hvis kilde 1 ikke er
redigeret siden):

| Tilstand | versioner_v2 | match | real_diff | skrivemaade | no_fact | accepteret_v2 | bundet_v2 | post_foedsel | post_doed | alle_bindinger |
|---|---|---|---|---|---|---|---|---|---|---|
| `foer`, `ddl` | 0 | 0 | 0 | 568 | 15 | 0 | 0 | 67 | 88 | 1.759 |
| `n` | 565 | 509 | 0 | 59 | 15 | 0 | 0 | 67 | 88 | 1.759 |
| `k` | 565 | 0 | 0 | 59 | 15 | 509 | 509 | 334 | 330 | 2.268 |

Bindingshash `fa08bb8ae9828f4e1eab562f496cd06b673a4de42ae78b946522ccc62f41809d` i `foer`, `ddl` og `n`;
`c4ef58dead05447e91ed4f22e900f5bea74bcced920cdbb2b5a3bf57c80cf534` i `k` (afhænger ikke af stikprøven: alle 509
bindes). Kandidatlisten: 565, sha `f1e6d2e3…`. `match` i `foer` er 0, fordi alle forslag bærer markøren; i `k` er 0,
fordi de accepterede versioner ikke længere er forslag.

## Øvelse (2026-11-12, plan Task 5)

Stand-in `daa5ab_ddl_standin_20261112154600_dato` (prod-dump 12/11 b9a0503d), runneren mod worktree'et på `e800aed8`
(= koden på `main` i `743787f3`; de bundne filer er uændrede ved merge'en).

- Hele forløbet: `maal` → `vejb` → `dump foer` → `apply-ddl` → `fortryd-ddl` (tilstand `foer`, writer og ACL som
  snapshottet) → `apply-ddl` igen → `dump ddl` → `forbered-n` (565) → `apply-n` → `kort` → `flet` → `dump n` → `apply-k`
  → `verify` → `vejb` (286 ms) → `fortryd` (k → n, bindingshash som før) → `fortryd` (n → ddl) → `fortryd-ddl` → `foer`
  med samme tal og hash som udgangspunktet. Svarene var syntetiske (`oev-svar alle-b`: `-` på alle personas, `B` på
  alle 20 felter, bygget af planens id'er uden at læse værdier); kortsiden blev ikke åbnet.
- Negative prøver: en redaktørafgørelse på én kandidat mellem GO og apply (`DAA_DATO_TEST_DRIFT=1`) →
  `NORMALISER_GO_DRIFT`, rullet tilbage, rækkerne dumpets, markøren fjernet. Et `D` i stikprøven → `go-k` stopper med
  `SAMPLE_FAILED`, intet skrevet. `fortryd-ddl` i tilstand `n` → `DATO_FORTRYD_DDL_TILSTAND`. Et bogmærke indsat mellem
  `apply-k`'s commit og aftrykket (`DAA_DATO_TEST_FREMMED=k`) → `DATO_FREMMED_SKRIVNING (… public.bookmark …)`, markøren
  står, og både `go-fortryd` og `fortryd` stopper med `DATO_MARKOER`; genopretningen ovenfor øvet, derefter `fortryd`.
- Fund under øvelsen: `SAMPLE_FAILED` kommer allerede ved `go-k` (SQL-genereringen afviser arket), ikke i ceremonien.
  Kortets rækkeeksport tager 43-46 s lokalt for kilde 1 (6c-2's kilde 3: 4 s); den er det langsomste læsetrin.

## Efter ceremonierne

- Browsertjek som `anon` (spec §7): Conrad (392) med fødsel og død med post, en person med en bundet dødsdato, en person
  i resten, og 0 `record-`/`legacy-source:`.
- `docs/evidensbaseret-genimport/status.md` (2018-20's promotion og B11-rækken), `docs/database-current-state.md` (nyt
  afsnit med prod-tider), `docs/changelog.md` og færdigbeviset `docs/evidensbaseret-genimport/dato-bindinger-2018-20-prod.md`.
- Notér prod-tiderne for `maal`, `kort`, `apply-k` og verify her, så senere skøn bygger på dem.
- Spørg projektejeren, om del 2 (kort over de 59 SKRIVEMAADE) skal køres.
