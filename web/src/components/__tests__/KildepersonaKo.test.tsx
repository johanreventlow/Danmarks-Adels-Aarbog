// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  decide: vi.fn(),
  detail: vi.fn(),
  queue: vi.fn(),
  persons: vi.fn(),
}));

vi.mock('../../data/sourcePersona', () => ({
  decideSourcePersona: mocks.decide,
  fetchSourcePersonaDetail: mocks.detail,
  fetchSourcePersonaQueue: mocks.queue,
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
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.queue.mockResolvedValue([row()]);
  mocks.detail.mockResolvedValue(detail);
  mocks.persons.mockResolvedValue([{ id: '42', navn: 'Johan Canonical', aar: '1800–1860', born: 1800, levende: false, privat: false, efternavnAfledt: false }]);
  mocks.decide.mockResolvedValue(1);
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
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 42, 'samme ægtefælle og dato'));
  });

  it.each(['different', 'unresolved'] as const)('sender %s uden kanonisk kandidat', async (action) => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'synligt kildegrundlag afkræfter match' } });
    fireEvent.click(screen.getByRole('button', { name: action === 'different' ? 'Forskellig' : 'Uafklaret' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, action, null, 'synligt kildegrundlag afkræfter match'));
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

  it('sender source-filter og cursor ved næste side', async () => {
    const firstPage = Array.from({ length: 50 }, (_, index) => row(index + 1));
    mocks.queue.mockImplementation((_status, sourceId, cursor) => Promise.resolve(
      cursor ? [row(51)] : sourceId === 7 ? firstPage : [row()],
    ));
    render(<KildepersonaKo role="redaktion" />);
    await screen.findByText('persona-1');
    fireEvent.change(screen.getByLabelText('Kilde-id'), { target: { value: '7' } });
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', 7, null));
    fireEvent.click(screen.getByRole('button', { name: 'Hent næste side' }));
    await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', 7, firstPage.at(-1)?.sourcePersonaId));
  });
});
