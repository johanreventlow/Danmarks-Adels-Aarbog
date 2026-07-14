import { useEffect } from 'react';
import { useStore } from '../store/useStore';

// Lazy geo-kæde (review 27 P3, single-sourcet /simplify): udløser geo-hentningen ved mount af
// en geo-visende flade (kort/godser/gods-detalje). Gates + re-kører på status (ikke tomme
// deps): _layout.tsx monterer routes uafhængigt af load()-status, så et direkte deep-link til
// en kort-flade kan mounte mens status stadig er 'loading' — uden dette ville loadGeo() kaldes
// for tidligt (stashedLoadGeo endnu null) og aldrig genforsøges når data rent faktisk ankommer
// (dual-review-fund). loadGeo() selv no-op'er hvis allerede loading/loaded.
export function useGeoOnMount(): void {
  const status = useStore((s) => s.status);

  useEffect(() => {
    if (status === 'ready') useStore.getState().loadGeo();
  }, [status]);
}
