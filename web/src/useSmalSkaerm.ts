// Smal skærm (telefon): stamtræet skifter til mobiltegningens fokusvisning, og personpanelet vises ikke
// (fokuskortet har selv »Åbn personsiden«). Uden matchMedia (jsdom, ældre browsere) regnes skærmen bred.
import { useEffect, useState } from 'react';

export const SMAL_SKAERM = '(max-width: 720px)';

const matcher = (): boolean =>
  typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia(SMAL_SKAERM).matches;

export function useSmalSkaerm(): boolean {
  const [smal, setSmal] = useState(matcher);
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mq = window.matchMedia(SMAL_SKAERM);
    const opdater = () => setSmal(mq.matches);
    opdater();
    mq.addEventListener?.('change', opdater);
    return () => mq.removeEventListener?.('change', opdater);
  }, []);
  return smal;
}
