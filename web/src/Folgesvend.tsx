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
import { gemMigId, laesMigId } from './data/migLager';
import { initials } from './data/format';
import { fetchArms, fetchAbout, fetchEstates, fetchEstateInfo, fetchEstateOwners, fetchPersonDetail, type AboutSection, type ArmsItem, type EstateInfo, type EstateItem, type PersonDetailData } from './data/public';
import { antalEjere, byggEjerraekke, type EjerRelation } from './data/ejerraekke';
import type { EjereTilstand } from './components/EstatesView';
import { personMemberIds } from './data/personMembers';
import type { AppModel, Model } from './data/types';
import { buildBrowse, showSearchResults } from './data/browse';
import { useBookmarks, type BookmarkSort } from './data/bookmarks';
import { signIn, signOut, currentSession, onAuthChange, loginFejlTekst, type RedSession } from './data/auth';
import { BookmarksView } from './components/BookmarksView';
import { Sidehoved, type HovedpunktAktiv } from './components/Sidehoved';
import { Slaegtsbjaelke } from './components/Slaegtsbjaelke';
import { PersonSide } from './components/PersonSide';
import { HomeView } from './components/HomeView';
import { TreeView } from './components/TreeView';
import { RelateView } from './components/RelateView';
import { SoegView } from './components/SoegView';
import { soegFiltre } from './data/soeg';
import { DetailPanel } from './components/DetailPanel';
import { EstatesView } from './components/EstatesView';
import { OverviewMapView } from './components/OverviewMapView';
import PresensView from './components/PresensView';
import { ArmsView } from './components/ArmsView';
import { AboutView } from './components/AboutView';
import { useSmalSkaerm } from './useSmalSkaerm';
import { type TreeSearchBundle } from './components/TreeSearch';
import { kanoniskeLinjerPrPerson, synligeLinjer } from './data/lineage';
import { labelOfMode, parseFolgesvendPath, pathForMode, detailOpenFor, type Mode, personPath, estatePath, stamtraePath, soegPath, slaegtskabPath, STANDARD_SLAEGT, SLAEGTER, findSlaegt } from './data/nav';
import { sidetitel, VAERK } from './data/sidetitel';
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
  // "rigtig" navigation), ikke af driftFocus (Kolonner-drill).
  const [prevFocusId, setPrevFocusId] = useState<string | null>(null);
  // "Mig" i slægten (PoC: localStorage; flyttes til profiles.reventlow_person_id ved login).
  const smal = useSmalSkaerm();
  const [meId, setMeId] = useState<string | null>(laesMigId);
  // Konto-bogmærker (spec 2026-07-06): login-eksklusiv session. "Mig" (ovenfor) forbliver
  // lokal/udskudt migration — denne session bruges KUN til bogmærker her.
  const [session, setSession] = useState<RedSession | null>(null);
  // sessionKlar: er den gemte session tjekket? Præsenslisten må ikke vise »log ind« til en
  // redaktør, mens sessionen stadig genskabes.
  const [sessionKlar, setSessionKlar] = useState(false);
  const erRedaktoer = session?.role === 'redaktion';
  const [loginOpen, setLoginOpen] = useState(false);
  const [login, setLogin] = useState<{ email: string; pw: string; err: string; busy: boolean }>(
    { email: '', pw: '', err: '', busy: false },
  );
  useEffect(() => {
    // review 22 N3: currentSession() kan i princippet afvises (netværksfejl) — sluges ikke
    // tavst, men sætter session til null (allerede default) og logger til konsol.
    genskabSession().finally(() => setSessionKlar(true));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Fælles sessionsgeneration for opstart, »Prøv igen« og auth-events: kun det nyeste opslag må sætte
  // session/fejl. SIGNED_OUT, login og logout tæller op og gør dermed tidligere opslag forældede.
  const sessGenRef = useRef(0);
  const loginIgangRef = useRef(false);
  // Bruger-id fra auth-events, der kom, mens eget login var i gang (undefined = ingen).
  const loginEventBrugerRef = useRef<string | null | undefined>(undefined);
  const genskabSession = (): Promise<void> => {
    const gen = ++sessGenRef.current;
    return currentSession().then(
      (s) => { if (gen === sessGenRef.current) setSession(s); },
      (e) => { if (gen === sessGenRef.current) sessionFejlet(e); },
    );
  };
  // Sessionen findes (JWT'en er aktiv), men rollen kunne ikke slås op. Vis aldrig »anonym« oven på en
  // aktiv, evt. privilegeret session: stands hentninger, ryd modellen og vis en eksplicit fejl (review 37).
  const [sessionFejl, setSessionFejl] = useState(false);
  const sessionRef = useRef<RedSession | null>(null);
  sessionRef.current = session;
  function sessionFejlet(e: unknown) {
    console.warn('[session] kunne ikke genskabes', e);
    loadGenRef.current++;
    setModel(null);
    setSessionFejl(true);
  }
  const proevSessionIgen = () => {
    setSessionFejl(false);
    const gen = sessGenRef.current + 1;
    void genskabSession().then(() => { if (gen === sessGenRef.current) loadData(); });
  };
  const logUdEfterFejl = async () => {
    sessGenRef.current++;
    try { await signOut(); } catch { /* sessionen ryddes lokalt alligevel */ }
    setSessionFejl(false); setSession(null); setModel(null);
    geoRequestedRef.current = false;
    loadData();
  };
  // Sessionsskift uden for denne komponents egen login/logout (logout i en anden fane, udløb,
  // brugerskift): SIGNED_OUT rydder straks; andre skift genskaber sessionen, hvis brugeren er en anden
  // eller profilen er opdateret. INITIAL_SESSION ignoreres (den ovenstående effekt tager den).
  useEffect(() => onAuthChange((event, userId) => {
    if (event === 'INITIAL_SESSION') return;
    // Gør tidligere sessions- og modelsvar forældede, ryd session og model og hent den offentlige model
    // — også når session allerede er null (kold start midt i et rolleopslag). forrigeBrugerRef sættes,
    // så bruger-effekten ikke henter en gang til.
    const nulstil = () => {
      sessGenRef.current++;
      forrigeBrugerRef.current = null;
      geoRequestedRef.current = false;
      setSessionFejl(false); setSession(null); setModel(null);
      loadDataRef.current();
    };
    if (event === 'SIGNED_OUT') { nulstil(); return; }
    // Eget login (doLogin) håndterer selv sin session; dets SIGNED_IN må ikke give et dobbelt opslag. Brugeren
    // noteres dog, så doLogin kan afvise sit svar, hvis en ANDEN bruger loggede ind undervejs (anden fane).
    if (loginIgangRef.current) { loginEventBrugerRef.current = userId; return; }
    if (userId !== (sessionRef.current?.userId ?? null)) {
      // Anden bruger: den gamle redaktørstatus og model må ikke stå, mens den nye brugers rolle slås op.
      nulstil();
      setTimeout(() => { void genskabSession(); }, 0);
    } else if (event === 'USER_UPDATED') {
      setTimeout(() => { void genskabSession(); }, 0);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), []);
  const doLogin = async () => {
    if (login.busy) return; // review 22 N3: forhindr overlappende signIn-kald ved dobbelt-klik
    if (!login.email.trim() || !login.pw) { setLogin((l) => ({ ...l, err: 'Udfyld e-mail og adgangskode' })); return; }
    setLogin((l) => ({ ...l, busy: true, err: '' }));
    // Loginforsøget bindes til en generation FØR await: logout/brugerskift undervejs gør svaret forældet.
    const gen = ++sessGenRef.current;
    loginIgangRef.current = true;
    loginEventBrugerRef.current = undefined;
    // Blev svaret ikke taget i brug (forældet, afvist eller anden bruger), mens et auth-event kom undervejs,
    // genskabes den faktiske Supabase-session i finally — ellers går fx et brugerskift i en anden fane tabt.
    let taget = false;
    try {
      const s = await signIn(login.email, login.pw);
      if (gen !== sessGenRef.current) { setLogin((l) => ({ ...l, busy: false })); return; }
      // Review 37 W5: loggede en anden bruger ind undervejs (auth-event for et andet id), er dette svar
      // forældet; den aktive Supabase-session tilhører den anden bruger og genskabes i finally.
      const eventBruger = loginEventBrugerRef.current;
      if (eventBruger !== undefined && eventBruger !== s.userId) {
        setLogin((l) => ({ ...l, busy: false }));
        setLoginOpen(false);
        setSession(null); setModel(null);
        return;
      }
      taget = true;
      setSession(s);
      setLoginOpen(false);
      setLogin({ email: '', pw: '', err: '', busy: false });
    } catch (e) {
      setLogin((l) => ({ ...l, busy: false, err: gen === sessGenRef.current ? loginFejlTekst(e) : '' }));
    } finally {
      loginIgangRef.current = false;
      if (!taget && loginEventBrugerRef.current !== undefined) void genskabSession();
      loginEventBrugerRef.current = undefined;
    }
  };
  const doLogout = async () => { sessGenRef.current++; await signOut(); setSession(null); };
  const [estates, setEstates] = useState<EstateItem[] | null>(null);
  const [arms, setArms] = useState<ArmsItem[] | null>(null);
  const [about, setAbout] = useState<AboutSection[] | null>(null);
  const [estateId, setEstateId] = useState<string | null>(() => initialPath.estateId);
  // Ejer-relationerne for den åbne besiddelse; fejl er en tilstand, ikke en tom liste (fase 7b).
  const [estateOwners, setEstateOwners] = useState<{ status: 'henter' } | { status: 'fejl' } | { status: 'ok'; rel: EjerRelation[] }>({ status: 'henter' });
  const [ejereForsoeg, setEjereForsoeg] = useState(0);
  const [estatesFejl, setEstatesFejl] = useState(false);
  const [estateInfo, setEstateInfo] = useState<EstateInfo | null>(null);
  const [detail, setDetail] = useState<PersonDetailData | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [detailForsoeg, setDetailForsoeg] = useState(0); // »Prøv igen« i personpanelets fejl

  // review 27 R2: udtrukket til en genkaldelig funktion, så fejlskærmens "Prøv igen"-knap
  // kan forsøge indlæsningen igen uden hard-reload (Supabase free-tier pauser efter 7 dages
  // inaktivitet — første kald efter en pause kan derfor fejle og lykkes ved forsøg nr. 2).
  // Generationstæller (review 37 W5): et sent svar fra en tidligere hentning (fx den anonyme,
  // eller redaktørens) må ikke overskrive den nyeste models data ved login/logout-skift.
  const loadGenRef = useRef(0);
  const loadDataRef = useRef<() => void>(() => {});
  const loadData = useCallback(() => {
    const gen = ++loadGenRef.current;
    setErr(null);
    // Den rå fejl (og udviklerens RLS-hint) går til konsollen; læseren får en forklaring i ord.
    loadModel().then((m) => { if (gen === loadGenRef.current) setModel(m); })
      .catch((e) => { console.warn('[Folgesvend] model-hentning fejlede:', describeErr(e)); if (gen === loadGenRef.current) setErr('fejl'); });
  }, []);
  loadDataRef.current = loadData;
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
  // Åbneren sendes med fra klikket: Safari fokuserer ikke knapper ved museklik, så
  // document.activeElement ville være body, og Esc ville sende fokus derhen.
  const setMenuAaben = useCallback((aaben: boolean, returFokus = false, aabner?: HTMLElement | null) => {
    if (aaben) aabnerRef.current = aabner ?? menuKnap.current;
    setMenuAabenState(aaben);
    // Den gemte åbner kan være forsvundet (fx menuknappen efter skift til bred skærm): så sidehovedets aktuelle knap.
    if (!aaben && returFokus) (aabnerRef.current?.isConnected ? aabnerRef.current : menuKnap.current)?.focus();
  }, []);
  // Senest besøgte slægt (Slægter-menuen). Kun gyldige slugs gemmes.
  const [senestSlaegt, setSenestSlaegt] = useState<string | null>(() => {
    try { return window.localStorage.getItem('daa_senest_slaegt'); } catch { return null; }
  });
  // Stabil array-reference til BookmarksView — /simplify-fund: [...bookmarks.ids] i JSX'et
  // nedenfor gav en NY array hvert render, hvilket ville nulstille en useMemo i BookmarksView.
  const bookmarkIds = useMemo(() => [...bookmarks.ids], [bookmarks.ids]);

  // Besiddelserne hentes eager (én gang) — bruges af listen, slægtens tal og feedet. En fejl giver en tom liste til
  // feedet, men besiddelsessiderne siger fejlen og kan prøve igen. Et ukendt id i adressen siges på siden (fase 7b),
  // ikke ved et tavst skift til listen.
  useEffect(() => {
    if (estates || estatesFejl) return;
    fetchEstates().then(setEstates).catch(() => { setEstates([]); setEstatesFejl(true); });
  }, [estates, estatesFejl]);
  // 'home' og 'about' udløser samme hentning som 'arms' (ikke kun mode==='arms'): forsidernes feed
  // (fase1-design.md §7) viser våben-kort og skal have data uden at brugeren først har
  // besøgt Våben-siden.
  useEffect(() => { if ((mode === 'arms' || mode === 'home' || mode === 'about') && !arms) fetchArms().then(setArms).catch(() => setArms([])); }, [mode, arms]);
  useEffect(() => { if (mode === 'about' && !about) fetchAbout().then(setAbout).catch(() => setAbout([])); }, [mode, about]);
  // Gods-detalje-fetches (review 15 M3): cancelled-guard så en sen resolver for gods A ikke
  // permanent overskriver gods B's data, når man skifter gods hurtigt.
  // Review 36 P1: hentes først, når modellen er landet (ejerrækken bygges alligevel først med modellen), og afhænger
  // kun af canonicalIdById — geo-svaret laver et nyt model-objekt ({ ...m, geo }), men delfelterne er de samme.
  const modelKlar = model !== null;
  const canonicalIdById = model?.canonicalIdById;
  useEffect(() => {
    if (!estateId || !modelKlar) return;
    let cancelled = false;
    setEstateOwners({ status: 'henter' });
    // model læses kun for canonicalIdById (deraf afhængigheden nedenfor).
    fetchEstateOwners(estateId, model).then((rel) => { if (!cancelled) setEstateOwners({ status: 'ok', rel }); }).catch(() => { if (!cancelled) setEstateOwners({ status: 'fejl' }); });
    return () => { cancelled = true; };
  }, [estateId, modelKlar, canonicalIdById, ejereForsoeg]);
  // Antal ejere pr. besiddelse talt mod modellen (samme person i flere udgaver er én ejer; skjulte tælles ikke).
  const estatesVist = useMemo(() => (estates && model
    ? estates.map((e) => (e.ejerIds ? { ...e, ownerCount: antalEjere(e.ejerIds, model) } : e)) : estates), [estates, model]);
  const ejere: EjereTilstand = useMemo(() => (estateOwners.status !== 'ok' ? estateOwners
    : model ? { status: 'ok', raekke: byggEjerraekke(estateOwners.rel, model) } : { status: 'henter' }), [estateOwners, model]);
  useEffect(() => {
    if (!estateId) return;
    let cancelled = false;
    setEstateInfo(null);
    fetchEstateInfo(estateId).then((info) => { if (!cancelled) setEstateInfo(info); }).catch(() => { if (!cancelled) setEstateInfo({ narrativ: '', sted: '', media: [] }); });
    return () => { cancelled = true; };
  }, [estateId]);
  // Detalje (bio/embeder/godser) for fokus-personen — til højre-panelet.
  // Review 36 P1: hentes ÉN gang pr. (fokus, forsøg, rolle), efter modellen er landet — før den mangler
  // medlems-id'erne og bog-nummeret (manglerBogNummer ville fejlagtigt være sand). Effekten afhænger af de delfelter,
  // den læser, ikke af hele modellen: geo-svaret laver et nyt model-objekt ({ ...m, geo }) med de samme delfelter, mens
  // en ny model efter log ind/ud har nye delfelter (RLS kan ændre medlemmerne) og derfor henter igen.
  const fokusPerson = focusId ? model?.byId[focusId] : undefined;
  const fokusKilder = focusId ? model?.sourcesBy?.[focusId] : undefined;
  const modelUdgaver = model?.udgaver;
  const modelUdgaveForPersonRaekke = model?.udgaveForPersonRaekke;
  useEffect(() => {
    if (!focusId) { setDetail(null); setDetailError(null); return; }
    setDetail(null);
    setDetailError(null);
    if (!modelKlar) return;
    let current = true;
    // Foldet person: hent detalje for ALLE medlems-id'er (narrativ/relationer unioneres — spec §8).
    const members = personMemberIds(focusId, fokusPerson);
    // Ingen bog-nummer (typisk en ægtefælle) → hent proveniens fra citationerne i stedet.
    const manglerBogNummer = !(fokusKilder?.length);
    // Redaktøren får også kladder for medlemmer, gæster ikke kan se (decisions 2026-11-13); et rolleskift henter igen.
    fetchPersonDetail(focusId, members, manglerBogNummer, { udgaver: modelUdgaver ?? [], udgaveForPersonRaekke: modelUdgaveForPersonRaekke ?? {} }, erRedaktoer).then(
      (next) => { if (current) setDetail(next); },
      (e) => { if (current) { console.warn('[Folgesvend] persondetalje fejlede:', e); setDetailError(String((e as Error)?.message ?? e)); } },
    );
    return () => { current = false; };
  }, [focusId, modelKlar, fokusPerson, fokusKilder, modelUdgaver, modelUdgaveForPersonRaekke, detailForsoeg, erRedaktoer]);

  const persons = model?.persons ?? [];
  const linjeList = useMemo(() => synligeLinjer(model?.lineage?.list ?? []), [model]);
  // Listens nøgler er kanoniske (én pr. linje på tværs af udgaver); filtret slår op i samme nøglerum.
  const linjeByPerson = useMemo(() => kanoniskeLinjerPrPerson(model?.lineage), [model]);
  // Browse-listen (§9.1) + gren-filter (§9.2) — al logik i buildBrowse (ren + testet).
  // bmOnly (§4/§9.e) filtrerer kilde-personerne til bogmærkede før browse-logikken. bmDep gør at
  // et bogmærke-toggle KUN re-kører browse når filteret faktisk er tændt (ellers stabil null).
  const bmDep = bmOnly ? bookmarkIds : null;
  const browse = useMemo(() => {
    const bmSet = bmDep ? new Set(bmDep) : null;
    const src = bmSet ? persons.filter((p) => bmSet.has(p.id)) : persons;
    return buildBrowse(src, query, browseSort, activeLetter, { linjeByPerson, activeLinje });
  }, [persons, linjeByPerson, query, browseSort, activeLetter, activeLinje, bmDep]);

  // /soeg (fase 6b): adressen er eneste kilde til søgeord og filtre; ændringer skrives i adressen (replace).
  const soegFiltreNu = useMemo(() => soegFiltre(loc.search), [loc.search]);
  const bogmaerkeSaet = useMemo(() => (bookmarks.canSave && bookmarkIds.length ? new Set(bookmarkIds) : null), [bookmarks.canSave, bookmarkIds]);

  // Er vi i familie? Adressen er eneste kilde til de to valgte personer (kanoniske id'er; et ukendt id bevares,
  // så siden kan sige, at personen i linket ikke findes).
  const relA = parsed.mode === 'relate' && parsed.relA ? canon(parsed.relA) : null;
  const relB = parsed.mode === 'relate' && parsed.relB ? canon(parsed.relB) : null;
  const findSlaegtskab = (a: string | null, b: string | null) => {
    setMenuAabenState(false);
    setMode('relate');
    navigate(slaegtskabPath(a ? canon(a) : null, b ? canon(b) : null));
  };

  // Navigér til en person i STAMTRÆET — kanoniserer id'et, tvinger mode til 'tree' (matcher
  // hvordan et sidebar-/detalje-panel-klik altid har betydet "vis denne person i træet",
  // uanset hvilken fane man kom fra) og pusher en NY browser-historik-post. URL'en ER nu
  // selve tilbage-stakken — DetailPanel's "◄ Tilbage" er blot window.history.back().
  // Rydder søge-resultaterne (§4): de tre flag der driver showSearchResults. Linje-/bogstav-
  // filtre er browse-præferencer og bevares (og er alligevel uden effekt når resultaterne skjules).
  const clearSearch = () => { setQuery(''); setBmOnly(false); setBrowsing(false); };
  // To handlinger: »vis i træet« (træets egne klik → …/stamtrae?fokus=<id>, panelet åbner og
  // slægtsbjælken bliver stående) og »vis person« (feed, søgning, bogmærker, familien på personsiden
  // → /person/<id>). href og klik bruger samme funktion, så cmd-klik åbner samme adresse som et klik.
  const traePath = (id: string) => stamtraePath(slug, id);
  const visPersonPath = (id: string) => (mode === 'tree' ? traePath(id) : personPath(id));
  const visPerson = (id: string) => {
    const cid = canon(id);
    setFocusId(cid);
    setMode('person');
    clearSearch();
    navigate(personPath(cid));
  };
  const navigateTree = (id: string) => {
    const cid = canon(id);
    const prev = focusId && focusId !== cid ? focusId : null;
    setPrevFocusId(prev);
    setFocusId(cid);
    setMode('tree');
    clearSearch(); // en "rigtig" navigation lader personen blive centrum i træet; resultat-grid'et viger (§4.1)
    navigate(traePath(cid), { state: { prevFocusId: prev } });
  };
  // Kolonner-variantens ane/efterkommer-drill (TreeView's onFocus): opdaterer URL'en så den
  // forbliver delbar, men UDEN en ny back-entry pr. generations-trin — samme "ingen historik
  // ved drill"-regel som før, nu udtrykt som en URL-replace i stedet for et no-op på et
  // separat back-stack.
  const driftFocus = (id: string) => {
    const cid = canon(id);
    setFocusId(cid);
    navigate(traePath(cid), { replace: true, state: { prevFocusId } });
  };
  // Personsiden starter øverst, også når man går fra person til person (siden forbliver monteret).
  const centerRef = useRef<HTMLDivElement>(null);
  useEffect(() => { if (mode === 'person' && centerRef.current) centerRef.current.scrollTop = 0; }, [mode, focusId]);

  // Menuen lukker ved enhver navigation; besøgte slægter huskes til »Senest besøgt«.
  useEffect(() => { setMenuAabenState(false); }, [loc]);
  useEffect(() => {
    if (!findSlaegt(parsed.slaegt)) return;
    setSenestSlaegt(parsed.slaegt);
    try { window.localStorage.setItem('daa_senest_slaegt', parsed.slaegt!); } catch { /* privat vindue */ }
  }, [parsed.slaegt]);

  // Slægtsbjælkens klik går præcis til linkets href (ingen ?fokus=), så klik og cmd-klik lander
  // samme sted, og Stamtræ ikke åbner panelet på en person, læseren ikke har valgt.
  const goToSide = (m: Mode) => {
    setMenuAabenState(false);
    setMode(m);
    if (m === 'estates') setEstateId(null);
    navigate(pathForMode(m, slug));
  };

  // Fane-skift (sidehoved og detalje-panelets "Sæt i fokus"/"Find slægtskab").
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
    if (p.mode === 'person') {
      // Personsiden: kanonisk id (alias → replace). Findes personen ikke i modellen — forkert id eller en
      // person, læseren ikke må se — er fokus tomt, og siden siger det neutralt. Hentes modellen igen
      // (login), kører effekten igen, og personen kommer frem af sig selv.
      const cid = canon(p.personId!);
      if (model.byId[cid]) {
        setFocusId(cid);
        if (cid !== p.personId) navigate(personPath(cid), { replace: true, state: window.history.state });
      } else setFocusId(null);
      return;
    }
    if (p.mode === 'relate') {
      // Alias-id'er i et delt link → kanoniske (replace). Ukendte id'er bliver stående; siden siger det.
      const a = p.relA ? canon(p.relA) : null, b = p.relB ? canon(p.relB) : null;
      if (a !== p.relA || b !== p.relB) navigate(slaegtskabPath(a, b), { replace: true, state: window.history.state });
      return;
    }
    if (p.mode !== 'tree') return;
    const urlId = p.fokusId;
    if (!urlId) {
      // /stamtrae bærer ikke selv et fokus-id. Split-skærm (§5): når man LUKKER detaljen navigeres
      // hertil, og træet skal blive stående på samme centrum — så bevar et allerede sat focusId og
      // fald kun tilbage til det deterministiske startFokus ved kold start (matcher altid samme
      // person for samme model).
      setFocusId((cur) => cur ?? startFokus(model));
      return;
    }
    const cid = canon(urlId);
    if (model.byId[cid]) {
      setFocusId(cid);
      if (cid !== urlId) navigate(stamtraePath(p.slaegt ?? STANDARD_SLAEGT, cid), { replace: true, state: window.history.state }); // alias → kanonisk
    } else {
      setFocusId(startFokus(model));
      navigate(stamtraePath(p.slaegt ?? STANDARD_SLAEGT), { replace: true }); // ugyldigt/slettet id — forkast til træet uden fokus frem for at foregive et gæt
    }
  }, [parsed, model, canon]);

  // Split-skærm (§5): detalje-panelet er åbent, når stamtræets URL bærer en person. closeDetail navigerer til /stamtrae (replace) — træets centrum
  // bevares (se path-sync ovenfor), kun detaljen viger. Escape lukker også.
  const detailOpen = detailOpenFor(mode, parsed.fokusId);
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
  // 'estates'/'kort' er selvforklarende kort-visninger; 'person' har livsrejsen (fase 5b). Panelet har ikke
  // længere et minikort (5b) og henter derfor ikke geo.
  const geoRequestedRef = useRef(false);
  const [geoLoading, setGeoLoading] = useState(false);
  useEffect(() => {
    const needsGeo = mode === 'estates' || mode === 'kort' || mode === 'person';
    if (!needsGeo || !model || geoRequestedRef.current) return;
    geoRequestedRef.current = true;
    setGeoLoading(true);
    const gen = loadGenRef.current;
    model.loadGeo()
      .then((geo) => { if (gen === loadGenRef.current) setModel((m) => (m ? { ...m, geo } : m)); })
      .catch((e) => console.warn('[Folgesvend] geo-hentning fejlede — intet kort:', e))
      .finally(() => setGeoLoading(false));
  }, [mode, model]);

  // Modellen hentes igen, når brugeren logger ind eller ud: RLS afgør, hvilke personer (levende)
  // den rummer, og ellers ville fx præsensmurens »Log ind« føre en redaktør til en liste uden
  // levende, indtil siden blev genindlæst. Første tjek af den gemte session udløser ikke en ny
  // hentning (den første hentning sker allerede med den gemte session).
  const brugerId = session ? `${session.userId}:${session.role}` : null;
  const forrigeBrugerRef = useRef<string | null | undefined>(undefined);
  useEffect(() => {
    if (!sessionKlar) return;
    if (forrigeBrugerRef.current === undefined) { forrigeBrugerRef.current = brugerId; return; }
    if (forrigeBrugerRef.current === brugerId) return;
    forrigeBrugerRef.current = brugerId;
    geoRequestedRef.current = false; // den nye model har ingen geo; lad geo-effekten hente igen
    // Ryd den gamle model med det samme: den kan rumme redaktørens levende personer (W5).
    setModel(null);
    loadData();
  }, [brugerId, sessionKlar, loadData]);

  // "Det er mig"-markering (localStorage) — samme person igen = fjern markering. Gemmer kanonisk id,
  // og sammenligner kanonisk (et gemt alias-meId matcher stadig den kanoniske person).
  const toggleMe = (id: string) => {
    const cid = canon(id);
    const next = meId && canon(meId) === cid ? null : cid;
    setMeId(next);
    gemMigId(next);
  };

  // Bogmærke-række → personsiden.
  const pickBookmark = (id: string) => visPerson(id);

  // Resultat-valg i stamtræets søgning (§4): centrér træet (navigateTree rydder selv); ellers personsiden.
  // Slægtskab har sine egne personvælgere (fase 6a).
  const pickPerson = (id: string) => {
    const cid = canon(id);
    if (mode === 'tree') {
      navigateTree(cid);
    } else {
      visPerson(cid);
    }
  };

  // Fanens titel (fase 9: delte links og bogmærker). Ved fejl beholdes den gamle model (fx efter logout), så titlen må
  // ikke bygges af den, mens fejlskærmen vises. Står før det tidlige return: hooks i samme rækkefølge.
  const titelSlaegt = findSlaegt(parsed.slaegt)?.navn ?? null;
  const titelPerson = mode === 'person' && focusId ? model?.byId[focusId]?.name ?? null : null;
  const titelA = relA ? model?.byId[relA]?.name ?? null : null;
  const titelB = relB ? model?.byId[relB]?.name ?? null : null;
  const titelBesiddelse = estateId ? estatesVist?.find((e) => e.id === estateId)?.navn ?? null : null;
  useEffect(() => {
    document.title = err ? VAERK : sidetitel({ mode, slaegtNavn: titelSlaegt, personNavn: titelPerson, aNavn: titelA, bNavn: titelB,
      q: soegFiltreNu.q, besiddelseNavn: titelBesiddelse });
  }, [err, mode, titelSlaegt, titelPerson, titelA, titelB, soegFiltreNu.q, titelBesiddelse]);

  if (sessionFejl) {
    return (
      <div style={{ minHeight: '100vh', background: T.surfaceGround, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        <Tilstand fejl etiket="Kunne ikke hente" titel="Din rolle kunne ikke hentes"
          handlinger={<>
            <button type="button" onClick={proevSessionIgen} style={tilstandPrimaer}>Prøv igen</button>
            <button type="button" onClick={() => { void logUdEfterFejl(); }} style={tilstandSekundaer}>Log ud</button>
          </>}>
          Du er stadig logget ind, men vi kunne ikke slå din rolle op. Prøv igen om lidt, eller log ud.
        </Tilstand>
      </div>
    );
  }
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
  // En besiddelse (/besiddelse/<id>) hører til en slægt, selv om adressen ligger over slægterne.
  const hovedpunkt: HovedpunktAktiv = mode === 'soeg' || mode === 'person' ? 'personer'
    : parsed.slaegt || mode === 'estates' ? 'slaegter' : mode === 'relate' ? 'slaegtskab' : null;

  // Søgning-i-træet (§4): bundtet der driver TreeSearch. showResults afgør resultat-grid vs. træ;
  // valg af et resultat rydder søgningen og centrerer træet på personen (brief §4.1).
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
    onPick: pickPerson, // tree → navigateTree (centrerer+rydder)
    personHref: visPersonPath,
  };

  return (
    // data-flade afgrænser læserfladens CSS (base.css) fra redaktionen, som bruger samme stilark. Højden står dér
    // (100vh som reserve, så 100dvh): på iPhone er 100vh højere end det synlige vindue.
    <div data-flade="laeser" style={{ display: 'flex', flexDirection: 'column', background: T.surfaceGround, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      <Sidehoved
        aktiv={hovedpunkt} menuAaben={menuAaben} setMenuAaben={setMenuAaben} menuKnap={menuKnap}
        slaegter={SLAEGTER} senestSlaegt={senestSlaegt} aktivSlaegt={parsed.slaegt}
        onVaelgSlaegt={(s) => goToMode('about', s)}
        onPersoner={() => goToMode('soeg')}
        onSlaegtskab={() => goToMode('relate')} onForside={() => goToMode('home')}
        loggetInd={!!session} onLogin={() => setLoginOpen(true)} onLogout={() => { void doLogout(); }}
        visRedaktion={session?.role === 'redaktion'} sti={loc.path + loc.search}
        ekstra={meCanon && model?.byId[meCanon] ? (
          <Link href={personPath(meCanon)} onNavigate={() => visPerson(meCanon)} title="Din plads i slægten" aria-label="Din plads i slægten" style={{ width: smal ? 44 : 38, height: smal ? 44 : 38, borderRadius: '50%', background: T.bordeauxTint, border: `1.5px solid ${T.bordeaux}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, flex: 'none', textDecoration: 'none' }}>{initials(model.byId[meCanon].name)}</Link>
        ) : null}
      />

      {findSlaegt(parsed.slaegt) && mode !== 'ukendtSlaegt' && (
        <Slaegtsbjaelke slaegt={findSlaegt(parsed.slaegt)!} aktivMode={mode} visPraesens={session?.role === 'redaktion'}
          onGaaTil={goToSide} onSkiftSlaegt={(knap) => setMenuAaben(true, false, knap)} />
      )}

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>

        {/* Center */}
        <div ref={centerRef} data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto' }}>
          {mode === 'home' ? <HomeView model={model} personCount={persons.length} estates={estatesVist} onPickPerson={visPerson} onBrowseAll={() => goToMode('soeg')} onOpenEstate={(id) => { setEstateId(id); navigate(estatePath(id)); }}
              arms={arms} meId={meCanon} focusId={focusId} bookmarkedIds={bookmarkIds}
              bookmarksReady={bookmarks.ready} bookmarkHydrationVersion={bookmarks.hydrationVersion}
              bookmarkOwnerId={session?.userId ?? null}
              hasBookmark={bookmarks.has} onSaveBookmark={saveOrPrompt} onOpenArms={() => goToMode('arms')}
              onOpenSlaegt={(aId, bId) => findSlaegtskab(aId, bId)} />
            : mode === 'person' ? (
              focusId && model?.byId[focusId] ? (
                <PersonSide key={focusId} model={model} focusId={focusId} detail={detail} detailError={detailError}
                  onRetry={() => setDetailForsoeg((n) => n + 1)} onVisPerson={visPerson}
                  onFindSlaegtskab={() => findSlaegtskab(focusId, null)}
                  onSlaegt={(s) => goToMode('about', s)}
                  loggetInd={bookmarks.canSave} onLogin={() => setLoginOpen(true)}
                  erBogmaerket={bookmarks.has(focusId)} onToggleBogmaerke={() => saveOrPrompt(focusId)}
                  geoLoading={geoLoading} erMig={focusId === meCanon} meId={meCanon} onToggleMig={() => toggleMe(focusId)}
                  onVisPraesens={session?.role === 'redaktion' ? () => navigate(pathForMode('praesens', slug), { state: { fokusId: focusId } }) : undefined} />
              ) : !model ? <div style={{ padding: 40, color: T.inkMuted }}>Henter …</div> : (
                <div style={{ padding: 40 }}>
                  <Tilstand etiket="Kan ikke vises" titel="Personen kan ikke vises"
                    handlinger={<Link href={soegPath()} onNavigate={() => goToMode('soeg')} style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Søg efter personen</Link>}>
                    Linket kan være forkert, eller personen vises kun for indloggede.
                  </Tilstand>
                </div>
              )
            )
            : mode === 'tree' ? <TreeView model={model} focusId={focusId} personHref={visPersonPath} onPick={treePick} onFocus={driftFocus} hasBookmark={bookmarks.has} onToggleBookmark={saveOrPrompt} search={treeSearch} />
            : mode === 'relate' ? <RelateView model={model} relA={relA} relB={relB} meId={meCanon} slug={slug} onVaelg={findSlaegtskab} />
            : mode === 'estates' ? <EstatesView estates={estatesVist} estatesFejl={estatesFejl} onRetryEstates={() => { setEstatesFejl(false); setEstates(null); }}
              estateId={estateId} estate={estatesVist?.find((e) => e.id === estateId) ?? null} info={estateInfo} ejere={ejere} onRetryEjere={() => setEjereForsoeg((n) => n + 1)}
              slaegt={findSlaegt(slug) ?? SLAEGTER[0]} geo={model?.geo} geoLoading={geoLoading} onOpen={(id) => { setEstateId(id); navigate(estatePath(id)); }} onPickOwner={visPerson}
              besiddelserHref={pathForMode('estates', slug)} onBesiddelser={() => { setEstateId(null); navigate(pathForMode('estates', slug)); }}
              slaegtensKortHref={pathForMode('kort', slug)} onSlaegtensKort={() => goToMode('kort')} />
            : mode === 'arms' ? <ArmsView arms={arms} />
            : mode === 'about' ? <AboutView slaegt={findSlaegt(slug) ?? SLAEGTER[0]} model={model} about={about} personCount={persons.length} estateCount={estates?.length ?? null} onPick={visPerson}
                feed={{ estates: estatesVist, arms, meId: meCanon, focusId, bookmarkedIds: bookmarkIds,
                  bookmarksReady: bookmarks.ready, bookmarkHydrationVersion: bookmarks.hydrationVersion,
                  bookmarkOwnerId: session?.userId ?? null, hasBookmark: bookmarks.has, onSaveBookmark: saveOrPrompt,
                  onOpenPerson: visPerson, onOpenEstate: (id) => { setEstateId(id); navigate(estatePath(id)); },
                  onOpenArms: () => goToMode('arms'),
                  onOpenSlaegt: (aId, bId) => findSlaegtskab(aId, bId),
                  onBrowseAll: () => goToMode('soeg') }} />
            : mode === 'bookmarks' ? (model ? <BookmarksView model={model} ids={bookmarkIds} sort={bmSort} setSort={setBmSort} onPick={pickBookmark} onRemove={saveOrPrompt} loggedIn={bookmarks.canSave} onRequireLogin={() => setLoginOpen(true)} /> : <div style={{ padding: 40, color: T.inkMuted }}>Henter…</div>)
            : mode === 'kort' ? <OverviewMapView model={model} geoLoading={geoLoading} onPickPerson={visPerson} onPickEstate={(id) => navigate(estatePath(id))} />
            : mode === 'praesens' ? <PresensView model={model} onPickPerson={visPerson} session={sessionKlar ? session : 'henter'} onLogin={() => setLoginOpen(true)} onGoTree={() => goToMode('tree')} />
            : mode === 'soeg' ? (
              <SoegView model={model} estates={estatesVist} filtre={soegFiltreNu} linjer={linjeList} bogmaerker={bogmaerkeSaet}
                onFiltre={(sti) => navigate(sti, { replace: true, state: window.history.state })} />
            )
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
        {/* På smal skærm har stamtræets fokuskort selv »Åbn personsiden«; panelet ville klemme træet (fase 5c). */}
        {detailOpen && !(smal && mode === 'tree') && model && focusId && (detailError ? (
          <aside role="alert" style={{ width: 380, padding: 28, background: T.surfaceRaised, borderLeft: `1px solid ${T.line}`, fontFamily: T.sans }}>
            <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux }}>Kunne ikke hente personens biografi</div>
            <div style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: T.inkSecondary }}>Forbindelsen til arkivet svigtede et øjeblik. Prøv igen om lidt.</div>
            <button type="button" onClick={() => setDetailForsoeg((n) => n + 1)} style={{ ...tilstandSekundaer, marginTop: 14 }}>Prøv igen</button>
          </aside>
        ) : (
          <DetailPanel
            model={model} focusId={focusId} detail={detail}
            backName={backName} onBack={() => window.history.back()} onClose={mode === 'tree' ? closeDetail : undefined}
            onRelate={() => findSlaegtskab(focusId, null)}
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
  return e instanceof Error ? e.message : String(e);
}
