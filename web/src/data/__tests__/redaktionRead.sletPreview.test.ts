// Review 37 P11: slet-forhåndsvisningen bærer vejen (kan_fortrydes/aarsag) og er fail-closed.
import { beforeEach, expect, it, vi } from 'vitest';

let svar: { data: unknown; error: { message: string; code?: string } | null } = { data: null, error: null };
vi.mock('../../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
    rpc: vi.fn(async () => svar),
  },
}));
const { fetchSletPreview, fetchSlettedePersoner } = await import('../redaktionRead');
const { oversaetFejl } = await import('../redaktionWrite');
beforeEach(() => { svar = { data: null, error: null }; });

it('læser kan_fortrydes, aarsag og sletning_blokeret', async () => {
  svar = { data: { antal_relationer: 1, antal_facts: 2, antal_narrativer: 0, antal_bindinger: 0, antal_medlemskaber: 0,
    sletning_blokeret: false, kan_fortrydes: false, aarsag: 'staged', relationer: [{ rolle: 'far', retning: 'ud', modpart_id: 7 }] },
    error: null };
  expect(await fetchSletPreview('5')).toEqual({ antalRelationer: 1, antalFacts: 2, antalNarrativer: 0, antalBindinger: 0,
    antalMedlemskaber: 0, relationer: [{ rolle: 'far', retning: 'ud', modpartId: 7 }], kanFortrydes: false, aarsag: 'staged',
    sletningBlokeret: false });
});

it('et svar fra en database uden P11 giver aldrig den fortrydelige vej', async () => {
  svar = { data: { antal_relationer: 0, antal_facts: 0, relationer: [] }, error: null };
  expect(await fetchSletPreview('5')).toMatchObject({ kanFortrydes: false, aarsag: 'ukendt' });
});

it('en fejl kastes i stedet for at ligne et tomt overblik', async () => {
  svar = { data: null, error: { message: 'Kun redaktion', code: 'P0001' } };
  await expect(fetchSletPreview('5')).rejects.toThrow('Kun redaktion');
});

it('oversaetFejl giver dansk tekst for SLET_KRAEVER_SLET_HELT', () => {
  const t = oversaetFejl('SLET_KRAEVER_SLET_HELT: levende — personen er ikke offentlig, så den skal slettes helt');
  expect(t).toMatch(/^Personen kan ikke længere slettes, så det kan fortrydes/);
  expect(t).toMatch(/nulevende/); expect(t).toMatch(/»Slet helt«/); expect(t).not.toMatch(/SLET_KRAEVER/);
});

it('fetchSlettedePersoner mapper rækkerne og kaster ved fejl', async () => {
  svar = { data: [{ change_set_id: 91, slettet_naar: '2026-11-22T10:15:00Z', actor_navn: null, person_id: 1791, navn: 'Christian' }],
    error: null };
  expect(await fetchSlettedePersoner()).toEqual([{ changeSetId: '91', slettetNaar: '2026-11-22T10:15:00Z', actorNavn: null,
    personId: '1791', navn: 'Christian' }]);
  svar = { data: null, error: { message: 'Kun redaktion' } };
  await expect(fetchSlettedePersoner()).rejects.toThrow('Kun redaktion');
});
