// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { useRef, useState, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Sidehoved, type HovedpunktAktiv } from '../Sidehoved';
import { SLAEGTER } from '../../data/nav';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
import { navigate } from '../../router';
const smal = vi.hoisted(() => ({ v: false }));
vi.mock('../../useSmalSkaerm', () => ({ useSmalSkaerm: () => smal.v }));

type OpsatProps = { aktiv?: HovedpunktAktiv; visRedaktion?: boolean; onVaelg?: (s: string) => void; sti?: string;
  onPersoner?: () => void; onSlaegtskab?: () => void; spion?: (a: boolean, retur?: boolean, aabner?: HTMLElement | null) => void; ekstra?: ReactNode };
function Opsat({ aktiv = null, visRedaktion = false, onVaelg = vi.fn(), sti = '/', onPersoner = vi.fn(), onSlaegtskab = vi.fn(), spion, ekstra }: OpsatProps) {
  const [aaben, setAaben] = useState(false);
  const knap = useRef<HTMLButtonElement>(null);
  return (
    <>
      <Sidehoved aktiv={aktiv} menuAaben={aaben} menuKnap={knap} sti={sti} ekstra={ekstra}
        setMenuAaben={(a, retur, aabner) => { spion?.(a, retur, aabner); setAaben(a); if (!a && retur) knap.current?.focus(); }}
        slaegter={SLAEGTER} senestSlaegt={null} aktivSlaegt={null} onVaelgSlaegt={onVaelg}
        onPersoner={onPersoner} onSlaegtskab={onSlaegtskab} onForside={vi.fn()}
        loggetInd={false} onLogin={vi.fn()} onLogout={vi.fn()} visRedaktion={visRedaktion} />
      <p>Udenfor</p>
    </>
  );
}

describe('Sidehoved', () => {
  it('har Personer, Slægter og Slægtskab — ingen Historie, ingen »kommer«', () => {
    render(<Opsat />);
    expect(screen.getByRole('link', { name: 'Personer' }).getAttribute('href')).toBe('/soeg');
    expect(screen.getByRole('button', { name: /Slægter/ })).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Slægtskab' }).getAttribute('href')).toBe('/slaegtskab');
    expect(screen.queryByText(/Historie/)).toBeNull();
    expect(screen.queryByText(/kommer/i)).toBeNull();
  });

  it('»Redaktion ↗« kun for redaktionen', () => {
    const { unmount } = render(<Opsat />);
    expect(screen.queryByRole('link', { name: /Redaktion/ })).toBeNull();
    unmount();
    render(<Opsat visRedaktion />);
    expect(screen.getByRole('link', { name: /Redaktion/ }).getAttribute('href')).toBe('/redaktion');
  });

  it('aria-current på det aktive punkt', () => {
    render(<Opsat aktiv="slaegtskab" />);
    expect(screen.getByRole('link', { name: 'Slægtskab' }).getAttribute('aria-current')).toBe('page');
    expect(screen.getByRole('link', { name: 'Personer' }).getAttribute('aria-current')).toBeNull();
  });

  it('Slægter åbner ved klik og pil ned; Esc lukker og giver fokus tilbage', () => {
    render(<Opsat />);
    const knap = screen.getByRole('button', { name: /Slægter/ });
    expect(knap.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(knap);
    expect(knap.getAttribute('aria-expanded')).toBe('true');
    expect(document.activeElement).toBe(screen.getByLabelText('Find slægt')); // fokus ind i panelet
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(knap.getAttribute('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(knap);
    fireEvent.keyDown(knap, { key: 'ArrowDown' });
    expect(knap.getAttribute('aria-expanded')).toBe('true');
  });

  it('klik udenfor lukker; klik på en slægt vælger den', () => {
    const onVaelg = vi.fn();
    render(<Opsat onVaelg={onVaelg} />);
    const knap = screen.getByRole('button', { name: /Slægter/ });
    fireEvent.click(knap);
    fireEvent.mouseDown(screen.getByText('Udenfor'));
    expect(knap.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(knap);
    const link = screen.getByRole('link', { name: 'Reventlow' });
    expect(link.getAttribute('href')).toBe('/slaegt/reventlow');
    fireEvent.click(link);
    expect(onVaelg).toHaveBeenCalledWith('reventlow');
  });

  it('Find slægt filtrerer og siger det med ord, når intet passer', () => {
    render(<Opsat />);
    fireEvent.click(screen.getByRole('button', { name: /Slægter/ }));
    fireEvent.change(screen.getByLabelText('Find slægt'), { target: { value: 'Moltke' } });
    expect(screen.queryByRole('link', { name: 'Reventlow' })).toBeNull();
    expect(screen.getByText(/Ingen slægt i Aarbogen hedder »Moltke«/)).toBeTruthy();
  });

  it('søgefeltet fører til /soeg?q=', () => {
    render(<Opsat />);
    fireEvent.change(screen.getByLabelText('Søg i Aarbogen'), { target: { value: 'Conrad' } });
    fireEvent.submit(screen.getByRole('search'));
    expect(navigate).toHaveBeenCalledWith('/soeg?q=Conrad');
  });
});

describe('Sidehoved på smal skærm (fase 9)', () => {
  beforeEach(() => { smal.v = true; vi.mocked(navigate).mockClear(); });
  afterEach(() => { smal.v = false; });
  const menu = () => screen.getByRole('button', { name: 'Menu' });

  it('én række: forsiden, »Din plads« og menuknappen — hovedmenu og søgefelt først, når menuen åbnes', () => {
    render(<Opsat ekstra={<span>LC</span>} />);
    expect(screen.getByRole('link', { name: /Danmarks Adels Aarbog/ }).getAttribute('href')).toBe('/');
    expect(screen.getByText('LC')).toBeTruthy();
    expect(menu().getAttribute('aria-expanded')).toBe('false');
    expect(menu().getAttribute('aria-controls')).toBe('mobilmenu');
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    expect(screen.queryByLabelText('Søg i Aarbogen')).toBeNull();
    fireEvent.click(menu());
    expect(menu().getAttribute('aria-expanded')).toBe('true');
    const nav = screen.getByRole('navigation', { name: 'Hovedmenu' });
    expect(within(nav).getByRole('link', { name: 'Personer' }).getAttribute('href')).toBe('/soeg');
    expect(screen.getByLabelText('Søg i Aarbogen')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Log ind' })).toBeTruthy();
  });

  it('Esc lukker og giver fokus tilbage til menuknappen; klik udenfor lukker', () => {
    render(<Opsat />);
    fireEvent.click(menu());
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(menu().getAttribute('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(menu());
    fireEvent.click(menu());
    fireEvent.mouseDown(screen.getByText('Udenfor'));
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
  });

  it('Personer, Slægtskab og en søgning lukker menuen', () => {
    const onPersoner = vi.fn(); const onSlaegtskab = vi.fn();
    render(<Opsat onPersoner={onPersoner} onSlaegtskab={onSlaegtskab} />);
    fireEvent.click(menu()); fireEvent.click(screen.getByRole('link', { name: 'Personer' }));
    expect(onPersoner).toHaveBeenCalled();
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    fireEvent.click(menu()); fireEvent.click(screen.getByRole('link', { name: 'Slægtskab' }));
    expect(onSlaegtskab).toHaveBeenCalled();
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    fireEvent.click(menu());
    fireEvent.change(screen.getByLabelText('Søg i Aarbogen'), { target: { value: 'Conrad' } });
    fireEvent.submit(screen.getByRole('search'));
    expect(navigate).toHaveBeenCalledWith('/soeg?q=Conrad');
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
  });

  it('Slægter i menuen lukker menuen og åbner slægtsvælgeren med menuknappen som åbner; menuknappen styrer den derefter', () => {
    const spion = vi.fn();
    render(<Opsat spion={spion} />);
    fireEvent.click(menu());
    fireEvent.click(screen.getByRole('button', { name: /Slægter/ }));
    expect(spion).toHaveBeenLastCalledWith(true, false, menu());
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    expect(screen.getByLabelText('Find slægt')).toBeTruthy();
    expect(menu().getAttribute('aria-expanded')).toBe('true');
    expect(menu().getAttribute('aria-controls')).toBe('slaegter-menu');
    fireEvent.click(menu()); // lukker slægtsvælgeren, åbner ikke menuen
    expect(screen.queryByLabelText('Find slægt')).toBeNull();
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    expect(menu().getAttribute('aria-expanded')).toBe('false');
  });

  it('åbning af menuen lukker en åben slægtsvælger (fx fra »Skift slægt«)', () => {
    const spion = vi.fn();
    function MedAabenVaelger() {
      const [aaben, setAaben] = useState(true);
      const knap = useRef<HTMLButtonElement>(null);
      return <Sidehoved aktiv={null} menuAaben={aaben} menuKnap={knap} sti="/"
        setMenuAaben={(a, r, o) => { spion(a, r, o); setAaben(a); }}
        slaegter={SLAEGTER} senestSlaegt={null} aktivSlaegt={null} onVaelgSlaegt={vi.fn()}
        onPersoner={vi.fn()} onSlaegtskab={vi.fn()} onForside={vi.fn()}
        loggetInd={false} onLogin={vi.fn()} onLogout={vi.fn()} visRedaktion={false} />;
    }
    render(<MedAabenVaelger />);
    fireEvent.click(menu()); // lukker vælgeren (knappen styrer den åbne vælger)
    expect(spion.mock.lastCall?.[0]).toBe(false);
    fireEvent.click(menu()); // nu åbner menuen
    expect(screen.getByRole('navigation', { name: 'Hovedmenu' })).toBeTruthy();
  });

  it('ny side (sti) lukker menuen; skift til bred skærm viser den brede navigation', () => {
    const { rerender } = render(<Opsat sti="/" />);
    fireEvent.click(menu());
    rerender(<Opsat sti="/person/1" />);
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    fireEvent.click(menu());
    smal.v = false;
    rerender(<Opsat sti="/person/1" />);
    expect(screen.queryByRole('button', { name: 'Menu' })).toBeNull();
    expect(screen.getByRole('navigation', { name: 'Hovedmenu' })).toBeTruthy();
    smal.v = true;
    rerender(<Opsat sti="/person/1" />);
    expect(menu().getAttribute('aria-expanded')).toBe('false');
  });

  it('Log ind lukker menuen, så login-dialogen ikke står oven på et åbent panel', () => {
    render(<Opsat />);
    fireEvent.click(menu());
    fireEvent.click(screen.getByRole('button', { name: 'Log ind' }));
    expect(screen.queryByRole('navigation', { name: 'Hovedmenu' })).toBeNull();
    expect(menu().getAttribute('aria-expanded')).toBe('false');
  });

  it('menuens knapper og links er mindst 44 px høje', () => {
    render(<Opsat visRedaktion />);
    fireEvent.click(menu());
    for (const el of [screen.getByRole('button', { name: 'Log ind' }), screen.getByRole('link', { name: /Redaktion/ })]) {
      expect(parseFloat(el.style.minHeight)).toBeGreaterThanOrEqual(44);
    }
  });

  it('»Redaktion ↗« i menuen kun for redaktionen', () => {
    render(<Opsat visRedaktion />);
    fireEvent.click(menu());
    expect(screen.getByRole('link', { name: /Redaktion/ }).getAttribute('href')).toBe('/redaktion');
  });
});
