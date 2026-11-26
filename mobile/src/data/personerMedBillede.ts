// Personer med mindst ét billede, til forsidens minimumskrav (krav 8, spec 2026-11-24-forside-minimumskrav-design.md;
// decisions.md »Forsiden tæller nu billeder som indhold … Mobilens forside følger i #457«). Web henter sættet med en
// egen forespørgsel (relation 'afbildet' + de media-rækker, læseren må se, kanoniseret); mobilen har præcis de data i
// aux.mediaBy fra opstarten (samme relationer, RLS-filtrerede media-rækker, nøglet på den kanoniske id), så der kommer
// intet nyt kald. Mislykkes media-hentningen, fælder den hele indlæsningen; findes aux, er sættet altså komplet og ikke
// »ukendt«.
import type { Aux } from './types';

export function personerMedBillede(aux: Pick<Aux, 'mediaBy'>): ReadonlySet<string> {
  return new Set(Object.keys(aux.mediaBy).filter((pid) => (aux.mediaBy[pid]?.length ?? 0) > 0));
}
