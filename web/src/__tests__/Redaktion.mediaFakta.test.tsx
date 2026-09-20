// @vitest-environment jsdom
// Task 5 (medie-metadata): wiring af "Kilde og beskrivelse"-sektionen (Task 4's overlay) i
// Redaktion.tsx. Dækker KUN wiring'en — feltgruppernes egen logik (diff/whitelist/præudfyld) er
// allerede testet i MediaDetaljeOverlay.test.tsx. Denne fil dokumenterer/regressionstester:
//  1. En 'mediaFakta'-change sendes med { dryRun: <den globale dryRun-state> } — IKKE en hardkodet
//     false (PR #72-fælden, MM-10, brief-step 3), i begge polariteter.
//  2. 'onFjernFakta' sender 'tilbagetraekFakta' og — fordi den art IKKE er i MEDIA_ARTER — genhenter
//     medie-fakta eksplicit efter en LIVE fjernelse, men aldrig ved dry-run (MM-08).
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { RedSession } from '../data/auth';
import type { MediaBibliotekPost } from '../data/redaktionRead';
import type { MediaFakta } from '../data/media';

const mocks = vi.hoisted(() => ({
  currentSession: vi.fn(),
  fetchRedaktionPersoner: vi.fn(),
  fetchSources: vi.fn(),
  fetchMediaBibliotek: vi.fn(),
  fetchMediaAnvendelse: vi.fn(),
  fetchUdrensPreview: vi.fn(),
  loadModel: vi.fn(),
  fetchMediaFakta: vi.fn(),
  submitChange: vi.fn(),
}));

vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession,
  signIn: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock('../data/redaktionRead', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionRead')>()),
  fetchRedaktionPersoner: mocks.fetchRedaktionPersoner,
  fetchSources: mocks.fetchSources,
  fetchMediaBibliotek: mocks.fetchMediaBibliotek,
  fetchMediaAnvendelse: mocks.fetchMediaAnvendelse,
  fetchUdrensPreview: mocks.fetchUdrensPreview,
}));

vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));

vi.mock('../data/media', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/media')>()),
  fetchMediaFakta: mocks.fetchMediaFakta,
}));

vi.mock('../data/redaktionWrite', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionWrite')>()),
  submitChange: mocks.submitChange,
}));

import Redaktion from '../Redaktion';

function session(role: string): RedSession {
  return { email: 'red@example.dk', role, userId: 'u1' };
}

function mediaRow(overrides: Partial<MediaBibliotekPost> = {}): MediaBibliotekPost {
  return {
    id: '42', slags: 'foto', titel: 'Testfoto', storagePath: 'x.jpg',
    kunstner: null, datering: null, rettighederStatus: 'ukendt',
    mimeType: 'image/jpeg', byteSize: 100, bredde: 10, hoejde: 20,
    originalFilnavn: 'x.jpg', uploadStatus: 'klar', maaPubliceres: true,
    createdAt: null, primaer: false, sha256: 'abc123', url: 'signed:large', thumbUrl: 'signed:thumb',
    antalAfbildet: 0, antalMentions: 0, koeer: [],
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.history.pushState(null, '', '/redaktion/media');

  mocks.currentSession.mockResolvedValue(session('redaktion'));
  mocks.fetchRedaktionPersoner.mockResolvedValue([]);
  mocks.fetchSources.mockResolvedValue([]);
  mocks.loadModel.mockResolvedValue(null);
  mocks.fetchMediaBibliotek.mockResolvedValue([mediaRow()]);
  mocks.fetchMediaAnvendelse.mockResolvedValue({ afbildet: [], mentions: [] });
  mocks.fetchUdrensPreview.mockResolvedValue(undefined);
  mocks.submitChange.mockResolvedValue({ dryRun: false, call: { fn: 'red_upsert_fakta', args: {} }, direkte: true });
});

// Åbner filsiden for det ene testmedie og venter på at "Kilde og beskrivelse"-sektionen er
// færdig-hentet (ikke i sin henter-tilstand).
async function aabnMediaDetalje() {
  render(<Redaktion />);
  fireEvent.click(await screen.findByText('Testfoto'));
  await screen.findByText('Kilde og beskrivelse');
  await waitFor(() => expect(screen.queryByText('Henter kildefelter…')).toBeNull());
}

describe('Redaktion — medie-fakta wiring: dryRun følger den globale state (MM-10)', () => {
  test('Gem kilde & beskrivelse sender dryRun=true (default) og dryRun=false efter flip', async () => {
    // Andet kald simulerer en realistisk backend: efter det LIVE gem er værdien reelt persisteret,
    // så refetch'et (brief-step 2) rent faktisk finder den — en evigt-tom mock ville stille nulstille
    // faktaForm til '' via Task 4's præudfyld-effekt og gøre resten af testen meningsløs.
    mocks.fetchMediaFakta
      .mockResolvedValueOnce(new Map<string, MediaFakta>())
      .mockResolvedValueOnce(new Map<string, MediaFakta>([
        ['42', { fotograf: { factId: '1', vaerdi: 'Sönke Ehlert', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null } }],
      ]));
    await aabnMediaDetalje();

    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Sönke Ehlert' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));

    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
    const [change1, opts1] = mocks.submitChange.mock.calls[0];
    expect(change1.art).toBe('mediaFakta');
    expect(change1.payload.faktatype).toBe('fotograf');
    expect(opts1).toEqual({ dryRun: true, role: 'redaktion' });
    // dry-run: ingen refetch af fakta (kun det ene indledende kald fra åbningen af overlayet).
    expect(mocks.fetchMediaFakta).toHaveBeenCalledTimes(1);

    // Flip 1: slå prøvekørsel fra via den EKSISTERENDE topbjælke-kontrol.
    fireEvent.click(screen.getByText('Dry-run · skriver ikke'));
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));

    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(2));
    const [change2, opts2] = mocks.submitChange.mock.calls[1];
    expect(change2.art).toBe('mediaFakta');
    expect(opts2).toEqual({ dryRun: false, role: 'redaktion' });
    // LIVE-gem: overlayet skal vise de netop gemte værdier → eksplicit refetch (brief-step 2).
    await waitFor(() => expect(mocks.fetchMediaFakta).toHaveBeenCalledTimes(2));
    await waitFor(() => expect((screen.getByLabelText('Fotograf') as HTMLInputElement).value).toBe('Sönke Ehlert'));

    // Flip 2 (regression, begge polariteter — en hardkodet dryRun={true} eller ={false} kan ikke
    // overleve begge flips i samme test). En ny ændring, da feltet efter refetch'et matcher den
    // gemte værdi og "Gem"-knappen ellers er disabled uden en reel diff.
    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Ny fotograf' } });
    fireEvent.click(screen.getByText('LIVE · skriver til basen'));
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(3));
    expect(mocks.submitChange.mock.calls[2][1]).toEqual({ dryRun: true, role: 'redaktion' });
    expect(mocks.fetchMediaFakta).toHaveBeenCalledTimes(2); // stadig ingen refetch ved dry-run
  });
});

describe('Redaktion — medie-fakta wiring: sekventielt awaited gem-loop (MM-08)', () => {
  test('to ændrede felter sendes ét ad gangen — IKKE parallelt (Promise.all ville afsløre sig her)', async () => {
    mocks.fetchMediaFakta.mockResolvedValue(new Map<string, MediaFakta>());
    let resolveFoerste!: () => void;
    const foerstePending = new Promise<void>((resolve) => { resolveFoerste = resolve; });
    mocks.submitChange.mockImplementation(async () => {
      // Kun DET FØRSTE kald hænger — et 2. kald der ankommer før vi løser det første ville
      // bevise en parallel implementering (Promise.all over changes.map(...) kalder submitChange
      // for begge felter SYNKRONT, før nogen af dem er awaited).
      if (mocks.submitChange.mock.calls.length === 1) await foerstePending;
      return { dryRun: false, call: { fn: 'red_upsert_fakta', args: {} }, direkte: true };
    });
    await aabnMediaDetalje();

    fireEvent.change(screen.getByLabelText('Fotograf'), { target: { value: 'Sönke Ehlert' } });
    fireEvent.change(screen.getByLabelText('Kilde-institution'), { target: { value: 'Det Kgl. Bibliotek' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem kilde & beskrivelse' }));

    // Umiddelbart efter klikket (synkront — INGEN await/waitFor endnu): en sekventiel
    // for-await-loop har kun nået at kalde submitChange ÉN gang, fordi den første await hænger.
    // Rækkefølgen følger MEDIA_FAKTATYPER (data/media.ts): kilde_institution (gruppen "Kilde")
    // kommer før fotograf (gruppen "Ophav") — det væsentlige her er ikke hvilket felt der er
    // først, men at det ANDET kald først sker EFTER det første er afsluttet.
    expect(mocks.submitChange).toHaveBeenCalledTimes(1);
    expect(mocks.submitChange.mock.calls[0][0].payload.faktatype).toBe('kilde_institution');

    resolveFoerste();
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(2));
    expect(mocks.submitChange.mock.calls[1][0].payload.faktatype).toBe('fotograf');
  });
});

describe('Redaktion — medie-fakta wiring: Fjern → tilbagetraekFakta + refetch kun ved LIVE (MM-08)', () => {
  test('Fjern-knappen tilbagetrækker fakta og refetcher medie-fakta først efter et LIVE kald', async () => {
    mocks.fetchMediaFakta.mockResolvedValue(new Map<string, MediaFakta>([
      ['42', { fotograf: { factId: '77', vaerdi: 'Eksisterende', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null } }],
    ]));
    await aabnMediaDetalje();

    // Dry-run: Fjern sender changen, men genhenter IKKE (tilbagetraekFakta er en generisk art,
    // uden for MEDIA_ARTER — run()'s automatiske medie-refetch fyrer derfor ikke; wiring'en i
    // Redaktion.tsx skal selv styre refetch, og skal respektere dryRun ligesom Gem-knappen).
    fireEvent.click(screen.getByRole('button', { name: 'Fjern Fotograf' }));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
    const [change1, opts1] = mocks.submitChange.mock.calls[0];
    expect(change1.art).toBe('tilbagetraekFakta');
    expect(change1.factId).toBe('77');
    expect(opts1).toEqual({ dryRun: true, role: 'redaktion' });
    expect(mocks.fetchMediaFakta).toHaveBeenCalledTimes(1); // kun det indledende hent-kald

    // LIVE: samme knap, nu skal en refetch følge.
    fireEvent.click(screen.getByText('Dry-run · skriver ikke'));
    fireEvent.click(screen.getByRole('button', { name: 'Fjern Fotograf' }));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(2));
    expect(mocks.submitChange.mock.calls[1][1]).toEqual({ dryRun: false, role: 'redaktion' });
    await waitFor(() => expect(mocks.fetchMediaFakta).toHaveBeenCalledTimes(2));
  });
});
