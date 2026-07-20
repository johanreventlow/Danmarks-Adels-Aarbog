import {
  decideMediaDedup, deriveMediaDedupTarget, ensureExistingMediaLinked,
  executeMediaDedupResume, fetchExistingMediaBySha, fetchMediaLinked,
  mediaDetailRoute, relationFiltersForTarget,
} from '../mediaDedup';

describe('mediaDedup — målretning og autoritativ relation', () => {
  it.each([
    [{ afbildetPersonId: '42' }, { maalType: 'person', maalId: '42' }, {
      subjekt_type: 'person', subjekt_id: '42', objekt_type: 'media', objekt_id: '91', rolle: 'afbildet',
    }],
    [{ objektType: 'estate', objektId: '7' }, { maalType: 'estate', maalId: '7' }, {
      subjekt_type: 'media', subjekt_id: '91', objekt_type: 'estate', objekt_id: '7', rolle: 'afbildet',
    }],
    [{ objektType: 'coat_of_arms', objektId: 8 }, { maalType: 'coat_of_arms', maalId: '8' }, {
      subjekt_type: 'media', subjekt_id: '91', objekt_type: 'coat_of_arms', objekt_id: '8', rolle: 'afbildet',
    }],
    [{ objektType: 'lineage', objektId: '9' }, { maalType: 'lineage', maalId: '9' }, {
      subjekt_type: 'media', subjekt_id: '91', objekt_type: 'lineage', objekt_id: '9', rolle: 'afbildet',
    }],
  ] as const)('afleder de fire tilladte mål og deres præcise relationsretning', (raw, target, filters) => {
    expect(deriveMediaDedupTarget(raw)).toEqual(target);
    expect(relationFiltersForTarget('91', target)).toEqual(filters);
  });

  it('afviser manglende/ukendt mål', () => {
    expect(deriveMediaDedupTarget({})).toBeNull();
    expect(deriveMediaDedupTarget({ objektType: 'organisation', objektId: '7' })).toBeNull();
  });

  it.each([[{ id: 1 }, true], [null, false]] as const)('bruger lookup-resultatet autoritativt (%j → %s)', async (data, expected) => {
    const seen: Record<string, string>[][] = [];
    const linked = await fetchMediaLinked('91', { maalType: 'person', maalId: '42' }, async (filters) => {
      seen.push(filters);
      return { data, error: null };
    });
    expect(linked).toBe(expected);
    expect(seen).toEqual([{
      subjekt_type: 'person', subjekt_id: '42', objekt_type: 'media', objekt_id: '91', rolle: 'afbildet',
    }]);
  });

  it('kaster autoritative lookup-fejl eksplicit', async () => {
    await expect(fetchMediaLinked('91', { maalType: 'estate', maalId: '7' }, async () => ({
      data: null, error: { message: 'relation lookup failed' },
    }))).rejects.toThrow('relation lookup failed');
  });
});

describe('mediaDedup — eksisterende medie og dialogbeslutning', () => {
  it('viser det eksisterende thumb; falder tilbage til signeret storage_path', async () => {
    const mediaLookup = async () => ({ data: {
      id: 91, titel: 'Eksisterende titel', upload_status: 'klar', storage_path: 'large.jpg',
    }, error: null });
    const withThumb = await fetchExistingMediaBySha('abc', {
      mediaLookup,
      thumbPaths: async () => new Map([['91', 'thumb.jpg']]),
      sign: async (paths) => new Map(paths.map((p) => [p, `signed:${p}`])),
    });
    expect(withThumb).toMatchObject({ id: '91', titel: 'Eksisterende titel', thumbUrl: 'signed:thumb.jpg' });

    const fallback = await fetchExistingMediaBySha('abc', {
      mediaLookup,
      thumbPaths: async () => new Map(),
      sign: async (paths) => new Map(paths.map((p) => [p, `signed:${p}`])),
    });
    expect(fallback?.thumbUrl).toBe('signed:large.jpg');
  });

  it('bevarer et bigint media-id præcist gennem thumb-opslaget', async () => {
    const mediaId = '9223372036854775807';
    const seen: Array<Array<number | string>> = [];
    await fetchExistingMediaBySha('abc', {
      mediaLookup: async () => ({ data: {
        id: mediaId, titel: 'Stor id', upload_status: 'klar', storage_path: 'large.jpg',
      }, error: null }),
      thumbPaths: async (ids) => { seen.push(ids); return new Map(); },
      sign: async () => new Map(),
    });
    expect(seen).toEqual([[mediaId]]);
  });

  it.each([
    ['klar', false, { kind: 'klar-link' }],
    ['klar', true, { kind: 'klar-linked' }],
    ['fjernet', false, { kind: 'fjernet', route: '/redaktion/media/91' }],
    ['kladde', false, { kind: 'kladde', alreadyLinked: false }],
    ['kladde', true, { kind: 'kladde', alreadyLinked: true }],
  ] as const)('vælger dialoggren for %s/linked=%s', (status, linked, expected) => {
    expect(decideMediaDedup({ id: '91', uploadStatus: status }, linked)).toEqual(expected);
  });

  it('bygger den præcise filside-route', () => {
    expect(mediaDetailRoute('9223372036854775807')).toBe('/redaktion/media/9223372036854775807');
  });
});

describe('mediaDedup — idempotent link og kladdegenoptagelse', () => {
  const target = { maalType: 'person' as const, maalId: '42' };
  const large = { tier: 'large' as const, file: new Blob(['l']), storagePath: 'large.jpg', mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1 };
  const variants = [{ tier: 'thumb' as const, file: new Blob(['t']), storagePath: 'thumb.jpg', mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1 }];

  it('dry-run udfører hverken Storage/resume, relation-RPC eller refresh', async () => {
    const calls: string[] = [];
    expect(await executeMediaDedupResume({ dryRun: true, mediaId: '91', alreadyLinked: false, target, large, variants }, {
      resume: async () => { calls.push('resume'); },
      link: async () => { calls.push('link'); },
      refresh: async () => { calls.push('refresh'); },
    })).toEqual({ kind: 'dry-run' });
    expect(calls).toEqual([]);
  });

  it('genoptager og linker med det eksisterende media-id', async () => {
    const calls: unknown[] = [];
    await executeMediaDedupResume({ dryRun: false, mediaId: '91', alreadyLinked: false, target, large, variants }, {
      resume: async (mediaId) => { calls.push(['resume', mediaId]); },
      link: async (mediaId, t) => { calls.push(['link', mediaId, t]); },
      refresh: async () => { calls.push(['refresh']); },
    });
    expect(calls).toEqual([
      ['resume', '91'], ['link', '91', target], ['refresh'],
    ]);
  });

  it('behandler en allerede-tilknyttet relationsrace som idempotent succes og refresher', async () => {
    const calls: string[] = [];
    await ensureExistingMediaLinked({ mediaId: '91', target, alreadyLinked: false }, {
      link: async () => { calls.push('link'); throw new Error('Mediet er allerede tilknyttet dette subjekt'); },
      refresh: async () => { calls.push('refresh'); },
    });
    expect(calls).toEqual(['link', 'refresh']);
  });

  it('sluger ikke andre linkfejl', async () => {
    await expect(ensureExistingMediaLinked({ mediaId: '91', target, alreadyLinked: false }, {
      link: async () => { throw new Error('forbindelse tabt'); }, refresh: async () => {},
    })).rejects.toThrow('forbindelse tabt');
  });
});
