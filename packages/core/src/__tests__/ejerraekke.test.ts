import { describe, expect, it } from 'vitest';
import { buildModel, type AppPerson } from '../index';
import type { Model } from '../types';
import { antalEjere, byggEjerraekke, periodeTekst } from '../ejerraekke';

const P = (id: string, name: string, born: number | null = null): AppPerson =>
  ({ id, name, born, died: null, years: born ? `* ${born}` : '', title: '', bio: '', privat: false, koen: null });

describe('periodeTekst', () => {
  it('kun de ydre parenteser fjernes; resten som bogen skriver det', () => {
    expect(periodeTekst('(1744-†, lagt under Frisenvold)')).toBe('1744-†, lagt under Frisenvold');
    expect(periodeTekst('(1918 (9. maj)-†)')).toBe('1918 (9. maj)-†');
    expect(periodeTekst('1606‑†')).toBe('1606‑†');
    expect(periodeTekst('solgte 1782 (12. april)')).toBe('solgte 1782 (12. april)');
    expect(periodeTekst('')).toBe('');
  });
});

describe('byggEjerraekke', () => {
  // Fixturens egne periodeformer.
  const model = buildModel({
    persons: [P('a', 'Abel', 1600), P('b', 'Bartram', 1590), P('c', 'Cai'), P('d', 'Detlef', 1700), P('e', 'Eggert', 1650), P('f', 'Frands')],
    unions: [], parentChild: [],
  }) as unknown as Model;
  const rel = [
    { personId: 'a', periode: '(efter 1618-1642-)' },
    { personId: 'b', periode: '(-1378)' },
    { personId: 'c', periode: '(1744-†, lagt under Frisenvold)' },
    { personId: 'd', periode: '' },
    { personId: 'e', periode: '(Klein Kollmar S., Steinburg Kr.)' }, // ingen årstal
    { personId: 'f', periode: '(-1576-)' },
    { personId: 'a', periode: '(alle 1622-1629)' },
    { personId: 'b', periode: '(-1378)' }, // samme person, samme periode → én række
    { personId: 'skjult', periode: '(1700-†)' }, // ikke i modellen → udelades
  ];
  const r = byggEjerraekke(rel, model);

  it('kronologisk efter første årstal; samme person med to perioder står to gange', () => {
    expect(r.raekker.map((x) => [x.navn, x.periode])).toEqual([
      ['Bartram', '-1378'], ['Frands', '-1576-'], ['Abel', 'efter 1618-1642-'], ['Abel', 'alle 1622-1629'], ['Cai', '1744-†, lagt under Frisenvold'],
    ]);
  });
  it('uden årstal til sidst efter fødeår; skjulte ejere nævnes ikke', () => {
    expect(r.udenAar.map((x) => [x.navn, x.periode])).toEqual([['Eggert', 'Klein Kollmar S., Steinburg Kr.'], ['Detlef', '']]);
    expect(JSON.stringify(r)).not.toContain('skjult');
  });
});

describe('samme person i flere udgaver (samme_som)', () => {
  const m = buildModel({ persons: [P('k', 'Christian Reventlow', 1750), P('x', 'Anden')], unions: [], parentChild: [] }) as unknown as Model;
  m.canonicalIdById = { a1: 'k', a2: 'k' } as never;
  it('samme periode med forskellig bindestreg og parentes er én række; visningen som bogen skriver den', () => {
    const r = byggEjerraekke([
      { personId: 'k', periode: '(1783-†)' }, { personId: 'k', periode: '(1783‑†)' }, { personId: 'k', periode: '1783‑†' }, { personId: 'k', periode: '1783 -†' },
    ], m);
    expect(r.raekker.map((x) => x.periode)).toEqual(['1783-†', '1783 -†']);
  });
  it('antal ejere tæller kanoniske personer i modellen', () => {
    expect(antalEjere(['a1', 'a2', 'k', 'x', 'skjult'], m)).toBe(2);
  });
});
