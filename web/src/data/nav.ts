// Navigations-model + URL-grammatik for publikums-følgesvenden (ren, uden DOM/fetch, så den
// kan unit-testes uafhængigt af Folgesvend-komponenten).
//
// 'home' = forsiden/landing (brief §6). 'bookmarks' er en konto-klynge-indgang (bmQuick
// "Se alle", spec §3.3). Begge ligger UDEN FOR mega-menuens temaer men indgår i Mode-typen
// så center-switchen i Folgesvend er exhaustive-tjekket af tsc.
export type Mode = 'home' | 'tree' | 'relate' | 'estates' | 'arms' | 'about' | 'bookmarks' | 'kort' | 'praesens';

// Mega-menu-navigationen (brief §3): rygraden er de TRE temaer, ikke enkeltdestinationer.
// Hvert punkt peger på en live Mode, eller null = "kommer" (endnu ikke bygget — vises
// inaktivt men inviterende, brief §3.2). Layoutet rummer den fulde vision nu, så nye views
// kun skal tændes, ikke ombygges. Gruppering efter brief §3.2.
export type ThemeItem = { label: string; mode: Mode | null };
export type Theme = { key: string; label: string; items: ThemeItem[] };
export const THEMES: Theme[] = [
  { key: 'slaegten', label: 'Slægten', items: [
    { label: 'Stamtræ', mode: 'tree' }, { label: 'Slægtskab', mode: 'relate' },
    { label: 'Præsensliste', mode: 'praesens' },
    { label: 'Våben', mode: 'arms' }, { label: 'Om slægten', mode: 'about' },
  ] },
  { key: 'godser', label: 'Godser & steder', items: [
    { label: 'Godser', mode: 'estates' }, { label: 'Kort', mode: 'kort' },
    { label: 'Steder (register)', mode: null }, { label: 'Organisationer', mode: null },
  ] },
  { key: 'historie', label: 'Historie', items: [
    { label: 'Artikler', mode: null }, { label: 'Kilder / værker', mode: null },
    { label: 'Tidslinje', mode: null }, { label: 'DAA-udgaver', mode: null },
    { label: 'Billeder', mode: null },
  ] },
];
// Hvilket tema en aktiv mode hører under (fremhæver temaet i den kollapsede bjælke).
// home/bookmarks hører ikke under noget tema → null.
export function themeOfMode(mode: Mode): string | null {
  for (const t of THEMES) if (t.items.some((it) => it.mode === mode)) return t.key;
  return null;
}
// Menu-label for en live mode (fallback-visning for ubyggede center-grene).
export function labelOfMode(mode: Mode): string {
  for (const t of THEMES) for (const it of t.items) if (it.mode === mode) return it.label;
  return '';
}

// URL-grammatik (ren path-routing, /vercel.json bærer SPA-fallback). '/' = forsiden (brief §6,
// landing). '/stamtrae' = stamtræet uden eksplicit fokus (default-person afgøres ved model-load;
// overtog rodens tidligere tree-adfærd da forsiden blev landing). '/person/:id' & '/estate/:id'
// er de to dybe-linkbare mål; øvrige faner har hver deres egen faste sti. Slægtskabs-fanens
// A/B-valg og sidebar-filtre (sort/bogstav/linje) er bevidst UDENFOR URL-scope.
// Faste (id-løse) faners sti — delt tabel så retning (mode→sti) og modstående retning
// (sti→mode, i parseFolgesvendPath) ikke kan komme ud af trit med hinanden (/simplify-fund).
const MODE_PATH: Record<Exclude<Mode, 'home'>, string> = {
  tree: '/stamtrae', estates: '/estates', relate: '/relate', arms: '/arms', about: '/about', bookmarks: '/bookmarks', kort: '/kort', praesens: '/praesens',
};
const PATH_MODE: Record<string, Mode> = Object.fromEntries(Object.entries(MODE_PATH).map(([m, p]) => [p.slice(1), m as Mode]));

export function parseFolgesvendPath(path: string): { mode: Mode; personId: string | null; estateId: string | null } {
  const seg = path.split('/').filter(Boolean);
  if (seg.length === 0) return { mode: 'home', personId: null, estateId: null };
  if (seg[0] === 'person' && seg[1]) return { mode: 'tree', personId: seg[1], estateId: null };
  if (seg[0] === 'estate' && seg[1]) return { mode: 'estates', personId: null, estateId: seg[1] };
  const mode = PATH_MODE[seg[0]];
  return { mode: mode ?? 'home', personId: null, estateId: null };
}
export function pathForMode(m: Mode): string {
  return m === 'home' ? '/' : MODE_PATH[m];
}

// De to id-bærende dybe-links. Egne helpers, så et href aldrig håndbygges ved kaldestedet og
// kan drive fra parseFolgesvendPath (samme begrundelse som MODE_PATH/PATH_MODE-tabellen ovenfor).
// Ingen kanonisering her: Folgesvends path-sync-effekt kanoniserer et alias-id ved indlæsning
// (navigate(…, { replace: true })), så et rå id i et href er sikkert.
export function personPath(id: string): string {
  return `/person/${id}`;
}
export function estatePath(id: string): string {
  return `/estate/${id}`;
}

// Split-skærm (§5): er detalje-panelet åbent? Drevet af URL'en (review 26 anbef. 6: URL ER
// split-tilstanden) — i tree betyder en eksplicit /person/:id "detalje åben", mens /stamtrae
// (urlPersonId=null) er fuldt træ uden detalje. Relate bevarer sin focusOnly-drevne detalje
// (brief §5.6), så den gates på focusId. Øvrige modes har ingen detalje.
export function detailOpenFor(mode: Mode, urlPersonId: string | null, focusId: string | null): boolean {
  if (mode === 'tree') return urlPersonId !== null;
  if (mode === 'relate') return focusId !== null;
  return false;
}
