// @vitest-environment jsdom
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MediaDetaljeOverlay, type MediaFletResultat } from '../MediaDetaljeOverlay';
import type { MediaFakta } from '../../data/media';

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

  it('flet-advarslen nævner at metadata-fakta på kopien ikke flyttes (MM-04)', () => {
    render(<MediaDetaljeOverlay {...props()} onFlet={async () => ({ kind: 'completed', lines: [] } as MediaFletResultat)} />);
    expect(screen.getByText(/Metadata-fakta på kopien flyttes ikke og bliver stående/)).toBeTruthy();
  });
});

// Task 4 (medie-metadata): kilde/beskrivelse-feltgrupper + præudfyld (MM-03/MM-11/MM-12).
const fv = (factId: string, vaerdi: string): MediaFakta[keyof MediaFakta] =>
  ({ factId, vaerdi, dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null });

function faktaProps(fakta: MediaFakta | undefined, overrides: Record<string, unknown> = {}) {
  return props({ fakta, onGemFakta: noop, onFjernFakta: noop, ...overrides });
}

describe('MediaDetaljeOverlay — kilde og beskrivelse', () => {
  it('præudfylder kilde-felter fra fakta-prop', () => {
    render(<MediaDetaljeOverlay {...faktaProps({ kilde_url: fv('10', 'https://x') })} />);
    expect((screen.getByLabelText('Kilde-URL') as HTMLInputElement).value).toBe('https://x');
  });

  it('viser henter-tilstand og ingen gem-knap når fakta ikke er indlæst', () => {
    render(<MediaDetaljeOverlay {...faktaProps(undefined)} />);
    expect(screen.getByText('Henter kildefelter…')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Gem kilde & beskrivelse' })).toBeNull();
  });

  it('Gem er disabled uden ændringer', () => {
    render(<MediaDetaljeOverlay {...faktaProps({ fotograf: fv('77', 'Sönke Ehlert') })} />);
    expect((screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }) as HTMLButtonElement).disabled).toBe(true);
  });

  it('Gem sender kun ændrede felter', () => {
    const onGemFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({ kilde_institution: fv('4', 'Det Kgl. Bibliotek') }, { onGemFakta })} />);
    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Sönke Ehlert' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    expect(onGemFakta).toHaveBeenCalledWith([{ faktatype: 'fotograf', vaerdi: 'Sönke Ehlert' }], '');
  });

  it('tømt felt der havde værdi medtages IKKE i payload', () => {
    const onGemFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({ fotograf: fv('77', 'Sönke Ehlert') }, { onGemFakta })} />);
    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('Teknik'), { target: { value: 'Daguerreotypi' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    expect(onGemFakta).toHaveBeenCalledWith([{ faktatype: 'teknik', vaerdi: 'Daguerreotypi' }], '');
  });

  it('Fjern kalder onFjernFakta med factId', () => {
    const onFjernFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({ fotograf: fv('77', 'Sönke Ehlert') }, { onFjernFakta })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Fjern Fotograf' }));
    expect(onFjernFakta).toHaveBeenCalledWith('77');
  });

  it('ugyldig kilde_url giver fejl og udelades af payload (MM-11)', () => {
    const onGemFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({}, { onGemFakta })} />);
    fireEvent.change(screen.getByLabelText('Kilde-URL'), { target: { value: 'ftp://arkiv.dk/x' } });
    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Sönke Ehlert' } });
    expect(screen.getByText(/Kilde-URL skal starte med http:\/\/ eller https:\/\//)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    expect(onGemFakta).toHaveBeenCalledWith([{ faktatype: 'fotograf', vaerdi: 'Sönke Ehlert' }], '');
  });

  it('datering sender rå tekst + kvalifikator med kanonisk engelsk value og dansk label (MM-07)', () => {
    const onGemFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({}, { onGemFakta })} />);
    const select = screen.getByLabelText('Datering kvalifikator') as HTMLSelectElement;
    expect([...select.options].map((o) => [o.value, o.text])).toEqual([
      ['', 'ikke sat'], ['about', 'ca.'], ['before', 'før'], ['after', 'efter'],
    ]);
    fireEvent.change(screen.getByLabelText('Datering (rå tekst)'), { target: { value: 'ca. 1850' } });
    fireEvent.change(select, { target: { value: 'about' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    expect(onGemFakta).toHaveBeenCalledWith([
      { faktatype: 'datering', vaerdi: 'ca. 1850', dateMin: null, dateMax: null, dateQualifier: 'about' },
    ], '');
  });

  it('kildenote sendes med som fritekst', () => {
    const onGemFakta = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({}, { onGemFakta })} />);
    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Sönke Ehlert' } });
    fireEvent.change(screen.getByLabelText('Kildenote'), { target: { value: 'Arkivets e-mail 2026-08-01' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    expect(onGemFakta).toHaveBeenCalledWith([{ faktatype: 'fotograf', vaerdi: 'Sönke Ehlert' }], 'Arkivets e-mail 2026-08-01');
  });

  it('gamle rettighedsfelter præudfyldes fra fakta (MM-12)', () => {
    render(<MediaDetaljeOverlay {...faktaProps({ licens: fv('5', 'CC-BY-4.0'), kildehenvisning: fv('6', 'DAA 1939') })} />);
    expect(screen.getByDisplayValue('CC-BY-4.0')).toBeTruthy();
    expect(screen.getByDisplayValue('DAA 1939')).toBeTruthy();
  });

  it('Gem rettigheder sender IKKE uændrede fritekstfelter (MM-03)', () => {
    const onGemRettigheder = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({ licens: fv('5', 'CC-BY-4.0') }, { onGemRettigheder })} />);
    fireEvent.click(screen.getByRole('button', { name: 'licenseret' }));
    fireEvent.click(screen.getByRole('button', { name: 'Gem rettigheder' }));
    expect(onGemRettigheder).toHaveBeenCalledTimes(1);
    const payload = onGemRettigheder.mock.calls[0][0];
    expect(payload.status).toBe('licenseret');
    expect(payload).not.toHaveProperty('licens');
    expect(payload).not.toHaveProperty('kildehenvisning');
    expect(payload).not.toHaveProperty('gengivelsestilladelse');
  });

  it('Gem rettigheder sender et ÆNDRET fritekstfelt', () => {
    const onGemRettigheder = vi.fn();
    render(<MediaDetaljeOverlay {...faktaProps({ licens: fv('5', 'CC-BY-4.0') }, { onGemRettigheder })} />);
    fireEvent.change(screen.getByDisplayValue('CC-BY-4.0'), { target: { value: 'CC0' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem rettigheder' }));
    expect(onGemRettigheder.mock.calls[0][0].licens).toBe('CC0');
  });
});
