import { describe, it, expect } from 'vitest';
import { curatedFounders, forsideStartpersoner, pickMaanedensGods } from '../data/home';
import type { Model, ModelPerson } from '../data/types';
import type { EstateItem } from '../data/public';

function person(id: string, name: string): ModelPerson {
  return { id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, parentId: null, spouse: null } as ModelPerson;
}

function buildModel(persons: ModelPerson[], childIdx: Record<string, Set<string>>, heads: (string | null)[]): Model {
  const byId: Record<string, ModelPerson> = {};
  for (const p of persons) byId[p.id] = p;
  return {
    persons,
    byId,
    indexes: { childIdx } as Model['indexes'],
    lineage: { byPerson: {}, list: heads.map((headId, i) => ({ linje: String(i + 1), count: 0, headId, navn: null })), navn: {} },
  } as Model;
}

describe('curatedFounders', () => {
  it('returnerer linje-stamfædre i rækkefølge, deduplikeret, springer manglende byId over', () => {
    const ps = [person('a', 'A'), person('b', 'B'), person('c', 'C')];
    // heads inkluderer en dublet ('a') og et ukendt id ('zzz') der skal ignoreres
    const m = buildModel(ps, {}, ['a', 'b', 'a', 'zzz', 'c']);
    expect(curatedFounders(m, 5).map((p) => p.id)).toEqual(['a', 'b', 'c']);
  });

  it('udfylder op til n med mest centrale personer (flest børn) når der er for få stamfædre', () => {
    const ps = [person('a', 'A'), person('b', 'B'), person('c', 'C'), person('d', 'D')];
    const childIdx = { b: new Set(['x', 'y', 'z']), c: new Set(['x']), d: new Set(['x', 'y']) };
    const m = buildModel(ps, childIdx, ['a']); // kun 1 stamfader
    // a (stamfader) + fyld efter centralitet: b(3) > d(2) > c(1)
    expect(curatedFounders(m, 3).map((p) => p.id)).toEqual(['a', 'b', 'd']);
  });

  it('respekterer n-loftet og medtager ikke centralitets-personer med 0 børn', () => {
    const ps = [person('a', 'A'), person('b', 'B')];
    const m = buildModel(ps, {}, ['a']); // ingen børn-indeks → ingen fill-kandidater
    expect(curatedFounders(m, 5).map((p) => p.id)).toEqual(['a']);
  });

  it('tie-break på id ved lige centralitet', () => {
    const ps = [person('b', 'B'), person('a', 'A')];
    const childIdx = { a: new Set(['x']), b: new Set(['y']) };
    const m = buildModel(ps, childIdx, []); // ingen stamfædre → ren centralitets-fill
    expect(curatedFounders(m, 2).map((p) => p.id)).toEqual(['a', 'b']);
  });
});

describe('forsideStartpersoner', () => {
  const ps = [person('a', 'A'), person('b', 'B'), person('c', 'C'), person('d', 'D')];
  const model = buildModel(ps, { c: new Set(['x']), d: new Set(['x', 'y']) }, ['a', 'b']);

  it('sætter gyldige portrait-pins først og bevarer pin-rækkefølgen', () => {
    const pins = [
      { kortNoegle: 'portrait:d', handling: 'pin' as const },
      { kortNoegle: 'portrait:c', handling: 'pin' as const },
    ];
    expect(forsideStartpersoner(model, pins, 3).map((p) => p.id)).toEqual(['d', 'c', 'a']);
  });

  it('ignorerer dinglende, story/arkiv og skjul', () => {
    const pins = [
      { kortNoegle: 'portrait:zzz', handling: 'pin' as const },
      { kortNoegle: 'story:7', handling: 'pin' as const },
      { kortNoegle: 'arkiv:8', handling: 'pin' as const },
      { kortNoegle: 'portrait:d', handling: 'skjul' as const },
    ];
    expect(forsideStartpersoner(model, pins, 2).map((p) => p.id)).toEqual(['a', 'b']);
  });

  it('fallback udfylder uden dubletter', () => {
    expect(forsideStartpersoner(model, [{ kortNoegle: 'portrait:a', handling: 'pin' }], 3)
      .map((p) => p.id)).toEqual(['a', 'b', 'd']);
  });

  it('tom pin-liste er identisk med curatedFounders', () => {
    expect(forsideStartpersoner(model, [], 4)).toEqual(curatedFounders(model, 4));
  });
});

describe('pickMaanedensGods', () => {
  const e = (id: string, ownerCount: number): EstateItem => ({ id, navn: id, slags: 'gods', ownerCount });
  it('vælger godset med flest ejere', () => {
    expect(pickMaanedensGods([e('x', 2), e('y', 5), e('z', 1)])?.id).toBe('y');
  });
  it('tie-break på id', () => {
    expect(pickMaanedensGods([e('m', 3), e('a', 3)])?.id).toBe('a');
  });
  it('null ved tom/manglende liste', () => {
    expect(pickMaanedensGods([])).toBeNull();
    expect(pickMaanedensGods(null)).toBeNull();
  });
});
