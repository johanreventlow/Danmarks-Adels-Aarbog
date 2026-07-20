import {
  buildResumeMediaUploadPlan,
  decideMediaDedup,
  deriveMediaDedupTarget,
  ensureExistingMediaLinked,
  executeMediaDedupResume,
  fetchExistingMediaBySha,
  fetchMediaLinked,
  mediaDetailRoute,
  queryMediaBySha,
  relationFiltersForTarget,
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
  ] as const)('afleder de fire mål og deres præcise relationsretning', (raw, target, filters) => {
    expect(deriveMediaDedupTarget(raw)).toEqual(target);
    expect(relationFiltersForTarget('91', target)).toEqual(filters);
  });

  it('afviser manglende/ukendt mål', () => {
    expect(deriveMediaDedupTarget({})).toBeNull();
    expect(deriveMediaDedupTarget({ objektType: 'organisation', objektId: '7' })).toBeNull();
  });

  it.each([[{ id: 1 }, true], [null, false]] as const)('bruger relation-opslaget autoritativt', async (data, expected) => {
    const seen: Record<string, string>[] = [];
    const linked = await fetchMediaLinked('91', { maalType: 'person', maalId: '42' }, async (filters) => {
      seen.push(filters);
      return { data, error: null };
    });
    expect(linked).toBe(expected);
    expect(seen).toEqual([{
      subjekt_type: 'person', subjekt_id: '42', objekt_type: 'media', objekt_id: '91', rolle: 'afbildet',
    }]);
  });

  it('kaster relation-opslagsfejl eksplicit', async () => {
    await expect(fetchMediaLinked('91', { maalType: 'estate', maalId: '7' }, async () => ({
      data: null, error: { message: 'relation lookup failed' },
    }))).rejects.toThrow('relation lookup failed');
  });
});

describe('mediaDedup — eksisterende medie og dialogbeslutning', () => {
  it('default-adapteren vælger id::text og bevarer sha-filteret', async () => {
    const calls: unknown[] = [];
    const client = {
      from: (table: string) => {
        calls.push(['from', table]);
        return { select: (columns: string) => {
          calls.push(['select', columns]);
          return { eq: (column: string, value: string) => {
            calls.push(['eq', column, value]);
            return { maybeSingle: async () => {
              calls.push(['maybeSingle']);
              return { data: { id: '9223372036854775807', titel: 'Stor id', upload_status: 'klar', storage_path: 'large.jpg' }, error: null };
            } };
          } };
        } };
      },
    };
    const result = await queryMediaBySha('abc123', client);
    expect(result.data?.id).toBe('9223372036854775807');
    expect(calls).toEqual([
      ['from', 'media'],
      ['select', 'id::text,titel,upload_status,storage_path'],
      ['eq', 'sha256', 'abc123'],
      ['maybeSingle'],
    ]);
  });

  it('viser eksisterende thumb og falder tilbage til signeret storage_path', async () => {
    const mediaLookup = async () => ({ data: {
      id: '91', titel: 'Eksisterende', upload_status: 'klar', storage_path: 'large.jpg',
    }, error: null });
    const withThumb = await fetchExistingMediaBySha('abc', {
      mediaLookup,
      thumbPath: async () => 'thumb.jpg',
      sign: async (paths) => new Map(paths.map((p) => [p, `signed:${p}`])),
    });
    expect(withThumb).toMatchObject({ id: '91', thumbUrl: 'signed:thumb.jpg' });
    const fallback = await fetchExistingMediaBySha('abc', {
      mediaLookup,
      thumbPath: async () => null,
      sign: async (paths) => new Map(paths.map((p) => [p, `signed:${p}`])),
    });
    expect(fallback?.thumbUrl).toBe('signed:large.jpg');
  });

  it('bevarer bigint media-id præcist gennem thumb-opslaget', async () => {
    const mediaId = '9223372036854775807';
    const seen: string[] = [];
    await fetchExistingMediaBySha('abc', {
      mediaLookup: async () => ({ data: {
        id: mediaId, titel: null, upload_status: 'klar', storage_path: 'large.jpg',
      }, error: null }),
      thumbPath: async (id) => { seen.push(id); return null; },
      sign: async () => new Map(),
    });
    expect(seen).toEqual([mediaId]);
  });

  it.each([
    ['klar', false, { kind: 'klar-link', alreadyLinked: false }],
    ['klar', true, { kind: 'klar-link', alreadyLinked: true }],
    ['fjernet', false, { kind: 'fjernet', route: '/redaktion/entitet/medie/91' }],
    ['kladde', false, { kind: 'kladde', alreadyLinked: false }],
    ['kladde', true, { kind: 'kladde', alreadyLinked: true }],
  ] as const)('vælger dialoggren for %s/linked=%s', (status, linked, expected) => {
    expect(decideMediaDedup({ id: '91', uploadStatus: status }, linked)).toEqual(expected);
  });

  it('bygger den præcise mobile filside-route', () => {
    expect(mediaDetailRoute('9223372036854775807')).toBe('/redaktion/entitet/medie/9223372036854775807');
  });
});

describe('mediaDedup — confirm-last, dry-run og idempotent link', () => {
  const target = { maalType: 'person' as const, maalId: '42' };
  const large = { tier: 'large' as const, uri: 'file:///large.jpg', storagePath: 'large.jpg', mimeType: 'image/jpeg', byteSize: 10, bredde: 10, hoejde: 10 };
  const variants = [{ tier: 'thumb' as const, uri: 'file:///thumb.jpg', storagePath: 'thumb.jpg', mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1 }];

  it('bygger genoptagelsesplan med varianter mens rækken er kladde og bekræftelse sidst', () => {
    expect(buildResumeMediaUploadPlan('9223372036854775807', large, variants)).toEqual([
      { kind: 'upload', uri: 'file:///large.jpg', storagePath: 'large.jpg', mimeType: 'image/jpeg' },
      { kind: 'upload', uri: 'file:///thumb.jpg', storagePath: 'thumb.jpg', mimeType: 'image/jpeg' },
      { kind: 'rpc', fn: 'red_registrer_media_variant', args: {
        p_media_id: '9223372036854775807', p_tier: 'thumb', p_storage_path: 'thumb.jpg',
        p_mime: 'image/jpeg', p_byte_size: 1, p_bredde: 1, p_hoejde: 1,
      } },
      { kind: 'rpc', fn: 'red_bekraeft_media_upload', args: { p_media_id: '9223372036854775807' } },
    ]);
  });

  it('dry-run udfører hverken Storage, RPC, link eller refresh', async () => {
    const calls: string[] = [];
    expect(await executeMediaDedupResume({ dryRun: true, mediaId: '91', alreadyLinked: false, target, large, variants }, {
      upload: async () => { calls.push('upload'); },
      rpc: async () => { calls.push('rpc'); },
      link: async () => { calls.push('link'); },
      refresh: async () => { calls.push('refresh'); },
    })).toEqual({ kind: 'dry-run' });
    expect(calls).toEqual([]);
  });

  it('genoptager eksisterende id i rigtig rækkefølge og linker bagefter', async () => {
    const calls: unknown[] = [];
    await executeMediaDedupResume({ dryRun: false, mediaId: '91', alreadyLinked: false, target, large, variants }, {
      upload: async (uri) => { calls.push(['upload', uri]); },
      rpc: async (fn) => { calls.push(['rpc', fn]); },
      link: async (mediaId) => { calls.push(['link', mediaId]); },
      refresh: async () => { calls.push(['refresh']); },
    });
    expect(calls).toEqual([
      ['upload', 'file:///large.jpg'], ['upload', 'file:///thumb.jpg'],
      ['rpc', 'red_registrer_media_variant'], ['rpc', 'red_bekraeft_media_upload'],
      ['link', '91'], ['refresh'],
    ]);
  });

  it.each([false, true])('sluger præcis already-linked-race, også stale alreadyLinked=%s', async (alreadyLinked) => {
    const calls: string[] = [];
    await ensureExistingMediaLinked({ mediaId: '91', target, alreadyLinked }, {
      link: async () => { calls.push('link'); throw new Error('Mediet er allerede tilknyttet dette subjekt'); },
      refresh: async () => { calls.push('refresh'); },
    });
    expect(calls).toEqual(['link', 'refresh']);
  });

  it('forsøger link trods stale linked=true og sluger ikke andre fejl', async () => {
    const calls: string[] = [];
    await ensureExistingMediaLinked({ mediaId: '91', target, alreadyLinked: true }, {
      link: async () => { calls.push('link'); }, refresh: async () => { calls.push('refresh'); },
    });
    expect(calls).toEqual(['link', 'refresh']);
    await expect(ensureExistingMediaLinked({ mediaId: '91', target, alreadyLinked: false }, {
      link: async () => { throw new Error('forbindelse tabt'); }, refresh: async () => {},
    })).rejects.toThrow('forbindelse tabt');
  });
});
