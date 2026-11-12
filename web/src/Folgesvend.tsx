// Publikums-følgesvend (web) — port af design/project/Reventlow-web-v2.dc.html,
// layout siden opdateret efter Reventlow-web-v3.dc.html (søg/gennemse som modalt overlay
// i stedet for en permanent sidebar, så stamtræ + detalje-panel deler hele skærmen).
// Header-nav · center-visning · detalje-panel. To visninger bygget: Stamtræ
// (variant A, fokus-centreret) og Slægtskab ("Er vi i familie?", med multi-linje + konfidens
// + korroboration fra den porterede finder). Godser/Våben/Om/Kort/Bogmærker følger.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { navigate, useLocation } from './router';
import { Link } from './Link';
import { loadModel } from './data/model';
import { initials } from './data/format';
import { fetchArms, fetchAbout, fetchEstates, fetchEstateInfo, fetchEstateOwners, fetchPersonDetail, type AboutSection, type ArmsItem, type EstateInfo, type EstateItem, type EstateOwner, type PersonDetailData } from './data/public';
import { personMemberIds } from './data/personMembers';
import type { AppModel, Model } from './data/types';
import { computeRelationship } from '@daa/core';
import { buildBrowse, showSearchResults } from './data/browse';
import { useBookmarks, type BookmarkSort } from './data/bookmarks';
import { signIn, signOut, currentSession, loginFejlTekst, type RedSession } from './data/auth';
import { BookmarksView } from './components/BookmarksView';
import { Sidehoved, type HovedpunktAktiv } from './components/Sidehoved';
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
import { synligeLinjer } from './data/lineage';
import { labelOfMode, parseFolgesvendPath, pathForMode, detailOpenFor, type Mode, personPath, estatePath, stamtraePath, STANDARD_SLAEGT, SLAEGTER, findSlaegt } from './data/nav';
import { Tilstand, tilstandPrimaer, tilstandSekundaer } from './components/Tilstand';
import { T } from './theme';

const EMPTY_CANONICAL_IDS: Record<string, string> = {};
// Mode og URL-grammatik bor i ./data/nav (ren + unit-testet).

export default function Folgesvend() {
  const loc = useLocation();
  const parsed = useMemo(() => parseFolgesvendPath(loc.path, loc.search), [loc]);
  const slug = parsed.slaegt ?? STANDARD_SLAEGT;
  const [model, setModel] = useState<AppModel | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // mode/focusId/estateId initialiseres SYNKRONT fra URL'en ved mount (parseFolgesvendPath er
  // ren streng-parsing, kræver ikke modellen) — undgår et synligt "flash" af startFokus's default
  // før et gyldigt URL-id kan overtage. Validering (findes id'et? kanonisk id?) OG al senere
  // synkronisering (egen navigation såvel som browserens back/forward) sker i den path-drevne
  // effekt nedenfor, der reagerer på usePath() — se dens kommentar.
  const initialPath = parseFolgesvendPath(window.location.pathname, window.location.search);
  const [mode, setMode] = useState<Mode>(() => initialPath.mode);
  const [focusId, setFocusId] = useState<string | null>(() => initialPath.personId ?? initialPath.fokusId);
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
  // sessionKlar: er den gemte session tjekket? Præsenslisten må ikke vise »log ind« til en
  // redaktør, mens sessionen stadig genskabes.
  const [sessionKlar, setSessionKlar] = useState(false);
  const [loginOpen, setLoginOpen] = useState(false);
  const [login, setLogin] = useState<{ email: string; pw: string; err: string; busy: boolean }>(
    { email: '', pw: '', err: '', busy: false },
  );
  useEffect(() => {
    // review 22 N3: currentSession() kan i princippet afvises (netværksfejl) — sluges ikke
    // tavst, men sætter session til null (allerede default) og logger til konsol.
    currentSession().then(setSession, (e) => console.warn('[session] kunne ikke genskabes', e)).finally(() => setSessionKlar(true));
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
      setLogin((l) => ({ ...l, busy: false, err: loginFejlTekst(e) }));
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
  const [detailError, setDetailError] = useState<string | null>(null);
  const [detailForsoeg, setDetailForsoeg] = useState(0); // »Prøv igen« i personpanelets fejl

  // review 27 R2: udtrukket til en genkaldelig funktion, så fejlskærmens "Prøv igen"-knap
  // kan forsøge indlæsningen igen uden hard-reload (Supabase free-tier pauser efter 7 dages
  // inaktivitet — første kald efter en pause kan derfor fejle og lykkes ved forsøg nr. 2).
  const loadData = useCallback(() => {
    setErr(null);
    // Den rå fejl (og udviklerens RLS-hint) går til konsollen; læseren får en forklaring i ord.
    loadModel().then(setModel).catch((e) => { console.warn('[Folgesvend] model-hentning fejlede:', describeErr(e)); setErr('fejl'); });
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
  // Slægter-menuen (sidehovedet). aabnerRef = elementet der åbnede den (knappen eller bjælkens
  // »Skift slægt«), så Esc kan sende fokus tilbage dertil.
  const [menuAaben, setMenuAabenState] = useState(false);
  const menuKnap = useRef<HTMLButtonElement>(null);
  const aabnerRef = useRef<HTMLElement | null>(null);
  const setMenuAaben = useCallback((aaben: boolean, returFokus = false) => {
    if (aaben) aabnerRef.current = (document.activeElement as HTMLElement | null) ?? menuKnap.current;
    setMenuAabenState(aaben);
    if (!aaben && returFokus) (aabnerRef.current ?? menuKnap.current)?.focus();
  }, []);
  // Senest besøgte slægt (Slægter-menuen). Kun gyldige slugs gemmes.
  const [senestSlaegt, setSenestSlaegt] = useState<string | null>(() => {
    try { return window.localStorage.getItem('daa_senest_slaegt'); } catch { return null; }
  });
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
      navigate(pathForMode('estates'), { replace: true });
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
    if (!focusId) { setDetail(null); setDetailError(null); return; }
    let current = true;
    setDetail(null);
    setDetailError(null);
    // Foldet person: hent detalje for ALLE medlems-id'er (narrativ/relationer unioneres — spec §8).
    const members = personMemberIds(focusId, model?.byId[focusId]);
    // Ingen bog-nummer (typisk en ægtefælle) → hent proveniens fra citationerne i stedet.
    const manglerBogNummer = !(model?.sourcesBy?.[focusId]?.length);
    fetchPersonDetail(focusId, members, manglerBogNummer, model ? { udgaver: model.udgaver ?? [], udgaveForPersonRaekke: model.udgaveForPersonRaekke ?? {} } : undefined).then(
      (next) => { if (current) setDetail(next); },
      (e) => { if (current) { console.warn('[Folgesvend] persondetalje fejlede:', e); setDetailError(String((e as Error)?.message ?? e)); } },
    );
    return () => { current = false; };
  }, [focusId, model, detailForsoeg]);

  const persons = model?.persons ?? [];
  const linjeList = useMemo(() => synligeLinjer(model?.lineage?.list ?? []), [model]);
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
  // Hvor en person vises: inde i slægtens stamtræ bliver man i træet (…/stamtrae?fokus=<id>), så
  // slægtsbjælken bliver stående; udefra (feed, søgning, bogmærker) er det /person/<id>. href og
  // klik bruger samme funktion, så cmd-klik åbner samme adresse som et almindeligt klik.
  const iSlaegtensTrae = mode === 'tree' && parsed.slaegt !== null;
  const visPersonPath = (id: string) => (iSlaegtensTrae ? stamtraePath(slug, id) : personPath(id));
  const navigateTree = (id: string) => {
    const cid = canon(id);
    const prev = focusId && focusId !== cid ? focusId : null;
    setPrevFocusId(prev);
    setFocusId(cid);
    setMode('tree');
    clearSearch(); // en "rigtig" navigation lader personen blive centrum i træet; resultat-grid'et viger (§4.1)
    navigate(visPersonPath(cid), { state: { prevFocusId: prev } });
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
    navigate(visPersonPath(cid), { replace: true, state: { prevFocusId } });
  };
  // Menuen lukker ved enhver navigation; besøgte slægter huskes til »Senest besøgt«.
  useEffect(() => { setMenuAabenState(false); }, [loc]);
  useEffect(() => {
    if (!findSlaegt(parsed.slaegt)) return;
    setSenestSlaegt(parsed.slaegt);
    try { window.localStorage.setItem('daa_senest_slaegt', parsed.slaegt!); } catch { /* privat vindue */ }
  }, [parsed.slaegt]);

  // Fane-skift (sidehoved, slægtsbjælke og detalje-panelets "Sæt i fokus"/"Find slægtskab").
  const goToMode = (m: Mode, tilSlaegt: string = slug) => {
    setMenuAabenState(false);
    setMode(m);
    if (m === 'estates') setEstateId(null);
    navigate(m === 'tree' && focusId ? stamtraePath(tilSlaegt, focusId) : pathForMode(m, tilSlaegt));
  };
  const backName = prevFocusId && model ? (model.byId[prevFocusId]?.name ?? null) : null;

  // Synkroniserer mode/focusId/estateId/prevFocusId med den AKTUELLE URL (usePath() reagerer
  // BÅDE på egne navigate()-kald OG på browserens back/forward — /simplify-fund: erstatter en
  // hånd-rullet window.addEventListener('popstate', …) med den delte hook router.ts allerede
  // eksponerer til formålet). Kører også første gang modellen bliver klar (null → model), hvor
  // den validerer/kanoniserer et evt. URL-id og retter URL'en hvis nødvendigt (alias/ugyldigt id)
  // — samme arbejde mount-effekten lavede før, nu ét sted for både mount og efterfølgende navigation.
  // Gamle stier (/stamtrae, /estates, /estate/<id> …) erstattes med de nye. Parseren har allerede
  // givet den rigtige mode, så første render er rigtig; history.state (»Tilbage til X«, fokusId)
  // og hash bevares.
  useEffect(() => {
    if (!parsed.omdiriger) return;
    const [ny, nyQ = ''] = parsed.omdiriger.split('?');
    const q = new URLSearchParams(nyQ);
    new URLSearchParams(loc.search).forEach((v, k) => { if (!q.has(k)) q.set(k, v); });
    const qs = q.toString();
    navigate(`${ny}${qs ? `?${qs}` : ''}${window.location.hash}`, { replace: true, state: window.history.state });
  }, [parsed, loc.search]);

  useEffect(() => {
    if (!model) return;
    const p = parsed;
    setMode(p.mode);
    setEstateId(p.estateId);
    setPrevFocusId((window.history.state as { prevFocusId?: string | null } | null)?.prevFocusId ?? null);
    if (p.mode !== 'tree') return;
    const urlId = p.personId ?? p.fokusId;
    if (!urlId) {
      // /stamtrae bærer ikke selv et fokus-id. Split-skærm (§5): når man LUKKER detaljen navigeres
      // hertil, og træet skal blive stående på samme centrum — så bevar et allerede sat focusId og
      // fald kun tilbage til det deterministiske startFokus ved kold start (matcher altid samme
      // person for samme model).
      setFocusId((cur) => cur ?? startFokus(model));
      return;
    }
    const cid = canon(urlId);
    const tilSammeSlags = (id: string) => (p.personId ? personPath(id) : stamtraePath(p.slaegt ?? STANDARD_SLAEGT, id));
    if (model.byId[cid]) {
      setFocusId(cid);
      if (cid !== urlId) navigate(tilSammeSlags(cid), { replace: true, state: window.history.state }); // alias → kanonisk
    } else {
      setFocusId(startFokus(model));
      navigate(stamtraePath(p.slaegt ?? STANDARD_SLAEGT), { replace: true }); // ugyldigt/slettet id — forkast til træet uden fokus frem for at foregive et gæt
    }
  }, [parsed, model, canon]);

  // Split-skærm (§5): detalje-panelet er åbent når URL'en bærer en eksplicit person (tree) /
  // et fokus er inspiceret (relate). closeDetail navigerer til /stamtrae (replace) — træets centrum
  // bevares (se path-sync ovenfor), kun detaljen viger. Escape lukker også.
  const detailOpen = detailOpenFor(mode, parsed.personId ?? parsed.fokusId, focusId);
  const closeDetail = () => navigate(stamtraePath(slug), { replace: true });
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

  // Modellen hentes igen, når brugeren logger ind eller ud: RLS afgør, hvilke personer (levende)
  // den rummer, og ellers ville fx præsensmurens »Log ind« føre en redaktør til en liste uden
  // levende, indtil siden blev genindlæst. Første tjek af den gemte session udløser ikke en ny
  // hentning (den første hentning sker allerede med den gemte session).
  const brugerId = session?.userId ?? null;
  const forrigeBrugerRef = useRef<string | null | undefined>(undefined);
  useEffect(() => {
    if (!sessionKlar) return;
    if (forrigeBrugerRef.current === undefined) { forrigeBrugerRef.current = brugerId; return; }
    if (forrigeBrugerRef.current === brugerId) return;
    forrigeBrugerRef.current = brugerId;
    geoRequestedRef.current = false; // den nye model har ingen geo; lad geo-effekten hente igen
    loadData();
  }, [brugerId, sessionKlar, loadData]);

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
      <div style={{ minHeight: '100vh', background: T.surfaceGround, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        {/* Vi kender ikke årsagen her: dvale efter en uges stilstand er den hyppigste, men en
            rigtig fejl ser ens ud for læseren. Teksten gætter derfor ikke; fejlen står i konsollen. */}
        <Tilstand fejl etiket="Kunne ikke hente" titel="Aarbogen svarer ikke lige nu"
          handlinger={<button type="button" onClick={loadData} style={tilstandPrimaer}>Prøv igen</button>}>
          Har der ikke været besøg et stykke tid, tager det et øjeblik at åbne arkivet, så prøv igen om et halvt minut. Hjælper det ikke, er fejlen hos os.
        </Tilstand>
      </div>
    );
  }
  const hovedpunkt: HovedpunktAktiv = mode === 'soeg' || (mode === 'tree' && parsed.personId) ? 'personer'
    : parsed.slaegt ? 'slaegter' : mode === 'relate' ? 'slaegtskab' : null;

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
    personHref: visPersonPath,
  };

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.surfaceGround, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      <Sidehoved
        aktiv={hovedpunkt} menuAaben={menuAaben} setMenuAaben={setMenuAaben} menuKnap={menuKnap}
        slaegter={SLAEGTER} senestSlaegt={senestSlaegt} aktivSlaegt={parsed.slaegt}
        onVaelgSlaegt={(s) => goToMode('about', s)}
        onPersoner={() => { goToMode('tree'); setBrowsing(true); }}
        onSlaegtskab={() => goToMode('relate')} onForside={() => goToMode('home')}
        loggetInd={!!session} onLogin={() => setLoginOpen(true)} onLogout={() => { void doLogout(); }}
        visRedaktion={session?.role === 'redaktion'}
        ekstra={meCanon && model?.byId[meCanon] ? (
          <Link href={personPath(meCanon)} onNavigate={() => navigateTree(meCanon)} title="Din plads i slægten" aria-label="Din plads i slægten" style={{ width: 38, height: 38, borderRadius: '50%', background: T.bordeauxTint, border: `1.5px solid ${T.bordeaux}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, flex: 'none', textDecoration: 'none' }}>{initials(model.byId[meCanon].name)}</Link>
        ) : null}
      />

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>

        {/* Center */}
        <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto' }}>
          {mode === 'home' ? <HomeView model={model} personCount={persons.length} estates={estates} onPickPerson={navigateTree} onOpenSearch={() => { goToMode('tree'); bumpSearchFocus(); }} onBrowseAll={() => { goToMode('tree'); setBrowsing(true); }} onOpenEstate={(id) => { setEstateId(id); navigate(estatePath(id)); }} onGoTree={() => goToMode('tree')}
              arms={arms} meId={meCanon} focusId={focusId} bookmarkedIds={bookmarkIds}
              bookmarksReady={bookmarks.ready} bookmarkHydrationVersion={bookmarks.hydrationVersion}
              bookmarkOwnerId={session?.userId ?? null}
              hasBookmark={bookmarks.has} onSaveBookmark={saveOrPrompt} onOpenArms={() => goToMode('arms')}
              onOpenSlaegt={(aId, bId) => { setRelA(aId); setRelB(bId); setRelSlot('B'); goToMode('relate'); }} />
            : mode === 'tree' ? <TreeView model={model} focusId={focusId} personHref={visPersonPath} onPick={treePick} onFocus={driftFocus} hasBookmark={bookmarks.has} onToggleBookmark={saveOrPrompt} search={treeSearch} />
            : mode === 'relate' ? <RelateView model={model} rel={rel} relA={relA} relB={relB} slot={relSlot} setSlot={setRelSlot} onPickStep={focusOnly} meId={meCanon} onSetMeA={() => { if (meCanon) { setRelA(meCanon); setRelSlot('B'); } }} search={treeSearch} />
            : mode === 'estates' ? <EstatesView estates={estates} estateId={estateId} estate={estates?.find((e) => e.id === estateId) ?? null} info={estateInfo} owners={estateOwners} geo={model?.geo} geoLoading={geoLoading} onOpen={(id) => { setEstateId(id); navigate(estatePath(id)); }} onBack={() => { setEstateId(null); navigate(pathForMode('estates', slug)); }} onPickOwner={navigateTree} />
            : mode === 'arms' ? <ArmsView arms={arms} />
            : mode === 'about' ? <AboutView about={about} personCount={persons.length} estateCount={estates?.length ?? null} onPick={navigateTree} />
            : mode === 'bookmarks' ? (model ? <BookmarksView model={model} ids={bookmarkIds} sort={bmSort} setSort={setBmSort} onPick={pickBookmark} onRemove={saveOrPrompt} loggedIn={bookmarks.canSave} onRequireLogin={() => setLoginOpen(true)} /> : <div style={{ padding: 40, color: T.inkMuted }}>Henter…</div>)
            : mode === 'kort' ? <OverviewMapView model={model} geoLoading={geoLoading} onPickPerson={navigateTree} onPickEstate={(id) => navigate(estatePath(id))} />
            : mode === 'praesens' ? <PresensView model={model} onPickPerson={navigateTree} session={sessionKlar ? session : 'henter'} onLogin={() => setLoginOpen(true)} onGoTree={() => goToMode('tree')} />
            : mode === 'ukendtSlaegt' ? (
              <div style={{ padding: 40 }}>
                <Tilstand etiket="Findes ikke" titel="Slægten findes ikke i Aarbogen"
                  handlinger={<Link href="/" onNavigate={() => goToMode('home')} style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Til forsiden</Link>}>
                  Linket peger på en slægt eller side, Aarbogen ikke har.
                </Tilstand>
              </div>
            )
            : <Placeholder label={labelOfMode(mode)} onHome={() => goToMode('home')} />}
        </div>

        {/* Højre: person-detalje (kun i person-centriske visninger) */}
        {detailOpen && model && focusId && (detailError ? (
          <aside role="alert" style={{ width: 380, padding: 28, background: T.surfaceRaised, borderLeft: `1px solid ${T.line}`, fontFamily: T.sans }}>
            <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux }}>Kunne ikke hente personens biografi</div>
            <div style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: T.inkSecondary }}>Forbindelsen til arkivet svigtede et øjeblik. Prøv igen om lidt.</div>
            <button type="button" onClick={() => setDetailForsoeg((n) => n + 1)} style={{ ...tilstandSekundaer, marginTop: 14 }}>Prøv igen</button>
          </aside>
        ) : (
          <DetailPanel
            model={model} focusId={focusId} detail={detail} onPick={mode === 'tree' ? navigateTree : focusOnly}
            personHref={visPersonPath}
            backName={backName} onBack={() => window.history.back()} onClose={mode === 'tree' ? closeDetail : undefined}
            onFocusTree={() => goToMode('tree')}
            onRelate={() => { setRelA(focusId); setRelB(null); setRelSlot('B'); goToMode('relate'); }}
            // Præsenslisten kræver i dag rollen redaktion (PresensView); for andre er linket en
            // offentlig indgang til en side, de ikke kan se (webredesign fase 0).
            onVisPraesens={session?.role === 'redaktion' ? () => navigate(pathForMode('praesens', slug), { state: { fokusId: focusId } }) : undefined}
            isMe={focusId === meCanon} onToggleMe={() => toggleMe(focusId)}
            isBookmarked={bookmarks.has(focusId)} onToggleBookmark={() => saveOrPrompt(focusId)}
            geoLoading={geoLoading}
          />
        ))}
      </div>

      {loginOpen && (
        <div onClick={() => setLoginOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(20,17,13,.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200 }}>
          {/* Rigtig <form> med <label htmlFor>: skærmlæsere navngiver felterne, og Enter logger ind. */}
          <form onClick={(e) => e.stopPropagation()} onSubmit={(e) => { e.preventDefault(); void doLogin(); }} role="dialog" aria-modal="true" aria-labelledby="fs-login-titel" style={{ width: 380, maxWidth: '100%', background: T.surfaceRaised, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '22px 24px 20px' }}>
            <div id="fs-login-titel" style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>Log ind</div>
            <div style={{ fontSize: 13, color: T.inkMuted, marginTop: 3, marginBottom: 15 }}>Log ind for at gemme bogmærker på tværs af dine enheder.</div>
            <label htmlFor="fs-login-email" style={{ display: 'block', fontSize: 12.5, fontWeight: 600, color: T.inkMuted, marginBottom: 4 }}>E-mail</label>
            <input id="fs-login-email" type="email" autoComplete="username" value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} placeholder="din@email.dk" style={{ width: '100%', fontSize: 14, color: T.ink, background: '#fff', border: `1px solid ${T.lineStrong}`, borderRadius: 7, padding: '8px 10px', outline: 'none' }} />
            <label htmlFor="fs-login-pw" style={{ display: 'block', fontSize: 12.5, fontWeight: 600, color: T.inkMuted, marginTop: 11, marginBottom: 4 }}>Adgangskode</label>
            <input id="fs-login-pw" type="password" autoComplete="current-password" value={login.pw} onChange={(e) => setLogin((l) => ({ ...l, pw: e.target.value }))} style={{ width: '100%', fontSize: 14, color: T.ink, background: '#fff', border: `1px solid ${T.lineStrong}`, borderRadius: 7, padding: '8px 10px', outline: 'none' }} />
            {login.err && <div role="alert" style={{ fontSize: 12.5, color: T.bordeaux, marginTop: 9 }}>{login.err}</div>}
            <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end' }}>
              <button type="button" onClick={() => setLoginOpen(false)} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.inkMuted, background: 'transparent', border: 0, padding: '8px 13px', cursor: 'pointer' }}>Annullér</button>
              <button type="submit" disabled={login.busy} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.onBordeaux, background: T.bordeaux, border: 0, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>{login.busy ? 'Logger ind…' : 'Log ind'}</button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}

// Vises kun, hvis nogen følger et gammelt link til en side, der ikke er bygget; menuen viser
// aldrig sider, der ikke findes.
function Placeholder({ label, onHome }: { label: string; onHome: () => void }) {
  return (
    <div style={{ padding: 40 }}>
      <Tilstand etiket="Ikke bygget endnu" titel={label ? `${label} findes ikke endnu` : 'Siden findes ikke endnu'}
        handlinger={<Link href="/" onNavigate={onHome} style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Til forsiden</Link>}>
        Den side, linket peger på, er ikke en del af Aarbogen endnu.
      </Tilstand>
    </div>
  );
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
