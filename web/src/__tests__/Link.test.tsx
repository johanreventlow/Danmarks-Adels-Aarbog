// @vitest-environment jsdom
// Bemærk: de tests hvor klikket bevidst IKKE forhindres, får jsdom til at skrive
// "Not implemented: navigation to another Document" til stderr. Det er forventet og beviser
// præcis dét testen tjekker: at browseren fik klikket.
import { render, screen, fireEvent } from '@testing-library/react';
import { vi } from 'vitest';
import { Link, isModifiedClick } from '../Link';

describe('Link', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('renderer et ægte anker med href (det højreklik-menuen læser)', () => {
    render(<Link href="/person/42">Navn</Link>);
    const a = screen.getByText('Navn');
    expect(a.tagName).toBe('A');
    expect(a.getAttribute('href')).toBe('/person/42');
  });

  it('almindeligt venstreklik navigerer i appen og forhindrer browserens egen navigation', () => {
    render(<Link href="/person/42">Navn</Link>);
    // fireEvent returnerer false når preventDefault() blev kaldt.
    expect(fireEvent.click(screen.getByText('Navn'))).toBe(false);
    expect(window.location.pathname).toBe('/person/42');
  });

  it('kalder onNavigate i stedet for navigate(href) når den er sat', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).toHaveBeenCalledTimes(1);
    expect(window.location.pathname).toBe('/'); // appen navigerede ikke selv
  });

  it('lader browseren håndtere cmd-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { metaKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
    expect(window.location.pathname).toBe('/');
  });

  it('lader browseren håndtere ctrl-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { ctrlKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere shift-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { shiftKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere alt-klik', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { altKey: true })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('lader browseren håndtere midterklik (button !== 0)', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'), { button: 1 })).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it('stopPropagation=true forhindrer at et omsluttende korts onClick også fyrer', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).toHaveBeenCalledTimes(1);
    expect(kortKlik).not.toHaveBeenCalled();
  });

  // Review B1 (BLOCKER): den nemme fejl er at afgive klikket til browseren FØR stopPropagation.
  // Så åbner browseren ny fane MENS kortets onClick navigerer den aktuelle — dobbelt-navigation.
  it('stopPropagation gælder også når browseren overtager klikket (cmd-klik)', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'), { metaKey: true });
    expect(onNavigate).not.toHaveBeenCalled(); // browseren ejer klikket
    expect(kortKlik).not.toHaveBeenCalled();   // ← men kortet må stadig ikke navigere
  });

  it('stopPropagation gælder også når en indre handler allerede har forhindret klikket', () => {
    const kortKlik = vi.fn();
    const onNavigate = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={onNavigate} stopPropagation>
          <span onClick={(e) => e.preventDefault()}>Navn</span>
        </Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(onNavigate).not.toHaveBeenCalled();
    expect(kortKlik).not.toHaveBeenCalled();
  });

  it('uden stopPropagation bobler klikket videre til det omsluttende kort', () => {
    const kortKlik = vi.fn();
    render(
      <div onClick={kortKlik}>
        <Link href="/person/42" onNavigate={vi.fn()}>Navn</Link>
      </div>,
    );
    fireEvent.click(screen.getByText('Navn'));
    expect(kortKlik).toHaveBeenCalledTimes(1);
  });

  it('et eksplicit target overlades til browseren', () => {
    const onNavigate = vi.fn();
    render(<Link href="/person/42" target="_blank" rel="noreferrer" onNavigate={onNavigate}>Navn</Link>);
    expect(fireEvent.click(screen.getByText('Navn'))).toBe(true);
    expect(onNavigate).not.toHaveBeenCalled();
  });
});

describe('isModifiedClick', () => {
  const basis = { defaultPrevented: false, button: 0, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false };
  it('er falsk for et rent venstreklik', () => {
    expect(isModifiedClick(basis as never)).toBe(false);
  });
  it('er sand når en indre handler allerede har taget klikket', () => {
    expect(isModifiedClick({ ...basis, defaultPrevented: true } as never)).toBe(true);
  });
});
