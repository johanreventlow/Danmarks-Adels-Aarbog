// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { LevendeKnap } from '../LevendeKnap';
afterEach(cleanup);

// Review 37 R37P11-2: afdød → levende skjuler og sendes straks; levende → afdød kræver bekræftelse med advarsel.
it('afdød → levende sendes straks uden bekræftelse', async () => {
  const run = vi.fn().mockResolvedValue(undefined);
  render(<LevendeKnap personId="42" levende={false} privat={false} run={run} />);
  fireEvent.click(screen.getByRole('button', { name: 'Levende' }));
  await waitFor(() => expect(run).toHaveBeenCalledTimes(1));
  expect(run).toHaveBeenCalledWith({ art: 'setLevende', subjektType: 'person', subjektId: '42', payload: { levende: true } }, 'Levende');
  expect(screen.queryByRole('alertdialog')).toBeNull();
});

it('levende → afdød viser advarslen og sender først efter »Ja«', async () => {
  const run = vi.fn().mockResolvedValue(undefined);
  render(<LevendeKnap personId="42" levende={true} privat={false} run={run} />);
  fireEvent.click(screen.getByRole('button', { name: 'Levende' }));
  const advarsel = screen.getByRole('alertdialog');
  expect(advarsel.textContent).toMatch(/kan blive synlige for gæster/);
  expect(run).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Ja, sæt som afdød' }));
  await waitFor(() => expect(run).toHaveBeenCalledTimes(1));
  expect(run).toHaveBeenCalledWith({ art: 'setLevende', subjektType: 'person', subjektId: '42', payload: { levende: false } }, 'Levende');
});

it('annullér sender intet, og en privat person får den rette tekst', () => {
  const run = vi.fn();
  render(<LevendeKnap personId="42" levende={true} privat={true} run={run} />);
  fireEvent.click(screen.getByRole('button', { name: 'Levende' }));
  expect(screen.getByRole('alertdialog').textContent).toMatch(/forbliver skjult for gæster/);
  fireEvent.click(screen.getByRole('button', { name: 'Annullér' }));
  expect(screen.queryByRole('alertdialog')).toBeNull();
  expect(run).not.toHaveBeenCalled();
});
