// @vitest-environment jsdom
// OCR-rettelse af kildepåstand (decisions 2026-11-20): »Ret læsefejl« i personeditoren retter en importeret
// kildepåstand på stedet (red_ret_ocr_paastand) i stedet for at lægge en ny påstand ved siden af.
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { RedSession } from '../data/auth';
import type { FeltEvidens, Oplysning } from '../data/redaktionRead';

const mocks = vi.hoisted(() => ({
  currentSession: vi.fn(),
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
  submitChange: vi.fn(),
}));

vi.mock('../data/personPurge', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/personPurge')>()),
  fetchPurgeUdbakke: vi.fn().mockResolvedValue([]),
}));
vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession, signIn: vi.fn(), signOut: vi.fn(),
}));
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
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/redaktionWrite', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionWrite')>()),
  submitChange: mocks.submitChange,
}));

import Redaktion from '../Redaktion';

const session = (role: string): RedSession => ({ email: 'red@example.dk', role, userId: 'u1' });

function kildepaastand(over: Partial<Oplysning> = {}): Oplysning {
  return {
    assertionId: 13833, vaerdi: '25 Marts 157', vaerdiTekst: null, dateRaw: '25 Marts 157',
    kilder: [{ sourceId: 3, sourceTitel: 'Danmarks Adels Aarbog' }], erKonklusion: true, uforanderlig: true, ...over,
  };
}

function foedt(o: Oplysning): FeltEvidens {
  return { felt: 'foedt', faktatype: 'fødsel', factId: 11315, konklusionAssertionId: o.assertionId,
    oplysninger: [o], uenig: false };
}

async function aabnFoedt() {
  render(<Redaktion />);
  // Fødselskortets hoved (»Født« findes også som sorteringsknap i personlisten).
  fireEvent.click(await screen.findByText('1 oplysning'));
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.history.pushState(null, '', '/redaktion/person/1559');
  mocks.currentSession.mockResolvedValue(session('redaktion'));
  mocks.fetchRedaktionPersoner.mockResolvedValue([
    { id: '1559', navn: 'Sophie von Sperling', aar: '', born: null, levende: false, privat: false, efternavnAfledt: false },
  ]);
  mocks.fetchSources.mockResolvedValue([]);
  mocks.fetchPersonEvidence.mockResolvedValue({ felter: { foedt: [foedt(kildepaastand())] }, koen: null });
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
  mocks.submitChange.mockResolvedValue({ dryRun: true, call: { fn: 'red_ret_ocr_paastand', args: {} }, direkte: true });
});

describe('Redaktion — Ret læsefejl', () => {
  test('kildepåstand har knappen', async () => {
    await aabnFoedt();
    expect(await screen.findByTitle('Ret læsefejl')).toBeTruthy();
  });

  test('redaktørens egen oplysning viser ikke knappen', async () => {
    mocks.fetchPersonEvidence.mockResolvedValue({
      felter: { foedt: [foedt(kildepaastand({ uforanderlig: false, kilder: [{ sourceId: null }] }))] }, koen: null,
    });
    await aabnFoedt();
    await screen.findByTitle('Redigér');
    expect(screen.queryByTitle('Ret læsefejl')).toBeNull();
  });

  test('ikke-redaktør ser ikke knappen', async () => {
    mocks.currentSession.mockResolvedValue(session('medlem'));
    await aabnFoedt();
    await screen.findByTitle('Redigér');
    expect(screen.queryByTitle('Ret læsefejl')).toBeNull();
  });

  test('titel med både tekst og dato åbner med teksten, og Gem kræver en ændring', async () => {
    const o = kildepaastand({ assertionId: 501, vaerdi: 'Kammerjunker', vaerdiTekst: 'Kammerjunker', dateRaw: '1750' });
    mocks.fetchPersonEvidence.mockResolvedValue({
      felter: { titel: [{ felt: 'titel', faktatype: 'titel', factId: 77, konklusionAssertionId: 501, oplysninger: [o], uenig: false }] },
      koen: null,
    });
    render(<Redaktion />);
    fireEvent.click(await screen.findByText('1 oplysning'));
    fireEvent.click(await screen.findByTitle('Ret læsefejl'));
    expect(screen.getByDisplayValue('Kammerjunker')).toBeTruthy();
    fireEvent.click(screen.getByText('Gem rettelse'));
    expect(mocks.submitChange).not.toHaveBeenCalled();
  });

  test('formularen forudfyldes, fortolker datoen og sender retLaesefejl', async () => {
    await aabnFoedt();
    fireEvent.click(await screen.findByTitle('Ret læsefejl'));
    expect(screen.getByText(/Retter bogens tekst, som den står trykt/)).toBeTruthy();
    const felt = screen.getByDisplayValue('25 Marts 157');
    const gem = () => screen.getByText('Gem rettelse');
    // Uændret værdi kan ikke gemmes.
    fireEvent.click(gem());
    expect(mocks.submitChange).not.toHaveBeenCalled();
    fireEvent.change(felt, { target: { value: '25 Marts 1578' } });
    expect(screen.getByText(/Forstået som/)).toBeTruthy();
    fireEvent.click(gem());
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
    const [change, opts] = mocks.submitChange.mock.calls[0];
    expect(change).toMatchObject({
      art: 'retLaesefejl', subjektType: 'person', subjektId: '1559', assertionId: '13833',
      payload: {
        forventet: { fact_id: 11315, faktatype: 'fødsel', date_raw: '25 Marts 157', vaerdi_tekst: null,
          valgt_assertion_id: 13833, citation_sources: [3] },
        ny: { date_raw: '25 Marts 1578', date_min: '1578-01-01', date_max: '1578-12-31' },
      },
    });
    // Prøvekørsel er standard: kaldet planlægges, men sendes ikke.
    expect(opts).toMatchObject({ dryRun: true });
  });

  test('ufortolkelig dato kræver bekræftelse', async () => {
    await aabnFoedt();
    fireEvent.click(await screen.findByTitle('Ret læsefejl'));
    fireEvent.change(screen.getByDisplayValue('25 Marts 157'), { target: { value: '25 Marts 15' } });
    expect(screen.getByText(/Kan ikke fortolkes/)).toBeTruthy();
    fireEvent.click(screen.getByText('Gem rettelse'));
    expect(mocks.submitChange).not.toHaveBeenCalled();
    fireEvent.click(screen.getByLabelText('Gem alligevel uden fortolket dato'));
    fireEvent.click(screen.getByText('Gem rettelse'));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
    expect(mocks.submitChange.mock.calls[0][0].payload.ny).toEqual({
      date_raw: '25 Marts 15', date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
    });
  });
});
