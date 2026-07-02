// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { NarrativRenderer } from '../NarrativRenderer';

const COLORS = { linkColor: '#881A33', inactiveColor: '#9a8f78' };

describe('NarrativRenderer', () => {
  it('renderer ren tekst uden links', () => {
    render(<NarrativRenderer tekst="bare prosa" onPickPerson={vi.fn()} {...COLORS} />);
    expect(screen.getByText('bare prosa')).toBeTruthy();
  });

  it('renderer person-token som klikbart link der kalder onPickPerson med korrekt id', () => {
    const onPick = vi.fn();
    render(<NarrativRenderer tekst="Se [[person:482|Chr. D. R.]] her." onPickPerson={onPick} {...COLORS} />);
    const link = screen.getByText('Chr. D. R.');
    fireEvent.click(link);
    expect(onPick).toHaveBeenCalledWith('482');
  });

  it('renderer ikke-person-token som inaktiv tekst uden klik-effekt', () => {
    const onPick = vi.fn();
    render(<NarrativRenderer tekst="Se [[estate:7|Gammel Gaard]] her." onPickPerson={onPick} {...COLORS} />);
    const inactive = screen.getByText('Gammel Gaard');
    fireEvent.click(inactive);
    expect(onPick).not.toHaveBeenCalled();
  });

  it('malformet token vises som rå tekst, ikke som knækket link', () => {
    render(<NarrativRenderer tekst="[[person:abc|x]]" onPickPerson={vi.fn()} {...COLORS} />);
    expect(screen.getByText('[[person:abc|x]]')).toBeTruthy();
  });
});
