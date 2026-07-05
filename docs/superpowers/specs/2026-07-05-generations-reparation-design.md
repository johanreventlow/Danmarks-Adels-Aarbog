# Design: Generations-reparation af stamtræet

**Dato:** 2026-07-05
**Status:** Design — afventer bruger-review før implementeringsplan
**Worktree/branch:** `feat/generation-reparation`
**Reviewet af:** Claude (advisor-gate) + Codex (5 HIGH + 2 MEDIUM + 1 LOW, alle empirisk verificeret mod koden — se §13)

---

## 1. Problem & mål

I de tidligste slægtled af nogle Reventlow-linjer kan Dansk Adels Aarbog **ikke bevise**
forælder-barn-kanterne, men bogen placerer alligevel hver person eksplicit i et **slægtled**
(generation). Stamtræets Kolonner-visning bygger i dag 100 % på beviste forælder-barn-kanter
(`parentsOf`/`childrenOf`), så en person uden bevist forælder falder ud af navigationen — netop de
tidlige, usikre generationer forsvinder.

**Mål:** Når en aner-kant mangler, kan brugeren bladre til **generations-naboerne** — de personer
bogen placerer i samme linjes forrige slægtled — som *ubeviste kandidater*. Generationsnummeret
vises eksplicit. Primær rolle er **hul-reparation** (ikke en selvstændig browse-flade).

## 2. Domæne-fakta (autoritative)

- Slægtled nummereres **pr. linje**: hver af de fem Reventlow-linjer (I–V) starter sin egen
  slægtled-tælling ved 1.
- Bogen bærer et **dobbelt tal** ved gren-headere: "Første (tolvte) slægtled" = 1. i den nye linje,
  12. gennemgående gennem moderlinjen. Begge tal bevares.
- En **gren-stamfar (founder)** findes som **to DB-personrækker** der `collapseSameAs` allerede
  folder til én kanonisk person — fx Conrad = V-1 (lokal 1 / gennem 12) + III-58 (lokal 12 /
  gennem 12). De to rækker er broen mellem linjerne.
- Typografien i `work/raw_full.txt` (hele bogen) er konsistent og maskinlæsbar: 61 standalone
  headers + 72 dobbelt-nummererede "(…) slægtled". Ordinaler er danske ord (Første…Nittende).

## 3. Ikke-mål / bevidst afgrænsning

- **Redaktør-forfremmelse** (gør en generations-nabo til en bevist forælder-kant) er **udskudt** —
  egen fremtidig skive. Feature'en skriver aldrig til evidenslaget.
- **Efterkommer-retningen** (fallback nedad når børn mangler) **udskydes til v2** (bekræftet ved
  bruger-review 2026-07-05). v1 er kun aner-retningen (mekanisk symmetrisk, men fordobler founder-
  tvetydigheden uden at løse den — jf. Codex LOW).
- **Fuld kuld→forælder-opløsning** (map en kuld-markør til den præcise forælder i gen−1) udskydes til
  v2. `kuld` **fanges og persisteres allerede i v1** (billigt fra `segment.py`, besluttet ved
  bruger-review 2026-07-05) og bruges til at **gruppere** fallback-ringen — den fulde parent-
  resolution er v2.

## 4. Datamodel — kolonner, ikke fact

Generation er en **strukturel bog-koordinat pr. udgave** — som `nr`/`linje` — ikke en omstridt
påstand. Den lever derfor som plain kolonner på `person_external_id` (PK `(person_id, source_id)`
→ præcis ét tal-par pr. person pr. kilde), i tråd med den bevidst dokumenterede kolonne-ikke-fact-
undtagelse for `lineage.slaegtsnavn` (schema.sql-kommentar).

```sql
-- schema.sql (source of truth) + db-migrations.sql (idempotent ALTER for deployet base)
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_lokal  INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_gennem INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS kuld             TEXT;
-- NULL = ikke fanget / bogen placerer ikke personen entydigt.
-- kuld = børne-gruppe-markør (romertal) inde i grenen fra segment.py; bevaret som proveniens +
--        til gruppering af fallback-ringen (fuld forælder-opløsning er v2).
```

**Trigger-hærdning (Codex MEDIUM):** `trg_external_id_regen` (AFTER INSERT/UPDATE/DELETE på
`person_external_id`) fyrer i dag `regen_person_visning` på enhver ændring. Generations-kolonnerne
påvirker IKKE `visning_*`-cachen. Indskærp derfor triggerens `UPDATE OF`-liste til kun `linje, nr`
(og `person_id, source_id`), så generations-UPDATE ikke udløser unødig cache-regen. Kolonnerne
indgår i versions-snapshots (`version_pk_registry`) — det er acceptabelt; backfill'en køres som ét
bevidst, fortrydbart `change_set`.

## 5. Datalag — deterministisk backfill (ingen LLM/Opus)

Ren, deterministisk pipeline over `work/raw_full.txt`:

1. **Fix `SLGT_RE`** i `segment.py` så den fanger både `^\s*<ord>\s+slægtled\s*$` og
   `^\s*<ord>\s*\(<ord>\)\s+slægtled\s*$`. Ret samtidig den fejlagtige docstring-påstand om at
   `nr` er globalt (den er **pr. gren** — empirisk bekræftet, se §13-1).
2. **Generationen sættes fra gren-konteksten**, ikke fra børne-henvisningernes romertal. Et
   standalone-header sætter (lokal, gennem) for den aktuelle gren; alle efterfølgende poster i den
   gren arver det indtil næste header. Romertallet i "Tredje slægtled, **I**, nr. 7-9" er en
   **kuld**-markør inde i grenen — det må **aldrig** bruges som `linje` (Codex HIGH, se §13-2).
3. **Dansk ordinal→heltal-tabel** (Første=1 … dæk det observerede spænd + margin). Fælles helper,
   unit-testet mod de faktiske header-linjer.
4. **Producér `(source_id, linje, nr) → (lokal, gennem, kuld)`** og join til `person_external_id`.
   `kuld` tages fra `segment.py`'s eksisterende per-post-felt (de fritstående kuld-romertal inde i
   grenen — IKKE børne-refernes romertal).
   - **Join-nøgle = `(source_id, linje, nr)`** (IKKE `nr` alene — resetter pr. gren).
   - **NULL/ukendt `linje` → karantæne**, ikke match (fail-closed).
   - **Suffiks-varianter** (`15a`/`15b`) deler integer-`nr` og dermed generation; **assertér** at
     alle varianter under samme `(linje, nr)` får samme generation, og **afvis** enhver
     konkurrerende én-til-mange-tildeling.
5. **Skriv til prod via ét versioneret, fortrydbart `change_set`** (projektets standard). Verificér
   **lokalt mod en prod-svarende skema-kopi først** (jf. memory-mønstre), og kør `get_advisors`
   efter DDL.
6. **Idempotens/reload-holdbarhed:** backfill'en skal kunne genkøres efter en `--force-reset`-reload
   (læg den i `post_load_fixup.R`-sporet eller et selvstændigt idempotent script).

## 6. Model-hydrering — generations-koordinater pr. kanonisk person

Codex HIGH: founder-hoppet **kan ikke** implementeres fra den nuværende `Model` — collapse dropper
alias-rækker, `mergedFrom` bærer kun ét `{linje,nr}` uden generation, og `Model.lineage` har kun
linje-koder (hverken lineage-id eller `parent_lineage_id`). Derfor:

1. **Udvid person-external-id-fetchen** (`model.ts` / mobile `load.ts`):
   `select('person_id,source_id,linje,nr,slaegtled_lokal,slaegtled_gennem,kuld')`.
2. **Udvid lineage-fetchen** til `select('id,source_id,kode,navn,parent_lineage_id')` (RawLineage +
   `Model.lineage` får `id` + `parentLineageId`).
3. **Byg en kanonisk-person → koordinat-array** FØR traversal:
   `Map<canonicalId, Array<{ sourceId, linje, lineageId, parentLineageId, lokal, gennem, kuld }>>`,
   hvor `person_id` kanoniseres via `collapseSameAs`' alias-map. Generation **coalesces aldrig** til
   én værdi — en founder bærer bevidst flere linje-medlemskaber med hver sit tal.

## 7. Founder-krydshop (aner-traversal på tværs af linjer)

Ved op-traversal fra en person med lokal gen = 1 i den aktuelle linje L (ingen gen−1 i L):

- Find blandt personens **øvrige linje-medlemskaber** (fra koordinat-arrayet i §6) den linje L′ der
  er **moderlinje** til L via `parent_lineage_id`-kæden **og** har lokal gen > 1. Fortsæt
  traversalen i L′ ved gen−1.
- **Degradér fail-closed:** hop kun når **præcis ét** hierarki-kompatibelt mål findes. Ellers
  **stop uden fallback** (ærlig dødende). Dækker edge-cases: person i 3+ linjer, flere gen>1-
  kandidater, begge linjer gen=1, manglende/uafklaret `samme_som`, karantænet collapse.

## 8. App-lag — fallback-ring (web + mobile, delt ren kerne)

Udvid den rene bygger `buildDirection`/`buildBidirectionalColumns` (`web/src/data/tree.ts` +
`mobile/src/data/selectors.ts`, spejlet):

- Når `parentsOf(model, cur)` giver **tom** ring, byg i stedet en **fallback-ring** =
  alle personer med `slaegtled_lokal = G−1` i **samme linje** (via koordinat-arrayet, in-memory over
  den fulde model). Ved founder (G = 1) anvendes §7-hoppet før ringen bygges.
- Ringen er en **ren read-time projektion**. Den skriver **aldrig** en `relation`-kant.
- **At vælge en kandidat re-ankrer** via den eksisterende historik-frie `onFocus` — samme mekanik
  som et normalt drill. Ingen edge oprettes.
- Cyklus-/karantæne-guard genbruges (`visited`-Set i `buildDirection`).

**Styling & labels** (variant A, bruger-valgt): fallback-ringen har stiplet kant, dæmpet/gul
baggrund og et "muligt slægtled"-tag pr. kort. Kolonne-headeren viser
`N. slægtled · <linje> (M. gennemgående)`. Sproget skal være ærligt: **"slægtled-naboer — ingen
bevist som forælder"**, ikke antyde forældreskab.

## 9. Fallback-ring — semantik & kant-tilfælde

- **Ærlig over-claim-afgrænsning (Codex MEDIUM):** ringen viser HELE generationen i linjen ved
  gen−1 (kan være mange, ikke-ancestrale). Det er bevidst — vi *kan ikke* bevise hvem forælderen er.
  Vis dem som "naboer", og gør labelen utvetydig.
- **Kuld-gruppering (v1):** hvor `kuld` er kendt, **grupperes** fallback-ringen på kuld (billig,
  ærlig strukturering af en lang liste) — uden at påstå at en given kuld er ankerets forælder. Fuld
  kuld→forælder-opløsning er v2.
- **NULL-generation (Codex LOW):** en person uden `slaegtled_lokal` kan ikke understøtte gen−1.
  **Skjul fallback** med en eksplicit "slægtled ukendt"-tilstand frem for at gætte naboskab.
- **Delvist kendt ring (Codex MEDIUM):** v1-triggeren er "**ingen** bevist forælder → fallback".
  Tilfældet "én forælder kendt, én mangler" er sjældnere og **udskudt** — noteret som v2-forfining.

## 10. Test-strategi

- **Rene enheder (høj værdi, deterministiske):** ordinal→tal; `SLGT_RE` mod ægte header-linjer fra
  `raw_full.txt` (både single & dual); backfill-join inkl. NULL-linje-karantæne + suffiks-varianter;
  koordinat-array-byg + kanonisering; `buildDirection`-fallback inkl. founder-hop, ambiguøs-hop-stop,
  cyklus/karantæne, NULL-skjul. Web + mobile spejlet.
- **Risiko-baseret:** datalaget verificeres lokalt mod prod-svarende skema-kopi før prod; `get_advisors`
  efter DDL.
- **Empirisk:** web i browser mod prod (founder folder korrekt over til moderlinjen); mobile i
  simulator/enhed.

## 11. Faser (implementeringsrækkefølge)

- **(a) Datalag:** schema.sql + db-migrations.sql (2 kolonner + trigger-hærdning), `segment.py`-fix,
  ordinal-tabel, backfill-script, lokal verifikation, prod-`change_set`, `get_advisors`.
- **(b) Model-hydrering:** udvid fetch (ext-id + lineage), typer, koordinat-array + kanonisering.
- **(c) Ren kerne:** `buildDirection`-fallback + founder-hop (web+mobile delt logik), fuld unit-dækning.
- **(d) UI web:** fallback-ring-styling + generations-header i Kolonner-visningen; browser-verifikation.
- **(e) UI mobile:** spejlet visning; simulator/enhed-verifikation.

## 12. Afklaret ved bruger-review (2026-07-05)

1. **Efterkommer-retning:** v1 er **kun aner-retningen**; descendants-fallback udskudt til v2.
2. **Kuld-persistering:** `kuld` **fanges og persisteres i v1** (kolonne på `person_external_id`) og
   bruges til at gruppere fallback-ringen; fuld kuld→forælder-opløsning er v2.

## 13. Codex-review-fund og hvordan de er adresseret

1. **HIGH — Join-nøgle:** `nr` reset­ter pr. gren (I:1–133 … V:1–200; 200 distinkte nr for 591
   poster). → Nøgle = `(source_id, linje, nr)`, NULL-linje karantæne (§5.4).
2. **HIGH — "I" i børne-refs = kuld, ikke linje** (ref I-6→"II nr 10" mens mål = I-10). → Generation
   sættes fra gren-kontekst + headers, aldrig fra child-ref-romertal (§5.2).
3. **MEDIUM — Integer-`nr` ikke fuldt identificerende** (15a/15b kollapser). → Assertér samme
   generation for varianter; afvis konflikt (§5.4).
4. **HIGH — Founder-hop umuligt fra nuværende Model** (collapse dropper alias-generation). → Byg
   kanonisk koordinat-array før traversal; coalesce aldrig generation (§6).
5. **HIGH — `parent_lineage_id` ikke hentet i app.** → Hent lineage-hierarki; hop kun ved præcis ét
   kompatibelt mål, ellers stop (§6.2, §7).
6. **MEDIUM — Kolonne-UPDATE-bivirkninger** (regen-trigger + versions-snapshot). → Indskærp trigger
   til `linje,nr`; kør backfill som bevidst `change_set` (§4).
7. **MEDIUM — Hele-generation over-claim + delvist-ring.** → Ærlige "nabo"-labels, cap/grupper;
   delvist-ring udskudt v2 (§9).
8. **LOW — NULL & symmetri.** → Skjul fallback ved NULL; aner-retning først, descendants v2 (§3, §9).
