// @vitest-environment jsdom
// Trin 5b 2a (spec §5.2) viste kildelinjer ved ægteskab, forældre og børn. Projektejeren 2026-11-21: Familie viser
// ingen kildelinjer (som fakta: kilden står nederst på siden). Testen holder fast i, at de ikke kommer tilbage.
import { render, screen } from '@testing-library/react';
import { buildModel, type AppPerson, type FamilieKilde } from '@daa/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PersonDetailData } from '../../data/public';
import type { Model } from '../../data/types';

let kilder: FamilieKilde[] = [];
const kald: string[][] = [];
vi.mock('../../router', () => ({ navigate: vi.fn() }));
vi.mock('../../data/familySources', () => ({
  fetchFamilySources: async (ids: string[]) => { kald.push(ids); return kilder; },
}));
const { PersonSide } = await import('../PersonSide');

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

// 6e-1: versionerne bærer v2-felterne (udgave og år), så vælgerens standard er den nyeste udgave (DAA Y).
const v2 = (sourceId: number, sourceYear: number, recordRef: string) =>
  ({ personId: 1, sourceId, sourceYear, recordOrder: null, sourceRecordRef: recordRef });
const detail: PersonDetailData = {
  bio: 'Ny tekst.', offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null,
  bioVersions: [
    { recordRef: 'r0', sourceLabel: 'DAA Y', recordLabel: 'Post 0', narrativeText: 'Ny tekst.', citationLabel: '', provenanceKind: 'source_record', ...v2(2, 2018, 'r0') },
    { recordRef: 'r1', sourceLabel: 'DAA X', recordLabel: 'Post 1', narrativeText: 'Gammel tekst.', citationLabel: '', provenanceKind: 'source_record', ...v2(1, 1939, 'r1') },
  ],
};
const kilde = (k: Partial<FamilieKilde>): FamilieKilde => ({
  familyId: '10', slags: 'aegteskab', counterpartPersonId: '2', sourceRecordRef: null,
  sourceLabel: 'DAA X', recordLabel: 'Post 1', citationLabel: '', ...k,
});
const vis = (m: Model = model) => render(
  <PersonSide model={m} focusId="1" detail={detail} detailError={null} onRetry={vi.fn()} onVisPerson={vi.fn()}
    onFindSlaegtskab={vi.fn()} onSlaegt={vi.fn()} loggetInd={false} onLogin={vi.fn()} erBogmaerket={false} onToggleBogmaerke={vi.fn()} />,
);

beforeEach(() => { kilder = []; kald.length = 0; });

describe('PersonSide — familiekilder', () => {
  it('Familie viser ingen kildelinjer ved ægtefælle, forældre eller børn', async () => {
    kilder = [
      kilde({ sourceRecordRef: 'r1' }),
      kilde({ familyId: '20', slags: 'foraelder', counterpartPersonId: '5', recordLabel: 'Post 2' }),
      kilde({ slags: 'boern', counterpartPersonId: '1', recordLabel: 'Post 8' }),
      kilde({ familyId: '20', slags: 'boern', counterpartPersonId: '5', recordLabel: 'Post 9' }),
    ];
    vis();
    await screen.findByRole('link', { name: 'Person 2' });
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByText(/Kilde: DAA X/)).toBeNull();
  });
});
