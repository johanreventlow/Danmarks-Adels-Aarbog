// @vitest-environment jsdom
import { fireEvent, render, screen } from '@testing-library/react';
import { useRef, useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { Sidehoved, type HovedpunktAktiv } from '../Sidehoved';
import { SLAEGTER } from '../../data/nav';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
import { navigate } from '../../router';

function Opsat({ aktiv = null, visRedaktion = false, onVaelg = vi.fn() }: { aktiv?: HovedpunktAktiv; visRedaktion?: boolean; onVaelg?: (s: string) => void }) {
  const [aaben, setAaben] = useState(false);
  const knap = useRef<HTMLButtonElement>(null);
  return (
    <>
      <Sidehoved aktiv={aktiv} menuAaben={aaben} menuKnap={knap}
        setMenuAaben={(a, retur) => { setAaben(a); if (!a && retur) knap.current?.focus(); }}
        slaegter={SLAEGTER} senestSlaegt={null} aktivSlaegt={null} onVaelgSlaegt={onVaelg}
        onPersoner={vi.fn()} onSlaegtskab={vi.fn()} onForside={vi.fn()}
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
