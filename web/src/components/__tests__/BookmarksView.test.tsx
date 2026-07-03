// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { BookmarksView } from '../BookmarksView';
import type { Model, ModelPerson } from '../../data/types';

function person(id: string, name: string): ModelPerson {
  return { id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, parentId: null, spouse: '' };
}

function makeModel(persons: ModelPerson[]): Model {
  return {
    persons,
    byId: Object.fromEntries(persons.map((p) => [p.id, p])),
    indexes: { spousesBy: {}, childIdx: {}, parentsByChild: {}, childrenByUnion: {}, unionById: {}, konfByEdge: {} },
    lineage: { byPerson: {}, list: [], navn: {} },
  };
}

describe('BookmarksView', () => {
  it('viser tom-tilstand når ingen bogmærker', () => {
    render(<BookmarksView model={makeModel([])} ids={[]} sort="linje" setSort={vi.fn()} onPick={vi.fn()} onRemove={vi.fn()} />);
    expect(screen.getByText(/Ingen bogmærker endnu/)).toBeTruthy();
  });

  it('renderer grupper og rækker fra buildBookmarkList', () => {
    const model = makeModel([person('1', 'Anders Reventlow'), person('2', 'Bertha Reventlow')]);
    render(<BookmarksView model={model} ids={['1', '2']} sort="navn" setSort={vi.fn()} onPick={vi.fn()} onRemove={vi.fn()} />);
    expect(screen.getByText('Anders Reventlow')).toBeTruthy();
    expect(screen.getByText('Bertha Reventlow')).toBeTruthy();
  });

  it('klik på række kalder onPick med person-id', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    const onPick = vi.fn();
    render(<BookmarksView model={model} ids={['1']} sort="navn" setSort={vi.fn()} onPick={onPick} onRemove={vi.fn()} />);
    fireEvent.click(screen.getByText('Anders Reventlow'));
    expect(onPick).toHaveBeenCalledWith('1');
  });

  it('fjern-knap kalder onRemove uden også at kalde onPick', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    const onPick = vi.fn();
    const onRemove = vi.fn();
    render(<BookmarksView model={model} ids={['1']} sort="navn" setSort={vi.fn()} onPick={onPick} onRemove={onRemove} />);
    fireEvent.click(screen.getByTitle('Fjern bogmærke'));
    expect(onRemove).toHaveBeenCalledWith('1');
    expect(onPick).not.toHaveBeenCalled();
  });

  it('sortér-segment kalder setSort', () => {
    const setSort = vi.fn();
    render(<BookmarksView model={makeModel([])} ids={[]} sort="linje" setSort={setSort} onPick={vi.fn()} onRemove={vi.fn()} />);
    fireEvent.click(screen.getByText('A–Å'));
    expect(setSort).toHaveBeenCalledWith('navn');
  });

  it('viser antal-label matchende antal fundne personer', () => {
    const model = makeModel([person('1', 'Anders Reventlow')]);
    render(<BookmarksView model={model} ids={['1', '999']} sort="navn" setSort={vi.fn()} onPick={vi.fn()} onRemove={vi.fn()} />);
    expect(screen.getByText(/1/).textContent).toMatch(/1/);
  });
});
