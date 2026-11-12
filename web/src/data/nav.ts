// Navigations-model + URL-grammatik for publikums-følgesvenden (ren, uden DOM/fetch, så den
// kan unit-testes uafhængigt af Folgesvend-komponenten).
//
// 'home' = forsiden/landing (brief §6). 'bookmarks' er en konto-klynge-indgang (bmQuick
// "Se alle", spec §3.3). Begge ligger UDEN FOR mega-menuens temaer men indgår i Mode-typen
// så center-switchen i Folgesvend er exhaustive-tjekket af tsc.
// 'soeg' = søgesiden (/soeg?q=); 'ukendtSlaegt' = /slaegt/<slug> med et slug, der ikke findes.
export type Mode = 'home' | 'tree' | 'relate' | 'estates' | 'arms' | 'about' | 'bookmarks' | 'kort' | 'praesens' | 'soeg' | 'ukendtSlaegt';

// Mega-menu-navigationen (brief §3): rygraden er de TRE temaer, ikke enkeltdestinationer.
// Hvert punkt peger på en live Mode, eller null = "kommer" (endnu ikke bygget — vises
// inaktivt men inviterende, brief §3.2). Layoutet rummer den fulde vision nu, så nye views
// kun skal tændes, ikke ombygges. Gruppering efter brief §3.2.
export type ThemeItem = { label: string; mode: Mode | null };
export type Theme = { key: string; label: string; items: ThemeItem[] };
export const THEMES: Theme[] = [
  { key: 'slaegten', label: 'Slægten', items: [
    { label: 'Stamtræ', mode: 'tree' }, { label: 'Slægtskab', mode: 'relate' },
    // Præsenslisten viser levende og er kun for indloggede (decisions.md 2026-11-12, webredesign
    // pkt. 6). Den står ikke i den offentlige menu, før medlemslaget er bygget (fase 8); ruten
    // /praesens findes stadig.
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

// URL-grammatik (webredesign fase 2, overdragelsens tabel »URL'er«). Ren path-routing; vercel.json
// bærer SPA-fallback. Sider, der hører til en slægt, ligger under /slaegt/<slug>; personer,
// slægtskab, søgning og min side ligger over slægterne.
//
//   /                                   hovedsiden
//   /slaegt/<slug>                      slægtens forside (i dag AboutView)
//   /slaegt/<slug>/stamtrae[?fokus=id]  stamtræet; med fokus er personpanelet åbent
//   /slaegt/<slug>/praesens             præsenslisten
//   /slaegt/<slug>/godser[?visning=kort] godser, liste eller oversigtskort
//   /slaegt/<slug>/vaaben               våben
//   /person/<id>                        personen (i dag træ + panel; egen side i fase 3)
//   /gods/<id>                          godset
//   /slaegtskab                         Er vi i familie?
//   /soeg[?q=]                          søgning (uden q: gennemse alle)
//   /min-side/bogmaerker                bogmærker
//
// Gamle stier (/stamtrae, /about, /estates, /estate/<id>, /kort, /arms, /relate, /bookmarks,
// /praesens) forstås stadig, så første render er rigtig, og parseren giver den nye sti som
// `omdiriger`; Folgesvend erstatter dem med replace, så eksisterende links virker.

// Slægterne i Aarbogen. Kun Reventlow i dag; slug er stabilt og bruges i URL'en.
export type Slaegt = { slug: string; navn: string };
export const SLAEGTER: readonly Slaegt[] = [{ slug: 'reventlow', navn: 'Reventlow' }];
export const STANDARD_SLAEGT = 'reventlow';
export function findSlaegt(slug: string | null | undefined): Slaegt | null {
  return SLAEGTER.find((s) => s.slug === slug) ?? null;
}

// Siderne under en slægt: mode ↔ understi (tom = forsiden).
const SLAEGT_SIDE: Partial<Record<Mode, string>> = {
  about: '', tree: 'stamtrae', praesens: 'praesens', estates: 'godser', kort: 'godser', arms: 'vaaben',
};
const SIDE_MODE: Record<string, Mode> = { '': 'about', stamtrae: 'tree', praesens: 'praesens', godser: 'estates', vaaben: 'arms' };
// Sider over slægterne.
const TOP_PATH: Partial<Record<Mode, string>> = { relate: '/slaegtskab', soeg: '/soeg', bookmarks: '/min-side/bogmaerker' };
// Gamle stier → mode (kun til omdirigering).
const GAMMEL_MODE: Record<string, Mode> = {
  stamtrae: 'tree', about: 'about', estates: 'estates', kort: 'kort', arms: 'arms', relate: 'relate', bookmarks: 'bookmarks', praesens: 'praesens',
};

export type ParsedPath = {
  mode: Mode;
  personId: string | null; // fra /person/<id>
  fokusId: string | null; // fra …/stamtrae?fokus=<id>
  estateId: string | null;
  slaegt: string | null; // slug, når stien ligger under /slaegt/<slug>
  q: string | null; // søgeord på /soeg
  omdiriger: string | null; // ny sti for en gammel (replace)
};

export function pathForMode(m: Mode, slug: string = STANDARD_SLAEGT): string {
  if (m === 'home' || m === 'ukendtSlaegt') return '/';
  if (m in SLAEGT_SIDE) {
    const side = SLAEGT_SIDE[m] ?? '';
    const base = `/slaegt/${slug}${side ? `/${side}` : ''}`;
    return m === 'kort' ? `${base}?visning=kort` : base;
  }
  return TOP_PATH[m] ?? '/';
}

export function parseFolgesvendPath(path: string, search = ''): ParsedPath {
  const seg = path.split('/').filter(Boolean).map((x) => decodeURIComponent(x));
  const qs = new URLSearchParams(search);
  const ud = (mode: Mode, x: Partial<ParsedPath> = {}): ParsedPath =>
    ({ mode, personId: null, fokusId: null, estateId: null, slaegt: null, q: null, omdiriger: null, ...x });

  if (seg.length === 0) return ud('home');
  const [s0, s1, s2] = seg;
  if (s0 === 'person' && s1) return ud('tree', { personId: s1 });
  if (s0 === 'gods' && s1) return ud('estates', { estateId: s1 });
  if (s0 === 'slaegtskab') return ud('relate');
  if (s0 === 'soeg') return ud('soeg', { q: qs.get('q') ?? '' });
  if (s0 === 'min-side' && s1 === 'bogmaerker') return ud('bookmarks');
  if (s0 === 'slaegt' && s1) {
    if (!findSlaegt(s1)) return ud('ukendtSlaegt', { slaegt: s1 });
    let mode = SIDE_MODE[s2 ?? ''];
    if (!mode || seg.length > 3) return ud('ukendtSlaegt', { slaegt: s1 });
    if (mode === 'estates' && qs.get('visning') === 'kort') mode = 'kort';
    return ud(mode, { slaegt: s1, fokusId: mode === 'tree' ? qs.get('fokus') || null : null });
  }
  // Gamle stier.
  if (s0 === 'estate' && s1) return ud('estates', { estateId: s1, omdiriger: estatePath(s1) });
  const gammel = GAMMEL_MODE[s0];
  if (gammel && seg.length === 1) {
    const ny = pathForMode(gammel);
    return ud(gammel, { slaegt: gammel in SLAEGT_SIDE ? STANDARD_SLAEGT : null, omdiriger: ny });
  }
  return ud('home');
}

// Id-bærende stier. Et href håndbygges aldrig ved kaldestedet. Ingen kanonisering her:
// Folgesvends sti-effekt kanoniserer et alias-id ved indlæsning (replace).
export function personPath(id: string): string {
  return `/person/${encodeURIComponent(id)}`;
}
export function estatePath(id: string): string {
  return `/gods/${encodeURIComponent(id)}`;
}
export function slaegtPath(slug: string = STANDARD_SLAEGT): string {
  return `/slaegt/${slug}`;
}
// Stamtræet med (valgfri) person i fokus — fokus åbner personpanelet.
export function stamtraePath(slug: string = STANDARD_SLAEGT, fokus?: string | null): string {
  return `/slaegt/${slug}/stamtrae${fokus ? `?fokus=${encodeURIComponent(fokus)}` : ''}`;
}
export function soegPath(q?: string | null): string {
  return q ? `/soeg?q=${encodeURIComponent(q)}` : '/soeg';
}

// Split-skærm (§5): er detalje-panelet åbent? Drevet af URL'en (review 26 anbef. 6: URL ER
// split-tilstanden) — i tree betyder en eksplicit person (/person/<id> eller ?fokus=<id>)
// "detalje åben", mens stamtræet uden fokus (urlPersonId=null) er fuldt træ uden detalje. Relate bevarer sin focusOnly-drevne detalje
// (brief §5.6), så den gates på focusId. Øvrige modes har ingen detalje.
export function detailOpenFor(mode: Mode, urlPersonId: string | null, focusId: string | null): boolean {
  if (mode === 'tree') return urlPersonId !== null;
  if (mode === 'relate') return focusId !== null;
  return false;
}
