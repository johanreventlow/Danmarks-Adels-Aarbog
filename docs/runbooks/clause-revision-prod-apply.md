# Runbook — omsegmentering af 2018-20's klausuler i prod (`clause_revision`, #147)

Manuel procedure for at deploye klausulsæt-DDL'en fra #222 og revidere 51 posters klausuler i prod
(profil `daa-2018-20-clause-revision-v1`). Øvet mod et prod-dump 2026-09-27:
`docs/evidensbaseret-genimport/omsegmentering-rehearsal-2018-20.md` (`REHEARSAL_OK`). Kræver
projektejerens GO; intet i denne runbook er kørt mod prod.

Mønstret er 4.1c's (`clause-evidence-prod-apply.md`): skrivepause, backup under pausen,
restore-rehearsal af netop det dump, apply, verify. Det, der er anderledes:

| | 4.1c | Omsegmentering |
|---|---|---|
| DDL | ingen (deployet 17/9) | `db-migrations.sql` + `db-rls.sql` (klausulsæt, 4 triggere, `clause_revision`, S4) |
| Data | 591 `clause_evidence` | 51 `clause_revision`: 116 klausuler skrives, 197 får `erstattet` |
| Fortrydelse | kun restore | **ny revision** tilbage til 4.1b's opdeling (øvet); restore er nødvejen |
| Operatørscripts | `~/.private/148c-prod/` | `~/.private/omseg-prod/` (00-08, `lib.zsh`, R-kopierne byte-identiske med rehearsal) |
| Fejl midt i apply | restore | `08-afgoer.sh` / `07 --afgoer` (læse-kun) afgør, om skrivningen nåede at committe |
| STOP før skrivning | — | `00-freeze.sh end --uden-apply` ophæver pausen, når intet er skrevet siden `begin` |

**Arbejdsdeling.** Kun projektejeren kører noget mod prod, i egen shell (klassifikatoren blokerer
AI-sessionens prod-adgang). AI'en kører kun 03 (lokalt) og læser kun rensede tal.

**Pakken er testet mod en lokal stand-in** (`DAA_STANDIN_DB=daa_omseg_standin_<14 cifre>`, en restore
af prod-dumpet): hele kæden, et 05 der dør efter dry-run'en, et 05 der dør efter commit, og fortrydelse
i en ny pause, et 07 der dør efter commit, og nødudgangen efter DDL'en. Uden `DAA_STANDIN_DB` går alt
mod prod, og målet skal være prods faste identitet (`71ca6e45…`, låst i `lib.zsh`); hvert script skriver
`MAAL: PROD` eller `MAAL: STAND-IN` på stderr. Stand-in'en bruger en dummy-adgangskode, så den ser, hvis
adgangskoden forsvinder undervejs (R2-fund: en EXIT-trap i en funktion slettede den straks; rettet med
`setopt POSIX_TRAPS`, og hvert script stopper nu, hvis `PGPASSWORD` er tom efter forbindelsen).

## 1. Adgangskrav

- `main` ren og på den commit, 01 udskriver (`DAA_EXPECTED_COMMIT`). Ingen kodeændring fra 03 til 06:
  03 skriver GO-hash-filen over alle eksekverede filer (repo, pakke, ledgers, rendition), og 04-08
  stopper ved den mindste afvigelse.
- 0 fortolkninger i prod (4.4 er ikke kørt). Ellers afviser writeren `CLAUSE_REVISION_HAS_INTERPRETATIONS`.
- Præcis én `redaktion`-profil (skrivepausen afhænger af det).
- Scriptene køres med `/bin/zsh -f` (ellers stopper de). **Skriv ikke `!` foran i din egen shell** — i
  zsh er `! kommando` negation; i AI-sessionens grænseflade er `! ` præfikset, der sender kommandoen til
  din shell. Kør aldrig med `zsh -x`.

## 2. Rækkefølge

**Prøve før dagen (læse-kun, anbefalet).** Bekræfter i prod, at forbindelsen holder, at målet stadig er
`71ca6e45…` (sidst set 18/9), og giver skemaets fingeraftryk før DDL'en, som AI'en kan holde op mod en
restore af det seneste dump:

```bash
export DAA_FREEZE_RESPONSIBLE=<kort ansvarskode>
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh begin      # ved STOP om aktive forbindelser: gentag med
                                                          #   --accepter-forbindelser <det viste antal>
/bin/zsh -f ~/.private/omseg-prod/01-preflight.sh         # MAAL: PROD … PREFLIGHT_OK … skema=<md5>
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh end --uden-apply
```

Rør ikke redaktørfladen under prøven: en redaktionel ændring mellem `begin` og `end --uden-apply` får
øjebliksbilledet til at afvige, og så er der ingen scriptet udgang (hold pausen, eskalér). `MAAL: PROD`
bekræfter den låste identitet. Send `skema=`-værdien til AI'en: en restore af dumpet fra 27/9 giver
`34a3b5115bd8660173380bc1c7c4f082` (samme i fem stand-ins og fem restores). Afviger den, sammenlignes
`preflight-….schema.txt` med en stand-ins før dagen.

Hvert script udskriver `DAA_…=`-linjer; eksportér dem, før næste trin køres. Afvigelser er STOP.

```bash
export DAA_FREEZE_RESPONSIBLE=<kort ansvarskode>
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh begin      # pause; → DAA_FREEZE_REPORT(+_SHA256)
/bin/zsh -f ~/.private/omseg-prod/01-preflight.sh         # læser; → DAA_EXPECTED_TARGET, _COMMIT, DAA_PREFLIGHT_REPORT(+_SHA256)
/bin/zsh -f ~/.private/omseg-prod/02-dump.sh              # læser; backup i pausen → DAA_DUMP_RECEIPT
/bin/zsh -f ~/.private/omseg-prod/03-rehearsal.sh         # LOKALT: netop det dump → DAA_GO_HASHES_FILE, DAA_REHEARSAL_REPORT(+_SHA256)
/bin/zsh -f ~/.private/omseg-prod/04-ddl.sh --jeg-mener-det   # SKRIVER: DDL → DAA_DDL_REPORT(+_SHA256)
#   get_advisors (security) mod prod-projektet i dashboardet; ingen nye fund → export DAA_ADVISORS_OK=ingen-nye-fund
/bin/zsh -f ~/.private/omseg-prod/05-apply.sh --jeg-mener-det # SKRIVER: 51 revisioner → DAA_APPLY_REPORT(+_SHA256)
/bin/zsh -f ~/.private/omseg-prod/06-verify.sh            # læser; komparator → verify-ok.json
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh end        # kræver verify-ok.json
```

Hvad hvert trin kræver (tallene er målt i rehearsal 2026-09-27 og i stand-in-kæden):

1. **01:** tilstand `591|868|591|0|0|0|1` (person_post, klausuler, `clause_evidence`, revisionsprofiler,
   aktive autorisationer, fortolkninger, redaktion), dispositioner 617/251, DDL'en ikke kørt,
   restore-privilegier, anon-rolle. Kanonisk md5, anon-hash og skemaets fingeraftryk før DDL'en gemmes
   som reference (objektlisten, navn + md5, ligger ved siden af som `preflight-….schema.txt`). Fingeraftrykket
   tages med `search_path` låst til `pg_catalog`, så rollens søgesti ikke ændrer gengivelsen.
2. **02:** dumpet starter efter pausen; kvitteringen bindes af 03 og tjekkes af 04/05.
3. **03:** restore = preflight (tilstand, kanonisk, anon **og skema**: en forskel mellem prod og restoren
   stopper her, lokalt, før prod røres); DDL to gange med samme skema-fingeraftryk og
   0 `WARNING`; F1 = `2f4b079b…`; apply → `match`; fortryd (U = `69f13caa…`) → `match` og sæt-hashes
   tilbage til `8d46a529…`; frem igen → `match` og `1bad2e97…`; fuld db-verify (kun lokalt).
4. **04:** alle bindinger før første skrivning; 0 `change_set` efter dump-start; prods skema =
   preflight's (sidste kontrol før skrivning); derefter
   `db-migrations.sql` (autocommit statement for statement; kun én eksplicit BEGIN/COMMIT-blok),
   `db-rls.sql --single-transaction`, `NOTIFY pgrst`. Efter:
   levende verify-blok, 0 `WARNING:`-meddelelser (prods DDL 17/9 gav 0), skema-fingeraftryk = rehearsal, 868/868 NULL-sæt, kanonisk og anon
   uændrede. Når skema-gaten er bestået, skriver 04 en gate-markør bundet til pausen og preflight, *før*
   første skrivning. Afbrudt midtvejs: bevar alt, kør 04 igen med `DAA_DDL_GENKOERSEL=ja` (filen er
   idempotent). Genkørslen springer kun skema-gaten over, når markøren fra samme pause findes; ellers
   STOP. Fjern variablen igen bagefter (`unset DAA_DDL_GENKOERSEL`). Kendt årsag, set på en stand-in:
   `deadlock detected` i `db-rls.sql` mod en autovacuum (`VACUUM ANALYZE` på en tabel, som filen
   `GRANT`/`ALTER`'er). `db-rls.sql` er da rullet helt tilbage; genkørslen ovenfor er vejen (bevist).
5. **05:** før-projektion → F1 skal være `2f4b079b…` (ellers har prods klausuler flyttet sig). Dry-run er
   **første datamutation** (writer-profilrækken; readback `b72ddf5f…`). Apply → `finalized`, replay
   `already_applied`, `984|787|197|51|1`, kanonisk uændret.
6. **06:** komparator `match` med tallene fra rehearsal (51 records, 116/197, 56/60), sæt-hashes
   `1bad2e97…`, profil-readback, anon uændret. Skriver `verify-ok.json`.

**Hvis 05 stopper efter dry-run'en** (fx tabt forbindelse omkring commit): **kør ikke 05 blindt igen.**
Kør `/bin/zsh -f ~/.private/omseg-prod/08-afgoer.sh <05's apply-mappe>` (læse-kun, samme miljø):

- 08 venter ikke: holder en anden session af samme bruger stadig en advisory-lås, stopper den (kør igen
  om lidt). Den viser antallet af aktive autorisationer.
- `INTET_COMMITTET` → kør 05 igen i samme pause; det genkender profilrækken fra første dry-run. Står der
  »en autorisation er udstedt og ubrugt«, så vent til den er udløbet (højst 30 min.) før genkørslen.
- `APPLY_COMMITTET` → 08 skriver `apply.json` (eksportér `DAA_APPLY_REPORT…`) → kør 06 og `00 end`.
- alt andet → NO-GO: bevar alt, hold pausen, eskalér.

**Nødudgang: STOP før skrivning.** Stopper et trin, før data er skrevet (preflight, rehearsal, 04 før
eller efter DDL'en, advisor-fund, F1-afvigelse i 05), ophæves pausen med
`/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh end --uden-apply`. Den kræver, at øjebliksbilledet fra
`begin` (antal observationer, reimport-hændelser og -batches, fortolkninger,
redaktionsprofiler, `change_set`) samt kanonisk og anon er uændrede; writer-profilrækker fra en dry-run
er tilladt (stand-in-testet). DDL'en må være kørt (den er additiv) og noteres i slutrapporten. Efter en afbrydelse med
DDL'en i prod kan kæden ikke startes forfra uden ændringer (01 og 03 kræver, at DDL'en mangler): eskalér.
Ved en skema-afvigelse: diff `schema-*.txt` i runmapperne (navn + md5, ingen data).

## 3. Fortrydelse

`07-fortryd.sh` skriver en **ny** revision tilbage til 4.1b's opdeling (privat `undo-profile.json` +
4.1b-ledgeren `8f4a88f5…`). Kræver en ny skrivepause og et **nyt dump i den**.

07 er bundet til GO-pakken: repoet skal stå på GO-commit'en (`DAA_EXPECTED_COMMIT`), og
`DAA_EXPECTED_TARGET`, `DAA_EXPECTED_COMMIT`, `DAA_GO_HASHES_FILE`, `DAA_PREFLIGHT_REPORT(+_SHA256)` og
`DAA_REHEARSAL_REPORT(+_SHA256)` fra kørslen skal eksporteres igen. **Gem derfor `DAA_…=`-linjerne fra
kørslen** (fx i `~/.private/omseg-prod/go-env.txt`, 0600). Står `main` senere på en nyere commit, så
tjek GO-commit'en ud (`git checkout <DAA_EXPECTED_COMMIT>`) før 07, og gå tilbage til `main` bagefter:

```bash
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh begin      # ny pause; ny DAA_FREEZE_REPORT
/bin/zsh -f ~/.private/omseg-prod/02-dump.sh              # nyt dump; ny DAA_DUMP_RECEIPT
/bin/zsh -f ~/.private/omseg-prod/07-fortryd.sh --jeg-mener-det
/bin/zsh -f ~/.private/omseg-prod/00-freeze.sh end        # 07 skriver selv verify-ok.json
```

Dumpet skal være taget efter F1's `finalized_at` (07 tjekker det). Stopper 07 efter dry-run'en (fx
tabt forbindelse), så kør **ikke** 07 igen, men `07-fortryd.sh --afgoer <runmappe>` (læse-kun; 07
udskriver mappen, før første skrivning): `INTET_COMMITTET` → kør 07 igen; `FORTRYD_OK` → U nåede at
committe, er verificeret mod målingen lige før (`pre.json`, bundet til pausen og dumpet), og
`verify-ok.json` er skrevet. `--afgoer` skriver i en ny mappe og kan derfor køres igen, hvis den selv
bliver afbrudt.

07 kræver tilstanden efter apply (`984|787|197|51|1`, sæt-hashes `1bad2e97…`), at U er præcis
`69f13caa…`, og efter skrivningen `match` (51 records, 197/116, 77/120), sæt-hashes tilbage til
`8d46a529…`, `1181|868|313|102|1` samt kanonisk og anon uændret mod målingen lige før. Et senere »frem
igen« kræver et nyt manifest fra den aktuelle projektion (det oprindelige F1 er herefter en
genafspilning: `already_applied`).

DDL'en fortrydes ikke: den er additiv, og NULL-sættet er sæt 1. Restore af pausens dump er nødvejen ved
en ukendt tilstand, med 4.1c's kendte pris (skrivninger efter dumpet går tabt).

**Bevar indtil fortrydelsesvinduet er lukket:** `~/.private/omseg-prod/`, de to ledgers
(`~/.private/omseg-maaling/ledger/`, `~/.private/148b-20260910165321/ledger/`) og renditionen
`~/.private/daa-2018-20-rendition.txt`. De findes kun dér; uden dem kan hverken F1 eller U bygges, og
GO-hash-filen kan ikke genskabes.

## 4. Stopregler

Enhver afvigelse fra tallene i §2 og rehearsalrapporten er STOP og bevarer alt. Særligt:
restore-fejl ud over `supabase_vault`; skema-fingeraftryk afviger; verify-blokken fejler; F1-hash afviger; nye advisor-fund;
`CLAUSE_REVISION_*`-afvisninger; komparator ≠ `match`; kanonisk eller anon-drift.

## 5. Efter kørslen

- `docs/database-current-state.md`, `status.md` og changelog opdateres med prod-tallene.
- 4.4's GO-pakke er bundet til de gamle klausuler og skal genbindes: piloten køres om på de reviderede
  poster, og kontrolmodellen køres igen, før 4.4/4.5 kan få prod-GO.
