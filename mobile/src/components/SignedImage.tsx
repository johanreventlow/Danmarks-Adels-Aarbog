// expo-image til signerede medie-URL'er (review 37 W7, spejler web's SignedImg). Signerede URL'er
// udløber efter 600 s, men ligger i skærmenes tilstand længe efter — et billede, der først indlæses
// senere, blev brudt. Ved en indlæsningsfejl signeres stien én gang forfra (fornyUrl); lykkes det
// ikke, eller fejler også den nye URL, kaldes kalderens onError som før.
import { Image, type ImageProps } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { fornyUrl } from '../lib/media';

type Props = Omit<ImageProps, 'source'> & { uri: string };

export function SignedImage({ uri, onError, ...rest }: Props) {
  const [aktuel, setAktuel] = useState(uri);
  const [fornyet, setFornyet] = useState(false);
  // Ny uri fra kalderen (andet billede) → start forfra under render; ét fornyelsesforsøg pr. uri.
  const [forrigeUri, setForrigeUri] = useState(uri);
  if (uri !== forrigeUri) {
    setForrigeUri(uri);
    setAktuel(uri);
    setFornyet(false);
  }
  const uriRef = useRef(uri);
  useEffect(() => { uriRef.current = uri; }, [uri]);

  const handleError: NonNullable<ImageProps['onError']> = (e) => {
    if (!uri || fornyet) { onError?.(e); return; }
    setFornyet(true);
    const original = uri;
    fornyUrl(aktuel).then(
      (ny) => {
        if (uriRef.current !== original) return; // kalderen har skiftet billede imens
        if (ny && ny !== aktuel) setAktuel(ny);
        else onError?.(e);
      },
      () => { if (uriRef.current === original) onError?.(e); },
    );
  };

  return <Image {...rest} source={{ uri: aktuel }} onError={handleError} />;
}
