# Kildeversioner for same_som-aliaser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Historisk status (2026-09-03):** Checkboksene er planens oprindelige
> arbejdsspor, ikke en aktuel udførelseslog. Kontrollér changelog, commits og
> aktuelle core-, web- og mobiltests ved statusspørgsmål.
> `docs/evidensbaseret-genimport/status.md` beskriver alene
> genimportprogrammet, ikke denne features status.

**Goal:** Sørg for, at web og mobil henter offentlige kildeversioner for alle fysiske personrækker bag en kanonisk `same_som`-person.

**Architecture:** En ren core-hjælper producerer canonical ID efterfulgt af deduplikerede, stabilt sorterede alias-ID'er. Webs eksisterende detailkald og mobilens bio-versionkald bruger samme hjælper; mobilens datafunktion kombinerer ID-projektion og RPC-kald, så adfærden kan regressionstestes uden at mocke hele skærmen.

**Tech Stack:** TypeScript, `@daa/core`, React 18, Expo SDK 56/React Native, Vitest og Jest.

## Global Constraints

- Canonical ID er altid første ID; aliaser sorteres lexicografisk og deduplikeres.
- Ingen ændring af `same_som`-collapse, publiceringsstatus, RPC-signatur eller database.
- En person uden aliaser sender fortsat præcis ét ID.
- Følg `mobile/AGENTS.md`: læs Expo SDK 56-dokumentationen før mobilkode ændres.
- Kør core-, web- og mobiltests separat og rapportér eksisterende miljøfejl separat.

---

### Task 1: Tilføj delt fysisk-person-ID-projektion i core

**Files:**

- Create: `packages/core/src/physicalPersonIds.ts`
- Create: `packages/core/src/__tests__/physicalPersonIds.test.ts`
- Modify: `packages/core/src/index.ts:1-35`

**Interfaces:**

- Consumes: `canonicalId: string`, `mergedFrom?: readonly Pick<Provenance,'personId'>[]`.
- Produces: `physicalPersonIds(canonicalId, mergedFrom) -> string[]`.

- [ ] **Step 1: Skriv den røde core-test**

```typescript
import { describe, expect, it } from 'vitest';
import { physicalPersonIds } from '../physicalPersonIds';

describe('physicalPersonIds', () => {
  it('returns canonical first and every unique alias in stable order', () => {
    expect(physicalPersonIds('10', [
      { personId: '2' }, { personId: '10' }, { personId: '3' }, { personId: '2' },
    ])).toEqual(['10', '2', '3']);
  });

  it('returns only canonical when provenance is absent', () => {
    expect(physicalPersonIds('10')).toEqual(['10']);
  });
});
```

- [ ] **Step 2: Kør RED**

```bash
npm test --workspace packages/core -- --run src/__tests__/physicalPersonIds.test.ts
```

Expected: modulet findes ikke.

- [ ] **Step 3: Implementér hjælperen og eksporten**

```typescript
import type { Provenance } from './types';

export function physicalPersonIds(
  canonicalId: string,
  mergedFrom: readonly Pick<Provenance, 'personId'>[] = [],
): string[] {
  const aliases = [...new Set(
    mergedFrom.map(({ personId }) => personId).filter((id) => id !== canonicalId),
  )].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return [canonicalId, ...aliases];
}
```

Tilføj `export * from './physicalPersonIds';` i `packages/core/src/index.ts`.

- [ ] **Step 4: Kør GREEN og typecheck**

```bash
npm test --workspace packages/core -- --run src/__tests__/physicalPersonIds.test.ts
npm run typecheck --workspace packages/core
```

Expected: tests og typecheck består.

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/physicalPersonIds.ts \
  packages/core/src/__tests__/physicalPersonIds.test.ts packages/core/src/index.ts
git commit -m "fix: centralize physical same-as person ids"
```

### Task 2: Brug den delte projektion i web

**Files:**

- Create: `web/src/data/personMembers.ts`
- Create: `web/src/data/__tests__/personMembers.test.ts`
- Modify: `web/src/Folgesvend.tsx:175-184`
- Modify: `web/src/components/PresensView.tsx:280-292`

**Interfaces:**

- Produces: `personMemberIds(canonicalId, person) -> string[]`, en tynd web-adapter over `physicalPersonIds`.
- Produces: eksisterende `fetchPersonDetail(id, memberIds, hentKilder)`-kald med canonical ID plus aliaser.

- [ ] **Step 1: Skriv den røde web-adaptertest**

```typescript
import { describe, expect, it } from 'vitest';
import { personMemberIds } from '../personMembers';

describe('personMemberIds', () => {
  it('adapts a folded web person to canonical plus alias ids', () => {
    expect(personMemberIds('10', {
      mergedFrom: [{ personId: '3' }, { personId: '10' }, { personId: '2' }],
    })).toEqual(['10', '2', '3']);
  });
});
```

- [ ] **Step 2: Kør testen og bekræft RED**

```bash
VITE_SUPABASE_URL=http://localhost VITE_SUPABASE_ANON_KEY=test \
  npm test --workspace web -- --run src/data/__tests__/personMembers.test.ts
```

Expected: `personMembers`-modulet findes ikke.

- [ ] **Step 3: Implementér webkaldet**

Implementér adapteren:

```typescript
import { physicalPersonIds, type Provenance } from '@daa/core';

export function personMemberIds(
  canonicalId: string,
  person?: { mergedFrom?: readonly Provenance[] } | null,
): string[] {
  return physicalPersonIds(canonicalId, person?.mergedFrom);
}
```

Importér `personMemberIds` i de to callsites. `Folgesvend` bruger
`personMemberIds(focusId, model?.byId[focusId])`; `PresensView` bruger
`personMemberIds(id, model!.byId[id])`. `fetchPersonDetail` ændres ikke.

- [ ] **Step 4: Kør GREEN og web type/buildgate**

```bash
VITE_SUPABASE_URL=http://localhost VITE_SUPABASE_ANON_KEY=test \
  npm test --workspace web -- --run src/data/__tests__/personMembers.test.ts \
  src/components/__tests__/PresensView.test.tsx
npm run build --workspace web
```

Expected: adaptertest, eksisterende PresensView-regressioner og build består.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/personMembers.ts web/src/data/__tests__/personMembers.test.ts \
  web/src/Folgesvend.tsx web/src/components/PresensView.tsx
git commit -m "fix: fetch web person detail for every same-as member"
```

### Task 3: Hent mobilens bio-versioner for canonical og aliases

**Files:**

- Modify: `mobile/src/data/publicBioVersions.ts:1-18`
- Modify: `mobile/src/data/__tests__/publicBioVersions.test.ts:1-18`
- Modify: `mobile/src/app/person/[id].tsx:15-66`

**Interfaces:**

- Produces: `fetchPublicBioVersionsForPerson(sb, canonicalId, mergedFrom) -> Promise<BioSourceVersion[] | null>`.
- Consumes: `physicalPersonIds` og eksisterende `fetchPublicBioVersions`.

- [ ] **Step 1: Læs den krævede Expo SDK 56-dokumentation**

Læs `https://docs.expo.dev/versions/v56.0.0/` og den versionerede side for React hooks/routing, hvis den findes. Bekræft, at ændringen kun bruger almindelig `useEffect` og ikke kræver en Expo API-ændring.

- [ ] **Step 2: Skriv den røde datafunktionstest**

```typescript
it('requests versions for canonical person and every alias', async () => {
  const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
  await fetchPublicBioVersionsForPerson(
    { rpc } as never,
    '10',
    [{ personId: '3' }, { personId: '10' }, { personId: '2' }],
  );
  expect(rpc).toHaveBeenCalledWith('public_person_bio_source_versions', {
    p_person_ids: [10, 2, 3],
  });
});
```

Tilføj en test uden `mergedFrom`, der forventer `[10]`.

- [ ] **Step 3: Kør RED**

```bash
npm test --workspace mobile -- --runInBand src/data/__tests__/publicBioVersions.test.ts
```

Expected: `fetchPublicBioVersionsForPerson` findes ikke.

- [ ] **Step 4: Implementér datafunktionen og skærmkaldet**

I `publicBioVersions.ts`:

```typescript
import { physicalPersonIds, type Provenance } from '@daa/core';

export function fetchPublicBioVersionsForPerson(
  sb: Parameters<typeof fetchPublicBioVersions>[0],
  canonicalId: string,
  mergedFrom: readonly Pick<Provenance, 'personId'>[] = [],
): Promise<BioSourceVersion[] | null> {
  return fetchPublicBioVersions(sb, physicalPersonIds(canonicalId, mergedFrom));
}
```

I personskærmen importeres den nye funktion. Effecten kalder
`fetchPublicBioVersionsForPerson(supabase, personId, person?.mergedFrom)` og har
`[personId, person?.mergedFrom]` som dependencies. State er fortsat keyed på
canonical `personId`, så et sent svar for en tidligere person ikke vises.

- [ ] **Step 5: Kør GREEN, mobil typecheck og relevante skærmtests**

```bash
npm test --workspace mobile -- --runInBand src/data/__tests__/publicBioVersions.test.ts
npx tsc -p mobile/tsconfig.json --noEmit
```

Kør desuden eksisterende person-detailtests, hvis repoet har dem. Expected: RPC-argumentet er `[10,2,3]`, enkeltperson er `[10]`, og TypeScript består.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/publicBioVersions.ts \
  mobile/src/data/__tests__/publicBioVersions.test.ts mobile/src/app/person/'[id]'.tsx
git commit -m "fix: include same-as aliases in mobile source versions"
```

### Task 4: Samlet web/mobil-paritetsgate

**Files:**

- Verify only: `packages/core`, `web`, `mobile`

**Interfaces:**

- Consumes: Tasks 1-3.
- Produces: frisk test- og buildbevis; ingen deployment.

- [ ] **Step 1: Kør fuld core-suite**

```bash
npm test --workspace packages/core -- --run
npm run typecheck --workspace packages/core
```

- [ ] **Step 2: Kør fuld web-suite med eksplicit testmiljø**

```bash
VITE_SUPABASE_URL=http://localhost VITE_SUPABASE_ANON_KEY=test \
  npm test --workspace web -- --run
npm run build --workspace web
```

- [ ] **Step 3: Kør fuld mobilsuite og typecheck**

```bash
npm test --workspace mobile -- --runInBand
npx tsc -p mobile/tsconfig.json --noEmit
```

- [ ] **Step 4: Kontrollér diff og worktree**

```bash
git diff --check
git status --short --branch
git log --oneline -5
```

Expected: alle relevante tests/builds består; ingen deployment eller push udføres.
