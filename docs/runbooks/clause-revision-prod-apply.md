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
| Operatørscripts | `~/.private/148c-prod/` | R-kopierne `~/.private/omseg-rehearsal/r-dryrun.R` og `r-apply.R` (samme bytes som i rehearsal); skrivepause, preflight og `lib.zsh` genbruges fra 148c |

**Arbejdsdeling.** Kun projektejeren kører noget mod prod, i egen shell (klassifikatoren blokerer
AI-sessionens prod-adgang). AI'en bygger manifestet lokalt, kører rehearsal og læser kun rensede tal.

## 1. Adgangskrav

- `main` ren og fastlåst på en commit, der indeholder #222. Notér commit-SHA og scripthashes i
  GO-pakken; ingen kodeændring mellem rehearsal og apply.
- 4.4's forslag er **ikke** kørt i prod (0 fortolkninger). Er der fortolkninger på nogen af de 51
  poster, afviser writeren med `CLAUSE_REVISION_HAS_INTERPRETATIONS` — det er en stopport, ikke en fejl
  at arbejde udenom.
- Præcis én `redaktion`-profil (skrivepausen afhænger af det).

## 2. Rækkefølge

1. **Skrivepause** (`00-freeze.sh begin`, 148c) og **læse-kun preflight**: 591 `clause_evidence`-
   hændelser, 868 klausuler, 617/251 dispositioner, 0 fortolkninger, 0 aktive autorisationer.
2. **Backup under pausen** (`02-dump.sh`); notér dumpets SHA og start. Stopport før apply:
   `count(change_set WHERE created_at >= dump_start) = 0`.
3. **Rehearsal af netop det dump** (`~/.private/omseg-rehearsal/02-rehearsal.sh <dump>`, lokalt).
   Kræv `REHEARSAL_OK` og de tal, rapporten fra 2026-09-27 viser.
4. **DDL i prod** (projektejer): `db-migrations.sql`, derefter `db-rls.sql`, begge med
   `ON_ERROR_STOP`. Kør derefter **kun** blokken `$clause_set_live_verify$` fra `db-verify.sql`
   (læse-kun; den fulde `run-db-verify-disposable.sql` må ikke køres mod prod). Kræv
   `OK: omsegmentering — indeks pr. sæt …`. Mål igen: 868/868 klausuler med NULL-sæt, kanonisk md5 og
   anon-hashes uændrede.
5. **Sikkerhedslint:** `get_advisors` (security) mod det rigtige projekt — Supabase-MCP'en peger p.t.
   på et andet projekt, så via dashboardet. Nye fund fra DDL'en er STOP.
6. **Før-projektion** efter DDL'en (`clause_evidence_projection.psql`, `source_id=1`) → byg F1 lokalt
   med revisionsprofilen, ledger `8c8ecd92…` (`~/.private/omseg-maaling/ledger/clause-ledger-v1.json`),
   renditionen `~/.private/daa-2018-20-rendition.txt` og `--current-projection`. **F1 skal være
   `2f4b079b45fbc0379c090c444e5e409f95605809121c4a977eb3549568c0ee59`** (51 operationer, 116
   klausuler); en anden hash betyder, at prods klausuler har flyttet sig — STOP.
7. **Dry-run.** **Første datamutation** (DDL'en i trin 4 var den første prod-mutation): scriptet
   indsætter writer-profilrækken. Kald præcis som i rehearsal — `--vanilla` er bærende; uden det kan
   `count(*)` komme tilbage som en anden R-type (rehearsalens `%d`-fejl), og scriptet læser selv
   `~/.Renviron` i prod-tilstand:

   ```bash
   env -u PGPASSWORD DAA_CONNECTION_MODE=prod DAA_EXPECTED_TARGET=<prod-målidentitet> \
     DAA_PROFILE_FILE=.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-revision-v1.json \
     DAA_PROFILE_VERSION=clause-revision-v1 \
     /usr/local/bin/Rscript --vanilla ~/.private/omseg-rehearsal/r-dryrun.R <F1-manifest.json>
   ```

   Kræv `DRY_RUN_OK` og profil-hash `b72ddf5f…` ved readback.
8. **Apply** (`r-apply.R`, samme kald og miljø). Kræv `APPLY_OK`, første status `finalized`, replay
   `already_applied`, kanonisk md5 uændret. Ved tabt forbindelse omkring commit: kør ikke igen; afgør
   tilstanden læse-kun ud fra `reimport_batch.manifest_sha256 = 2f4b079b…` som i 4.1c §5.1.
9. **Verify:** efter-projektion → komparator med `--expect-target-sha256` (prod). Kræv `match`, scope
   `clause-revision-delta-v1`, records 51, skrevet/erstattet 116/197, dispositioner 56/60, neutrale
   lister 587/587/587/591/591, anon uændret. Til slut: 1 `finalized` batch og 51 `clause_revision`-
   hændelser for manifestet; 787 aktuelle klausuler.
10. **Pausen ophæves** først efter verify.

## 3. Fortrydelse

Byg manifest U med den private fortrydelsesprofil (`~/.private/omseg-rehearsal/undo-profile.json`:
revisionsprofilen med regler `clause-rules-2018-20-v2` og segmenter `clause_segment.py@v1`), 4.1b's
ledger `8f4a88f5…` (`~/.private/148b-20260910165321/ledger/clause-ledger-v1.json`) og en frisk projektion.

**Bevar indtil fortrydelsesvinduet er lukket:** de to ledgers og renditionen ovenfor, `undo-profile.json`,
R-kopierne og rehearsal-scriptet. De findes kun i `~/.private/`; uden dem kan hverken F1 eller U bygges. Kør dry-run/apply/verify som ovenfor. I rehearsal gav det 51
operationer (197 klausuler skrevet, 116 erstattet) og sæt-hashes identiske med før revisionen. Et
senere »frem igen« kræver et nyt manifest bygget fra den aktuelle projektion (det oprindelige F1 er
herefter en genafspilning: `already_applied`).

DDL'en fortrydes ikke: den er additiv, og NULL-sættet er sæt 1. Restore af dagens backup er
nødvejen ved en ukendt tilstand, med 4.1c's kendte pris (skrivninger efter dumpet går tabt).

## 4. Stopregler

Enhver afvigelse fra tallene i §2 og rehearsalrapporten er STOP og bevarer alt. Særligt:
restore-fejl ud over `supabase_vault`; verify-blokken fejler; F1-hash afviger; nye advisor-fund;
`CLAUSE_REVISION_*`-afvisninger; komparator ≠ `match`; kanonisk eller anon-drift.

## 5. Efter kørslen

- `docs/database-current-state.md`, `status.md` og changelog opdateres med prod-tallene.
- 4.4's GO-pakke er bundet til de gamle klausuler og skal genbindes: piloten køres om på de reviderede
  poster, og kontrolmodellen køres igen, før 4.4/4.5 kan få prod-GO.
