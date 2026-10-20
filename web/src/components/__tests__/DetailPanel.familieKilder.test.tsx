// @vitest-environment jsdom
// Trin 5b 2a (spec §5.2): kildelinje ved ægteskab og forældrelinje i detaljepanelet.
import { fireEvent, render, screen } from '@testing-library/react';
import { buildModel, type AppPerson, type FamilieKilde } from '@daa/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PersonDetailData } from '../../data/public';
import type { Model } from '../../data/types';

let kilder: FamilieKilde[] = [];
const kald: string[][] = [];
vi.mock('../../data/familySources', () => ({
  fetchFamilySources: async (ids: string[]) => { kald.push(ids); return kilder; },
}));
const { DetailPanel } = await import('../DetailPanel');

const person = (id: string): AppPerson => ({ id, name: `Person ${id}`, born: null, died: null, years: '', title: '', bio: '', privat: false });
const model = buildModel({
  persons: ['1', '2', '5', '6', '7'].map(person),
  unions: [
    { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
    { id: 'f20', p1: '5', p2: '6', p2_name: null, year: null },
  ],
  parentChild: [{ child: '1', parent: '5', union: 'f20' }, { child: '1', parent: '6', union: 'f20' },
    { child: '7', parent: '1', union: 'f10' }, { child: '7', parent: '2', union: 'f10' }],
}) as unknown as Model;

const detail: PersonDetailData = {
  bio: 'Ny tekst.', offices: [], estates: [], media: [], sources: [],
  bioVersions: [
    { recordRef: 'r0', sourceLabel: 'DAA Y', recordLabel: 'Post 0', narrativeText: 'Ny tekst.', citationLabel: '', provenanceKind: 'source_record' },
    { recordRef: 'r1', sourceLabel: 'DAA X', recordLabel: 'Post 1', narrativeText: 'Gammel tekst.', citationLabel: '', provenanceKind: 'source_record' },
  ],
};
const kilde = (k: Partial<FamilieKilde>): FamilieKilde => ({
  familyId: '10', slags: 'aegteskab', counterpartPersonId: '2', sourceRecordRef: null,
  sourceLabel: 'DAA X', recordLabel: 'Post 1', citationLabel: '', ...k,
});
const noop = () => {};
const vis = () => render(
  <DetailPanel model={model} focusId="1" detail={detail} onPick={noop} backName={null} onBack={noop}
    onFocusTree={noop} onRelate={noop} isMe={false} onToggleMe={noop} isBookmarked={false} onToggleBookmark={noop} geoLoading={false} />,
);

beforeEach(() => { kilder = []; kald.length = 0; });

describe('DetailPanel — familiekilder', () => {
  it('viser ægteskabskilden som knap til egen post og forælderkilden kun ved den rette forælder', async () => {
    kilder = [
      kilde({ sourceRecordRef: 'r1' }),
      kilde({ familyId: '20', slags: 'foraelder', counterpartPersonId: '5', sourceRecordRef: 'r9', recordLabel: 'Post 2' }),
    ];
    vis();
    const knap = await screen.findByRole('button', { name: 'Kilde: DAA X · Post 1' });
    expect(kald[0].sort()).toEqual(['10', '20']);
    // forælderkilden: ren tekst (r9 er ikke en af personens egne versioner), præcis én gang (kun ved forælder 5)
    expect(screen.getAllByText('Kilde: DAA X · Post 2')).toHaveLength(1);
    expect(screen.queryByRole('button', { name: 'Kilde: DAA X · Post 2' })).toBeNull();
    const forælder5 = screen.getByText('Person 5 ›').closest('span');
    expect(forælder5?.textContent).toContain('Kilde: DAA X · Post 2');
    const forælder6 = screen.getByText('Person 6 ›').closest('span');
    expect(forælder6?.textContent).not.toContain('Kilde:');
    // klik vælger personens egen version (versionsvælgeren skifter til den ældre udgave)
    expect(screen.queryByText('Tidligere udgave')).toBeNull();
    fireEvent.click(knap);
    expect(screen.getByText('Tidligere udgave')).toBeTruthy();
  });
  // Trin 5b 2b-iii (spec §8): børneflokkens kilde — hos forælderen under »Børn«, hos barnet ved den forælder,
  // påstanden står hos (ikke ved den anden forælder); en ukendt slags springes over i datalaget.
  it('viser børnekilden under Børn hos forælderen', async () => {
    kilder = [kilde({ slags: 'boern', counterpartPersonId: '1', recordLabel: 'Post 8' })];
    vis();
    await screen.findByText('Kilde: DAA X · Post 8');
    expect(screen.getAllByText('Kilde: DAA X · Post 8')).toHaveLength(1);
    const børn = screen.getByText('Børn');
    expect(børn.compareDocumentPosition(screen.getByText('Kilde: DAA X · Post 8')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(kald[0].sort()).toEqual(['10', '20']);
  });
  it('viser børnekilden hos barnet kun ved den forælder, der er modpart', async () => {
    kilder = [kilde({ familyId: '20', slags: 'boern', counterpartPersonId: '5', recordLabel: 'Post 9' })];
    vis();
    await screen.findByText('Kilde: DAA X · Post 9');
    expect(screen.getAllByText('Kilde: DAA X · Post 9')).toHaveLength(1);
    expect(screen.getByText('Person 5 ›').closest('span')?.textContent).toContain('Kilde: DAA X · Post 9');
    expect(screen.getByText('Person 6 ›').closest('span')?.textContent).not.toContain('Kilde:');
  });
  it('viser ingen kildelinje uden kilder', async () => {
    vis();
    await screen.findByText('Person 2 ›');
    await Promise.resolve();
    expect(screen.queryByText(/Kilde:/)).toBeNull();
  });
  it('viser ikke en ægteskabskilde, hvis modparten ikke er ægtefællen eller personen selv', async () => {
    kilder = [kilde({ counterpartPersonId: '99', recordLabel: 'Post 7' })];
    vis();
    await screen.findByText('Person 2 ›');
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByText('Kilde: DAA X · Post 7')).toBeNull();
  });
});
