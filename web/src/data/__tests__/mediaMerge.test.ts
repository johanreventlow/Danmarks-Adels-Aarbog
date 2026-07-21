import type { MediaAnvendelse, MediaBibliotekPost } from '../redaktionRead';
import {
  buildMediaMergePlan,
  executeMediaMerge,
  findMediaMergeCandidates,
  mediaMentionFingerprint,
  sortMediaForQueue,
} from '../mediaMerge';

const media = (overrides: Partial<MediaBibliotekPost>): MediaBibliotekPost => ({
  id: '1', slags: 'foto', titel: null, kunstner: null, datering: null,
  storagePath: null, uploadStatus: 'klar', maaPubliceres: false, rettighederStatus: 'ukendt',
  mimeType: 'image/jpeg', byteSize: 100, bredde: 10, hoejde: 20, originalFilnavn: null,
  createdAt: null, url: null, thumbUrl: null, antalAfbildet: 0, antalMentions: 0, koeer: [],
  ...overrides,
});

const anvendelse = (
  afbildet: MediaAnvendelse['afbildet'] = [],
  mentions: MediaAnvendelse['mentions'] = [],
): MediaAnvendelse => ({ afbildet, mentions });

describe('mediaMerge — køsortering og kandidater', () => {
  it('sorterer kun strandede ældste først og lægger null/ugyldig alder sidst', () => {
    const rows = [
      media({ id: 'null', createdAt: null }),
      media({ id: 'ny', createdAt: '2026-07-20T10:00:00Z' }),
      media({ id: 'ugyldig', createdAt: 'ikke-en-dato' }),
      media({ id: 'gammel', createdAt: '2026-07-18T10:00:00Z' }),
    ];
    expect(sortMediaForQueue(rows, 'strandede').map((m) => m.id))
      .toEqual(['gammel', 'ny', 'null', 'ugyldig']);
    expect(sortMediaForQueue(rows, 'alle').map((m) => m.id))
      .toEqual(['null', 'ny', 'ugyldig', 'gammel']);
    expect(rows.map((m) => m.id)).toEqual(['null', 'ny', 'ugyldig', 'gammel']);
  });

  it('finder øvrige klar-medier med samme fulde trilling, også når kopien er fjernet', () => {
    const copy = media({ id: '9223372036854775807', uploadStatus: 'fjernet' });
    const rows = [
      copy,
      media({ id: '9007199254740992', titel: 'Original' }),
      media({ id: '3', byteSize: 101 }),
      media({ id: '4', uploadStatus: 'fjernet' }),
      media({ id: '5', bredde: null }),
    ];
    expect(findMediaMergeCandidates(copy, rows).map((m) => m.id))
      .toEqual(['9007199254740992']);
  });

  it('kræver at alle tre nøgleværdier er ikke-null', () => {
    const copy = media({ id: '1', hoejde: null });
    expect(findMediaMergeCandidates(copy, [copy, media({ id: '2', hoejde: null })])).toEqual([]);
  });

  it('viser ikke flet for en kladde, selv om trillingen matcher en klar række', () => {
    const copy = media({ id: '1', uploadStatus: 'kladde' });
    expect(findMediaMergeCandidates(copy, [copy, media({ id: '2' })])).toEqual([]);
  });
});

describe('mediaMerge — autoritativ, genoptagelig orkestrering', () => {
  const person = { type: 'person', id: '9007199254740992', navn: 'Person', relationId: '9223372036854775806' };
  const estate = { type: 'estate', id: '7', navn: 'Gods', relationId: '81' };
  const mention = { kildeType: 'narrative', kildeId: '22', subjektNavn: 'Fortællingens person' };
  const noRelationEvidence = async () => [];

  it('fingerprinter mention-snapshots deterministisk uafhængigt af rækkefølge', () => {
    const anden = { kildeType: 'note', kildeId: '9223372036854775807', subjektNavn: 'Et navn' };
    expect(mediaMentionFingerprint([mention, anden])).toBe(mediaMentionFingerprint([anden, mention]));
    expect(mediaMentionFingerprint([mention])).not.toBe(mediaMentionFingerprint([anden]));
  });

  it('bygger fjern-før-flyt i korrekt rækkefølge og med mention-advarselsmetadata', () => {
    const plan = buildMediaMergePlan({
      copyId: '9223372036854775807', copyStatus: 'klar', originalId: '9007199254740993',
      copyAnvendelse: anvendelse([person, estate], [mention]),
      originalAnvendelse: anvendelse(),
    });
    expect(plan.mentions).toEqual([mention]);
    expect(plan.steps.map((s) => s.kind)).toEqual([
      'soft-delete-copy',
      'link-original', 'delete-copy-relation',
      'link-original', 'delete-copy-relation',
    ]);
    expect(plan.steps.map((s) => s.change)).toEqual([
      { art: 'fjernMedia', subjektType: 'media', subjektId: '9223372036854775807', mediaId: '9223372036854775807' },
      { art: 'tilknytMedia', subjektType: 'media', subjektId: '9007199254740993', mediaId: '9007199254740993', payload: { maalType: 'person', maalId: '9007199254740992' } },
      { art: 'sletMediaRelationUdenEvidens', subjektType: 'media', subjektId: '9223372036854775807', relationId: '9223372036854775806' },
      { art: 'tilknytMedia', subjektType: 'media', subjektId: '9007199254740993', mediaId: '9007199254740993', payload: { maalType: 'estate', maalId: '7' } },
      { art: 'sletMediaRelationUdenEvidens', subjektType: 'media', subjektId: '9223372036854775807', relationId: '81' },
    ]);
  });

  it('springer link over når originalen allerede har målet, men rydder kopiens relation', () => {
    const plan = buildMediaMergePlan({
      copyId: '91', copyStatus: 'fjernet', originalId: '92',
      copyAnvendelse: anvendelse([person]),
      originalAnvendelse: anvendelse([{ ...person, relationId: '99' }]),
    });
    expect(plan.steps.map((s) => s.kind)).toEqual(['delete-copy-relation']);
  });

  it('dry-run henter autoritativ tilstand og returnerer sekvensen uden executor-kald', async () => {
    const calls: string[] = [];
    const result = await executeMediaMerge({
      copyId: '91', originalId: '92', dryRun: true,
      confirmedMentionFingerprint: mediaMentionFingerprint([mention]),
    }, {
      loadState: async () => {
        calls.push('load');
        return { copyStatus: 'klar', copyAnvendelse: anvendelse([estate], [mention]), originalAnvendelse: anvendelse() };
      },
      loadRelationEvidence: noRelationEvidence,
      execute: async () => { calls.push('execute'); },
    });
    expect(calls).toEqual(['load']);
    expect(result.kind).toBe('dry-run');
    if (result.kind === 'mentions-changed') throw new Error('unexpected mention guard');
    expect(result.plan.steps.map((s) => s.kind)).toEqual(['soft-delete-copy', 'link-original', 'delete-copy-relation']);
    expect(result.plan.mentions).toEqual([mention]);
  });

  it.each([
    ['tilføjet', [mention], [mention, { kildeType: 'narrative', kildeId: '23', subjektNavn: 'Ny' }]],
    ['fjernet', [mention], []],
    ['ændret', [mention], [{ ...mention, subjektNavn: 'Nyt navn' }]],
  ] as const)('stopper uden writes når en mention er %s siden bekræftelsen', async (_case, confirmed, current) => {
    const calls: string[] = [];
    const result = await executeMediaMerge({
      copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([...confirmed]),
    }, {
      loadState: async () => ({ copyStatus: 'klar', copyAnvendelse: anvendelse([], [...current]), originalAnvendelse: anvendelse() }),
      loadRelationEvidence: noRelationEvidence,
      execute: async () => { calls.push('write'); },
    });
    expect(result).toMatchObject({ kind: 'mentions-changed', state: { copyAnvendelse: { mentions: [...current] } } });
    expect(calls).toEqual([]);
  });

  it('kan genkøres efter afbrydelse: fjernet kopi springes over og en allerede flyttet relation afkobles', async () => {
    let copyStatus = 'klar';
    let originalHasPerson = false;
    let copyHasPerson = true;
    let interrupt = true;
    const calls: string[] = [];
    const deps = {
      loadState: async () => ({
        copyStatus,
        copyAnvendelse: anvendelse(copyHasPerson ? [person] : []),
        originalAnvendelse: anvendelse(originalHasPerson ? [{ ...person, relationId: '99' }] : []),
      }),
      loadRelationEvidence: noRelationEvidence,
      execute: async (change: { art: string }) => {
        calls.push(change.art);
        if (change.art === 'fjernMedia') copyStatus = 'fjernet';
        if (change.art === 'tilknytMedia') originalHasPerson = true;
        if (change.art === 'sletMediaRelationUdenEvidens') {
          if (interrupt) { interrupt = false; throw new Error('netværk afbrudt'); }
          copyHasPerson = false;
        }
      },
    };
    await expect(executeMediaMerge({ copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([]) }, deps))
      .rejects.toThrow('netværk afbrudt');
    expect([copyStatus, originalHasPerson, copyHasPerson]).toEqual(['fjernet', true, true]);

    await executeMediaMerge({ copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([]) }, deps);
    expect(calls).toEqual(['fjernMedia', 'tilknytMedia', 'sletMediaRelationUdenEvidens', 'sletMediaRelationUdenEvidens']);
    expect(copyHasPerson).toBe(false);
  });

  it('behandler kun den præcise already-linked-race idempotent og fortsætter med afkobling', async () => {
    const calls: string[] = [];
    await executeMediaMerge({ copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([]) }, {
      loadState: async () => ({ copyStatus: 'fjernet', copyAnvendelse: anvendelse([person]), originalAnvendelse: anvendelse() }),
      loadRelationEvidence: noRelationEvidence,
      execute: async (change) => {
        calls.push(change.art);
        if (change.art === 'tilknytMedia') throw new Error('Mediet er allerede tilknyttet dette subjekt');
      },
    });
    expect(calls).toEqual(['tilknytMedia', 'sletMediaRelationUdenEvidens']);
  });

  it('stopper på en anden linkfejl før kopiens relation slettes', async () => {
    const calls: string[] = [];
    await expect(executeMediaMerge({ copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([]) }, {
      loadState: async () => ({ copyStatus: 'fjernet', copyAnvendelse: anvendelse([person]), originalAnvendelse: anvendelse() }),
      loadRelationEvidence: noRelationEvidence,
      execute: async (change) => {
        calls.push(change.art);
        if (change.art === 'tilknytMedia') throw new Error('forbindelse tabt');
      },
    })).rejects.toThrow('forbindelse tabt');
    expect(calls).toEqual(['tilknytMedia']);
  });

  it('stopper uden writes når en kopirelation har evidens', async () => {
    const calls: string[] = [];
    await expect(executeMediaMerge({ copyId: '91', originalId: '92', dryRun: false,
      confirmedMentionFingerprint: mediaMentionFingerprint([]) }, {
      loadState: async () => ({
        copyStatus: 'klar', copyAnvendelse: anvendelse([person]), originalAnvendelse: anvendelse(),
      }),
      loadRelationEvidence: async (relationIds) => {
        calls.push(`evidence:${relationIds.join(',')}`);
        return [person.relationId];
      },
      execute: async (change) => { calls.push(change.art); },
    })).rejects.toThrow('evidens');
    expect(calls).toEqual([`evidence:${person.relationId}`]);
  });
});
