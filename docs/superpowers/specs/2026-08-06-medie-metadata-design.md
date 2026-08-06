# Medie-metadata-udvidelse — design

**Dato:** 2026-08-06
**Status:** Godkendt af bruger (tilgang A)
**Branch:** `feat/medie-metadata` (worktree, baseret på main efter PR #142)

## Formål

Udvide de metadata der kan registreres om medier, så eksternt hentede billeder
(fx fra Deutsche Digitale Bibliothek) kan håndteres korrekt: kilde-weblink,
fuld kildeangivelse/kreditlinje (juridisk krav ved CC-licenser), og en kort
prosa om billedets historie. Motiverende eksempel: DDB's Quellenangabe for
"Luise Gräfin von Reventlow" (kunstner Rahl, Carl / fotograf Sönke Ehlert /
rettighedshaver Schleswig-Holsteinische Landesbibliothek / CC BY-SA 4.0 / URL).

## Afklarede beslutninger

1. **Eksterne billeder:** egen kopi i Storage + kilde-URL som metadata
   (ikke hotlink). Eksisterende upload-flow genbruges uændret.
2. **Omfang:** hele kæden — DB-lag, redaktør-UI, læser-visning.
3. **Feltgrupper:** kerne (kilde, ophav, kreditlinje, historik) + alt-tekst,
   fysisk objekt, institutions-ID/hentedato, fuzzy datering.
4. **Tilgang A:** alle nye felter er **faktatyper** (data i `vocab`), ikke
   kolonner. Følger invariant 2+3 og skemaets egen kontrakt ("rettigheds-
   dokumentation forbliver fact"; byte-felter er "eneste legitime fedning").

## §1 Datalag — kun vocab-seeds, ingen DDL på `media`

12 nye seeds i `vocab (scheme='faktatype')`:

| code | label (forslag) | note |
|---|---|---|
| `kilde_url` | Kilde-URL — permalink til billedside hos ekstern kilde | |
| `kilde_institution` | Kilde-institution / datapartner | |
| `ekstern_objekt_id` | Institutionens objekt-/inventar-ID | robust gen-opslag |
| `hentedato` | Dato billedet blev hentet fra kilden | date-felter bruges |
| `fotograf` | Fotograf af reproduktionen | ≠ `media.kunstner` (ophavsmand) |
| `rettighedshaver` | Rettighedshaver / Rechtewahrnehmung | |
| `kreditlinje` | Ordret kreditlinje som kilden kræver vist | juridisk tekst, IKKE sammensat af delfelter |
| `beskrivelse` | Billedets historie/proveniens (prosa) | |
| `alt_tekst` | Alt-tekst til skærmlæsere | |
| `teknik` | Teknik/materiale (fx "olie på lærred") | tunge medier |
| `fysiske_maal` | Fysiske mål (fx "92 × 73 cm") | tunge medier |
| `datering` | Datering af værket (fuzzy) | `date_min/max/qualifier/raw` på fact |

**Ingen ny RPC.** `red_upsert_fakta('media', id, faktatype, værdi, date…, kilde_fritekst)`
dækker alt, er granted til authenticated, re-entrant, versioneret og kildebindende.
`fact.faktatype` har ingen FK til vocab — seeds er konsistens/UI-føde (invariant 9).

**Visningsregel:** findes en `datering`-fakt, vinder den over `media.datering`-
kolonnen. Kolonnen bevares (legacy/rå tekst fra oprettelse).

**Sletning:** `red_slet_media` blokerer allerede ved eksisterende media-fakta
("fjern den først") — uændret, tilsigtet friktion. Fjernelse af enkeltfakta går
via eksisterende `red_tilbagetraek_fakta`.

**Migration:** idempotent `INSERT … ON CONFLICT DO NOTHING`-blok i
`schema.sql` + `db-migrations.sql`; assert i `db-verify.sql`.

## §2 Redaktør-flade (`web/src/components/MediaDetaljeOverlay.tsx`)

Feltgrupper i overlayet:

- **Kilde:** kilde-URL, institution, ekstern objekt-ID, hentedato
- **Ophav:** fotograf, rettighedshaver (kunstner-kolonnen findes allerede)
- **Rettigheder:** eksisterende felter (licens, kildehenvisning,
  gengivelsestilladelse) + kreditlinje
- **Beskrivelse:** historik-prosa (textarea), alt-tekst
- **Fysisk:** teknik, fysiske mål
- **Datering:** fuzzy (min/max/kvalifikator/rå tekst)

**Kendt fejl fikses samtidig:** overlayet er i dag *write-only* — felterne
nulstilles til `''` ved load, så redaktøren kan ikke se eksisterende værdier.
Ny læse-vej i `redaktionRead.ts` henter mediets fakta (fact + valgt konklusion)
og præudfylder formularen.

**Skrivning:** pr. udfyldt/ændret felt kaldes `red_upsert_fakta` via den
eksisterende submit-flow. **DryRun-prop skal threades korrekt** + en
"default respekteres"-regressionstest (kendt fælde, jf. PR #72).

## §3 Læser-flade (Lightbox/billedside)

- **Kreditlinje vises altid når udfyldt** — diskret linje under billedet.
  Juridisk krav ved CC-licenser; må ikke gemmes bag fold.
- **Kilde-URL** som ægte link: "Se hos [institution]" (åbner i ny fane).
- **Historik-prosa** foldbar under billedet.
- **`alt_tekst`** → `alt`-attribut på både thumbnail og lightbox-billede.
- **Teknik / mål / datering** i metadata-linjen (datering-fakt > kolonne).

RLS: `media` er i det faste ikke-PII-entitetssæt i `db-rls.sql`, så media-fakta
følger den eksisterende fact-politik og bør være anon-læsbare for publicerede
medier — **verificeres empirisk** (fail-closed-princip; se §4).

## §4 Test

- **Vitest (web):** formular præudfyldes fra eksisterende fakta;
  submit-payloads pr. felt; dryRun-default-regressionstest;
  læser-visning (kreditlinje, link, alt-tekst).
- **`db-verify.sql`:** assert på at de 12 seeds findes.
- **Empirisk RLS-tjek:** anon kan læse media-fakta for et publiceret medie;
  kan IKKE for et ikke-publiceret.
- **Manuel ende-til-ende:** DDB-eksemplet (Luise Gräfin von Reventlow) —
  upload kopi, udfyld alle felter fra Quellenangabe, verificér læser-visning.

## Uden for scope

- Hotlink-/byte-løse medier (fravalgt — egen kopi er strategien)
- Fuldtekstsøgning i billedhistorik (kan tilføjes senere)
- Automatisk import/parsing af eksterne metadata (fx LIDO/DDB-API)
- Mobil-fladen (web først; mobil er dev-only)
