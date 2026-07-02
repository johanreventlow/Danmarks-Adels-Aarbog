import { groupSameAs } from '../collapseSameAs';

const known = (...ids: string[]) => new Set(ids);

describe('groupSameAs', () => {
  it('par: objekt = kanonisk', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('A', 'B'));
    expect(quarantined).toEqual([]);
    expect([...groups.entries()]).toEqual([['B', expect.arrayContaining(['A', 'B'])]]);
  });
  it('kæde A→B, B→C → C kanonisk', () => {
    const { groups } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'B', canonical: 'C' },
      ],
      known('A', 'B', 'C'),
    );
    expect([...groups.keys()]).toEqual(['C']);
    expect(groups.get('C')!.sort()).toEqual(['A', 'B', 'C']);
  });
  it('tvetydig sink A→B, A→C → karantæne', () => {
    const { groups, quarantined } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'A', canonical: 'C' },
      ],
      known('A', 'B', 'C'),
    );
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink/i);
  });
  it('retnings-cyklus A→B, B→A → karantæne', () => {
    const { groups, quarantined } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'B', canonical: 'A' },
      ],
      known('A', 'B'),
    );
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink|cyklus/i);
  });
  it('ufuldstændig komponent (endpoint mangler) → karantæne', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('B'));
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/ufuldstændig|mangler/i);
  });
  it('duplikerede kanter normaliseres', () => {
    const { groups } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'A', canonical: 'B' },
      ],
      known('A', 'B'),
    );
    expect(groups.get('B')!.sort()).toEqual(['A', 'B']);
  });
});
