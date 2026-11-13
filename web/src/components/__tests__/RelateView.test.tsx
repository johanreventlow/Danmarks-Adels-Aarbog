// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { buildModel, type AppPerson } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { Model } from '../../data/types';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { RelateView } = await import('../RelateView');

const P = (id: string, name: string, years = '', koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name, born: null, died: null, years, title: '', bio: '', privat: false, koen });
// 1 → 2 → 3 → 4 (formodet sidste led). 5 og 6 er fætre ad to anepar (to veje). 9 står alene.
const model = buildModel({
  persons: [P('1', 'Otto Reventlow', '1634', 'mand'), P('2', 'Otto Reventlow', 'ca. 1660–1700', 'mand'),
    P('3', 'Friedrich Reventlow', '', 'mand'), P('4', 'Magdalena Sophia Reventlow', '1745', 'kvinde'),
    P('9', 'Hans Holck')],
  unions: [],
  parentChild: [{ child: '2', parent: '1', union: 'u1' }, { child: '3', parent: '2', union: 'u2' }, { child: '4', parent: '3', union: 'u3' }],
}) as unknown as Model;
model.indexes.konfByEdge = { '4|3': 'formodet' };

const vis = (o: Partial<Parameters<typeof RelateView>[0]> = {}) => {
  const p = { model, relA: null, relB: null, meId: null, slug: 'reventlow', onVaelg: vi.fn(), ...o };
  return { ...render(<RelateView {...p} />), p };
};

describe('RelateView', () => {
  it('uden valg: to navngivne felter og en forklaring', () => {
    vis();
    expect(screen.getByRole('combobox', { name: 'Første person' })).toBeTruthy();
    expect(screen.getByRole('combobox', { name: 'Anden person' })).toBeTruthy();
    expect(screen.getByText(/Vælg to personer/)).toBeTruthy();
  });

  it('personvælgeren: skriv, piletast, Enter vælger og bevarer den anden plads', () => {
    const { p } = vis({ relB: '4' });
    const felt = screen.getByRole('combobox', { name: 'Første person' });
    fireEvent.change(felt, { target: { value: 'otto' } });
    const liste = screen.getByRole('listbox', { name: /første person/ });
    expect(within(liste).getAllByRole('option').map((o) => o.textContent)).toEqual(['Otto Reventlow1634', 'Otto Reventlowca. 1660–1700']);
    fireEvent.keyDown(felt, { key: 'ArrowDown' });
    expect(felt.getAttribute('aria-activedescendant')).toBe(within(liste).getAllByRole('option')[1].id);
    fireEvent.keyDown(felt, { key: 'Enter' });
    expect(p.onVaelg).toHaveBeenCalledWith('2', '4');
  });

  it('ingen forslag siges med ord', () => {
    vis();
    fireEvent.change(screen.getByRole('combobox', { name: 'Anden person' }), { target: { value: 'xyz' } });
    expect(screen.getByText('Ingen i Aarbogen hedder »xyz«')).toBeTruthy();
  });

  it('byt om sender pladserne omvendt', () => {
    const { p } = vis({ relA: '1', relB: '4' });
    fireEvent.click(screen.getByRole('button', { name: 'Byt om på de to personer' }));
    expect(p.onVaelg).toHaveBeenCalledWith('4', '1');
  });

  it('resultat: etiket, fælles ane, slægtled; usikkert led med ordet, stiplet streg og »sandsynligvis«', () => {
    vis({ relA: '1', relB: '4' });
    const res = screen.getByRole('region', { name: 'Resultat' });
    expect(within(res).getByRole('heading', { level: 2 }).textContent).toBe('SandsynligvisOldefar & oldebarn');
    expect(within(res).getByText(/Fælles ane: Otto Reventlow\. Tre slægtled\./)).toBeTruthy();
    const vej = within(res).getByRole('list', { name: 'Vejen, trin for trin' });
    const trin = within(vej).getAllByRole('link');
    expect(trin.map((a) => a.getAttribute('href'))).toEqual(['/person/1', '/person/2', '/person/3', '/person/4']);
    expect(trin[0].textContent).toContain('Fælles ane · Første person');
    expect(trin[3].textContent).toContain('Anden person');
    const led = within(vej).getByText('formodet led');
    expect((led.previousElementSibling as HTMLElement).style.borderLeft).toContain('dashed');
    expect(within(res).getByRole('link', { name: 'Vis fælles ane i stamtræet' }).getAttribute('href')).toBe('/slaegt/reventlow/stamtrae?fokus=1');
  });

  it('kopiér link lægger den delbare adresse i udklipsholderen', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    vis({ relA: '1', relB: '4' });
    fireEvent.click(screen.getByRole('button', { name: 'Kopiér link til resultatet' }));
    expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/slaegtskab?a=1&b=4`);
    expect(await screen.findByText('Linket er kopieret.')).toBeTruthy();
  });

  it('ingen fælles ane: »Aarbogen viser ingen forbindelse«, ikke »ikke i familie«', () => {
    vis({ relA: '1', relB: '9' });
    expect(screen.getByRole('heading', { name: 'Aarbogen viser ingen forbindelse' })).toBeTruthy();
  });

  it('ukendt id i linket: siges ved feltet, intet resultat', () => {
    vis({ relA: '1', relB: '999' });
    expect(screen.getByText(/Personen i linket findes ikke i Aarbogen/)).toBeTruthy();
    expect(screen.queryByRole('region', { name: 'Resultat' })).toBeNull();
  });

  it('»Det er mig« sætter mig som første person', () => {
    const { p } = vis({ meId: '9', relB: '4' });
    fireEvent.click(screen.getByRole('button', { name: /Brug »Det er mig« \(Hans Holck\)/ }));
    expect(p.onVaelg).toHaveBeenCalledWith('9', '4');
  });
});

describe('RelateView — flere veje', () => {
  // Dobbelt fætterskab ad to forskellige afstande: A og B deler bedsteforælder G1 (fætre) og oldeforælder G0
  // ad en anden gren (2. grads) → to linjer med forskellig etiket.
  const m = buildModel({
    persons: ['A', 'B', 'pa', 'pb', 'G1', 'G0', 'x', 'y', 'qa', 'qb'].map((id) => P(id, `Person ${id}`)),
    unions: [],
    parentChild: [
      { child: 'A', parent: 'pa', union: 'a' }, { child: 'B', parent: 'pb', union: 'b' },
      { child: 'pa', parent: 'G1', union: 'g' }, { child: 'pb', parent: 'G1', union: 'g' },
      { child: 'A', parent: 'qa', union: 'a' }, { child: 'B', parent: 'qb', union: 'b' },
      { child: 'qa', parent: 'x', union: 'x' }, { child: 'qb', parent: 'y', union: 'y' },
      { child: 'x', parent: 'G0', union: 'h' }, { child: 'y', parent: 'G0', union: 'h' },
    ],
  }) as unknown as Model;

  it('»Vej 1 af 2«; næste vej skifter etiket og trin', () => {
    vis({ model: m, relA: 'A', relB: 'B' });
    expect(screen.getByText(/Vej 1 af 2/)).toBeTruthy();
    const h = () => screen.getByRole('heading', { level: 2 }).textContent;
    const foer = h();
    fireEvent.click(screen.getByRole('button', { name: 'Næste vej ›' }));
    expect(screen.getByText('Vej 2 af 2')).toBeTruthy();
    expect(h()).not.toBe(foer);
    expect(screen.getByRole('button', { name: 'Næste vej ›' })).toHaveProperty('disabled', true);
  });
});
