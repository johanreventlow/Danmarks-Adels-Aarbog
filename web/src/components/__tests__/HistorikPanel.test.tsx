// @vitest-environment jsdom
// Issue #144: ændringshistorik + fortryd-knap i web-redaktøren (person-siden).
// Panelet henter selv sin historik (fetchHistorik) men skriver ALDRIG selv — fortryd
// delegeres til onFortryd-prop'en, som Redaktion.tsx implementerer gennem det delte
// submitChange-flow (dry-run/rolle/writeView). Konflikt-flowet (B9: "nyere ændring rører
// samme data") vises som et eksplicit valg med force — aldrig tavs overskrivning.
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { HistorikPanel } from '../HistorikPanel';
import { fetchHistorik, type HistPost } from '../../data/historik';

// Fuldt mock (ikke importOriginal): den rigtige data/historik trækker supabase.ts ind,
// som kræver VITE_-env og derfor ville vælte test-collection.
vi.mock('../../data/historik', () => ({ fetchHistorik: vi.fn() }));

const post = (over: Partial<HistPost> = {}): HistPost => ({
  id: '42', hvem: 'Johan', hvornaar: '6.8.2026, 10.00.00',
  resume: 'Rettede fødselsdato', reverteret: false, erFortryd: false, ...over,
});

beforeEach(() => {
  vi.clearAllMocks();
  (fetchHistorik as ReturnType<typeof vi.fn>).mockResolvedValue([post()]);
});

test('viser historik-poster med resume, aktør og tidspunkt', async () => {
  render(<HistorikPanel personId="7" onFortryd={vi.fn()} />);
  expect(await screen.findByText('Rettede fødselsdato')).toBeTruthy();
  expect(screen.getByText(/Johan/)).toBeTruthy();
  expect(fetchHistorik).toHaveBeenCalledWith('7');
});

test('tom historik viser ærlig tom-tilstand', async () => {
  (fetchHistorik as ReturnType<typeof vi.fn>).mockResolvedValue([]);
  render(<HistorikPanel personId="7" onFortryd={vi.fn()} />);
  expect(await screen.findByText('Ingen ændringer registreret.')).toBeTruthy();
});

test('fejl ved hentning vises i panelet', async () => {
  (fetchHistorik as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('Kun redaktion'));
  render(<HistorikPanel personId="7" onFortryd={vi.fn()} />);
  expect(await screen.findByText(/Kun redaktion/)).toBeTruthy();
});

test('Fortryd-klik delegerer til onFortryd uden force og genindlæser ved ok', async () => {
  const onFortryd = vi.fn().mockResolvedValue('ok');
  render(<HistorikPanel personId="7" onFortryd={onFortryd} />);
  fireEvent.click(await screen.findByText('Fortryd'));
  await waitFor(() => expect(onFortryd).toHaveBeenCalledWith('42', false));
  expect(fetchHistorik).toHaveBeenCalledTimes(2); // init + refetch efter ok
});

test('reverteret post viser "Fortrudt" og har ingen Fortryd-knap', async () => {
  (fetchHistorik as ReturnType<typeof vi.fn>).mockResolvedValue([post({ reverteret: true })]);
  render(<HistorikPanel personId="7" onFortryd={vi.fn()} />);
  expect(await screen.findByText('Fortrudt')).toBeTruthy();
  expect(screen.queryByText('Fortryd')).toBeNull();
});

test('fortryd-sæt (erFortryd) har ingen Fortryd-knap — der er ingen events at spille baglæns', async () => {
  (fetchHistorik as ReturnType<typeof vi.fn>).mockResolvedValue([
    post({ id: '43', erFortryd: true, resume: 'Fortrød: Rettede fødselsdato' }),
  ]);
  render(<HistorikPanel personId="7" onFortryd={vi.fn()} />);
  expect(await screen.findByText('Fortrød: Rettede fødselsdato')).toBeTruthy();
  expect(screen.queryByText('Fortryd')).toBeNull();
});

test('konflikt (B9) viser eksplicit force-valg; "Fortryd alligevel" kalder igen med force', async () => {
  const onFortryd = vi.fn().mockResolvedValueOnce('konflikt').mockResolvedValueOnce('ok');
  render(<HistorikPanel personId="7" onFortryd={onFortryd} />);
  fireEvent.click(await screen.findByText('Fortryd'));
  expect(await screen.findByText(/Nyere ændring rører samme data/)).toBeTruthy();
  fireEvent.click(screen.getByText('Fortryd alligevel'));
  await waitFor(() => expect(onFortryd).toHaveBeenLastCalledWith('42', true));
});

test('konflikt-valget kan annulleres uden nyt kald', async () => {
  const onFortryd = vi.fn().mockResolvedValue('konflikt');
  render(<HistorikPanel personId="7" onFortryd={onFortryd} />);
  fireEvent.click(await screen.findByText('Fortryd'));
  fireEvent.click(await screen.findByText('Annullér'));
  expect(screen.queryByText(/Nyere ændring rører samme data/)).toBeNull();
  expect(onFortryd).toHaveBeenCalledTimes(1);
});
