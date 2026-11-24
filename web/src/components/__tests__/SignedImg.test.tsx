// @vitest-environment jsdom
// Review 37 W7: en udløbet signeret URL fornyes én gang ved indlæsningsfejl; derefter kalderens onError.
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const fornyUrl = vi.fn<(url: string) => Promise<string | null>>();
vi.mock('../../data/media', () => ({ fornyUrl: (url: string) => fornyUrl(url) }));

const { SignedImg } = await import('../SignedImg');

beforeEach(() => { fornyUrl.mockReset(); });

describe('SignedImg (review 37 W7)', () => {
  it('en indlæsningsfejl fornyer URL\'en og viser den nye', async () => {
    fornyUrl.mockResolvedValue('https://x/ny');
    const onError = vi.fn();
    render(<SignedImg src="https://x/gammel" alt="billede" onError={onError} />);
    fireEvent.error(screen.getByAltText('billede'));
    await waitFor(() => expect(screen.getByAltText('billede').getAttribute('src')).toBe('https://x/ny'));
    expect(fornyUrl).toHaveBeenCalledWith('https://x/gammel');
    expect(onError).not.toHaveBeenCalled();
  });

  it('fejler også den fornyede URL, kaldes onError — ingen løkke', async () => {
    fornyUrl.mockResolvedValue('https://x/ny');
    const onError = vi.fn();
    render(<SignedImg src="https://x/gammel" alt="billede" onError={onError} />);
    fireEvent.error(screen.getByAltText('billede'));
    await waitFor(() => expect(screen.getByAltText('billede').getAttribute('src')).toBe('https://x/ny'));
    fireEvent.error(screen.getByAltText('billede'));
    expect(onError).toHaveBeenCalledTimes(1);
    expect(fornyUrl).toHaveBeenCalledTimes(1);
  });

  it('kan URL\'en ikke fornyes, kaldes onError', async () => {
    fornyUrl.mockResolvedValue(null);
    const onError = vi.fn();
    render(<SignedImg src="https://x/gammel" alt="billede" onError={onError} />);
    fireEvent.error(screen.getByAltText('billede'));
    await waitFor(() => expect(onError).toHaveBeenCalledTimes(1));
  });

  it('en ny src fra kalderen giver et nyt fornyelsesforsøg', async () => {
    fornyUrl.mockResolvedValue(null);
    const { rerender } = render(<SignedImg src="https://x/a" alt="billede" />);
    fireEvent.error(screen.getByAltText('billede'));
    await waitFor(() => expect(fornyUrl).toHaveBeenCalledTimes(1));
    rerender(<SignedImg src="https://x/b" alt="billede" />);
    expect(screen.getByAltText('billede').getAttribute('src')).toBe('https://x/b');
    fireEvent.error(screen.getByAltText('billede'));
    await waitFor(() => expect(fornyUrl).toHaveBeenLastCalledWith('https://x/b'));
  });
});
