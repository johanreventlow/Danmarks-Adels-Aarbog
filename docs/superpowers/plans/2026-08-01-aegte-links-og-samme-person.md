# Ægte links i web-fladen + tydeligere "Samme person" — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør web-fladens navigation til ægte `<a href>`-links (højreklik → "åbn i nyt vindue", cmd/ctrl-klik, midterklik, tastaturfokus) og gør redaktørens "Samme person"-rækker tydelige og klikbare.

**Architecture:** Én ny primitiv, `web/src/Link.tsx`, renderer et rigtigt `<a href>` og afgiver klikket til browseren ved modifier-/ikke-venstreklik; ellers `preventDefault()` + eksisterende navigations-handler. Alle kaldesteder beholder deres nuværende adfærd ved almindeligt venstreklik — konverteringen tilføjer kun det browseren allerede kunne, hvis elementet havde været et anker.

**Tech Stack:** TypeScript, React 18, Vite, vitest + @testing-library/react (jsdom), inline styles (ingen CSS-framework), hånd-rullet path-router (`web/src/router.ts`).

**Reviewet:** `docs/reviews/aegte-links-plan-review-2026-08-01.md` (egen fase 1 + 1b + Codex adversarial-review, reconciled 2026-08-01). Denne plan er den rettede udgave; alle linjenumre er verificeret mod `origin/main`.

## Global Constraints

- **Sprog:** al UI-tekst, alle kodekommentarer og alle commit-beskeder på dansk med korrekte diakritiske tegn (æ, ø, å).
- **Kun `web/`.** `mobile/` (React Native) har ingen `<a>` og røres ikke i denne plan.
- **Ingen adfærdsændring ved almindeligt venstreklik.** Samme mål, samme state, samme history-semantik (push vs. replace) som i dag. Konverteringen tilføjer udelukkende modifier-/højreklik-adfærd.
- **Ingen `target="_blank"`.** Brugeren vælger selv ny fane via modifier/højreklik.
- **Ingen interaktivt indhold inde i `<a>`.** Rækker/kort der indeholder `<button>` (fx `BookmarkFlag`) eller andre klik-handlers får ankeret på *navnet*, ikke på hele rækken. Interaktivt indhold i et anker er ugyldig HTML og knækker de indlejrede handlers.
- **`stopPropagation` skal ske FØR klikket afgives til browseren.** Ellers navigerer et omsluttende korts `onClick` den aktuelle fane samtidig med at browseren åbner en ny (reproduceret — se review B1).
- **Redaktøren kanoniserer ikke id'er.** `Redaktion.tsx` kører `loadModel({ collapse: false })` og arbejder i skrive-id-rummet. Alle `/redaktion/person/<id>`-hrefs bruger det rå id fra rækken.
- **Ingen fabrikerede links.** Et element får kun et `href` hvis målet faktisk er adresserbart i URL-grammatikken (`web/src/data/nav.ts` + `parseRedaktionPath`). Tilstand der bevidst ligger uden for URL'en (fx Slægtskabsfanens A/B-valg) får intet anker.
- **Kirurgisk diff i `web/src/Redaktion.tsx`.** En parallel session har filen modificeret på branch `feat/union-redigering`. Rør kun de kaldesteder planen navngiver — ingen drive-by-konvertering af filens øvrige `<span onClick>`.
- **Baseline:** 55 testfiler / 637 tests grønne i worktreet før første ændring. Tre af dem SKAL opdateres undervejs (Task 2 og Task 6) fordi de asserterer rollen `button` på elementer der bliver ankre — det er forventet, ikke en regression.
- **Test-kommando:** `npm run test -w web` (vitest). Typecheck: `npx tsc --noEmit -p web/tsconfig.json`. Bemærk at `web/tsconfig.json` har `"exclude": ["src/**/__tests__/**"]` — testfiler typecheckes ikke.

## Filstruktur

| Fil | Ansvar | Handling |
|---|---|---|
| `web/src/Link.tsx` | Anker-primitiv + `isModifiedClick`-prædikat. Routing-infrastruktur, derfor ved siden af `router.ts` — **ikke** i `components/primitives.tsx`, som er Følgesvend-scoped og ikke importeres af `Redaktion.tsx`. | Opret |
| `web/src/__tests__/Link.test.tsx` | Enheds-tests for klik-semantikken | Opret |
| `web/src/data/nav.ts` | URL-grammatik (ren, DOM-fri). Får `personPath`/`estatePath`. | Modificér |
| `web/src/__tests__/nav.test.ts` | Findes (i `src/__tests__/`, ikke `src/data/__tests__/`) | Modificér |
| `web/src/data/sammeSom.ts` | `sammeSomEtiket` — ren, DOM- og Supabase-fri. Kan **ikke** ligge i `Redaktion.tsx` (trækker hele dataflade ind) eller `data/redaktionRead.ts` (importerer `supabase.ts`, som kaster ved modul-load uden env). | Opret |
| `web/src/data/__tests__/sammeSom.test.ts` | Enheds-test for etiketten | Opret |
| `web/src/Redaktion.tsx` | Redaktørbordet: `listRow`, `linkRow`, familie-navne, samme_person, narrativ-preview, beslutnings-link, forældre-konflikt-rækker | Modificér |
| `web/src/components/OcrKildepanel.tsx`, `PersonKvalitetsark.tsx` | "Åbn person"-veje i kvalitetsarket | Modificér |
| `web/src/Folgesvend.tsx` | "Redaktion ↗" + brugerens egen avatar | Modificér |
| `web/src/components/primitives.tsx` | `PersonCard` får valgfrit `href` | Modificér |
| `web/src/components/HomeView.tsx`, `TreeSearch.tsx`, `TreeView.tsx` | Personkort/-noder + "Månedens gods" | Modificér |
| `web/src/components/DetailPanel.tsx`, `NarrativRenderer.tsx`, `BookmarksView.tsx`, `EstatesView.tsx`, `PresensView.tsx` | Detaljepanel, prosa-links, bogmærker, godser, præsensliste | Modificér |
| `web/src/components/feed/FeedStreamView.tsx`, `FeedCardView.tsx`, `PersonFeedCardView.tsx` | Forsidens feed-kort | Modificér |

**Bevidst urørt:**
- `web/src/components/PresensView.tsx:301/307` (`href="#linje-…"` er in-page-ankre — at sende dem gennem `navigate()` ville pushe et fragment som en path).
- `web/src/components/OverviewMapView.tsx:46` — kort-punkter navigerer via kort-rendererens `onPointPress`-callback; rendereren kan ikke levere ankre. **Teknisk undtagelse**, ikke en forglemmelse.
- Hele `mobile/`.

---

### Task 0: Worktree-opsætning

**Files:** ingen kode-ændringer.

- [ ] **Step 1: Installér afhængigheder**

Worktreet har intet `node_modules`; uden det fejler enhver testkørsel på en uløselig
`@testing-library/react`-import.

Run: `npm ci`
Expected: `added ~1248 packages`.

- [ ] **Step 2: Kopiér miljøfilen**

`web/.env.local` er gitignoreret og følger ikke med et nyt worktree. Uden den kaster
`web/src/supabase.ts:7` ved modul-load, og **enhver** test der importerer et data-modul fejler:

```
Error: Mangler VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY.
 ❯ src/supabase.ts:8:9
 ❯ src/data/redaktionRead.ts:1:1
```

Run: `cp <hovedmappe>/web/.env.local web/.env.local`

Filen indeholder kun den offentlige anon-nøgle, er gitignoreret og må ikke committes eller vises.

- [ ] **Step 3: Fastslå baseline**

Run: `npm run test -w web`
Expected: **55 passed (55) test-filer, 637 passed (637) tests.** Afviger tallet, så stop og find ud
af hvorfor før du ændrer noget.

---

### Task 1: `Link`-primitiven + sti-helpers

**Files:**
- Create: `web/src/Link.tsx`
- Create: `web/src/__tests__/Link.test.tsx`
- Modify: `web/src/data/nav.ts:63-65` (efter `pathForMode`)
- Modify: `web/src/__tests__/nav.test.ts`

**Interfaces:**
- Consumes: `navigate` fra `web/src/router.ts` (`navigate(path: string, opts?: { replace?: boolean; state?: unknown }): void`)
- Produces:
  - `isModifiedClick(e: React.MouseEvent): boolean`
  - `Link(props: Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'onClick'> & { href: string; onNavigate?: () => void; stopPropagation?: boolean })`
  - `personPath(id: string): string` → `/person/<id>`
  - `estatePath(id: string): string` → `/estate/<id>`

- [ ] **Step 1: Skriv den fejlende test**

Opret `web/src/__tests__/Link.test.tsx`:

```tsx
// @vitest-environment jsdom
// Bemærk: de tests hvor klikket bevidst IKKE forhindres, får jsdom til at skrive
// "Not implemented: navigation to another Document" til stderr. Det er forventet og beviser
// præcis dét testen tjekker: at browseren fik klikket.
import { render, screen, fireEvent } from '@testing-library/react';
import { vi } from 'vitest';
import { Link, isModifiedClick } from '../Link';

describe('Link', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('renderer et ægte anker med href (det højreklik-menuen læser)', () => {
    render(<Link href="/person/42">Navn</Link>);
    const a = screen.getByText('Navn');
    expect(a.tagName).toBe('A');
    expect(a.getAttribute('href')).toBe('/person/42');
  });

  it('almindeligt venstreklik navigerer i appen og forhindrer browserens egen navigation', () => {
    render(<Link href="/person/42">Navn</Link>);
    // fireEvent returnerer false når preventDefault() blev kaldt.
    expect(fireEvent.click(screen.getByText('Navn'))).toBe(false);
    expect(window.location.pathname).toBe('/person/42');
  });

  it('kalder onNavigate i stedet for navigate(href) når den er sat', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).toHaveBeenCalledTimes(1);
    expect(window.location.pathname).toBe('/'); // appen navigerede ikke selv
  });

  it('lader browseren håndtere cmd-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { metaKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
    expect(window.location.pathname).toBe('/');
  });

  it('lader browseren håndtere ctrl-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { ctrlKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere shift-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { shiftKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere alt-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { altKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere midterklik (button !== 0)', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { button: 1 })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('stopPropagation=true forhindrer at et omsluttende korts onClick også fyrer', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).toHaveBeenCalledTimes(1);
    expect(kortKlik).not.toHaveBeenCalled();
  });

  // Review B1 (BLOCKER): den nemme fejl er at afgive klikket til browseren FØR stopPropagation.
  // Så åbner browseren ny fane MENS kortets onClick navigerer den aktuelle — dobbelt-navigation.
  it('stopPropagation gælder også når browseren overtager klikket (cmd-klik)', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'), { metaKey: true });
    expect(onNavigate).not.toHaveBeenCalled(); // browseren ejer klikket
    expect(kortKlik).not.toHaveBeenCalled();   // ← men kortet må stadig ikke navigere
  });

  it('stopPropagation gælder også når en indre handler allerede har forhindret klikket', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>
          <span onClick={(e) => e.preventDefault()}>Navn</span>
        </Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).not.toHaveBeenCalled();
    expect(kortKlik).not.toHaveBeenCalled();
  });

  it('uden stopPropagation bobler klikket videre til det omsluttende kort', () => {
    const kortKlik = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={vi.fn()}>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(kortKlik).toHaveBeenCalledTimes(1);
  });

  it('et eksplicit target overlades til browseren', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" target="_blank" rel="noreferrer" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'))).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });
});

describe('isModifiedClick', () => {
  const basis = { defaultPrevented: false, button: 0, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false };
  it('er falsk for et rent venstreklik', () => {
    expect(isModifiedClick(basis as never)).toBe(false);
  });
  it('er sand når en indre handler allerede har taget klikket', () => {
    expect(isModifiedClick({ ...basis, defaultPrevented: true } as never)).toBe(true);
  });
});
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- Link`
Expected: FAIL — `Failed to resolve import "../Link"`.

- [ ] **Step 3: Skriv `Link`-primitiven**

Opret `web/src/Link.tsx`:

```tsx
// Ægte links. Al navigation i web-fladen gik tidligere gennem <div onClick>/<span onClick>, hvilket
// koster højreklik → "åbn i nyt vindue", cmd/ctrl-klik, midterklik og tastaturfokus. Denne primitiv
// renderer et rigtigt <a href> og afgiver klikket til browseren når brugeren har bedt om det.
//
// Højreklik (contextmenu) og midterklik (auxclick) fyrer ALDRIG Reacts onClick — de virker i det
// øjeblik elementet har et href, og kræver ingen kode her.
//
// Ligger ved siden af router.ts (routing-infrastruktur), ikke i components/primitives.tsx, som er
// Følgesvend-scoped og ikke importeres af Redaktion.tsx.
import type { AnchorHTMLAttributes, MouseEvent } from 'react';
import { navigate } from './router';

// Skal browserens egen klik-adfærd have forrang? Ja hvis en indre handler allerede har taget
// klikket, hvis det ikke er venstreklik, eller hvis en modifier-tast er nede (ny fane/nyt vindue).
export function isModifiedClick(e: MouseEvent): boolean {
  return e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey;
}

// onNavigate: kaldesteder der gør MERE end at skifte URL (sætter state, kalder afslut(), bruger
// replace frem for push) beholder deres handler her og får modifier-klik oveni. Uden onNavigate
// navigerer Link selv til href.
// stopPropagation: sæt når ankeret sidder inde i et kort der har sin egen onClick.
export function Link({ href, onNavigate, stopPropagation = false, style, target, children, ...rest }:
  Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'onClick'> & {
    href: string;
    onNavigate?: () => void;
    stopPropagation?: boolean;
  }) {
  return (
    <a
      href={href}
      target={target}
      {...rest}
      onClick={(e) => {
        // FØR alt andet: også når browseren overtager klikket, må et omsluttende kort ikke
        // navigere den aktuelle fane — ellers gør et cmd-klik begge dele på én gang.
        if (stopPropagation) e.stopPropagation();
        if (isModifiedClick(e)) return;            // browseren åbner selv ny fane/nyt vindue
        if (target && target !== '_self') return;  // eksplicit ny fane — browseren ejer klikket
        e.preventDefault();
        if (onNavigate) onNavigate();
        else navigate(href);
      }}
      // Ankerets browser-default (blå + understregning) ville bryde designet; farve/dekoration
      // sættes af kaldestedet via style, præcis som de <span>'s der erstattes.
      style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer', ...style }}
    >
      {children}
    </a>
  );
}
```

- [ ] **Step 4: Kør testen og se den bestå**

Run: `npm run test -w web -- Link`
Expected: PASS (15 tilfælde).

- [ ] **Step 5: Skriv den fejlende test for sti-helpers**

Tilføj `personPath, estatePath` til den eksisterende import øverst i `web/src/__tests__/nav.test.ts`:

```ts
import { parseFolgesvendPath, pathForMode, themeOfMode, labelOfMode, detailOpenFor, personPath, estatePath, type Mode } from '../data/nav';
```

og tilføj denne blok i bunden af filen:

```ts
describe('personPath / estatePath', () => {
  it('bygger den dybe-linkbare person-sti', () => {
    expect(personPath('482')).toBe('/person/482');
  });
  it('bygger den dybe-linkbare gods-sti', () => {
    expect(estatePath('7')).toBe('/estate/7');
  });
  it('er den modsatte retning af parseFolgesvendPath', () => {
    // Samme par-invariant som MODE_PATH/PATH_MODE: de to retninger må ikke komme ud af trit.
    expect(parseFolgesvendPath(personPath('482')).personId).toBe('482');
    expect(parseFolgesvendPath(estatePath('7')).estateId).toBe('7');
  });
});
```

- [ ] **Step 6: Kør testen og se den fejle**

Run: `npm run test -w web -- nav`
Expected: FAIL — import-fejl (`personPath` findes ikke).

- [ ] **Step 7: Tilføj sti-helpers**

Indsæt i `web/src/data/nav.ts` umiddelbart efter `pathForMode` (linje 65):

```ts
// De to id-bærende dybe-links. Egne helpers, så et href aldrig håndbygges ved kaldestedet og
// kan drive fra parseFolgesvendPath (samme begrundelse som MODE_PATH/PATH_MODE-tabellen ovenfor).
// Ingen kanonisering her: Folgesvends path-sync-effekt kanoniserer et alias-id ved indlæsning
// (navigate(…, { replace: true })), så et rå id i et href er sikkert.
export function personPath(id: string): string {
  return `/person/${id}`;
}
export function estatePath(id: string): string {
  return `/estate/${id}`;
}
```

- [ ] **Step 8: Kør testen og se den bestå**

Run: `npm run test -w web -- nav`
Expected: PASS

- [ ] **Step 9: Typecheck + fuld web-suite**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: ingen typefejl; 637 + de nye tests grønne.

- [ ] **Step 10: Commit**

```bash
git add web/src/Link.tsx web/src/__tests__/Link.test.tsx web/src/data/nav.ts web/src/__tests__/nav.test.ts
git commit -m "feat(web): Link-primitiv der bevarer browserens egen klik-adfærd

Modifier-, midter- og højreklik skal kunne åbne et link i ny fane. Det
kræver et rigtigt <a href>; app-navigationen overtager kun det rene
venstreklik. stopPropagation sker før klikket afgives, så et omsluttende
kort ikke navigerer den aktuelle fane samtidig."
```

---

### Task 2: Redaktørens person-links bliver ægte

**Files:** (linjenumre verificeret mod `origin/main`)
- Modify: `web/src/Redaktion.tsx` — `listRow` (917-926), narrativ-preview (1308), `linkRow` (1765-1777), partner-navne (1791), børne-kaldet (1806-1814), forældre-navne (1824), beslutnings-link (2047), forældre-konflikt-rækker (2449)
- Modify: `web/src/components/OcrKildepanel.tsx:278-284`
- Modify: `web/src/components/PersonKvalitetsark.tsx:339-341,352-354`
- Modify: `web/src/components/NarrativRenderer.tsx` (nyt valgfrit `hrefFor`-prop)
- Test: `web/src/components/__tests__/NarrativRenderer.test.tsx`, `web/src/components/__tests__/OcrKildepanel.test.tsx:302`

**Interfaces:**
- Consumes: `Link` fra `../Link` / `../../Link`, `personPath` fra `./data/nav`, den eksisterende private `redaktionPath(entity, recordId)` i `Redaktion.tsx:124`
- Produces: `linkRow(navn, meta, onRemove, extra?, onOpen?, href?)` — `href` er nyt 6. argument (alle nuværende kald bruger 3 eller 5 argumenter, så intet brydes); `NarrativRenderer` får `hrefFor?: (id: string) => string` med default `personPath`

- [ ] **Step 1: Skriv den fejlende test for `NarrativRenderer`s href**

Tilføj i `web/src/components/__tests__/NarrativRenderer.test.tsx` inde i `describe('NarrativRenderer', …)`:

```tsx
  it('person-token er et ægte anker med default-sti til publikumsfladen', () => {
    render(<NarrativRenderer tekst="Se [[person:482|Chr. D. R.]] her." onPickPerson={vi.fn()} {...COLORS} />);
    const link = screen.getByText('Chr. D. R.');
    expect(link.tagName).toBe('A');
    expect(link.getAttribute('href')).toBe('/person/482');
  });

  it('hrefFor overstyrer stien (redaktørens preview peger på redaktør-posten)', () => {
    render(
      <NarrativRenderer
        tekst="Se [[person:482|Chr. D. R.]] her."
        onPickPerson={vi.fn()}
        hrefFor={(id) => `/redaktion/person/${id}`}
        {...COLORS}
      />,
    );
    expect(screen.getByText('Chr. D. R.').getAttribute('href')).toBe('/redaktion/person/482');
  });
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- NarrativRenderer`
Expected: FAIL — `expected 'SPAN' to be 'A'`.

- [ ] **Step 3: Gør `NarrativRenderer`s person-tokens til ankre**

I `web/src/components/NarrativRenderer.tsx`, tilføj imports øverst:

```tsx
import { Link } from '../Link';
import { personPath } from '../data/nav';
```

Erstat `renderInline` (linje 12-25):

```tsx
function renderInline(
  segs: Segment[],
  onPickPerson: (id: string) => void,
  linkColor: string,
  inactiveColor: string,
  hrefFor: (id: string) => string,
) {
  return segs.map((s, i) => {
    if (s.kind === 'text') return <span key={i}>{s.text}</span>;
    if (s.maalType === 'person') {
      const id = String(s.maalId);
      return (
        <Link key={i} href={hrefFor(id)} onNavigate={() => onPickPerson(id)}
          style={{ color: linkColor, textDecoration: 'underline' }}>
          {s.label}
        </Link>
      );
    }
    return <span key={i} style={{ color: inactiveColor }}>{s.label}</span>;
  });
}
```

Udvid props-typen (linje 27-32) og destruktureringen (linje 33):

```tsx
export function NarrativRenderer(props: {
  tekst: string;
  onPickPerson: (id: string) => void;
  linkColor: string;
  inactiveColor: string;
  // Hvor person-tokens peger hen. Default er publikumsfladen; redaktøren overstyrer til sin egen
  // record-sti, så et cmd-klik i narrativ-preview'et ikke sender redaktøren over i læser-fladen.
  hrefFor?: (id: string) => string;
}) {
  const { tekst, onPickPerson, linkColor, inactiveColor, hrefFor = personPath } = props;
```

Og kaldet i bunden (linje 87):

```tsx
        return <p key={i} style={{ margin: '0 0 0.6em', whiteSpace: 'pre-line' }}>{renderInline(b.segs, onPickPerson, linkColor, inactiveColor, hrefFor)}</p>;
```

- [ ] **Step 4: Kør testen og se den bestå**

Run: `npm run test -w web -- NarrativRenderer`
Expected: PASS (inkl. de eksisterende tests — `fireEvent.click` på ankeret kalder stadig `onPickPerson('482')`).

- [ ] **Step 5: Konvertér redaktørens kaldesteder**

Tilføj til de eksisterende imports i `web/src/Redaktion.tsx`:

```tsx
import { Link } from './Link';
```

**(a) `listRow` (917-926)** — record-listen i venstre kolonne. Rækkens eneste `tail` er en
ikke-interaktiv `privat`-`span`, så hele rækken må lovligt være ankeret:

```tsx
    const listRow = (o: { id: string; badge: string; label: string; sub: string; round: number | string; tail?: ReactNode }) => (
      <Link key={o.id} href={redaktionPath(entity, o.id)} onNavigate={() => openRecord(entity, o.id)}
        style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 9px', borderRadius: 9, background: o.id === recordId ? '#efe7d7' : 'transparent' }}>
        <span style={{ width: 30, height: 30, borderRadius: o.round, background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{o.badge}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: T.serif, fontSize: 16.5, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.label}</div>
          <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.sub}</div>
        </div>
        {o.tail}
      </Link>
    );
```

**(b) `linkRow` (1765-1777)** — får `href` som 6. parameter. Rækken indeholder ✕, konfidens-chips,
↑↓ og `flyt→`, så kun navnet bliver anker:

```tsx
    // onOpen + href (valgfri, følges ad): gør navnet klikbart → naviger til den person (kun for
    // person-rækker, ikke hverv/godser). Skifter recordId som browse-listen gør; ugemte
    // narrativ-edits kasseres stille — samme adfærd som person-listen (bevidst konsistent, ingen
    // ny advarsel). Ankeret sidder på NAVNET, ikke på rækken: rækken rummer ✕/chips/pile, og
    // interaktivt indhold inde i <a> er ugyldig HTML.
    const linkRow = (navn: string, meta: string, onRemove: () => void, extra?: React.ReactNode, onOpen?: () => void, href?: string) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '8px 11px', marginBottom: 6 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          {onOpen && href ? (
            <Link href={href} onNavigate={onOpen} title="Åbn person"
              style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, lineHeight: 1.05, color: T.bordeaux, display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              {navn}<span style={{ fontSize: 11, opacity: .55 }}>↗</span>
            </Link>
          ) : (
            // Fald-tilbage-grenen beholder onClick: et fremtidigt kaldested der giver onOpen men
            // glemmer href ville ellers tavst miste sin klik-handler (ingen test ville fange det).
            <div onClick={onOpen} title={onOpen ? 'Åbn person' : undefined}
              style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, lineHeight: 1.05, cursor: onOpen ? 'pointer' : 'default', color: onOpen ? T.bordeaux : undefined, display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              {navn}{onOpen && <span style={{ fontSize: 11, opacity: .55 }}>↗</span>}
            </div>
          )}
          {meta && <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2, marginTop: 1 }}>{meta}</div>}
        </div>
        {extra}
        <span onClick={onRemove} title="Fjern" style={{ color: '#bcae93', fontSize: 14, cursor: 'pointer', flex: 'none' }}>✕</span>
      </div>
    );
```

**(c) Børne-rækken (1814)** — tilføj `href` som 6. argument. Linjen

```tsx
                      () => openRecord('person', b.personId));
```

bliver til:

```tsx
                      () => openRecord('person', b.personId), redaktionPath('person', b.personId));
```

**(d) Partner-navne (1791)** — erstat:

```tsx
                          <span onClick={() => openRecord('person', p.personId)} title="Åbn person" style={{ color: T.bordeaux, cursor: 'pointer' }}>{p.navn}</span>
```

med:

```tsx
                          <Link href={redaktionPath('person', p.personId)} onNavigate={() => openRecord('person', p.personId)} title="Åbn person" style={{ color: T.bordeaux }}>{p.navn}</Link>
```

**(e) Forældre-navne (1824)** — erstat:

```tsx
                        <span onClick={() => openRecord('person', f.personId)} title="Åbn person" style={{ color: T.bordeaux, cursor: 'pointer' }}>{f.navn}</span>
```

med:

```tsx
                        <Link href={redaktionPath('person', f.personId)} onNavigate={() => openRecord('person', f.personId)} title="Åbn person" style={{ color: T.bordeaux }}>{f.navn}</Link>
```

**(f) Narrativ-preview (1308)** — peg preview'ets person-tokens på redaktørens egne poster.
`onPickPerson` forbliver en no-op (et almindeligt klik må ikke forlade det ugemte udkast);
cmd-/højreklik åbner posten i en ny fane:

```tsx
              <NarrativRenderer tekst={narrativUdkast.tekst} onPickPerson={() => {}} hrefFor={(id) => redaktionPath('person', id)} linkColor={T.bordeaux} inactiveColor={T.muted2} />
```

**(g) Beslutnings-linket (2047)** — allerede et `<a>`, men med ubetinget `preventDefault`. Erstat:

```tsx
              <a href={decision.route} onClick={(e) => { e.preventDefault(); afslut(); navigate(decision.route); }}
```

med `Link` (bevar resten af elementets attributter og børn uændret, og luk med `</Link>`):

```tsx
              <Link href={decision.route} onNavigate={() => { afslut(); navigate(decision.route); }}
```

**(h) Forældre-konflikt-rækker (2449)** — rækken rummer intet andet klikbart. Erstat:

```tsx
          <div key={r.factId} onClick={() => onOpen(String(r.personId))}
            style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 13px', marginBottom: 8, cursor: 'pointer',
              border: '1px solid rgba(136,26,51,.25)', borderRadius: 10, background: '#faf1dc' }}>
```

med (og luk med `</Link>`):

```tsx
          <Link key={r.factId} href={`/redaktion/person/${r.personId}`} onNavigate={() => onOpen(String(r.personId))}
            style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 13px', marginBottom: 8,
              border: '1px solid rgba(136,26,51,.25)', borderRadius: 10, background: '#faf1dc' }}>
```

- [ ] **Step 6: Konvertér kvalitetsarkets to "åbn person"-veje**

`web/src/components/OcrKildepanel.tsx:278-284` — tilføj `import { Link } from '../Link';` og erstat:

```tsx
          <button
            type="button"
            onClick={() => onOpenPerson(activeRow.personId)}
            style={{ ...secondaryButtonStyle(false), marginTop: 8 }}
          >
            Åbn person
          </button>
```

med:

```tsx
          <Link
            href={`/redaktion/person/${activeRow.personId}`}
            onNavigate={() => onOpenPerson(activeRow.personId)}
            style={{ ...secondaryButtonStyle(false), marginTop: 8, display: 'inline-block' }}
          >
            Åbn person
          </Link>
```

`web/src/components/PersonKvalitetsark.tsx` — samme mønster for **begge** knapper (linje 339-341
og 352-354). Tilføj `import { Link } from '../Link';` og erstat hver

```tsx
        <button
          type="button"
          onClick={() => onOpenPerson(row.personId)}
```

med

```tsx
        <Link
          href={`/redaktion/person/${row.personId}`}
          onNavigate={() => onOpenPerson(row.personId)}
```

(behold hver knaps eksisterende `style` + tekst; luk med `</Link>`). **`onNavigate` er påkrævet** —
`handleKvOpenPerson` (`Redaktion.tsx:305`) gør mere end at navigere: den skifter også fra
kvalitetsark tilbage til liste-visningen.

- [ ] **Step 7: Ret den test der forudsætter en knap**

`web/src/components/__tests__/OcrKildepanel.test.tsx:302` asserterer i dag:

```tsx
    fireEvent.click(screen.getByRole('button', { name: 'Åbn person' }));
    expect(onOpenPerson).toHaveBeenCalledWith('1');
```

Et anker har rollen `link`, ikke `button`. Erstat med:

```tsx
    const aabnPerson = screen.getByRole('link', { name: 'Åbn person' });
    expect(aabnPerson.getAttribute('href')).toBe('/redaktion/person/1');
    fireEvent.click(aabnPerson);
    expect(onOpenPerson).toHaveBeenCalledWith('1');
```

- [ ] **Step 8: Kør hele web-suiten**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS. `web/src/__tests__/Redaktion.kvalitetsark.test.tsx:323-338` asserterer allerede at et
klik på "Åbn person" lander på `/redaktion/person/1` — den skal fortsat være grøn, nu via ankeret.

- [ ] **Step 9: Commit**

```bash
git add web/src/Redaktion.tsx web/src/components/OcrKildepanel.tsx web/src/components/PersonKvalitetsark.tsx web/src/components/NarrativRenderer.tsx web/src/components/__tests__/
git commit -m "feat(redaktion): person-navigation som ægte links

Record-listen, familie-navnene, prosa-links, forældre-konflikt-rækkerne
og kvalitetsarkets tre \"åbn person\"-veje kunne ikke åbnes i ny fane.
Navigationsadfærden ved venstreklik er uændret."
```

---

### Task 3: "Samme person" bliver tydelig og klikbar

**Files:**
- Create: `web/src/data/sammeSom.ts`
- Create: `web/src/data/__tests__/sammeSom.test.ts`
- Modify: `web/src/Redaktion.tsx:1845-1850`

**Interfaces:**
- Consumes: `linkRow(navn, meta, onRemove, extra?, onOpen?, href?)` fra Task 2, `SammeSomLink` fra `data/redaktionRead.ts` (`{ relationId: string; retning: 'alias' | 'kanonisk'; modpartId: string }`)
- Produces: `sammeSomEtiket(retning: 'alias' | 'kanonisk'): { rolle: 'KANONISK' | 'ALIAS'; forklaring: string }`

Funktionen får sit **eget modul** frem for at bo i `Redaktion.tsx` eller `data/redaktionRead.ts`:
begge trækker `web/src/supabase.ts` med ind, og det modul kaster ved import uden `VITE_SUPABASE_*`.
Et rent modul holder enheds-testen hermetisk.

`retning` er klassificeret **set fra den redigerede person** (`mapSammeSomLinks`,
`data/redaktionRead.ts:711-719`): `'alias'` = den redigerede er subjekt og peger på en kanonisk;
`'kanonisk'` = andre peger på den redigerede. Etiketten beskriver derimod **modparten**, hvis navn
står i rækken — derfor byttes rollen om:

| `l.retning` | modpartens rolle | etiket | forklaring |
|---|---|---|---|
| `'alias'` | kanonisk | `KANONISK` | `den post du redigerer er markeret som alias for denne` |
| `'kanonisk'` | alias | `ALIAS` | `markeret som alias for den post du redigerer` |

Forklaringen beskriver **relationen**, ikke resultatet. Et samme_som-link medfører ikke altid en
foldning: `Redaktion.tsx:2117-2119` viser "⚠ Foldes ikke endnu — … Linket oprettes, men personerne
vises separat til konflikten er løst." En tekst der siger "foldes ind i" ville lyve i netop de
tilfælde hvor redaktøren har mest brug for præcision.

- [ ] **Step 1: Skriv den fejlende test**

Opret `web/src/data/__tests__/sammeSom.test.ts`:

```ts
import { sammeSomEtiket } from '../sammeSom';

describe('sammeSomEtiket', () => {
  // retning er set fra den REDIGEREDE person; etiketten beskriver MODPARTEN, hvis navn står
  // i rækken. Rollerne er derfor byttet om — den nemmeste fejl at lave her, derfor testet.
  it('retning "alias" betyder at modparten er den kanoniske post', () => {
    expect(sammeSomEtiket('alias')).toEqual({
      rolle: 'KANONISK',
      forklaring: 'den post du redigerer er markeret som alias for denne',
    });
  });

  it('retning "kanonisk" betyder at modparten er aliaset', () => {
    expect(sammeSomEtiket('kanonisk')).toEqual({
      rolle: 'ALIAS',
      forklaring: 'markeret som alias for den post du redigerer',
    });
  });

  it('lover ikke en foldning — pre-flight kan afvise den', () => {
    // Regressionsværn: teksten må beskrive relationen, ikke resultatet.
    expect(sammeSomEtiket('alias').forklaring).not.toMatch(/foldes/);
    expect(sammeSomEtiket('kanonisk').forklaring).not.toMatch(/foldes/);
  });
});
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- sammeSom`
Expected: FAIL — `Failed to resolve import "../sammeSom"`.

- [ ] **Step 3: Opret modulet**

Opret `web/src/data/sammeSom.ts`:

```ts
// Identitets-linkets etiket i redaktørens "Samme person"-liste. Egen fil (ingen DOM, ingen
// Supabase-import) så den kan enheds-testes uden miljøvariabler — data/redaktionRead.ts importerer
// supabase.ts, som kaster ved modul-load uden VITE_SUPABASE_*.
//
// SammeSomLink.retning er klassificeret set fra den REDIGEREDE person (mapSammeSomLinks i
// redaktionRead.ts); rækken viser MODPARTENS navn — derfor er rollen spejlvendt.
//
// Forklaringen beskriver relationen, ikke resultatet: et link medfører ikke altid en foldning.
// Bekræftelsesdialogen kan sige "⚠ Foldes ikke endnu — … Linket oprettes, men personerne vises
// separat til konflikten er løst", og listen må ikke love mere end den.
export function sammeSomEtiket(retning: 'alias' | 'kanonisk'): { rolle: 'KANONISK' | 'ALIAS'; forklaring: string } {
  return retning === 'alias'
    ? { rolle: 'KANONISK', forklaring: 'den post du redigerer er markeret som alias for denne' }
    : { rolle: 'ALIAS', forklaring: 'markeret som alias for den post du redigerer' };
}
```

- [ ] **Step 4: Kør testen og se den bestå**

Run: `npm run test -w web -- sammeSom`
Expected: PASS

- [ ] **Step 5: Brug etiketten + gør navnet klikbart**

Tilføj `import { sammeSomEtiket } from './data/sammeSom';` i `web/src/Redaktion.tsx` og erstat
linje 1845-1850:

```tsx
              {subHeader('Samme person', () => setPicker({ kind: 'sammeSom' }), '+ Marker som samme person', 10)}
              {sammeSom.length ? sammeSom.map((l) => linkRow(
                persons.find((p) => p.id === l.modpartId)?.navn ?? `#${l.modpartId}`,
                l.retning === 'alias' ? 'denne foldes ind i' : 'foldes ind i denne',
                () => run({ art: 'fjernSammeSom', subjektType: 'person', subjektId: pid, relationId: l.relationId }, 'Fjern samme-person-link'),
              )) : <div style={{ fontSize: 12.5, color: T.muted3 }}>Ingen identitets-links.</div>}
```

med:

```tsx
              {subHeader('Samme person', () => setPicker({ kind: 'sammeSom' }), '+ Marker som samme person', 10)}
              {sammeSom.length ? sammeSom.map((l) => {
                const modpart = persons.find((p) => p.id === l.modpartId);
                const { rolle, forklaring } = sammeSomEtiket(l.retning);
                // Rå modpart-id i stien: redaktøren arbejder i skrive-id-rummet (loadModel({ collapse: false })),
                // så en kanonisering her ville åbne en anden post end den rækken navngiver.
                return linkRow(
                  [modpart?.navn ?? `#${l.modpartId}`, modpart?.aar ? `(${modpart.aar})` : ''].filter(Boolean).join(' '),
                  `${rolle} · ${forklaring}`,
                  () => run({ art: 'fjernSammeSom', subjektType: 'person', subjektId: pid, relationId: l.relationId }, 'Fjern samme-person-link'),
                  undefined,
                  () => openRecord('person', l.modpartId),
                  redaktionPath('person', l.modpartId),
                );
              }) : <div style={{ fontSize: 12.5, color: T.muted3 }}>Ingen identitets-links.</div>}
```

- [ ] **Step 6: Verificér manuelt i browseren**

Run: `npm run dev -w web`
Åbn `/redaktion/person/<id>` for en person med et identitets-link (fx en af de kendte
grundlægger-dubletter). Kontrollér:
1. Rækken viser `KANONISK · …` eller `ALIAS · …` med navn + årstal.
2. Venstreklik på navnet åbner modpartens redaktør-post.
3. Højreklik på navnet giver browserens "Åbn link i ny fane"-menu; ny fane lander på `/redaktion/person/<modpartId>`.
4. ✕-knappen fjerner stadig linket (ingen navigation).

- [ ] **Step 7: Typecheck + fuld suite**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add web/src/data/sammeSom.ts web/src/data/__tests__/sammeSom.test.ts web/src/Redaktion.tsx
git commit -m "feat(redaktion): vis hvem der er kanonisk i \"Samme person\"

Rækkerne sagde \"denne foldes ind i\" uden at vise hvilken post der
beholdes, og navnet kunne ikke åbnes. Teksten beskriver nu relationen
frem for resultatet — et link medfører ikke altid en foldning."
```

---

### Task 4: Publikumsfladens personkort og træ

**Files:**
- Modify: `web/src/Folgesvend.tsx:427` (brugerens egen avatar), `:429` ("Redaktion ↗")
- Modify: `web/src/components/primitives.tsx:70-80` (`PersonCard`)
- Modify: `web/src/components/HomeView.tsx:90` (kuraterede kort), `:98` ("Månedens gods")
- Modify: `web/src/components/TreeSearch.tsx:109,113`
- Modify: `web/src/components/TreeView.tsx` — navnene på linje 142, 170, 188, 208, 219, 234, 251 (de omsluttende kort ligger på 139, 166, 185, 206, 215, 230, 249 og forbliver `<div onClick>`)
- Test: `web/src/components/__tests__/TreeView.test.tsx`

**Interfaces:**
- Consumes: `Link` fra `../Link`, `personPath` + `estatePath` fra `../data/nav`
- Produces: `PersonCard(props: { p: { name: string; years?: string; title?: string }; onClick?: () => void; href?: string; width?: number | string })` — nyt valgfrit `href`; uden det er kortet uændret

- [ ] **Step 1: Skriv den fejlende test**

Tilføj i `web/src/components/__tests__/TreeView.test.tsx` inde i `describe('TreeView', …)`. Filens
fixture er Farfar/Farmor → Far (+ Mor) → Anna (`focusId="A"`) → {Bo (`C1`), Cille (`C2`)}, og
`props` er allerede defineret i filen:

```tsx
  it('søskende-kortets navn er et ægte anker til /person/<id>', () => {
    render(<TreeView {...props} focusId="A" />);
    const anker = screen.getByText('Anna').closest('a');
    expect(anker).not.toBeNull();
    expect(anker!.getAttribute('href')).toBe('/person/A');
  });

  it('venstreklik på et børne-navn kalder onPick præcis én gang (kortet navigerer ikke også selv)', () => {
    const onPick = vi.fn();
    render(<TreeView {...props} onPick={onPick} focusId="A" />);
    fireEvent.click(screen.getByText('Bo'));
    expect(onPick).toHaveBeenCalledTimes(1);
    expect(onPick).toHaveBeenCalledWith('C1');
  });

  it('cmd-klik på et navn lader browseren åbne ny fane UDEN at kortet også navigerer', () => {
    const onPick = vi.fn();
    render(<TreeView {...props} onPick={onPick} focusId="A" />);
    fireEvent.click(screen.getByText('Bo'), { metaKey: true });
    expect(onPick).not.toHaveBeenCalled();
  });

  it('kolonne-variantens anker-kolonne har intet link (ikke-klikbar i dag)', () => {
    render(<TreeView {...props} focusId="A" />);
    fireEvent.click(screen.getByText('Kolonner'));
    // 'Anna' står i anker-kolonnen; onTap er undefined dér, så navnet forbliver almindelig tekst.
    expect(screen.getByText('Anna').closest('a')).toBeNull();
    // 'Far' står i Forældre-kolonnen og ER et drill-mål.
    expect(screen.getByText('Far').closest('a')?.getAttribute('href')).toBe('/person/F');
  });
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- TreeView`
Expected: FAIL — `expect(received).not.toBeNull()` (navnet er en `<div>`, intet omsluttende anker).

- [ ] **Step 3: Giv `PersonCard` et valgfrit href**

Tilføj `import { Link } from '../Link';` øverst i `web/src/components/primitives.tsx` og erstat
linje 70-80:

```tsx
// Personkortet — den gennemgående primitiv (brief §8.1): avatar + serif-navn + mono-år +
// valgfri titel. Bruges af forsidens kuraterede grid nu; tænkt genbrugt af søgeresultater og
// træet i senere slices (§4/§5), så appen føles som ét system. Tager kun de felter et kort
// har brug for (ikke hele ModelPerson) så primitiven forbliver løst koblet.
// href: kortet rummer intet andet klikbart, så HELE kortet bliver ankeret — højreklik/cmd-klik
// åbner personen i ny fane. Uden href opfører kortet sig præcis som før.
export const PersonCard = ({ p, onClick, href, width = 210 }: {
  p: { name: string; years?: string; title?: string };
  onClick?: () => void; href?: string; width?: number | string;
}) => {
  const indhold = (
    <>
      <Avatar n={p.name} size={50} />
      <div style={{ fontFamily: T.serif, fontSize: 19, lineHeight: 1.05, fontWeight: 600, color: T.ink, marginTop: 11 }}>{p.name}</div>
      {p.years ? <div style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted2, marginTop: 4 }}>{p.years}</div> : null}
      {p.title ? <div style={{ fontFamily: T.sans, fontSize: 12.5, fontWeight: 500, color: T.bordeaux, marginTop: 6, lineHeight: 1.3 }}>{p.title}</div> : null}
    </>
  );
  const kortStil = { width, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14, padding: 16, boxShadow: '0 1px 2px rgba(34,31,26,.04)' };
  if (href) {
    return <Link href={href} onNavigate={onClick} style={{ ...kortStil, display: 'block' }}>{indhold}</Link>;
  }
  return <div onClick={onClick} style={{ ...kortStil, cursor: onClick ? 'pointer' : 'default' }}>{indhold}</div>;
};
```

- [ ] **Step 4: Send href fra kortenes kaldesteder**

`web/src/components/HomeView.tsx` — tilføj `import { personPath, estatePath } from '../data/nav';`
og `import { Link } from '../Link';`, og erstat linje 90:

```tsx
            <PersonCard p={p} width="100%" href={personPath(p.id)} onClick={() => onPickPerson(p.id)} />
```

Erstat desuden "Månedens gods"-kortet (linje 98). Kortet er kun klikbart når `gods` findes, så
ankeret er betinget:

```tsx
        {gods ? (
          <Link href={estatePath(gods.id)} onNavigate={() => onOpenEstate(gods.id)} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 15, overflow: 'hidden', display: 'block' }}>
            {godsKortIndhold}
          </Link>
        ) : (
          <div style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 15, overflow: 'hidden', cursor: 'default' }}>
            {godsKortIndhold}
          </div>
        )}
```

hvor `godsKortIndhold` er en lokal `const` defineret lige før `return`-blokken med præcis de to
`<div>`'s der i dag ligger inde i kortet (billed-båndet og tekst-blokken, linje 99-108) — uændret.

`web/src/components/TreeSearch.tsx` — tilføj `import { personPath } from '../data/nav';` og erstat
linje 109 og 113:

```tsx
                    {g.people.map((p) => <PersonCard key={p.id} p={p} width={186} href={personPath(p.id)} onClick={() => s.onPick(p.id)} />)}
```

```tsx
            : <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>{s.browse.flat.map((p) => <PersonCard key={p.id} p={p} width={186} href={personPath(p.id)} onClick={() => s.onPick(p.id)} />)}</div>}
```

- [ ] **Step 5: Gør træets navne til ankre**

`web/src/components/TreeView.tsx` — tilføj imports:

```tsx
import type { CSSProperties } from 'react';
import { Link } from '../Link';
import { personPath } from '../data/nav';
```

Træets kort indeholder `BookmarkFlag` (et `<button>`), så kortet forbliver en `<div onClick>` og kun
**navnet** bliver anker. `stopPropagation` sikrer at kortets egen `onClick` ikke også fyrer —
hverken ved venstreklik (dobbelt navigation) eller ved cmd-klik (ny fane *og* navigation).

Definér én lokal hjælper lige efter `hasParents` (linje 91):

```tsx
  // Navnet i et kort er ankeret (kortet selv rummer BookmarkFlag → ugyldigt som <a>).
  // stopPropagation: kortets egen onClick ville ellers udføre samme navigation én gang til —
  // og ved cmd-klik navigere den aktuelle fane mens browseren åbner en ny.
  const navnLink = (id: string, navn: string, style: CSSProperties, onTap?: () => void) =>
    onTap
      ? <Link href={personPath(id)} onNavigate={onTap} stopPropagation style={style}>{navn}</Link>
      : <div style={style}>{navn}</div>;
```

Erstat derefter navne-elementerne (behold hvert steds egen `style` uændret):

| Linje | Element | `onTap` |
|---|---|---|
| 142 | kandidat-kort (variant B) | `() => onFocus(p.id)` |
| 170 | kolonne-kort | kortets egen `onTap` (`undefined` for anker-kolonnen → ingen link) |
| 188 | uforbundne | `() => onFocus(person.id)` |
| 208 | bedsteforælder-chip | `() => onPick(grand.id)` |
| 219 | forælder-kort | `() => onPick(parent.id)` |
| 234 | søskende-kort | `() => onPick(p.id)` |
| 251 | børne-kort | `() => onPick(p.id)` |

Eksempel (linje 234, søskende-kortet):

```tsx
                {navnLink(p.id, p.name, { fontFamily: T.serif, fontSize: 21, lineHeight: 1.04, fontWeight: 600, marginTop: 11 }, () => onPick(p.id))}
```

- [ ] **Step 6: Konvertér Folgesvends header**

`web/src/Folgesvend.tsx` — tilføj `import { Link } from './Link';` og `personPath` til den
eksisterende `./data/nav`-import.

Brugerens egen avatar (linje 427):

```tsx
            <div onClick={() => navigateTree(meCanon)} title="Din plads i slægten" style={{ width: 38, height: 38, … }}>{initials(model.byId[meCanon].name)}</div>
```

bliver til (behold hele `style`-objektet uændret):

```tsx
            <Link href={personPath(meCanon)} onNavigate={() => navigateTree(meCanon)} title="Din plads i slægten" style={{ width: 38, height: 38, … }}>{initials(model.byId[meCanon].name)}</Link>
```

"Redaktion ↗" (linje 429):

```tsx
          <a href="/redaktion" onClick={(e) => { e.preventDefault(); navigate('/redaktion'); }} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux, textDecoration: 'none' }}>Redaktion ↗</a>
```

bliver til:

```tsx
          <Link href="/redaktion" style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>Redaktion ↗</Link>
```

- [ ] **Step 7: Kør testene**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS — inkl. de eksisterende TreeView-/TreeSearch-tests, der klikker på navne og forventer
ét `onPick`-kald.

- [ ] **Step 8: Commit**

```bash
git add web/src/Folgesvend.tsx web/src/components/primitives.tsx web/src/components/HomeView.tsx web/src/components/TreeSearch.tsx web/src/components/TreeView.tsx web/src/components/__tests__/TreeView.test.tsx
git commit -m "feat(web): personkort, træ-navne og forsidens gods som ægte links

Kort uden indlejrede knapper bliver selv ankeret; kort med bogmærke-flag
får ankeret på navnet, så HTML'en forbliver gyldig."
```

---

### Task 5: Detaljepanel, bogmærker, godser og præsensliste

**Files:**
- Modify: `web/src/components/DetailPanel.tsx:111,170,181`
- Modify: `web/src/components/BookmarksView.tsx:55-62`
- Modify: `web/src/components/EstatesView.tsx:62-65,104-108`
- Modify: `web/src/components/PresensView.tsx:60-66` ("Se fuld profil")
- Test: `web/src/components/__tests__/BookmarksView.test.tsx`

`DetailPanel`, `EstatesView` og `PresensView` har ingen enheds-test der dækker deres
navigation (props-fladen kræver fixtures der ikke findes). De dækkes af typecheck og af den manuelle
gennemgang i Task 7. `BookmarksView` har allerede en fixture og dækker det interessante tilfælde:
navn-anker inde i en række der også rummer en knap.

**Interfaces:**
- Consumes: `Link` fra `../Link`, `personPath` + `estatePath` fra `../data/nav`
- Produces: intet nyt — kun konverteringer

- [ ] **Step 1: Skriv den fejlende test**

Tilføj i `web/src/components/__tests__/BookmarksView.test.tsx` inde i `describe('BookmarksView', …)`
(filen har allerede `makeModel`/`person`-hjælperne):

```tsx
  it('bogmærke-navnet er et ægte anker til /person/<id>', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    render(<BookmarksView model={model} ids={['1']} sort="navn" setSort={vi.fn()} onPick={vi.fn()} onRemove={vi.fn()} loggedIn onRequireLogin={vi.fn()} />);
    const anker = screen.getByText('Anders Reventlow').closest('a');
    expect(anker).not.toBeNull();
    expect(anker!.getAttribute('href')).toBe('/person/1');
  });

  it('klik på navnet kalder onPick præcis én gang (rækkens egen handler fyrer ikke også)', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    const onPick = vi.fn();
    render(<BookmarksView model={model} ids={['1']} sort="navn" setSort={vi.fn()} onPick={onPick} onRemove={vi.fn()} loggedIn onRequireLogin={vi.fn()} />);
    fireEvent.click(screen.getByText('Anders Reventlow'));
    expect(onPick).toHaveBeenCalledTimes(1);
    expect(onPick).toHaveBeenCalledWith('1');
  });

  it('cmd-klik på navnet lader browseren om det og rækken navigerer ikke', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    const onPick = vi.fn();
    render(<BookmarksView model={model} ids={['1']} sort="navn" setSort={vi.fn()} onPick={onPick} onRemove={vi.fn()} loggedIn onRequireLogin={vi.fn()} />);
    fireEvent.click(screen.getByText('Anders Reventlow'), { metaKey: true });
    expect(onPick).not.toHaveBeenCalled();
  });
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- BookmarksView`
Expected: FAIL — intet omsluttende anker (`expect(received).not.toBeNull()`).

- [ ] **Step 3: Konvertér `DetailPanel`**

Tilføj imports:

```tsx
import { Link } from '../Link';
import { personPath } from '../data/nav';
```

Forælder (linje 111):

```tsx
                <Link href={personPath(pa.id)} onNavigate={() => onPick(pa.id)} style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: T.bordeaux }}>{pa.name} ›</Link>
```

Ægtefælle (linje 170):

```tsx
                {sp.id ? <Link href={personPath(sp.id)} onNavigate={() => onPick(sp.id!)} style={{ fontWeight: 600, fontStyle: 'normal', color: T.bordeaux }}>{sp.name} ›</Link> : <span>{sp.name}</span>}
```

Børne-chip (linje 180-185) — chippen rummer intet andet klikbart, så hele chippen bliver anker:

```tsx
                <Link key={c.id} href={personPath(c.id)} onNavigate={() => onPick(c.id)} style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 9, padding: '6px 11px 6px 7px' }}>
                  <div style={{ width: 26, height: 26, borderRadius: '50%', background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux }}>{initials(c.name)}</div>
                  <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600 }}>{c.name.split(' ')[0]}</span>
                </Link>
```

- [ ] **Step 4: Konvertér `BookmarksView`**

Rækken indeholder `BookmarkFlag` (fjern-knap), så kun navnet bliver anker. Tilføj imports (`Link`,
`personPath`) og erstat linje 58:

```tsx
                    <Link href={personPath(p.id)} onNavigate={() => onPick(p.id)} stopPropagation style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, lineHeight: 1.05, display: 'block' }}>{p.name}</Link>
```

Rækkens egen `onClick={() => onPick(p.id)}` bevares uændret (hele rækken er stadig klikbar).

- [ ] **Step 5: Konvertér `EstatesView`**

Tilføj imports (`Link`, `personPath`, `estatePath`).

Ejer-række (linje 62-65) — rummer intet andet klikbart:

```tsx
                <Link href={personPath(o.personId)} onNavigate={() => onPickOwner(o.personId)} style={{ flex: 1, paddingBottom: 18, display: 'block' }}>
                  {(o.periode || o.rolle) && <div style={{ fontFamily: T.mono, fontSize: 11.5, color: T.muted2 }}>{[o.periode, o.rolle].filter(Boolean).join(' · ')}</div>}
                  <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 1 }}>{o.navn} ›</div>
                </Link>
```

Gods-kort (linje 104-108):

```tsx
            <Link key={e.id} href={estatePath(e.id)} onNavigate={() => onOpen(e.id)} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: 15, boxShadow: '0 1px 2px rgba(34,31,26,.03)', display: 'block' }}>
              <span style={{ width: 36, height: 36, borderRadius: 8, background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 17, color: T.bordeaux }}>⌂</span>
              <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 11 }}>{e.navn}</div>
              <div style={{ fontSize: 12.5, color: T.muted, marginTop: 3 }}>{[e.slags, e.ownerCount ? `${e.ownerCount} tilknytning${e.ownerCount === 1 ? '' : 'er'}` : ''].filter(Boolean).join(' · ') || '—'}</div>
            </Link>
```

- [ ] **Step 6: Konvertér `PresensView`s "Se fuld profil"**

Tilføj imports (`Link`, `personPath`) og erstat linje 60-66:

```tsx
          <div
            onClick={() => onPick(id)}
            style={{ marginTop: 6, cursor: 'pointer', color: T.bordeaux, fontSize: 13.5, fontFamily: T.mono, letterSpacing: '.03em' }}
          >
            → Se fuld profil
          </div>
```

med:

```tsx
          <Link
            href={personPath(id)}
            onNavigate={() => onPick(id)}
            style={{ marginTop: 6, display: 'block', color: T.bordeaux, fontSize: 13.5, fontFamily: T.mono, letterSpacing: '.03em' }}
          >
            → Se fuld profil
          </Link>
```

Bogstav-/gren-hoppene i samme fil (linje 301/307) er `href="#linje-…"` og forbliver urørte.

- [ ] **Step 7: Kør testene**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add web/src/components/DetailPanel.tsx web/src/components/BookmarksView.tsx web/src/components/EstatesView.tsx web/src/components/PresensView.tsx web/src/components/__tests__/BookmarksView.test.tsx
git commit -m "feat(web): detaljepanel, bogmærker, godser og præsensliste

Forældre, ægtefælle, børn, bogmærke-navne, ejerrækken, godskortene og
\"Se fuld profil\" kan nu åbnes i ny fane."
```

---

### Task 6: Forsidens feed-kort

**Files:**
- Modify: `web/src/components/feed/FeedStreamView.tsx:256-286`
- Modify: `web/src/components/feed/FeedCardView.tsx:34,67,78,90`
- Modify: `web/src/components/feed/PersonFeedCardView.tsx:19-20`
- Test: `web/src/components/__tests__/FeedStreamView.test.tsx`, `web/src/components/__tests__/PersonFeedCardView.test.tsx:40,97`

**Interfaces:**
- Consumes: `Link` fra `../../Link`, `personPath`/`estatePath`/`pathForMode` fra `../../data/nav`, `FeedCard` fra `@daa/feed`
- Produces: `hrefForCard(card: FeedCard): string | null` (eksporteret fra `FeedStreamView.tsx`), samt `href?: string | null` som nyt prop på `FeedCardView` og `PersonFeedCardView`

Kort hvis mål **ikke** er adresserbart får `null` og forbliver `<div onClick>`: `slaegt` bærer
A/B-parret uden for URL'en, `samle` åbner browse-tilstand, og `forbundet` er slet ikke klikbart i dag.

- [ ] **Step 1: Skriv den fejlende test**

Tilføj i `web/src/components/__tests__/FeedStreamView.test.tsx`:

```tsx
import { hrefForCard } from '../feed/FeedStreamView';
import type { FeedCard } from '@daa/feed';

describe('hrefForCard', () => {
  it('person-kort peger på personens side', () => {
    const kort = { kind: 'dagensperson', id: 'x', personId: '42' } satisfies Partial<FeedCard> as FeedCard;
    expect(hrefForCard(kort)).toBe('/person/42');
  });
  it('gods-kort peger på godsets side', () => {
    const kort = { kind: 'gods', id: 'x', estateId: '7' } satisfies Partial<FeedCard> as FeedCard;
    expect(hrefForCard(kort)).toBe('/estate/7');
  });
  it('våben-kort peger på våben-fanen', () => {
    const kort = { kind: 'vaaben', id: 'x' } satisfies Partial<FeedCard> as FeedCard;
    expect(hrefForCard(kort)).toBe('/arms');
  });
  it('slægtskabs-, forbundet- og samle-kort får intet href (målet ligger uden for URL-grammatikken)', () => {
    expect(hrefForCard({ kind: 'slaegt', id: 'x', aId: '1', bId: '2' } satisfies Partial<FeedCard> as FeedCard)).toBeNull();
    expect(hrefForCard({ kind: 'forbundet', id: 'x' } satisfies Partial<FeedCard> as FeedCard)).toBeNull();
    expect(hrefForCard({ kind: 'samle', id: 'x' } satisfies Partial<FeedCard> as FeedCard)).toBeNull();
  });
});
```

Slår `satisfies Partial<FeedCard>` fejl på et kort fordi unionens variant kræver flere felter, så
udfyld de manglende felter frem for at falde tilbage til `as never` — en fixture der ikke ligner en
rigtig `FeedCard` tester ikke noget.

- [ ] **Step 2: Kør testen og se den fejle**

Run: `npm run test -w web -- FeedStreamView`
Expected: FAIL — `hrefForCard is not a function`.

- [ ] **Step 3: Tilføj `hrefForCard`**

I `web/src/components/feed/FeedStreamView.tsx`, tilføj import:

```tsx
import { personPath, estatePath, pathForMode } from '../../data/nav';
```

og eksportér hjælperen umiddelbart før `openCard` (linje 256):

```tsx
// Hvor peger et feed-kort hen, som en adresserbar sti? null = målet ligger bevidst uden for
// URL-grammatikken (Slægtskabsfanens A/B-par, browse-tilstand), og så får kortet intet anker —
// et href ville love en side der ikke findes.
export function hrefForCard(card: FeedCard): string | null {
  switch (card.kind) {
    case 'portrait': case 'citat': case 'arkiv': case 'historie': case 'embede':
    case 'jubilaeum': case 'paadennedag': case 'dagensperson':
      return personPath(card.personId);
    case 'gods': return estatePath(card.estateId);
    case 'vaaben': return pathForMode('arms');
    case 'slaegt': case 'forbundet': case 'samle': return null;
  }
}
```

Send den videre i render-løkken (linje 276-284) ved at tilføje endnu et prop på `FeedCardView`:

```tsx
              href={hrefForCard(card)}
```

- [ ] **Step 4: Kør testen og se den bestå**

Run: `npm run test -w web -- FeedStreamView`
Expected: PASS

- [ ] **Step 5: Brug href'et i kort-komponenterne**

`web/src/components/feed/FeedCardView.tsx` — tilføj `import { Link } from '../../Link';` og
`import type { CSSProperties, ReactNode } from 'react';`, tilføj `href?: string | null` til
props-typen, og indfør én lokal wrapper der bruges de fire steder (34, 67, 78, 90):

```tsx
// Kortets ydre skal: et anker når målet er adresserbart, ellers den hidtidige <div onClick>.
const KortSkal = ({ href, onOpen, style, children }: { href?: string | null; onOpen: () => void; style: CSSProperties; children: ReactNode }) =>
  href
    ? <Link href={href} onNavigate={onOpen} style={{ ...style, display: 'block' }}>{children}</Link>
    : <div onClick={onOpen} style={{ ...style, cursor: 'pointer' }}>{children}</div>;
```

Erstat hvert af de fire `<div style={{ … cursor: 'pointer' }} onClick={() => onOpen(card)}>` med
`<KortSkal href={href} onOpen={() => onOpen(card)} style={{ … }}>` (samme stil-objekt, minus
`cursor`) og luk med `</KortSkal>`.

`web/src/components/feed/PersonFeedCardView.tsx:19-20` — `<article onClick>` beholdes (kortet rummer
`BookmarkFlag`), men den indre `<button>` bliver et anker:

```tsx
      <Link href={href ?? personPath(card.personId)} onNavigate={() => onOpen(card)} stopPropagation
        aria-label={`Åbn profil for ${person.name}`}
        style={{ display: 'block', width: '100%', textAlign: 'left' }}>
```

(luk med `</Link>`; tilføj `href?: string | null` til props og importér `Link` + `personPath`).

- [ ] **Step 6: Ret de to tests der forudsætter en knap**

`web/src/components/__tests__/PersonFeedCardView.test.tsx:40` asserterer i dag rollen `button` og
**tre** aktiveringer (klik + Enter + Space). Et anker har rollen `link`, og **Space aktiverer ikke et
anker** — kun klik og Enter. Erstat testen:

```tsx
  it('åbner personkortet med klik og Enter på den store profilkontrol', async () => {
    const { onOpen } = renderPersonCard();
    const profile = screen.getByRole('link', { name: 'Åbn profil for Anna Reventlow' });
    const user = userEvent.setup();

    expect(profile.getAttribute('href')).toBe('/person/42'); // fixturens portrait.personId er '42'

    fireEvent.click(profile);
    profile.focus();
    await user.keyboard('{Enter}');

    expect(onOpen).toHaveBeenCalledTimes(2);
  });
```

Og linje 97 (arkivkortet i samme fil):

```tsx
    expect(screen.getByRole('link', { name: 'Åbn profil for Anna Reventlow' })).toBeTruthy();
```

- [ ] **Step 7: Kør testene**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add web/src/components/feed/ web/src/components/__tests__/
git commit -m "feat(web): feed-kort som ægte links hvor målet er adresserbart

Person-, gods- og våben-kort får href; slægtskabs-, forbundet- og
samle-kort gør ikke, fordi deres mål bevidst ligger uden for
URL-grammatikken. Profilkontrollen er nu et anker, ikke en knap."
```

---

### Task 7: Ende-til-ende-verifikation

**Files:** `web/e2e/` (Playwright — eksisterende opsætning, i dag kun `feed.spec.ts`)

- [ ] **Step 1: Kør hele web-suiten + typecheck**

Run: `npx tsc --noEmit -p web/tsconfig.json && npm run test -w web`
Expected: PASS. Antallet skal være ≥ 637 tests (baseline) plus de nye.

- [ ] **Step 2: Kør de øvrige workspaces (regression)**

Run: `npm run test -w @daa/core && npm run test -w @daa/feed`
Expected: PASS (ingen af dem er rørt, men CI kræver dem grønne).

- [ ] **Step 3: Manuel browser-verifikation**

Run: `npm run dev -w web`

For hvert punkt: højreklik → "Åbn link i ny fane", og kontrollér at den nye fane viser den rigtige
side (ikke en 404, ikke forsiden) — og at almindeligt venstreklik gør præcis som før:

1. `/` → et personkort i "Redaktionen foreslår"
2. `/` → "Månedens gods"
3. `/` → et feed-personkort (og at bogmærke-flaget stadig kan trykkes uden at navigere)
4. `/stamtrae` → et navn i et træ-kort (variant A **og** variant B)
5. `/person/<id>` → forælder, ægtefælle og et barn i detaljepanelet
6. `/person/<id>` → et person-link inde i biografi-prosaen
7. `/estates` → et godskort, derefter en ejer i ejerrækken
8. `/bookmarks` → et bogmærke-navn
9. `/praesens` → "Se fuld profil"
10. `/redaktion/person/<id>` → record-listen, et familie-navn, en "Samme person"-række
11. Headerens "Redaktion ↗" og din egen avatar ved siden af

Kontrollér desuden **cmd-klik** på mindst ét træ-navn og ét bogmærke-navn: der må åbne en ny fane
**uden** at den aktuelle fane også skifter person.

- [ ] **Step 4: Kør Playwright-smoken**

Run: `npm run e2e -w web`
Expected: PASS. Slår den fejl på en selector der antog `<div>` eller rollen `button`, opdatér
selectoren — ikke komponenten.

- [ ] **Step 5: Commit eventuelle test-justeringer**

```bash
git add web/e2e
git commit -m "test(web): tilpas e2e-selectorer til ankre"
```

(Spring over hvis intet ændrede sig.)

---

## Kendte afgrænsninger

- `mobile/` er urørt: React Native har ingen `<a>`, og en tilsvarende dybt-link-flade dér er et separat stykke arbejde.
- `PresensView`s bogstav-/gren-hop forbliver fragment-ankre (`href="#…"`) — de er allerede ægte links, blot in-page.
- `OverviewMapView.tsx:46`: kort-punkter navigerer via kort-rendererens `onPointPress`-callback og kan ikke være ankre. Teknisk undtagelse.
- Feed-kort af typen `slaegt`, `forbundet` og `samle` får bevidst intet `href`, fordi deres mål (A/B-parret, browse-tilstanden) ligger uden for URL-grammatikken.
- **`RelateView.tsx:87` (slægtskabsstiens trin) får bevidst intet anker.** Handleren er `focusOnly`: venstreklik skifter fokus uden at navigere. Et `href` browseren viser i statuslinjen, men som venstreklik ikke går til, ville være præcis det "ingen fabrikerede links"-reglen forbyder. Det rigtige næste skridt er ikke et anker, men en beslutning om hvorvidt `/relate/<aId>/<bId>` skal være adresserbar (delbare slægtskabs-links) — en selvstændig feature.
