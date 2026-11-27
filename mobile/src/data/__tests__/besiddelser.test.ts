import { buildModel, byggEjerraekke, type AppPerson } from '@daa/core';
import { buildAux } from '../buildAux';
import { besiddelserVist, ejerRelationer, ejerTekst, hentBesiddelseInfo } from '../besiddelser';

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

// --- Gods-detaljen: ejerrækken gennem buildAux og hentningen af historie/sted ---

describe('ejerrækken fra opstartens relationer', () => {
  const aux = buildAux({
    sources: [], estates: [{ id: 1, navn: 'Gods', slags: null }] as never, orgs: [], media: [], arms: [],
    relations: [
      { subjekt_type: 'person', subjekt_id: 'a1', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '(1640-1660)' },
      { subjekt_type: 'person', subjekt_id: 'k', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '(1600-1620)' },
      { subjekt_type: 'person', subjekt_id: 'skjult', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '(1500-†)' },
      { subjekt_type: 'person', subjekt_id: 'x', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null },
    ] as never,
  }, { a1: 'k' });
  const r = byggEjerraekke(ejerRelationer(aux.ownersByEstate['1']), model);

  test('samme (foldede) person med to perioder står to gange, kronologisk; skjulte ejere udelades', () => {
    expect(r.raekker.map((x) => [x.personId, x.periode])).toEqual([['k', '1600-1620'], ['k', '1640-1660']]);
    expect(r.udenAar.map((x) => x.navn)).toEqual(['Anden']);
    expect(JSON.stringify(r)).not.toContain('skjult');
  });
});

type Svar = { data: unknown; error: { message: string } | null };
function falskKlient(narr: Svar, place: Svar) {
  const kald: string[] = [];
  const kaede = (tabel: string, svar: Svar) => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'order']) q[m] = (...a: unknown[]) => { kald.push(`${tabel}.${m}(${a.map((x) => JSON.stringify(x)).join(',')})`); return q; };
    q.limit = () => Promise.resolve(svar);
    q.maybeSingle = () => Promise.resolve(svar);
    return q;
  };
  return { sb: { from: (t: string) => kaede(t, t === 'narrative' ? narr : place) } as never, kald };
}

describe('hentBesiddelseInfo', () => {
  test('henter første offentlige narrativ og stedets navn med web\'s forespørgsler', async () => {
    const { sb, kald } = falskKlient({ data: [{ tekst: 'Historien' }], error: null }, { data: { navn: 'Lolland' }, error: null });
    await expect(hentBesiddelseInfo(sb, '12', '7')).resolves.toEqual({ narrativ: 'Historien', sted: 'Lolland' });
    expect(kald).toEqual(expect.arrayContaining([
      'narrative.select("tekst")', 'narrative.eq("subjekt_type","estate")', 'narrative.eq("subjekt_id",12)',
      'narrative.eq("privat",false)', 'narrative.order("id",{"ascending":true})', 'place.select("navn")', 'place.eq("id",7)',
    ]));
  });
  test('en fejl kastes — den må ikke ligne »ingen historie«', async () => {
    const { sb } = falskKlient({ data: null, error: { message: 'timeout' } }, { data: null, error: null });
    await expect(hentBesiddelseInfo(sb, '12', null)).rejects.toThrow('timeout');
    const { sb: sb2 } = falskKlient({ data: [], error: null }, { data: null, error: { message: 'nej' } });
    await expect(hentBesiddelseInfo(sb2, '12', '7')).rejects.toThrow('nej');
  });
  test('uden sted læses place ikke; uden klient intet at vise', async () => {
    const { sb, kald } = falskKlient({ data: [], error: null }, { data: null, error: null });
    await expect(hentBesiddelseInfo(sb, '12', null)).resolves.toEqual({ narrativ: '', sted: '' });
    expect(kald.some((k) => k.startsWith('place.'))).toBe(false);
    await expect(hentBesiddelseInfo(null, '12', null)).resolves.toEqual({ narrativ: '', sted: '' });
  });
});
