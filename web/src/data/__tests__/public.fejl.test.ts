// Review 36 K4 (læserdelen): en databasefejl må ikke ligne tomme data, når kalderen har en fejl-tilstand med
// »Prøv igen«. Kun den dokumenterede pynt (fetchArms/fetchAbout/fetchEstateInfo) må give tom-tilstand.
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Tabeller, hvis opslag svarer med en PostgREST-fejl ({ data: null, error }), i denne test.
const fejlTabeller = new Set<string>();
const DB_FEJL = { message: 'canceling statement due to statement timeout', code: '57014' };

function table(name: string) {
  const svar = () => (fejlTabeller.has(name)
    ? { data: null, error: DB_FEJL }
    : { data: name === 'fact' ? [{ id: 1, subjekt_id: 1 }] : [], error: null });
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'is', 'in', 'order', 'limit']) q[m] = () => q;
  q.range = async () => svar();
  q.maybeSingle = async () => svar();
  q.then = (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) => Promise.resolve(svar()).then(ok, ko);
  return q;
}
vi.mock('../../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => {} },
    from: (n: string) => table(n),
    rpc: (n: string) => Promise.resolve(n === 'narrative_record_contract_version' ? { data: 2, error: null } : { data: [], error: null }),
  },
}));
vi.mock('../media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => new Map() }));
const { fetchPersonDetail, fetchEstates, fetchEstateOwners, fetchArms } = await import('../public');

beforeEach(() => {
  fejlTabeller.clear();
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
});

describe('fetchPersonDetail kaster ved databasefejl (kalderne viser fejl + »Prøv igen«)', () => {
  it('kontrol: uden fejl gives en (tom) detalje', async () => {
    await expect(fetchPersonDetail('1')).resolves.toMatchObject({ bio: '', offices: [], estates: [] });
  });

  it('en fejl i relationsopslaget (embeder/besiddelser) afviser — ikke en tom person', async () => {
    fejlTabeller.add('relation');
    await expect(fetchPersonDetail('1')).rejects.toMatchObject(DB_FEJL);
  });

  it('en fejl i proveniensens fact-opslag (person uden bog-nummer) afviser — ikke »ingen kilde«', async () => {
    fejlTabeller.add('fact');
    await expect(fetchPersonDetail('1', undefined, true)).rejects.toThrow('fetchProveniens/fact');
  });

  it('en fejl i proveniensens assertion-opslag afviser', async () => {
    fejlTabeller.add('assertion');
    await expect(fetchPersonDetail('1', undefined, true)).rejects.toThrow('fetchProveniens/assertion');
  });
});

// Regressionslås: fetchEstates/fetchEstateOwners kastede allerede efter fase 7b (gik ikke gennem safe()), så disse to
// består også mod koden før review 36 — de sikrer, at Folgesvends estatesFejl-/ejerfejl-gren forbliver nåelig.
describe('besiddelser kaster ved databasefejl (kalderen sætter estatesFejl / ejer-fejl)', () => {
  it('fetchEstates afviser, når relation-opslaget fejler', async () => {
    fejlTabeller.add('relation');
    await expect(fetchEstates()).rejects.toMatchObject(DB_FEJL);
  });
  it('fetchEstateOwners afviser, når relation-opslaget fejler', async () => {
    fejlTabeller.add('relation');
    await expect(fetchEstateOwners('1', null)).rejects.toMatchObject(DB_FEJL);
  });
});

describe('dokumenteret undtagelse: pynt uden fejl-UI forbliver tolerant', () => {
  it('fetchArms giver tom liste ved databasefejl', async () => {
    fejlTabeller.add('coat_of_arms');
    await expect(fetchArms()).resolves.toEqual([]);
  });
});
