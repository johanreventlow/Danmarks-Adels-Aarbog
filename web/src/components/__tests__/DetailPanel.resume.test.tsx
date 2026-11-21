// @vitest-environment jsdom
// Fase 5b: stamtræets panel er en genvej — resumé, »Åbn personsiden«, »Find slægtskab med …«.
import { fireEvent, render, screen } from '@testing-library/react';
import { buildModel, type AppPerson } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { PersonDetailData } from '../../data/public';
import type { Model } from '../../data/types';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { DetailPanel, godsResume } = await import('../DetailPanel');

const person = (id: string, name: string, o: Partial<AppPerson> = {}): AppPerson =>
  ({ id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o });
const model = {
  ...buildModel({ persons: [person('60', 'Iwan Reventlow', { years: 'ca. 1484 – ca. 25. okt. 1569', title: 'Amtmand' })], unions: [], parentChild: [] }),
  lineage: { byPerson: { '60': ['ctx:I'] }, list: [], navn: { 'ctx:I': 'I. linje' } },
  sourcesBy: { '60': [{ ref: 'Linje I, nr. 60', work: 'Danmarks Adels Aarbog' }] },
} as unknown as Model;
const detail: PersonDetailData = {
  bio: 'Lang biografi, der ikke hører hjemme i panelet.', bioVersions: [], offices: [{ label: 'amtmand', period: '1530' }],
  estates: ['Rixdorf', 'Schönweide', 'Stocksee', 'Bramstedt', 'Neuhaus'].map((navn, i) => ({ id: `e${i}`, navn, personId: '60' })),
  media: [], sources: [], facts: [], factsError: false, faktaInput: null,
};
const vis = (o: Partial<Parameters<typeof DetailPanel>[0]> = {}) => render(
  <DetailPanel model={model} focusId="60" detail={detail} backName={null} onBack={vi.fn()} onRelate={vi.fn()} {...o} />,
);

describe('DetailPanel (genvej)', () => {
  it('viser resuméet og ikke personsidens indhold', () => {
    vis();
    expect(screen.getByRole('heading', { level: 2, name: 'Iwan Reventlow' })).toBeTruthy();
    expect(screen.getByText('Reventlow · Linje I, nr. 60')).toBeTruthy();
    expect(screen.getByText('ca. 1484 – ca. 25. okt. 1569')).toBeTruthy();
    expect(screen.getByText('Amtmand. Besiddelser: Rixdorf, Schönweide, Stocksee og 2 flere.')).toBeTruthy();
    expect(screen.queryByText(/Lang biografi/)).toBeNull();
    expect(screen.queryByText('amtmand')).toBeNull();
    expect(screen.queryByText('Det er mig')).toBeNull();
    expect(screen.queryByText(/præsensliste/i)).toBeNull();
  });

  it('»Åbn personsiden« og »Find slægtskab« er links', () => {
    const onRelate = vi.fn();
    vis({ onRelate });
    expect(screen.getByRole('link', { name: 'Åbn personsiden' }).getAttribute('href')).toBe('/person/60');
    const find = screen.getByRole('link', { name: 'Find slægtskab' });
    expect(find.getAttribute('href')).toBe('/slaegtskab?a=60');
    fireEvent.click(find);
    expect(onRelate).toHaveBeenCalled();
  });

  it('Luk og Tilbage er knapper; panelet har ingen »Vis i stamtræet« (det står kun i træet)', () => {
    const onClose = vi.fn(); const onBack = vi.fn();
    const { unmount } = vis({ onClose, backName: 'Detlef', onBack });
    fireEvent.click(screen.getByRole('button', { name: 'Luk' }));
    fireEvent.click(screen.getByRole('button', { name: '‹ Tilbage til Detlef' }));
    expect(onClose).toHaveBeenCalled();
    expect(onBack).toHaveBeenCalled();
    expect(screen.queryByText('Vis i stamtræet')).toBeNull();
    unmount();
  });

  it('floruit vises som Nævnes', () => {
    vis({ model: { ...model, byId: { '60': { ...model.byId['60'], years: 'Nævnes 1349–1391' } } } as Model, detail: null });
    expect(screen.getByText('Nævnes 1349–1391')).toBeTruthy();
  });

  it('uden år vises ingen årslinje, og der hentes, før detaljen er kommet', () => {
    vis({ model: { ...model, byId: { '60': { ...model.byId['60'], years: '', title: '' } } } as Model, detail: null });
    expect(screen.queryByText(/Livsdatoer ikke angivet/)).toBeNull();
    expect(screen.getByRole('status').textContent).toBe('Henter …');
  });
});

describe('godsResume', () => {
  it('ét, to, tre og flere besiddelser', () => {
    expect(godsResume([])).toBe('');
    expect(godsResume(['A'])).toBe('Besiddelse: A.');
    expect(godsResume(['A', 'B'])).toBe('Besiddelser: A og B.');
    expect(godsResume(['A', 'B', 'C'])).toBe('Besiddelser: A, B og C.');
    expect(godsResume(['A', 'B', 'C', 'D'])).toBe('Besiddelser: A, B, C og 1 mere.');
  });
});
