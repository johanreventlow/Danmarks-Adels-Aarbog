// @vitest-environment jsdom
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MediaDetaljeOverlay, type MediaFletResultat } from '../MediaDetaljeOverlay';

const baseMedia = {
  id: '9223372036854775807', slags: 'foto', titel: 'Kopi', storagePath: 'large.jpg',
  kunstner: null, datering: null, rettighederStatus: 'ukendt', mimeType: 'image/jpeg',
  byteSize: 100, bredde: 10, hoejde: 20, originalFilnavn: 'kopi.jpg', uploadStatus: 'fjernet',
  maaPubliceres: false, createdAt: null, url: 'signed:large', thumbUrl: 'signed:thumb',
};
const candidate = { ...baseMedia, id: '9007199254740992', titel: 'Original', uploadStatus: 'klar' };
const noop = () => {};

function props(overrides: Record<string, unknown> = {}) {
  return {
    media: baseMedia,
    anvendelse: { afbildet: [], mentions: [] },
    fletKandidater: [candidate],
    onClose: noop, onPreview: noop, onGemMetadata: noop, onGemRettigheder: noop,
    onFjern: noop, onSlet: noop, onGenopret: noop,
    ...overrides,
  };
}

describe('MediaDetaljeOverlay — sikker fletdialog', () => {
  it('har et associeret label på original-picker', () => {
    render(<MediaDetaljeOverlay {...props()} onFlet={async () => ({ kind: 'completed', lines: [] } as MediaFletResultat)} />);
    fireEvent.click(screen.getByRole('button', { name: 'Flet ind i…' }));
    expect(screen.getByLabelText('Original · beholdes')).toBeTruthy();
  });

  it('låser alle mutationer, genopret og dismiss mens fletningen kører', async () => {
    let resolve!: (value: MediaFletResultat) => void;
    const pending = new Promise<MediaFletResultat>((r) => { resolve = r; });
    const onFlet = vi.fn(() => pending);
    const onGenopret = vi.fn();
    const onClose = vi.fn();
    render(<MediaDetaljeOverlay {...props({ onFlet, onGenopret, onClose })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Flet ind i…' }));
    const original = screen.getByLabelText('Original · beholdes') as HTMLSelectElement;
    fireEvent.change(original, { target: { value: candidate.id } });
    fireEvent.click(screen.getByRole('button', { name: 'Kør blød flet' }));
    await waitFor(() => expect(onFlet).toHaveBeenCalledTimes(1));

    expect(original.disabled).toBe(true);
    expect(screen.getByDisplayValue('Kopi').matches(':disabled')).toBe(true);
    expect(screen.getByRole('button', { name: 'Genopret' }).matches(':disabled')).toBe(true);
    expect((screen.getByRole('button', { name: '×' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Genopret' }));
    fireEvent.click(screen.getByRole('button', { name: '×' }));
    expect(onGenopret).not.toHaveBeenCalled();
    expect(onClose).not.toHaveBeenCalled();

    resolve({ kind: 'completed', lines: [] } as MediaFletResultat);
    await waitFor(() => expect(original.disabled).toBe(false));
  });

  it('viser et ændret autoritativt mention-snapshot og kræver et nyt klik', async () => {
    const changed = [{ kildeType: 'narrative', kildeId: '9223372036854775807', subjektNavn: 'Ny person' }];
    const onFlet = vi.fn()
      .mockResolvedValueOnce({ kind: 'mentions-changed', mentions: changed })
      .mockResolvedValueOnce({ kind: 'completed', lines: ['færdig'] });
    render(<MediaDetaljeOverlay {...props({ onFlet })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Flet ind i…' }));
    fireEvent.change(screen.getByLabelText('Original · beholdes'), { target: { value: candidate.id } });
    fireEvent.click(screen.getByRole('button', { name: 'Kør blød flet' }));

    expect(await screen.findByText(/Mentions er ændret siden din første gennemgang/)).toBeTruthy();
    expect(screen.getByText(/narrative #9223372036854775807 på Ny person/)).toBeTruthy();
    expect(onFlet).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: 'Gennemgået — kør blød flet' }));
    await waitFor(() => expect(onFlet).toHaveBeenCalledTimes(2));
    expect(onFlet.mock.calls[1][1]).toEqual(changed);
  });

  it('låser også preview-navigation mens fletningen kører', async () => {
    let resolve!: (value: MediaFletResultat) => void;
    const pending = new Promise<MediaFletResultat>((r) => { resolve = r; });
    const onPreview = vi.fn();
    render(<MediaDetaljeOverlay {...props({
      media: { ...baseMedia, uploadStatus: 'klar' }, onPreview, onFlet: () => pending,
    })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Flet ind i…' }));
    fireEvent.change(screen.getByLabelText('Original · beholdes'), { target: { value: candidate.id } });
    fireEvent.click(screen.getByRole('button', { name: 'Kør blød flet' }));
    await waitFor(() => expect(screen.getByAltText('Kopi').getAttribute('aria-disabled')).toBe('true'));
    fireEvent.click(screen.getByAltText('Kopi'));
    expect(onPreview).not.toHaveBeenCalled();
    await act(async () => resolve({ kind: 'completed', lines: [] }));
  });
});
