# Omsegmentering af 2018-20 — rehearsal mod prod-dump (2026-09-27)

Plan: `docs/superpowers/plans/2026-09-27-trin4-omsegmentering-og-s4.md`, Task 7. Spec:
`docs/superpowers/specs/2026-09-27-trin4-omsegmentering-og-s4-design.md`. Kode: `main` @ `cbc6564`
(#222). Alt nedenfor er kørt i en lokal restore; intet er skrevet til prod. Kun tal og hashes;
rå artefakter ligger 0600 i `~/.private/omseg-rehearsal/run-20260927213311/`.

**Resultat: `REHEARSAL_OK`.** Revisionen af de 51 poster, fortrydelsen og en ny kørsel frem gav alle
`match` i komparatoren, uden kanonisk delta og med uændrede anon-hashes.

## Input

| | |
|---|---|
| Prod-dump (læse-kun, 2026-09-27) | `1646e57c332c7aec09aafce02950d62fc086b095d499cd8dd7832ecbf0fb1dd8`, 10 522 331 bytes |
| Rehearsal-base | `daa_omseg_20260927213311_rehearsal` |
| Revisionsprofil | `daa-2018-20-clause-revision-v1`, profil-hash `b72ddf5f41c1cac199d84ef09c05b82157a9a4749afa6b2503f183579b9910bb` |
| Ledger (profil v2) | `8c8ecd92cc6d568ac4a28297488c5bcdeb3ec9e7d4236e46539f1185343787ae` |
| Ledger til fortrydelse (4.1b) | `8f4a88f5803287778666c120fa36bc5e770cebe685286f0e2a4eb9bc08980210` |
| Scripts (`~/.private/omseg-rehearsal/`) | `01-dump.sh` `c4468cdd…`, `02-rehearsal.sh` `d7b04b3b…`, `r-dryrun.R` `e363a236…`, `r-apply.R` `b8cd52e1…`, `undo-profile.json` `c9139af3…` |
| Repo-værktøj (uændret fra `cbc6564`) | `apply_reimport_helpers.R` `5611d47c…`, `build_clause_evidence_manifest.py` `cfb6f0a0…`, `compare_clause_evidence_projection.py` `f7f4ffc5…`, `clause_evidence_projection.sql` `88b70204…` |

## Forløb og målinger

| Trin | Måling | Resultat |
|---|---|---|
| Restore | fejl i alt / ud over `supabase_vault` | 8 / 0 |
| Før DDL | `clause_evidence`-hændelser, klausuler | 591, 868 |
| | dispositioner | 617 `afventer_fortolkning`, 251 `maskinelt_flagget` |
| | fortolkninger, aktive autorisationer, redaktionsprofiler | 0, 0, 1 |
| DDL | `db-migrations.sql` ×2 + `db-rls.sql` | rene |
| | levende verify-blok (`$clause_set_live_verify$`) | OK — ét unikt ordinal-indeks pr. sæt på prods form |
| | klausuler med `clause_set_seq` NULL | 868/868 |
| | kanonisk md5 / anon (8 hashes) | uændret / uændret |
| Manifest F1 (frem) | sha, operationer, klausuler | `2f4b079b…` (= målingen fra restore-kopien), 51, 116 |
| Dry-run + apply F1 | status | `finalized`, committed; replay `already_applied` |
| Komparator F1 | scope, records, skrevet/erstattet | `clause-revision-delta-v1`, 51, 116/197, `match` |
| Manifest U (fortryd, 4.1b's opdeling) | sha, operationer, klausuler | `69f13caa…`, 51, 197 |
| Komparator U | skrevet/erstattet | 197/116, `match` |
| | sæt-hashes pr. post efter fortrydelse | = før frem (`8d46a529…`) |
| | det oprindelige F1 igen | `already_applied`, projektionen byte-identisk |
| Manifest F2 (frem igen) | sha, operationer, klausuler | `64f89811…`, 51, 116 |
| Komparator F2 | skrevet/erstattet | 116/197, `match` |
| | sæt-hashes pr. post | = efter første frem (`1bad2e97…`) |
| Til slut | kanonisk md5 / anon | uændret (`3dfdc1ef…`) / uændret |
| | klausuler i alt / aktuelle / `erstattet` | 1297 / 787 / 510 |
| | `clause_revision`-hændelser, batches | 153, 3 `finalized` |
| | neutrale lister (alle tre komparatorer) | 587 narrativ-bindinger, 587 personer, 591 kildeankre, 591 records |
| | fuld `db-verify` (sidst, efterlader rester) | OK |

787 aktuelle klausuler svarer til ledgerens total for profil v2; de nye dispositioner efter frem er
56 `afventer_fortolkning` og 60 `maskinelt_flagget`. 4.1b-ledgeren og prods sæt 1 har samme sæt-hash
for alle 591 poster (Python mod SQL), så fortrydelsen bygges med den almindelige manifest-bygger og en
privat profil med de gamle regler.

## Fundet undervejs

- Første kørsel stoppede i dry-run: 4.1c's R-script formaterede `count(*)` med `%d`, som R afviser for
  numeric. Rettet til `format()` som i apply-scriptet; ingen data var skrevet ud over profilrækken i en
  engangsbase.
- Planfilen var aldrig nået `main` (#221 squash-merget før plan-commit'en blev pushet); lagt ind uændret.

## Hvad det betyder for prod

- Fortrydelse kræver **ikke** restore: en ny revision tilbage til 4.1b's opdeling er øvet og giver
  byte-identiske sæt-hashes. Restore af dagens backup er stadig nødvejen ved en ukendt tilstand.
- Hvis prods klausuler er uændrede ved prod-kørslen, bliver F1 byte-identisk (`2f4b079b…`); en anden
  hash er en stopport.
- Prod-kørslen følger `docs/runbooks/clause-revision-prod-apply.md` og kræver projektejerens GO.
