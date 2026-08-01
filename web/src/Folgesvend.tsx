// Publikums-følgesvend (web) — port af design/project/Reventlow-web-v2.dc.html,
// layout siden opdateret efter Reventlow-web-v3.dc.html (søg/gennemse som modalt overlay
// i stedet for en permanent sidebar, så stamtræ + detalje-panel deler hele skærmen).
// Header-nav · center-visning · detalje-panel. To visninger bygget: Stamtræ
// (variant A, fokus-centreret) og Slægtskab ("Er vi i familie?", med multi-linje + konfidens
// + korroboration fra den porterede finder). Godser/Våben/Om/Kort/Bogmærker følger.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { navigate, usePath } from './router';
import { Link } from './Link';
import { loadModel } from './data/model';
import { initials } from './data/format';
import { fetchArms, fetchAbout, fetchEstates, fetchEstateInfo, fetchEstateOwners, fetchPersonDetail, TOM_PERSONDETALJE, type AboutSection, type ArmsItem, type EstateInfo, type EstateItem, type EstateOwner, type PersonDetailData } from './data/public';
import type { AppModel, Model } from './data/types';
import { computeRelationship } from '@daa/core';
import { buildBrowse, showSearchResults } from './data/browse';
import { useBookmarks, type BookmarkSort } from './data/bookmarks';
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
import { BookmarksView } from './components/BookmarksView';
import { SlaegtPicker } from './components/SlaegtPicker';
import { HomeView } from './components/HomeView';
import { TreeView } from './components/TreeView';
import { RelateView } from './components/RelateView';
import { DetailPanel } from './components/DetailPanel';
import { EstatesView } from './components/EstatesView';
import { OverviewMapView } from './components/OverviewMapView';
import PresensView from './components/PresensView';
import { ArmsView } from './components/ArmsView';
import { AboutView } from './components/AboutView';
import type { TreeSearchBundle } from './components/TreeSearch';
import { THEMES, themeOfMode, labelOfMode, parseFolgesvendPath, pathForMode, detailOpenFor, type Mode, personPath } from './data/nav';
import { SearchIcon } from './components/primitives';
import { T } from './theme';

// Kun Reventlow findes i dag; vælgeren er 1-punkt + "flere kommer"-note (spec §2 ikke-mål).
const SLAEGTER = [{ id: 'reventlow', navn: 'Reventlow' }];
const EMPTY_CANONICAL_IDS: Record<string, string> = {};
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
  const [model, setModel] = useState<AppModel | null>(null);
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

  // review 27 R2: udtrukket til en genkaldelig funktion, så fejlskærmens "Prøv igen"-knap
  // kan forsøge indlæsningen igen uden hard-reload (Supabase free-tier pauser efter 7 dages
  // inaktivitet — første kald efter en pause kan derfor fejle og lykkes ved forsøg nr. 2).
  const loadData = useCallback(() => {
    setErr(null);
    loadModel().then(setModel).catch((e) => setErr(describeErr(e)));
  }, []);
  useEffect(() => { loadData(); }, [loadData]);

  // Resolv et (evt. alias-)id til dets kanoniske (samme_som-collapse). canonicalIdById bor på
  // modellen; alle indgående id'er (fokus, rel, mig) resolves gennem det. Memoized på
  // canonicalIdById (ikke model) — /simplify-fund: en ustabil canon-reference hver render fik
  // useBookmarks' re-normaliserings-useEffect til at genkøre unødigt ved hvert tastetryk.
  const canon = useCallback((id: string) => model?.canonicalIdById?.[id] ?? id, [model?.canonicalIdById]);
  const meCanon = meId ? canon(meId) : null;
  // Bogmærker (web v3 Slice 1) — localStorage, kanonisk via canon(). bmSort default 'linje'
  // (designets første segment, spec §4). slaegtOpen = slægt-vælger-modal på header-chippen.
  const bookmarks = useBookmarks(session?.userId ?? null, model?.canonicalIdById ?? EMPTY_CANONICAL_IDS);
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
  // 'home' udløser samme hentning som 'arms' (ikke kun mode==='arms'): forsidens feed
  // (fase1-design.md §7) viser våben-kort og skal have data uden at brugeren først har
  // besøgt Våben-siden.
  useEffect(() => { if ((mode === 'arms' || mode === 'home') && !arms) fetchArms().then(setArms).catch(() => setArms([])); }, [mode, arms]);
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
    // Ingen bog-nummer (typisk en ægtefælle) → hent proveniens fra citationerne i stedet.
    const manglerBogNummer = !(model?.sourcesBy?.[focusId]?.length);
    fetchPersonDetail(focusId, members, manglerBogNummer).then(setDetail).catch(() => setDetail(TOM_PERSONDETALJE));
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

  // Lazy geo-kæde (review 27 P3): place+fact hentes IKKE ved cold-start (se loadModel) —
  // kun de tre kort-bærende flader udløser hentningen, og kun ÉN gang (geoRequestedRef er en
  // ref, ikke state, så gentagne mode-skift ikke refetcher selvom resultatet reelt blev tomt).
  // 'estates'/'kort' er selvforklarende kort-visninger; detailOpen dækker minikortet i
  // detalje-panelet (der kan åbne fra BÅDE 'tree' og 'relate' — vi kender ikke points.length
  // for den fokuserede person før geo er hentet, så vi henter så snart panelet er åbent).
  const geoRequestedRef = useRef(false);
  const [geoLoading, setGeoLoading] = useState(false);
  useEffect(() => {
    const needsGeo = mode === 'estates' || mode === 'kort' || detailOpen;
    if (!needsGeo || !model || geoRequestedRef.current) return;
    geoRequestedRef.current = true;
    setGeoLoading(true);
    model.loadGeo()
      .then((geo) => setModel((m) => (m ? { ...m, geo } : m)))
      .catch((e) => console.warn('[Folgesvend] geo-hentning fejlede — intet kort:', e))
      .finally(() => setGeoLoading(false));
  }, [mode, detailOpen, model]);

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

  if (err) {
    return (
      <div style={{ minHeight: '100vh', background: T.pageBg, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, fontFamily: T.sans }}>
        <div style={{ maxWidth: 420, background: T.paper, borderRadius: 16, border: `1px solid ${T.cream}`, padding: '32px 28px', textAlign: 'center' }}>
          <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.bordeaux, marginBottom: 12 }}>Kunne ikke hente data</div>
          <div style={{ color: T.ink, whiteSpace: 'pre-wrap', fontSize: 15, marginBottom: 14 }}>{err}</div>
          <div style={{ color: T.muted, fontSize: 14, marginBottom: 20 }}>
            Databasen kan være gået i dvale efter en periode uden aktivitet. Vent et øjeblik og prøv igen.
          </div>
          <button
            onClick={loadData}
            style={{ background: T.bordeaux, color: T.paper, border: 'none', borderRadius: 10, padding: '10px 22px', fontFamily: T.sans, fontSize: 15, fontWeight: 600, cursor: 'pointer' }}
          >
            Prøv igen
          </button>
        </div>
      </div>
    );
  }
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
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.16em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Følgesvend · Dansk Adels Forening</div>
          </div>
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
          {THEMES.map((t) => {
            const active = activeTheme === t.key;
            return (
              <div key={t.key} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '9px 16px', borderRadius: 9, fontFamily: T.sans, fontSize: 15, fontWeight: 600, whiteSpace: 'nowrap', color: active ? T.bordeaux : '#3d382f' }}>
                {t.label}<span style={{ fontSize: 10, color: active ? T.bordeaux : T.muted2 }}>▾</span>
              </div>
            );
          })}
        </div>
        <div style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 12 }}>
          {/* Søg-knap — åbner søg/gennemse-modalen (v3: erstatter den permanente sidebar). */}
          <div onClick={() => { goToMode('tree'); bumpSearchFocus(); }} title="Søg &amp; gennemse personer" style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '7px 13px', cursor: 'pointer' }}>
            <SearchIcon size={15} />
            <span style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: '#3d382f' }}>Søg</span>
          </div>
          {/* Slægt-chip — åbner slægt-vælger-modal (kosmetisk, kun Reventlow findes — spec §3.3). */}
          <div onClick={() => setSlaegtOpen(true)} style={{ display: 'flex', alignItems: 'center', gap: 9, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '6px 12px', cursor: 'pointer' }}>
            <span style={{ width: 26, height: 26, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', boxShadow: 'inset 0 0 0 2px #f4efe6, inset 0 0 0 2.5px rgba(136,26,51,.28)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 14, fontWeight: 600, color: T.bordeaux }}>R</span>
            <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: T.ink }}>Reventlow</span>
            <span style={{ fontSize: 11, color: T.muted2 }}>▾</span>
          </div>
          {/* Konto-indikator (bogmærke-login) — minimal, ikke en fuld kontoflade (spec §6). */}
          {session ? (
            <div onClick={() => { void doLogout(); }} title={session.email} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.muted, cursor: 'pointer' }}>Log ud</div>
          ) : (
            <div onClick={() => setLoginOpen(true)} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>Log ind</div>
          )}
          {meCanon && model?.byId[meCanon] && (
            <Link href={personPath(meCanon)} onNavigate={() => navigateTree(meCanon)} title="Din plads i slægten" style={{ width: 38, height: 38, borderRadius: '50%', background: '#f8ecef', border: `1.5px solid ${T.bordeaux}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(model.byId[meCanon].name)}</Link>
          )}
          <Link href="/redaktion" style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>Redaktion ↗</Link>
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
              <div style={{ fontFamily: T.sans, fontSize: 13.5, color: T.muted, marginTop: 6, lineHeight: 1.45 }}>Følgesvend · Dansk Adels Forening. En digital ledsager til det trykte værk.</div>
              <div onClick={() => goToMode('home')} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 16, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>‹ Til forsiden</div>
            </div>
            <div style={{ flex: 1, display: 'flex', gap: 32 }}>
              {THEMES.map((t) => (
                <div key={t.key} style={{ flex: 1 }}>
                  <div style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', color: T.gold, paddingBottom: 10, borderBottom: '1px solid rgba(34,31,26,.1)' }}>{t.label}</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 1, marginTop: 10 }}>
                    {t.items.map((it) => {
                      const live = it.mode !== null;
                      const active = it.mode === mode;
                      return (
                        <div key={it.label} onClick={() => { if (it.mode) goToMode(it.mode); }} title={live ? '' : 'Kommer'} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: active ? T.bordeaux : (live ? T.ink : T.muted3), padding: '6px 0', cursor: live ? 'pointer' : 'default' }}>
                          <span>{it.label}</span>
                          {live
                            ? <span style={{ fontFamily: T.mono, fontSize: 10, color: active ? T.bordeaux : '#1f8a5b' }}>✓</span>
                            : <span style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted3 }}>kommer</span>}
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
          {mode === 'home' ? <HomeView model={model} personCount={persons.length} estates={estates} onPickPerson={navigateTree} onOpenSearch={() => { goToMode('tree'); bumpSearchFocus(); }} onBrowseAll={() => { goToMode('tree'); setBrowsing(true); }} onOpenEstate={(id) => { setEstateId(id); navigate(`/estate/${id}`); }} onGoTree={() => goToMode('tree')}
              arms={arms} meId={meCanon} focusId={focusId} bookmarkedIds={bookmarkIds}
              bookmarksReady={bookmarks.ready} bookmarkHydrationVersion={bookmarks.hydrationVersion}
              bookmarkOwnerId={session?.userId ?? null}
              hasBookmark={bookmarks.has} onSaveBookmark={saveOrPrompt} onOpenArms={() => goToMode('arms')}
              onOpenSlaegt={(aId, bId) => { setRelA(aId); setRelB(bId); setRelSlot('B'); goToMode('relate'); }} />
            : mode === 'tree' ? <TreeView model={model} focusId={focusId} onPick={treePick} onFocus={driftFocus} hasBookmark={bookmarks.has} onToggleBookmark={saveOrPrompt} search={treeSearch} />
            : mode === 'relate' ? <RelateView model={model} rel={rel} relA={relA} relB={relB} slot={relSlot} setSlot={setRelSlot} onPickStep={focusOnly} meId={meCanon} onSetMeA={() => { if (meCanon) { setRelA(meCanon); setRelSlot('B'); } }} search={treeSearch} />
            : mode === 'estates' ? <EstatesView estates={estates} estateId={estateId} estate={estates?.find((e) => e.id === estateId) ?? null} info={estateInfo} owners={estateOwners} geo={model?.geo} geoLoading={geoLoading} onOpen={(id) => { setEstateId(id); navigate(`/estate/${id}`); }} onBack={() => { setEstateId(null); navigate('/estates'); }} onPickOwner={navigateTree} />
            : mode === 'arms' ? <ArmsView arms={arms} />
            : mode === 'about' ? <AboutView about={about} personCount={persons.length} estateCount={estates?.length ?? null} onPick={navigateTree} />
            : mode === 'bookmarks' ? (model ? <BookmarksView model={model} ids={bookmarkIds} sort={bmSort} setSort={setBmSort} onPick={pickBookmark} onRemove={saveOrPrompt} loggedIn={bookmarks.canSave} onRequireLogin={() => setLoginOpen(true)} /> : <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>)
            : mode === 'kort' ? <OverviewMapView model={model} geoLoading={geoLoading} onPickPerson={navigateTree} onPickEstate={(id) => navigate(`/estate/${id}`)} />
            : mode === 'praesens' ? <PresensView model={model} onPickPerson={navigateTree} />
            : <Placeholder label={labelOfMode(mode)} />}
        </div>

        {/* Højre: person-detalje (kun i person-centriske visninger) */}
        {detailOpen && model && focusId && (
          <DetailPanel
            model={model} focusId={focusId} detail={detail} onPick={mode === 'tree' ? navigateTree : focusOnly}
            backName={backName} onBack={() => window.history.back()} onClose={mode === 'tree' ? closeDetail : undefined}
            onFocusTree={() => goToMode('tree')}
            onRelate={() => { setRelA(focusId); setRelB(null); setRelSlot('B'); goToMode('relate'); }}
            onVisPraesens={() => navigate('/praesens', { state: { fokusId: focusId } })}
            isMe={focusId === meCanon} onToggleMe={() => toggleMe(focusId)}
            isBookmarked={bookmarks.has(focusId)} onToggleBookmark={() => saveOrPrompt(focusId)}
            geoLoading={geoLoading}
          />
        )}
      </div>

      <SlaegtPicker open={slaegtOpen} slaegter={SLAEGTER} activeId="reventlow" onClose={() => setSlaegtOpen(false)} onPick={() => setSlaegtOpen(false)} />

      {loginOpen && (
        <div onClick={() => setLoginOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(20,17,13,.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ width: 380, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '22px 24px 20px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>Log ind</div>
            <div style={{ fontSize: 13, color: T.muted, marginTop: 3, marginBottom: 15 }}>Log ind for at gemme bogmærker på tværs af dine enheder.</div>
            <input value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} placeholder="din@email.dk" style={{ width: '100%', fontSize: 14, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none' }} />
            <input value={login.pw} type="password" onChange={(e) => setLogin((l) => ({ ...l, pw: e.target.value }))} style={{ width: '100%', fontSize: 14, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none', marginTop: 11 }} />
            {login.err && <div style={{ fontSize: 12.5, color: T.bordeaux, marginTop: 9 }}>{login.err}</div>}
            <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end' }}>
              <div onClick={() => setLoginOpen(false)} style={{ fontSize: 13, fontWeight: 600, color: T.muted, padding: '8px 13px', cursor: 'pointer' }}>Annullér</div>
              <div onClick={doLogin} style={{ fontSize: 13, fontWeight: 600, color: '#fbf8f1', background: T.bordeaux, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>{login.busy ? 'Logger ind…' : 'Log ind'}</div>
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
