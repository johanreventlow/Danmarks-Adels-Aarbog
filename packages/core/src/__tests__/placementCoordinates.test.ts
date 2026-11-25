import { describe, it, expect } from 'vitest';
import { coordinateRowToExtId, compareLineHead, erUkendtFunktion, fetchPublicCoordinates, type PublicCoordinateRow } from '../placementCoordinates';

const row = (o: Partial<PublicCoordinateRow> = {}): PublicCoordinateRow => ({
  person_id: 7,
  source_id: 1,
  legacy_line_code: 'I',
  printed_number: 15,
  printed_number_label: '15a',
  generation_local: 3,
  generation_global: 7,
  kuld_label: null,
  provenance_kind: 'placement',
  ...o,
});

describe('coordinateRowToExtId', () => {
  it('mapper RPC-rækken til RawExtId med label og proveniens', () => {
    expect(coordinateRowToExtId(row({ kuld_label: 'II' }))).toEqual({
      person_id: 7,
      source_id: 1,
      linje: 'I',
      nr: 15,
      nr_label: '15a',
      slaegtled_lokal: 3,
      slaegtled_gennem: 7,
      kuld: 'II',
      provenance: 'placement',
      trykt_side: null,
    });
  });

  it('bærer printed_page videre som trykt_side', () => {
    expect(coordinateRowToExtId(row({ printed_page: '49' })).trykt_side).toBe('49');
  });

  it('bevarer null-koordinater (karantæne nedstrøms)', () => {
    const x = coordinateRowToExtId(row({
      legacy_line_code: null, printed_number: null, printed_number_label: null,
      generation_local: null, generation_global: null, kuld_label: null, provenance_kind: 'legacy_external_id',
    }));
    expect(x).toMatchObject({ linje: null, nr: null, nr_label: null, slaegtled_lokal: null, slaegtled_gennem: null, kuld: null, provenance: 'legacy_external_id' });
  });
});

describe('compareLineHead', () => {
  it('sorterer på heltal, derefter label; unummereret før nummereret', () => {
    const xs = [{ nr: 16, nr_label: '16' }, { nr: null, nr_label: null }, { nr: 15, nr_label: '15b' }, { nr: 15, nr_label: '15a' }];
    expect([...xs].sort(compareLineHead).map((x) => x.nr_label)).toEqual([null, '15a', '15b', '16']);
  });

  it('laveste slægtled vinder, uafhængigt af nr.; NULL slægtled sidst', () => {
    expect(compareLineHead({ nr: 1, slaegtled: 2 }, { nr: null, slaegtled: 1 })).toBeGreaterThan(0);
    expect(compareLineHead({ nr: null, slaegtled: 1 }, { nr: 1, slaegtled: 2 })).toBeLessThan(0);
    expect(compareLineHead({ nr: 5, slaegtled: null }, { nr: 9, slaegtled: 3 })).toBeGreaterThan(0);
  });

  it('samme slægtled: unummereret før nummereret', () => {
    expect(compareLineHead({ nr: null, slaegtled: 1 }, { nr: 1, slaegtled: 1 })).toBeLessThan(0);
  });

  it('kilde 1 uden slægtled: kun nr. afgør (I→1, II→137, III→172, IV→298, V→392)', () => {
    const hoveder = [392, 1, 298, 137, 172].map((nr) => ({ nr, nr_label: String(nr) }));
    expect(hoveder.sort(compareLineHead).map((x) => x.nr)).toEqual([1, 137, 172, 298, 392]);
  });

  it('uden label sorteres et rent heltal før et suffiks med samme tal', () => {
    expect(compareLineHead({ nr: 15 }, { nr: 15, nr_label: '15a' })).toBeLessThan(0);
  });
});

describe('fetchPublicCoordinates (kodereview 36 P2)', () => {
  const raekker = (pages: PublicCoordinateRow[][]) => {
    const kald: [number, number][] = [];
    let i = 0;
    return { kald, fn: () => ({ range: async (a: number, b: number) => { kald.push([a, b]); return { data: pages[i++] ?? [], error: null }; } }) };
  };

  it('henter alt i ét kald fra den samlede funktion og rører ikke rækkefunktionen', async () => {
    const r = raekker([]);
    let n = 0;
    const rows = await fetchPublicCoordinates(async () => { n++; return { data: [row(), row({ person_id: 8 })], error: null }; }, r.fn);
    expect(n).toBe(1);
    expect(rows.map((x) => x.person_id)).toEqual([7, 8]);
    expect(r.kald).toEqual([]);
  });

  it('falder tilbage til rækkefunktionen via getAll, når den samlede funktion ikke findes (PGRST202)', async () => {
    const fuld = Array.from({ length: 1000 }, (_, i) => row({ person_id: i }));
    const r = raekker([fuld, [row({ person_id: 1000 })]]);
    const rows = await fetchPublicCoordinates(async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }), r.fn);
    expect(rows).toHaveLength(1001);
    expect(r.kald).toEqual([[0, 999], [1000, 1999]]);
  });

  it('prøver andre fejl igen én gang og kaster dem så videre uden fallback', async () => {
    const r = raekker([[row()]]);
    let n = 0;
    await expect(fetchPublicCoordinates(async () => { n++; return { data: null, error: { code: '57014', message: 'timeout' } }; }, r.fn, 0)).rejects.toMatchObject({ code: '57014' });
    expect(n).toBe(2);
    expect(r.kald).toEqual([]);
  });

  it('et 57014 på første kald redder sig på genforsøget (prod 25/11, kold start)', async () => {
    const r = raekker([]);
    let n = 0;
    const rows = await fetchPublicCoordinates(async () => (n++ === 0
      ? { data: null, error: { code: '57014', message: 'timeout' } }
      : { data: [row()], error: null }), r.fn, 0);
    expect(n).toBe(2);
    expect(rows.map((x) => x.person_id)).toEqual([7]);
    expect(r.kald).toEqual([]);
  });

  it('en ukendt funktion prøves ikke igen, men falder tilbage med det samme', async () => {
    const r = raekker([[row()]]);
    let n = 0;
    await fetchPublicCoordinates(async () => { n++; return { data: null, error: { code: 'PGRST202', message: 'x' } }; }, r.fn, 0);
    expect(n).toBe(1);
  });

  it('kaster, hvis svaret ikke er et array', async () => {
    await expect(fetchPublicCoordinates(async () => ({ data: { x: 1 }, error: null }), raekker([]).fn)).rejects.toThrow(/JSON-array/);
  });

  it('genkender ukendt funktion på PostgREST- og Postgres-koden', () => {
    expect(erUkendtFunktion({ code: 'PGRST202' })).toBe(true);
    expect(erUkendtFunktion({ code: '42883' })).toBe(true);
    expect(erUkendtFunktion({ code: '42501' })).toBe(false);
    expect(erUkendtFunktion(null)).toBe(false);
  });
});
