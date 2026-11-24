// @vitest-environment jsdom
// Review 37 W8: modale overlays flytter fokus ind, holder Tab inde og giver fokus tilbage ved lukning.
import { fireEvent, render, screen } from '@testing-library/react';
import { useRef, useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { useModalFokus } from '../useModalFokus';

function Dialog({ onEscape }: { onEscape?: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  useModalFokus(ref, { onEscape });
  return (
    <div ref={ref} role="dialog" aria-label="Test">
      <button type="button">Første</button>
      <button type="button">Sidste</button>
    </div>
  );
}

function Vaert({ onEscape }: { onEscape?: () => void }) {
  const [aaben, setAaben] = useState(false);
  return (
    <>
      <button type="button" onClick={() => setAaben(true)}>Åbn</button>
      <button type="button" onClick={() => setAaben(false)}>Luk udefra</button>
      {aaben && <Dialog onEscape={onEscape ?? (() => setAaben(false))} />}
    </>
  );
}

describe('useModalFokus (review 37 W8)', () => {
  it('flytter fokus til første knap ved åbning og tilbage til åbneren ved lukning', () => {
    render(<Vaert />);
    const aabn = screen.getByRole('button', { name: 'Åbn' });
    aabn.focus();
    fireEvent.click(aabn);
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Første' }));
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(document.activeElement).toBe(aabn);
  });

  it('Tab fra sidste går til første, Shift+Tab fra første går til sidste', () => {
    render(<Vaert />);
    fireEvent.click(screen.getByRole('button', { name: 'Åbn' }));
    const foerste = screen.getByRole('button', { name: 'Første' });
    const sidste = screen.getByRole('button', { name: 'Sidste' });
    sidste.focus();
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(document.activeElement).toBe(foerste);
    fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(sidste);
  });

  it('uden onEscape gør Esc intet (kalderen har sin egen håndtering)', () => {
    const ref = { current: null as HTMLDivElement | null };
    function UdenEsc() {
      useModalFokus(ref);
      return <div ref={(el) => { ref.current = el; }}><button type="button">x</button></div>;
    }
    const spy = vi.fn();
    document.addEventListener('keydown', spy);
    render(<UdenEsc />);
    const ev = new KeyboardEvent('keydown', { key: 'Escape', cancelable: true });
    document.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(false);
    document.removeEventListener('keydown', spy);
  });
});
