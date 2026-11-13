// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { buildModel, type AppPerson } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { Model } from '../../data/types';
import { STANDARD_FILTRE, type SoegFiltre } from '../../data/soeg';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { SoegView } = await import('../SoegView');

const P = (id: string, name: string, born: number | null = null, died: number | null = null): AppPerson =>
  ({ id, name, born, died, years: born ? `${born}–${died ?? ''}` : '', title: '', bio: '', privat: false, koen: null });
const mange = Array.from({ length: 30 }, (_, i) => P(`m${i}`, `Hans Reventlow ${String(i).padStart(2, '0')}`, 1700 + i, 1760 + i));
const model = buildModel({
  persons: [P('1', 'Greve Conrad de Reventlow', 1640, 1708), P('2', 'Conradina Reventlow'), P('3', 'Adelheid de Reventlou', 1909, 1981), ...mange],
  unions: [], parentChild: [],
}) as unknown as Model;
model.lineage = { byPerson: { 1: ['L5'] }, list: [], navn: { L5: 'V. linje' } } as never;
const estates = [{ id: 'e1', navn: 'Conradsborg', slags: 'gods', ownerCount: 2 }];
const linjer = [{ linje: 'L5', count: 1, headId: null, navn: 'V. linje' }];

const vis = (f: Partial<SoegFiltre> = {}, o: Partial<Parameters<typeof SoegView>[0]> = {}) => {
  const p = { model, estates, filtre: { ...STANDARD_FILTRE, ...f }, linjer, bogmaerker: null, onFiltre: vi.fn(), ...o };
  return { ...render(<SoegView {...p} />), p };
};

describe('SoegView', () => {
  it('fremhæver søgeordet; godser og personer; linjens navn', () => {
    vis({ q: 'Conrad' });
    const res = screen.getByRole('region', { name: 'Resultater' });
    expect(within(res).getByRole('status').textContent).toBe('2 personer · 1 gods');
    const conrad = within(res).getByRole('link', { name: /Greve Conrad de Reventlow/ });
    expect(conrad.getAttribute('href')).toBe('/person/1');
    expect(within(conrad).getByText('Conrad', { selector: 'mark' })).toBeTruthy();
    expect(within(conrad).getByText('V. linje')).toBeTruthy();
    expect(within(res).getByRole('link', { name: /Conradsborg/ }).getAttribute('href')).toBe('/gods/e1');
  });

  it('filtre skrives i adressen', () => {
    const { p } = vis({ q: 'Conrad' });
    fireEvent.click(screen.getByRole('radio', { name: 'Personer (2)' }));
    expect(p.onFiltre).toHaveBeenLastCalledWith('/soeg?q=Conrad&type=personer');
    fireEvent.click(screen.getByRole('button', { name: 'V. linje' }));
    expect(p.onFiltre).toHaveBeenLastCalledWith('/soeg?q=Conrad&linje=L5');
    fireEvent.change(screen.getByLabelText('Fra år'), { target: { value: '1700' } });
    expect(p.onFiltre).toHaveBeenLastCalledWith('/soeg?q=Conrad&fra=1700');
    fireEvent.change(screen.getByRole('combobox', { name: 'Sortér' }), { target: { value: 'foedt' } });
    expect(p.onFiltre).toHaveBeenLastCalledWith('/soeg?q=Conrad&sort=foedt');
  });

  it('aktiv linje er trykket ned; levetid tæller personer uden årstal for sig', () => {
    vis({ q: 'Conrad', linje: 'L5', fra: 1600, til: 1700 });
    expect(screen.getByRole('button', { name: 'V. linje' }).getAttribute('aria-pressed')).toBe('true');
    expect(screen.getByRole('status').textContent).toBe('1 person');
    vis({ q: 'Conradina', fra: 1600, til: 1700 });
    expect(screen.getByText(/1 uden årstal er ikke med/)).toBeTruthy();
  });

  it('ingen træffere: »Mente du …?« med link til den rettede søgning', () => {
    vis({ q: 'Revenlow' });
    expect(screen.getByRole('heading', { name: 'Ingen hedder »Revenlow«' })).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Reventlow' }).getAttribute('href')).toBe('/soeg?q=Reventlow');
  });

  it('med træffere: andre stavemåder med antal (Reventlow ↔ Reventlou)', () => {
    vis({ q: 'Reventlow' });
    expect(screen.getByText(/Andre stavemåder/)).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Reventlou (1)' }).getAttribute('href')).toBe('/soeg?q=Reventlou');
  });

  it('uden søgeord: alle personer, 25 ad gangen', () => {
    vis();
    const liste = () => within(screen.getByRole('region', { name: 'Resultater' })).getAllByRole('listitem');
    expect(liste()).toHaveLength(25 + 1); // 25 personer + 1 gods
    fireEvent.click(screen.getByRole('button', { name: 'Vis 8 mere (af 8)' }));
    expect(liste()).toHaveLength(33 + 1);
  });

  it('bogmærkefilter kun, når der er bogmærker', () => {
    vis({ q: 'Conrad' });
    expect(screen.queryByRole('checkbox', { name: 'Kun bogmærkede' })).toBeNull();
    const { p } = vis({ q: 'Conrad' }, { bogmaerker: new Set(['1']) });
    fireEvent.click(screen.getByRole('checkbox', { name: 'Kun bogmærkede' }));
    expect(p.onFiltre).toHaveBeenLastCalledWith('/soeg?q=Conrad&bm=1');
  });
});
