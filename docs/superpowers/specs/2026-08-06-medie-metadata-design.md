# Medie-metadata-udvidelse — design

**Dato:** 2026-08-06 (revideret samme dag efter dual-review — se
`docs/reviews/medie-metadata-spec-plan-review-2026-08-06.md`, fund MM-01..13)
**Status:** Godkendt af bruger (tilgang A + RLS-skærpelse valgt ved MM-01)
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

**Fjernelse og livscyklus (MM-02, MM-04, MM-09):**
- Fjernelse af et felt = `red_tilbagetraek_fakta` (sætter KUN `conclusion.status
  ='tilbagetrukket'` og beholder `valgt_assertion_id`) — derfor SKAL alle
  læsninger filtrere på `conclusion.status='afklaret'`. Gen-gem via
  `red_upsert_fakta` genopliver slottet (`status='afklaret'` igen).
- Tilbagetrukne fact-slots BESTÅR i basen. `red_udrens_media` (hård sletning;
  NB: der findes ingen `red_slet_media` — blød fjernelse hedder
  `red_fjern_media`) blokerer på ENHVER media-fact uanset status. Accepteret
  v1-friktion: et medie med (også tilbagetrukne) fakta kan ikke udrenses før
  fakta er manuelt slettet i basen. Dokumenteres i udrens-blokeringsteksten.
- Blød medieflet (`mediaMerge.ts`) flytter KUN afbildnings-relationer — fakta
  bliver på kopien. V1-politik: accepteret (kopien er parkeret i papirkurven);
  flet-UI'ens advarselstekst udvides til også at nævne efterladte fakta.
- Ingen unik constraint på `(subjekt_type, subjekt_id, faktatype)` og
  `red_upsert_fakta` vælger slot med uordnet `LIMIT 1` — eksisterende
  modelvilkår; ingen ny dublet-politik i denne omgang.

**Migration:** idempotent `INSERT … ON CONFLICT DO NOTHING`-blok i
`schema.sql` + `db-migrations.sql`; assert i `db-verify.sql`.

## §1b RLS-skærpelse (MM-01 — brugerbeslutning 2026-08-06)

I dag returnerer `entitet_offentlig('media', id)` ubetinget `true`
(db-rls.sql:83-84), så anon OG medlemmer kan læse fakta på upublicerede
medier. Skærpelse: media-grenen ændres til `media_rettigheder_ok(p_id)`
(kræver `upload_status='klar'` + `maa_publiceres`).

- **Redaktionen er uberørt:** `fact`/`assertion`/`conclusion`/`citation` har
  additivt `redaktion_read`-lag (db-rls.sql:536-547).
- **Afledt (ønsket):** note/text_mention/relation med media-mål følger nu også
  publiceringsgaten via samme funktion.
- **Bevidst afgrænsning:** fakta følger PUBLICERINGS-gaten, ikke
  person-afbildningsgaten (`media_afbilder_skjult/privat` er rollespecifik og
  gælder fortsat media-rækken/bytes selv). Tekstfelterne må ikke indeholde
  PII om levende — redaktionel regel, uændret.
- **Regressionskrav:** publicerede mediers fakta forbliver læsbare for anon;
  upublicerede bliver mørke. `get_advisors(security)` køres efter migrationen
  (ægte DDL — CREATE OR REPLACE FUNCTION).

## §2 Redaktør-flade (`web/src/components/MediaDetaljeOverlay.tsx`)

Feltgrupper i overlayet:

- **Kilde:** kilde-URL, institution, ekstern objekt-ID, hentedato
- **Ophav:** fotograf, rettighedshaver (kunstner-kolonnen findes allerede)
- **Rettigheder:** eksisterende felter (licens, kildehenvisning,
  gengivelsestilladelse) + kreditlinje
- **Beskrivelse:** historik-prosa (textarea), alt-tekst
- **Fysisk:** teknik, fysiske mål
- **Datering:** fuzzy (min/max/kvalifikator/rå tekst)

**Kendt fejl fikses samtidig (præciseret, MM-12):** overlayet er write-only
for de fire rettigheds-fritekstfelter (licens, kildehenvisning,
gengivelsestilladelse, kildenote) — de nulstilles til `''` ved load
(MediaDetaljeOverlay.tsx:54); titel/slags/kunstner/datering/status
præudfyldes allerede. Ny læse-vej henter mediets fakta (fact + valgt
konklusion, filtreret `status='afklaret'`) for BÅDE de 12 nye koder og de 3
eksisterende rettigheds-koder og præudfylder formularen.

**Proveniens-værn (MM-03):** kun ÆNDREDE felter gensendes ved gem — også for
rettighedsfelterne. Gensend af uændret værdi ville oprette ny assertion med
citation "(kilde mangler)" (schema.sql:1179-1181) og degradere proveniensen.

**Skrivning:** pr. ændret felt kaldes `red_upsert_fakta` via den eksisterende
submit-flow (sekventielt awaited). `kilde_url` whitelist-valideres
(`https?://`) før skrivning (MM-11). **DryRun:** `run()` i Redaktion.tsx
læser dryRun fra state — regressionstesten skal ramme netop den wiring
(submitChange kræver eksplicit `opts.dryRun`; en "manglende arg"-test er
umulig, MM-10). Kendt fælde, jf. PR #72.

## §3 Læser-flade (Lightbox/billedside)

- **Kreditlinje vises altid når udfyldt** — diskret linje under billedet.
  Juridisk krav ved CC-licenser; må ikke gemmes bag fold.
- **Kilde-URL** som ægte link: "Se hos [institution]" (ny fane,
  `rel="noopener noreferrer"`; kun renderet når URL'en består
  `https?://`-validering, MM-11).
- **Historik-prosa** foldbar under billedet.
- **`alt_tekst`** → `alt`-attribut på thumbnail og lightbox-billede.
- **Teknik / mål / datering** i metadata-linjen (datering-fakt > kolonne).

**Render-stier (MM-05):** thumbs renderes centralt af `MediaThumb` i
`web/src/components/primitives.tsx` (bruges af DetailPanel/ArmsView/
EstatesView) — alt-attributten sættes DÉR, ikke i kalderne. Feedet har egen
pipeline (`feedMedia.ts`/`WebFeedMediaItem` + `FeedMediaStrip`) og
`PresensView` renderer selv — begge skal med. `EmbeddedMedia`
(narrativ-indlejrede billeder) er UDEN FOR SCOPE i denne omgang, inkl.
alt-tekst (egen type/flow — eksplicit afgrænsning).

RLS: efter §1b-skærpelsen er media-fakta anon-læsbare KUN for publicerede
medier — verificeres empirisk (§4).

## §4 Test

- **Vitest (web):** formular præudfyldes fra eksisterende fakta (inkl. de 3
  rettigheds-koder); submit-payloads = kun ændrede felter; tilbagetrukket
  fakt udelades af læsning (status-filter); dryRun-wiring-regressionstest
  (Redaktion-`run()`-niveau, MM-10); læser-visning (kreditlinje, valideret
  link, alt-tekst via `MediaThumb`).
- **`db-verify.sql`:** assert på at de 12 seeds findes + at
  `entitet_offentlig('media', <upubliceret-id>)` er false efter §1b.
- **Empirisk RLS-tjek (efter §1b-migration):** anon kan læse media-fakta for
  et publiceret medie; kan IKKE for et ikke-publiceret. `get_advisors`
  efter DDL.
- **Manuel ende-til-ende:** DDB-eksemplet (Luise Gräfin von Reventlow) —
  upload kopi, udfyld alle felter fra Quellenangabe, verificér læser-visning.

## Uden for scope

- Hotlink-/byte-løse medier (fravalgt — egen kopi er strategien)
- Fuldtekstsøgning i billedhistorik (kan tilføjes senere)
- Automatisk import/parsing af eksterne metadata (fx LIDO/DDB-API)
- Mobil-fladen (web først; mobil er dev-only)
- Alt-tekst på `EmbeddedMedia` (narrativ-indlejrede billeder; eget flow)
- DB-hærdning af `red_upsert_fakta` (vocab-/eksistens-guard, MM-06) og
  unik-constraint på fact-slots (MM-09) — opfølgnings-kandidater, egen PR
- Flytning af fakta ved blød medieflet (v1: bliver på kopien, UI advarer)
