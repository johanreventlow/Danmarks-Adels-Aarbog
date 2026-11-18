// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { PersonPurgeUdbakke } from '../PersonPurgeUdbakke';
import { executePurgeOprydning, fetchPurgeUdbakke } from '../../data/personPurge';
vi.mock('../../data/personPurge', () => ({
  fetchPurgeUdbakke: vi.fn(), executePurgeOprydning: vi.fn(), purgeStorage: {},
  purgeFejl: (e: { message: string }) => ({ kind: 'raw', tekst: e.message }),
}));
vi.mock('../../data/redaktionWrite', () => ({ submitChange: vi.fn() }));
afterEach(cleanup);
beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(fetchPurgeUdbakke).mockResolvedValue([{ bucket: 'media', sti: 'sha/a.jpg', oprettet: '2026-11-17T10:00:00Z' }]);
  vi.mocked(executePurgeOprydning).mockResolvedValue({ kind: 'completed' });
});
it('viser bucket, sti og oprettet og genhenter efter oprydning uden at slette personen igen', async () => {
  render(<PersonPurgeUdbakke dryRun={false} role="redaktion" revision={0} />);
  await screen.findByText(/media \/ sha\/a.jpg/);
  expect(screen.getByText(/2026-11-17T10:00:00Z/)).toBeTruthy();
  vi.mocked(fetchPurgeUdbakke).mockResolvedValueOnce([]);
  fireEvent.click(screen.getByRole('button', { name: 'Prøv oprydning igen' }));
  await screen.findByText('Ingen filer venter.');
  expect(executePurgeOprydning).toHaveBeenCalledWith({ dryRun: false, role: 'redaktion' }, expect.objectContaining({ submit: expect.any(Function) }));
});
it('sender dryRun videre og bevarer filerne synligt', async () => {
  vi.mocked(executePurgeOprydning).mockResolvedValueOnce({ kind: 'dry-run' });
  render(<PersonPurgeUdbakke dryRun role="redaktion" revision={0} />);
  await screen.findByText(/sha\/a.jpg/); fireEvent.click(screen.getByRole('button', { name: 'Prøv oprydning igen' }));
  await screen.findByText('Dry-run: ingen filer er slettet eller kvitteret.');
  expect(executePurgeOprydning).toHaveBeenCalledWith({ dryRun: true, role: 'redaktion' }, expect.anything());
  expect(await screen.findByText(/sha\/a.jpg/)).toBeTruthy();
});
it('viser advarslen og den tilbageværende fil efter Storage-fejl', async () => {
  vi.mocked(executePurgeOprydning).mockResolvedValueOnce({ kind: 'completed', storageAdvarsel: 'Storage nede — prøv igen' });
  render(<PersonPurgeUdbakke dryRun={false} role="redaktion" revision={0} />);
  await screen.findByText(/sha\/a.jpg/); fireEvent.click(screen.getByRole('button', { name: 'Prøv oprydning igen' }));
  await screen.findByText('Storage nede — prøv igen'); expect(await screen.findByText(/sha\/a.jpg/)).toBeTruthy();
});
it('en listefejl vises som fejl, og Genindlæs filer kan hente den igen', async () => {
  vi.mocked(fetchPurgeUdbakke).mockRejectedValueOnce(new Error('listen nede'));
  render(<PersonPurgeUdbakke dryRun={false} role="redaktion" revision={0} />);
  await screen.findByRole('alert'); expect(screen.queryByText('Ingen filer venter.')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: 'Genindlæs filer' })); await screen.findByText(/sha\/a.jpg/);
});
it('genhenter ved en ny personsletning og læser ikke som medlem', async () => {
  const { rerender } = render(<PersonPurgeUdbakke dryRun={false} role="medlem" revision={0} />);
  expect(fetchPurgeUdbakke).not.toHaveBeenCalled(); expect(screen.queryByRole('region')).toBeNull();
  rerender(<PersonPurgeUdbakke dryRun={false} role="redaktion" revision={0} />);
  await screen.findByText(/sha\/a.jpg/);
  rerender(<PersonPurgeUdbakke dryRun={false} role="redaktion" revision={1} />);
  await waitFor(() => expect(fetchPurgeUdbakke).toHaveBeenCalledTimes(2));
});
