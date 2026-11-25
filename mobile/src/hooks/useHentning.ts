// Én læsning til en redaktionsflade, med tre ærlige tilstande (review 37 W1-W3, spejl af web 54d1b7db/47fe59f8):
// 'henter', 'fejl' og 'ok'. En fejl er en fejl — aldrig en tom liste, der ligner »ingen oplysninger«.
// Kun det nyeste kald må lande: et svar fra en tidligere hentning (andet id, ældre genindlæsning efter en skrivning,
// eller efter unmount) kasseres.
// `noegle` er det, der hentes for (fx person-id'et); skifter den (også via null), starter tilstanden forfra, og data
// fra en anden nøgle vises aldrig. `hent` skal være memoiseret (useCallback); skifter den alene (fx fordi
// redaktions-modellen er genindlæst), hentes der igen, mens de hidtidige data bliver stående. null = intet at hente.
import { useCallback, useEffect, useRef, useState } from 'react';

export type HentStatus = 'henter' | 'fejl' | 'ok';
export type Hentning<T> = {
  status: HentStatus;
  // Seneste vellykkede svar for nøglen; bevares under en genindlæsning og ved en fejlet genindlæsning.
  data: T | null;
  fejl: string | null;
  // Hent igen (»Prøv igen«, eller efter en skrivning). Løftet afgøres, når svaret er landet eller kasseret.
  genhent: () => Promise<void>;
};

type Tilstand<T> = { noegle: string | null; status: HentStatus; data: T | null; fejl: string | null };

const tekst = (e: unknown): string =>
  e instanceof Error ? e.message
    : typeof e === 'object' && e !== null && typeof (e as { message?: unknown }).message === 'string'
      ? (e as { message: string }).message
      : String(e);

export function useHentning<T>(noegle: string | null, hent: () => Promise<T>): Hentning<T> {
  const [tilstand, setTilstand] = useState<Tilstand<T>>({ noegle, status: 'henter', data: null, fejl: null });
  // Ny nøgle: start forfra under render (Reacts mønster for at nulstille tilstand ved skift af en prop).
  if (tilstand.noegle !== noegle) setTilstand({ noegle, status: 'henter', data: null, fejl: null });
  const genRef = useRef(0);
  const annuller = useCallback(() => { genRef.current++; }, []);

  const koer = useCallback((n: string, fn: () => Promise<T>): Promise<void> => {
    const gen = ++genRef.current;
    return fn().then(
      (data) => { if (gen === genRef.current) setTilstand({ noegle: n, status: 'ok', data, fejl: null }); },
      (e) => {
        if (gen !== genRef.current) return;
        console.warn('[redaktion] hentning fejlede:', e);
        setTilstand((t) => ({ noegle: n, status: 'fejl', data: t.data, fejl: tekst(e) }));
      },
    );
  }, []);

  useEffect(() => {
    if (noegle === null) return;
    void koer(noegle, hent);
    // Unmount, ny nøgle eller ny hent-funktion: et svar, der stadig er undervejs, må ikke lande.
    return annuller;
  }, [noegle, hent, koer, annuller]);

  const genhent = useCallback((): Promise<void> => {
    if (noegle === null) return Promise.resolve();
    setTilstand((t) => (t.status === 'fejl' ? { ...t, status: 'henter', fejl: null } : t));
    return koer(noegle, hent);
  }, [noegle, hent, koer]);

  // Tilstand for en anden nøgle vises aldrig: indtil den nye har svaret, hentes der.
  if (noegle === null) return { status: 'ok', data: null, fejl: null, genhent };
  if (tilstand.noegle !== noegle) return { status: 'henter', data: null, fejl: null, genhent };
  return { status: tilstand.status, data: tilstand.data, fejl: tilstand.fejl, genhent };
}
