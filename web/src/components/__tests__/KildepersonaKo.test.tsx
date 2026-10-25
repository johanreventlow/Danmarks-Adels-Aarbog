// @vitest-environment jsdom
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  decide: vi.fn(),
  detail: vi.fn(),
  queue: vi.fn(),
  persons: vi.fn(),
  history: vi.fn(),
}));

vi.mock('../../data/sourcePersona', () => ({
  decideSourcePersona: mocks.decide,
  fetchSourcePersonaDetail: mocks.detail,
  fetchSourcePersonaQueue: mocks.queue,
  fetchSourcePersonaHistory: mocks.history,
}));
vi.mock('../../data/redaktionRead', () => ({ fetchRedaktionPersoner: mocks.persons }));

import { KildepersonaKo } from '../KildepersonaKo';

const row = (n = 1) => ({
  sourcePersonaId: `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`,
  sourceId: 7,
  personaKey: `persona-${n}`,
  decisionStatus: 'proposed',
  version: 0,
  canonicalPersonId: null,
  mentionCount: 3,
});
const detail = {
  persona: row(),
  mentions: [{ mentionKind: 'person_name', mentionRole: 'primary', verbatimText: 'Johan Example', observationKind: 'name_clause', pageFrom: 12, pageTo: 12, textVersions: [] }],
  placements: [], interpretations: [],
  candidates: [{ candidateId: 'cand-1', runId: 'run-1', rank: 1, score: 0.93, tier: 'auto', personId: 42, personName: 'Johan Canonical', born: '1800', died: '1860', signals: ['name', 'birth'],
                 titles: [], ownPostKey: null, familyId: null, ordinal: null }],
  familyContext: null,
  collisions: [{ personId: 42, personaKey: 'persona-9' }],
  principalPartners: [],
  reviewReason: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.queue.mockResolvedValue([row()]);
  mocks.detail.mockResolvedValue(detail);
  mocks.persons.mockResolvedValue([{ id: '42', navn: 'Johan Canonical', aar: '1800–1860', born: 1800, levende: false, privat: false, efternavnAfledt: false }]);
  mocks.decide.mockResolvedValue(1);
  mocks.history.mockResolvedValue([]);
});

describe('KildepersonaKo', () => {
  it('holder køen lukket uden redaktionsrolle', () => {
    render(<KildepersonaKo />);
    expect(screen.getByText(/kun redaktionen/i)).toBeTruthy();
    expect(mocks.queue).not.toHaveBeenCalled();
  });

  it('afviser afgørelse før det ordrette kildegrundlag er åbnet', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Samme person' }));
    expect((await screen.findByRole('alert')).textContent).toMatch(/åbn først/i);
    expect(mocks.decide).not.toHaveBeenCalled();
  });

  it('viser kildegrundlag og sender kun valgt kanonisk kandidat ved samme-afgørelse', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText('Johan Example')).toBeTruthy();
    expect(await screen.findByRole('option', { name: /Johan Canonical/ })).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Kanonisk kandidat'), { target: { value: '42' } });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'samme ægtefælle og dato' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme person' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 42, 'samme ægtefælle og dato', null));
  });

  it.each(['different', 'unresolved'] as const)('sender %s uden kanonisk kandidat', async (action) => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'synligt kildegrundlag afkræfter match' } });
    fireEvent.click(screen.getByRole('button', { name: action === 'different' ? 'Forskellig' : 'Uafklaret' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, action, null, 'synligt kildegrundlag afkræfter match', null));
  });

  it('viser versionskonflikten fra den atomiske RPC', async () => {
    mocks.decide.mockRejectedValueOnce(new Error('EVIDENCE_IDENTITY_VERSION_CONFLICT'));
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    fireEvent.change(screen.getByLabelText('Kanonisk kandidat'), { target: { value: '42' } });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'samme ægtefælle og dato' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme person' }));
    expect((await screen.findByRole('alert')).textContent).toMatch(/EVIDENCE_IDENTITY_VERSION_CONFLICT/);
  });

  it('dubletreglen: filtrerer uafklarede dubletter og viser årsagen', async () => {
    mocks.queue.mockResolvedValue([{ ...row(), decisionStatus: 'accepted', version: 1, reason: 'duplicate_unresolved' }]);
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'duplicate_unresolved' } });
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('duplicate_unresolved', null, null, null));
    expect(await screen.findByText(/dublet uafklaret/)).toBeTruthy();
  });

  it('sender source-filter og cursor ved næste side', async () => {
    const firstPage = Array.from({ length: 50 }, (_, index) => row(index + 1));
    mocks.queue.mockImplementation((_status, sourceId, cursor) => Promise.resolve(
      cursor ? [row(51)] : sourceId === 7 ? firstPage : [row()],
    ));
    render(<KildepersonaKo role="redaktion" />);
    await screen.findByText('persona-1');
    fireEvent.change(screen.getByLabelText('Kilde-id'), { target: { value: '7' } });
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', 7, null, null));
    fireEvent.click(screen.getByRole('button', { name: 'Hent næste side' }));
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', 7, firstPage.at(-1)?.sourcePersonaId, null));
  });

  it('følger en kandidat med ét klik og sender kandidat-id', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByRole('button', { name: 'Samme som kandidat 1' });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'navn og år' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme som kandidat 1' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 42, 'navn og år', { candidateId: 'cand-1', runId: 'run-1' }));
  });

  it('søger en person, der ikke er kandidat, og vælger den uden kandidatspor', async () => {
    mocks.persons.mockResolvedValue([
      { id: '42', navn: 'Johan Canonical', aar: '1800', born: 1800, levende: false, privat: false, efternavnAfledt: false },
      { id: '77', navn: 'Anna Anden', aar: '1790', born: 1790, levende: false, privat: false, efternavnAfledt: false },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    fireEvent.change(await screen.findByLabelText('Søg person'), { target: { value: 'anna' } });
    fireEvent.change(screen.getByLabelText('Kanonisk kandidat'), { target: { value: '77' } });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'fundet ved søgning' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme person' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 77, 'fundet ved søgning', null));
    // (Kræver RedPerson-felter ud over disse, så tilføj dem med neutrale værdier — typen står i web/src/data/redaktionRead.ts:15.)
  });

  it('viser kollision uden at blokere', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText(/allerede accepteret for persona-9/)).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Samme som kandidat 1' }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('sender ny person nødvendig uden person', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'ikke i basen' } });
    fireEvent.click(screen.getByRole('button', { name: 'Ny person nødvendig' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'new_person_needed', null, 'ikke i basen', null));
  });

  it('viser historik med kandidat fulgt og ny person nødvendig', async () => {
    mocks.history.mockResolvedValue([
      { version: 2, decisionStatus: 'unresolved', canonicalPersonId: null, basis: 'human_sheet', candidateId: null, reason: 'new_person_needed', decidedByName: 'R', decidedAt: null },
      { version: 1, decisionStatus: 'accepted', canonicalPersonId: 42, basis: 'web_detail', candidateId: 'cand-1', reason: null, decidedByName: 'R', decidedAt: null },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText(/v1 · accepted · #42 · web_detail · kandidat fulgt/)).toBeTruthy();
    expect(screen.getByText(/v2 · unresolved · human_sheet · ny person nødvendig/)).toBeTruthy();
  });

  it('sorterer køen auto → review → none → ingen kandidat', async () => {
    mocks.queue.mockResolvedValue([
      { ...row(1), bestTier: null, reason: null }, { ...row(2), bestTier: 'none', reason: null },
      { ...row(3), bestTier: 'auto', reason: null }, { ...row(4), bestTier: 'review', reason: null },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    await screen.findByText('persona-3');
    const tekst = document.body.textContent ?? '';
    const pos = ['persona-3', 'persona-4', 'persona-2', 'persona-1'].map((k) => tekst.indexOf(k));
    expect(pos.every((p) => p >= 0)).toBe(true);
    expect(pos).toEqual([...pos].sort((a, b) => a - b));
  });

  it('viser kun den senest valgte personas detalje, selv om svarene kommer i omvendt rækkefølge', async () => {
    mocks.queue.mockResolvedValue([row(1), row(2)]);
    const venter: Record<string, (d: unknown) => void> = {};
    mocks.detail.mockImplementation((id: string) => new Promise((resolve) => { venter[id] = resolve; }));
    render(<KildepersonaKo role="redaktion" />);
    await screen.findByText('persona-2');
    const knapper = screen.getAllByRole('button', { name: 'Vis kildegrundlag' });
    fireEvent.click(knapper[0]);
    fireEvent.click(knapper[1]);
    await waitFor(() => expect(Object.keys(venter)).toHaveLength(2));
    await act(async () => { venter[row(2).sourcePersonaId]({ ...detail, persona: row(2) }); });
    await act(async () => { venter[row(1).sourcePersonaId]({ ...detail, persona: row(1) }); });
    expect(await screen.findByText(/Kildegrundlag for persona-2/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'navn og år' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme som kandidat 1' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row(2).sourcePersonaId, 0, 'same', 42, 'navn og år', { candidateId: 'cand-1', runId: 'run-1' }));
  });

  it('viser rollefilter og kandidatens titler, egen post og familie', async () => {
    mocks.queue.mockResolvedValue([{ ...row(1), mentionRole: 'spouse' }]);
    mocks.detail.mockResolvedValue({ persona: { ...row(1), mentionRole: 'spouse' }, mentions: [], placements: [], interpretations: [], collisions: [],
      familyContext: { principalRecordKey: 'IX-1', marriageOrdinal: 2 }, principalPartners: [], reviewReason: null,
      candidates: [{ candidateId: 'c', runId: 'r', rank: 1, score: 0.9, tier: 'review', personId: 5, personName: 'Mage', born: null, died: null,
                     signals: ['name'], titles: ['kammerherre'], ownPostKey: 'II-4', familyId: 30, ordinal: 2 }] });
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.change(await screen.findByLabelText('Rolle'), { target: { value: 'spouse' } });
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', null, null, 'spouse'));
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText(/ægtefælle nr\. 2 i IX-1/)).toBeTruthy();
    expect(await screen.findByText(/kammerherre · egen post II-4 · familie 30 nr\. 2/)).toBeTruthy();
  });

  it('2b-i: viser årsag og hovedpersonens partnere, og knappen sender partneren med familie-id i noten', async () => {
    mocks.detail.mockResolvedValue({ ...detail, candidates: [], collisions: [], reviewReason: 'partner_not_candidate',
      principalPartners: [{ personId: 10, familyId: 7, name: 'Bo Beta', born: '1801', died: null, ordinal: 1, konfidens: [] }] });
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText('Hovedpersonens partner er ikke blandt kandidaterne')).toBeTruthy();
    expect(screen.getByText('Hovedpersonens partnere i databasen')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Samme som denne partner' }));
    expect((await screen.findByRole('alert')).textContent).toMatch(/begrundelse/i);
    expect(mocks.decide).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'bogens ægtefælle er hovedpersonens partner' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme som denne partner' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 10,
      'bogens ægtefælle er hovedpersonens partner (partner i familie 7)', null));
  });

  it('2b-i: ingen partnerboks uden partnere', async () => {
    mocks.detail.mockResolvedValue({ ...detail, reviewReason: null, principalPartners: [] });
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    expect(screen.queryByText('Hovedpersonens partnere i databasen')).toBeNull();
  });
});
