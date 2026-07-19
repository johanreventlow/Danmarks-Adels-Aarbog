import { describe, expect, it, vi } from 'vitest';
import { createStorySaveGuard, saveStoryWithSources, storySaveClosesEditor } from '../storySave';
import type { Change } from '../redaktionWrite';

const createChange: Change = {
  art: 'opretStory', subjektType: 'person', subjektId: '7',
  payload: { tekst: 'En minihistorie.' },
};
const kilder = [{ sourceId: 2, side: '112' }];

describe('saveStoryWithSources', () => {
  it('bevarer det oprettede story-id og melder delvis gemning når kilderne fejler', async () => {
    const run = vi.fn()
      .mockResolvedValueOnce({ dryRun: false, direkte: true, result: 41 })
      .mockResolvedValueOnce(undefined);

    await expect(saveStoryWithSources(createChange, kilder, run)).resolves.toEqual({
      status: 'sources-failed', storyId: 41,
    });
    expect(run).toHaveBeenNthCalledWith(1, createChange, 'Opret historie', { refresh: false });
    expect(run).toHaveBeenNthCalledWith(2, {
      art: 'setStoryKilder', subjektType: 'person', subjektId: '7', storyId: 41, kilder,
    }, 'Gem historiekilder', { refresh: false });
  });

  it('melder komplet gemning først efter både story og kilder er gemt', async () => {
    const run = vi.fn()
      .mockResolvedValueOnce({ dryRun: false, direkte: true, result: 41 })
      .mockResolvedValueOnce({ dryRun: false, direkte: true, result: null });

    await expect(saveStoryWithSources(createChange, kilder, run)).resolves.toEqual({
      status: 'saved', storyId: 41,
    });
  });

  it('sender kun ét samlet forslag for et medlem', async () => {
    const stagedChange = { ...createChange, kilder };
    const run = vi.fn().mockResolvedValue({ dryRun: false, direkte: false, result: 9 });

    await expect(saveStoryWithSources(stagedChange, kilder, run)).resolves.toEqual({
      status: 'staged', storyId: null,
    });
    expect(run).toHaveBeenCalledTimes(1);
  });

  it('lukker editoren efter gemt story eller vellykket staging, men ikke ved fejl/dry-run', () => {
    expect(storySaveClosesEditor({ status: 'saved', storyId: 41 })).toBe(true);
    expect(storySaveClosesEditor({ status: 'staged', storyId: null })).toBe(true);
    expect(storySaveClosesEditor({ status: 'sources-failed', storyId: 41 })).toBe(false);
    expect(storySaveClosesEditor({ status: 'dry-run', storyId: null })).toBe(false);
  });

  it('single-flight-guarden afviser overlap og invaliderer en sen completion ved editor-skift', () => {
    const guard = createStorySaveGuard();
    const first = guard.start();
    expect(first).not.toBeNull();
    expect(guard.busy).toBe(true);
    expect(guard.start()).toBeNull();

    guard.invalidate();
    expect(guard.isCurrent(first!)).toBe(false);
    expect(guard.busy).toBe(true);

    guard.finish(first!);
    expect(guard.busy).toBe(false);
    expect(guard.start()).not.toBeNull();
  });
});
