// <img> til signerede medie-URL'er (review 37 W7). Signerede URL'er udløber efter 600 s, men ligger i komponenternes
// tilstand længe efter — et billede, der først indlæses senere (Lightbox, fuld størrelse, et nyt galleri-udsnit),
// fik et brudt billede. Ved en indlæsningsfejl signeres stien én gang forfra (fornyUrl); lykkes det ikke, eller
// fejler også den nye URL, kaldes kalderens onError som før.
import { useEffect, useRef, useState, type ImgHTMLAttributes, type SyntheticEvent } from 'react';
import { fornyUrl } from '../data/media';

export function SignedImg({ src, onError, ...rest }: ImgHTMLAttributes<HTMLImageElement>) {
  const [aktuel, setAktuel] = useState(src);
  const [fornyetFor, setFornyetFor] = useState<string | undefined>(undefined);
  // Ny src fra kalderen (andet billede) → start forfra under render (ingen frame med den gamle URL);
  // ét fornyelsesforsøg pr. src.
  const [forrigeSrc, setForrigeSrc] = useState(src);
  if (src !== forrigeSrc) {
    setForrigeSrc(src);
    setAktuel(src);
    setFornyetFor(undefined);
  }
  const srcRef = useRef(src);
  useEffect(() => { srcRef.current = src; }, [src]);

  const handleError = (e: SyntheticEvent<HTMLImageElement, Event>) => {
    if (typeof src !== 'string' || !src || fornyetFor === src || typeof aktuel !== 'string') {
      onError?.(e);
      return;
    }
    setFornyetFor(src);
    const original = src;
    void fornyUrl(aktuel).then(
      (ny) => {
        if (srcRef.current !== original) return; // kalderen har skiftet billede imens
        if (ny && ny !== aktuel) setAktuel(ny);
        else onError?.(e);
      },
      () => { if (srcRef.current === original) onError?.(e); },
    );
  };

  return <img {...rest} src={aktuel} onError={handleError} />;
}
