# Levende feed — sociale personposter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every person-related web and mobile feed card a shared social-post shell with a deterministic, swipeable strip of up to four public images and a large profile target.

**Architecture:** Keep `@daa/feed` pure by adding only generic media selection there. Web batches relation/media/variant reads and signs only selected paths; mobile reuses `Aux.mediaBy` and its existing signed-URL cache. Platform-specific person-post and media-strip components own gestures and lightbox state, while feed ordering remains completely independent of media arrival.

**Tech Stack:** TypeScript, Vitest, Jest, React 18, React Native 0.85/Expo 56, Supabase JS/Storage, Testing Library.

## Global Constraints

- Work only in `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/feed-social-posts` on `feat/feed-social-posts`.
- Every behavior change follows literal RED → verify expected failure → minimal GREEN → verify pass → refactor. Record the failing command and failure reason in the task report.
- All implementation subagents use `gpt-5.6-terra`.
- Do not change `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, redaktion flows, uploads, or publication behavior.
- Do not add likes, comments, reposts, follows, automatic carousel movement, video, audio, or a post-detail route.
- Media never enters `buildFeedOrder`, scoring, pins, seen-weights, resume state, or GDPR filtering.
- Every person card may show media; no usable media means the existing text card without an empty placeholder.
- Select at most `4` unique media items per card. `portrait` and `dagensperson` start with the primary portrait; other person cards rotate deterministically by `card.id` and canonical `personId`.
- Header identity is initials in v1, behind a replaceable identity model for a future lineage/branch coat of arms.
- Horizontal swipe/scroll navigates media; image press opens the existing lightbox; bookmark remains independent; the large header/body target opens the person profile.
- Preserve intrinsic image proportions with `object-fit`/`contentFit="contain"`; do not aggressively crop archival documents.
- Web and mobile use existing theme/tokens and exact Danish UI language.
- Use only public rows permitted by existing RLS and the current user session. Reuse `createSignedUrls` through existing `signPaths`; current Supabase docs require `storage.objects SELECT` for signed URLs and support batching paths.
- No service-role/secret key, no new Storage policy, and no new Supabase dependency.
- The only dependency addition allowed is exact mobile test tooling: `@testing-library/react-native@13.3.3` and `react-test-renderer@19.2.3`.

---

### Task 1: Pure deterministic feed-media selection

**Files:**
- Create: `packages/feed/src/media.ts`
- Create: `packages/feed/src/__tests__/media.test.ts`
- Modify: `packages/feed/src/index.ts`

**Interfaces:**
- Consumes: existing `stableHash()` from `packages/feed/src/prng.ts` and `FeedCard['kind']`.
- Produces:

```ts
export type FeedMediaCandidate = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  largePath: string;
  mediumPath: string | null;
  primaer?: boolean;
};

export function selectFeedMedia<T extends FeedMediaCandidate>(
  cardId: string,
  kind: FeedCard['kind'],
  personId: string,
  media: readonly T[],
  limit?: number,
): T[];
```

- `selectFeedMedia` preserves additional fields on generic `T`.
- Stable order before rotation is ascending `id.localeCompare(id, 'en', { numeric: true })`.
- Duplicate IDs collapse to one; a later/earlier `primaer:true` occurrence always wins.
- Portrait kinds are exactly `portrait` and `dagensperson`.
- Portrait-suitable normalized kinds are exactly `foto`, `maleri`, `portræt`, `portraet`.
- Rotation offset is `stableHash(`${cardId}|${personId}`) % candidates.length`.

- [x] **Step 1: Write the failing selection tests**

Create fixtures with literal expected IDs:

```ts
const media = [
  m('1', 'segl'),
  m('2', 'foto'),
  m('3', 'dokument', true),
  m('4', 'maleri'),
  m('5', 'brev'),
];

expect(selectFeedMedia('arkiv:a', 'arkiv', 'p1', media).map(x => x.id))
  .toEqual(['1', '2', '3', '4']);
expect(selectFeedMedia('historie:b', 'historie', 'p1', media).map(x => x.id))
  .toEqual(['3', '4', '5', '1']);
expect(selectFeedMedia('portrait:p1', 'portrait', 'p1', media).map(x => x.id))
  .toEqual(['3', '4', '5', '1']);
```

Also assert:

- empty input gives `[]`;
- one input stays one;
- two duplicate id `5` rows in both input orders produce one row with `primaer:true`;
- without explicit primary, normalized `" Portræt "` beats a preceding `segl`;
- limit `2` returns exactly two;
- different input permutations produce the same IDs;
- returned objects retain an extra fixture property.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
npm test --workspace packages/feed -- src/__tests__/media.test.ts
```

Expected: FAIL because `../media` and `selectFeedMedia` do not exist.

- [x] **Step 3: Implement the minimal pure selector**

Implement helpers local to `media.ts`:

```ts
const PORTRAIT_KINDS = new Set<FeedCard['kind']>(['portrait', 'dagensperson']);
const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);
const normSlags = (value: string) => value.trim().toLowerCase();
const rotate = <T,>(items: T[], offset: number) =>
  items.length === 0 ? [] : [...items.slice(offset), ...items.slice(0, offset)];
```

Deduplicate before sorting. For portrait kinds, remove the chosen primary from the
rotatable remainder, rotate that remainder using the same hash, prepend the primary,
then slice. For all other kinds rotate the full sorted list, then slice. Default
`limit` is `4`; `limit <= 0` returns `[]`.

Export `media.ts` from `packages/feed/src/index.ts`.

- [x] **Step 4: Verify GREEN and package regression**

Run:

```bash
npm test --workspace packages/feed -- src/__tests__/media.test.ts
npm test --workspace packages/feed
```

Expected: focused tests pass and the complete feed suite remains green.

- [x] **Step 5: Commit**

```bash
git add packages/feed/src/media.ts packages/feed/src/__tests__/media.test.ts packages/feed/src/index.ts
git commit -m "feat(feed): vælg postbilleder deterministisk"
```

---

### Task 2: Batched web feed-media adapter

**Files:**
- Create: `web/src/data/feedMedia.ts`
- Create: `web/src/data/__tests__/feedMedia.test.ts`

**Interfaces:**
- Consumes: `FeedMediaCandidate`, `selectFeedMedia`, `getAll`, the existing web
  `supabase` client, and `signPaths()` from `web/src/data/media.ts`.
- Produces:

```ts
export type FeedMediaRequest = {
  cardId: string;
  kind: FeedCard['kind'];
  personId: string;
};

export type WebFeedMediaItem = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  mediumUrl: string;
  largeUrl: string;
  primaer?: boolean;
};

export type FeedMediaCandidatesByPerson = Record<string, FeedMediaCandidate[]>;
export type WebFeedMediaByCard = Record<string, WebFeedMediaItem[]>;

export async function fetchFeedMediaCandidates(
  canonicalPersonIds: string[],
  canonicalIdById: Record<string, string>,
): Promise<FeedMediaCandidatesByPerson>;

export async function resolveFeedMediaForCards(
  requests: FeedMediaRequest[],
  candidatesByPerson: FeedMediaCandidatesByPerson,
): Promise<WebFeedMediaByCard>;
```

- [x] **Step 1: Write failing query/mapping/signing tests**

Mock complete Supabase query builders with `select`, `eq`, `in`, `order`, `range`, and
thenable behavior, plus `signPaths`.

Use this hand-built fixture:

```ts
const canonicalIdById = { '10': '10', '11': '10', '12': '10' };
const relations = [
  { subjekt_id: 11, objekt_id: 101, kvalifikator: null },
  { subjekt_id: 12, objekt_id: 101, kvalifikator: { primaer: true } },
  { subjekt_id: 10, objekt_id: 102, kvalifikator: null },
];
const media = [
  { id: 101, slags: 'maleri', titel: 'A', kunstner: 'K1', datering: '1800', storage_path: 'large/101.jpg' },
  { id: 102, slags: 'brev', titel: 'B', kunstner: null, datering: null, storage_path: 'large/102.jpg' },
];
const variants = [
  { media_id: 101, storage_path: 'medium/101.jpg' },
];
```

Assert:

- one batch each for `relation`, `media`, and `media_variant`, never one per person/card;
- relation query filters both person→media and `rolle='afbildet'`;
- aliases 11/12 merge into canonical key `10`;
- duplicate media 101 keeps `primaer:true`;
- media without `storage_path` is excluded;
- `resolveFeedMediaForCards` selects before signing and passes only selected
  `mediumPath`/`largePath` values to one `signPaths` call;
- `mediumUrl` falls back to `largeUrl` for media 102;
- a missing signed large URL removes only that item;
- thrown fetch errors warn and return keys with empty arrays for requested persons;
- an empty request performs no Supabase or Storage call.

- [x] **Step 2: Run focused test and verify RED**

Run:

```bash
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web -- src/data/__tests__/feedMedia.test.ts
```

Expected: FAIL because `../feedMedia` does not exist.

- [x] **Step 3: Implement batched candidate loading**

Implement the three-query flow:

```ts
const canonicalSet = new Set(canonicalPersonIds);
const memberIds = Object.entries(canonicalIdById)
  .filter(([, canonical]) => canonicalSet.has(canonical))
  .map(([member]) => Number(member))
  .filter(Number.isFinite);
for (const id of canonicalPersonIds.map(Number).filter(Number.isFinite)) memberIds.push(id);
```

Use `getAll` for all paginated reads. Relation select is
`subjekt_id,objekt_id,kvalifikator`; media select is
`id,slags,titel,kunstner,datering,storage_path`; variant select is
`media_id,storage_path` with `.eq('tier', 'medium')`.

Normalize nullable text to `''`, preserve `primaer`, map relation subject through
`canonicalIdById`, and return a key for every requested canonical person even when empty.
Catch once at the exported boundary, warn with prefix `[feedMedia]`, and return empty
keys.

- [x] **Step 4: Implement selected-path signing**

For each request, call `selectFeedMedia(request.cardId, request.kind,
request.personId, candidates)`. Build one union of selected medium/large paths, call
the existing `signPaths` once, and then materialize `WebFeedMediaItem[]` per card.
Require a signed `largePath`; use `signed.get(mediumPath) ?? largeUrl` for `mediumUrl`.

- [x] **Step 5: Verify GREEN and web data regression**

Run:

```bash
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web -- src/data/__tests__/feedMedia.test.ts
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web
```

Expected: focused tests and full web suite pass.

- [x] **Step 6: Commit**

```bash
git add web/src/data/feedMedia.ts web/src/data/__tests__/feedMedia.test.ts
git commit -m "feat(web): hent feedmedier i batch"
```

---

### Task 3: Mobile feed-media adapter and interaction test tooling

**Files:**
- Modify: `mobile/package.json`
- Modify: `package-lock.json`
- Create: `mobile/src/lib/feedMedia.ts`
- Create: `mobile/src/lib/__tests__/feedMedia.test.ts`

**Interfaces:**
- Consumes: Task 1 `FeedMediaCandidate`/`selectFeedMedia`, `RawMedia`, and existing
  `useMediaAndThumbUris`.
- Produces:

```ts
export type MobileFeedMediaItem = {
  id: string;
  slags: string;
  titel: string | null;
  kunstner: string | null;
  datering: string | null;
  mediumUri: string;
  largeUri: string;
};

export function selectMobileFeedMedia(
  card: Pick<FeedCard, 'id' | 'kind'>,
  personId: string,
  media: readonly RawMedia[],
): RawMedia[];

export function buildMobileFeedMediaItems(
  selected: readonly RawMedia[],
  largeUris: Record<string, string>,
  mediumUris: Record<string, string>,
): MobileFeedMediaItem[];

export function useMobileFeedMedia(
  card: Pick<FeedCard, 'id' | 'kind'>,
  personId: string,
  media: readonly RawMedia[],
): MobileFeedMediaItem[];
```

- [x] **Step 1: Install exact mobile test dependencies**

Run:

```bash
npm install --workspace mobile --save-dev --save-exact @testing-library/react-native@13.3.3 react-test-renderer@19.2.3
```

Verify only `mobile/package.json` and root `package-lock.json` changed.

- [x] **Step 2: Write failing adapter tests**

Use real `selectMobileFeedMedia` behavior with raw fields:

```ts
const raw = [
  { id: 1, slags: 'segl', storage_path: 'large/1.jpg', medium_storage_path: 'medium/1.jpg' },
  { id: 2, slags: 'maleri', storage_path: 'large/2.jpg', primaer: true },
  { id: 3, slags: 'brev', storage_path: null },
] satisfies RawMedia[];
```

Assert:

- portrait selects id 2 first and excludes id 3 because it has no original path;
- story/arkiv selection is stable and limited to four;
- duplicate IDs preserve the primary raw row;
- `buildMobileFeedMediaItems` requires a large URI, uses medium when present, falls back
  to large, and retains nullable captions;
- missing large URI filters only the affected item.

- [x] **Step 3: Run focused test and verify RED**

Run:

```bash
npm test --workspace mobile -- src/lib/__tests__/feedMedia.test.ts --runInBand
```

Expected: FAIL because `../feedMedia` does not exist.

- [x] **Step 4: Implement normalization, mapping, and hook**

Normalize each displayable `RawMedia` into:

```ts
{
  id: String(m.id),
  slags: String(m.slags ?? ''),
  titel: String(m.titel ?? ''),
  kunstner: String(m.kunstner ?? ''),
  datering: String(m.datering ?? ''),
  largePath: String(m.storage_path),
  mediumPath: m.medium_storage_path ? String(m.medium_storage_path) : null,
  primaer: m.primaer === true,
  raw: m,
}
```

Call Task 1's selector and return `.raw`. In `useMobileFeedMedia`, memoize selection,
call:

```ts
useMediaAndThumbUris(selected, m => m.medium_storage_path)
```

and pass `uris`/`thumbUris` to `buildMobileFeedMediaItems`. Do not sign unselected raw
media.

- [x] **Step 5: Verify GREEN and mobile regression**

Run:

```bash
npm test --workspace mobile -- src/lib/__tests__/feedMedia.test.ts --runInBand
npm test --workspace mobile -- --runInBand
```

Expected: focused tests and full mobile suite pass, with only the established offline
Supabase warnings.

- [x] **Step 6: Commit**

```bash
git add mobile/package.json package-lock.json mobile/src/lib/feedMedia.ts mobile/src/lib/__tests__/feedMedia.test.ts
git commit -m "feat(mobile): forbered feedmedier til visning"
```

---

### Task 4: Unified web person-post shell, media strip, and feed integration

**Files:**
- Create: `web/src/components/feed/FeedMediaStrip.tsx`
- Create: `web/src/components/feed/PersonFeedCardView.tsx`
- Create: `web/src/components/__tests__/PersonFeedCardView.test.tsx`
- Modify: `web/src/components/feed/FeedCardView.tsx`
- Modify: `web/src/components/feed/FeedStreamView.tsx`
- Modify: `web/src/components/primitives.tsx`

**Interfaces:**
- Consumes: Task 2 `fetchFeedMediaCandidates`, `resolveFeedMediaForCards`,
  `WebFeedMediaItem`; existing `Lightbox`, theme tokens, `Avatar`, and feed callbacks.
- `PersonFeedCardView` accepts:

```ts
type PersonCard = Extract<FeedCard, { personId: string }>;
type PersonIdentity = { name: string; years: string };

{
  card: PersonCard;
  person: PersonIdentity;
  media: WebFeedMediaItem[];
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
}
```

- `FeedCardView` adds optional `person`/`media` props and delegates every card containing
  `personId` to `PersonFeedCardView`; non-person cases remain visually and behaviorally
  unchanged.

- [x] **Step 1: Write failing person-post interaction tests**

Use `@vitest-environment jsdom`, Testing Library, a real portrait card, and two literal
`WebFeedMediaItem` fixtures. Assert:

- initials, model-derived name/years, kicker, body, and two images render;
- pressing the large profile control calls `onOpen(card)`;
- Enter and Space on that control call `onOpen(card)`;
- image press opens the real lightbox and does not call `onOpen`;
- bookmark press calls `onSave(personId)` and does not call `onOpen`;
- two images render in a horizontal strip and one image gets the full-width variant;
- no media renders no media-strip region;
- an `arkiv` card gets the same header shell but keeps its clause/year/category/source;
- a non-person `gods` card still uses the old `FeedCardView` branch.

Query by accessible roles/names, not test IDs.

- [x] **Step 2: Run focused component test and verify RED**

Run:

```bash
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web -- src/components/__tests__/PersonFeedCardView.test.tsx
```

Expected: FAIL because `PersonFeedCardView` does not exist and `FeedCardView` lacks the
new props.

- [x] **Step 3: Implement `FeedMediaStrip` and lightbox state**

Render no wrapper for `[]`. For one item use `flexBasis: '100%'`; for multiple use
`flexBasis: '78%'`. The scroll container uses:

```ts
{
  display: 'flex',
  overflowX: 'auto',
  scrollSnapType: 'x mandatory',
  gap: 8,
  overscrollBehaviorInline: 'contain',
}
```

Each image is inside a real button with Danish accessible name
`Åbn billede: ${titel || slags || 'medie'}`, `objectFit: 'contain'`, fixed max display
height, neutral theme background, and `scrollSnapAlign: 'start'`. Stop propagation on
the media button. Local nullable index renders existing `Lightbox` with `largeUrl`.

- [x] **Step 4: Implement the shared web person shell**

Use one paper `<article>` as the surface. Inside it:

- a large reset-styled `<button type="button">` containing initial avatar, model name,
  years, kicker/meta, and the card-kind-specific body;
- bookmark as a sibling control, positioned in the header corner;
- media strip as a sibling after the profile button.

The article has `onClick={() => onOpen(card)}` for unused pointer padding but is not in
the tab order. The profile button stops propagation, calls `onOpen(card)`, and handles
browser button keyboard behavior natively. Image and bookmark controls also stop
propagation, so every action fires exactly once.

Move these person cases from the old switch without losing fields:
`portrait`, `dagensperson`, `citat`, `arkiv`, `historie`, `embede`, `jubilaeum`,
`paadennedag`. Remove the mobile-only concept of `Læs mere`; web currently has none.

Change `BookmarkFlag` from a clickable `<span>` to a reset-styled real `<button
type="button">` while preserving its title, SVG, size, colors, and propagation stop.

- [x] **Step 5: Integrate progressive web media loading without feed rebuild**

In `FeedStreamView`:

- derive `FeedMediaRequest[]` only from `shown` cards containing `personId`;
- derive `person` from `model.byId[personId]`, falling back to card `name` when present
  and `#${personId}` otherwise;
- keep `FeedMediaCandidatesByPerson` and `WebFeedMediaByCard` in separate state;
- keep a `requestedPersonIdsRef` so appending a page fetches only unseen canonical
  persons;
- on new shown persons, call `fetchFeedMediaCandidates(missingIds,
  model.canonicalIdById ?? {})` and merge results;
- in a separate cancellable effect, call `resolveFeedMediaForCards(requests,
  candidatesByPerson)` and replace `mediaByCard`;
- when `bookmarkOwnerId` changes, clear both media states and the requested-person set
  before loading under the new auth context;
- include `bookmarkOwnerId` in both async-effect dependencies and set each cleanup's
  `alive=false`, so a late result from the previous auth context cannot repopulate state;
- never add either media state to the effect that creates/resumes `FeedStream`.

Pass `person` and `mediaByCard[card.id] ?? []` into `FeedCardView`.

- [x] **Step 6: Verify web GREEN, typecheck, and build**

Run:

```bash
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web -- src/components/__tests__/PersonFeedCardView.test.tsx src/data/__tests__/feedMedia.test.ts
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm run build --workspace web
```

Expected: focused tests, complete web suite, TypeScript, and Vite build pass.

- [x] **Step 7: Commit**

```bash
git add web/src/components/feed/FeedMediaStrip.tsx web/src/components/feed/PersonFeedCardView.tsx web/src/components/__tests__/PersonFeedCardView.test.tsx web/src/components/feed/FeedCardView.tsx web/src/components/feed/FeedStreamView.tsx web/src/components/primitives.tsx
git commit -m "feat(web): vis personposter med billedstribe"
```

---

### Task 5: Unified mobile person-post shell, swipe strip, and lightbox

**Files:**
- Create: `mobile/src/components/feed/FeedMediaStrip.tsx`
- Create: `mobile/src/components/feed/PersonFeedCardView.tsx`
- Create: `mobile/src/components/feed/__tests__/PersonFeedCardView.test.tsx`
- Modify: `mobile/src/components/feed/FeedCardView.tsx`
- Modify: `mobile/src/app/(tabs)/index.tsx`
- Modify: `mobile/src/components/Lightbox.tsx`

**Interfaces:**
- Consumes: Task 3 `useMobileFeedMedia`/`MobileFeedMediaItem`, `Aux.mediaBy`, model
  `byId`, existing typography/tokens/bookmark/lightbox.
- `PersonFeedCardView` accepts the same conceptual props as web, with `RawMedia[]`:

```ts
{
  card: Extract<FeedCard, { personId: string }>;
  person: { name: string; years: string };
  rawMedia: RawMedia[];
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
}
```

- [x] **Step 1: Write failing React Native interaction tests**

Using the exact Task 3 testing-library dependency, render a real portrait card and mock
only the slow/external `useMobileFeedMedia` boundary with two complete
`MobileFeedMediaItem` rows.

Assert by accessible roles/names:

- initial badge, person name/years, body, and two image controls render;
- press on the large profile target calls `onOpen(card)`;
- press on image opens the real `Lightbox` and does not call `onOpen`;
- press on bookmark calls `onSave(personId)` and does not call `onOpen`;
- firing horizontal `scroll`/`momentumScrollEnd` on the media strip does not call
  `onOpen`;
- no media result renders no adjustable/image strip;
- portrait no longer contains the `Læs mere ›` target;
- `arkiv` keeps clause/year/category/source in the shared shell;
- a `gods` card remains on the existing non-person branch.

- [x] **Step 2: Run focused test and verify RED**

Run:

```bash
npm test --workspace mobile -- src/components/feed/__tests__/PersonFeedCardView.test.tsx --runInBand
```

Expected: FAIL because the new component and props do not exist.

- [x] **Step 3: Implement mobile media strip**

Use a horizontal `ScrollView` with:

```tsx
horizontal
showsHorizontalScrollIndicator={false}
decelerationRate="fast"
snapToAlignment="start"
contentContainerStyle={{ gap: 8 }}
accessibilityLabel="Billeder tilknyttet personen"
```

Measure available width with `onLayout`. One image uses the full measured width; multiple
images use `Math.round(width * 0.78)` and `snapToInterval={itemWidth + 8}`. Each image is
an independent `Pressable` labeled `Åbn billede: …`, with `expo-image`
`contentFit="contain"` and a neutral token-backed surface. Local nullable index renders
the existing `Lightbox` with `largeUri`.

- [x] **Step 4: Implement mobile shared person shell**

Use a non-pressable card `View`. Inside it:

- one large `Pressable` containing initials, model name/years, kicker/meta, and
  kind-specific body;
- bookmark as an absolutely positioned sibling `Pressable`;
- `FeedMediaStrip` as a sibling, never nested in the profile `Pressable`.

Move the same eight person cases as web into this component. Remove `Læs mere ›`.
All non-person cases remain in `FeedCardView`.

Add Danish accessibility labels to Lightbox close/previous/next controls while keeping
existing behavior.

- [x] **Step 5: Wire mobile model and `Aux.mediaBy`**

In `mobile/src/app/(tabs)/index.tsx` render:

```tsx
const pid = bookmarkPersonId(item);
const person = pid ? model?.byId[pid] : null;
<FeedCardView
  card={item}
  person={person ? { name: person.name, years: person.years } : undefined}
  rawMedia={pid ? aux?.mediaBy[pid] ?? [] : []}
  ...
/>
```

`FeedCardView` supplies a safe name fallback from card fields/`#personId` if a model row
is unexpectedly absent. Media signing remains inside each visible person card through
`useMobileFeedMedia`; only Task 1's selected maximum four paths reach the signing hook.

- [x] **Step 6: Verify mobile GREEN, typecheck, and suite**

Run:

```bash
npm test --workspace mobile -- src/components/feed/__tests__/PersonFeedCardView.test.tsx src/lib/__tests__/feedMedia.test.ts --runInBand
npm test --workspace mobile -- --runInBand
npx tsc --noEmit -p mobile/tsconfig.json
```

Expected: focused and full mobile tests pass, TypeScript passes, and only established
offline Supabase warnings remain.

- [x] **Step 7: Run cross-workspace acceptance gates**

Run:

```bash
npm test --workspace packages/feed
npm test --workspace packages/core
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm test --workspace web
VITE_SUPABASE_URL=https://example.supabase.co VITE_SUPABASE_ANON_KEY=test-anon-key npm run build --workspace web
npm test --workspace mobile -- --runInBand
npx tsc --noEmit -p mobile/tsconfig.json
git diff --check
```

Also verify the changed-file list contains no SQL, migration, RLS, redaktion, upload, or
publication files.

- [x] **Step 8: Commit**

```bash
git add mobile/src/components/feed/FeedMediaStrip.tsx mobile/src/components/feed/PersonFeedCardView.tsx mobile/src/components/feed/__tests__/PersonFeedCardView.test.tsx mobile/src/components/feed/FeedCardView.tsx 'mobile/src/app/(tabs)/index.tsx' mobile/src/components/Lightbox.tsx
git commit -m "feat(mobile): vis personposter med billedstribe"
```

After this task, the controller performs the branch-wide review and visual smoke tests
before presenting integration options.

---

## Status (2026-07-26): Tasks 1–5 done, scope decision applied

All five tasks implemented and committed. Last review before handoff (by Codex) found
commit `fa4c018` ("invalidér direkte signering ved authskift") had extended the feed's
auth-epoch invalidation into `mobile/src/data/mediaDedup.ts`,
`mobile/src/data/presensLinjer.ts`, `mobile/src/app/praesens.tsx`, and
`mobile/src/components/redaktion/MediaUploadSheet.tsx` — all redaktion upload/resume
territory, violating the Global Constraint against touching those flows. Codex
recommended reverting and stopped without deciding; the user asked for the remaining
work including this finding, and the Global Constraint itself makes the call, so option
A (scope-limit to feed/media display) was applied rather than asked again.

**Step 1 — reverted `fa4c018`** (commit `f38a0c6`). `mediaDedup.ts`, `presensLinjer.ts`,
`praesens.tsx`, and `MediaUploadSheet.tsx` are byte-identical to `main` again.

**Step 2 — found the leak went one level deeper.** The two earlier commits (`d8cd1f2`,
`cc9cc00`) that survived the revert had themselves changed the *shared*
`useMediaAndThumbUris` hook in `mobile/src/lib/media.ts` (requestKey/epoch-tagged state,
clears to `{}` immediately on auth or path change). That hook isn't feed-only — it's
called directly by six redaktion/reader screens (`app/redaktion/entitet/[type].tsx`,
`.../slaegt-narrativ.tsx`, `.../medie/[id].tsx`, `app/redaktion/person/[id].tsx`,
`components/redaktion/MaterialeSektion.tsx`, `components/NarrativRenderer.tsx`) plus
`usePersonMedia` (used by the reader's `app/person/[id].tsx`). Changing its clear-timing
changes observable render behavior on all of those screens — the same class of scope
violation as `fa4c018`, just via a shared function instead of direct file edits.

**Fix (commit `6a7de7b`):** restored `useMediaAndThumbUris` in `lib/media.ts` to be
byte-identical to its pre-branch form (verified with a direct diff against the
pre-Task-3 commit). The auth-epoch invalidation now lives only in a local
`useFeedMediaUris` hook inside `mobile/src/lib/feedMedia.ts` (feed-only file), consumed
solely by `useMobileFeedMedia`. `useMediaAuthEpoch` stays exported from `lib/media.ts`
as a generic subscription primitive (harmless — a no-op for anyone who doesn't call it),
but no redaktion or reader screen does. `mediaOwner.test.tsx` now exercises
`useMobileFeedMedia` instead of the shared hook directly.

**Why `signPaths` itself staying modified doesn't count as touching redaktion:** the full
residual diff of `lib/media.ts` vs `main` is exactly four things — the `authEpoch`
counter/listener set, `onAuthStateChange` also bumping it, exported `useMediaAuthEpoch`,
and `signPaths`' optional `epoch` param with an epoch-namespaced cache key.
`mediaDedup.ts`/`presensLinjer.ts` still call `signPaths(paths)` with no explicit epoch
(defaults to current), and `cache.clear()` still fires on every auth event exactly as on
`main` — so within one epoch the cache keys are stable, and namespacing them by epoch
cannot produce a hit the old path-keyed cache wouldn't already have produced. Default-
epoch callers see identical results to `main`.

**Web-side symmetry:** `web/src/data/media.ts` doesn't appear in the changed-file list —
web's shared media/signing layer was never touched. Web's feed media went entirely
through the new `web/src/data/feedMedia.ts`, calling the existing `signPaths` unchanged.
No mirror fix was needed on the web side.

**Parked, not fixed here:** `fetchExistingMediaBySha` (`mediaDedup.ts`) calls
`signPaths(paths)` with the default epoch captured at call time — if auth changes
mid-`await`, the dedup flow can resolve with a stale signed URL. This race is
pre-existing on `main` (confirmed by reading `main`'s version), not introduced by this
branch, and fixing it means touching the redaktion upload/resume flow this plan
explicitly excludes. Backlog item for a separate, dedicated change. The user can choose
option B (harden it now, in a follow-up PR) if preferred.

**Verification run after both fixes** (all green): `packages/feed` (129 tests),
`packages/core` (304 tests), `web` (545 tests) + build, `mobile` full suite (417 tests) +
`tsc --noEmit -p mobile/tsconfig.json`, `git diff --check`. Changed-file list vs `main`
reviewed twice (before and after the second fix) — no SQL, migration, RLS, redaktion, or
upload/publication files present either time. `git diff main -- mediaDedup.ts
presensLinjer.ts praesens.tsx MediaUploadSheet.tsx` is empty.

**Not run:** visual/device smoke tests (no simulator/device driven this session). Unit +
typecheck + build confirm the code is wired correctly; they don't confirm the feed cards
render and swipe correctly on a real screen, or that the six redaktion/reader screens
using `useMediaAndThumbUris` still look/feel identical to `main` in practice (the byte-
identical diff is strong evidence but isn't the same as eyes on a device).
