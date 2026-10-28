# A6b i prod: 10 narrativrevisioner (de beskårne prosalinjer)

Plan: `docs/superpowers/plans/2026-10-28-a6b-noise-re-narrativer.md`. Beslutninger: `docs/decisions.md` 2026-10-27
(»de 13 `NOISE_RE`-linjer«) og 2026-10-28 (»A6b afgrænses til narrativerne«). Scripts:
`.claude/skills/daa-extract/scripts/fix_a6b_maal.sql` og `fix_a6b_narrative_revision.sql`; manifestet bygges af
`build_narrative_revision_manifest.py`. Privat runner: `~/.private/5ab-overfoersel/23-a6b.sh` (kørt gennem `koer.zsh`).
Kører i projektejerens egen shell; AI'en har ingen prod-forbindelse.

## Hvad der skrives

Ingen DDL. I én transaktion revideres de 10 publicerede narrativer (I-9, I-11, I-17, I-18, I-32, I-33, I-44, I-84, I-89,
III-37) med redaktør-RPC'en `red_revider_publiceret_person_narrative_record`. Pr. narrativ:

- `narrative.tekst` får de prosalinjer, v1-støjreglen fjernede (rene indsættelser, 8-30 ord; `fts` følger med).
- én ny `narrative_publication_event` med før- og eftertilstand, ét `change_set` og ét `change_event` (målt: +10 af hver).
- `text_mention` genberegnes af triggeren `trg_mentions_narrative` (tom for de 10 før og efter).

Kildetekst (helpost) og klausuler røres ikke; de følger i trin 6. III-129 er ubundet og røres ikke.

Manifestet `work/a6b/manifest.json` (mode 600, gitignoreret, rummer posttekst) har `manifest_sha256` `f80e8156…`.
Runneren binder manifestet, de to SQL-filer, aktørfilen og retningen i GO-koden.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 23-a6b.sh …` fra `main` efter merge.

1. `maal` → `A6B_MAAL_OK tilstand=gammel …`. Først, fordi `rest` og `maal_oevrigt` er målt på en kopi: har nogen
   ændret et narrativ i prod siden, stopper `maal` med `MAAL_A6B_UKENDT`, før en GO-kode er udstedt.
2. `go` → `GO_A6B_KODE=<8 hex>` og commit. Projektejeren skriver `GO a6b <kode>`.
3. `dump` → `DUMP_A6B_OK …` og `EKSTERN_A6B_OK … rundtur=ok` (B1: `age`-krypteret kopi på SFTP-serveren, hentet tilbage,
   sammenlignet og dekrypteret).
4. `apply --jeg-mener-det --go <kode>` →
   - `B1_A6B_OK dump_sha256=… age_sha256=…`: dumpet er de samme bytes som i kvitteringen, og den eksterne kopi er hentet
     igen og har kvitteringens størrelse og sha.
   - `A6B_OK retning=frem revideret=10 ubundet=1 change_sets=10 go=<kode>`
   - `A6B_APPLY_OK retning=frem tilstand=ny events=+10 change_sets=+10 change_events=+10 log=…`
5. `maal` → `A6B_MAAL_OK tilstand=ny …`.

Hashes og målelinjer står i `apply-frem-<stempel>.log` i `~/.private/5ab-overfoersel/prod/a6b/`.

## Prøvet (2026-10-28)

På stand-in'en `daa5ab_ddl_standin_20261028190000_a6b` (trin B-dumpet `e253f352…` + trin B-blokken, fingeraftryk
`faeef822` = prod):

- **SQL'en direkte:** frem (10/10, +10/+10/+10), frem igen (`A6B_PRE_ALLEREDE_ANVENDT`), tilbage, frem; `rest` og
  `maal_oevrigt` uændrede hele vejen. Én narrativtekst ændret direkte → `A6B_PRE_TEKST_DRIFT I-84`, intet skrevet.
  `anon`-læseren `public_person_bio_source_versions_v2` viser den nye tekst for 10/10. Køretid ca. 1 s.
- **Gennem runneren:** `maal`, `go` (frem og tilbage), `dump` med lokal SFTP-simulering, og så tilbage → frem → tilbage
  → frem. Afvist: en frem-kode brugt til `--tilbage` (`GO_MISMATCH`), frem i tilstand `ny` (`A6B_FOER`), en ændret
  ekstern kopi (`B1_EKSTERN_BYTES`).

## Fortrydelse

- **Særskilt handling (gate 8):** `go --tilbage` → kode, så `apply --jeg-mener-det --go <kode> --tilbage` →
  `A6B_APPLY_OK retning=tilbage tilstand=gammel …`. Det er en ny revision tilbage til den gamle tekst (ny event, intet
  slettes). Prøvet to gange gennem runneren.
- **Nødudvej:** restore af dumpet fra skridt 3 inden for vinduet, som lukkes efter efterkontrollen (B1). Efter en
  restore køres `db-rls.sql` igen.

## Kendte følger

- **Narrativ ≠ kildetekst:** efter A6b afviger `narrative.tekst` fra helpostens `verbatim_text` for de 10 poster, indtil
  trin 6 retter kildeteksten og klausulerne. En genkørsel af 149b's komparator viser dem.
- **III-129** er stadig `unresolved_text` af en ukendt grund; de manglende linjer er ikke årsagen.
- **1939-testen** `test_v2_faktisk_ocr_bevarer_v1_nummererede_byte_for_byte` fejler lokalt også på `main` (den læser en
  gitignoreret OCR-fil og springes over i CI). Uden for A6b.
