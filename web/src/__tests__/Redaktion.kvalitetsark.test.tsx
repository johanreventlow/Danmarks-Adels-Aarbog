// @vitest-environment jsdom
// Task 9 (halvdel B): integration af personers OCR-kvalitetsark (grid + kildepanel) i
// Redaktion.tsx — se docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md "Task 9".
// PersonKvalitetsark.tsx og OcrKildepanel.tsx er begge færdige, testede byggeklodser
// (Task 8 / Task 9a); disse tests dækker KUN wiring'en: rolle-/entitets-gate for
// Liste/Kvalitetsark-skifteren, dovent-hentet grid (cachet for sessionen), dovent-hentet
// pr.-celle-historik, "gemning erstatter kun den returnerede række", at et exit til den
// almindelige liste ikke mister den valgte person, og at prøvekørsel-tilstanden reelt er den
// globale `dryRun`-værdi (ikke en hardkodet konstant) — begge polariteter, i ét flip.
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { PersonKvalitetsarkRow } from '@daa/core';
import type { RedSession } from '../data/auth';

const mocks = vi.hoisted(() => ({
  currentSession: vi.fn(),
  signIn: vi.fn(),
  signOut: vi.fn(),
  fetchRedaktionPersoner: vi.fn(),
  fetchSources: vi.fn(),
  fetchPersonEvidence: vi.fn(),
  fetchHaendelserForPerson: vi.fn(),
  fetchStoriesForPerson: vi.fn(),
  fetchNarrativer: vi.fn(),
  fetchPersonFamilie: vi.fn(),
  fetchPersonRelationer: vi.fn(),
  fetchSammeSomLinks: vi.fn(),
  fetchRedPersonMedia: vi.fn(),
  fetchForaeldreUkendtMarkering: vi.fn(),
  fetchForaeldreSlot: vi.fn(),
  fetchBarnFamilie: vi.fn(),
  loadModel: vi.fn(),
  fetchPersonKvalitetsark: vi.fn(),
  fetchOcrHistorik: vi.fn(),
  retOcrFelt: vi.fn(),
}));

vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession,
  signIn: mocks.signIn,
  signOut: mocks.signOut,
}));

// Kun de fetchere `loadPerson`/mount-effekterne rent faktisk kalder overstyres — resten
// (buildTidslinje, storyPrefillFraPost, nudgeOrdinal, formatMedieAlder m.fl.) forbliver de
// ægte, rene funktioner via importOriginal (samme mønster som MatchOversigt.test.tsx).
vi.mock('../data/redaktionRead', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionRead')>()),
  fetchRedaktionPersoner: mocks.fetchRedaktionPersoner,
  fetchSources: mocks.fetchSources,
  fetchPersonEvidence: mocks.fetchPersonEvidence,
  fetchHaendelserForPerson: mocks.fetchHaendelserForPerson,
  fetchStoriesForPerson: mocks.fetchStoriesForPerson,
  fetchNarrativer: mocks.fetchNarrativer,
  fetchPersonFamilie: mocks.fetchPersonFamilie,
  fetchPersonRelationer: mocks.fetchPersonRelationer,
  fetchSammeSomLinks: mocks.fetchSammeSomLinks,
  fetchRedPersonMedia: mocks.fetchRedPersonMedia,
  fetchForaeldreUkendtMarkering: mocks.fetchForaeldreUkendtMarkering,
  fetchForaeldreSlot: mocks.fetchForaeldreSlot,
  fetchBarnFamilie: mocks.fetchBarnFamilie,
}));

vi.mock('../data/model', () => ({
  loadModel: mocks.loadModel,
}));

// oversaetOcrFejl er en ren funktion og forbliver ægte (importOriginal) — kun de tre RPC-
// vendte adaptere overstyres. Havde den været blanket-mocket til undefined, ville
// `setKvError(oversaetOcrFejl(e))` kaste inde i en .catch og fremstå som en uhåndteret
// rejection frem for en ren test-fejl.
vi.mock('../data/personKvalitetsark', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/personKvalitetsark')>()),
  fetchPersonKvalitetsark: mocks.fetchPersonKvalitetsark,
  fetchOcrHistorik: mocks.fetchOcrHistorik,
  retOcrFelt: mocks.retOcrFelt,
}));

import Redaktion from '../Redaktion';

function session(role: string): RedSession {
  return { email: 'red@example.dk', role, userId: 'u1' };
}

function kvRow(overrides: Partial<PersonKvalitetsarkRow> = {}): PersonKvalitetsarkRow {
  return {
    personId: '1',
    importKey: 'daa-2018-reventlow',
    recordKey: 'p-001',
    sourceId: '7',
    sourceTitel: 'Danmarks Adels Aarbog 2018-20',
    sourceUdgave: '2018-20',
    linje: 'III',
    nr: 12,
    slaegtled: 5,
    personStatus: 'ok',
    navn: 'Christian Ditlev Reventlow',
    navnAssertionId: '501',
    foedselRaw: '12. juli 1748',
    foedselMin: '1748-07-12',
    foedselMax: '1748-07-12',
    foedselQualifier: 'exact',
    foedselAssertionId: '502',
    doedRaw: '1827',
    doedMin: '1827-01-01',
    doedMax: '1827-12-31',
    doedQualifier: null,
    doedAssertionId: '503',
    koen: 'mand',
    levende: false,
    privat: false,
    staged: false,
    kanoniskPersonId: null,
    sammeSomStatus: null,
    antalTitler: 2,
    antalFamilier: 1,
    antalRelationer: 4,
    antalKildeAssertions: 3,
    qaKoder: [],
    qaAlvor: null,
    reviewStatus: {},
    kanRettes: { navn: true, foedsel: true, doed: true, koen: true },
    blokarsager: {},
    ocrContext: { navn: 'Chr: Ditlev Reüentlow (OCR-tekst)', foedsel: '12. juli 1748', doed: '1827' },
    kildeSide: { navn: '42', foedsel: '42', doed: '43' },
    importeret: {
      navn: { value: 'Christian Ditlev Reventlow' },
      foedsel: { raw: '12. juli 1748', min: '1748-07-12', max: '1748-07-12', qualifier: 'exact', calendar: 'gregoriansk', certainty: null },
      doed: { raw: '1827', min: '1827-01-01', max: '1827-12-31', qualifier: null, calendar: 'gregoriansk', certainty: null },
      koen: { value: 'mand' },
    },
    korrigeret: {},
    inputFingerprint: { navn: 'fp-navn', foedsel: 'fp-foedsel', doed: 'fp-doed', koen: 'fp-koen' },
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.history.pushState(null, '', '/redaktion');

  mocks.currentSession.mockResolvedValue(session('redaktion'));
  mocks.fetchRedaktionPersoner.mockResolvedValue([]);
  mocks.fetchSources.mockResolvedValue([]);
  mocks.fetchPersonEvidence.mockResolvedValue({ felter: {}, koen: null });
  mocks.fetchHaendelserForPerson.mockResolvedValue([]);
  mocks.fetchStoriesForPerson.mockResolvedValue([]);
  mocks.fetchNarrativer.mockResolvedValue([]);
  mocks.fetchPersonFamilie.mockResolvedValue({ somPartner: [], somBarn: [] });
  mocks.fetchPersonRelationer.mockResolvedValue([]);
  mocks.fetchSammeSomLinks.mockResolvedValue([]);
  mocks.fetchRedPersonMedia.mockResolvedValue([]);
  mocks.fetchForaeldreUkendtMarkering.mockResolvedValue(null);
  mocks.fetchForaeldreSlot.mockResolvedValue(null);
  mocks.fetchBarnFamilie.mockResolvedValue(null);
  mocks.loadModel.mockResolvedValue(null);
  mocks.fetchPersonKvalitetsark.mockResolvedValue([kvRow()]);
  mocks.fetchOcrHistorik.mockResolvedValue([]);
  mocks.retOcrFelt.mockResolvedValue(kvRow());
});

// Åbner kvalitetsark-tilstanden og venter på at griddet er hentet — delt opstart for de tests
// der arbejder inde i tilstanden.
async function aabnKvalitetsark() {
  render(<Redaktion />);
  const knap = await screen.findByRole('button', { name: 'Kvalitetsark' });
  fireEvent.click(knap);
  await screen.findByText('Christian Ditlev Reventlow');
}

describe('Redaktion — Liste/Kvalitetsark-skifter (rolle- og entitetsgate)', () => {
  test('redaktør ser skifteren på person-entiteten', async () => {
    render(<Redaktion />);
    expect(await screen.findByRole('group', { name: 'Personvisning' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Liste' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Kvalitetsark' })).toBeTruthy();
  });

  test('medlem ser IKKE skifteren', async () => {
    mocks.currentSession.mockResolvedValue(session('medlem'));
    render(<Redaktion />);
    // Vent på at sessionen er indlæst (personlisten er altid til stede for entity=person).
    await screen.findByPlaceholderText('Søg…');
    expect(screen.queryByRole('group', { name: 'Personvisning' })).toBeNull();
  });

  test('anonym (ikke logget ind) ser IKKE skifteren', async () => {
    mocks.currentSession.mockResolvedValue(null);
    render(<Redaktion />);
    await screen.findByPlaceholderText('Søg…');
    expect(screen.queryByRole('group', { name: 'Personvisning' })).toBeNull();
  });
});

describe('Redaktion — regression: kvalitetsarket monteres kun for entity=person', () => {
  test('media-, slægts- og en generisk entitet monterer ikke kvalitetsark-griddet', async () => {
    render(<Redaktion />);
    await screen.findByRole('button', { name: 'Kvalitetsark' });
    fireEvent.click(screen.getByRole('button', { name: 'Kvalitetsark' }));
    await screen.findByText('Christian Ditlev Reventlow');
    expect(screen.getByText('Personers OCR-kvalitetsark')).toBeTruthy();

    // Skift til en anden entitet (media) — griddet skal forsvinde, uden at rive et separat
    // "person + ikke-redaktion"-tilfælde ned med det.
    fireEvent.click(screen.getByText('Medier'));
    await waitFor(() => expect(screen.queryByText('Personers OCR-kvalitetsark')).toBeNull());
    expect(screen.queryByRole('group', { name: 'Filtrér efter status' })).toBeNull(); // PersonKvalitetsark's egen preset-bjælke

    // Slægten (generisk editor via renderSlaegtEditor, ikke person-griddet).
    fireEvent.click(screen.getByText('Slægten'));
    await waitFor(() => expect(screen.queryByText('Personers OCR-kvalitetsark')).toBeNull());

    // En vilkårlig generisk entitet (renderGenericEditor-sporet).
    fireEvent.click(screen.getByText('Godser'));
    await waitFor(() => expect(screen.queryByText('Personers OCR-kvalitetsark')).toBeNull());
  });
});

describe('Redaktion — dovent griddet, cachet for sessionen', () => {
  test('indgang i kvalitetsark henter ÉN gang, og "Alle personer" er valgt fra start', async () => {
    render(<Redaktion />);
    await screen.findByPlaceholderText('Søg…');
    expect(mocks.fetchPersonKvalitetsark).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Kvalitetsark' }));
    await screen.findByText('Christian Ditlev Reventlow');
    expect(mocks.fetchPersonKvalitetsark).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('button', { name: 'Alle personer' }).getAttribute('aria-pressed')).toBe('true');

    // Gen-besøg (liste → kvalitetsark igen) genhenter IKKE griddet — kun "Genindlæs" gør.
    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    fireEvent.click(screen.getByRole('button', { name: 'Kvalitetsark' }));
    await screen.findByText('Christian Ditlev Reventlow');
    expect(mocks.fetchPersonKvalitetsark).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole('button', { name: 'Genindlæs' }));
    await waitFor(() => expect(mocks.fetchPersonKvalitetsark).toHaveBeenCalledTimes(2));
  });

  test('ugyldig gemt personVisning i localStorage falder tilbage til liste', async () => {
    window.localStorage.setItem('redaktion.personVisning', 'noget-vrøvl');
    render(<Redaktion />);
    await screen.findByPlaceholderText('Søg…');
    expect(screen.queryByText('Personers OCR-kvalitetsark')).toBeNull();
    expect(screen.getByRole('button', { name: 'Liste' }).getAttribute('aria-pressed')).toBe('true');
  });
});

describe('Redaktion — historik hentes dovent pr. valgt celle', () => {
  test('historik hentes først når en celle vælges, ikke ved grid-indlæsning', async () => {
    await aabnKvalitetsark();
    expect(mocks.fetchOcrHistorik).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' }));
    await waitFor(() => expect(mocks.fetchOcrHistorik).toHaveBeenCalledTimes(1));
    expect(mocks.fetchOcrHistorik).toHaveBeenCalledWith('daa-2018-reventlow', 'p-001', 'navn');
  });
});

describe('Redaktion — gemning erstatter kun den returnerede række', () => {
  test('en vellykket gemning opdaterer kun den gemte person, filtre/valg bevares', async () => {
    mocks.fetchPersonKvalitetsark.mockResolvedValue([
      kvRow({ personId: '1', navn: 'Christian Ditlev Reventlow' }),
      kvRow({ personId: '2', navn: 'Anna Sofie Reventlow', importKey: 'daa-2018-reventlow', recordKey: 'p-002', inputFingerprint: { navn: 'fp-navn-2', foedsel: 'fp-foedsel-2', doed: 'fp-doed-2', koen: 'fp-koen-2' } }),
    ]);
    const opdateret = kvRow({ personId: '1', navn: 'Christian Ditlev Reventlow (rettet)' });
    mocks.retOcrFelt.mockResolvedValue(opdateret);

    await aabnKvalitetsark();
    expect(screen.getByText('Anna Sofie Reventlow')).toBeTruthy();

    // dryRun default = true → slå fra, så Gem reelt er aktiv (se separat prøvekørsels-test for
    // selve trådningen).
    fireEvent.click(screen.getByText('Dry-run · skriver ikke'));

    fireEvent.click(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' }));
    const nyVaerdi = await screen.findByLabelText('Ny værdi');
    fireEvent.change(nyVaerdi, { target: { value: 'Christian Ditlev Reventlow (rettet)' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));

    await waitFor(() => expect(mocks.retOcrFelt).toHaveBeenCalledTimes(1));
    // Grid-cellen er navne-knappen (panelets egen undertitel viser SAMME navn — matches derfor
    // specifikt via role, ellers er teksten tvetydig mellem de to steder).
    await screen.findByRole('button', { name: 'Christian Ditlev Reventlow (rettet)' });
    // Den urørte anden person's række er uændret — griddet blev IKKE genhentet i sin helhed.
    expect(screen.getByText('Anna Sofie Reventlow')).toBeTruthy();
    expect(mocks.fetchPersonKvalitetsark).toHaveBeenCalledTimes(1);
  });

  test('en afvist gemning lader lokale data stå uændret', async () => {
    mocks.retOcrFelt.mockRejectedValue(new Error('OCR_VALUE_INVALID'));
    await aabnKvalitetsark();
    fireEvent.click(screen.getByText('Dry-run · skriver ikke'));

    fireEvent.click(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' }));
    const nyVaerdi = await screen.findByLabelText('Ny værdi');
    fireEvent.change(nyVaerdi, { target: { value: 'Noget andet' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));

    await waitFor(() => expect(mocks.retOcrFelt).toHaveBeenCalledTimes(1));
    // Rækken i griddet er stadig den oprindelige — kun input-feltets udkast er ændret lokalt.
    expect(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' })).toBeTruthy();
  });
});

describe('Redaktion — exit bevarer den valgte person', () => {
  test('exit til liste mister ikke den person der var åben', async () => {
    await aabnKvalitetsark();
    // Åbn personen fra griddet (tælle-kolonnen kalder altid onOpenPerson, uafhængigt af kanRettes).
    fireEvent.click(screen.getByRole('button', { name: '2 titler' }));
    await waitFor(() => expect(window.location.pathname).toBe('/redaktion/person/1'));

    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    expect(window.location.pathname).toBe('/redaktion/person/1');

    fireEvent.click(screen.getByRole('button', { name: 'Kvalitetsark' }));
    expect(window.location.pathname).toBe('/redaktion/person/1');
  });
});

describe('Redaktion — prøvekørsel er den globale dryRun-værdi (regression, begge polariteter)', () => {
  test('flipper topbjælkens dry-run og ser panelet følge med i begge retninger', async () => {
    await aabnKvalitetsark();
    fireEvent.click(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' }));

    // dryRun default = true → panelet nægter at gemme og viser prøvekørsels-banneret.
    await screen.findByRole('note');
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);

    // Flip 1: slå prøvekørsel fra via den EKSISTERENDE topbjælke-kontrol (ikke en ny, testkun
    // kontrol) — panelet skal nu tillade gemning (navn-feltet er allerede udfyldt fra row.navn).
    fireEvent.click(screen.getByText('Dry-run · skriver ikke'));
    expect(screen.queryByRole('note')).toBeNull();
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(false);

    // Flip 2: slå den til igen — banneret og blokeringen skal komme tilbage. En hardkodet
    // proevekoersel={true} eller ={false} kan ikke overleve begge flips i samme test.
    fireEvent.click(screen.getByText('LIVE · skriver til basen'));
    expect(await screen.findByRole('note')).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);
  });
});
