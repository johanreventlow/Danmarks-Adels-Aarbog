// @vitest-environment jsdom
// Slægtskab som kontekst over navnet (webredesign fase 8): den præcise tekst pr. tilstand. Usikkerhed siges altid
// med ord (invariant 7), og personsiden nævner aldrig »dobbelt« slægtskab (planens valg 5).
import { fireEvent, render, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { SlaegtskabsKontekst } from '../../data/slaegtskab';
import { personPath, slaegtskabPath } from '../../data/nav';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { SlaegtskabsLinje } = await import('../SlaegtskabsLinje');

const vis = (kontekst: SlaegtskabsKontekst, onVisPerson = vi.fn()) =>
  render(<SlaegtskabsLinje kontekst={kontekst} meId="mig" focusId="fokus" onVisPerson={onVisPerson} />);
const linje = () => screen.getByTestId('slaegtskab-kontekst');

const blod = (o: Partial<Extract<SlaegtskabsKontekst, { art: 'blod' }>> = {}): SlaegtskabsKontekst =>
  ({ art: 'blod', ord: 'din 1. grads fætter', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false, ...o });
const gift = (o: Partial<Extract<SlaegtskabsKontekst, { art: 'gift' }>> = {}): SlaegtskabsKontekst =>
  ({ art: 'gift', ord: 'din onkel', aegtefaelleId: 'aegtef', aegtefaelleNavn: 'Christian Reventlow', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false, ...o });

describe('SlaegtskabsLinje', () => {
  it('skjult renderer intet', () => {
    vis({ art: 'skjult' });
    expect(screen.queryByTestId('slaegtskab-kontekst')).toBeNull();
  });

  it('dig, min ægtefælle og ingen fælles ane', () => {
    const { unmount } = vis({ art: 'dig' });
    expect(linje().textContent).toMatch(/^Det er dig$/);
    unmount();
    const r2 = vis({ art: 'min-aegtefaelle' });
    expect(linje().textContent).toMatch(/^Din ægtefælle$/);
    r2.unmount();
    vis({ art: 'ingen' });
    expect(linje().textContent).toMatch(/^Aarbogen viser ingen fælles ane med dig$/);
  });

  it('blodslægtning: ordet med stort begyndelsesbogstav og »Se vejen« til »Er vi i familie?«', () => {
    vis(blod());
    expect(linje().textContent).toMatch(/^Din 1\. grads fætter/);
    const vej = within(linje()).getByRole('link', { name: 'Se vejen' });
    expect(vej.getAttribute('href')).toBe(slaegtskabPath('mig', 'fokus'));
  });

  it('flere veje → »Se alle N veje«', () => {
    vis(blod({ veje: 2 }));
    expect(within(linje()).getByRole('link', { name: 'Se alle 2 veje' }).getAttribute('href')).toBe(slaegtskabPath('mig', 'fokus'));
  });

  it('usikkerhed med ord: sandsynligvis, omstridt og bekræftet ad en anden linje', () => {
    const r1 = vis(blod({ sikkerhed: 'sandsynligvis' }));
    expect(linje().textContent).toMatch(/^Sandsynligvis din 1\. grads fætter/);
    r1.unmount();
    const r2 = vis(blod({ sikkerhed: 'omstridt' }));
    expect(linje().textContent).toMatch(/^Omstridt: din 1\. grads fætter/);
    r2.unmount();
    vis(blod({ sikkerhed: 'omstridt', bekraeftetAndenVej: true, veje: 2 }));
    expect(linje().textContent).toMatch(/^Omstridt: din 1\. grads fætter · bekræftet ad en anden linje/);
  });

  it('indgiftet: ægtefællen som link, og vejen går til ægtefællen', () => {
    const onVisPerson = vi.fn();
    vis(gift(), onVisPerson);
    expect(linje().textContent).toMatch(/^Gift med Christian Reventlow, din onkel/);
    const navn = within(linje()).getByRole('link', { name: 'Christian Reventlow' });
    expect(navn.getAttribute('href')).toBe(personPath('aegtef'));
    fireEvent.click(navn);
    expect(onVisPerson).toHaveBeenCalledWith('aegtef');
    expect(within(linje()).getByRole('link', { name: 'Se vejen' }).getAttribute('href')).toBe(slaegtskabPath('mig', 'aegtef'));
  });

  it('indgiftet med flere veje og usikkerhed på blodsforbindelsen, ikke på ægteskabet', () => {
    const r1 = vis(gift({ veje: 2 }));
    expect(within(linje()).getByRole('link', { name: 'Se alle 2 veje' })).toBeTruthy();
    r1.unmount();
    const r2 = vis(gift({ sikkerhed: 'sandsynligvis' }));
    expect(linje().textContent).toMatch(/^Gift med Christian Reventlow, sandsynligvis din onkel/);
    r2.unmount();
    const r3 = vis(gift({ sikkerhed: 'omstridt' }));
    expect(linje().textContent).toMatch(/^Gift med Christian Reventlow, omstridt: din onkel/);
    r3.unmount();
    vis(gift({ sikkerhed: 'sandsynligvis', bekraeftetAndenVej: true, veje: 2 }));
    expect(linje().textContent).toMatch(/^Gift med Christian Reventlow, sandsynligvis din onkel · bekræftet ad en anden linje/);
  });

  it('ingen tilstand nævner »dobbelt«', () => {
    const alle: SlaegtskabsKontekst[] = [{ art: 'dig' }, { art: 'min-aegtefaelle' }, { art: 'ingen' },
      blod({ veje: 3 }), blod({ sikkerhed: 'omstridt', bekraeftetAndenVej: true, veje: 2 }), gift({ veje: 2 })];
    for (const k of alle) {
      const r = vis(k);
      expect(linje().textContent ?? '').not.toMatch(/dobbelt/i);
      r.unmount();
    }
  });
});
