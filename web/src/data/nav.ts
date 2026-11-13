// Navigations-model + URL-grammatik for publikums-følgesvenden (ren, uden DOM/fetch, så den
// kan unit-testes uafhængigt af Folgesvend-komponenten).
//
// 'home' = hovedsiden. 'person' = personsiden /person/<id>. 'bookmarks' = min side/bogmærker. 'soeg' = søgesiden (/soeg?q=);
// 'ukendtSlaegt' = /slaegt/<slug> med et slug eller en side, der ikke findes. Mode-typen gør
// center-switchen i Folgesvend exhaustive-tjekket af tsc.
export type Mode = 'home' | 'person' | 'tree' | 'relate' | 'estates' | 'arms' | 'about' | 'bookmarks' | 'kort' | 'praesens' | 'soeg' | 'ukendtSlaegt';

// Sidens navn (overskrifter, slægtsbjælken og pladsholderen for ubyggede sider).
const MODE_LABEL: Partial<Record<Mode, string>> = {
  tree: 'Stamtræ', relate: 'Slægtskab', estates: 'Besiddelser', kort: 'Kort over godser', arms: 'Våben',
  about: 'Forside', bookmarks: 'Bogmærker', praesens: 'Præsensliste', soeg: 'Søgning',
};
export function labelOfMode(mode: Mode): string {
  return MODE_LABEL[mode] ?? '';
}

// URL-grammatik (webredesign fase 2, overdragelsens tabel »URL'er«). Ren path-routing; vercel.json
// bærer SPA-fallback. Sider, der hører til en slægt, ligger under /slaegt/<slug>; personer,
// slægtskab, søgning og min side ligger over slægterne.
//
//   /                                   hovedsiden
//   /slaegt/<slug>                      slægtens forside (i dag AboutView)
//   /slaegt/<slug>/stamtrae[?fokus=id]  stamtræet; med fokus er personpanelet åbent
//   /slaegt/<slug>/praesens             præsenslisten
//   /slaegt/<slug>/besiddelser[?visning=kort] besiddelser, liste eller oversigtskort
//   /slaegt/<slug>/vaaben               våben
//   /person/<id>                        personsiden (over slægterne)
//   /besiddelse/<id>                    besiddelsen (gods, gård, len, stamhus …)
//   /slaegtskab[?a=&b=]                 Er vi i familie?
//   /soeg[?q=]                          søgning (uden q: gennemse alle)
//   /min-side/bogmaerker                bogmærker
//
// Gamle stier (/stamtrae, /about, /estates, /estate/<id>, /kort, /arms, /relate, /bookmarks,
// /praesens, og fra før fase 7a /slaegt/<slug>/godser og /gods/<id>) forstås stadig, så første render er rigtig, og parseren giver den nye sti som
// `omdiriger`; Folgesvend erstatter dem med replace, så eksisterende links virker.

// Slægterne i Aarbogen. Kun Reventlow i dag; slug er stabilt og bruges i URL'en.
//
// vaaben: slægtens våben. src er tegningen på slægtens forside, maerke den lille gengivelse i
// slægtsbjælken, slægtsregistret og på personsiden. Aarbogen vælger selv sin tegning; der findes
// ingen dansk instans, der autoriserer adelsvåben (projektejeren 13/11, docs/decisions.md).
// Skift = nye filer i web/public/vaaben/. note er valgfri og vises under den store tegning, når
// der er grund til at skrive noget.
export type SlaegtsVaaben = { src: string; maerke?: string; note?: string };
export type Slaegt = { slug: string; navn: string; vaaben?: SlaegtsVaaben };
export const SLAEGTER: readonly Slaegt[] = [{
  slug: 'reventlow', navn: 'Reventlow',
  vaaben: { src: '/vaaben/reventlow.png', maerke: '/vaaben/reventlow-sepia.png' },
}];
export const STANDARD_SLAEGT = 'reventlow';
export function findSlaegt(slug: string | null | undefined): Slaegt | null {
  return SLAEGTER.find((s) => s.slug === slug) ?? null;
}

// Siderne under en slægt: mode ↔ understi (tom = forsiden).
const SLAEGT_SIDE: Partial<Record<Mode, string>> = {
  about: '', tree: 'stamtrae', praesens: 'praesens', estates: 'besiddelser', kort: 'besiddelser', arms: 'vaaben',
};
// »Besiddelser« (fase 7a, decisions.md 2026-11-13) hed før »godser«; den gamle understi omdirigeres.
const SIDE_MODE: Record<string, Mode> = { '': 'about', stamtrae: 'tree', praesens: 'praesens', besiddelser: 'estates', godser: 'estates', vaaben: 'arms' };
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
  relA: string | null; // /slaegtskab?a=<id>
  relB: string | null; // /slaegtskab?b=<id>
  omdiriger: string | null; // ny sti for en gammel (replace)
};

export function pathForMode(m: Mode, slug: string = STANDARD_SLAEGT): string {
  if (m === 'home' || m === 'ukendtSlaegt' || m === 'person') return '/';
  if (m in SLAEGT_SIDE) {
    const side = SLAEGT_SIDE[m] ?? '';
    const base = `/slaegt/${slug}${side ? `/${side}` : ''}`;
    return m === 'kort' ? `${base}?visning=kort` : base;
  }
  return TOP_PATH[m] ?? '/';
}

export function parseFolgesvendPath(path: string, search = ''): ParsedPath {
  const qs = new URLSearchParams(search);
  const ud = (mode: Mode, x: Partial<ParsedPath> = {}): ParsedPath =>
    ({ mode, personId: null, fokusId: null, estateId: null, slaegt: null, q: null, relA: null, relB: null, omdiriger: null, ...x });
  let seg: string[];
  try {
    seg = path.split('/').filter(Boolean).map((x) => decodeURIComponent(x));
  } catch {
    return ud('ukendtSlaegt'); // ødelagt link (fx »%« uden kode) → »findes ikke«, ikke fejlskærmen
  }

  if (seg.length === 0) return ud('home');
  const [s0, s1, s2] = seg;
  if (s0 === 'person' && s1) return ud('person', { personId: s1 });
  if (s0 === 'besiddelse' && s1) return ud('estates', { estateId: s1 });
  if (s0 === 'slaegtskab') return ud('relate', { relA: qs.get('a') || null, relB: qs.get('b') || null });
  if (s0 === 'soeg') return ud('soeg', { q: qs.get('q') ?? '' });
  if (s0 === 'min-side' && s1 === 'bogmaerker') return ud('bookmarks');
  if (s0 === 'slaegt' && s1) {
    if (!findSlaegt(s1)) return ud('ukendtSlaegt', { slaegt: s1 });
    let mode = SIDE_MODE[s2 ?? ''];
    if (!mode || seg.length > 3) return ud('ukendtSlaegt', { slaegt: s1 });
    if (mode === 'estates' && qs.get('visning') === 'kort') mode = 'kort';
    const omdiriger = s2 === 'godser' ? pathForMode(mode, s1) : null; // gammel understi → én omdirigering
    return ud(mode, { slaegt: s1, fokusId: mode === 'tree' ? qs.get('fokus') || null : null, omdiriger });
  }
  // Gamle stier.
  if ((s0 === 'estate' || s0 === 'gods') && s1) return ud('estates', { estateId: s1, omdiriger: estatePath(s1) });
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
  return `/besiddelse/${encodeURIComponent(id)}`;
}
export function slaegtPath(slug: string = STANDARD_SLAEGT): string {
  return `/slaegt/${slug}`;
}
// Stamtræet med (valgfri) person i fokus — fokus åbner personpanelet.
export function stamtraePath(slug: string = STANDARD_SLAEGT, fokus?: string | null): string {
  return `/slaegt/${slug}/stamtrae${fokus ? `?fokus=${encodeURIComponent(fokus)}` : ''}`;
}
// Er vi i familie? De valgte personer ligger i adressen, så resultatet kan deles og åbnes direkte.
export function slaegtskabPath(a?: string | null, b?: string | null): string {
  const qs = new URLSearchParams();
  if (a) qs.set('a', a);
  if (b) qs.set('b', b);
  const s = qs.toString();
  return s ? `/slaegtskab?${s}` : '/slaegtskab';
}
export function soegPath(q?: string | null): string {
  return q ? `/soeg?q=${encodeURIComponent(q)}` : '/soeg';
}

// Split-skærm (§5): er detalje-panelet åbent? Drevet af URL'en (review 26 anbef. 6: URL ER
// split-tilstanden) — i tree betyder en eksplicit person (/person/<id> eller ?fokus=<id>)
// "detalje åben", mens stamtræet uden fokus (urlPersonId=null) er fuldt træ uden detalje.
// Slægtskab har intet panel længere (fase 6a): vejens trin er links til personsiden.
export function detailOpenFor(mode: Mode, urlPersonId: string | null): boolean {
  return mode === 'tree' && urlPersonId !== null;
}
