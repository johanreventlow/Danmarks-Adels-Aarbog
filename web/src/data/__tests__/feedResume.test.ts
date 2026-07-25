import { describe, expect, it } from 'vitest';
import { createFeedStream, resumeStream, type FeedCard, type Model } from '@daa/feed';
import { buildModel } from '@daa/core';
import { preserveShownForResume } from '../feedResume';

describe('preserveShownForResume', () => {
  it('fjerner et forældet terminalkort men bevarer det viste præfiks', () => {
    const shown: FeedCard[] = [
      { kind: 'gods', id: 'gods:1', estateId: '1', navn: 'A', meta: '', ownerDots: 0, kicker: 'Gods' },
      { kind: 'samle', id: 'samle:personer', count: 920, tail: 'personer i registeret', kicker: 'Registeret' },
      { kind: 'vaaben', id: 'vaaben:1', armsId: '1', blazon: 'B', foot: '', kicker: 'Våben' },
    ];
    expect(preserveShownForResume(shown).map((card) => card.id)).toEqual(['gods:1', 'vaaben:1']);
  });

  it('lader den genbyggede strøm levere et opdateret terminalkort til sidst', () => {
    // died: 1700 → sikkert død (levende.ts's GDPR-gate i buildFeedOrder ekskluderer ellers
    // alle tre, uafhængigt af bio-berigelsen testen faktisk øver på).
    const raw = [
      { id: '1', name: 'A', born: null, died: 1700, years: '', title: '', bio: '', privat: false },
      { id: '2', name: 'B', born: null, died: 1700, years: '', title: '', bio: '', privat: false },
      { id: '3', name: 'C', born: null, died: 1700, years: '', title: '', bio: '', privat: false },
    ];
    const model = buildModel({ persons: raw, unions: [], parentChild: [] }) as unknown as Model;
    const aux = { godsListe: [], vaabenListe: [], officesBy: {} };
    const inputs = { seed: 7, todayISO: '2026-07-18', meId: null, focusId: null };
    const initialShown = createFeedStream(model, aux, inputs).next(12);
    expect(initialShown.at(-1)).toMatchObject({ kind: 'samle', count: 3 });

    const persons = model.persons.map((p) => p.id === '3' ? p : ({
      ...p,
      bio: 'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, '
        + 'virke og eftermæle, skrevet med tilstrækkeligt mange detaljer og sammenhæng.',
    }));
    const enriched = { ...model, persons, byId: Object.fromEntries(persons.map((p) => [p.id, p])) };
    const preserved = preserveShownForResume(initialShown);
    const resumed = resumeStream(
      createFeedStream(enriched, aux, inputs),
      new Set(preserved.map((card) => card.id)),
    );
    const finalShown = [...preserved, ...resumed.next(100)];
    expect(finalShown.at(-1)).toMatchObject({ kind: 'samle', count: 1 });
    expect(finalShown.slice(0, -1).some((card) => card.kind === 'samle')).toBe(false);
  });
});
