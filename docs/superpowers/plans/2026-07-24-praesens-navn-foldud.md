# Præsensliste: fold-ud narrativ ved navneklik — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Klik på et navn i Præsenslisten folder en narrativ-boks ud under rækken (i stedet for at navigere væk med det samme); en "Se fuld profil"-knap i boksen er den eneste vej videre til stamtræ-profilen.

**Architecture:** Ren tilføjelse i `web/src/components/PresensView.tsx`. `PresensGrenSektion`/`PresensLinjeSektion` forbliver "dumme" præsentationskomponenter — de kender kun til fire nye, valgfrie props (`erAaben`, `erHenter`, `bioAf`, `onToggle`); al data-hentning (`fetchPersonDetail`) og state (åbne id'er, cache) lever i det øverste `PresensView`-komponent, samme sted `fokusId`/`navneDele` allerede bor.

**Tech Stack:** React 18, TypeScript, Vitest + @testing-library/react, eksisterende `NarrativRenderer`/`fetchPersonDetail` (`web/src/data/public.ts`).

## Global Constraints

- Klik på et navn (personens eget OG en ægtefælles, "· g. m. ...") skal veksle fold-ud, ikke navigere direkte — se spec `docs/superpowers/specs/2026-07-24-praesens-navn-foldud-design.md`.
- Flere rækker skal kunne være foldet ud samtidig og uafhængigt — ingen accordion-lukning.
- Tom/manglende narrativ viser præcis teksten "Ingen biografi registreret" (dæmpet, kursiv).
- Loading-tilstand viser præcis teksten "Henter…".
- "Se fuld profil"-linket skal kalde `onPick`, ALDRIG `onToggle` — det er den eneste tilbageværende vej til `onPickPerson`/`navigateTree`.
- Bio-tekst hentes via den eksisterende `fetchPersonDetail(id, memberIds)` (`web/src/data/public.ts:143`), `memberIds` udledt som i `Folgesvend.tsx:180`: `model.byId[id]?.mergedFrom?.map((m) => m.personId)`.
- Bio caches pr. person-id — gentagne fold-ud/-sammen af samme række må ikke genudløse et fetch-kald.
- `NarrativRenderer`s egne indlejrede person-links (inde i selve bio-teksten) er UÆNDREDE — de kalder fortsat `onPick` direkte, uden fold-ud.
- Ingen ændring af `DetailPanel`, `AboutView`, `EstatesView`, eller andre steder `fetchPersonDetail`/`NarrativRenderer` allerede bruges.
- Eksisterende 6 tests i `PresensView.test.tsx` (og den seneste marginLeft-regressionstest) må fortsat bestå UÆNDREDE — de nye props skal derfor være valgfrie med sikre defaults.

---

### Task 1: Fold-ud narrativ ved navneklik

**Files:**
- Modify: `web/src/components/PresensView.tsx`
- Test: `web/src/components/__tests__/PresensView.test.tsx`

**Interfaces:**
- Consumes: `fetchPersonDetail(id: string, memberIds?: string[]): Promise<PersonDetailData>` (`web/src/data/public.ts`, `PersonDetailData.bio: string`); `NarrativRenderer(props: { tekst: string; onPickPerson: (id: string) => void; linkColor: string; inactiveColor: string })` (`web/src/components/NarrativRenderer.tsx`); `model.byId[id].mergedFrom?: { personId: string; linje: string | null; nr: number | null }[]` (`@daa/core` `Provenance[]`).
- Produces: `PresensGrenSektion`/`PresensLinjeSektion` gain four new optional props — `erAaben?: (id: string) => boolean`, `erHenter?: (id: string) => boolean`, `bioAf?: (id: string) => string | undefined`, `onToggle?: (id: string) => void` — defaulting to `() => false` / `() => false` / `() => undefined` / `() => {}` respectively when omitted.

- [ ] **Step 1: Skriv de fejlende tests først**

Åbn `web/src/components/__tests__/PresensView.test.tsx`. Tilføj `fireEvent` og `useState` til imports øverst:

```tsx
import { useState } from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { vi } from 'vitest';
```

(behold de eksisterende imports af `PresensGrenSektion`, `PresensLinjeSektion`, typerne osv. uændrede).

Tilføj følgende harness + fem tests i BUNDEN af filen (efter den sidste eksisterende test, "navnAfAnker bruges KUN til..."):

```tsx
// ---- Fold-ud narrativ ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md) ----
// PresensGrenSektion er bevidst "dum" og kender ikke til fetchPersonDetail — denne harness
// holder ÆGTE aabne/henter/bio-state (samme mønster PresensView selv bruger) og injicerer sin
// egen hentBio-stub, så testen dækker den rigtige toggle/cache-logik uden at mocke supabase.
function FoldUdHarness(props: { gren: PresensGren; hentBio: (id: string) => Promise<string> }) {
  const { gren, hentBio } = props;
  const [aabne, setAabne] = useState<Set<string>>(new Set());
  const [henter, setHenter] = useState<Set<string>>(new Set());
  const [bio, setBio] = useState<Map<string, string>>(new Map());
  const onToggle = (id: string) => {
    setAabne((prev) => { const next = new Set(prev); if (next.has(id)) next.delete(id); else next.add(id); return next; });
    if (bio.has(id) || henter.has(id)) return;
    setHenter((prev) => new Set(prev).add(id));
    hentBio(id).then((tekst) => {
      setBio((prev) => new Map(prev).set(id, tekst));
      setHenter((prev) => { const next = new Set(prev); next.delete(id); return next; });
    });
  };
  return (
    <PresensGrenSektion
      gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}}
      erAaben={(id) => aabne.has(id)} erHenter={(id) => henter.has(id)} bioAf={(id) => bio.get(id)}
      onToggle={onToggle}
    />
  );
}

test('klik på et navn folder en boks ud med hentet narrativ; klik igen folder den sammen', async () => {
  const hentBio = async (id: string) => (id === 'A' ? 'Anker biografi.' : '');
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  expect(await screen.findByText('Anker biografi.')).toBeTruthy();
  fireEvent.click(screen.getByText('Anker Person'));
  expect(screen.queryByText('Anker biografi.')).toBeNull();
});

test('to forskellige rækker kan være foldet ud samtidig, uafhængigt af hinanden', async () => {
  const hentBio = async (id: string) => `Bio for ${id}.`;
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  fireEvent.click(screen.getByText('Søster Person'));
  expect(await screen.findByText('Bio for A.')).toBeTruthy();
  expect(await screen.findByText('Bio for S.')).toBeTruthy();
});

test('mangler narrativ (tom streng) viser en dæmpet placeholder, ikke en tom boks', async () => {
  const hentBio = async () => '';
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  expect(await screen.findByText('Ingen biografi registreret')).toBeTruthy();
});

test('gentagne fold-ud/-sammen af samme række genhenter ikke bio-teksten', async () => {
  const hentBio = vi.fn(async (id: string) => `Bio for ${id}.`);
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person')); // fold ud (1. hentning)
  await screen.findByText('Bio for A.');
  fireEvent.click(screen.getByText('Anker Person')); // fold sammen
  fireEvent.click(screen.getByText('Anker Person')); // fold ud igen — skal IKKE genhente
  await screen.findByText('Bio for A.');
  expect(hentBio).toHaveBeenCalledTimes(1);
});

test('"Se fuld profil"-linket kalder onPick med personens id, ikke onToggle', () => {
  const onPick = vi.fn();
  render(
    <PresensGrenSektion
      gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={onPick}
      erAaben={(id) => id === 'A'} erHenter={() => false} bioAf={() => 'Anker biografi.'}
      onToggle={() => {}}
    />
  );
  fireEvent.click(screen.getByText('→ Se fuld profil'));
  expect(onPick).toHaveBeenCalledWith('A');
});
```

- [ ] **Step 2: Kør testene og bekræft at de fejler**

Run: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx`
Expected: FAIL — `erAaben`/`erHenter`/`bioAf`/`onToggle` findes ikke som props endnu (TypeScript-fejl eller ingen synlig fold-ud-effekt); "→ Se fuld profil" findes slet ikke i DOM'en.

- [ ] **Step 3: Udvid `PresensGrenSektion` med toggle-interaktion og fold-ud-rendering**

I `web/src/components/PresensView.tsx`, erstat hele den eksisterende `PresensGrenSektion`-funktion (linje 14-104 i den nuværende fil) med:

```tsx
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, kanoniserPresensGrundlag, groupByLinje, samlIds } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode, PresensLinjeGruppe } from '@daa/core';
import {
  fetchPresensGrundlag, fetchPresensNavneDele, formatAnkerNavn, formatAndetNavn,
  type PresensGrundlag, type PresensNavneDele,
} from '../data/presens';
import { fetchPresensLinjer, fetchPresensIntro, type PresensLinjeInfo } from '../data/presensLinjer';
import { fetchPersonDetail } from '../data/public';
import { currentSession, type RedSession } from '../data/auth';
import { NarrativRenderer } from './NarrativRenderer';
import { T } from '../theme';

// Ren gren-sektion — eksporteret til test. navnAf/aarAf holder Model ude af renderingen.
// navnAfAnker (valgfri, default=navnAf) navngiver KUN grenens hovedrække (dybde 0, gren.ankerBlok)
// efter bogens hovedrække-format (fulde fornavne + titel inde i navnet + efternavn); alle øvrige
// rækker (søskende, efterkommere, forbindelsesled, partnere) bruger det almindelige navnAf-format
// (Titel + fornavne, uden efternavn) — jf. mekanismen fundet ved bruger-verifikation 2026-07-24.
//
// erAaben/erHenter/bioAf/onToggle (alle valgfri, default = ingen fold-ud nogensinde åben) styrer
// fold-ud-narrativet ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md). Komponenten
// kender bevidst IKKE til fetchPersonDetail — al hentning/cache lever i PresensView, der kalder
// onToggle og læser tilbage via erAaben/erHenter/bioAf. Det holder denne fil testbar uden supabase.
export function PresensGrenSektion(props: {
  gren: PresensGren;
  navnAf: (id: string) => string;
  navnAfAnker?: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  erAaben?: (id: string) => boolean;
  erHenter?: (id: string) => boolean;
  bioAf?: (id: string) => string | undefined;
  onToggle?: (id: string) => void;
  fokusId?: string | null;
}) {
  const {
    gren, navnAf, navnAfAnker = navnAf, aarAf, onPick,
    erAaben = () => false, erHenter = () => false, bioAf = () => undefined, onToggle = () => {},
    fokusId,
  } = props;

  // Fold-ud-boksen under en række — bio-teksten rendres med samme NarrativRenderer som Om-siden/
  // Godser/detaljepanelet (samme typografi, samme klikbare person-links INDE i teksten, som fortsat
  // navigerer direkte via onPick — det er en anden, allerede etableret mekanik, ikke en del af dette
  // fold-ud-lag). "Se fuld profil" er den eneste tilbageværende vej fra Præsenslisten til profilen.
  const renderFoldud = (id: string) => (
    <div style={{ marginTop: 4, marginBottom: 12, paddingLeft: 14, borderLeft: '2px solid rgba(185,160,106,.45)' }}>
      {erHenter(id) ? (
        <div style={{ fontSize: 13, color: T.muted2 }}>Henter…</div>
      ) : (
        <>
          <div style={{ fontFamily: T.serif, fontSize: 14.5, lineHeight: 1.6, color: '#3d382f' }}>
            {bioAf(id) ? (
              <NarrativRenderer tekst={bioAf(id)!} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} />
            ) : (
              <span style={{ fontStyle: 'italic', color: T.muted2 }}>Ingen biografi registreret</span>
            )}
          </div>
          <div
            onClick={() => onPick(id)}
            style={{ marginTop: 6, cursor: 'pointer', color: T.bordeaux, fontSize: 12.5, fontFamily: T.mono, letterSpacing: '.03em' }}
          >
            → Se fuld profil
          </div>
        </>
      )}
    </div>
  );

  // dybde styrer KUN den visuelle indrykning (marginLeft); erAnker styrer navngivningsformatet
  // og er sand PRÆCIST for gren.ankerBlok's egen række — de to var tidligere sammenblandet via
  // "dybde===0", hvilket fejlagtigt gav grupperødder (fx "Søstre") anker-navneformat, når de blev
  // rykket til dybde 0 (bruger-fund 2026-07-24: grupperødder står allerede under egen overskrift
  // og skal derfor IKKE indrykkes yderligere, men skal stadig hedde "Komtesse X", ikke ankerformen).
  //
  // marginLeft er en FAST værdi pr. niveau (0 for roden, ellers 22 — samme indent*22 som
  // mockuppets egen padding-left, jf. Reventlow-praesens.dc.html linje 170), IKKE dybde*22 — børnene
  // renderes som nestede <div>'er (bruger-fund 2026-07-24: afstanden mellem generationer voksede
  // støt jo dybere i træet, fx en 4-5 led lang linje som "Farfars farbror"). Da marginLeft på et
  // nested element regnes relativt til FORÆLDRENS allerede forskudte position, ville dybde*22 lægge
  // barnets fulde absolutte forskydning oveni forælderens — dybde 2 endte fx 66px fra venstre
  // (22 fra forælder + 44 egen), ikke de tilsigtede 44. Nestingen giver akkumuleringen gratis; et
  // fast 22px-tillæg pr. niveau giver derfor korrekt lineær 22/44/66/88-forskydning, som i mockuppet.
  //
  // Navne-spannet indeholder chevronen i sit EGET nested <span> og navnet i sit EGET nested <span>
  // (adskilt fra chevronen) — så det ydre klik-spans textContent er "▸ Navn", men det INDRE
  // navne-span's egen textContent forbliver PRÆCIST "Navn". Det er bevidst: getByText matcher på et
  // elements EGEN textContent, så hvis chevronen lå som ren tekst ved siden af navnet i samme span
  // (uden eget wrapper), ville alle eksisterende getByText('Anker Person')-agtige tests knække.
  const renderNode = (n: PresensNode, dybde: number, erAnker: boolean) => (
    <div key={n.id} style={{ marginLeft: dybde === 0 ? 0 : 22, marginBottom: 2, fontSize: 14.5, lineHeight: 1.5 }}>
      <span
        data-person-id={n.id}
        onClick={() => onToggle(n.id)}
        title={n.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
        style={{
          cursor: 'pointer',
          fontWeight: n.forbindelsesled ? 400 : 600, // bogens fed for levende, normal for forbindelsesled
          fontStyle: n.forbindelsesled ? 'italic' : 'normal', // bogens kursiv for afdøde forbindelsesled
          color: n.forbindelsesled ? T.muted3 : T.ink,
          background: fokusId === n.id ? 'rgba(128,0,32,.08)' : 'transparent',
        }}
      >
        <span aria-hidden style={{ color: T.muted2, fontSize: 10 }}>{erAaben(n.id) ? '▾ ' : '▸ '}</span>
        <span>{erAnker ? navnAfAnker(n.id) : navnAf(n.id)}</span>
      </span>
      {' '}<span style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2 }}>{aarAf(n.id)}</span>
      {n.usikker ? <span style={{ color: T.gold }}> ⚠</span> : ''}
      {n.krydsReference ? <span style={{ fontSize: 12, color: T.muted2 }}> ↗ vist andetsteds i denne gren</span> : ''}
      {n.partnere.filter((p) => p.levende || !n.forbindelsesled).map((p) => (
        <span key={p.id}>
          <span style={{ color: T.muted2, fontSize: 13.5 }}> · g. m. </span>
          <span data-person-id={p.id} onClick={() => onToggle(p.id)} style={{ cursor: 'pointer', color: T.muted, fontSize: 13.5 }}>
            <span aria-hidden style={{ fontSize: 9 }}>{erAaben(p.id) ? '▾ ' : '▸ '}</span>
            <span>{navnAf(p.id)}</span>
          </span>
        </span>
      ))}
      {erAaben(n.id) && renderFoldud(n.id)}
      {n.partnere.filter((p) => erAaben(p.id)).map((p) => <div key={`fu-${p.id}`}>{renderFoldud(p.id)}</div>)}
      {n.boern.map((b) => renderNode(b, dybde + 1, false))}
    </div>
  );
  return (
    <section
      id={gren.anker.gren != null ? `${gren.anker.linje.toLowerCase()}-g${gren.anker.gren}` : undefined}
      style={
        gren.anker.gren != null
          ? { marginTop: 34, borderLeft: '2px solid rgba(185,160,106,.45)', paddingLeft: 26 }
          : { marginBottom: 34 }
      }
    >
      {gren.anker.gren != null && (
        // margin:0 — appen har ingen CSS-reset, så <h2> ellers arver browserens UA-standardmargin
        // og lægger uventet luft oveni sektionens egen border-top/padding-top (reviewfund).
        <h2 style={{ margin: 0, fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.22em', textTransform: 'uppercase', color: T.gold, fontWeight: 500 }}>
          {gren.anker.gren}. gren
        </h2>
      )}
      {renderNode(gren.ankerBlok, 0, true)}
      {gren.grupper.map((gr) => (
        <div key={gr.overskrift + gr.niveau} style={{ marginTop: 26 }}>
          <h3
            title={gr.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
            // margin:0 (samme reviewfund) — kun paddingBottom+marginBottom fra mockuppet skal gælde,
            // ikke <h3>'ens egen UA-standard top-margin oveni det omgivende div's marginTop:26.
            style={{ margin: 0, fontFamily: T.mono, fontSize: 10, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted, borderBottom: '1px solid rgba(34,31,26,.08)', paddingBottom: 6, marginBottom: 10 }}
          >
            {gr.overskrift}{gr.usikker ? ' ⚠' : ''}
          </h3>
          {/* dybde 0 — gruppens egen overskrift (fx "Søstre") giver allerede konteksten, så
              rødderne rykkes ikke yderligere ind (bruger-fund 2026-07-24). */}
          {gr.roedder.map((r) => renderNode(r, 0, false))}
        </div>
      ))}
    </section>
  );
}
```

Bemærk: dette erstatter kun imports-blokken øverst i filen OG hele `PresensGrenSektion`-funktionen — resten af filen (`PresensLinjeSektion`, `PresensView`) redigeres i de næste steps, ikke her.

- [ ] **Step 4: Tråd de fire nye props gennem `PresensLinjeSektion`**

Erstat den eksisterende `PresensLinjeSektion`-funktion med:

```tsx
// Pr.-linje sektion: våben + linjenummer + titel (lineage.navn) + navn (lineage.slaegtsnavn),
// derefter dens grene i rækkefølge (eksporteret til test, samme mønster som PresensGrenSektion).
export function PresensLinjeSektion(props: {
  gruppe: PresensLinjeGruppe;
  info: PresensLinjeInfo | undefined;
  navnAf: (id: string) => string;
  navnAfAnker?: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  erAaben?: (id: string) => boolean;
  erHenter?: (id: string) => boolean;
  bioAf?: (id: string) => string | undefined;
  onToggle?: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gruppe, info, navnAf, navnAfAnker, aarAf, onPick, erAaben, erHenter, bioAf, onToggle, fokusId } = props;
  return (
    <div id={`linje-${gruppe.linje.toLowerCase()}`} style={{ marginTop: 52 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 24, borderTop: `1px solid rgba(34,31,26,.14)`, paddingTop: 26 }}>
        {info?.vaaben?.url && (
          <img src={info.vaaben.url} alt="Linjens våben" style={{ width: 92, height: 'auto', display: 'block', flex: 'none' }} />
        )}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, color: T.bordeaux, lineHeight: 1 }}>{gruppe.linje}</span>
            <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.26em', textTransform: 'uppercase', color: T.ink }}>linje</span>
          </div>
          {info?.titel && (
            <div style={{ fontFamily: T.serif, fontSize: 19, fontStyle: 'italic', color: '#3d382f', marginTop: 8 }}>{info.titel}</div>
          )}
          {info?.slaegtsnavn && (
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.3em', textTransform: 'uppercase', color: T.muted2, marginTop: 6 }}>{info.slaegtsnavn}</div>
          )}
        </div>
      </div>
      {gruppe.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} navnAfAnker={navnAfAnker} aarAf={aarAf} onPick={onPick} erAaben={erAaben} erHenter={erHenter} bioAf={bioAf} onToggle={onToggle} fokusId={fokusId} />
      ))}
    </div>
  );
}
```

- [ ] **Step 5: Kør testene og bekræft at de nye 5 tests + de 6 eksisterende (inkl. marginLeft-regressionstesten) består**

Run: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx`
Expected: PASS — 11 tests i alt (6 eksisterende + 5 nye).

- [ ] **Step 6: Wire data-hentning ind i `PresensView`**

I den samme fil, i `PresensView`-funktionen: tilføj tre nye `useState`-hooks lige efter den eksisterende `navneDele`-state (linje 151 i den nuværende fil), FØR `fokusId`-konstanten:

```tsx
  const [navneDele, setNavneDele] = useState<Record<string, PresensNavneDele>>({});
  // Fold-ud-narrativ ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md): aabne = hvilke
  // person-id'er er foldet ud; bioById = hentet bio-tekst pr. id (tom streng er en gyldig "ingen
  // bio"-værdi, IKKE "endnu ikke hentet" — den skelnen holdes af hentendeIds i stedet); hentendeIds =
  // id'er hvis fetchPersonDetail-kald er undervejs (viser "Henter…", og forhindrer dobbelt-hentning).
  const [aabne, setAabne] = useState<Set<string>>(new Set());
  const [bioById, setBioById] = useState<Map<string, string>>(new Map());
  const [hentendeIds, setHentendeIds] = useState<Set<string>>(new Set());
  const fokusId = (window.history.state as { fokusId?: string } | null)?.fokusId ?? null;
```

Tilføj derefter, lige efter linjen `const aarAf = (id: string) => model!.byId[id]?.years ?? '';` (mod slutningen af filen, efter alle de tidlige `return`-guards — modellen er her garanteret ikke-null, ligesom for `navnAf`/`aarAf`):

```tsx
  const aarAf = (id: string) => model!.byId[id]?.years ?? '';
  const erAaben = (id: string) => aabne.has(id);
  const erHenter = (id: string) => hentendeIds.has(id);
  const bioAf = (id: string) => bioById.get(id);
  const onToggle = (id: string) => {
    setAabne((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
    if (bioById.has(id) || hentendeIds.has(id)) return;
    setHentendeIds((prev) => new Set(prev).add(id));
    const members = model!.byId[id]?.mergedFrom?.map((m) => m.personId);
    fetchPersonDetail(id, members)
      .then((d) => setBioById((prev) => new Map(prev).set(id, d.bio)))
      .catch(() => setBioById((prev) => new Map(prev).set(id, '')))
      .finally(() => setHentendeIds((prev) => { const next = new Set(prev); next.delete(id); return next; }));
  };
```

Til sidst, opdater kaldet af `PresensLinjeSektion` i JSX'en (linje ~278) til at give de fire nye props videre:

```tsx
          {linjer.map((lin) => (
            <PresensLinjeSektion key={lin.linje} gruppe={lin} info={linjeInfo[lin.linje]} navnAf={navnAf} navnAfAnker={navnAfAnker} aarAf={aarAf} onPick={onPickPerson} erAaben={erAaben} erHenter={erHenter} bioAf={bioAf} onToggle={onToggle} fokusId={fokusId} />
          ))}
```

- [ ] **Step 7: Fuld verifikation**

Run: `cd web && npx vitest run`
Expected: alle test-filer består (503 eksisterende + 5 nye = 508).

Run: `cd web && npx tsc --noEmit`
Expected: ingen output (ren).

Run: `cd web && npx vite build`
Expected: build lykkes (samme chunk-size-advarsel som hidtil er OK, ikke en regression).

- [ ] **Step 8: Commit**

```bash
git add web/src/components/PresensView.tsx web/src/components/__tests__/PresensView.test.tsx
git commit -m "$(cat <<'EOF'
feat(praesens): fold narrativ ud ved navneklik i stedet for direkte navigation

Klik på et navn (person eller ægtefælle) veksler nu en fold-ud-boks med
personens narrativ under rækken; et "Se fuld profil"-link i boksen er
den eneste vej videre til stamtræ-profilen. Flere rækker kan være åbne
samtidig. Bio hentes lazy via eksisterende fetchPersonDetail og caches
pr. person-id.

Design godkendt 2026-07-24, se
docs/superpowers/specs/2026-07-24-praesens-navn-foldud-design.md
EOF
)"
```

---

## Self-Review Note (til udførende agent)

Efter Step 8: kør en hurtig manuel gennemgang af diffen mod Global Constraints-listen øverst i denne plan, før branchen betragtes som færdig. Ingen yderligere opgaver i denne plan — funktionen er lille nok til ét sammenhængende task.
