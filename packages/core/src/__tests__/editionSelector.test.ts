import { describe, expect, it } from 'vitest';
import { byggUdgaveVaelger } from '../editionSelector';
import type { BioSourceVersionV2 } from '../bioVersions';
import type { Udgave } from '../editionFacts';

const udgaver: Udgave[] = [
  { sourceId: '1', label: 'DAA 1939', aar: 1939 },
  { sourceId: '3', label: 'DAA 2018-20', aar: 2018 },
];

function v(sourceId: number, recordLabel: string, tekst: string, label = sourceId === 1 ? 'DAA 1939' : 'DAA 2018-20'): BioSourceVersionV2 {
  return {
    recordRef: null,
    sourceLabel: label,
    recordLabel,
    narrativeText: tekst,
    citationLabel: '',
    provenanceKind: 'source_record',
    personId: 1,
    sourceId,
    sourceYear: null,
    recordOrder: null,
    sourceRecordRef: null,
  };
}

describe('byggUdgaveVaelger', () => {
  // 2026-11-19: én chip pr. udgave; III-58 (henvisning »Se V-1.«) kan ikke længere vælges.
  it('Conrad: én chip pr. udgave, 2018-20 bærer V-1 (fuld biografi)', () => {
    const r = byggUdgaveVaelger(
      [v(3, 'III-58', 'Se V-1.'), v(1, '1939-post', 'x'.repeat(50)), v(3, 'V-1', 'y'.repeat(500))],
      udgaver,
      ['1', '3'],
    );
    expect(r.chips.map((c) => c.label)).toEqual(['DAA 2018-20', 'DAA 1939']);
    expect(r.standard).toBe(0);
    expect((r.chips[0] as { version: { recordLabel: string } }).version.recordLabel).toBe('V-1');
    expect(r.chips.some((c) => c.art === 'post' && c.version.recordLabel === 'III-58')).toBe(false);
    expect(r.form).toBe('chips');
  });

  it('bogpost foretrækkes for overgangsdata, selv om overgangsdata er længere', () => {
    const legacy = { ...v(3, 'x', 'z'.repeat(900)), provenanceKind: 'legacy_narrative' as const };
    const r = byggUdgaveVaelger([legacy, v(3, 'V-1', 'kort tekst')], udgaver, ['3']);
    expect(r.chips).toHaveLength(1);
    expect((r.chips[0] as { version: { recordLabel: string } }).version.recordLabel).toBe('V-1');
  });

  it('chippen kender alle personens poster i udgaven (også III-58), så en kildelinje kan vælge den', () => {
    const r = byggUdgaveVaelger(
      [{ ...v(3, 'III-58', 'Se V-1.'), recordRef: 'rec-iii58' }, { ...v(3, 'V-1', 'y'.repeat(500)), recordRef: 'rec-v1' }],
      udgaver, ['3'],
    );
    expect((r.chips[0] as { poster: string[] }).poster).toEqual(['rec-iii58', 'rec-v1']);
  });

  it('samme længde: den første post vinder (stabil)', () => {
    const r = byggUdgaveVaelger([v(3, 'A', 'abc'), v(3, 'B', 'xyz')], udgaver, ['3']);
    expect((r.chips[0] as { version: { recordLabel: string } }).version.recordLabel).toBe('A');
  });

  it('1939 med fakta men uden biografi får en udgave-chip', () => {
    const r = byggUdgaveVaelger([v(3, 'V-1', 'tekst')], udgaver, ['1', '3']);
    expect(r.chips).toHaveLength(2);
    expect(r.chips[1]).toEqual({ art: 'udgave', sourceId: '1', label: 'DAA 1939' });
  });

  it('én chip giver form ingen', () => {
    expect(byggUdgaveVaelger([v(3, 'V-1', 'tekst')], udgaver, ['3']).form).toBe('ingen');
  });

  it('ingen biografier og to udgaver giver form skift', () => {
    const r = byggUdgaveVaelger([], udgaver, ['1', '3']);
    expect(r.form).toBe('skift');
    expect(r.chips.map((c) => c.sourceId)).toEqual(['3', '1']);
  });

  it('ingen biografi og ingen fakta giver ingen chips', () => {
    const r = byggUdgaveVaelger([], udgaver, []);
    expect(r.chips).toEqual([]);
    expect(r.form).toBe('ingen');
    expect(r.standard).toBe(0);
  });

  it('postetiket record-uuid vises ikke i chippen', () => {
    const r = byggUdgaveVaelger(
      [v(3, 'record-07565168-b903-4444-9189-43d62d5c6ed6', 'tekst')],
      udgaver,
      ['3'],
    );
    expect(r.chips[0].label).toBe('DAA 2018-20');
  });

  it('overgangsdata og version uden sourceId slås op på label; etiketten er kun udgaven', () => {
    const { sourceId: _s, ...uden } = v(3, 'x', 'tekst');
    const r = byggUdgaveVaelger([{ ...uden, provenanceKind: 'legacy_narrative' }], udgaver, ['3']);
    expect(r.chips[0].label).toBe('DAA 2018-20');
    expect(r.chips[0].sourceId).toBe('3');
  });

  it('nyeste udgave uden biografi: standard er den ældre udgaves post', () => {
    const r = byggUdgaveVaelger([v(1, '1939-post', 'tekst')], udgaver, ['1', '3']);
    expect(r.chips[0]).toEqual({ art: 'udgave', sourceId: '3', label: 'DAA 2018-20' });
    expect(r.chips[r.standard].art).toBe('post');
    expect(r.chips[r.standard].sourceId).toBe('1');
    expect(r.standard).toBe(1);
    expect(r.form).toBe('chips');
  });

  it('tom biografitekst tæller ikke som post', () => {
    const r = byggUdgaveVaelger([v(3, 'V-1', '   ')], udgaver, ['3']);
    expect(r.chips).toEqual([{ art: 'udgave', sourceId: '3', label: 'DAA 2018-20' }]);
    expect(r.form).toBe('ingen');
  });

  it('sourceYear bruges når udgavens aar er ukendt; ukendt år sidst', () => {
    const ukendt: Udgave[] = [
      { sourceId: '1', label: 'A', aar: null },
      { sourceId: '2', label: 'B', aar: null },
      { sourceId: '3', label: 'C', aar: null },
    ];
    const a = { ...v(1, 'x', 'a', 'A'), sourceYear: 1900 };
    const b = { ...v(2, 'x', 'b', 'B'), sourceYear: 2000 };
    const c = v(3, 'x', 'c', 'C');
    const r = byggUdgaveVaelger([c, a, b], ukendt, []);
    expect(r.chips.map((x) => x.sourceId)).toEqual(['2', '1', '3']);
  });

  it('samme år: lavere numerisk sourceId først', () => {
    const lige: Udgave[] = [
      { sourceId: '10', label: 'A', aar: 2000 },
      { sourceId: '9', label: 'B', aar: 2000 },
    ];
    const r = byggUdgaveVaelger([v(10, 'x', 'a', 'A'), v(9, 'x', 'b', 'B')], lige, []);
    expect(r.chips.map((x) => x.sourceId)).toEqual(['9', '10']);
  });
});

describe('chipetiket = udgavens navn (2026-11-19; afløser 6e-2-postetiketten i chippen)', () => {
  const chip = (label: string, citationLabel: string, recordLabel: string) =>
    (byggUdgaveVaelger([{ ...v(1, recordLabel, 'tekst'), sourceLabel: label, citationLabel }], udgaver, []).chips[0] as { label: string }).label;
  it('side og post vises ikke i chippen', () => {
    expect(chip('DAA 1939', 'DAA 1939, s. 49', 'IV, nr. 3')).toBe('DAA 1939');
    expect(chip('DAA 1939', 'DAA 1939 side 538', 'record-07565168-b903-4444-9189-43d62d5c6ed6')).toBe('DAA 1939');
  });
});
