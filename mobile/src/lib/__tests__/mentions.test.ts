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
