// PORTERET fra mobile/src/lib/__tests__/mentions.test.ts — hold i sync.
import { parseNarrativ } from '../mentions';

describe('parseNarrativ', () => {
  it('splitter gyldigt token til link-segment', () => {
    const segs = parseNarrativ('Se [[person:482|Chr. D. R.]] her.');
    expect(segs).toEqual([
      { kind: 'text', text: 'Se ' },
      { kind: 'link', maalType: 'person', maalId: 482, label: 'Chr. D. R.' },
      { kind: 'text', text: ' her.' },
    ]);
  });
  it('malformet/ukendt type bliver rå tekst', () => {
    const segs = parseNarrativ('[[person:abc|x]] [[ufo:1|y]]');
    expect(segs.every((s) => s.kind === 'text')).toBe(true);
  });
  it('afkoder escaped pipe i label', () => {
    const segs = parseNarrativ('[[person:9|a\\|b]]');
    expect(segs).toEqual([{ kind: 'link', maalType: 'person', maalId: 9, label: 'a|b' }]);
  });
  it('uafsluttet token bliver rå tekst (ingen ]])', () => {
    const segs = parseNarrativ('[[person:1|ulukket');
    expect(segs.every((s) => s.kind === 'text')).toBe(true);
    expect(segs.map((s) => (s.kind === 'text' ? s.text : '')).join('')).toBe('[[person:1|ulukket');
  });
  it('token-fri tekst bliver ét text-segment', () => {
    expect(parseNarrativ('bare prosa')).toEqual([{ kind: 'text', text: 'bare prosa' }]);
  });
  it('tom/undefined → tomt array', () => {
    expect(parseNarrativ('')).toEqual([]);
    expect(parseNarrativ(undefined as unknown as string)).toEqual([]);
  });
});

import { makeToken, insertAt } from '../mentions';

describe('makeToken/insertAt', () => {
  it('makeToken escaper specialtegn i label', () => {
    expect(makeToken('person', 5, 'a|b]c')).toBe('[[person:5|a\\|b\\]c]]');
  });
  it('makeToken roundtrip via parseNarrativ bevarer label', () => {
    const tok = makeToken('person', 5, 'a|b]c[');
    const segs = parseNarrativ(tok);
    expect(segs).toEqual([{ kind: 'link', maalType: 'person', maalId: 5, label: 'a|b]c[' }]);
  });
  it('insertAt indsætter ved position og flytter cursor', () => {
    expect(insertAt('Hej  verden', 4, 'X')).toEqual({ text: 'Hej X verden', cursor: 5 });
  });
  it('insertAt klamper position til [0,len]', () => {
    expect(insertAt('ab', 99, 'X')).toEqual({ text: 'abX', cursor: 3 });
    expect(insertAt('ab', -5, 'X')).toEqual({ text: 'Xab', cursor: 1 });
  });
});

describe('makeToken/parseNarrativ — backslash-roundtrip (review10 H1)', () => {
  const cases = ['X\\', 'a\\|b', 'a\\b', 'a|b]c[', '\\\\dobbelt', 'normal', 'sti\\til\\fil'];
  for (const label of cases) {
    it(`roundtrip bevarer "${label}"`, () => {
      const tok = makeToken('person', 1, label);
      const segs = parseNarrativ(tok);
      expect(segs).toEqual([{ kind: 'link', maalType: 'person', maalId: 1, label }]);
    });
  }
});
