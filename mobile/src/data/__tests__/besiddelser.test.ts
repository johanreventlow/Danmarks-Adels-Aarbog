import { buildModel, type AppPerson } from '@daa/core';
import { besiddelserVist, ejerTekst } from '../besiddelser';

const P = (id: string, name: string): AppPerson =>
  ({ id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, koen: null });

const model = buildModel({ persons: [P('k', 'Christian'), P('x', 'Anden')], unions: [], parentChild: [] });
model.canonicalIdById = { a1: 'k', a2: 'k' };

test('besiddelserVist: foldet person tælles én gang, skjulte ejere tælles ikke', () => {
  const [g] = besiddelserVist([{ id: '1', navn: 'Gods', slags: '', ownerCount: 4, ejerIds: ['a1', 'a2', 'k', 'skjult'] }], model);
  expect(g.ownerCount).toBe(1);
});

test('besiddelserVist: ejerløse er med; flest ejere først, derefter navn', () => {
  const r = besiddelserVist([
    { id: '1', navn: 'Ørslev', slags: '', ownerCount: 0, ejerIds: [] },
    { id: '2', navn: 'Brahe', slags: '', ownerCount: 2, ejerIds: ['k', 'x'] },
    { id: '3', navn: 'Aalholm', slags: '', ownerCount: 0, ejerIds: [] },
  ], model);
  expect(r.map((e) => [e.navn, e.ownerCount])).toEqual([['Brahe', 2], ['Aalholm', 0], ['Ørslev', 0]]);
});

test('ejerTekst som web', () => {
  expect(ejerTekst(0)).toBe('Ingen ejere registreret');
  expect(ejerTekst(1)).toBe('1 ejer i Aarbogen');
  expect(ejerTekst(3)).toBe('3 ejere i Aarbogen');
});
