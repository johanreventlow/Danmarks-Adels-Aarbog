# Runbook — trin 6c-2 i prod: 1939's fakta bundet til bogen (fire ceremonier)

Spec: `docs/superpowers/specs/2026-11-02-trin6c2-1939-bundet-til-bogen-design.md` (§4.1-§4.4, §6, §7). Plan:
`docs/superpowers/plans/2026-11-02-trin6c2-1939-bundet-til-bogen.md` Task 11-14.

Kort sagt: efter de fire ceremonier viser læseren 1939's fakta bundet til bogens post. Det sker kun, hvor
projektejeren eller maskinens kontrol har afgjort forslaget, og kun gennem påstande, der står i bogen. 2018-20's
bindinger røres ikke (`k1_bindinger_hash` er den samme før og efter hver ceremoni).

| Ceremoni | Hvad | Skriver |
|---|---|---|
| 1 | Blok `-- ===== trin 6c-2a: set-baseret bindingstjek (vej B) =====`: `public_person_facts` tjekker bindinger set-baseret | DDL (3 funktioner), additiv |
| 2 | Blok `-- ===== trin 6c-2b: forslagsversion, påstandsrettelse, én binding pr. påstand =====` + `db-rls.sql` + kort 122 i **én** transaktion | DDL + én identitetsversion |
| 3a | `red_normaliser_forslag` (regel `dato-markoer-v1`) på den bundne kandidatliste | nye forslagsversioner |
| 3b | `red_ret_paastand(…, 'linjeskift-v1', …)` på den bundne liste (kan først beregnes efter 3a) | påstandsrettelser |
| 4 | Kontrolværktøjet v2: kort → projektejerens svar → flet → GO → afgørelser, rettelser og bindinger → uafhængig verify | afgørelser + promotions |

Kort 122 (6c-1 C's F, persona `589f8292-4903-5072-9723-ca13312708d1`) står allerede som `unresolved` (version 1) fra 6c-1
C. Ceremoni 2 tilføjer kun noten `ønsket_person_id=1054; grund=…` (version 2) med C's kortkvittering (ark-5, linje 27),
så overleveringen til 6d ligger i basen. GO-filen for ceremoni 2 indeholder linjen
`kort122 persona=… expected_version=1 oensket_person_id=1054 linje=27`; **projektejerens GO for ceremoni 2 er
bekræftelsen af 1054**.

Runneren er privat: `~/.private/5ab-overfoersel/29-trin6c2.sh` med 5c-2's `lib.zsh`, `koer.zsh` og
`rollback-preflight.sql`. Projektejeren kører alt, der rører prod, fra egen shell. AI-sessionen læser kun linjer med
tal, koder og hashes; kortsiderne (posttekst) åbnes kun af projektejeren.

## Forudsætninger

- PR 1 og PR 2 er merget, og `main` er checket ud rent i `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`. GO-
  koderne binder commit'en og de bundne repo-filer (`db-migrations.sql`, `db-rls.sql`, målingen, kontrollens SQL og
  værktøjer, kandidat-SQL'en, fingeraftrykkene og vej B's frosne reference).
- **Slutøvelsen på `main`** (merge-commit'en, ikke grenens head) er gennemført med den runner, der skal bruges. Den
  fastlåser blokkenes og `db-rls.sql`'s sha i runneren (`T6C2_BLOK_A`, `T6C2_BLOK_B`, `T6C2_RLS`). I prod stopper
  runneren med `T6C2_IKKE_FASTLAAST`, hvis en fastlåst værdi mangler.
- **Forbindelsens rolle** er Supabase's `postgres` via Session pooleren (`~/.Renviron`). Den skal eje alt i
  private+public (`RESTORE_PRIVILEGES`, fortrydelsen) og især `private.interpretation` og
  `private.interpretation_promotion`. Ceremoni 4 kører `ANALYZE` på dem efter sine egne skrivninger, og `ANALYZE` på en
  tabel, rollen ikke ejer, springer lydløst over (kun en advarsel). Uden statistik tager bindingstællingen over 2 min
  (T10). `kort` og `apply-4` tjekker ejerskabet læse-kun (`T6C2_EJER`), og ceremoniens SQL stopper selv med
  `CONTROL_V2_ANALYZE_IKKE_EJER`.
- `DAA_EXPECTED_TARGET` (prods målidentitet) står i `prod/go-env.txt` som ved 6c-1. Aktøren læses fra `b2/aktoer.txt`
  (0600, sha'en tjekkes); den printes aldrig.
- age-nøglen (`~/.private/age/daa-dump.key`) og SFTP-miljøet (`~/.private/sftp-dump.env`) som ved 6a-6c-1.
- `~/.private/6c2/vejb-personer.txt`: de 10 tungeste personer (T10 step 1), ét id pr. linje.
- **Ingen redigering i prod fra hvert dump til dets ceremoni, og fra ceremonien til den er godkendt** (så længe en
  fortrydelse ved restore kan komme på tale). Hvert dump binder `max(change_set.id)`; `apply-*` stopper med
  `DUMP_6C2_SKREVET_SIDEN`, hvis der er skrevet siden, og `fortryd` nægter restore, hvis andre end ceremoniens aktør har
  skrevet (`T6C2_FORTRYD_FREMMEDE_AENDRINGER`). Mellem ceremoni 3b og ceremoni 4's dump (mens projektejeren besvarer
  kortene, evt. i dagevis) er der ingen pause; ceremoni 4's egne værn (`MACHINE_NOT_MATCH`, versionsdrift, SQL'en
  genereret byte-ens) fanger en mellemliggende skrivning.
- **Slutøvelsen på `main`** køres gennem `koer.zsh` (stand-in: `DAA_ENV_FILE=<fil>`), så `DAA_T6C2_DUMP`/
  `DAA_T6C2_KONTROL` går gennem dens linjefangst som i prod. Ændrer reviewet `db-migrations.sql` eller `db-rls.sql`,
  tømmes `T6C2_BLOK_A`/`T6C2_BLOK_B`/`T6C2_RLS` i runneren før slutøvelsen (en udfyldt pin stopper ved afvigelse i
  stedet for at blive lært), og de udskrevne `T6C2_FASTLAAS`-værdier skrives ind bagefter.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 29-trin6c2.sh …`. `koer.zsh` gemmer
runnerens `DAA_`-linjer (`DAA_T6C2_DUMP`, `DAA_T6C2_KONTROL`) i `prod/go-env.txt`; den seneste linje vinder. Skrivende
handlinger kræver `--jeg-mener-det --go <kode>`; ethvert ukendt argument afvises. Hver GO-kode binder ceremoniens navn,
målet (prod/stand-in), commit'en og filerne, så en kode aldrig gælder for en anden ceremoni.

Målingen klassificerer tilstanden efter tallene, ikke kun efter skemaet: `foer`, `a`, `b`, `c3a` (efter 3a), `c3b`
(efter 3b) og `d`. `c3a` og `c3b` har samme rå tilstand `c`, men forskellige tal (se Forventede tal), så et dump fra
før 3b aldrig kan bruges som fortrydelsesmål for ceremoni 4.

### Ceremoni 1 (vej B)

1. `maal` → `T6C2_MAAL_OK tilstand=foer`, `k1_bindinger_hash=d5bedf7d…`.
2. `vejb` → `T6C2_VEJB_OK tilstand=foer personer=10 stoerste_median_ms=…` (før-tallet; i prod).
3. `go-1` → `GO_6C2_1_KODE=<8 hex>`. Projektejeren skriver `GO 6c2-1 <kode>`.
4. `apply-1 --jeg-mener-det --go <kode>` → `T6C2_APPLY_1_OK tilstand=a …`. Før blokken gemmer runneren de nuværende
   definitioner af `public_person_facts`, `assertion_binding_current` og (hvis den findes) `binding_value_matches` i
   `prod/6c2/fortryd1-<stempel>/` (fortrydelsens mål). Blokken kører i én transaktion med `lock_timeout` 5 s;
   derefter `NOTIFY pgrst`.
5. `lighed` → `T6C2_LIGHED_OK personer=30 afvigende=0`: vej B og den frosne reference
   (`tests/sql/fixtures/public_person_facts_reference.sql` i `pg_temp`, transaktionen rulles tilbage) giver præcis
   samme rækker for de 10 tungeste + 20 tilfældige personer.
6. `vejb` → median ≤ 1.000 ms for hver af de 10 (`VEJB_OVER_GRAENSEN` ellers). **Ikke nået: stop**; 6c-2 fortsætter
   ikke til ceremoni 2 (spec §4.1 pkt. 4), og ceremoni 1 fortrydes med `fortryd-1`.
7. Projektejeren læser Security Advisor.

### Ceremoni 2 (DDL + kort 122)

1. `dump` → `DUMP_6C2_OK tilstand=a …`, `EKSTERN_6C2_OK … rundtur=ok`, `DAA_T6C2_DUMP=…`. Dumpet tages læse-kun,
   krypteres med age, lægges på SFTP og hentes tilbage (rundtur); restore-hashen og `change_set` måles før og efter,
   så et dump, der blev skrevet under, afvises.
2. `go-2` → GO-filen viser linjen `kort122 … oensket_person_id=1054 …` og `GO_6C2_2_KODE`. Projektejeren bekræfter
   1054 og skriver `GO 6c2-2 <kode>`.
3. `apply-2 --jeg-mener-det --go <kode>`: blok 6c-2b, `db-rls.sql` og kort 122-skridtet i én transaktion. Kort 122-
   skridtet kræver identitetsversion 1, `unresolved`, ingen person, ingen promotions fra personaen
   (`PERSONA_HAR_PROMOTIONER`) og at person 1054 findes; derefter `red_afgoer_source_persona(…, 1, 'unresolved', NULL,
   'ønsket_person_id=1054; grund=…', {basis human_sheet, sheet, rows, line 27})` som aktøren og en efterkontrol
   (version 2 med noten). Fejler noget, rulles **både** DDL og kort 122 tilbage (`maal` står i `a`).
   → `T6C2_APPLY_2_OK tilstand=b … kort122=version_2`.
4. `maal` → `b` og `T6C2_KORT122 version=2 status=unresolved person_tom=1 oensket=1`. Security Advisor.

### Ceremoni 3a (dato-markoer-v1)

1. `dump` → `tilstand=b`.
2. `forbered-3a` → `T6C2_FORBERED_3A_OK T6C2_NORMALISER antal=574 kandidater_sha256=acf348a5…`. Antal og sha er
   fastlåst fra øvelsen; afviger de, stopper runneren (`T6C2_NORM_ANTAL`/`T6C2_NORM_SHA`).
3. `go-3a` binder kandidatfilen → `GO 6c2-3a <kode>`.
4. `apply-3a --jeg-mener-det --go <kode>`: én transaktion. Kandidatlisten genberegnes i transaktionen og skal være
   GO-listen (`NORMALISER_GO_DRIFT`); ét `red_normaliser_forslag` pr. element med nulstillet ændringssæt; efterkontrol
   (`NORMALISER_EFTERKONTROL`). → `T6C2_APPLY_3A_OK tilstand=c3a versioner=574`.

### Ceremoni 3b (linjeskift-v1)

1. `dump` → `tilstand=c3a`.
2. `forbered-3b` → `T6C2_FORBERED_3B_OK antal=70 forventet=… graenser=e2ac1a56…`. Påstandsmængden (de 70 sorterede
   `assertion_id`) og grænsernes sha er fastlåst. Listens `interpretation_id` er id'et på den version, 3a selv
   oprettede (tilfældigt pr. kørsel), så `forventet_sha256` kan ikke fastlåses på tværs af kørsler; den bindes af GO-
   filen og tjekkes i transaktionen (`LINJESKIFT_FORVENTET_DRIFT`). `delstreng_i_tilstand` og `graenser_udfyldt` skal
   være 0.
3. `go-3b` → `GO 6c2-3b <kode>`.
4. `apply-3b --jeg-mener-det --go <kode>`: én transaktion; parlisten genberegnes (`LINJESKIFT_PAR_DRIFT`), forventningen
   genberegnes (`LINJESKIFT_FORVENTET_DRIFT`), én `red_ret_paastand` pr. element (DO-løkke, ændringssæt nulstillet pr.
   element), og grænserne skal være uændrede bagefter (`LINJESKIFT_GRAENSER_AENDRET`).
   → `T6C2_APPLY_3B_OK tilstand=c3b rettelser=70`.

### Ceremoni 4 (kontrol v2)

Dumpet tages **efter** svarene (skridt 5), ikke før `kort`: dumpet er kun fortrydelsesmålet for `apply-4`, og
`apply-*` kræver et dump, der højst er 12 timer gammelt (`DUMP_6C2_FOR_GAMMELT`). Besvarelsen kan tage dage.

1. `maal` → `c3b`.
2. `kort` (læse-kun; tilstand `c3b`; ejer-tjek) → kontrolmappen `prod/6c2/kontrol-<stempel>/` med klassifikation og
   rækkeeksport (kildescope 3), planen (`control_model_v2.py plan`), et tomt ark, konteksten
   (`persona_kort_kontekst.sql`) og kortsiderne. → `T6C2_KORT_OK personas=… sider=… plan=…`, `PLAN_V2_OK …`,
   `DAA_T6C2_KONTROL=…`.
3. **Projektejeren** åbner `kort/kort-1.html …` i browseren, besvarer alle personas (`-`, `P` eller `P <person-id>`)
   og alle felter (`B`, `D`, `V`) og gemmer svarfilerne (JSON). Siderne tilbyder ikke `B`, hvor kontrollen ville afvise
   det.
4. `flet <svar-1.json> [<svar-2.json> …]` (lokalt) → `T6C2_FLET_OK svar=… ark_sha256=…`. Svarfilerne kopieres ind i
   kontrolmappen; arket valideres af kontrolværktøjet (ubesvarede, ukendte og dobbelte svar afvises). Arket kan kun
   flettes én gang pr. kontrolmappe; nye svar kræver en ny `kort`.
5. `dump` → `tilstand=c3b` (efter svarene; se ovenfor).
6. `go-4` genererer ceremoniens SQL og den uafhængige verify fra plan + ark og binder kontrolmappens filer (plan,
   eksporter, kontekst, svar, ark, SQL, verify) → `GO 6c2-4 <kode>`.
7. `apply-4 --jeg-mener-det --go <kode>`: tilstand `c3b`, ejer-tjek, SQL'en genereres igen og skal være byte-ens med
   den bundne; ceremonien kører med `statement_timeout` 30 min på sessionen; derefter verify læse-kun.
   → `T6C2_APPLY_4_OK unresolved=… rettelser=… afgoerelser=… stikproeve=… maskine=… bundet=… verify=bundet=…`.
8. `maal` → `d`; `vejb` → median ≤ 1.000 ms for hver af de 10; `overlevering` → `T6C2_OVERLEVERING_OK antal=… fil=…`
   (listen over 1939-personas, der står `unresolved` med `ønsket_person_id`, til 6d; kun id'er).
9. Læsertjek som `anon` (spec §7 (b)) og status (plan Task 14).

## Varighed og prods tidsgrænse

Prods `statement_timeout` er 2 min for login-rollen og 3 s for `anon`. Stand-in-tallene er fra øvelsen 2026-11-04
(`…_20261104205203_t11`, restore af prod-dumpet `89633bc6…`, ICU, prods timeouts, `ANALYZE`). Prod anslås med 27× for
mange små writer-/RPC-kald, 3× for store læsninger, men **~20× for alt, der kalder `assertion_binding_current` pr.
række** (spec §2.3 pkt. 4: ca. 130 ms pr. kald i prod mod ca. 7 ms lokalt). Det gælder ceremoni 4's bindingstælling og
efterkontrol, verify og målingen i tilstand `d`. Runneren sætter derfor `statement_timeout='30min'` på sessionen før
filen for målingen, eksporterne, ceremoni 3a/3b, ceremoni 4 og verify (KRAV 1).

| Skridt | Stand-in | Skøn i prod |
|---|---|---|
| `maal` (`foer`-`c3b` / `d`) | 3,1-3,3 s / 6,9 s | ≤ 20 s / ca. 4 min |
| `vejb` (5 kald × 10 personer; median) | 3-6 ms (`a`), 24 ms (`d`) | kriterium ≤ 1.000 ms |
| `lighed` (30 personer) | 1,2 s | under 1 min |
| `dump` inkl. mål (restore-hash, katalog, ACL) | 5,9 s | dump ca. 2,5 min (dump-kopien 4/11: 151 s) + mål |
| `apply-1` / `apply-2` (blokke) | 0,1 s / 0,2 s | sekunder (6b's DDL: 16 s) |
| `apply-3a` (574 RPC-kald) / `apply-3b` (70) | 0,3 s / 0,4-0,6 s | ca. 10 s / ca. 15 s |
| `kort`: eksporter / kontekst | 3,9 s / 2,2 s | ≤ 1 min / ≤ 10 s |
| `apply-4`: ceremoniens SQL / verify | 18,5 s / 8,3 s | ca. 5-6 min / ca. 2-3 min (enkeltsætninger op til ca. 140 s) |
| `fortryd`: restore / efterarbejde | 2,9-3,1 s / ca. 8 s | minutter |

Ceremoni 4's enkeltsætninger (bindingstællingen og efterkontrollen) kan overstige 2 min i prod; det er grunden til
sessionens 30 min. Uden `ANALYZE` efter egne skrivninger tog bindingstællingen over 2 min allerede på stand-in'en (T10,
FUND 2); ceremoniens SQL kører `ANALYZE` med ejer-værn.

## Stoppunkter

Alle `STOPPORT:`-linjer stopper uden at skrive yderligere. Hvor langt man er nået, læses af `maal`.

| Hvor | Tilstand bagefter | Gør |
|---|---|---|
| Før en skrivning (`GO_MISMATCH`, `DUMP_6C2_MANGLER`, `DUMP_6C2_TILSTAND`, `DUMP_6C2_FOR_GAMMELT`, `DUMP_6C2_SKREVET_SIDEN`, `B1_EKSTERN_*`, `T6C2_FOER_*`, `T6C2_K1_AENDRET`, `T6C2_BLOK`, `T6C2_RLS`, `T6C2_EJER`, `T6C2_KORT122_FOER`) | uændret; intet skrevet | Ret årsagen (nyt `dump` i rette tilstand, ny GO, hvis filer er ændret) og kør skridtet igen |
| `T6C2_IKKE_FASTLAAST` | uændret | Runneren mangler en værdi fra slutøvelsen. Ingen prod-kørsel før slutøvelsen på `main` er gennemført |
| I en ceremonis transaktion (`DDL_6C2A fejlede`, `CEREMONI_2 fejlede`, `CEREMONI_3A/3B fejlede`, `CEREMONI_4 fejlede`; koden står i linjen, fx `NORMALISER_GO_DRIFT`, `LINJESKIFT_*_DRIFT`, `MACHINE_NOT_MATCH`, `SAMPLE_FAILED`, `PERSONA_HAR_PROMOTIONER`, `KORT122_*`) | som før ceremonien; rullet tilbage | Basen har ændret sig siden GO, eller arket afviser. Find årsagen; ny `forbered-*`/`kort` og ny GO |
| `forbered-3a`/`forbered-3b` (`T6C2_NORM_*`, `T6C2_LINJE_*`) | uændret; læse-kun | Listen er ikke øvelsens. Stop og forklar afvigelsen, før der tages GO |
| `kort`, `flet` (`T6C2_KONTROL_EKSPORT_*`, `T6C2_PLAN`, `T6C2_KORT_HTML`, `T6C2_FLET (<kode>)`, `T6C2_ARK_FINDES`) | uændret | Ret og kør igen; nye svar kræver en ny `kort` |
| Efter et commit: `DDL_6C2A_NOTIFY`/`CEREMONI_2_NOTIFY` | ceremonien er committet | Kør `maal`; står den i den nye tilstand: kør `NOTIFY pgrst, 'reload schema'` manuelt og fortsæt |
| Efter et commit: `T6C2_EFTER_*`, `T6C2_K1_AENDRET`, `T6C2_KORT122_EFTER`, `T6C2_VERIFY_4` | ceremonien er committet | Kør `maal`. Viser den forkerte tal, eller er `k1` ændret, eller fejler verify: **fortrydelsestilfælde** (nedenfor) |
| `vejb` efter ceremoni 1 eller 4: `VEJB_OVER_GRAENSEN` | ceremonien er committet | Efter 1: stop, `fortryd-1`. Efter 4: stop; restore af ceremoni 4's dump (`fortryd`) |
| `lighed`: `T6C2_LIGHED_BRUDT` | ceremoni 1 er committet | Stop, `fortryd-1` |
| `fortryd`: `T6C2_FORTRYD_FREMMEDE_AENDRINGER`, `T6C2_FORTRYD_TILSTAND`, `T6C2_FORTRYD_K1`, `T6C2_FORTRYD_LAAS` | uændret; ingen restore | Nogen har skrevet siden dumpet, eller basen står ikke lige efter ceremonien. Ingen restore; projektejeren afgør |
| `fortryd`: `T6C2_FORTRYD_RESTORE_FEJL` eller en efterkontrol (`T6C2_FORTRYD_ACL`, `_KATALOG`, `_RESTORE_HASH`, `T6C2_EFTER_FORTRYD`) | restoren er kørt; markøren `fortryd-<dump-sha>.igang` står | Alle handlinger ud over `maal`/`vejb` er spærret (`T6C2_FORTRYD_IGANG`). Undersøg fejlklasserne i `restore.err`; en ny restore af samme dump kræver, at markøren flyttes manuelt efter projektejerens afgørelse |
| Målingens egne fejl (`maal_trin6c2.sql fejlede`, `T6C2_MAAL_FORM`, `MAAL_6C2_UKENDT`) | uændret af fejlen selv | Kør `maal` igen; `ukendt` betyder tal, ingen øvet tilstand har |

`GO_MISMATCH` viser den kode, filerne svarer til nu. Brug den ikke uden at have tjekket, hvad der er ændret siden GO.

## Fortrydelse pr. ceremoni (spec §6)

- **Ceremoni 1:** `go-fortryd-1` → `GO 6c2-fortryd-1 <kode>` → `fortryd-1 --jeg-mener-det --go <kode>`. Kun i tilstand
  `a` (efter ceremoni 2 fortrydes 1 ikke alene). Runneren afspiller de gemte definitioner i én transaktion
  (`CREATE OR REPLACE` bevarer grants), kører `NOTIFY pgrst` og tjekker, at `maal` er `foer`, og at
  `public_person_facts` og `assertion_binding_current` er byte-ens med det gemte. `binding_value_matches` er ny i 6c-2a
  og bliver stående; intet kalder den i `foer`. → `T6C2_FORTRYD_1_OK tilstand=foer`.
- **Ceremoni 2:** `fortryd` med `a`-dumpet. En restore alene sletter ikke objekter, dumpet ikke kender, så runneren
  finder først blokkens nye objekter ved katalogdiffen (nu mod dumpets mål): kun nye tabeller (med deres kolonner,
  indeks, constraints og ejede sekvens) og nye funktioner er tilladt (ellers `T6C2_FORTRYD_2_UKENDT_OBJEKT`), og de nye
  tabeller skal være tomme (`T6C2_FORTRYD_2_TABEL_IKKE_TOM`). Øvelsen: `paastand_korrektion` + 6 funktioner
  (`T6C2_FORTRYD_2_DROP tabeller=1 funktioner=6`). De droppes i én transaktion, derefter restoren som nedenfor. Den
  ændrede `validate_interpretation_promotion_items` genskabes af restoren, og kort 122 står igen i version 1.
  `db-rls.sql` køres i versionen fra før 6c-2 (hentet med `git show` fra en fastlåst commit på `main` og tjekket mod
  6c-1's sha `f517b2e5…`): repo'ets version kræver 6c-2b's RPC'er (`RLS_REDACTION_RPC_ALLOW_LIST_SIGNATURE_MISSING`).
  Ceremoni 2 kan derefter køres igen fra `go-2` (øvet).
- **Ceremoni 3a, 3b og 4:** restore af dumpet, taget lige før ceremonien:
  1. `koer.zsh --saet DAA_T6C2_DUMP=<kvittering>` hvis det ikke er det seneste dump (`prod/6c2/daa-prod-<stempel>-6c2.dump.receipt.json`;
     `tilstand` står i kvitteringen).
  2. `go-fortryd` → GO-filen viser `fortryd dump_tilstand=<b|c3a|c3b> dump_sha256=…` → `GO 6c2-fortryd <kode>`.
  3. `fortryd --jeg-mener-det --go <kode>`: basen skal stå lige efter ceremonien (`a`→`b`, `b`→`c3a`, `c3a`→`c3b`,
     `c3b`→`d`),
     `k1` som dumpets, ingen fremmede `change_set` siden dumpet, ingen låse; markøren sættes; skema-defaults ryddes;
     `pg_restore --clean --if-exists --no-owner` af private+public (fejlmønsteret: de 4 kendte fejl om
     `current_rolle()`/`media_object_synlig_anon(text)` + advarslen); defaults genskabes; `ANALYZE`; `db-rls.sql`;
     grants afstemmes mod dumpets mål; `NOTIFY pgrst`; efterkontrol af grants, default-rettigheder, katalog,
     forældreløse rækker, restore-hash og `maal` = dumpets tilstand. → `T6C2_FORTRYD_OK tilstand=… acl=som_dump
     katalog=som_dump restore_hash=…`.
  4. Kæden kan gå baglæns (4 → 3b → 3a → 2), ét dump ad gangen; ceremonien kan derefter køres igen fra sit `dump`.
     Ceremoni 1 fortrydes derefter med `fortryd-1`.

**Stand-in'ens rolle.** Prod har en global default-ACL for `postgres` (`REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`, fra
`db-rls.sql`). pg_restore lægger den på `postgres`, men stand-in'en forbinder som den lokale rolle. `standin` giver
derfor den lokale rolle samme række. Uden den opretter ceremoni 2's `db-rls.sql` rækken, og fortrydelsens kontrol af
default-ACL'en ser en forskel, som prod ikke har (fundet i T11).

## Forventede tal

Fastlåst i runneren fra øvelserne på prod-kopien 4/11 (stand-in'en er en kopi af prod, så tallene gælder prod):

| Tilstand | forslag_k | match | skrivemaade | real_diff | accepteret_k | bindinger_k | rettelser | unresolved_fra_kort |
|---|---|---|---|---|---|---|---|---|
| `foer`, `a`, `b` | 1.248 | 544 | 579 | 100 | 0 | 0 | 0 | 1 |
| `c3a` | 1.248 | 1.023 | 100 | 100 | 0 | 0 | 0 | 1 |
| `c3b` | 1.248 | 1.093 | 30 | 100 | 0 | 0 | 70 | 1 |
| `d` (øvelsesarket) | 28 | 0 | 0 | 0 | 1.093 | 1.093 | 71 | 2 |

`k1_bindinger_hash` = `d5bedf7d2c7bd8b04fcaf04f055cd5aab0c14fb7e9480fb350d9569131b95f9f` i alle tilstande.
Normaliseringen: 574 kandidater, sha `acf348a5…`. Linjeskift: 70, påstandsmængde `787a3fdc…`, grænser `e2ac1a56…`.
Tallene i `d` afhænger af projektejerens ark; øvelsesarket (alle stikprøvefelter `B`, øvrige `V`, ét `B` på et
`REAL_DIFF`, én persona `P 1054`) gav `CONTROL_V2_OK unresolved=1 rettelser=1 afgoerelser=128 stikproeve=20
maskine=1072 bundet=1093` og verify `bundet=1093 p_personas=1`. Planen: 150 felter (100 `REAL_DIFF` + 30
`SKRIVEMAADE` + 20 stikprøve) på 119-120 personas. Stikprøven trækkes efter forslagenes versions-id'er, og 3a opretter
nye id'er ved hver kørsel; prods stikprøve er derfor ikke øvelsens, og antallet af personas kan variere lidt.

## Øvelse (2026-11-04, plan Task 10-11)

- **Task 10** (`…_20261104174109_t10`, uden runner): ceremonierne kørt i hånden. Tre ydelsesfejl fundet og rettet,
  som alle ville have stoppet en ceremoni i prod: klassifikationen og målfinderen (kvadratisk CTE-join; 33 s → 0,4 s,
  md5-ens), rækkeeksporten med kildescope (navn/maal genberegnet pr. række; over 120 min → 11 s, byte-ens med den
  gamle SQL kørt uden nested loop) og ceremoni 4's bindingstælling (`ANALYZE` efter egne skrivninger, med ejer-værn).
  Vej B mængde-lig for alle 1.811 personer.
- **Task 11** (`…_20261104205203_t11`, frisk fra samme dump, med runneren): hele forløbet `maal` → `apply-1` →
  `lighed` (30/0) → `dump a` → `apply-2` → `dump b` → `forbered-3a` → `apply-3a` → `dump c3a` → `forbered-3b` →
  `apply-3b` → `dump c3b` → `kort` → `flet` → `go-4` → `apply-4` → `maal d`, `vejb` (24 ms). Fortrydelser: `fortryd-1`
  (to gange, også på `…_t11f`, med byte-tjek af funktionerne), `fortryd` af 3b (og 3b igen), derefter kæden 4 → 3b →
  3a tilbage til `b`; alle med restore-hash, ACL og katalog som dumpets. Fortrydelse af ceremoni 2 (`…_t11h`): DROP af
  1 tabel og 6 funktioner + restore + `db-rls.sql` fra før 6c-2 → `a` med restore-hash `cae39043…` (som `_t11`'s
  `a`-dump), kort 122 i version 1; ceremoni 2 derefter kørt igen. Negative prøver: `MACHINE_NOT_MATCH` på en klon med
  én ændret maskinkandidat (ceremonien afviser og ruller tilbage), `apply-3b` i forkert tilstand afvist, forkert GO
  afvist. Fund: linjeskiftlistens `forventet_sha256` reproducerer ikke
  på tværs af kørsler (3a's versions-id'er); pinnen er påstandsmængden.
- `track_functions` kan ikke sættes i prod (superuser); at vej B ikke kalder enkeltopslaget pr. række, er testet i CI
  (`tests/sql/test-person-facts.sql`, `fpf_abc_calls`).

## Efter ceremonierne

- `docs/evidensbaseret-genimport/status.md` (1939 »Forslag og afgørelse« og promotion med dato), `docs/database-current-state.md`
  (nyt afsnit med prod-tider og forholdet til stand-in'en) og `docs/changelog.md`.
- Overleveringen til 6d: `overlevering`-filen (id'er) og noten i kort 122's identitet.
- Notér prod-tiderne for `maal` i `d`, ceremoni 4 og verify her, så senere skøn bygger på dem.
