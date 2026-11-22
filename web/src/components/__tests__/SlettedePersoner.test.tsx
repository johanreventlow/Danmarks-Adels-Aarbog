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
function setup(o: { role?: string; dryRun?: boolean; fortryd?: (r: SlettetPerson) => Promise<{ dryRun: boolean }>;
  load?: () => Promise<SlettetPerson[]> } = {}) {
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

it('uden redaktørrolle hentes intet', () => {
  const p = setup({ role: 'medlem' });
  expect(screen.getByText('Kun redaktionen kan se slettede personer.')).toBeTruthy();
  expect(p.load).not.toHaveBeenCalled();
});
