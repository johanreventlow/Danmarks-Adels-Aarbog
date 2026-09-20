import { describe, it, expect, vi } from 'vitest';

const rpc = vi.hoisted(() => vi.fn());

// public.ts importerer '../supabase' på modul-niveau (kaster uden VITE_SUPABASE_URL/ANON_KEY i
// test-miljøet); public.ts importerer også media.ts, der kalder supabase.auth.onAuthStateChange
// ved modul-load — mockes minimalt, da orThrow selv ikke rører supabase-klienten (samme mønster
// som bookmarks.test.ts).
vi.mock('../../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => {} },
    rpc,
    from: () => {
      const query = {
        select: () => query,
        eq: () => query,
        in: () => query,
        order: () => query,
        range: async () => ({ data: [], error: null }),
        then: (resolve: (value: { data: unknown[]; error: null }) => void) => resolve({ data: [], error: null }),
      };
      return query;
    },
  },
}));

import { supabase } from '../../supabase';
import { fetchPersonDetail, mapPublicBioSourceVersions, mapPublicBioSourceVersionsV2, orThrow } from '../public';

describe('orThrow', () => {
  it('returnerer data når error er null', () => {
    expect(orThrow({ data: [1, 2, 3], error: null }, 'label')).toEqual([1, 2, 3]);
  });

  it('returnerer data når error er undefined', () => {
    expect(orThrow({ data: 'x', error: undefined }, 'label')).toBe('x');
  });

  it('kaster når error er tilstede', () => {
    expect(() => orThrow({ data: null, error: { message: 'boom' } }, 'mit-label')).toThrow(/mit-label/);
  });

  it('den kastede fejls .cause er det oprindelige error-objekt', () => {
    const originalError = { message: 'boom', code: '42P01' };
    try {
      orThrow({ data: null, error: originalError }, 'label');
      expect.unreachable('skulle have kastet');
    } catch (e) {
      expect((e as Error).cause).toBe(originalError);
    }
  });
});

describe('mapPublicBioSourceVersions', () => {
  it('bevarer recorde fra samme bog separat og ignorerer ekstra private felter', () => {
    const versions = mapPublicBioSourceVersions([
      { record_ref: 'safe-b', source_label: 'DAA 1939', record_label: 'Linje I, nr. 2', narrative_text: 'B', citation_label: 's. 2', provenance_kind: 'source_record', source_record_id: 'privat-uuid' },
      { record_ref: 'safe-a', source_label: 'DAA 1939', record_label: 'Linje I, nr. 1', narrative_text: 'A', citation_label: 's. 1', provenance_kind: 'source_record' },
      { record_ref: null, source_label: 'DAA 1939', record_label: 'Overgangsdata', narrative_text: 'Gammel', citation_label: '', provenance_kind: 'legacy_narrative' },
    ]);
    expect(versions.map((v) => v.recordRef)).toEqual(['safe-a', 'safe-b', null]);
    expect(versions[0]).not.toHaveProperty('sourceRecordId');
  });
});

describe('mapPublicBioSourceVersionsV2', () => {
  it('bevarer kun den sikre v2-kontrakt og sorterer med struktureret rækkefølge', () => {
    const versions = mapPublicBioSourceVersionsV2([
      { person_id: 1, source_id: 9, source_year: null, record_order: null, source_record_ref: 'sidst', source_label: 'Z', record_label: 'Z', narrative_text: 'Null-år', citation_label: '', provenance_kind: 'source_record' },
      { person_id: 1, source_id: 3, source_year: 1939, record_order: 2, source_record_ref: 'senere-side', source_label: 'A', record_label: 'Ø', narrative_text: 'Anden', citation_label: 's. 2', provenance_kind: 'source_record', source_record_id: 'privat-uuid' },
      { person_id: 1, source_id: 3, source_year: 1939, record_order: 1, source_record_ref: 'foerste-side', source_label: 'Z', record_label: 'Å', narrative_text: 'Første', citation_label: 's. 1', provenance_kind: 'source_record' },
    ]);
    expect(versions.map((v) => v.sourceRecordRef)).toEqual(['foerste-side', 'senere-side', 'sidst']);
    expect(versions[0]).not.toHaveProperty('sourceRecordId');
  });

  it('lader en fejlformet v2-række være en eksplicit fetch-fejl', () => {
    expect(() => mapPublicBioSourceVersionsV2([
      { person_id: 1, source_id: '3', source_year: 1939, record_order: 1, source_record_ref: 'ref', source_label: 'DAA', record_label: 'Post', narrative_text: 'Tekst', citation_label: '', provenance_kind: 'source_record' },
    ])).toThrow(/source_id/);
  });
});

describe('fetchPersonDetail v2 RPC', () => {
  it('kalder RPCen med Supabase-klienten som receiver og falder ikke tilbage til narrative', async () => {
    rpc.mockReset();
    rpc.mockImplementation(function (this: unknown, name: string) {
      if (this == null) throw new Error('RPC mistede Supabase receiver');
      if (name === 'narrative_record_contract_version') return Promise.resolve({ data: 2, error: null });
      if (name === 'public_person_bio_source_versions_v2') return Promise.resolve({ data: [
        { person_id: 1, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'r1', source_label: 'DAA', record_label: 'Post 1', narrative_text: 'Bundet tekst', citation_label: '', provenance_kind: 'source_record' },
      ], error: null });
      throw new Error(`uventet RPC: ${name}`);
    });
    await expect(fetchPersonDetail('1')).resolves.toMatchObject({ bio: 'Bundet tekst' });
    expect(rpc).toHaveBeenNthCalledWith(1, 'narrative_record_contract_version', {});
    expect(rpc).toHaveBeenNthCalledWith(2, 'public_person_bio_source_versions_v2', { p_person_ids: [1] });
  });

  it('lader en v2 RPC-fejl være en eksplicit hente-fejl', async () => {
    rpc.mockReset();
    rpc
      .mockResolvedValueOnce({ data: 2, error: null })
      .mockResolvedValueOnce({ data: null, error: { message: 'RPC utilgængelig' } });
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(fetchPersonDetail('1')).rejects.toThrow('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
    warn.mockRestore();
  });

  it('lader et synkront v2 RPC-kast være en eksplicit hente-fejl', async () => {
    rpc.mockReset();
    rpc
      .mockResolvedValueOnce({ data: 2, error: null })
      .mockImplementationOnce(() => { throw new Error('synkront RPC-kast'); });
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(fetchPersonDetail('1')).rejects.toThrow('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
    warn.mockRestore();
  });

  it('lader manglende contract-version RPC være en eksplicit hente-fejl', async () => {
    const client = supabase as unknown as { rpc?: typeof rpc };
    const originalRpc = client.rpc;
    client.rpc = undefined;
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    try {
      await expect(fetchPersonDetail('1')).rejects.toThrow('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
    } finally {
      client.rpc = originalRpc;
      warn.mockRestore();
    }
  });

  it('bevarer den tolerante v1-fallback når den gamle RPC afviser', async () => {
    rpc.mockReset();
    rpc
      .mockResolvedValueOnce({ data: 1, error: null })
      .mockRejectedValueOnce(new Error('v1 RPC utilgængelig'));
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(fetchPersonDetail('1')).resolves.toEqual(expect.objectContaining({ bio: '', bioVersions: [] }));
    warn.mockRestore();
  });
});
