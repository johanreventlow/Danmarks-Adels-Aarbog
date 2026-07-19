import type { Change } from './redaktionWrite';

type StoryRunResult = {
  dryRun: boolean;
  direkte: boolean;
  result?: unknown;
} | undefined;

export type StoryRun = (
  change: Change,
  titel: string,
  options?: { refresh?: boolean },
) => Promise<StoryRunResult>;

export type StorySaveOutcome =
  | { status: 'failed' | 'dry-run' | 'staged'; storyId: number | null }
  | { status: 'invalid-story-id'; storyId: null }
  | { status: 'sources-failed' | 'saved'; storyId: number };

export function storySaveClosesEditor(outcome: StorySaveOutcome): boolean {
  return outcome.status === 'saved' || outcome.status === 'staged';
}

// Synkron single-flight + generations-token. invalidate() bruges ved navigation/editor-skift:
// DB-kaldet kan ikke annulleres, men dets sene resultat må ikke mutere det nye UI-udkast.
export function createStorySaveGuard() {
  let generation = 0;
  let activeToken: number | null = null;
  return {
    get busy() { return activeToken != null; },
    start(): number | null {
      if (activeToken != null) return null;
      activeToken = ++generation;
      return activeToken;
    },
    invalidate(): void { generation += 1; },
    isCurrent(token: number): boolean {
      return activeToken === token && generation === token;
    },
    finish(token: number): void {
      if (activeToken === token) activeToken = null;
    },
  };
}

// Story og kilder er to eksisterende RPC'er. Reload udsættes til begge er lykkedes, så
// editoren ikke ryddes mellem kaldene. Hvis kildekaldet fejler efter en oprettelse, returneres
// det persistente id; UI'en kan dermed skifte udkastet til redigering og retry uden en dublet.
export async function saveStoryWithSources(
  change: Change,
  kilder: NonNullable<Change['kilder']>,
  run: StoryRun,
): Promise<StorySaveOutcome> {
  const originalStoryId = change.storyId ?? null;
  const first = await run(
    change,
    change.art === 'opretStory' ? 'Opret historie' : 'Gem historie',
    { refresh: false },
  );
  if (!first) return { status: 'failed', storyId: originalStoryId };
  if (first.dryRun) return { status: 'dry-run', storyId: originalStoryId };
  if (!first.direkte) return { status: 'staged', storyId: originalStoryId };

  const storyId = originalStoryId ?? Number(first.result);
  if (!Number.isFinite(storyId)) return { status: 'invalid-story-id', storyId: null };

  const sources = await run({
    art: 'setStoryKilder', subjektType: change.subjektType, subjektId: change.subjektId,
    storyId, kilder,
  }, 'Gem historiekilder', { refresh: false });
  return sources
    ? { status: 'saved', storyId }
    : { status: 'sources-failed', storyId };
}
