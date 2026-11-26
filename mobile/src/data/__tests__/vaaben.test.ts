import { vaabenSide, variantTitel } from '../vaaben';

const m = (id: number, slags: string) => ({ id, slags, titel: `m${id}` });

test('vaabenSide: hovedvåben = første i id-orden, varianter resten, hver med sine billeder', () => {
  const r = vaabenSide({
    vaaben: [{ id: '5', blasonering: 'Ørn', note: '' }, { id: '7', blasonering: 'Bjørn', note: 'linje V' }],
    mediaByObjekt: { 'coat_of_arms:5': [m(1, 'våben')], 'coat_of_arms:7': [m(2, 'segl')] },
    mediaById: { 1: m(1, 'våben'), 2: m(2, 'segl') },
  });
  expect(r.hoved?.id).toBe('5');
  expect(r.hoved?.media.map((x) => x.id)).toEqual([1]);
  expect(r.varianter.map((v) => [v.id, v.media.map((x) => x.id)])).toEqual([['7', [2]]]);
});

test('vaabenSide: galleriet er bogens våben i id-orden uden billeder, der allerede står som våben', () => {
  const r = vaabenSide({
    vaaben: [{ id: '5', blasonering: '', note: '' }],
    mediaByObjekt: { 'coat_of_arms:5': [m(3, 'våben')] },
    mediaById: { 9: m(9, 'våben'), 3: m(3, 'våben'), 4: m(4, 'portræt'), 6: m(6, 'våben') },
  });
  expect(r.galleri.map((x) => x.id)).toEqual([6, 9]);
});

test('vaabenSide: ingen våben registreret', () => {
  const r = vaabenSide({ vaaben: [], mediaByObjekt: {}, mediaById: {} });
  expect(r).toEqual({ hoved: null, varianter: [], galleri: [] });
});

test('variantTitel som web', () => {
  expect(variantTitel({ note: 'Linje V', blasonering: 'x' })).toBe('Linje V');
  expect(variantTitel({ note: '', blasonering: 'a'.repeat(50) })).toBe('a'.repeat(40));
  expect(variantTitel({ note: '', blasonering: '' })).toBe('variant');
});
