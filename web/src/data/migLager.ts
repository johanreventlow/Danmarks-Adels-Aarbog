// »Det er mig«-markeringen (PoC: localStorage; flyttes til profiles.reventlow_person_id ved login).
// Review 37 W11: localStorage kan kaste (privat vindue, blokerede site-data, fuld kvote). Markeringen
// er en bekvemmelighed, så en fejl betyder blot, at den ikke huskes — aldrig at siden vælter.
export const MIG_KEY = 'daa_me_id';

export function laesMigId(): string | null {
  try {
    return typeof window !== 'undefined' ? window.localStorage.getItem(MIG_KEY) : null;
  } catch {
    return null;
  }
}

export function gemMigId(id: string | null): void {
  try {
    if (id) window.localStorage.setItem(MIG_KEY, id);
    else window.localStorage.removeItem(MIG_KEY);
  } catch {
    /* localStorage utilgængelig — markeringen gælder kun dette besøg */
  }
}
