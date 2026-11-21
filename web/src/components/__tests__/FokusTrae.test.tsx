// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { buildModel, type AppPerson } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { Model } from '../../data/types';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { FokusTrae } = await import('../FokusTrae');

const P = (id: string, name: string, koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, koen });
const boern = ['K1', 'K2', 'K3', 'K4', 'K5', 'K6', 'K7', 'K8'];
const model = buildModel({
  persons: [P('F', 'Joachim', 'mand'), P('A', 'Detlef'), P('I', 'Iwan', 'mand'), P('H', 'Hartwich'), P('E1', 'Anna von Ahlefeldt'),
    ...boern.map((k, i) => P(k, `Barn${i + 1}`))],
  unions: [{ id: 'u1', p1: 'I', p2: 'E1', p2_name: null, year: null }, { id: 'u2', p1: 'I', p2: null, p2_name: 'Margaretha uden id', year: null }],
  parentChild: [
    { child: 'A', parent: 'F', union: 'u0' }, { child: 'I', parent: 'F', union: 'u0' }, { child: 'H', parent: 'F', union: 'u0' },
    ...boern.map((k) => ({ child: k, parent: 'I', union: 'u1' })),
  ],
}) as unknown as Model;
model.indexes.konfByEdge = { 'K8|I': 'formodet' };

const vis = (o: Partial<Parameters<typeof FokusTrae>[0]> = {}) => {
  const p = { model, focusId: 'I', onPick: vi.fn(), onFocus: vi.fn(), hasBookmark: () => false, onToggleBookmark: vi.fn(), smal: false, ...o };
  return { ...render(<FokusTrae {...p} />), p };
};

it.each([false, true])('barnekort viser udgavemærket efter konfidensordet (smal: %s)', (smal) => {
  const nr = (sourceId: string) => ({ sourceId, linje: 'V', nr: 1, nrLabel: null, stamtavle: true });
  const m: Model = {
    ...model,
    bogNrBy: { I: [nr('20')], K1: [nr('10')], K2: [nr('10'), nr('20')] },
    udgaver: [
      { sourceId: '20', label: 'DAA 2018-20', aar: 2018 },
      { sourceId: '10', label: 'DAA 1939', aar: 1939 },
    ],
    indexes: { ...model.indexes, konfByEdge: { 'K1|I': 'formodet' } },
  };
  vis({ model: m, smal });
  const barn = screen.getByText('Barn1').closest('a')!;
  const maerke = within(barn).getByText('Kun i DAA 1939');
  expect(maerke.getAttribute('title')).toBe('Står i DAA 1939, men ikke i DAA 2018-20.');
  expect(within(barn).getByText('formodet').nextElementSibling).toBe(maerke);
  expect(within(screen.getByText('Barn2').closest('a')!).queryByText(/Kun i/)).toBeNull();
});

describe('FokusTrae (bred)', () => {
  it('hele søskendeflokken i én række; piletaster skifter person uden historik', () => {
    const { p } = vis();
    const flok = screen.getByRole('group', { name: /Søskendeflokken/ });
    expect(within(flok).getByText('Detlef').closest('a')?.getAttribute('href')).toBe('/person/A');
    expect(within(flok).getByText('Hartwich')).toBeTruthy();
    expect(screen.getByText('3 søskende')).toBeTruthy();
    fireEvent.keyDown(within(flok).getByText('Iwan'), { key: 'ArrowRight' });
    expect(p.onFocus).toHaveBeenCalledWith('H');
    fireEvent.keyDown(within(flok).getByText('Iwan'), { key: 'ArrowLeft' });
    expect(p.onFocus).toHaveBeenCalledWith('A');
    expect(p.onPick).not.toHaveBeenCalled();
  });

  it('mangler siges med ord; ægtefælle med id er et link, uden id ren tekst', () => {
    vis();
    expect(screen.getByText('Mor ikke angivet i bogen')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Anna von Ahlefeldt' }).getAttribute('href')).toBe('/person/E1');
    expect(screen.getByText(/Margaretha uden id/).closest('a')).toBeNull();
  });

  it('børn grupperet pr. ægteskab; usikkert barn har ordet og en stiplet kant; forklaring vises', () => {
    vis();
    expect(screen.getByText('8 børn')).toBeTruthy();
    expect(screen.getByText('Med Anna von Ahlefeldt')).toBeTruthy();
    const usikker = screen.getByText('Barn8').closest('a')!;
    expect(within(usikker).getByText('formodet')).toBeTruthy();
    expect(usikker.getAttribute('style')).toContain('dashed');
    expect(screen.getByText('formodet eller omstridt')).toBeTruthy();
  });

  it('bogmærket sidder i fokuskortet som knap', () => {
    const { p } = vis();
    fireEvent.click(screen.getByRole('button', { name: 'Bogmærk denne person' }));
    expect(p.onToggleBookmark).toHaveBeenCalledWith('I');
  });
});

describe('FokusTrae (smal, mobiltegningen)', () => {
  it('synlige pile mellem søskende med navn; skifter uden historik', () => {
    const { p } = vis({ smal: true });
    expect(screen.getByText(/Søskende 2 af 3/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Forrige søskende: Detlef' }));
    expect(p.onFocus).toHaveBeenCalledWith('A');
    fireEvent.click(screen.getByRole('button', { name: 'Næste søskende: Hartwich' }));
    expect(p.onFocus).toHaveBeenCalledWith('H');
    expect(screen.queryByRole('group', { name: /Søskendeflokken/ })).toBeNull();
  });

  it('fokuskortet har »Åbn personsiden«, forælderen står som »Far: …«', () => {
    vis({ smal: true });
    expect(screen.getByRole('link', { name: 'Åbn personsiden' }).getAttribute('href')).toBe('/person/I');
    expect(screen.getByRole('link', { name: /Far: Joachim/ }).getAttribute('href')).toBe('/person/F');
  });

  it('mange børn: de første fire, så »Vis alle«', () => {
    vis({ smal: true });
    expect(screen.queryByText('Barn5')).toBeNull();
    const knap = screen.getByRole('button', { name: 'Vis alle 8 børn' });
    expect(knap.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(knap);
    expect(screen.getByText('Barn8')).toBeTruthy();
  });
});
