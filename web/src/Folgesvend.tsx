// Publikums-følgesvend (web) — port af design/project/Reventlow-web-v2.dc.html,
// layout siden opdateret efter Reventlow-web-v3.dc.html (søg/gennemse som modalt overlay
// i stedet for en permanent sidebar, så stamtræ + detalje-panel deler hele skærmen).
// Header-nav · center-visning · detalje-panel. To visninger bygget: Stamtræ
// (variant A, fokus-centreret) og Slægtskab ("Er vi i familie?", med multi-linje + konfidens
// + korroboration fra den porterede finder). Godser/Våben/Om/Kort/Bogmærker følger.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { navigate, usePath } from './router';
import { childrenOf, loadModel, parentsOf } from './data/model';
import { buildBidirectionalColumns } from './data/tree';
import { initials, konfTekst } from './data/format';
import { computeRelationship, type RelationResult } from './data/relationship';
import { fetchArms, fetchAbout, fetchEstates, fetchEstateInfo, fetchEstateOwners, fetchPersonDetail, type AboutSection, type ArmsItem, type EstateInfo, type EstateItem, type EstateOwner, type PersonDetailData } from './data/public';
import { pickPortrait, firstSignable, withUrl } from './data/media';
import type { Geo, LinjeEntry, Model } from './data/types';
import { estatePoints, filterByLineage, lifeJourney } from './data/geoSelectors';
import { NarrativRenderer } from './components/NarrativRenderer';
import { buildBrowse, showSearchResults, type BrowseResult } from './data/browse';
import { useBookmarks, type BookmarkSort } from './data/bookmarks';
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
import { BookmarksView } from './components/BookmarksView';
import { SlaegtPicker } from './components/SlaegtPicker';
import { HomeView } from './components/HomeView';
import { THEMES, themeOfMode, labelOfMode, parseFolgesvendPath, pathForMode, detailOpenFor, type Mode } from './data/nav';
import { GeoMap } from './components/GeoMap';
import { ExpandableMiniMap } from './components/MapLightbox';
import { ViewHeader, Avatar, BookmarkFlag, MediaThumb, SearchIcon, Crest, PersonCard } from './components/primitives';
import { Lightbox } from './components/Lightbox';
import { T } from './theme';

// Kun Reventlow findes i dag; vælgeren er 1-punkt + "flere kommer"-note (spec §2 ikke-mål).
const SLAEGTER = [{ id: 'reventlow', navn: 'Reventlow' }];
// Mode/THEMES/routing bor i ./data/nav (ren + unit-testet).
function useFonts() {
  useEffect(() => {
    if (document.getElementById('daa-pub-fonts')) return;
    const l = document.createElement('link');
    l.id = 'daa-pub-fonts'; l.rel = 'stylesheet';
    l.href = 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500;1,600&family=Hanken+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap';
    document.head.appendChild(l);
    const s = document.createElement('style'); s.textContent = '*{box-sizing:border-box}body{margin:0}input{font-family:inherit}';
    document.head.appendChild(s);
  }, []);
}

export default function Folgesvend() {
  useFonts();
  const path = usePath();
  const [model, setModel] = useState<Model | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // mode/focusId/estateId initialiseres SYNKRONT fra URL'en ved mount (parseFolgesvendPath er
  // ren streng-parsing, kræver ikke modellen) — undgår et synligt "flash" af startFokus's default
  // før et gyldigt URL-id kan overtage. Validering (findes id'et? kanonisk id?) OG al senere
  // synkronisering (egen navigation såvel som browserens back/forward) sker i den path-drevne
  // effekt nedenfor, der reagerer på usePath() — se dens kommentar.
  const initialPath = parseFolgesvendPath(window.location.pathname);
  const [mode, setMode] = useState<Mode>(() => initialPath.mode);
  const [focusId, setFocusId] = useState<string | null>(() => initialPath.personId);
  const [query, setQuery] = useState('');
  const [browseSort, setBrowseSort] = useState<'navn' | 'aar'>('navn'); // sidebar-sortering (§9.1)
  const [activeLetter, setActiveLetter] = useState<string | null>(null); // alfabet-filter (null = Alle)
  const [activeLinje, setActiveLinje] = useState<string | null>(null); // gren-filter (§9.2, null = hele slægten)
  // Søgning-i-træet (§4): bmOnly = bogmærke-filter, browsing = "gennemse hele slægten" uden query,
  // searchFocusToken = bump-signal så header-⌕/forsiden kan fokusere tree-søgefeltet.
  const [bmOnly, setBmOnly] = useState(false);
  const [browsing, setBrowsing] = useState(false);
  const [searchFocusToken, setSearchFocusToken] = useState(0);
  // Forrige fokus-person (kun til "◄ Tilbage til X"-labelen) — ÉN værdi, ikke en fuld stak:
  // selve tilbage-navigationen er nu browserens rigtige back-knap (window.history.back()),
  // som allerede har sin egen fulde historik. prevFocusId sættes kun af navigateTree (en
  // "rigtig" navigation), ikke af focusOnly/driftFocus (Slægtskabs-fokus / Kolonner-drill).
  const [prevFocusId, setPrevFocusId] = useState<string | null>(null);
  // "Mig" i slægten (PoC: localStorage; flyttes til profiles.reventlow_person_id ved login).
  const [meId, setMeId] = useState<string | null>(() => (typeof window !== 'undefined' ? window.localStorage.getItem('daa_me_id') : null));
  // Konto-bogmærker (spec 2026-07-06): login-eksklusiv session. "Mig" (ovenfor) forbliver
  // lokal/udskudt migration — denne session bruges KUN til bogmærker her.
  const [session, setSession] = useState<RedSession | null>(null);
  const [loginOpen, setLoginOpen] = useState(false);
  const [login, setLogin] = useState<{ email: string; pw: string; err: string; busy: boolean }>(
    { email: '', pw: '', err: '', busy: false },
  );
  useEffect(() => {
    // review 22 N3: currentSession() kan i princippet afvises (netværksfejl) — sluges ikke
    // tavst, men sætter session til null (allerede default) og logger til konsol.
    currentSession().then(setSession, (e) => console.warn('[session] kunne ikke genskabes', e));
  }, []);
  const doLogin = async () => {
    if (login.busy) return; // review 22 N3: forhindr overlappende signIn-kald ved dobbelt-klik
    if (!login.email.trim() || !login.pw) { setLogin((l) => ({ ...l, err: 'Udfyld e-mail og adgangskode' })); return; }
    setLogin((l) => ({ ...l, busy: true, err: '' }));
    try {
      const s = await signIn(login.email, login.pw);
      setSession(s);
      setLoginOpen(false);
      setLogin({ email: '', pw: '', err: '', busy: false });
    } catch (e) {
      setLogin((l) => ({ ...l, busy: false, err: e instanceof Error ? e.message : 'Login fejlede' }));
    }
  };
  const doLogout = async () => { await signOut(); setSession(null); };
  const [relA, setRelA] = useState<string | null>(null);
  const [relB, setRelB] = useState<string | null>(null);
  const [relSlot, setRelSlot] = useState<'A' | 'B'>('A');
  const [estates, setEstates] = useState<EstateItem[] | null>(null);
  const [arms, setArms] = useState<ArmsItem[] | null>(null);
  const [about, setAbout] = useState<AboutSection[] | null>(null);
  const [estateId, setEstateId] = useState<string | null>(() => initialPath.estateId);
  const [estateOwners, setEstateOwners] = useState<EstateOwner[]>([]);
  const [estateInfo, setEstateInfo] = useState<EstateInfo | null>(null);
  const [detail, setDetail] = useState<PersonDetailData | null>(null);

  useEffect(() => {
    loadModel().then(setModel).catch((e) => setErr(describeErr(e)));
  }, []);

  // Resolv et (evt. alias-)id til dets kanoniske (samme_som-collapse). canonicalIdById bor på
  // modellen; alle indgående id'er (fokus, rel, mig) resolves gennem det. Memoized på
  // canonicalIdById (ikke model) — /simplify-fund: en ustabil canon-reference hver render fik
  // useBookmarks' re-normaliserings-useEffect til at genkøre unødigt ved hvert tastetryk.
  const canon = useCallback((id: string) => model?.canonicalIdById?.[id] ?? id, [model?.canonicalIdById]);
  const meCanon = meId ? canon(meId) : null;
  // Bogmærker (web v3 Slice 1) — localStorage, kanonisk via canon(). bmSort default 'linje'
  // (designets første segment, spec §4). slaegtOpen = slægt-vælger-modal på header-chippen.
  const bookmarks = useBookmarks(session?.userId ?? null, canon);
  const saveOrPrompt = useCallback(
    (id: string) => { if (bookmarks.canSave) bookmarks.toggle(id); else setLoginOpen(true); },
    [bookmarks],
  );
  const [bmSort, setBmSort] = useState<BookmarkSort>('linje');
  const [slaegtOpen, setSlaegtOpen] = useState(false);
  // Stabil array-reference til BookmarksView — /simplify-fund: [...bookmarks.ids] i JSX'et
  // nedenfor gav en NY array hvert render, hvilket ville nulstille en useMemo i BookmarksView.
  const bookmarkIds = useMemo(() => [...bookmarks.ids], [bookmarks.ids]);

  // Estates hentes eager (én gang) — bruges både af godser-visningen OG sidebar-statistikkens
  // "godser"-tæller. Én pagineret query; billig nok til mount.
  useEffect(() => { if (!estates) fetchEstates().then(setEstates).catch(() => setEstates([])); }, [estates]);
  // URL'en pegede evt. på et gods-id (deep link) — valider det så snart listen er hentet;
  // et forældet/forkert id falder pænt tilbage til gods-listen i stedet for en tom detaljevisning.
  useEffect(() => {
    if (estates && estateId && !estates.some((e) => e.id === estateId)) {
      setEstateId(null);
      navigate('/estates', { replace: true });
    }
  }, [estates, estateId]);
  useEffect(() => { if (mode === 'arms' && !arms) fetchArms().then(setArms).catch(() => setArms([])); }, [mode, arms]);
  useEffect(() => { if (mode === 'about' && !about) fetchAbout().then(setAbout).catch(() => setAbout([])); }, [mode, about]);
  // Gods-detalje-fetches (review 15 M3): cancelled-guard så en sen resolver for gods A ikke
  // permanent overskriver gods B's data, når man skifter gods hurtigt.
  useEffect(() => {
    if (!estateId) return;
    let cancelled = false;
    setEstateOwners([]);
    fetchEstateOwners(estateId, model).then((o) => { if (!cancelled) setEstateOwners(o); }).catch(() => { if (!cancelled) setEstateOwners([]); });
    return () => { cancelled = true; };
  }, [estateId, model]);
  useEffect(() => {
    if (!estateId) return;
    let cancelled = false;
    setEstateInfo(null);
    fetchEstateInfo(estateId).then((info) => { if (!cancelled) setEstateInfo(info); }).catch(() => { if (!cancelled) setEstateInfo({ narrativ: '', sted: '', media: [] }); });
    return () => { cancelled = true; };
  }, [estateId]);
  // Detalje (bio/embeder/godser) for fokus-personen — til højre-panelet.
  useEffect(() => {
    if (!focusId) { setDetail(null); return; }
    setDetail(null);
    // Foldet person: hent detalje for ALLE medlems-id'er (narrativ/relationer unioneres — spec §8).
    const members = model?.byId[focusId]?.mergedFrom?.map((m) => m.personId);
    fetchPersonDetail(focusId, members).then(setDetail).catch(() => setDetail({ bio: '', offices: [], estates: [], media: [] }));
  }, [focusId, model]);

  const persons = model?.persons ?? [];
  const linjeList = model?.lineage?.list ?? [];
  // Browse-listen (§9.1) + gren-filter (§9.2) — al logik i buildBrowse (ren + testet).
  // bmOnly (§4/§9.e) filtrerer kilde-personerne til bogmærkede før browse-logikken. bmDep gør at
  // et bogmærke-toggle KUN re-kører browse når filteret faktisk er tændt (ellers stabil null).
  const bmDep = bmOnly ? bookmarkIds : null;
  const browse = useMemo(() => {
    const bmSet = bmDep ? new Set(bmDep) : null;
    const src = bmSet ? persons.filter((p) => bmSet.has(p.id)) : persons;
    return buildBrowse(src, query, browseSort, activeLetter, { linjeByPerson: model?.lineage?.byPerson, activeLinje });
  }, [persons, model, query, browseSort, activeLetter, activeLinje, bmDep]);

  const rel = useMemo(() => (model && relA && relB ? computeRelationship(model, relA, relB) : null), [model, relA, relB]);

  // Navigér til en person i STAMTRÆET — kanoniserer id'et, tvinger mode til 'tree' (matcher
  // hvordan et sidebar-/detalje-panel-klik altid har betydet "vis denne person i træet",
  // uanset hvilken fane man kom fra) og pusher en NY browser-historik-post. URL'en ER nu
  // selve tilbage-stakken — DetailPanel's "◄ Tilbage" er blot window.history.back().
  // Rydder søge-resultaterne (§4): de tre flag der driver showSearchResults. Linje-/bogstav-
  // filtre er browse-præferencer og bevares (og er alligevel uden effekt når resultaterne skjules).
  const clearSearch = () => { setQuery(''); setBmOnly(false); setBrowsing(false); };
  const navigateTree = (id: string) => {
    const cid = canon(id);
    const prev = focusId && focusId !== cid ? focusId : null;
    setPrevFocusId(prev);
    setFocusId(cid);
    setMode('tree');
    clearSearch(); // en "rigtig" navigation lader personen blive centrum i træet; resultat-grid'et viger (§4.1)
    navigate(`/person/${cid}`, { state: { prevFocusId: prev } });
  };
  // Fokus-skift UDEN navigation — bruges hvor det AKTUELLE mode bevidst skal bevares og ikke
  // bør ligge i URL'en: Slægtskabs-fanens "trin for trin"-liste (relate er udenfor URL-scope,
  // jf. plan) og detalje-panelets links mens man er i Slægtskab-mode.
  const focusOnly = (id: string) => setFocusId(canon(id));
  // Kolonner-variantens ane/efterkommer-drill (TreeView's onFocus): opdaterer URL'en så den
  // forbliver delbar, men UDEN en ny back-entry pr. generations-trin — samme "ingen historik
  // ved drill"-regel som før, nu udtrykt som en URL-replace i stedet for et no-op på et
  // separat back-stack.
  const driftFocus = (id: string) => {
    const cid = canon(id);
    setFocusId(cid);
    navigate(`/person/${cid}`, { replace: true, state: { prevFocusId } });
  };
  // Mega-menu (brief §3): hover-udfoldning med lille intent-delay så bjælken ikke "blafrer".
  const [megaOpen, setMegaOpen] = useState(false);
  const megaTimer = useRef<number | null>(null);
  const openMega = () => { if (megaTimer.current) clearTimeout(megaTimer.current); megaTimer.current = window.setTimeout(() => setMegaOpen(true), 120); };
  const closeMega = () => { if (megaTimer.current) { clearTimeout(megaTimer.current); megaTimer.current = null; } setMegaOpen(false); };
  useEffect(() => () => { if (megaTimer.current) clearTimeout(megaTimer.current); }, []);

  // Fane-skift (mega-menu + detalje-panelets "Sæt i fokus"/"Find slægtskab"-knapper).
  const goToMode = (m: Mode) => {
    closeMega();
    setMode(m);
    if (m === 'estates') setEstateId(null);
    navigate(m === 'tree' && focusId ? `/person/${focusId}` : pathForMode(m));
  };
  const backName = prevFocusId && model ? (model.byId[prevFocusId]?.name ?? null) : null;

  // Synkroniserer mode/focusId/estateId/prevFocusId med den AKTUELLE URL (usePath() reagerer
  // BÅDE på egne navigate()-kald OG på browserens back/forward — /simplify-fund: erstatter en
  // hånd-rullet window.addEventListener('popstate', …) med den delte hook router.ts allerede
  // eksponerer til formålet). Kører også første gang modellen bliver klar (null → model), hvor
  // den validerer/kanoniserer et evt. URL-id og retter URL'en hvis nødvendigt (alias/ugyldigt id)
  // — samme arbejde mount-effekten lavede før, nu ét sted for både mount og efterfølgende navigation.
  useEffect(() => {
    if (!model) return;
    const p = parseFolgesvendPath(path);
    setMode(p.mode);
    setEstateId(p.estateId);
    setPrevFocusId((window.history.state as { prevFocusId?: string | null } | null)?.prevFocusId ?? null);
    if (p.mode !== 'tree') return;
    if (!p.personId) {
      // /stamtrae bærer ikke selv et fokus-id. Split-skærm (§5): når man LUKKER detaljen navigeres
      // hertil, og træet skal blive stående på samme centrum — så bevar et allerede sat focusId og
      // fald kun tilbage til det deterministiske startFokus ved kold start (matcher altid samme
      // person for samme model).
      setFocusId((cur) => cur ?? startFokus(model));
      return;
    }
    const cid = canon(p.personId);
    if (model.byId[cid]) {
      setFocusId(cid);
      if (cid !== p.personId) navigate(`/person/${cid}`, { replace: true }); // alias → kanonisk
    } else {
      setFocusId(startFokus(model));
      navigate(pathForMode('tree'), { replace: true }); // ugyldigt/slettet id — forkast til default-tree frem for at foregive et gæt
    }
  }, [path, model, canon]);

  // Split-skærm (§5): detalje-panelet er åbent når URL'en bærer en eksplicit person (tree) /
  // et fokus er inspiceret (relate). closeDetail navigerer til /stamtrae (replace) — træets centrum
  // bevares (se path-sync ovenfor), kun detaljen viger. Escape lukker også.
  const detailOpen = detailOpenFor(mode, parseFolgesvendPath(path).personId, focusId);
  const closeDetail = () => navigate(pathForMode('tree'), { replace: true });
  // Klik på den allerede-valgte person i træet lukker detaljen igen (brief §5.2); ellers navigér.
  const treePick = (id: string) => { if (detailOpen && canon(id) === focusId) closeDetail(); else navigateTree(id); };
  // Escape lukker KUN tree-detaljen (relate har ingen luk-til-tree — dual-review M6), og kun når
  // Escape ikke allerede "ejes" af et tekstfelt (dual-review M5-sekundær) eller et overliggende
  // overlay som billede-lightboxen, der har sin egen Escape (dual-review M5-primær).
  useEffect(() => {
    if (!detailOpen || mode !== 'tree') return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) return;
      if (document.querySelector('[data-overlay]')) return;
      closeDetail();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [detailOpen, mode]);

  // "Det er mig"-markering (localStorage) — samme person igen = fjern markering. Gemmer kanonisk id,
  // og sammenligner kanonisk (et gemt alias-meId matcher stadig den kanoniske person).
  const toggleMe = (id: string) => {
    const cid = canon(id);
    const next = meId && canon(meId) === cid ? null : cid;
    setMeId(next);
    if (next) window.localStorage.setItem('daa_me_id', next);
    else window.localStorage.removeItem('daa_me_id');
  };

  // Bogmærke-række → tree-nav (Codex BLOCKER-fix, spec §3.3): detalje-panelet vises kun i
  // tree/relate, så et klik fra bookmarks-mode ville ellers være visuelt resultatløst.
  const pickBookmark = (id: string) => navigateTree(id);

  // Fælles resultat-valg for tree-søgningen (§4) OG relate-A/B-valg (§5.6): i relate fylder et
  // valg den aktive plads (og rydder søgningen så A/B + sti vises igen), ellers navigerer/centrerer
  // det træet (navigateTree rydder selv). Delt så begge modes bruger samme søge-personkort.
  const pickPerson = (id: string) => {
    const cid = canon(id);
    if (mode === 'relate') {
      if (relSlot === 'A') { setRelA(cid); setRelSlot('B'); } else { setRelB(cid); setRelSlot('A'); }
      clearSearch();
    } else {
      navigateTree(cid);
    }
  };

  if (err) return <div style={{ fontFamily: T.sans, padding: 40, color: T.bordeaux, whiteSpace: 'pre-wrap' }}>{err}</div>;
  const activeTheme = themeOfMode(mode); // aktivt tema for den kollapsede bjælke — beregnes én gang

  // Søgning-i-træet (§4): bundtet der driver TreeSearch. showResults afgør resultat-grid vs. træ;
  // valg af et resultat rydder søgningen og centrerer træet på personen (brief §4.1).
  const bumpSearchFocus = () => setSearchFocusToken((t) => t + 1);
  const treeSearch: TreeSearchBundle = {
    query, setQuery,
    browse,
    sort: browseSort, setSort: setBrowseSort,
    activeLetter, setActiveLetter,
    linjeList, activeLinje, setActiveLinje,
    bmOnly, setBmOnly, hasBookmarks: bookmarkIds.length > 0,
    browsing, setBrowsing,
    showResults: showSearchResults({ query, bmOnly, browsing }), clearSearch,
    focusToken: searchFocusToken, resetFocus: () => setSearchFocusToken(0),
    onPick: pickPerson, // tree → navigateTree (centrerer+rydder); relate → fylder A/B-plads (§5.6)
  };

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.pageBg, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      {/* Header — mega-menu-navigation (brief §3): kollapset bjælke hvis rygrad er de tre
          temaer; folder sig ud på hover til en mega-menu med større logo + status-mærkede
          punkter (live ✓ / kommer). Udskudt til Fase 2: redigér-knap (inline-redigering). */}
      <div onMouseEnter={openMega} onMouseLeave={closeMega} style={{ flex: 'none', position: 'relative', zIndex: 30 }}>
        <div style={{ height: 66, display: 'flex', alignItems: 'center', gap: 22, padding: '0 26px', background: T.paper, borderBottom: '1px solid rgba(34,31,26,.1)' }}>
        {/* Lille logo i bjælken — crossfader ud når mega-menuen folder ud, så det store logo
            i panelet "vokser frem" fra samme plads (ét logo, ikke to synlige på én gang). */}
        <div onClick={() => goToMode('home')} title="Til forsiden" style={{ display: 'flex', alignItems: 'center', gap: 13, flex: 'none', cursor: 'pointer', transition: 'opacity .22s ease', opacity: megaOpen ? 0 : 1, pointerEvents: megaOpen ? 'none' : 'auto' }}>
          <img src="/daf-logo.png" alt="Dansk Adels Forening" style={{ width: 40, height: 40, objectFit: 'contain' }} />
          <div>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600, lineHeight: 1, color: T.ink }}>Danmarks Adels Aarbog</div>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.16em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Følgesvend · Dansk Adels Forening</div>
          </div>
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
          {THEMES.map((t) => {
            const active = activeTheme === t.key;
            return (
              <div key={t.key} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '9px 16px', borderRadius: 9, fontFamily: T.sans, fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', color: active ? T.bordeaux : '#3d382f' }}>
                {t.label}<span style={{ fontSize: 9, color: active ? T.bordeaux : T.muted2 }}>▾</span>
              </div>
            );
          })}
        </div>
        <div style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 12 }}>
          {/* Søg-knap — åbner søg/gennemse-modalen (v3: erstatter den permanente sidebar). */}
          <div onClick={() => { goToMode('tree'); bumpSearchFocus(); }} title="Søg &amp; gennemse personer" style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '7px 13px', cursor: 'pointer' }}>
            <SearchIcon size={15} />
            <span style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: '#3d382f' }}>Søg</span>
          </div>
          {/* Slægt-chip — åbner slægt-vælger-modal (kosmetisk, kun Reventlow findes — spec §3.3). */}
          <div onClick={() => setSlaegtOpen(true)} style={{ display: 'flex', alignItems: 'center', gap: 9, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '6px 12px', cursor: 'pointer' }}>
            <span style={{ width: 26, height: 26, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', boxShadow: 'inset 0 0 0 2px #f4efe6, inset 0 0 0 2.5px rgba(136,26,51,.28)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>R</span>
            <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.ink }}>Reventlow</span>
            <span style={{ fontSize: 10, color: T.muted2 }}>▾</span>
          </div>
          {/* Konto-indikator (bogmærke-login) — minimal, ikke en fuld kontoflade (spec §6). */}
          {session ? (
            <div onClick={() => { void doLogout(); }} title={session.email} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.muted, cursor: 'pointer' }}>Log ud</div>
          ) : (
            <div onClick={() => setLoginOpen(true)} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>Log ind</div>
          )}
          {meCanon && model?.byId[meCanon] && (
            <div onClick={() => navigateTree(meCanon)} title="Din plads i slægten" style={{ width: 38, height: 38, borderRadius: '50%', background: '#f8ecef', border: `1.5px solid ${T.bordeaux}`, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', fontFamily: T.serif, fontSize: 15, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(model.byId[meCanon].name)}</div>
          )}
          <a href="/redaktion" onClick={(e) => { e.preventDefault(); navigate('/redaktion'); }} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux, textDecoration: 'none' }}>Redaktion ↗</a>
        </div>
        </div>

        {/* Mega-menu — folder ud på hover (brief §3.1): større logo-lockup + tematiserede
            kolonner med live ✓ / kommer-status. */}
        {/* Panelet er altid monteret men transition-styret (opacity/translateY/pointer-events),
            så det folder blødt ud OG ind ("værket åbner sig", brief §3.1) frem for at poppe. */}
          <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, background: T.paper, borderBottom: '1px solid rgba(34,31,26,.12)', boxShadow: '0 26px 46px rgba(20,17,13,.14)', padding: '32px 44px 38px', display: 'flex', gap: 44, transition: 'opacity .28s ease, transform .28s ease', opacity: megaOpen ? 1 : 0, transform: megaOpen ? 'translateY(0)' : 'translateY(-10px)', pointerEvents: megaOpen ? 'auto' : 'none' }}>
            <div style={{ flex: 'none', width: 274, borderRight: '1px solid rgba(34,31,26,.1)', paddingRight: 40 }}>
              {/* Samme logo som bjælkens — skalerer fra .62 (≈40px, bjælke-størrelse) op til 1
                  (64px), så det læses som ét logo der vokser frem, ikke en anden kopi. */}
              <div onClick={() => goToMode('home')} title="Til forsiden" style={{ cursor: 'pointer' }}>
                <img src="/daf-logo.png" alt="Dansk Adels Forening" style={{ width: 64, height: 64, objectFit: 'contain', transition: 'transform .28s ease', transform: megaOpen ? 'scale(1)' : 'scale(.62)', transformOrigin: 'top left' }} />
                <div style={{ fontFamily: T.serif, fontSize: 26, fontWeight: 600, color: T.ink, lineHeight: 1.05, marginTop: 14 }}>Danmarks Adels Aarbog</div>
              </div>
              <div style={{ fontFamily: T.sans, fontSize: 12.5, color: T.muted, marginTop: 6, lineHeight: 1.45 }}>Følgesvend · Dansk Adels Forening. En digital ledsager til det trykte værk.</div>
              <div onClick={() => goToMode('home')} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 16, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>‹ Til forsiden</div>
            </div>
            <div style={{ flex: 1, display: 'flex', gap: 32 }}>
              {THEMES.map((t) => (
                <div key={t.key} style={{ flex: 1 }}>
                  <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.18em', textTransform: 'uppercase', color: T.gold, paddingBottom: 10, borderBottom: '1px solid rgba(34,31,26,.1)' }}>{t.label}</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 1, marginTop: 10 }}>
                    {t.items.map((it) => {
                      const live = it.mode !== null;
                      const active = it.mode === mode;
                      return (
                        <div key={it.label} onClick={() => { if (it.mode) goToMode(it.mode); }} title={live ? '' : 'Kommer'} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: active ? T.bordeaux : (live ? T.ink : T.muted3), padding: '6px 0', cursor: live ? 'pointer' : 'default' }}>
                          <span>{it.label}</span>
                          {live
                            ? <span style={{ fontFamily: T.mono, fontSize: 9, color: active ? T.bordeaux : '#1f8a5b' }}>✓</span>
                            : <span style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted3 }}>kommer</span>}
                        </div>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>
      </div>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>

        {/* Center */}
        <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto' }}>
          {mode === 'home' ? <HomeView model={model} personCount={persons.length} estates={estates} onPickPerson={navigateTree} onOpenSearch={() => { goToMode('tree'); bumpSearchFocus(); }} onBrowseAll={() => { goToMode('tree'); setBrowsing(true); }} onOpenEstate={(id) => { setEstateId(id); navigate(`/estate/${id}`); }} onGoTree={() => goToMode('tree')} />
            : mode === 'tree' ? <TreeView model={model} focusId={focusId} onPick={treePick} onFocus={driftFocus} hasBookmark={bookmarks.has} onToggleBookmark={saveOrPrompt} search={treeSearch} />
            : mode === 'relate' ? <RelateView model={model} rel={rel} relA={relA} relB={relB} slot={relSlot} setSlot={setRelSlot} onPickStep={focusOnly} meId={meCanon} onSetMeA={() => { if (meCanon) { setRelA(meCanon); setRelSlot('B'); } }} search={treeSearch} />
            : mode === 'estates' ? <EstatesView estates={estates} estateId={estateId} estate={estates?.find((e) => e.id === estateId) ?? null} info={estateInfo} owners={estateOwners} geo={model?.geo} onOpen={(id) => { setEstateId(id); navigate(`/estate/${id}`); }} onBack={() => { setEstateId(null); navigate('/estates'); }} onPickOwner={navigateTree} />
            : mode === 'arms' ? <ArmsView arms={arms} />
            : mode === 'about' ? <AboutView about={about} personCount={persons.length} estateCount={estates?.length ?? null} onPick={navigateTree} />
            : mode === 'bookmarks' ? (model ? <BookmarksView model={model} ids={bookmarkIds} sort={bmSort} setSort={setBmSort} onPick={pickBookmark} onRemove={saveOrPrompt} loggedIn={bookmarks.canSave} onRequireLogin={() => setLoginOpen(true)} /> : <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>)
            : mode === 'kort' ? <OverviewMapView model={model} onPickPerson={navigateTree} onPickEstate={(id) => navigate(`/estate/${id}`)} />
            : <Placeholder label={labelOfMode(mode)} />}
        </div>

        {/* Højre: person-detalje (kun i person-centriske visninger) */}
        {detailOpen && model && focusId && (
          <DetailPanel
            model={model} focusId={focusId} detail={detail} onPick={mode === 'tree' ? navigateTree : focusOnly}
            backName={backName} onBack={() => window.history.back()} onClose={mode === 'tree' ? closeDetail : undefined}
            onFocusTree={() => goToMode('tree')}
            onRelate={() => { setRelA(focusId); setRelB(null); setRelSlot('B'); goToMode('relate'); }}
            isMe={focusId === meCanon} onToggleMe={() => toggleMe(focusId)}
            isBookmarked={bookmarks.has(focusId)} onToggleBookmark={() => saveOrPrompt(focusId)}
          />
        )}
      </div>

      <SlaegtPicker open={slaegtOpen} slaegter={SLAEGTER} activeId="reventlow" onClose={() => setSlaegtOpen(false)} onPick={() => setSlaegtOpen(false)} />

      {loginOpen && (
        <div onClick={() => setLoginOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(20,17,13,.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ width: 380, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '22px 24px 20px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>Log ind</div>
            <div style={{ fontSize: 12, color: T.muted, marginTop: 3, marginBottom: 15 }}>Log ind for at gemme bogmærker på tværs af dine enheder.</div>
            <input value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} placeholder="din@email.dk" style={{ width: '100%', fontSize: 13, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none' }} />
            <input value={login.pw} type="password" onChange={(e) => setLogin((l) => ({ ...l, pw: e.target.value }))} style={{ width: '100%', fontSize: 13, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none', marginTop: 11 }} />
            {login.err && <div style={{ fontSize: 11.5, color: T.bordeaux, marginTop: 9 }}>{login.err}</div>}
            <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end' }}>
              <div onClick={() => setLoginOpen(false)} style={{ fontSize: 12, fontWeight: 600, color: T.muted, padding: '8px 13px', cursor: 'pointer' }}>Annullér</div>
              <div onClick={doLogin} style={{ fontSize: 12, fontWeight: 600, color: '#fbf8f1', background: T.bordeaux, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>{login.busy ? 'Logger ind…' : 'Log ind'}</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Placeholder({ label }: { label: string }) {
  return <div style={{ padding: 40, fontFamily: T.serif, fontSize: 22, color: T.muted }}>{label} — visningen porteres som næste skive.</div>;
}

// ---- Stamtræ (variant A "Fokus" + variant B "Kolonner") ----
// Søgning-i-træet (§4): søgefelt + universel-klart fane-bånd + browse-værktøjer + resultat-grid
// som personkort. Bundtet (state + handlers) ejes af Folgesvend og deles af TreeView (onPick =
// centrér træet) og RelateView (onPick = fyld A/B-plads, §5.6). `showResults` gater om
// resultaterne eller selve fladen (træ / A-B-sti) vises.
export type TreeSearchBundle = {
  query: string; setQuery: (s: string) => void;
  browse: BrowseResult;
  sort: 'navn' | 'aar'; setSort: (s: 'navn' | 'aar') => void;
  activeLetter: string | null; setActiveLetter: (l: string | null) => void;
  linjeList: LinjeEntry[]; activeLinje: string | null; setActiveLinje: (l: string | null) => void;
  bmOnly: boolean; setBmOnly: (b: boolean) => void; hasBookmarks: boolean;
  browsing: boolean; setBrowsing: (b: boolean) => void;
  showResults: boolean; clearSearch: () => void;
  focusToken: number; resetFocus: () => void;
  onPick: (id: string) => void;
};

const SEARCH_TABS: { key: string; label: string; live: boolean }[] = [
  { key: 'personer', label: 'Personer', live: true },
  { key: 'godser', label: 'Godser', live: false },
  { key: 'steder', label: 'Steder', live: false },
  { key: 'artikler', label: 'Artikler', live: false },
];

function TreeSearch(s: TreeSearchBundle) {
  const inputRef = useRef<HTMLInputElement>(null);
  // Consume-and-reset (dual-review M1): fokusér ved et bump og nulstil straks tokenet, ellers ville
  // TreeSearch (der re-mountes ved hvert mode-skift) stjæle fokus på ENHVER senere tree/relate-entry
  // — fx når man klikker "Find slægtskab" uden at ville søge.
  useEffect(() => { if (s.focusToken > 0) { inputRef.current?.focus(); s.resetFocus(); } }, [s.focusToken]);
  return (
    <div style={{ marginBottom: 16 }}>
      {/* Søgefelt */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, background: T.paper, border: '1px solid rgba(34,31,26,.16)', borderRadius: 12, padding: '13px 17px', boxShadow: '0 2px 8px rgba(20,17,13,.04)' }}>
        <SearchIcon size={19} />
        <input ref={inputRef} value={s.query} onChange={(e) => s.setQuery(e.target.value)} placeholder="Søg i slægten…" style={{ flex: 1, minWidth: 0, fontFamily: T.sans, fontSize: 15, color: T.ink, background: 'transparent', border: 'none', outline: 'none' }} />
        {s.showResults && (
          <>
            <span style={{ fontFamily: T.sans, fontSize: 12, color: T.muted3, whiteSpace: 'nowrap', flex: 'none' }}>{`${s.browse.flat.length} ${s.query.trim() ? 'træffere' : 'personer'}`}</span>
            <span onClick={s.clearSearch} title="Ryd søgning" style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', flex: 'none' }}>
              <svg viewBox="0 0 24 24" width={15} height={15} fill="none" stroke={T.muted2} strokeWidth={2} strokeLinecap="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
            </span>
          </>
        )}
      </div>

      {/* Fane-bånd — universel-klar (brief §4.2); kun Personer aktiv nu */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 2, marginTop: 12, borderBottom: '1px solid rgba(34,31,26,.1)' }}>
        {SEARCH_TABS.map((tb) => (
          <div key={tb.key} title={tb.live ? '' : 'Kommer'} style={{ padding: '9px 3px', marginRight: 16, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: tb.live ? T.bordeaux : T.muted3, borderBottom: `2px solid ${tb.live ? T.bordeaux : 'transparent'}` }}>{tb.label}</div>
        ))}
        <div style={{ flex: 1 }} />
        {!s.showResults && (
          <span onClick={() => s.setBrowsing(true)} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', padding: '8px 0', whiteSpace: 'nowrap' }}>Gennemse hele slægten ›</span>
        )}
      </div>

      {/* Resultater (kun når der søges/gennemses) */}
      {s.showResults && (
        <div style={{ marginTop: 16 }}>
          {/* Filter-række: linje-chips + bogmærke-filter + sortér */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', marginBottom: 16 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, flex: 1 }}>
              <LinjeChip label="Hele slægten" active={!s.activeLinje} onClick={() => s.setActiveLinje(null)} />
              {s.linjeList.map((l) => (
                <LinjeChip key={l.linje} label={`Linje ${l.linje}`} title={l.navn ?? undefined} active={s.activeLinje === l.linje} onClick={() => s.setActiveLinje(l.linje)} />
              ))}
              {s.hasBookmarks && (
                <span onClick={() => s.setBmOnly(!s.bmOnly)} title="Vis kun bogmærkede" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 12px', borderRadius: 15, fontFamily: T.sans, fontSize: 11.5, fontWeight: 600, cursor: 'pointer', background: s.bmOnly ? T.bordeaux : T.paper, color: s.bmOnly ? T.paper : '#3d382f', border: `1px solid ${s.bmOnly ? T.bordeaux : 'rgba(34,31,26,.14)'}` }}>
                  {/* Samme ribbon-form som BookmarkFlag-primitiven (bruger-bestemt, konsistent). */}
                  <svg viewBox="0 0 14 17" width={11} height={13} fill={s.bmOnly ? T.paper : 'none'} stroke={s.bmOnly ? T.paper : T.muted2} strokeWidth={1.5} strokeLinejoin="round"><path d="M3 1.5 H11 V15.5 L7 11.8 L3 15.5 Z" /></svg>
                  Bogmærker
                </span>
              )}
            </div>
            <div style={{ display: 'flex', background: '#e6ddcc', borderRadius: 7, padding: 2, gap: 2, flex: 'none' }}>
              {(['navn', 'aar'] as const).map((so) => (
                <span key={so} onClick={() => s.setSort(so)} style={{ fontFamily: T.sans, fontSize: 11, fontWeight: 600, padding: '4px 11px', borderRadius: 5, cursor: 'pointer', background: s.sort === so ? T.bordeaux : 'transparent', color: s.sort === so ? T.paper : '#3d382f' }}>{so === 'navn' ? 'A–Å' : 'Født'}</span>
              ))}
            </div>
          </div>

          {/* Alfabet-hop */}
          {s.browse.grouped && s.browse.letters.length > 1 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 16 }}>
              {[{ key: null as string | null, label: 'Alle' }, ...s.browse.letters.map((l) => ({ key: l as string | null, label: l }))].map((L) => {
                const on = s.activeLetter === L.key;
                return <span key={L.label} onClick={() => s.setActiveLetter(L.key)} style={{ fontFamily: T.mono, fontSize: 11, fontWeight: 500, minWidth: 24, height: 24, padding: '0 5px', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 6, cursor: 'pointer', background: on ? T.bordeaux : T.beige, color: on ? T.paper : T.muted }}>{L.label}</span>;
              })}
            </div>
          )}

          {/* Resultat-grid som personkort (§8.1 én korttype) */}
          {s.browse.grouped
            ? s.browse.groups.map((g) => (
                <div key={g.letter}>
                  <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.gold, margin: '6px 0 10px', paddingBottom: 5, borderBottom: '1px solid rgba(34,31,26,.08)' }}>{g.letter}</div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginBottom: 14 }}>
                    {g.people.map((p) => <PersonCard key={p.id} p={p} width={186} onClick={() => s.onPick(p.id)} />)}
                  </div>
                </div>
              ))
            : <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>{s.browse.flat.map((p) => <PersonCard key={p.id} p={p} width={186} onClick={() => s.onPick(p.id)} />)}</div>}
          {s.browse.flat.length === 0 && <div style={{ padding: '20px 4px', fontFamily: T.sans, fontSize: 13, color: T.muted3 }}>Ingen træffere.</div>}
        </div>
      )}
    </div>
  );
}

// Eksporteret så drill-down/toggle/reset-adfærden kan komponent-testes uden hele Folgesvend.
// onPick = fokus-hop MED historik (variant A-kort, matcher designets goToPerson). onFocus =
// drill-valg UDEN historik (variant B-kolonner, matcher designets selectAt) — så en dyb drill
// ikke fylder detalje-panelets tilbage-stak med hvert generations-trin.
export function TreeView({ model, focusId, onPick, onFocus, hasBookmark, onToggleBookmark, search }: {
  model: Model | null; focusId: string | null; onPick: (id: string) => void; onFocus: (id: string) => void;
  hasBookmark: (id: string) => boolean; onToggleBookmark: (id: string) => void; search: TreeSearchBundle;
}) {
  // Visnings-variant (segmenteret kontrol) — bevares på tværs af fokus-skift (nulstilles kun når
  // TreeView unmountes ved mode-skift til Godser/Våben/Slægtskab). Matcher designets state.variant.
  const [variant, setVariant] = useState<'A' | 'B'>('A');
  // Bidirektionel drill-tilstand (variant B): fast anker + valgte aner (op) + valgte efterkommere (ned).
  // up[i] = valgt forælder i ane-ring i+1; down[i] = valgt barn i efterkommer-ring i+1.
  const [anchorId, setAnchorId] = useState<string | null>(null);
  const [up, setUp] = useState<string[]>([]);
  const [down, setDown] = useState<string[]>([]);
  const colsRef = useRef<HTMLDivElement>(null);
  const anchorIdxRef = useRef(0);           // indeks på anker-kolonnen (til centrering)
  const prevUp = useRef(0), prevDown = useRef(0), prevAnchor = useRef<string | null>(null), prevVariant = useRef<'A' | 'B'>('A');
  const STRIDE = 222;                        // kolonnebredde 208 + gap 14

  // Ankeret følger fokus-personen. Nulstil (ryd begge drill-retninger) KUN ved EKSTERN navigation.
  // Frontier-tjek (IKKE fuldt medlemskab, jf. spec §5.3): efter en drill er focusId altid den
  // YDERSTE valgte ane/efterkommer, så et frontier-match betyder "drill", ellers "ekstern nav →
  // nulstil". Invariant: focusId + alle up/down-id'er er KANONISKE (focusId post-canon; up/down
  // udvides kun med parentsOf/childrenOf-id'er) → korrekt lighed i tjekket.
  useEffect(() => {
    if (!focusId) return;
    const keep =
      (up.length === 0 && down.length === 0 && focusId === anchorId) ||
      focusId === up[up.length - 1] ||
      focusId === down[down.length - 1];
    if (!keep) { setAnchorId(focusId); setUp([]); setDown([]); }
  }, [focusId]); // bevidst kun focusId — up/down/anchorId læses som frontier ved fokus-skift

  // Kompensér FØR paint når en ane-kolonne prepend'es, så ankeret ikke "hopper" (spec §5.5, fase 1).
  useLayoutEffect(() => {
    const el = colsRef.current;
    if (el && variant === 'B' && up.length > prevUp.current) el.scrollLeft += (up.length - prevUp.current) * STRIDE;
  }, [up.length, variant]);

  // Efter paint (spec §5.5, fase 2): centrér anker ved reset/B-skift; afslør nyeste kolonne ved drill.
  // scrollTo feature-detekteres (findes ikke i jsdom).
  useEffect(() => {
    const el = colsRef.current;
    const sync = () => { prevUp.current = up.length; prevDown.current = down.length; prevAnchor.current = anchorId; prevVariant.current = variant; };
    if (variant !== 'B' || !el?.scrollTo) { sync(); return; }
    if (anchorId !== prevAnchor.current || prevVariant.current !== 'B') {
      const target = Math.max(0, anchorIdxRef.current * STRIDE - (el.clientWidth - 208) / 2);
      el.scrollTo({ left: target, behavior: 'smooth' });          // centrér anker
    } else if (down.length > prevDown.current) {
      el.scrollTo({ left: el.scrollWidth, behavior: 'smooth' });  // ny efterkommer → højre
    } else if (up.length > prevUp.current) {
      el.scrollTo({ left: Math.max(0, el.scrollLeft - STRIDE), behavior: 'smooth' }); // ny ane → afslør venstre
    }
    sync();
  }, [variant, anchorId, up.length, down.length]);

  if (!model || !focusId) return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  const f = model.byId[focusId];
  if (!f) return <div style={{ padding: 40, color: T.muted3 }}>Ukendt person.</div>;
  // Forenkling: stamtræet viser den PRIMÆRE forælder-linje (f.parentId). Slægtskabsfinderen er
  // bilineal (begge forældre) — så et halvsøskende via den anden forælder kan optræde som
  // beslægtet uden at stå i søskende-rækken her. Bevidst (variant A kan ikke vise to-forælder-celler).
  const parent = f.parentId ? model.byId[f.parentId] : null;
  const grand = parent?.parentId ? model.byId[parent.parentId] : null;
  const siblings = f.parentId ? childrenOf(model, f.parentId) : [f];
  const spouses = (model.indexes.spousesBy[focusId] ?? []).map((s) => s.name).filter(Boolean);
  const children = childrenOf(model, focusId);
  const childCount = (id: string) => model.indexes.childIdx[id]?.size ?? 0;
  const hasParents = (id: string) => (model.indexes.parentsByChild[id]?.length ?? 0) > 0;

  // Drill-valg (variant B). onFocus opdaterer fokus UDEN historik, så detalje-panelet følger valget.
  // Vi udvider up/down KUN med parentsOf/childrenOf-id'er (kanoniske) → frontier-invarianten holder.
  const selectAncestor = (depth: number, id: string) => { setUp((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const selectDescendant = (depth: number, id: string) => { setDown((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const cols = variant === 'B' && anchorId ? buildBidirectionalColumns(model, anchorId, up, down, model.genCoordsByPerson) : [];
  anchorIdxRef.current = Math.max(0, cols.findIndex((c) => c.kind === 'anchor'));

  return (
    <div style={{ padding: '30px 40px 50px', position: 'relative', minHeight: '100%' }}>
      {/* Dekorativt våbenskjold-vandmærke (delt Crest-primitiv). */}
      <Crest opacity={0.09} size={116} style={{ position: 'absolute', top: 104, right: 34, zIndex: 0 }} />
      <div style={{ position: 'relative', zIndex: 1 }}>
      {/* Header: titel til venstre, segmenteret kontrol (Fokus/Kolonner) til højre. */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <ViewHeader title="Stamtræ" mb="0" />
        </div>
        <div style={{ display: 'flex', background: T.beige, borderRadius: 10, padding: 3, gap: 3, flex: 'none' }}>
          {(['A', 'B'] as const).map((v) => {
            const active = variant === v;
            return (
              <div key={v} onClick={() => setVariant(v)} style={{ padding: '7px 16px', borderRadius: 7, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', background: active ? T.paper : 'transparent', color: active ? T.bordeaux : '#8a8170' }}>{v === 'A' ? 'Fokus' : 'Kolonner'}</div>
            );
          })}
        </div>
      </div>

      {/* Søgning-i-træet (§4): søgefelt + fane-bånd + resultat-grid, over selve træet. */}
      <TreeSearch {...search} />

      {!search.showResults && (variant === 'B' ? (
        <div ref={colsRef} data-scroll style={{ display: 'flex', gap: 14, overflowX: 'auto', padding: '10px 0 16px', alignItems: 'flex-start' }}>
          {cols.map((col) => (
            <div key={col.key} style={{ flex: 'none', width: 208, display: 'flex', flexDirection: 'column', gap: 9 }}>
              <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.gold, padding: '0 2px 4px', borderBottom: '1px solid rgba(34,31,26,.1)' }}>{col.fallback ? col.genLabel : col.label}</div>
              {col.fallback && (
                <div style={{ fontFamily: T.sans, fontSize: 10.5, color: T.muted2, padding: '0 2px', marginTop: -6 }}>
                  slægtled-naboer — ingen bevist som forælder
                </div>
              )}
              {col.fallback ? (
                Object.entries(col.kuldGroups ?? {}).map(([kuld, people]) => (
                  <div key={kuld} style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
                    {kuld !== '—' && (
                      <div style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, padding: '2px 2px 0' }}>Kuld {kuld}</div>
                    )}
                    {people.map((p) => (
                      <div key={p.id} onClick={() => onFocus(p.id)} style={{ background: '#faf1dc', border: `1.5px dashed ${T.gold}`, borderRadius: 12, padding: '11px 13px', cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                        <Avatar n={p.name} size={34} />
                        <div style={{ minWidth: 0, flex: 1 }}>
                          <div style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                          {p.years && <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 2 }}>{p.years}</div>}
                          <div style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.06em', textTransform: 'uppercase', color: T.gold, marginTop: 2 }}>muligt slægtled</div>
                        </div>
                        <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                      </div>
                    ))}
                  </div>
                ))
              ) : col.people.map((p) => {
                const sel = p.id === col.selectedId;
                // Kort-chevron peger i drill-retningen: aner ‹ (venstre), efterkommere › (højre).
                const canAnc = col.kind === 'ancestor' && hasParents(p.id);
                const canDesc = col.kind === 'descendant' && childCount(p.id) > 0;
                const onTap = col.kind === 'ancestor' ? () => selectAncestor(col.depth, p.id)
                  : col.kind === 'descendant' ? () => selectDescendant(col.depth, p.id)
                  : () => onFocus(p.id);
                return (
                  <div key={p.id} onClick={onTap} style={{ background: sel ? '#f8ecef' : T.paper, border: `1.5px solid ${sel ? T.bordeaux : 'rgba(34,31,26,.1)'}`, borderRadius: 12, padding: '11px 13px', cursor: 'pointer', boxShadow: sel ? '0 4px 14px rgba(136,26,51,.12)' : '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                    {canAnc && <span style={{ color: '#bcae93', fontSize: 16, flex: 'none' }}>‹</span>}
                    <Avatar n={p.name} size={34} />
                    <div style={{ minWidth: 0, flex: 1 }}>
                      <div style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                      {p.years && <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 2 }}>{p.years}</div>}
                    </div>
                    <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                    {canDesc && <span style={{ color: '#bcae93', fontSize: 16, flex: 'none' }}>›</span>}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      ) : (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        {grand && (
          <>
            <div onClick={() => onPick(grand.id)} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 16px', borderRadius: 20, background: T.beige, border: '1px solid rgba(34,31,26,.08)', cursor: 'pointer', opacity: 0.85 }}>
              <span style={{ color: T.muted2, fontSize: 12 }}>▲</span>
              <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: '#5a5246' }}>{grand.name}</span>
            </div>
            <Stem h={18} />
          </>
        )}
        {parent && (
          <>
            <div onClick={() => onPick(parent.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: '11px 18px 11px 12px', cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)' }}>
              <Avatar n={parent.name} size={40} />
              <div>
                <div style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.12em', textTransform: 'uppercase', color: T.gold }}>Forælder ▲</div>
                <div style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, lineHeight: 1.05 }}>{parent.name}</div>
              </div>
            </div>
            <Stem h={22} />
          </>
        )}
        <Label>Denne generation</Label>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 13, justifyContent: 'center', maxWidth: 760 }}>
          {siblings.map((p) => {
            const sel = p.id === focusId;
            return (
              <div key={p.id} onClick={() => onPick(p.id)} style={{ position: 'relative', width: 188, background: sel ? '#fff' : T.paper, border: `1.5px solid ${sel ? T.bordeaux : 'rgba(34,31,26,.1)'}`, borderRadius: 15, padding: 16, cursor: 'pointer', boxShadow: sel ? '0 4px 14px rgba(136,26,51,.12)' : '0 1px 2px rgba(34,31,26,.04)' }}>
                <div style={{ position: 'absolute', top: 12, left: 13 }}><BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} /></div>
                {sel && <div style={{ position: 'absolute', top: 12, right: 13, fontFamily: T.mono, fontSize: 7.5, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux }}>I fokus</div>}
                <Avatar n={p.name} size={56} />
                <div style={{ fontFamily: T.serif, fontSize: 21, lineHeight: 1.04, fontWeight: 600, marginTop: 11 }}>{p.name}</div>
                {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 4 }}>{p.years}</div>}
                {p.title && <div style={{ fontSize: 11.5, fontWeight: 500, color: T.bordeaux, marginTop: 6, lineHeight: 1.3 }}>{p.title}</div>}
                {childCount(p.id) > 0 && <div style={{ fontSize: 10.5, color: T.muted, marginTop: 8 }}>↓ {childCount(p.id)} {childCount(p.id) === 1 ? 'barn' : 'børn'}</div>}
              </div>
            );
          })}
        </div>
        {spouses.length > 0 && <div style={{ marginTop: 12, fontFamily: T.serif, fontSize: 15, fontStyle: 'italic', color: T.muted }}>⚭ gift med {spouses.join(', ')}</div>}
        {children.length > 0 ? (
          <>
            <Stem h={22} mt={16} />
            <Label>Børn &amp; grene</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 11, justifyContent: 'center', maxWidth: 820 }}>
              {children.map((p) => (
                <div key={p.id} onClick={() => onPick(p.id)} style={{ width: 150, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: 13, cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)' }}>
                  <Avatar n={p.name} size={40} />
                  <div style={{ fontFamily: T.serif, fontSize: 17, lineHeight: 1.05, fontWeight: 600, marginTop: 9 }}>{p.name}</div>
                  {p.years && <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 3 }}>{p.years}</div>}
                  {childCount(p.id) > 0 && <div style={{ fontSize: 10, color: T.bordeaux, marginTop: 6 }}>↓ {childCount(p.id)}</div>}
                </div>
              ))}
            </div>
          </>
        ) : (
          <div style={{ marginTop: 18, fontSize: 12.5, color: T.muted3 }}>Ingen registrerede efterkommere</div>
        )}
      </div>
      ))}
      </div>
    </div>
  );
}

// ---- Slægtskab ("Er vi i familie?") ----
function RelateView({ model, rel, relA, relB, slot, setSlot, onPickStep, meId, onSetMeA, search }: {
  model: Model | null; rel: RelationResult | null; relA: string | null; relB: string | null;
  slot: 'A' | 'B'; setSlot: (s: 'A' | 'B') => void; onPickStep: (id: string) => void;
  meId: string | null; onSetMeA: () => void; search: TreeSearchBundle;
}) {
  const a = relA && model ? model.byId[relA] : null;
  const b = relB && model ? model.byId[relB] : null;
  const me = meId && model ? model.byId[meId] : null;
  const p0 = rel?.lines[0];
  const korrob = p0 && p0.uafhaengige >= 2 ? `Bekræftet ad ${p0.uafhaengige} uafhængige linjer`
    : (p0?.usikker && rel?.alternativSolidLinje) ? 'Bekræftet ad en anden, sikker linje' : '';
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <ViewHeader title="Er vi i familie?" />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 20 }}>Klik et felt for at vælge plads, søg og vælg så en person nedenfor.</div>
      {me && relA !== meId && (
        <div onClick={onSetMeA} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginBottom: 14, background: '#f8ecef', border: '1px solid rgba(136,26,51,.25)', borderRadius: 9, padding: '8px 12px', cursor: 'pointer', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux }}>★ Sæt mig ({me.name}) som første person</div>
      )}
      <div style={{ display: 'flex', alignItems: 'stretch', gap: 12 }}>
        {(['A', 'B'] as const).map((sl) => {
          const person = sl === 'A' ? a : b;
          const active = slot === sl;
          return (
            <div key={sl} onClick={() => setSlot(sl)} style={{ flex: 1, background: active ? '#f8ecef' : T.paper, border: `1.5px solid ${active ? T.bordeaux : 'rgba(34,31,26,.12)'}`, borderRadius: 14, padding: 16, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
              <Avatar n={person?.name ?? '?'} size={50} />
              <div style={{ fontFamily: T.serif, fontSize: 18, lineHeight: 1.05, fontWeight: 600, marginTop: 10 }}>{person?.name ?? `Vælg person ${sl}`}</div>
              <div style={{ fontSize: 11, color: T.bordeaux, marginTop: 6, fontWeight: 600 }}>{active ? 'vælger nu ▾' : 'skift'}</div>
            </div>
          );
        })}
      </div>

      {/* Søgning-i-træet (§4/§5.6): et valg fylder den aktive A/B-plads (pickPerson relate-gren). */}
      <div style={{ marginTop: 20 }}><TreeSearch {...search} /></div>

      {/* Slægtskabs-panelerne (resultat · også-beslægtet · sti) skjules under en aktiv søgning. */}
      {!search.showResults && (<>
      {rel && (
        <div style={{ marginTop: 20, background: T.ink, borderRadius: 14, padding: 20, textAlign: 'center' }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldLight }}>Slægtskab</div>
          <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1.1, fontWeight: 600, color: T.paper, marginTop: 7 }}>{rel.label}</div>
          {rel.found && p0 && p0.aner.length > 0 && <div style={{ fontSize: 12.5, color: T.cream, marginTop: 8 }}>{p0.multiplicitet > 1 ? 'Fælles aner' : 'Fælles ane'}: {p0.aner.join(' · ')}</div>}
          {p0?.usikker && <div style={{ fontSize: 11.5, color: T.goldLight, marginTop: 7 }}>⚠ Forbindelsen går gennem et {konfTekst(p0.weakestKonfidens)} led</div>}
          {korrob && <div style={{ fontSize: 11.5, color: '#a9c2a0', marginTop: 7 }}>✓ {korrob}</div>}
        </div>
      )}

      {rel?.found && rel.lines.length > 1 && (
        <div style={{ marginTop: 14, background: T.paper, borderRadius: 12, padding: '12px 14px', border: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, marginBottom: 6 }}>Også beslægtet</div>
          {rel.lines.slice(1).map((l) => (
            <div key={l.lcaId} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '5px 0' }}>
              <span style={{ fontFamily: T.serif, fontSize: 14, flex: 1 }}>{l.label}</span>
              <span style={{ fontSize: 11, color: T.muted2 }}>via {l.aner.join(' · ')}</span>
            </div>
          ))}
        </div>
      )}

      {rel && rel.steps.length > 0 && (
        <>
          <div style={{ marginTop: 22, fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, marginBottom: 6 }}>Forbindelsen, trin for trin</div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {rel.steps.map((st, i) => {
              const linkKonf = i > 0 ? konfTekst(st.edgeKonfidens) : '';
              return (
                <div key={`${st.id}-${i}`}>
                  {i > 0 && (
                    <div style={{ marginLeft: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div style={{ width: 2, height: 9, background: 'rgba(34,31,26,.18)' }} />
                      {linkKonf && <span style={{ fontFamily: T.mono, fontSize: 8, textTransform: 'uppercase', color: T.bordeaux }}>{linkKonf} led</span>}
                    </div>
                  )}
                  <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '3px 0' }}>
                    <div style={{ width: 26, display: 'flex', justifyContent: 'center', flex: 'none' }}>
                      <div style={{ width: 11, height: 11, borderRadius: '50%', background: st.isLca ? T.gold : T.bordeaux, border: `2px solid ${st.isLca ? T.gold : 'rgba(136,26,51,.25)'}` }} />
                    </div>
                    <div onClick={() => onPickStep(st.id)} style={{ flex: 1, background: st.isLca ? '#f3ecdb' : T.paper, border: `1px solid ${st.isLca ? 'rgba(185,160,106,.5)' : 'rgba(34,31,26,.1)'}`, borderRadius: 11, padding: '10px 14px', display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, lineHeight: 1.04 }}>{st.name}</div>
                        {st.years && <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2, marginTop: 2 }}>{st.years}</div>}
                      </div>
                      {st.isLca && <div style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.08em', textTransform: 'uppercase', color: T.gold }}>Fælles ane</div>}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}
      </>)}
    </div>
  );
}

// ---- Person-detalje (højre panel) ----
function DetailPanel({ model, focusId, detail, onPick, backName, onBack, onClose, onFocusTree, onRelate, isMe, onToggleMe, isBookmarked, onToggleBookmark }: {
  model: Model; focusId: string; detail: PersonDetailData | null; onPick: (id: string) => void;
  backName: string | null; onBack: () => void; onClose?: () => void; onFocusTree: () => void; onRelate: () => void;
  isMe: boolean; onToggleMe: () => void; isBookmarked: boolean; onToggleBookmark: () => void;
}) {
  // Lightbox (Slice A): useState skal stå FØR den betingede return nedenfor (Rules of Hooks) —
  // portræt + galleri bliver ÉT navigerbart sæt (portræt først), så pil-tasterne bladrer gennem
  // alle personens billeder uanset hvilket der blev klikket på.
  const [lightbox, setLightbox] = useState<number | null>(null);
  const p = model.byId[focusId];
  if (!p) return null;
  const parents = parentsOf(model, focusId);
  const spouses = (model.indexes.spousesBy[focusId] ?? []);
  const children = childrenOf(model, focusId);
  const linjer = model.lineage?.byPerson[focusId] ?? [];
  const sources = model.sourcesBy?.[focusId] ?? [];
  // Portræt = hovedbilledet; galleri = de øvrige medier (materiale). RLS-gatet i data-laget.
  const media = detail?.media ?? [];
  const portrait = pickPortrait(media);
  const gallery = media.filter((m) => m.url && m.id !== portrait?.id);
  const lightboxItems = withUrl([portrait, ...gallery]);
  // Proveniens: er personen foldet af flere DAA-poster (samme_som), vis hvilke linjer/numre.
  const mergedFrom = p.mergedFrom ?? [];
  const proveniens =
    mergedFrom.length > 1
      ? mergedFrom
          .map((m) => {
            const navn = m.linje ? model.lineage?.navn[m.linje] ?? `linje ${m.linje}` : 'ukendt linje';
            const ref = m.linje && m.nr != null ? ` (${m.linje}-${m.nr})` : '';
            return `${navn}${ref}`;
          })
          .join(' og ')
      : null;
  return (
    <>
    <div data-scroll style={{ flex: 'none', width: '50%', maxWidth: 760, minWidth: 430, borderLeft: '1px solid rgba(34,31,26,.1)', background: T.paper, overflowY: 'auto' }}>
      <div style={{ padding: '24px 24px 36px' }}>
        {(backName || onClose) && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 14 }}>
            {backName ? (
              <div onClick={onBack} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>‹ Tilbage til {backName}</div>
            ) : <span />}
            {/* Luk detaljen (§5): navigerer til /stamtrae → fuldt-bredt træ, samme centrum. */}
            {onClose && (
              <div onClick={onClose} title="Luk detalje (Esc)" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.muted, cursor: 'pointer', padding: '4px 9px', borderRadius: 8, background: T.panel, border: '1px solid rgba(34,31,26,.12)', flex: 'none' }}>
                Luk
                <svg viewBox="0 0 24 24" width={13} height={13} fill="none" stroke={T.muted} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
              </div>
            )}
          </div>
        )}
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
          {portrait ? (
            <div style={{ flex: 'none' }}><MediaThumb m={portrait} w={92} h={116} radius={11} onClick={() => setLightbox(0)} /></div>
          ) : (
            <div style={{ width: 92, height: 116, borderRadius: 11, background: 'repeating-linear-gradient(45deg,#ece4d6 0 9px,#e2d8c8 9px 18px)', border: '1px solid rgba(34,31,26,.1)', flex: 'none', display: 'flex', alignItems: 'flex-end', padding: 8 }}><span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted }}>portræt</span></div>
          )}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1, fontWeight: 600, minWidth: 0 }}>{p.name}</div>
              <BookmarkFlag active={isBookmarked} onClick={onToggleBookmark} />
            </div>
            {p.years && <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 6 }}>{p.years}</div>}
            {/* Badges: ★ Dig + Linje(r) + titel. */}
            {(isMe || linjer.length > 0 || p.title) && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 9 }}>
                {isMe && <div style={{ fontFamily: T.sans, fontSize: 10.5, fontWeight: 700, color: T.paper, background: T.bordeaux, padding: '4px 9px', borderRadius: 6 }}>★ Dig</div>}
                {linjer.map((lk) => (
                  <div key={lk} style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '4px 8px', borderRadius: 6 }}>{model.lineage?.navn[lk] ?? `Linje ${lk}`}</div>
                ))}
                {p.title && <div style={{ fontSize: 11, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '4px 9px', borderRadius: 6 }}>{p.title}</div>}
              </div>
            )}
            {proveniens && (
              <div style={{ fontFamily: T.sans, fontSize: 11, color: T.muted2, marginTop: 8, lineHeight: 1.45 }}>
                Optræder i Aarbogen som {proveniens}.
              </div>
            )}
          </div>
        </div>

        {parents.length > 0 && (
          <div style={{ marginTop: 16, display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '4px 7px' }}>
            <span style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.gold }}>Barn af</span>
            {parents.map((pa, i) => (
              <span key={pa.id} style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                {i > 0 && <span style={{ fontFamily: T.serif, fontSize: 15, fontStyle: 'italic', color: T.gold }}>&amp;</span>}
                <span onClick={() => onPick(pa.id)} style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>{pa.name} ›</span>
              </span>
            ))}
          </div>
        )}

        {detail?.bio && <div style={{ marginTop: 14, fontSize: 13.5, lineHeight: 1.55, color: '#3d382f' }}><NarrativRenderer tekst={detail.bio} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} /></div>}

        {/* Livskort: kun hvis personen har mindst ét geo-punkt (undgår tom-boks-støj for de fleste). */}
        {model.geo && lifeJourney(model.geo, focusId).length > 0 && (
          <div style={{ marginTop: 14 }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted2, marginBottom: 6 }}>Livsrejse</div>
            <ExpandableMiniMap points={lifeJourney(model.geo, focusId)} />
          </div>
        )}

        {spouses.length > 0 && (
          <div style={{ marginTop: 14, fontFamily: T.serif, fontSize: 15, fontStyle: 'italic', color: T.muted, lineHeight: 1.5 }}>⚭ gift med{' '}
            {spouses.map((sp, i) => (
              <span key={(sp.id ?? sp.name) + i}>
                {i > 0 && <span style={{ color: T.gold }}>· </span>}
                {sp.id ? <span onClick={() => onPick(sp.id!)} style={{ fontWeight: 600, fontStyle: 'normal', color: T.bordeaux, cursor: 'pointer' }}>{sp.name} ›</span> : <span>{sp.name}</span>}
              </span>
            ))}
          </div>
        )}

        {children.length > 0 && (
          <>
            <Label>Børn</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
              {children.map((c) => (
                <div key={c.id} onClick={() => onPick(c.id)} style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 9, padding: '6px 11px 6px 7px', cursor: 'pointer' }}>
                  <div style={{ width: 26, height: 26, borderRadius: '50%', background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 11, fontWeight: 600, color: T.bordeaux }}>{initials(c.name)}</div>
                  <span style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600 }}>{c.name.split(' ')[0]}</span>
                </div>
              ))}
            </div>
          </>
        )}

        {detail && detail.offices.length > 0 && (
          <>
            <Label>Embeder, rang &amp; hverv</Label>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {detail.offices.map((o, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'baseline', gap: 10, padding: '7px 0', borderBottom: '1px solid rgba(34,31,26,.07)' }}>
                  <span style={{ flex: 1, fontSize: 13, color: '#3d382f', lineHeight: 1.3 }}>{o.label}</span>
                  {o.period && <span style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2, flex: 'none', whiteSpace: 'nowrap' }}>{o.period}</span>}
                </div>
              ))}
            </div>
          </>
        )}

        {detail && detail.estates.length > 0 && (
          <>
            <Label>Godser &amp; besiddelser</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
              {detail.estates.map((e, i) => (
                <span key={e.id + i} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 8, padding: '6px 10px', fontFamily: T.serif, fontSize: 14, fontWeight: 600, color: T.ink }}>⌂ {e.navn}</span>
              ))}
            </div>
          </>
        )}

        {gallery.length > 0 && (
          <>
            <Label>Materiale</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {gallery.map((m) => (
                <MediaThumb key={m.id} m={m} w={84} h={84} radius={9}
                  onClick={() => setLightbox(lightboxItems.findIndex((x) => x.id === m.id))} />
              ))}
            </div>
          </>
        )}

        {detail === null && <div style={{ marginTop: 18, fontSize: 12, color: T.muted3 }}>Henter detaljer…</div>}

        {/* Kilde i Aarbogen (§ + trykt værk + "Linje X, nr. N"). */}
        {sources.length > 0 && (
          <>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '22px 0 8px' }}>Kilde i Aarbogen</div>
            {sources.map((s, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 0', borderBottom: '1px solid rgba(34,31,26,.08)' }}>
                <span style={{ fontFamily: T.serif, fontSize: 18, color: T.bordeaux, flex: 'none' }}>§</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.ink, lineHeight: 1.25 }}>{s.work}</div>
                  {s.ref && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 2 }}>{s.ref}</div>}
                </div>
              </div>
            ))}
          </>
        )}

        {/* Handlinger: fokus · slægtskab · "det er mig"-toggle. */}
        <div onClick={onFocusTree} style={{ marginTop: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: '#3d382f', background: T.panel, border: '1.5px solid rgba(34,31,26,.16)', padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>
          <span style={{ fontSize: 13 }}>⊹</span> Sæt i fokus i stamtræet
        </div>
        <div style={{ marginTop: 9, display: 'flex', gap: 9 }}>
          <div onClick={onRelate} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.paper, background: T.bordeaux, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>Find slægtskab</div>
          <div onClick={onToggleMe} title={isMe ? 'Fjern din markering' : 'Marker denne person som dig'} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: isMe ? T.bordeaux : '#3d382f', background: isMe ? '#f8ecef' : T.panel, border: `1.5px solid ${isMe ? T.bordeaux : 'rgba(34,31,26,.16)'}`, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>{isMe ? '★ Dette er dig' : 'Det er mig'}</div>
        </div>
      </div>
    </div>
    {lightbox != null && (
      <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
    )}
    </>
  );
}

// (Søgning + browsing bor nu ØVERST I STAMTRÆET (§4): søgefelt + fane-bånd + sortér/alfabet-hop
//  + grupperet personkort-resultat. Se `TreeSearch` + `browse`-memo i Folgesvend().)

// ---- Godser & ejendomme ----
function EstatesView({ estates, estateId, estate, info, owners, geo, onOpen, onBack, onPickOwner }: {
  estates: EstateItem[] | null; estateId: string | null; estate: EstateItem | null; info: EstateInfo | null;
  owners: EstateOwner[]; geo?: Geo; onOpen: (id: string) => void; onBack: () => void; onPickOwner: (id: string) => void;
}) {
  const [lightbox, setLightbox] = useState<number | null>(null); // Slice A — kun brugt i detalje-grenen nedenfor
  const [viewMode, setViewMode] = useState<'liste' | 'kort'>('liste');
  if (estateId && estate) {
    const lightboxItems = withUrl(info?.media ?? []);
    const point = geo?.byEstate[estate.id];
    return (
      <div style={{ padding: '26px 40px 50px', maxWidth: 620 }}>
        <div onClick={onBack} style={{ fontSize: 12.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginBottom: 14 }}>‹ Alle godser</div>
        <div style={{ fontFamily: T.serif, fontSize: 32, fontWeight: 600, lineHeight: 1.02 }}>{estate.navn}</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 9 }}>
          {estate.slags && <span style={{ fontSize: 11.5, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '5px 10px', borderRadius: 7 }}>{estate.slags}</span>}
          {info?.sted && <span style={{ fontSize: 11.5, fontWeight: 600, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '5px 10px', borderRadius: 7 }}>⌖ {info.sted}</span>}
        </div>
        {point && (
          <div style={{ marginTop: 14 }}><ExpandableMiniMap points={[point]} /></div>
        )}
        {info && info.media.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 16 }}>
            {lightboxItems.map((m, i) => (
              <MediaThumb key={m.id} m={m} w={180} h={130} radius={11} onClick={() => setLightbox(i)} />
            ))}
          </div>
        )}
        {/* Vis intet under load (info===null); derefter narrativ eller tom-tilstand. */}
        {info && (info.narrativ ? (
          <div style={{ marginTop: 16, fontFamily: T.serif, fontSize: 15.5, lineHeight: 1.6, color: '#3d382f' }}><NarrativRenderer tekst={info.narrativ} onPickPerson={onPickOwner} linkColor={T.bordeaux} inactiveColor={T.muted2} /></div>
        ) : (
          <div style={{ marginTop: 16, border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 14, background: T.paper, fontSize: 12.5, color: T.muted3 }}>Ingen godshistorik registreret endnu.</div>
        ))}
        <Label>Ejere &amp; tilknytninger gennem tiden</Label>
        {owners.length ? (
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {owners.map((o, i) => (
              <div key={o.personId + i} style={{ display: 'flex', alignItems: 'flex-start', gap: 13 }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flex: 'none', width: 13, paddingTop: 6 }}>
                  <div style={{ width: 11, height: 11, borderRadius: '50%', background: T.bordeaux }} />
                  {i < owners.length - 1 && <div style={{ width: 2, flex: 1, minHeight: 28, background: 'rgba(136,26,51,.22)', marginTop: 2 }} />}
                </div>
                <div onClick={() => onPickOwner(o.personId)} style={{ flex: 1, cursor: 'pointer', paddingBottom: 18 }}>
                  {(o.periode || o.rolle) && <div style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted2 }}>{[o.periode, o.rolle].filter(Boolean).join(' · ')}</div>}
                  <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 1 }}>{o.navn} ›</div>
                </div>
              </div>
            ))}
          </div>
        ) : <div style={{ fontSize: 12.5, color: T.muted3 }}>Ingen registrerede ejere.</div>}
        {lightbox != null && (
          <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
        )}
      </div>
    );
  }
  const points = geo ? estatePoints(geo) : [];
  return (
    <div style={{ padding: '30px 40px 50px', height: viewMode === 'kort' ? 'calc(100vh - 60px)' : undefined, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
        <ViewHeader title="Godser &amp; ejendomme" />
        <div style={{ display: 'flex', gap: 2, background: T.beige, borderRadius: 8, padding: 2, flex: 'none' }}>
          {(['liste', 'kort'] as const).map((m) => (
            <button key={m} onClick={() => setViewMode(m)} style={{
              border: 'none', cursor: 'pointer', fontSize: 11.5, fontWeight: 600, padding: '6px 12px', borderRadius: 6,
              background: viewMode === m ? T.paper : 'transparent', color: viewMode === m ? T.bordeaux : T.muted,
            }}>{m === 'liste' ? 'Liste' : 'Kort'}</button>
          ))}
        </div>
      </div>
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 20 }}>Besiddelser knyttet til slægten — klik for ejerrækken gennem tiden.</div>
      {!estates ? <div style={{ color: T.muted3 }}>Henter…</div> : !estates.length ? <div style={{ color: T.muted3 }}>Ingen godser registreret.</div> : viewMode === 'kort' ? (
        points.length ? (
          <div style={{ flex: 1, minHeight: 0 }}>
            <GeoMap points={points} mode="explorer" onPointPress={(p) => p.estateId && onOpen(p.estateId)} />
          </div>
        ) : <div style={{ color: T.muted3 }}>Ingen godser er kortlagt endnu.</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(220px,1fr))', gap: 12 }}>
          {estates.map((e) => (
            <div key={e.id} onClick={() => onOpen(e.id)} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: 15, cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.03)' }}>
              <span style={{ width: 36, height: 36, borderRadius: 8, background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 17, color: T.bordeaux }}>⌂</span>
              <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 11 }}>{e.navn}</div>
              <div style={{ fontSize: 11.5, color: T.muted, marginTop: 3 }}>{[e.slags, e.ownerCount ? `${e.ownerCount} tilknytning${e.ownerCount === 1 ? '' : 'er'}` : ''].filter(Boolean).join(' · ') || '—'}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---- Slægtens kort (overbliks-kort) ----
// Fuldskærms-kort over ALLE geo-punkter (personhændelser + godser), filtrerbart pr. linje.
// v1: kun linje-filter (type-filter/år-slider/"nær mig" er senere skiver — se claude.md kort-plan).
function OverviewMapView({ model, onPickPerson, onPickEstate }: {
  model: Model | null; onPickPerson: (id: string) => void; onPickEstate: (id: string) => void;
}) {
  const [linje, setLinje] = useState<string | null>(null);
  const allPoints = model?.geo?.points ?? [];
  const linjeList = model?.lineage?.list ?? [];
  const points = linje ? filterByLineage(allPoints, model?.lineage?.byPerson ?? {}, linje, { includeNonPerson: true }) : allPoints;
  const chip = (active: boolean): CSSProperties => ({
    fontSize: 11.5, fontWeight: 600, padding: '6px 12px', borderRadius: 999, cursor: 'pointer',
    border: '1px solid ' + (active ? 'rgba(136,26,51,.3)' : 'rgba(34,31,26,.1)'),
    background: active ? '#f4e2e6' : T.beige, color: active ? T.bordeaux : T.muted,
  });
  return (
    <div style={{ padding: '30px 40px 0', height: 'calc(100vh - 60px)', display: 'flex', flexDirection: 'column' }}>
      <ViewHeader title="Slægtens kort" />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 12 }}>
        {points.length} {points.length === 1 ? 'sted' : 'steder'} kortlagt{linje ? ` for ${linjeList.find((l) => l.linje === linje)?.navn ?? 'linje ' + linje}` : ' — flere følger efterhånden som slægtens steder kortlægges'}.
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 16 }}>
        <button onClick={() => setLinje(null)} style={chip(linje === null)}>Hele slægten</button>
        {linjeList.map((l) => (
          <button key={l.linje} onClick={() => setLinje(l.linje)} style={chip(linje === l.linje)}>
            {l.navn ?? `Linje ${l.linje}`}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, paddingBottom: 24 }}>
        {points.length ? (
          <GeoMap
            points={points}
            mode="explorer"
            onPointPress={(p) => { if (p.personId) onPickPerson(p.personId); else if (p.estateId) onPickEstate(p.estateId); }}
          />
        ) : <div style={{ color: T.muted3 }}>Ingen steder kortlagt endnu{linje ? ' for denne linje' : ''}.</div>}
      </div>
    </div>
  );
}

// ---- Slægtens våben ----
function ArmsView({ arms }: { arms: ArmsItem[] | null }) {
  const [lightbox, setLightbox] = useState<number | null>(null);
  const main = arms?.[0];
  const rest = (arms ?? []).slice(1);
  const mainCrest = main ? firstSignable(main.media) : null; // første signerbare (ikke blindt media[0])
  const variantImgs = rest.map((v) => firstSignable(v.media));
  // Lightbox (Slice A): hoved-våben + alle varianter er ÉT navigerbart sæt.
  const lightboxItems = withUrl([mainCrest, ...variantImgs]);
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <ViewHeader title="Slægtens våben" mb="18px" />
      {!arms ? <div style={{ color: T.muted3 }}>Henter…</div> : (
        <>
          <div style={{ background: T.ink, borderRadius: 16, padding: 26, display: 'flex', gap: 24, alignItems: 'center' }}>
            {mainCrest ? (
              <div style={{ flex: 'none' }}><MediaThumb m={mainCrest} w={150} h={185} radius={10} onClick={() => setLightbox(0)} /></div>
            ) : (
              <div style={{ width: 150, height: 185, borderRadius: 10, background: 'repeating-linear-gradient(45deg,#3a352c 0 9px,#322d25 9px 18px)', border: '1px solid rgba(231,201,143,.2)', flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ fontFamily: T.mono, fontSize: 10, color: T.gold }}>våbenskjold</span></div>
            )}
            <div>
              <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.goldLight }}>Autoriseret våben</div>
              <div style={{ fontSize: 12, color: T.cream, marginTop: 3 }}>Dansk Adels Forenings gældende gengivelse</div>
              <div style={{ fontFamily: T.serif, fontSize: 17, fontStyle: 'italic', lineHeight: 1.45, color: T.paper, marginTop: 14 }}>{main?.blasonering || 'Blasonering ikke registreret.'}</div>
              {main?.note && <div style={{ fontSize: 11.5, color: T.cream, marginTop: 10, lineHeight: 1.45 }}>{main.note}</div>}
            </div>
          </div>
          {rest.length > 0 && (
            <>
              <Label>Øvrige gengivelser &amp; varianter</Label>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 12 }}>
                {rest.map((v, i) => {
                  const vImg = variantImgs[i]; // første signerbare variant-billede
                  return (
                    <div key={v.id} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: 11 }}>
                      {/* Fast .82-aspekt uanset billede/placeholder, så grid-cellerne flugter. */}
                      {vImg ? (
                        <div style={{ width: '100%', aspectRatio: '.82', borderRadius: 8, overflow: 'hidden' }}>
                          <MediaThumb m={vImg} w="100%" h="100%" radius={8}
                            onClick={() => setLightbox(lightboxItems.findIndex((x) => x.id === vImg.id))} />
                        </div>
                      ) : (
                        <div style={{ width: '100%', aspectRatio: '.82', borderRadius: 8, background: 'repeating-linear-gradient(45deg,#ece4d6 0 8px,#e2d8c8 8px 16px)', border: '1px solid rgba(34,31,26,.08)' }} />
                      )}
                      <div style={{ fontFamily: T.serif, fontSize: 14, fontWeight: 600, marginTop: 7, lineHeight: 1.1 }}>{v.note || v.blasonering.slice(0, 40) || 'variant'}</div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </>
      )}
      {lightbox != null && (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </div>
  );
}

// ---- Om slægten ----
function AboutView({ about, personCount, estateCount, onPick }: { about: AboutSection[] | null; personCount: number; estateCount: number | null; onPick: (id: string) => void }) {
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 680 }}>
      <div style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, lineHeight: 1.02 }}>Slægten Reventlow</div>
      <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted2, marginTop: 8 }}>Indledning til stamtavlen · Danmarks Adels Aarbog</div>
      <div style={{ display: 'flex', gap: 22, marginTop: 16 }}>
        <Counter n={personCount} label="personer" />
        {estateCount != null && <Counter n={estateCount} label="godser" />}
      </div>
      <div style={{ height: 1, background: 'rgba(34,31,26,.12)', margin: '20px 0' }} />
      {/* NarrativRenderer (Slice C4): samme blok-renderer som person-bio/gods-narrativ — understøtter
          nu ##-overskrifter/linjeskift/indlejrede billeder i selve prosaen, ikke kun rå pre-wrap-tekst. */}
      {!about ? <div style={{ color: T.muted3 }}>Henter…</div> : about.length ? about.map((s, i) => (
        <div key={i} style={{ marginBottom: 24 }}>
          {s.lineageNavn && <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, marginBottom: 8, color: T.bordeaux }}>{s.lineageNavn}</div>}
          <div style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.6, color: '#3d382f' }}>
            <NarrativRenderer tekst={s.tekst} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} />
          </div>
        </div>
      )) : (
        <div style={{ border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 16, background: T.paper, fontSize: 13, lineHeight: 1.5, color: T.muted }}>
          Ingen slægts-narrativ registreret endnu. Indledningen indlæses fra stamtavlen (narrative · subjekt_type slaegt).
        </div>
      )}
    </div>
  );
}
const Counter = ({ n, label }: { n: number; label: string }) => (
  <div><span style={{ fontFamily: T.serif, fontSize: 28, fontWeight: 600, color: T.bordeaux }}>{n.toLocaleString('da')}</span> <span style={{ fontSize: 12.5, color: T.muted }}>{label}</span></div>
);
// Sidebar-statistik-celle (tal over label). n=null → placeholder mens data hentes.
// Gren-filter-chip (§9.2). Aktiv = bordeaux fyld.
const LinjeChip = ({ label, active, onClick, title }: { label: string; active: boolean; onClick: () => void; title?: string }) => (
  <div onClick={onClick} title={title} style={{ padding: '5px 11px', borderRadius: 15, fontFamily: T.sans, fontSize: 11.5, fontWeight: 600, cursor: 'pointer', background: active ? T.bordeaux : 'transparent', color: active ? T.paper : T.muted, border: `1px solid ${active ? T.bordeaux : 'rgba(34,31,26,.18)'}` }}>{label}</div>
);

// ---- små byggeklodser ----
// Kicker/H1/ViewHeader/Avatar/BookmarkFlag flyttet til ./components/primitives (delt med
// BookmarksView/SlaegtPicker — /simplify-fund, review 19b).
const Label = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 12px' }}>{children}</div>;
const Stem = ({ h, mt = 0 }: { h: number; mt?: number }) => <div style={{ width: 1, height: h, background: 'rgba(34,31,26,.22)', marginTop: mt }} />;

// Start-fokus midt i træet: en person med BÅDE børn og forælder, flest børn (som mobil).
// Fallback: flest børn generelt; ellers første person.
function startFokus(m: Model): string | null {
  let best: string | null = null; let max = -1;
  for (const p of m.persons) {
    const n = m.indexes.childIdx[p.id]?.size ?? 0;
    if (n > 0 && p.parentId && n > max) { max = n; best = p.id; }
  }
  if (!best) for (const p of m.persons) { const n = m.indexes.childIdx[p.id]?.size ?? 0; if (n > max) { max = n; best = p.id; } }
  return best ?? m.persons[0]?.id ?? null;
}

function describeErr(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  return /permission|row-level|JWT|PGRST|policy/i.test(m) ? m + '\n\nMangler måske anon-læseadgang — kør web/dev-rls.sql i Supabase.' : m;
}
