// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { buildModel, type AppPerson } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { Model } from '../../data/types';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const smal = vi.hoisted(() => ({ v: false }));
vi.mock('../../useSmalSkaerm', () => ({ useSmalSkaerm: () => smal.v }));
const { RelateView } = await import('../RelateView');

const P = (id: string, name: string, years = '', koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name, born: null, died: null, years, title: '', bio: '', privat: false, koen });
// 1 → 2 → 3 → 4 (formodet sidste led). 5 og 6 er fætre ad to anepar (to veje). 9 står alene.
const model = buildModel({
  persons: [P('1', 'Otto Reventlow', '1634', 'mand'), P('2', 'Otto Reventlow', 'ca. 1660–1700', 'mand'),
    P('3', 'Friedrich Reventlow', '', 'mand'), P('4', 'Magdalena Sophia Reventlow', '1745', 'kvinde'),
    P('9', 'Hans Holck'), P('8', 'Niels Brahe', 'Nævnes 1349–1391')],
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

  it('forslag: floruit vises som Nævnes, og uden år står kun navnet (ingen »Livsdatoer ikke angivet«)', () => {
    vis();
    const felt = screen.getByRole('combobox', { name: 'Første person' });
    fireEvent.change(felt, { target: { value: 'brahe' } });
    expect(within(screen.getByRole('listbox', { name: /første person/ })).getAllByRole('option').map((o) => o.textContent)).toEqual(['Niels BraheNævnes 1349–1391']);
    fireEvent.change(felt, { target: { value: 'friedrich' } });
    expect(within(screen.getByRole('listbox', { name: /første person/ })).getAllByRole('option').map((o) => o.textContent)).toEqual(['Friedrich Reventlow']);
    expect(screen.queryByText(/Livsdatoer ikke angivet/)).toBeNull();
  });

  it('resultat: trin uden år har intet årsspan', () => {
    vis({ relA: '1', relB: '4' });
    const trin = within(screen.getByRole('list', { name: 'Vejen, trin for trin' })).getAllByRole('link');
    expect(trin[2].textContent).not.toContain('Livsdatoer');
    const aarSpans = (el: Element) => Array.from(el.querySelectorAll('span')).filter((s) => s.style.fontFamily.includes('monospace') && s.style.fontSize === '12px');
    expect(aarSpans(trin[1]).length).toBe(1);
    expect(aarSpans(trin[2])).toHaveLength(0);
    expect(screen.queryByText(/Livsdatoer ikke angivet/)).toBeNull();
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

  it('rigtige tastetryk i et udfyldt felt søger på det nye, ikke på »Navn (leveår)« + det nye', async () => {
    const bruger = userEvent.setup();
    vis({ relA: '1', relB: '4' });
    const felt = screen.getByRole('combobox', { name: 'Første person' }) as HTMLInputElement;
    expect(felt.value).toBe('Otto Reventlow (1634)');
    await bruger.click(felt);
    await bruger.keyboard('Hans');
    expect(felt.value).toBe('Hans');
    expect(within(screen.getByRole('listbox', { name: /første person/ })).getByRole('option').textContent).toContain('Hans Holck');
    // Markøren efter navnet (markeringen ophævet): kun det nye tæller.
    await bruger.keyboard('{Escape}');
    felt.setSelectionRange(felt.value.length, felt.value.length);
    await bruger.type(felt, 'X', { initialSelectionStart: felt.value.length, initialSelectionEnd: felt.value.length, skipClick: true });
    expect(felt.value).toBe('X');
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
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    vis({ relA: '1', relB: '4' });
    fireEvent.click(screen.getByRole('button', { name: 'Kopiér link til resultatet' }));
    expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/slaegtskab?a=1&b=4`);
    expect(await screen.findByText('Linket er kopieret.')).toBeTruthy();
  });

  it('smal skærm: feltet viser kun navnet; leveårene står under feltet og beskriver det', () => {
    smal.v = true;
    try {
      vis({ relA: '2', relB: '4' });
      const felt = screen.getByRole('combobox', { name: 'Første person' }) as HTMLInputElement;
      expect(felt.value).toBe('Otto Reventlow');
      const beskrevet = felt.getAttribute('aria-describedby');
      expect(beskrevet && document.getElementById(beskrevet)?.textContent).toBe('ca. 1660–1700');
      expect((screen.getByRole('combobox', { name: 'Anden person' }) as HTMLInputElement).value).toBe('Magdalena Sophia Reventlow');
    } finally { smal.v = false; }
  });

  it('bred skærm: feltet viser »Navn (leveår)« som før', () => {
    vis({ relA: '2', relB: '4' });
    expect((screen.getByRole('combobox', { name: 'Første person' }) as HTMLInputElement).value).toBe('Otto Reventlow (ca. 1660–1700)');
  });

  it('smal skærm: »Del resultatet« deler den delbare adresse med telefonens delemenu', async () => {
    smal.v = true;
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'share', { value: share, configurable: true, writable: true });
    try {
      vis({ relA: '1', relB: '4' });
      expect(screen.queryByRole('button', { name: 'Kopiér link til resultatet' })).toBeNull();
      fireEvent.click(screen.getByRole('button', { name: 'Del resultatet' }));
      await vi.waitFor(() => expect(share).toHaveBeenCalledTimes(1));
      expect(share.mock.calls[0][0].url).toBe(`${window.location.origin}/slaegtskab?a=1&b=4`);
    } finally {
      smal.v = false;
      Object.defineProperty(navigator, 'share', { value: undefined, configurable: true, writable: true });
    }
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

  it('omstridt led: »Omstridt«, ikke »Sandsynligvis«', () => {
    const m = { ...model, indexes: { ...model.indexes, konfByEdge: { '4|3': 'omstridt' } } } as Model;
    vis({ model: m, relA: '1', relB: '4' });
    expect(screen.getByRole('heading', { level: 2 }).textContent).toBe('OmstridtOldefar & oldebarn');
    expect(screen.getByText(/kilderne er uenige/)).toBeTruthy();
    expect(screen.getByText('omstridt led')).toBeTruthy();
  });

  it('smal skærm: »Det er mig« er første person uden valg i adressen, men overstyrer aldrig et delt link', () => {
    smal.v = true;
    try {
      const { unmount } = vis({ meId: '9' });
      expect((screen.getByRole('combobox', { name: 'Første person' }) as HTMLInputElement).value).toBe('Hans Holck');
      unmount();
      vis({ meId: '9', relB: '4' });
      expect((screen.getByRole('combobox', { name: 'Første person' }) as HTMLInputElement).value).toBe('');
    } finally { smal.v = false; }
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

  it.each([null, undefined, 'sikker'] as const)('en usikker vej 2 bekræftes af en uangivet/sikker (%s) vej 1', (k) => {
    const konfByEdge = Object.fromEntries([
      ['A|pa', k], ['B|pb', k], ['pa|G1', k], ['pb|G1', k],
      ['qa|x', 'formodet'],
    ]);
    const mu = { ...m, indexes: { ...m.indexes, konfByEdge } } as Model;
    vis({ model: mu, relA: 'A', relB: 'B' });
    expect(screen.queryByText(/Bekræftet ad en anden, sikker linje/)).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Næste vej ›' }));
    expect(screen.getByRole('heading', { level: 2 }).textContent).toMatch(/^Sandsynligvis/);
    expect(screen.getByText(/Bekræftet ad en anden, sikker linje/)).toBeTruthy();
  });

  it.each(['sandsynlig', 'formodet', 'omstridt'] as const)('en %s vej 1 bekræfter ikke den usikre vej 2', (k) => {
    const mu = { ...m, indexes: { ...m.indexes, konfByEdge: {
      'A|pa': k, 'B|pb': 'sikker', 'pa|G1': 'sikker', 'pb|G1': 'sikker', 'qa|x': 'formodet',
    } } } as Model;
    vis({ model: mu, relA: 'A', relB: 'B' });
    fireEvent.click(screen.getByRole('button', { name: 'Næste vej ›' }));
    expect(screen.getByRole('heading', { level: 2 }).textContent).toMatch(/^Sandsynligvis/);
    expect(screen.queryByText(/Bekræftet ad/)).toBeNull();
  });

  it('et sandsynligt led vises som sandsynligt, med ordet ved selve leddet', () => {
    const mu = { ...m, indexes: { ...m.indexes, konfByEdge: { 'A|pa': 'sandsynlig' } } } as Model;
    vis({ model: mu, relA: 'A', relB: 'B' });
    expect(screen.getByRole('heading', { level: 2 }).textContent).toMatch(/^Sandsynligvis/);
    expect(screen.getByText('sandsynligt led')).toBeTruthy();
    expect(screen.queryByText(/Vejen går gennem et formodet led/)).toBeNull();
  });
});
