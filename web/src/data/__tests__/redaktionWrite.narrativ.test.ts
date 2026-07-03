import { describe, it, expect } from 'vitest';
import { buildRpcCall } from '../redaktionWrite';

describe('narrativ arg-builder (source-nøglet)', () => {
  it('sender p_source_id + p_side fra payload', () => {
    const call = buildRpcCall({
      art: 'narrativ', subjektType: 'person', subjektId: '5', vaerdi: 'bio',
      payload: { privat: false, sourceId: 2, side: '12' },
    });
    expect(call).toMatchObject({
      fn: 'red_upsert_narrativ',
      args: { p_subjekt_type: 'person', p_subjekt_id: 5, p_tekst: 'bio', p_privat: false, p_source_id: 2, p_side: '12' },
    });
  });
  it('defaulter source_id/side til null når payload mangler dem', () => {
    const call = buildRpcCall({ art: 'narrativ', subjektType: 'person', subjektId: '5', vaerdi: 'bio', payload: { privat: true } });
    expect(call?.args).toMatchObject({ p_privat: true, p_source_id: null, p_side: null });
  });
});

describe('opretKilde arg-builder', () => {
  it('mapper ny DAA-udgave → red_opret_kilde med p_aar', () => {
    const call = buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '',
      payload: { titel: 'DAA 1982-84', slags: 'DAA-udgave', udgave: 'DAA 1982-84', aar: 1982 } });
    expect(call).toMatchObject({ fn: 'red_opret_kilde', args: { p_titel: 'DAA 1982-84', p_slags: 'DAA-udgave', p_udgave: 'DAA 1982-84', p_aar: 1982, p_ekstern: false } });
  });
  it('uden titel → null', () => {
    expect(buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '', payload: {} })).toBeNull();
  });
});
