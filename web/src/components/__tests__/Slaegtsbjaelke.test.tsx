// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { Slaegtsbjaelke } from '../Slaegtsbjaelke';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const REVENTLOW = { slug: 'reventlow', navn: 'Reventlow' };

describe('Slaegtsbjaelke', () => {
  it('slægtens sider med adresser og aria-current', () => {
    render(<Slaegtsbjaelke slaegt={REVENTLOW} aktivMode="tree" visPraesens={false} onGaaTil={vi.fn()} onSkiftSlaegt={vi.fn()} />);
    const nav = screen.getByRole('navigation', { name: 'Slægten Reventlow' });
    const href = (navn: string) => within(nav).getByRole('link', { name: navn }).getAttribute('href');
    expect(href('Forside')).toBe('/slaegt/reventlow');
    expect(href('Stamtræ')).toBe('/slaegt/reventlow/stamtrae');
    expect(href('Godser')).toBe('/slaegt/reventlow/godser');
    expect(href('Våben')).toBe('/slaegt/reventlow/vaaben');
    expect(within(nav).getByRole('link', { name: 'Stamtræ' }).getAttribute('aria-current')).toBe('page');
    expect(within(nav).getByRole('link', { name: 'Forside' }).getAttribute('aria-current')).toBeNull();
    expect(within(nav).queryByText('Artikler')).toBeNull(); // findes ikke endnu
  });

  it('Godser er aktiv også på oversigtskortet', () => {
    render(<Slaegtsbjaelke slaegt={REVENTLOW} aktivMode="kort" visPraesens={false} onGaaTil={vi.fn()} onSkiftSlaegt={vi.fn()} />);
    expect(screen.getByRole('link', { name: 'Godser' }).getAttribute('aria-current')).toBe('page');
  });

  it('præsenslisten kun for redaktionen', () => {
    const { unmount } = render(<Slaegtsbjaelke slaegt={REVENTLOW} aktivMode="about" visPraesens={false} onGaaTil={vi.fn()} onSkiftSlaegt={vi.fn()} />);
    expect(screen.queryByRole('link', { name: 'Præsensliste' })).toBeNull();
    unmount();
    render(<Slaegtsbjaelke slaegt={REVENTLOW} aktivMode="about" visPraesens onGaaTil={vi.fn()} onSkiftSlaegt={vi.fn()} />);
    expect(screen.getByRole('link', { name: 'Præsensliste' }).getAttribute('href')).toBe('/slaegt/reventlow/praesens');
  });

  it('»Skift slægt« er en knap, der åbner vælgeren', () => {
    const onSkift = vi.fn();
    render(<Slaegtsbjaelke slaegt={REVENTLOW} aktivMode="about" visPraesens={false} onGaaTil={vi.fn()} onSkiftSlaegt={onSkift} />);
    fireEvent.click(screen.getByRole('button', { name: 'Skift slægt' }));
    expect(onSkift).toHaveBeenCalled();
  });
});
