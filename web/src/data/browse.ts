// Sidebar-browse-logik (§9.1) som REN funktion — udtrukket af Folgesvend så den kan unit-testes
// DB-uafhængigt (prod-basen kan være tom/reset). Filtrér på query, sortér (navn dansk / fødeår),
// og — kun ved navne-sort uden søgning — gruppér på efternavns-initial med alfabet-hop + sticky
// bogstav-headers. activeLetter filtrerer til ét bogstav (null = Alle).
import { compareDanish, initialOf, sortLetters } from '../lib/collation';
import type { ModelPerson } from './types';

export type BrowseGroup = { letter: string; people: ModelPerson[] };
export type BrowseResult = {
  grouped: boolean;
  flat: ModelPerson[];
  letters: string[];
  groups: BrowseGroup[];
};

export function buildBrowse(
  persons: ModelPerson[],
  query: string,
  sort: 'navn' | 'aar',
  activeLetter: string | null,
  opts?: { linjeByPerson?: Record<string, string>; activeLinje?: string | null },
): BrowseResult {
  // Gren-filter (§9.2) FØRST: begræns til den aktive linjes medlemmer før query/sortering.
  const scoped = opts?.activeLinje && opts.linjeByPerson
    ? persons.filter((p) => opts.linjeByPerson![p.id] === opts.activeLinje)
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

  const byL: Record<string, ModelPerson[]> = {};
  flat.forEach((p) => { (byL[initialOf(p.name)] ??= []).push(p); });
  const letters = sortLetters(Object.keys(byL));
  const groups = letters
    .filter((l) => !activeLetter || l === activeLetter)
    .map((l) => ({ letter: l, people: byL[l] }));
  return { grouped: true, flat, letters, groups };
}
