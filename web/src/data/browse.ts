// Sidebar-browse-logik (§9.1) som REN funktion — udtrukket af Folgesvend så den kan unit-testes
// DB-uafhængigt (prod-basen kan være tom/reset). Filtrér på query, sortér (navn dansk / fødeår),
// og — kun ved navne-sort uden søgning — gruppér på efternavns-initial med alfabet-hop + sticky
// bogstav-headers. activeLetter filtrerer til ét bogstav (null = Alle).
import { compareDanish, initialOf, sortLetters } from '../lib/collation';
import type { ModelPerson } from './types';

// buildBrowse bruger kun id/name/born — struktureres derfor over et minimalt person-shape, så
// både publikums-`ModelPerson` (Folgesvend) OG redaktørens `RedPerson` (via et `name`-alias)
// kan drive samme testede browse-logik uden duplikering.
export type BrowsePerson = { id: string; name: string; born: number | null };
export type BrowseGroup<P extends BrowsePerson = ModelPerson> = { letter: string; people: P[] };
export type BrowseResult<P extends BrowsePerson = ModelPerson> = {
  grouped: boolean;
  flat: P[];
  letters: string[];
  groups: BrowseGroup<P>[];
};

export function buildBrowse<P extends BrowsePerson>(
  persons: P[],
  query: string,
  sort: 'navn' | 'aar',
  activeLetter: string | null,
  opts?: { linjeByPerson?: Record<string, string[]>; activeLinje?: string | null },
): BrowseResult<P> {
  // Gren-filter (§9.2) FØRST: begræns til den aktive linjes medlemmer før query/sortering. En
  // person kan høre til flere linjer (collapsed grundlægger) → medtag hvis linjen er blandt dem.
  const scoped = opts?.activeLinje && opts.linjeByPerson
    ? persons.filter((p) => (opts.linjeByPerson![p.id] ?? []).includes(opts.activeLinje!))
    : persons;
  const q = query.trim().toLowerCase();
  const pool = q ? scoped.filter((p) => p.name.toLowerCase().includes(q)) : scoped;

  if (sort === 'aar') {
    const flat = [...pool].sort((a, b) => (a.born ?? 9999) - (b.born ?? 9999) || compareDanish(a.name, b.name));
    return { grouped: false, flat, letters: [], groups: [] };
  }

  const flat = [...pool].sort((a, b) => compareDanish(a.name, b.name));
  // Alfabet-hop kun ved navne-sort UDEN søgning.
  if (q) return { grouped: false, flat, letters: [], groups: [] };

  const byL: Record<string, P[]> = {};
  flat.forEach((p) => { (byL[initialOf(p.name)] ??= []).push(p); });
  const letters = sortLetters(Object.keys(byL));
  // Defensivt (review 15 H1): ignorér activeLetter hvis bogstavet ikke findes i den aktuelle
  // pool — ellers giver fx et gren-filter der fjerner bogstavet en blank, låst liste (groups=[]
  // mens flat.length>0, så hverken rækker eller "Ingen træffere" vises). Robust mod ALLE
  // pool-skift-stier (linje/query/sort), ikke kun eksplicit nulstilling i kalder.
  const effectiveLetter = activeLetter && letters.includes(activeLetter) ? activeLetter : null;
  const groups = letters
    .filter((l) => !effectiveLetter || l === effectiveLetter)
    .map((l) => ({ letter: l, people: byL[l] }));
  return { grouped: true, flat, letters, groups };
}

// Søgning-i-træet (§4): afgør om resultat-grid'et skal vises i stedet for selve stamtræet.
// Vises når man aktivt søger (query), filtrerer på bogmærker, eller eksplicit "gennemser hele
// slægten". Whitespace-only query tæller ikke som en søgning.
export function showSearchResults(s: { query: string; bmOnly: boolean; browsing: boolean }): boolean {
  return s.query.trim() !== '' || s.bmOnly || s.browsing;
}
