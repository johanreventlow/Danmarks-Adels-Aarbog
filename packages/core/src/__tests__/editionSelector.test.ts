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
  it('Conrad: åbner på V-1, III-58 er stadig en chip', () => {
    const r = byggUdgaveVaelger(
      [v(3, 'III-58', 'kort'), v(1, '1939-post', 'x'.repeat(50)), v(3, 'V-1', 'y'.repeat(500))],
      udgaver,
      ['1', '3'],
    );
    expect(r.standard).toBe(0);
    expect((r.chips[0] as { version: { recordLabel: string } }).version.recordLabel).toBe('V-1');
    expect(r.chips.some((c) => c.art === 'post' && c.version.recordLabel === 'III-58')).toBe(true);
    const sidste = r.chips[r.chips.length - 1];
    expect(sidste.sourceId).toBe('1');
    expect(r.form).toBe('chips');
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

  it('overgangsdata og version uden sourceId slås op på label', () => {
    const { sourceId: _s, ...uden } = v(3, 'x', 'tekst');
    const r = byggUdgaveVaelger([{ ...uden, provenanceKind: 'legacy_narrative' }], udgaver, ['3']);
    expect(r.chips[0].label).toBe('DAA 2018-20 · overgangsdata');
    expect(r.chips[0].sourceId).toBe('3');
  });
});
