# Medie-metadata-udvidelse — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 12 nye medie-faktatyper (kilde-URL, kreditlinje, historik-prosa m.fl.) hele vejen fra vocab-seeds over redaktør-formular til læser-visning i Lightbox.

**Architecture:** Tilgang A fra spec `docs/superpowers/specs/2026-08-06-medie-metadata-design.md`: ingen DDL på `media` — nye faktatyper i `vocab`, skrivning via eksisterende `red_upsert_fakta`, læsning via direkte selects på `fact`/`assertion`/`conclusion` (samme mønster som `fetchPersonEvidence`). Web-first; mobil er uden for scope.

**Tech Stack:** Postgres/Supabase (SQL-seeds), TypeScript + React (web/), vitest.

> **Revideret 2026-08-06 efter dual-review** (`docs/reviews/medie-metadata-spec-plan-review-2026-08-06.md`,
> MM-01..13): RLS-skærpelse tilføjet (Task 1), status-filter + læse-union (Task 2), engelske
> date-qualifiers + wiring-dryRun-test (Task 3-4), kun-ændrede-felter/URL-validering (Task 4),
> await/refetch/MEDIA_ARTER (Task 5), render-stier omskrevet (Task 6).

## Global Constraints

- Ingen `ALTER TABLE media` — vocab-seeds + én `CREATE OR REPLACE FUNCTION public.entitet_offentlig` (RLS-skærpelse, spec §1b).
- ALLE læsninger af media-fakta filtrerer `conclusion.status='afklaret'` (MM-02).
- Kun ÆNDREDE felter gensendes ved gem — gensend af uændret værdi degraderer proveniens til "(kilde mangler)" (MM-03).
- `date_qualifier`-værdier er de kanoniske engelske: `about`/`before`/`after` (schema.sql:826) (MM-07).
- Faktatype-koder (præcist disse 12): `kilde_url`, `kilde_institution`, `ekstern_objekt_id`, `hentedato`, `fotograf`, `rettighedshaver`, `kreditlinje`, `beskrivelse`, `alt_tekst`, `teknik`, `fysiske_maal`, `datering`.
- Dansk UI-tekst; kode-identifikatorer på dansk følger eksisterende stil (`kildeFritekst`, `maaPubliceres`).
- TDD: failing test før implementering i alle web-tasks.
- Commits: Conventional Commits, dansk beskrivelse, ingen Claude-attribution-footers.
- SQL mod prod er GATED — skrives og verificeres syntaktisk her; kørsel mod prod er separat beslutning (Task 7).
- `datering`-fakt vinder over `media.datering`-kolonnen i al visning.
- Kreditlinje gemmes ORDRET (juridisk tekst) — aldrig sammensat af delfelter.

---

### Task 1: DB — vocab-seeds + RLS-skærpelse + verify-asserts

**Files:**
- Modify: `schema.sql` (efter `overhoved`-seed-blokken, ~linje 985)
- Modify: `db-rls.sql` (`entitet_offentlig`, ~linje 77-89)
- Modify: `db-migrations.sql` (append i bunden)
- Modify: `db-verify.sql` (append asserts)

**Interfaces:**
- Produces: 12 rækker i `vocab (scheme='faktatype')` som Task 2-6 refererer med præcise koder,
  + skærpet `entitet_offentlig` (media-grenen → `media_rettigheder_ok(p_id)`).

- [ ] **Step 1: Seed-blok i schema.sql**

Indsæt efter `overhoved`-seed-blokken:

```sql
-- Medie-metadata (spec docs/superpowers/specs/2026-08-06-medie-metadata-design.md §1).
-- Faktatyper på media-entiteten — ingen kolonner (invariant 2+3). Skrives via red_upsert_fakta.
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','kilde_url',         'Kilde-URL — permalink til billedside hos ekstern kilde'),
  ('faktatype','kilde_institution', 'Kilde-institution / datapartner'),
  ('faktatype','ekstern_objekt_id', 'Institutionens objekt-/inventar-ID'),
  ('faktatype','hentedato',         'Dato mediet blev hentet fra kilden'),
  ('faktatype','fotograf',          'Fotograf af reproduktionen (≠ kunstner/ophavsmand)'),
  ('faktatype','rettighedshaver',   'Rettighedshaver / Rechtewahrnehmung'),
  ('faktatype','kreditlinje',       'Ordret kreditlinje som kilden kræver vist'),
  ('faktatype','beskrivelse',       'Beskrivelse/proveniens-prosa'),
  ('faktatype','alt_tekst',         'Alt-tekst til skærmlæsere'),
  ('faktatype','teknik',            'Teknik/materiale (fx olie på lærred)'),
  ('faktatype','fysiske_maal',      'Fysiske mål (fx 92 × 73 cm)'),
  ('faktatype','datering',          'Datering af værket (fuzzy dato på fact)')
ON CONFLICT (scheme, code) DO NOTHING;
```

- [ ] **Step 2: RLS-skærpelse i db-rls.sql (spec §1b, MM-01)**

I `entitet_offentlig` (db-rls.sql ~77-89) ændres media-grenen — `media` fjernes fra
altid-true-sættet og får egen gren:

```sql
create or replace function public.entitet_offentlig(p_type text, p_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_type = 'person' then public.person_offentlig(p_id)
    when p_type = 'family' then public.family_offentlig(p_id)
    -- media: fakta/noter/relationer følger publiceringsgaten (spec §1b, MM-01).
    -- Redaktionen ser fortsat alt via det additive redaktion_read-lag.
    when p_type = 'media' then public.media_rettigheder_ok(p_id)
    -- det faste ikke-PII-entitetssæt (sted/gods/våben/linje/organisation/begivenhed/kilde/arkiv)
    when p_type in ('place','estate','coat_of_arms','lineage','organisation',
                    'historical_event','source','repository') then true
    else false  -- ukendt/fejlstavet type → fail-closed
  end;
$$;
```

Bevar de eksisterende revoke/grant-linjer uændret under funktionen.

- [ ] **Step 3: Begge blokke i db-migrations.sql**

Append seed-blokken + den nye `entitet_offentlig`-definition i bunden af `db-migrations.sql`
med dato-kommentar `-- 2026-08-06: medie-metadata-faktatyper + RLS-skærpelse (spec §1b)`.

- [ ] **Step 4: Asserts i db-verify.sql**

Append (følg filens eksisterende assert-stil — kig på naboerne og brug samme DO/RAISE-mønster):

```sql
-- Medie-metadata-faktatyper + RLS-skærpelse (2026-08-06)
DO $$
DECLARE v_n int; v_id bigint;
BEGIN
  SELECT count(*) INTO v_n FROM vocab WHERE scheme='faktatype' AND code IN
    ('kilde_url','kilde_institution','ekstern_objekt_id','hentedato','fotograf','rettighedshaver',
     'kreditlinje','beskrivelse','alt_tekst','teknik','fysiske_maal','datering');
  IF v_n <> 12 THEN RAISE EXCEPTION 'medie-metadata-seeds: forventede 12, fandt %', v_n; END IF;
  -- entitet_offentlig gater nu media på publicering (spec §1b): et upubliceret medie skal være mørkt
  SELECT id INTO v_id FROM media WHERE NOT maa_publiceres LIMIT 1;
  IF v_id IS NOT NULL AND entitet_offentlig('media', v_id) THEN
    RAISE EXCEPTION 'entitet_offentlig(media) gater ikke upubliceret medie %', v_id;
  END IF;
  -- ikke-eksisterende medie → fail-closed
  IF entitet_offentlig('media', -1) THEN
    RAISE EXCEPTION 'entitet_offentlig(media, -1) burde være false';
  END IF;
END $$;
```

- [ ] **Step 5: Lokal verifikation**

Hvis lokal prod-kopi kører (`psql`-adgang, jf. memory lokal-db-testbase): kør seed-blok +
`entitet_offentlig`-definitionen + begge asserts mod den, og verificér at et publiceret
medies fakta stadig er læsbare via anon-rolle-simulering. Ellers: omhyggelig gennemlæsning
+ notér "ikke kørt lokalt" i commit-body.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-rls.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): medie-metadata-faktatyper + RLS-gate på media-fakta"
```

---

### Task 2: Web-datalag — `fetchMediaFakta` (delt læsning, anon-venlig)

**Files:**
- Modify: `web/src/data/media.ts`
- Test: `web/src/data/__tests__/mediaFakta.test.ts` (ny)

**Interfaces:**
- Produces:
  ```ts
  // SKRIVE-whitelist (12 nye koder — de 3 rettigheds-koder skrives fortsat via red_set_media_rettigheder):
  export const MEDIA_FAKTATYPER = ['kilde_url','kilde_institution','ekstern_objekt_id','hentedato',
    'fotograf','rettighedshaver','kreditlinje','beskrivelse','alt_tekst','teknik','fysiske_maal','datering'] as const;
  // LÆSE-union (MM-03): 12 + de 3 eksisterende rettigheds-koder, så overlayet kan præudfylde dem:
  export const MEDIA_FAKTA_LAES = [...MEDIA_FAKTATYPER, 'licens', 'kildehenvisning', 'gengivelsestilladelse'] as const;
  export type MediaFaktatype = typeof MEDIA_FAKTATYPER[number];
  export type MediaFaktaLaesKode = typeof MEDIA_FAKTA_LAES[number];
  export type MediaFaktaVaerdi = { factId: string; vaerdi: string | null;
    dateMin: string | null; dateMax: string | null; dateQualifier: string | null; dateRaw: string | null };
  export type MediaFakta = Partial<Record<MediaFaktaLaesKode, MediaFaktaVaerdi>>;
  export function joinMediaFakta(facts: …, assertions: …, conclusions: …): Map<string, MediaFakta>; // ren, testbar
  export async function fetchMediaFakta(mediaIds: number[]): Promise<Map<string, MediaFakta>>; // nøgle = String(mediaId)
  ```
- Consumes: Task 1's faktatype-koder.

Læse-mønster kopieres fra `redaktionRead.ts` `fetchPersonEvidence` (linje 129-142): `fact`-select på
`subjekt_type='media'` + `in('subjekt_id', mediaIds)` + `in('faktatype', MEDIA_FAKTA_LAES)`, derefter
`assertion`/`conclusion` på `target_type='fact'` + `in('target_id', factIds)`. **Conclusion-selecten
SKAL medtage `status` og filtrere `.eq('status','afklaret')` (MM-02)** — `red_tilbagetraek_fakta`
beholder `valgt_assertion_id` (schema.sql:1379-1380), så uden filteret vises "fjernede" værdier
fortsat. Gældende værdi = assertion udpeget af `conclusion.valgt_assertion_id`; fact uden afklaret
konklusion udelades. RLS afgør synlighed (efter Task 1: anon ser kun publicerede mediers fakta).

- [ ] **Step 1: Failing test for ren join-funktion**

```ts
// web/src/data/__tests__/mediaFakta.test.ts
import { describe, it, expect } from 'vitest';
import { joinMediaFakta } from '../media';

describe('joinMediaFakta', () => {
  it('samler valgt assertion pr. faktatype pr. medie', () => {
    const out = joinMediaFakta(
      [{ id: 10, subjekt_id: 5, faktatype: 'kreditlinje' }],
      [{ id: 100, target_id: 10, vaerdi_tekst: 'Luise … | Lizenz: CC BY-SA 4.0', date_min: null, date_max: null, date_qualifier: null, date_raw: null }],
      [{ target_id: 10, valgt_assertion_id: 100 }],
    );
    expect(out.get('5')?.kreditlinje?.vaerdi).toContain('Lizenz');
    expect(out.get('5')?.kreditlinje?.factId).toBe('10');
  });
  it('udelader fact uden valgt assertion', () => {
    const out = joinMediaFakta([{ id: 10, subjekt_id: 5, faktatype: 'teknik' }], [], []);
    expect(out.get('5')?.teknik).toBeUndefined();
  });
  it('udelader tilbagetrukket fakt (status-filter, MM-02)', () => {
    // fetchMediaFakta filtrerer .eq('status','afklaret') i selecten; join-funktionen skal
    // ALLIGEVEL forsvare sig: en conclusion-række med status !== 'afklaret' ignoreres.
    const out = joinMediaFakta(
      [{ id: 10, subjekt_id: 5, faktatype: 'fotograf' }],
      [{ id: 100, target_id: 10, vaerdi_tekst: 'X', date_min: null, date_max: null, date_qualifier: null, date_raw: null }],
      [{ target_id: 10, valgt_assertion_id: 100, status: 'tilbagetrukket' }],
    );
    expect(out.get('5')?.fotograf).toBeUndefined();
  });
  it('bevarer date-felter på datering', () => {
    const out = joinMediaFakta(
      [{ id: 11, subjekt_id: 5, faktatype: 'datering' }],
      [{ id: 101, target_id: 11, vaerdi_tekst: 'ca. 1840', date_min: '1835-01-01', date_max: '1845-12-31', date_qualifier: 'ca', date_raw: 'ca. 1840' }],
      [{ target_id: 11, valgt_assertion_id: 101 }],
    );
    expect(out.get('5')?.datering?.dateMin).toBe('1835-01-01');
  });
});
```

- [ ] **Step 2: Kør test — forvent FAIL** (`npm run test -w web -- mediaFakta`) med "joinMediaFakta is not exported".

- [ ] **Step 3: Implementér `joinMediaFakta` + `fetchMediaFakta` i `media.ts`**

`joinMediaFakta` er ren (ingen supabase); `fetchMediaFakta` henter rows (guard: tom input → tom Map, spring queries over) og delegerer til join. Typér raw-rows lokalt som i filens `RawMediaRow`-stil.

- [ ] **Step 4: Kør test — forvent PASS.**

- [ ] **Step 5: Commit** — `feat(web): fetchMediaFakta — delt læsning af medie-fakta`

---

### Task 3: redaktionWrite — ny art `mediaFakta`

**Files:**
- Modify: `web/src/data/redaktionWrite.ts` (art-union ~linje 39, buildRpc-kæden ved `mediaRettigheder`-grenen ~linje 435)
- Test: `web/src/data/__tests__/redaktionWrite.test.ts` (udvid)

**Interfaces:**
- Consumes: `MEDIA_FAKTATYPER`, `MediaFaktatype` fra `media.ts` (Task 2).
- Produces: art `'mediaFakta'` med change-form:
  ```ts
  { art: 'mediaFakta', subjektType: string, subjektId: string, mediaId: string,
    payload: { faktatype: MediaFaktatype, vaerdi: string,
               dateMin?: string|null, dateMax?: string|null, dateQualifier?: string|null, dateRaw?: string|null,
               kildeFritekst?: string|null } }
  ```
  → `{ fn: 'red_upsert_fakta', args: { p_subjekt_type: 'media', p_subjekt_id: <mediaId som number>, p_faktatype, p_vaerdi, p_date_min?, p_date_max?, p_date_qualifier?, p_date_raw?, p_kilde_fritekst? } }`.
  Fjernelse af et felt genbruger EKSISTERENDE art `'tilbagetraekFakta'` (factId fra `MediaFaktaVaerdi.factId`) — ingen ny kode.

Regler i buildRpc-grenen: afvis (returnér `null`) hvis `mediaId` mangler, `vaerdi` er tom/blank, eller `faktatype` ikke er i `MEDIA_FAKTATYPER` (whitelist — klienten må ikke kunne skrive vilkårlige faktatyper på media; de 3 rettigheds-koder er BEVIDST ikke med). `kilde_url` afvises hvis værdien ikke matcher `/^https?:\/\//i` (MM-11). Date-args sendes kun når udfyldt; `dateQualifier` valideres mod de kanoniske engelske værdier `about`/`before`/`after` (schema.sql:826, MM-07). For `hentedato`/`datering` uden eksplicitte date-felter: sæt `p_date_raw = vaerdi` (samme konvention som person-DATE_FELT, linje 240).

- [ ] **Step 1: Failing tests**

```ts
// i redaktionWrite.test.ts — følg filens eksisterende buildRpc-testmønster
it('mediaFakta mapper til red_upsert_fakta på media-subjekt', () => {
  const rpc = buildRpc({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
    payload: { faktatype: 'kilde_url', vaerdi: 'https://www.deutsche-digitale-bibliothek.de/item/H4Z…' } });
  expect(rpc).toEqual({ fn: 'red_upsert_fakta', args: {
    p_subjekt_type: 'media', p_subjekt_id: 42, p_faktatype: 'kilde_url',
    p_vaerdi: 'https://www.deutsche-digitale-bibliothek.de/item/H4Z…' } });
});
it('mediaFakta afviser ukendt faktatype', () => {
  expect(buildRpc({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
    payload: { faktatype: 'levende', vaerdi: 'x' } })).toBeNull();
});
it('mediaFakta datering sætter p_date_raw og date-felter (kanoniske engelske qualifiers)', () => {
  const rpc = buildRpc({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
    payload: { faktatype: 'datering', vaerdi: 'ca. 1840', dateMin: '1835-01-01', dateMax: '1845-12-31', dateQualifier: 'about' } });
  expect(rpc?.args).toMatchObject({ p_date_raw: 'ca. 1840', p_date_min: '1835-01-01', p_date_max: '1845-12-31', p_date_qualifier: 'about' });
});
it('mediaFakta afviser ugyldig qualifier og ikke-http(s) kilde_url', () => {
  expect(buildRpc({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
    payload: { faktatype: 'datering', vaerdi: '1840', dateQualifier: 'ca' } })).toBeNull();
  expect(buildRpc({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
    payload: { faktatype: 'kilde_url', vaerdi: 'javascript:alert(1)' } })).toBeNull();
});
// NB (MM-10): submitChange kræver eksplicit opts.dryRun (redaktionWrite.ts:564) — en
// "manglende arg"-test er umulig. DryRun-regressionen testes i stedet på Redaktion-wiring
// (Task 5 Step 3): run() skal sende state-dryRun videre for mediaFakta-arten som for alle andre.
```

(NB: buildRpc hedder muligvis noget andet internt — brug det navn den eksisterende testfil importerer.)

- [ ] **Step 2: Kør — forvent FAIL.**
- [ ] **Step 3: Implementér grenen** (placeres ved de andre media-arter, ~linje 455).
- [ ] **Step 4: Kør — forvent PASS. Kør hele `redaktionWrite.test.ts`.**
- [ ] **Step 5: Commit** — `feat(web): mediaFakta-skriveart → red_upsert_fakta`

---

### Task 4: MediaDetaljeOverlay — nye feltgrupper + præudfyld

**Files:**
- Modify: `web/src/components/MediaDetaljeOverlay.tsx`
- Test: `web/src/components/__tests__/MediaDetaljeOverlay.test.tsx` (udvid)

**Interfaces:**
- Consumes: `MediaFakta`, `MediaFaktatype`, `MEDIA_FAKTATYPER` (Task 2).
- Produces: nye props:
  ```ts
  fakta?: MediaFakta;            // undefined = henter stadig
  onGemFakta: (changes: { faktatype: MediaFaktatype, vaerdi: string,
    dateMin?: string|null, dateMax?: string|null, dateQualifier?: string|null }[],
    kildeFritekst: string) => void;
  onFjernFakta: (factId: string) => void;  // wiring: tilbagetraekFakta
  ```

UI-struktur (ny sektion "Kilde og beskrivelse" mellem Metadata- og Rettigheder-sektionerne, samme visuelle stil):

- *Kilde:* `kilde_url` (input, type=url), `kilde_institution`, `ekstern_objekt_id`, `hentedato` (input type=date → vaerdi=ISO-dato)
- *Ophav:* `fotograf`, `rettighedshaver`
- *Kreditlinje:* `kreditlinje` (textarea 2 rækker — ordret juridisk tekst, hjælpetekst "Indsæt institutionens krævede kreditlinje ordret")
- *Beskrivelse:* `beskrivelse` (textarea 4 rækker), `alt_tekst` (input)
- *Fysisk:* `teknik`, `fysiske_maal`
- *Datering (værk):* `vaerdi` (rå tekst) + `dateMin`/`dateMax` (type=date) + `dateQualifier` (select: tom/`about`/`before`/`after` — kanoniske engelske værdier, schema.sql:826 (MM-07); danske labels i UI: "ca."/"før"/"efter")
- Fælles `Kildenote`-input (kildeFritekst) + én "Gem kilde & beskrivelse"-knap, disabled når ingen ændringer.
- Pr. felt med eksisterende fakt: lille "Fjern"-knap → `onFjernFakta(factId)`.
- `kilde_url`-inputtet viser valideringsfejl og udelukkes fra gem-payload hvis værdien ikke matcher `/^https?:\/\//i` (MM-11).
- Flet-advarselsteksten ("Blød flet flytter tilknytninger…", linje 177) udvides: "…Metadata-fakta på kopien flyttes ikke og bliver stående." (MM-04).

Adfærd:
- Præudfyld fra `fakta`-prop i `useEffect` (dependency: `media.id`, `fakta`) — fixer write-only-fejlen for de fire rettigheds-fritekstfelter (præcisering MM-12: titel/slags/kunstner/datering/status præudfyldes allerede i dag; kun licens/kildehenvisning/gengivelsestilladelse/kildenote nulstilles). `MediaFakta`-typen dækker læse-unionen `MEDIA_FAKTA_LAES` (Task 2), så `fakta.licens` m.fl. typechecker (MM-03).
- "Gem"-payload = KUN ændrede felter (diff mod `fakta`-prop, samme mønster som `metadataPayload` linje 61-65). **Gælder OGSÅ rettighedsfelterne (MM-03):** "Gem rettigheder"-payloaden må kun medtage licens/kildehenvisning/gengivelsestilladelse når de er ÆNDREDE ift. `fakta`-prop — gensend af uændret værdi opretter ny assertion med citation "(kilde mangler)" og degraderer proveniensen.
- Tømt felt der havde værdi → medtag IKKE i gem-payload; fjernelse sker eksplicit via Fjern-knappen (undgår utilsigtet tilbagetræk).

- [ ] **Step 1: Failing tests**

```tsx
it('præudfylder kilde-felter fra fakta-prop', () => {
  render(<MediaDetaljeOverlay media={m} fakta={{ kilde_url: { factId: '10', vaerdi: 'https://x', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null } }} … />);
  expect(screen.getByLabelText('Kilde-URL')).toHaveValue('https://x');
});
it('Gem sender kun ændrede felter', async () => { /* udfyld fotograf, klik Gem, forvent onGemFakta([{faktatype:'fotograf',vaerdi:'Sönke Ehlert'}], '') */ });
it('Fjern kalder onFjernFakta med factId', async () => { /* … */ });
it('gamle rettighedsfelter præudfyldes fra fakta', () => { /* licens vises fra fakta.licens */ });
it('Gem rettigheder sender IKKE uændrede fritekstfelter (MM-03)', async () => {
  /* fakta.licens præudfyldt, kun status ændres, klik "Gem rettigheder" →
     onGemRettigheder-payload UDEN licens/kildehenvisning/gengivelsestilladelse */
});
it('ugyldig kilde_url giver fejl og udelades af payload (MM-11)', async () => { /* … */ });
```

Brug `getByLabelText` — kræver at nye inputs får rigtige `<label htmlFor>`-koblinger (de eksisterende bruger div-labels; nye felter SKAL bruge ægte label-elementer, jf. tilgængelighed).

- [ ] **Step 2: Kør — forvent FAIL.**
- [ ] **Step 3: Implementér sektionen.**
- [ ] **Step 4: Kør hele MediaDetaljeOverlay-suiten — forvent PASS.**
- [ ] **Step 5: Commit** — `feat(web): kilde/beskrivelse/kreditlinje-felter i medie-overlay + præudfyld`

---

### Task 5: Redaktion.tsx — wiring

**Files:**
- Modify: `web/src/Redaktion.tsx` (overlay-instansen ~linje 1625-1650 + state/hentning ved åbning)
- Test: `web/src/__tests__/` — kun hvis eksisterende Redaktion-tests dækker overlay-wiring; ellers dækkes adfærden af Task 4-tests + manuel test (notér i commit).

**Interfaces:**
- Consumes: `fetchMediaFakta` (Task 2), art `'mediaFakta'` (Task 3), props fra Task 4.

- [ ] **Step 1: Hent fakta når overlay åbnes** — state `mediaFakta`, effekt på `mediaDetalje`-ændring: `fetchMediaFakta([Number(m.id)])` → `.get(m.id)`; nulstil ved luk. Effekten SKAL have cleanup-guard (`let aktiv = true; … return () => { aktiv = false; }`) så et hurtigt medie-skift ikke skriver stale fakta ind (MM-08).
- [ ] **Step 2: `MEDIA_ARTER` + wiring (MM-08):**

Tilføj `'mediaFakta'` til `MEDIA_ARTER`-sættet (Redaktion.tsx ~637-647) så medie-refetch-logikken i `run()` fyrer.

```tsx
fakta={mediaFakta}
onGemFakta={async (changes, kildeFritekst) => {
  // Sekventielt awaited (MM-08): parallelle run() giver delvise opdateringer + race om resultatpanelet.
  for (const ch of changes) {
    await run({ art: 'mediaFakta', subjektType: mediaDetalje.subjektType,
      subjektId: mediaDetalje.subjektId, mediaId: m.id,
      payload: { ...ch, kildeFritekst: kildeFritekst || null } }, `Gem ${ch.faktatype}`);
  }
  if (!dryRun) await refetchMediaFakta(); // overlayet viser gemte værdier
}}
onFjernFakta={async (factId) => {
  await run({ art: 'tilbagetraekFakta', subjektType: mediaDetalje.subjektType,
    subjektId: mediaDetalje.subjektId, factId }, 'Fjern medie-fakt');
  if (!dryRun) await refetchMediaFakta(); // generisk art → ingen automatisk media-refetch (MM-08)
}}
```

(Verificér `run`/`tilbagetraekFakta`-changens præcise form mod eksisterende brug i filen — kopiér nabobrug frem for at opfinde. `refetchMediaFakta` = samme kald som Step 1's hentning.)

- [ ] **Step 3: DryRun-wiring-regressionstest (MM-10, erstatter Task 3's umulige test):** test på Redaktion-niveau (eller udtræk `run`-kaldets arg-bygning til testbar funktion) at en `mediaFakta`-change sendes med `{ dryRun: <state> }` — dry-run-state respekteres, ingen hardkodet `false` (PR #72-fælden).
- [ ] **Step 4: `npm run test -w web` fuld suite — forvent PASS.** Manuel røgtest i `npm run dev -w web` mod prod (læs-kun: åbn overlay, se felter; gem KUN via dry-run).
- [ ] **Step 5: Commit** — `feat(web): wiring af medie-fakta i redaktionen`

---

### Task 6: Læser-visning — Lightbox + alt-tekster

**Files (MM-05 — render-stier verificeret mod faktiske call-sites):**
- Modify: `web/src/data/media.ts` (`MediaItem` + `loadMediaItems`/`fetchPersonMedia`/`fetchObjectMedia` beriges, `mediaCaption`)
- Modify: `web/src/components/Lightbox.tsx`
- Modify: `web/src/components/primitives.tsx` — `MediaThumb` (~linje 57) sætter alt-attributten ÉT sted; dækker DetailPanel/ArmsView/EstatesView uden at røre kalderne
- Modify: `web/src/data/feedMedia.ts` + `web/src/components/feed/FeedMediaStrip.tsx` — feedets separate `WebFeedMediaItem`-pipeline beriges med `altTekst` (mindst); genbrug `fetchMediaFakta`
- Modify: `web/src/components/PresensView.tsx` (~linje 183) — egen medie-rendering, alt-attribut dér
- Test: `web/src/components/__tests__/Lightbox.test.tsx` (ny/udvid), `web/src/data/__tests__/mediaFakta.test.ts` (mediaCaption-precedens), `MediaThumb`-alt-test i primitives-testfil (findes én — ellers ny)

**Interfaces:**
- Consumes: `fetchMediaFakta` (Task 2).
- Produces:
  ```ts
  // MediaItem udvides:
  export type MediaItem = { …eksisterende…,
    altTekst: string | null; kreditlinje: string | null; kildeUrl: string | null;
    kildeInstitution: string | null; beskrivelse: string | null;
    teknik: string | null; fysiskeMaal: string | null; dateringFakt: string | null };
  // LightboxItem udvides tilsvarende (alle felter valgfrie — bagudkompatibelt).
  ```

Adfærd:
- Berigelse: i den fælles hale af `fetchPersonMedia`/`fetchObjectMedia` (og redaktionens `mediaFromRelPairs` i `redaktionRead.ts` hvis det er gratis — ellers udelad, redaktøren har overlayet) kaldes `fetchMediaFakta(mediaIds)` batched parallelt med de eksisterende queries; felterne mappes ind. `dateringFakt = datering-faktens dateRaw ?? vaerdi`.
- `mediaCaption`: brug `dateringFakt ?? datering` (fakt vinder, Global Constraint).
- Lightbox: `alt={m.altTekst || m.titel || 'billede'}`; under caption: kreditlinje (altid synlig når udfyldt, `fontSize` ~12, `T.muted3`); "Se hos {kildeInstitution || 'kilden'} ↗"-link — renderes KUN når `kildeUrl` matcher `/^https?:\/\//i` (MM-11) (`target="_blank"`, `rel="noopener noreferrer"`, stopPropagation så overlay ikke lukker); beskrivelse bag `<details><summary>Om billedet</summary>…</details>` (native fold — ingen ny state).
- Thumb-`alt` centralt i `MediaThumb` (primitives.tsx): `alt={m.altTekst || m.titel || m.slags || 'billede'}` — én ændring dækker alle MediaItem-gallerier (MM-05).
- Feed: `feedMedia.ts`-mapningen medtager `altTekst`; `FeedMediaStrip` bruger den som `alt`.
- `PresensView`: samme alt-mønster på dens egen `<img>`.
- Embedded narrativ-billeder (`EmbeddedMedia`) er UDEN FOR SCOPE inkl. alt-tekst (spec-afgrænsning; notér i commit).

- [ ] **Step 1: Failing tests**

```tsx
// Lightbox.test.tsx
it('viser kreditlinje når udfyldt', () => {
  render(<Lightbox items={[{ id: '1', url: 'u', titel: 'T', kreditlinje: 'Luise … | Lizenz: CC BY-SA 4.0' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
  expect(screen.getByText(/Lizenz: CC BY-SA 4.0/)).toBeInTheDocument();
});
it('kilde-link åbner eksternt', () => { /* href, target=_blank, rel indeholder noopener */ });
it('alt-tekst foretrækkes over titel', () => { /* altTekst sat → img alt=altTekst */ });
it('beskrivelse ligger i details-fold', () => { /* getByText('Om billedet') */ });
// mediaCaption-precedens (data-test):
it('mediaCaption bruger dateringFakt før datering', () => {
  expect(mediaCaption({ titel: 'T', kunstner: null, datering: '1900', dateringFakt: 'ca. 1840' })).toContain('ca. 1840');
});
```

- [ ] **Step 2: Kør — forvent FAIL.**
- [ ] **Step 3: Implementér** (media.ts først, så Lightbox, så alt-attributter).
- [ ] **Step 4: Fuld web-suite — forvent PASS (678+ tests).**
- [ ] **Step 5: Commit** — `feat(web): kreditlinje, kildelink, beskrivelse og alt-tekst i læser-visning`

---

### Task 7: Prod-gated verifikation (kørsel kræver eksplicit go)

**Files:**
- Ingen kodeændringer — runbook-afsnit tilføjes i PR-beskrivelsen.

- [ ] **Step 1: Seeds + RLS-skærpelse mod prod** — `db-migrations.sql`-blokken (seeds + ny `entitet_offentlig`) via Supabase MCP `apply_migration`; derefter `db-verify.sql`-assertens DO-blok + `get_advisors(security)` (OBLIGATORISK — migrationen indeholder ægte DDL: CREATE OR REPLACE FUNCTION).
- [ ] **Step 2: Empirisk RLS-tjek (nu meningsfuld efter skærpelsen)** — med anon-nøgle: REST-select `fact?subjekt_type=eq.media&subjekt_id=eq.<publiceret-id>` → rækker; samme for et upubliceret medie → tomt. VIGTIG regression: eksisterende publicerede mediers fakta (licens m.fl.) skal stadig komme tilbage. Dokumentér alle tre i PR.
- [ ] **Step 3: Manuel E2E (DDB-casen)** — upload kopi af Luise Gräfin von Reventlow-billedet, udfyld alle felter fra Quellenangabe (kunstner: Rahl, Carl; fotograf: Sönke Ehlert; rettighedshaver + institution: Schleswig-Holsteinische Landesbibliothek — Landesgeschichtliche Sammlung; licens: CC BY-SA 4.0; kilde-URL: DDB-permalink; kreditlinje: ordret), publicér, verificér læser-visning anonymt.
- [ ] **Step 4: Draft-PR** — `gh pr create --draft`, spec+plan linket, testplan med Step 1-3 som checkliste.

---

## Selv-review (kørt; revideret efter dual-review)

- **Spec-dækning:** §1→Task 1, §1b→Task 1 (RLS) + Task 7, §2→Task 2-5, §3→Task 6, §4→spredt i tasks + Task 7. Fuzzy datering: Task 3 (payload) + Task 4 (UI) + Task 6 (visningsprecedens). Write-only-fixet (præciseret MM-12): Task 4.
- **Typer:** `MediaFakta` (over `MEDIA_FAKTA_LAES`)/`MediaFaktatype`/`fetchMediaFakta` defineret i Task 2, konsumeret med samme navne i 3-6.
- **Review-fund indarbejdet:** MM-01 (Task 1 RLS), MM-02 (Task 2 status-filter + spec-livscyklus), MM-03 (læse-union + kun-ændrede-felter), MM-04 (flet-advarsel Task 4 + spec), MM-05 (Task 6 render-stier), MM-07 (engelske qualifiers), MM-08 (await/refetch/MEDIA_ARTER Task 5), MM-10 (dryRun-wiring-test Task 5), MM-11 (URL-validering Task 3/4/6). MM-06/MM-09 = uden for scope (spec-noteret).
