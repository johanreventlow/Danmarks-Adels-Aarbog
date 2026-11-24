// Fokusstyring for modale overlays (review 37 W8): Lightbox, MapLightbox og login-dialogen.
// - Ved åbning flyttes fokus ind i dialogen (første fokuserbare element, ellers containeren selv).
// - Tab og Shift+Tab bliver i dialogen (en skærmlæser- eller tastaturbruger kan ikke »falde ud« bag overlayet).
// - Esc kalder onEscape, hvis kalderen ønsker det (Lightbox/MapLightbox har deres egen Esc-håndtering).
// - Ved lukning får det element, der havde fokus før åbning, fokus igen — hvis det stadig findes.
import { useEffect, useRef, type RefObject } from 'react';

const FOKUSERBAR = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"])';

function fokuserbare(container: HTMLElement): HTMLElement[] {
  return [...container.querySelectorAll<HTMLElement>(FOKUSERBAR)].filter((el) => !el.hasAttribute('inert'));
}

export function useModalFokus(ref: RefObject<HTMLElement | null>, opts?: { onEscape?: () => void; startFokus?: RefObject<HTMLElement | null> }) {
  const onEscapeRef = useRef(opts?.onEscape);
  useEffect(() => { onEscapeRef.current = opts?.onEscape; });
  const startFokus = opts?.startFokus;

  useEffect(() => {
    const container = ref.current;
    if (!container) return;
    const foer = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const start = startFokus?.current ?? fokuserbare(container)[0] ?? container;
    if (start === container && !container.hasAttribute('tabindex')) container.setAttribute('tabindex', '-1');
    start.focus();

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && onEscapeRef.current) { e.preventDefault(); onEscapeRef.current(); return; }
      if (e.key !== 'Tab') return;
      const liste = fokuserbare(container);
      if (!liste.length) { e.preventDefault(); container.focus(); return; }
      const foerste = liste[0];
      const sidste = liste[liste.length - 1];
      const aktiv = document.activeElement;
      if (e.shiftKey && (aktiv === foerste || !container.contains(aktiv))) { e.preventDefault(); sidste.focus(); }
      else if (!e.shiftKey && (aktiv === sidste || !container.contains(aktiv))) { e.preventDefault(); foerste.focus(); }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      if (foer?.isConnected) foer.focus();
    };
    // Kun ved åbning/lukning — ikke ved hvert render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}
