// @vitest-environment jsdom
// Review 37 P11: redaktionens liste over slettede personer med »Fortryd sletning« pr. sletning.
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { SlettedePersoner } from '../SlettedePersoner';
import type { SlettetPerson } from '../../data/redaktionRead';
vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } } }));
afterEach(cleanup);

const raekker: SlettetPerson[] = [
  { changeSetId: '91', slettetNaar: '2026-11-22T10:15:00Z', actorNavn: 'redaktor@daa.dk', personId: '1791', navn: 'Christian Reventlow' },
  { changeSetId: '88', slettetNaar: '2026-11-21T09:00:00Z', actorNavn: null, personId: '1802', navn: null },
];
function setup(o: { role?: string; dryRun?: boolean;
  fortryd?: (r: SlettetPerson, opts?: { force?: boolean }) => Promise<{ dryRun: boolean }>;
  load?: (limit: number) => Promise<SlettetPerson[]> } = {}) {
  const props = { role: o.role ?? 'redaktion', dryRun: o.dryRun ?? false,
    load: vi.fn(o.load ?? (() => Promise.resolve(raekker))),
    fortryd: vi.fn(o.fortryd ?? (() => Promise.resolve({ dryRun: false }))) };
  render(<SlettedePersoner {...props} />);
  return props;
}
const knap = (navn: string) => screen.getByRole('button', { name: `Fortryd sletning af ${navn}` }) as HTMLButtonElement;

it('viser navn, id, hvornår og af hvem pr. sletning', async () => {
  setup();
  const raek = (await screen.findByText('Christian Reventlow')).closest('tr')!;
  expect(within(raek).getByText('1791')).toBeTruthy();
  expect(within(raek).getByText('redaktor@daa.dk')).toBeTruthy();
  expect(within(raek).getByText(/2026/)).toBeTruthy();
  expect(within(raek).getByRole('button').textContent).toBe('Fortryd sletning');
  const anden = screen.getByText('(uden navn)').closest('tr')!;
  expect(within(anden).getByText('ukendt')).toBeTruthy();
  expect(screen.getByText(/slettet helt \(GDPR\), står ikke her/)).toBeTruthy();
});

it('»Fortryd sletning« kalder fortrydelsen med sættet, og rækken forsvinder', async () => {
  const p = setup();
  await screen.findByText('Christian Reventlow');
  fireEvent.click(knap('Christian Reventlow'));
  await waitFor(() => expect(screen.queryByText('Christian Reventlow')).toBeNull());
  expect(p.fortryd).toHaveBeenCalledWith(raekker[0]);
  expect(screen.getByRole('status').textContent).toBe('Christian Reventlow (id 1791) er genskabt.');
  expect(screen.getByText('(uden navn)')).toBeTruthy();
});

it('en fejl oversættes og rækken bliver stående', async () => {
  const p = setup({ fortryd: () => Promise.reject(new Error('Kun redaktion')) });
  await screen.findByText('Christian Reventlow');
  fireEvent.click(knap('Christian Reventlow'));
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toBe('Kræver redaktør-rettigheder.');
  expect(screen.getByText('Christian Reventlow')).toBeTruthy();
  expect(p.fortryd).toHaveBeenCalledTimes(1);
});

it('dry-run fortryder intet og beholder rækken', async () => {
  setup({ dryRun: true, fortryd: () => Promise.resolve({ dryRun: true }) });
  await screen.findByText('Christian Reventlow');
  fireEvent.click(knap('Christian Reventlow'));
  await screen.findByText('Dry-run: intet er fortrudt.');
  expect(screen.getByText('Christian Reventlow')).toBeTruthy();
});

it('tom liste og fejlet hentning', async () => {
  setup({ load: () => Promise.resolve([]) });
  await screen.findByText('Ingen slettede personer, der kan fortrydes.');
  cleanup();
  const p = setup({ load: () => Promise.reject(new Error('Kun redaktion')) });
  expect((await screen.findByRole('alert')).textContent).toMatch(/Listen kunne ikke hentes: Kræver redaktør-rettigheder\./);
  p.load.mockResolvedValueOnce(raekker);
  fireEvent.click(screen.getByRole('button', { name: 'Hent igen' }));
  await screen.findByText('Christian Reventlow');
});

// Review 37 R37P11-1 (ceremoni 2): tvangsvalg ved konflikt, som i historikpanelet.
it('en konflikt tilbyder »Fortryd alligevel«, som fortryder med force', async () => {
  const fortryd = vi.fn((_r: SlettetPerson, opts?: { force?: boolean }) => opts?.force
    ? Promise.resolve({ dryRun: false })
    : Promise.reject(new Error('FEJL: change_set 91 divergerer fra nuværende tilstand — afvist (brug force)')));
  setup({ fortryd });
  await screen.findByText('Christian Reventlow');
  fireEvent.click(knap('Christian Reventlow'));
  const raek = (await screen.findByText(/Nyere ændring rører samme data/)).closest('tr')!;
  expect(fortryd).toHaveBeenCalledWith(raekker[0]);
  fireEvent.click(within(raek).getByRole('button', { name: 'Fortryd alligevel: Christian Reventlow' }));
  await waitFor(() => expect(screen.queryByText('Christian Reventlow')).toBeNull());
  expect(fortryd).toHaveBeenLastCalledWith(raekker[0], { force: true });
});

it('»Annullér« lukker konflikten uden at fortryde', async () => {
  const fortryd = vi.fn(() => Promise.reject(new Error('afvist (brug force)')));
  setup({ fortryd });
  await screen.findByText('Christian Reventlow');
  fireEvent.click(knap('Christian Reventlow'));
  await screen.findByText(/Nyere ændring rører samme data/);
  fireEvent.click(screen.getByRole('button', { name: 'Annullér' }));
  expect(screen.queryByText(/Nyere ændring rører samme data/)).toBeNull();
  expect(fortryd).toHaveBeenCalledTimes(1);
});

const mange = (n: number): SlettetPerson[] => Array.from({ length: n }, (_, i) =>
  ({ changeSetId: String(1000 + i), slettetNaar: '2026-11-22T10:15:00Z', actorNavn: null, personId: String(5000 + i), navn: `Person ${i}` }));

it('»Vis flere« henter 100 ad gangen, højst 500', async () => {
  const p = setup({ load: (limit) => Promise.resolve(mange(Math.min(limit, 500))) });
  await screen.findByText('Person 99');
  expect(p.load).toHaveBeenLastCalledWith(100);
  for (const limit of [200, 300, 400, 500]) {
    fireEvent.click(screen.getByRole('button', { name: 'Vis flere' }));
    await screen.findByText(`Person ${limit - 1}`);
    expect(p.load).toHaveBeenLastCalledWith(limit);
  }
  expect(screen.queryByRole('button', { name: 'Vis flere' })).toBeNull();
  expect(screen.getByText('Viser de 500 nyeste sletninger.')).toBeTruthy();
}, 20_000); // 4 × op til 500 rækker: over vitests standard på 5 s, når hele suiten kører samtidig.

it('»Vis flere« bliver stående, når en række fra en fuld side er genskabt', async () => {
  setup({ load: (limit) => Promise.resolve(mange(Math.min(limit, 500))) });
  await screen.findByText('Person 0');
  fireEvent.click(knap('Person 0'));
  await waitFor(() => expect(screen.queryByText('Person 0')).toBeNull());
  expect(screen.getByRole('button', { name: 'Vis flere' })).toBeTruthy();
});

it('en hentning, der lander efter en fortrydelse, viser ikke den genskabte person igen', async () => {
  let svar: (r: SlettetPerson[]) => void = () => {};
  const load = vi.fn((limit: number) => limit === 100
    ? Promise.resolve(mange(100))
    : new Promise<SlettetPerson[]>((res) => { svar = res; }));
  setup({ load });
  await screen.findByText('Person 0');
  fireEvent.click(screen.getByRole('button', { name: 'Vis flere' }));
  fireEvent.click(knap('Person 0'));
  await waitFor(() => expect(screen.queryByText('Person 0')).toBeNull());
  svar(mange(200)); // læst før fortrydelsens commit
  await screen.findByText('Person 199');
  expect(screen.queryByText('Person 0')).toBeNull();
});

it('færre end 100 rækker: ingen »Vis flere«', async () => {
  setup();
  await screen.findByText('Christian Reventlow');
  expect(screen.queryByRole('button', { name: 'Vis flere' })).toBeNull();
});

it('uden redaktørrolle hentes intet', () => {
  const p = setup({ role: 'medlem' });
  expect(screen.getByText('Kun redaktionen kan se slettede personer.')).toBeTruthy();
  expect(p.load).not.toHaveBeenCalled();
});
