// Biografierne hentes i bidder efter cold-start (prod 25/11: alle 1.725 id'er i ét kald ramte gæsternes 3 s-loft,
// 57014, og hele appen faldt tilbage til offline-seed). Spejl af web/src/data/__tests__ for feedAux.
import { BIO_IN_CHUNK, BIO_PARALLEL, hentBios } from '../load';
import { withBios } from '../../store/useStore';
import type { Model } from '../types';

const raekke = (personId: number, tekst: string, order = 1) => ({
  person_id: personId, source_id: 9, source_year: 1939, record_order: order, source_record_ref: `r${personId}-${order}`,
  source_label: 'DAA', record_label: `Post ${order}`, narrative_text: tekst, citation_label: '', provenance_kind: 'source_record',
});

type Kald = { fn: string; ids: number[] };

// Falsk klient: kontrakt v2; bio-RPC'en svarer med én række pr. id, undtagen når `fejler(ids)` siger nej.
function falskKlient(fejler: (ids: number[]) => boolean = () => false) {
  const kald: Kald[] = [];
  let samtidige = 0;
  let maksSamtidige = 0;
  const rpc = jest.fn(async (fn: string, args: { p_person_ids?: number[] }) => {
    if (fn === 'narrative_record_contract_version') return { data: 2, error: null };
    const ids = args.p_person_ids ?? [];
    kald.push({ fn, ids });
    samtidige++;
    maksSamtidige = Math.max(maksSamtidige, samtidige);
    await new Promise((r) => setTimeout(r, 1));
    samtidige--;
    if (fejler(ids)) return { data: null, error: { code: '57014' } };
    return { data: ids.map((id) => raekke(id, `Bio ${id}`)), error: null };
  });
  return { sb: { rpc } as never, kald, maks: () => maksSamtidige };
}

const ids = (n: number) => Array.from({ length: n }, (_, i) => i + 1);

test('hentBios: bidder à BIO_IN_CHUNK med højst BIO_PARALLEL samtidige kald, komplet ved succes', async () => {
  const { sb, kald, maks } = falskKlient();
  const res = await hentBios(sb, ids(173), {});
  const bioKald = kald.filter((k) => k.fn === 'public_person_bio_source_versions_v2');
  expect(bioKald.map((k) => k.ids.length)).toEqual([50, 50, 50, 23]);
  expect(Math.max(...bioKald.map((k) => k.ids.length))).toBeLessThanOrEqual(BIO_IN_CHUNK);
  expect(maks()).toBeLessThanOrEqual(BIO_PARALLEL);
  expect(Object.keys(res.bioBy)).toHaveLength(173);
  expect(res.komplet).toBe(true);
});

test('hentBios: en bid der fejler prøves igen som to halvdele', async () => {
  // Hele bidden 1-50 fejler; halvdelene (25 id'er) lykkes.
  const { sb, kald } = falskKlient((del) => del.length === 50 && del[0] === 1);
  const res = await hentBios(sb, ids(60), {});
  expect(kald.map((k) => k.ids.length)).toEqual(expect.arrayContaining([50, 10, 25, 25]));
  expect(Object.keys(res.bioBy)).toHaveLength(60);
  expect(res.komplet).toBe(true);
});

test('hentBios: en halvdel der bliver ved med at fejle koster kun sine egne id\'er (komplet=false)', async () => {
  const { sb } = falskKlient((del) => del.includes(1));
  const res = await hentBios(sb, ids(60), {});
  expect(res.komplet).toBe(false);
  expect(res.bioBy['1']).toBeUndefined();
  expect(res.bioBy['26']).toBe('Bio 26');
  expect(Object.keys(res.bioBy)).toHaveLength(35);
});

test('hentBios: kaster når alle bidder fejler', async () => {
  const { sb } = falskKlient(() => true);
  await expect(hentBios(sb, ids(10), {})).rejects.toThrow('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
});

test('hentBios: kaster når kontrakten ikke kan læses', async () => {
  const rpc = jest.fn(async () => ({ data: null, error: { message: 'nej' } }));
  await expect(hentBios({ rpc } as never, [1], {})).rejects.toThrow('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
  expect(rpc).toHaveBeenCalledTimes(1);
});

test('hentBios: alias i en anden bid end den kanoniske nøgles på kanonisk id', async () => {
  const { sb } = falskKlient();
  // id 1 og 51 havner i hver sin bid; 51 er alias for 1.
  const res = await hentBios(sb, ids(60), { '51': '1' });
  expect(res.bioBy['1']).toBeDefined();
  expect(res.bioBy['51']).toBeUndefined();
});

test('hentBios: ingen id\'er = intet kald, komplet', async () => {
  const rpc = jest.fn();
  await expect(hentBios({ rpc } as never, [], {})).resolves.toEqual({ bioBy: {}, komplet: true });
  expect(rpc).not.toHaveBeenCalled();
});

test('withBios: ny model med nye person-objekter; den gamle røres ikke', () => {
  const a = { id: '1', name: 'A', bio: '' };
  const b = { id: '2', name: 'B', bio: '' };
  const model = { persons: [a, b], byId: { '1': a, '2': b }, indexes: {} } as unknown as Model;
  const ny = withBios(model, { '1': 'Tekst' });
  expect(ny).not.toBe(model);
  expect(ny.byId['1'].bio).toBe('Tekst');
  expect(ny.persons[0]).toBe(ny.byId['1']);
  expect(ny.byId['2']).toBe(b);
  expect(a.bio).toBe('');
  expect(ny.indexes).toBe(model.indexes);
});
