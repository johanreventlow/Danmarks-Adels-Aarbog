// Redaktør-arbejdsbord (web) — port af design/project/Reventlow-redaktion.dc.html.
// Tre paneler: entitets-nav · record-liste · editor. Person-editoren redigerer evidens-laget
// (konklusion ← oplysninger) via de rigtige red_*-RPC'er; generiske entiteter foreslås til
// staging (red_suggest). Dry-run viser hvad der sendes; live skriver. Pixel-tro mod designet,
// men struktur er ren React (ikke prototypens DCLogic).
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { navigate, usePath } from './router';
import { SammenlignUdgaver } from './components/SammenlignUdgaver';
import { FeedStyring } from './components/FeedStyring';
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
import {
  buildTidslinje, fetchHaendelserForPerson, fetchStoriesForPerson, storyPrefillFraPost, fetchRedaktionPersoner, fetchPersonEvidence, fetchNarrativer, fetchSources, fetchLineages, fetchSletPreview,
  fetchEntityRecords, fetchPersonFamilie, fetchPersonRelationer, fetchSammeSomLinks, fetchRedPersonMedia, fetchRedObjectMedia, nudgeOrdinal, fetchForaeldreUkendtMarkering, type RedPerson, type PersonEvidence,
  type FeltEvidens, type Oplysning, type SletPreview, type EntityRecord, type PersonFamilie, type PersonRelation, type SammeSomLink,
  type HaendelsePost, type StoryPost, type TidslinjePost, type PersonNarrativ, type SourceRow, type LineageRow, type PersonMedia, type ForaeldreUkendtMarkering, SLAEGT_SUBJEKT_ID,
  fetchForaeldreSlot, fetchForaeldreKonflikter, fetchBarnFamilie, type ForaeldreSlot, type ForaeldreKonflikt, type BarnFamilie,
  fetchMediaBibliotek, fetchMediaAnvendelse, type MediaBibliotekPost, type MediaAnvendelse, type MedieKoe,
} from './data/redaktionRead';
import { GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE, insertAt, makeToken, previewSammeSom } from '@daa/core';
import { loadModel } from './data/model';
import type { Model } from './data/types';
import { submitChange, describeCall, oversaetFejl, resumeMediaUpload, type Change } from './data/redaktionWrite';
import { createStorySaveGuard, saveStoryWithSources, storySaveClosesEditor } from './data/storySave';
import { buildVariants, type BuiltVariants } from './data/mediaUpload';
import { supabase } from './supabase';
import { withUrl } from './data/media';
import { buildBrowse } from './data/browse';
import { initials } from './data/format';
import { NarrativRenderer } from './components/NarrativRenderer';
import { Lightbox } from './components/Lightbox';
import { MediaDetaljeOverlay } from './components/MediaDetaljeOverlay';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const MEDIA_RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;
type StoryDraft = {
  storyId: number | null; titel: string; tekst: string; privat: boolean;
  haendelseId: number | null; dateMin: string; dateMax: string;
  dateQualifier: string; dateRaw: string;
  kilder: { sourceId: number; side: string }[];
};
type MediaDedupHit = {
  id: string; titel: string | null; upload_status: string; storage_path: string | null;
};
type MediaDedupState = {
  existing: MediaDedupHit; built: BuiltVariants; uploadTarget: Record<string, unknown>;
  originalFilnavn: string;
};
// Change-arter der kan ændre et materiale-galleri (Slice 0h) — bruges til at afgøre om
// person-editorens/objekt-editorens medieliste skal genhentes efter et gemt kald.
const MEDIA_ARTER = new Set(['uploadMedia', 'opdaterMedia', 'genopretMedia', 'mediaRettigheder', 'fjernMedia', 'sletRelation', 'tilknytMedia']);
// Generiske entiteter med et materiale-galleri (Slice 0h) — spejler mobiles HAR_MATERIALE.
const HAR_OBJEKT_MATERIALE = new Set(['estate', 'arms']);
// --- Tokens (fra designet) ---
const T = {
  pageBg: '#ece6da', paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', dark: '#2a211c', bordeaux: '#881A33', gold: '#b9a06a', goldLight: '#e7c98f',
  muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c', green: '#1f5b3a', red: '#8a2b2b',
  paperText: '#f4efe6', cream: '#cabfa9',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};

const ENTITIES = [
  { key: 'person', label: 'Personer', icon: '☗' },
  { key: 'family', label: 'Familier & relationer', icon: '⚭' },
  { key: 'slaegt', label: 'Slægten', icon: '⚘' },
  { key: 'narrative', label: 'Narrativer', icon: '¶' },
  { key: 'office', label: 'Embeder & hverv', icon: '❦' },
  { key: 'estate', label: 'Godser', icon: '⌂' },
  { key: 'majorat', label: 'Majorater', icon: '⚜' },
  { key: 'org', label: 'Organisationer', icon: '◈' },
  { key: 'source', label: 'Kilder', icon: '§' },
  { key: 'arms', label: 'Våben', icon: '⛨' },
  { key: 'media', label: 'Medier', icon: '▦' },
  { key: 'feed', label: 'Feed-styring', icon: '⚑' },
  { key: 'sammenlign', label: 'Sammenlign udgaver', icon: '⇄' },
  { key: 'foraeldre-konflikter', label: 'Forældre-konflikter', icon: '⚠' },
];
const FELT_DEFS: [string, string][] = [
  ['navn', 'Navn'], ['foedt', 'Født'], ['doed', 'Død'], ['titel', 'Titel/rang'],
  ['daab', 'Dåb'], ['begravelse', 'Begravelse'], ['floruit', 'Floruit'], ['naturalisering', 'Naturalisation'],
];
// UI-entitetsnøgle → DB subjekt_type + primær-felt (til forslag via red_suggest). Eksplicit
// map, så UI-nøgler ('org','arms') ikke lækker rå til basen, der bruger fulde navne.
const ENTITY_DB: Record<string, { type: string; felt: string }> = {
  estate: { type: 'estate', felt: 'navn' },
  source: { type: 'source', felt: 'titel' },
  org: { type: 'organisation', felt: 'navn' },
  arms: { type: 'coat_of_arms', felt: 'blasonering' },
  narrative: { type: 'narrative', felt: 'tekst' },
  family: { type: 'family', felt: 'type' },
  office: { type: 'relation', felt: 'rolle' },
  majorat: { type: 'majorat', felt: 'navn' },
  media: { type: 'media', felt: 'titel' },
};
const konklusionAf = (f: FeltEvidens): Oplysning | undefined => f.oplysninger.find((o) => o.erKonklusion) ?? f.oplysninger[0];
const kildeAf = (o: Oplysning): string => {
  const k = o.kilder[0];
  if (!k) return 'ingen kilde';
  return [k.sourceTitel, k.side].filter(Boolean).join(', ') || 'ingen kilde';
};

// URL-grammatik (matcher web/vercel.json's SPA-fallback + allerede etableret navngivning i
// mobile/src/app/redaktion/): /redaktion → entity 'person', intet recordId · /redaktion/:entity
// → entity, intet recordId · /redaktion/:entity/:id → entity + recordId.
function parseRedaktionPath(path: string): { entity: string; recordId: string | null } {
  const seg = path.split('/').filter(Boolean); // ['redaktion', entity?, id?]
  return { entity: seg[1] || 'person', recordId: seg[2] || null };
}
function redaktionPath(entity: string, recordId: string | null): string {
  return recordId ? `/redaktion/${entity}/${recordId}` : `/redaktion/${entity}`;
}

// Indsæt fonte + base-styles én gang (svarer til designets <helmet>).
function useDesignHead() {
  useEffect(() => {
    if (document.getElementById('daa-red-fonts')) return;
    const link = document.createElement('link');
    link.id = 'daa-red-fonts'; link.rel = 'stylesheet';
    link.href = 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500;1,600&family=Hanken+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap';
    document.head.appendChild(link);
    const st = document.createElement('style');
    st.textContent = '*{box-sizing:border-box}body{margin:0}input,textarea,select{font-family:inherit}';
    document.head.appendChild(st);
  }, []);
}

export default function Redaktion() {
  useDesignHead();
  const path = usePath();
  const [session, setSession] = useState<RedSession | null>(null);
  const [dryRun, setDryRun] = useState(true);
  const [showAnno, setShowAnno] = useState(true);
  // Initialiseres synkront fra URL'en (deep link, fx /redaktion/person/123) — overlever login-
  // flowet uændret, jf. recordId-auto-default nedenfor der KUN fylder et tomt felt (cur ?? …).
  const initialPath = parseRedaktionPath(window.location.pathname);
  const [entity, setEntity] = useState(() => initialPath.entity);
  const [recordId, setRecordId] = useState<string | null>(() => initialPath.recordId);
  const [query, setQuery] = useState('');
  // Person-browse (spejler Følgesvend §9.1/§9.2): sortér (navn/fødeår), alfabet-hop, linje-filter.
  const [browseSort, setBrowseSort] = useState<'navn' | 'aar'>('navn');
  const [activeLetter, setActiveLetter] = useState<string | null>(null);
  const [activeLinje, setActiveLinje] = useState<string | null>(null);

  const [persons, setPersons] = useState<RedPerson[]>([]);
  const [recCache, setRecCache] = useState<Record<string, EntityRecord[]>>({});
  const [evidence, setEvidence] = useState<PersonEvidence | null>(null);
  const [haendelser, setHaendelser] = useState<HaendelsePost[]>([]);
  const [stories, setStories] = useState<StoryPost[]>([]);
  const [storyEditor, setStoryEditor] = useState<StoryDraft | null>(null);
  const [storySaving, setStorySaving] = useState(false);
  const storySaveGuardRef = useRef(createStorySaveGuard());
  const [haendelseNotice, setHaendelseNotice] = useState('');
  // Narrativ pr. udgave: liste (faner) + aktiv kilde + redigerbart udkast for den aktive fane.
  const [narrativer, setNarrativer] = useState<PersonNarrativ[]>([]);
  const [aktivSourceId, setAktivSourceId] = useState<number | null>(null);
  const [narrativUdkast, setNarrativUdkast] = useState<{ tekst: string; privat: boolean; side: string }>({ tekst: '', privat: false, side: '' });
  // Cursor-position i narrativ-textarea'en (billeder-i-narrativer 2026-07-05, Slice C2) — ref, ikke
  // state: påvirker aldrig render-output, kun læst ved billed-indsættelse (samme mønster som
  // mobile's narrativSelPos).
  const narrativTextareaRef = useRef<HTMLTextAreaElement>(null);
  const narrativSelPos = useRef(0);
  const [mediaPickerOpen, setMediaPickerOpen] = useState(false);
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [lineages, setLineages] = useState<LineageRow[]>([]);
  const [nyUdgave, setNyUdgave] = useState<{ titel: string; udgave: string; aar: string } | null>(null);
  const [model, setModel] = useState<Model | null>(null);
  const [familie, setFamilie] = useState<PersonFamilie | null>(null);
  const [relationer, setRelationer] = useState<PersonRelation[] | null>(null);
  const [sammeSom, setSammeSom] = useState<SammeSomLink[]>([]);
  // Materiale (mediehåndtering Slice 0g). fetchRedPersonMedia signerer allerede internt (ét sted,
  // som media.ts's loadMediaItems) — media[].url er klar til brug, ingen separat uri-state/effekt.
  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [mediaBibliotek, setMediaBibliotek] = useState<MediaBibliotekPost[]>([]);
  const [mediaKoe, setMediaKoe] = useState<MedieKoe | 'alle'>('alle');
  const [mediaAnvendelse, setMediaAnvendelse] = useState<MediaAnvendelse | undefined>();
  const [mediaAnvendelseFejl, setMediaAnvendelseFejl] = useState('');
  const [mediaLightbox, setMediaLightbox] = useState<number | null>(null); // Slice A
  const [mediaDetalje, setMediaDetalje] = useState<{ id: string; subjektType: string; subjektId: string } | null>(null);
  const mediaDetaljeRef = useRef(mediaDetalje);
  const [mediaTilknytPicker, setMediaTilknytPicker] = useState<{ mediaId: string; maalType: 'person' | 'estate' | 'coat_of_arms' | 'lineage' } | null>(null);
  const [mediaTilknytQuery, setMediaTilknytQuery] = useState('');
  const [mediaPick, setMediaPick] = useState<{ file: File; previewUrl: string } | null>(null);
  const [mediaDedup, setMediaDedup] = useState<MediaDedupState | null>(null);
  const [mediaForm, setMediaForm] = useState<{ slags: string; titel: string; kunstner: string; datering: string; rettighederStatus: string; maaPubliceres: boolean }>(
    { slags: 'foto', titel: '', kunstner: '', datering: '', rettighederStatus: 'ukendt', maaPubliceres: false });
  const [mediaBusy, setMediaBusy] = useState(false); // Slice B2: klient-genkodning tager et øjeblik
  // Retningsbekræftelse for et nyt samme_som-link: den valgte person + hvem der er kanonisk.
  const [ssConfirm, setSsConfirm] = useState<{ personId: string; navn: string; kanoniskId: string } | null>(null);
  const [picker, setPicker] = useState<{ kind: 'barn' | 'partner' | 'hverv' | 'gods' | 'sammeSom'; familyId?: string } | null>(null);
  const [pickQuery, setPickQuery] = useState('');
  // Flyt et barn til et af PERSONENS EGNE andre forhold (brugerfund 2026-07-02: forkert
  // mor/far-par). Ikke en fri søgning som `picker` ovenfor — bevidst begrænset til de forhold
  // der allerede vises på denne side, så et barn ikke kan flyttes til en urelateret persons familie.
  const [flytBarn, setFlytBarn] = useState<{ fraFamilyId: string; personId: string; rolle: string; navn: string } | null>(null);
  const [loadErr, setLoadErr] = useState<string | null>(null);

  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [editingAssert, setEditingAssert] = useState<number | null>(null);
  const [addingFact, setAddingFact] = useState<number | null>(null);
  const [scratch, setScratch] = useState<Record<string, string>>({});

  const [login, setLogin] = useState<{ open: boolean; email: string; pw: string; err: string; busy: boolean }>(
    { open: false, email: '', pw: '', err: '', busy: false });
  const [confirmDel, setConfirmDel] = useState<{ id: string; label: string; preview: SletPreview | null; ack: boolean } | null>(null);
  const [writeView, setWriteView] = useState<{ title: string; lines: string[]; error: string; done: boolean; dryRun: boolean; direkte: boolean } | null>(null);

  const role = session?.role;
  const sc = (k: string, fb = '') => (scratch[k] !== undefined ? scratch[k] : fb);
  const setSc = (k: string, v: string) => setScratch((s) => ({ ...s, [k]: v }));
  const refreshMediaBibliotek = useCallback(() => {
    fetchMediaBibliotek().then(setMediaBibliotek).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
  }, []);

  // --- Initial load ---
  // Fejl her er reelle (currentSession() returnerer null, ikke throw, ved "ikke logget ind") —
  // en tavs catch lod UI'et hænge uden forklaring; logges + vises via samme loadErr-banner som
  // fetchRedaktionPersoner nedenfor (review 27 R1).
  useEffect(() => {
    currentSession().then(setSession).catch((e) => {
      console.warn('[redaktion] session-load fejlede:', e);
      setLoadErr(oversaetFejl(String(e?.message ?? e)));
    });
  }, []);
  // Redaktion collapser IKKE: navne slås op på de rå DB-poster (spec §8 — model holdes separat).
  useEffect(() => {
    loadModel({ collapse: false }).then(setModel).catch((e) => {
      console.warn('[redaktion] model-load fejlede:', e);
      setLoadErr(oversaetFejl(String(e?.message ?? e)));
    });
  }, []);
  useEffect(() => {
    fetchRedaktionPersoner().then((ps) => {
      setPersons(ps);
      setRecordId((cur) => cur ?? ps[0]?.id ?? null);
    }).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
  }, []);
  // Kilde-liste (udgave-picker) er person-uafhængig → hentes én gang. opretUdgave refresher selv.
  useEffect(() => { fetchSources().then(setSources).catch(() => setSources([])); }, []);
  // Linje-listen bruges KUN af 'slaegt'-entiteten — dovent hentet ved første besøg der (ikke ved
  // hver person-visning), refetches ikke når man forlader/genbesøger fanen (lineages.length>0).
  useEffect(() => {
    if (entity !== 'slaegt' || lineages.length > 0) return;
    fetchLineages().then(setLineages).catch(() => setLineages([]));
  }, [entity, lineages.length]);

  // Skift entitets-fane (sidebar-nav) — rydder valgt record + søgefelt, matcher original adfærd.
  const goToEntity = (e: string) => {
    setEntity(e); setRecordId(null); setQuery('');
    navigate(redaktionPath(e, null));
  };
  // Åbn en bestemt record (record-liste-klik + "Åbn person"-links i familie/relations-visningen).
  const openRecord = (e: string, id: string) => {
    setEntity(e); setRecordId(id);
    navigate(redaktionPath(e, id));
  };
  // Synkroniserer entity/recordId med den AKTUELLE URL (usePath() reagerer BÅDE på egne
  // navigate()-kald OG på browserens back/forward — /simplify-fund: erstatter en hånd-rullet
  // window.addEventListener('popstate', …) med den delte hook router.ts allerede eksponerer).
  useEffect(() => {
    const p = parseRedaktionPath(path);
    setEntity(p.entity);
    setRecordId(p.recordId);
  }, [path]);
  useEffect(() => { setMediaDedup(null); }, [entity, recordId]);
  // Navigation kan ikke annullere et allerede sendt RPC-kald, men invaliderer dets UI-resultat,
  // så en sen completion aldrig lukker eller overskriver editoren for en anden person.
  useEffect(() => { storySaveGuardRef.current.invalidate(); }, [entity, recordId]);

  // Records for aktuel entitet (person = live person-liste; øvrige = lazy fetch + cache).
  const records: EntityRecord[] = useMemo(() => {
    if (entity === 'person') {
      return persons.map((p) => ({ id: p.id, label: p.navn, sub: p.aar || '—', badge: initials(p.navn) }));
    }
    return recCache[entity] ?? [];
  }, [entity, persons, recCache]);

  // Lazy entitets-liste pr. type, kun ÉN gang (ref-dedup → effekten genkører ikke når cachen fyldes).
  const fetchedRef = useRef<Set<string>>(new Set());
  const mediaInputRef = useRef<HTMLInputElement>(null);
  // Ryd den midlertidige preview-blob-URL når valget skiftes/annulleres/gemmes (undgår at ophobe
  // objectURL'er en session igennem).
  useEffect(() => {
    if (!mediaPick) return;
    return () => URL.revokeObjectURL(mediaPick.previewUrl);
  }, [mediaPick]);
  useEffect(() => {
    if (entity === 'media') { refreshMediaBibliotek(); return; }
    if (entity === 'person' || fetchedRef.current.has(entity)) return;
    fetchedRef.current.add(entity);
    fetchEntityRecords(entity).then((rs) => setRecCache((c) => ({ ...c, [entity]: rs }))).catch(() => fetchedRef.current.delete(entity));
  }, [entity, refreshMediaBibliotek]);

  useEffect(() => {
    mediaDetaljeRef.current = mediaDetalje;
    if (!mediaDetalje) { setMediaAnvendelse(undefined); setMediaAnvendelseFejl(''); return; }
    let aktiv = true;
    setMediaAnvendelse(undefined);
    setMediaAnvendelseFejl('');
    fetchMediaAnvendelse(mediaDetalje.id)
      .then((a) => { if (aktiv) setMediaAnvendelse(a); })
      .catch(() => { if (aktiv) setMediaAnvendelseFejl('Kunne ikke kontrollere anvendelser. Sletning er derfor blokeret.'); });
    return () => { aktiv = false; };
  }, [mediaDetalje?.id]);
  useEffect(() => {
    if (entity !== 'media') return;
    if (!recordId) { setMediaDetalje(null); return; }
    if (!mediaBibliotek.some((m) => m.id === recordId)) return;
    setMediaDetalje({ id: recordId, subjektType: 'media', subjektId: recordId });
  }, [entity, recordId, mediaBibliotek]);

  // Evidens + narrativ når en person vælges.
  // skipMedia: run()'s post-write reload kalder loadPerson efter ETHVERT gemt ændring (allerede
  // eksisterende, bredt over-fetchende mønster for evidens/narrativer/familie/relationer/sammeSom
  // — urørt her). Medielisten er IKKE føjet ind i den samme ubetingede liste: den er to sekventielle
  // DB-kald (relation→media), så den fetches kun ved persons-valg eller efter en uploadMedia-ændring,
  // ikke ved fx en narrativ- eller privat-toggle-gem (cost-uden-gevinst, /simplify-fund).
  // Generaliseret fra person-only (billeder-i-narrativer 2026-07-05, Slice C3) — genbruges nu også
  // af slægts/linje-narrativ-editoren, samme udgave-fane-tilstand (narrativer/aktivSourceId/
  // narrativUdkast/nyUdgave), blot et andet (subjekt_type, subjekt_id).
  const loadNarrativer = useCallback((subjektType: string, subjektId: number) => {
    setNarrativer([]); setAktivSourceId(null); setNyUdgave(null);
    setNarrativUdkast({ tekst: '', privat: false, side: '' });
    fetchNarrativer(subjektType, subjektId).then((ns) => {
      setNarrativer(ns);
      const first = ns[0];
      setAktivSourceId(first?.sourceId ?? 1);
      setNarrativUdkast({ tekst: first?.tekst ?? '', privat: first?.privat ?? false, side: first?.side ?? '' });
    }).catch(() => { setNarrativer([]); setAktivSourceId(1); setNarrativUdkast({ tekst: '', privat: false, side: '' }); });
  }, []);

  const loadPerson = useCallback((id: string, opts?: { skipMedia?: boolean }) => {
    storySaveGuardRef.current.invalidate();
    setEvidence(null); setHaendelser([]); setStories([]); setStoryEditor(null); setHaendelseNotice(''); setFamilie(null); setRelationer(null); setEditingAssert(null); setAddingFact(null);
    fetchPersonEvidence(id).then(setEvidence).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
    fetchHaendelserForPerson(id).then(setHaendelser).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
    fetchStoriesForPerson(id).then(setStories).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
    loadNarrativer('person', Number(id));
    fetchPersonFamilie(id, model).then(setFamilie).catch(() => setFamilie({ somPartner: [], somBarn: [] }));
    fetchPersonRelationer(id).then(setRelationer).catch(() => setRelationer([]));
    fetchSammeSomLinks(id).then(setSammeSom).catch(() => setSammeSom([]));
    if (!opts?.skipMedia) {
      setMedia([]); setMediaPick(null); setMediaForm({ slags: 'foto', titel: '', kunstner: '', datering: '', rettighederStatus: 'ukendt', maaPubliceres: false }); setMediaDetalje(null);
      fetchRedPersonMedia(id).then(setMedia).catch(() => setMedia([]));
    }
  }, [model, loadNarrativer]);

  // Skift aktiv udgave-fane; nulstil udkast fra den fanes gemte narrativ (ugemte edits kasseres,
  // som ved record-skift). sourceId==null når en ny udgave er valgt men endnu ikke gemt.
  const vaelgUdgave = useCallback((sourceId: number | null) => {
    setAktivSourceId(sourceId); setNyUdgave(null);
    const n = narrativer.find((x) => x.sourceId === sourceId) ?? null;
    setNarrativUdkast({ tekst: n?.tekst ?? '', privat: n?.privat ?? false, side: n?.side ?? '' });
  }, [narrativer]);

  // Indsæt et token ved cursor-position i narrativ-textarea'en (billeder-i-narrativer 2026-07-05,
  // Slice C2). setSelectionRange kræver at elementet har fokus igen — refocus FØR det, ellers
  // flytter browseren blot cursor uden effekt.
  const insertNarrativToken = useCallback((token: string) => {
    const r = insertAt(narrativUdkast.tekst, narrativSelPos.current, token);
    setNarrativUdkast((u) => ({ ...u, tekst: r.text }));
    narrativSelPos.current = r.cursor;
    requestAnimationFrame(() => {
      const el = narrativTextareaRef.current;
      if (el) { el.focus(); el.setSelectionRange(r.cursor, r.cursor); }
    });
  }, [narrativUdkast.tekst]);

  // Opret en ny DAA-udgave (source) via det delte submitChange-flow — så dry-run/staging/rolle-
  // routing honoreres som for al anden skrivning. På LIVE bruges det nye source-id straks (skift
  // aktiv fane, tomt udkast); på dry-run vises kun previewet (intet oprettet).
  const opretUdgave = useCallback(async () => {
    if (!nyUdgave || !nyUdgave.titel.trim()) return;
    const change: Change = { art: 'opretKilde', subjektType: 'source', subjektId: '', payload: {
      titel: nyUdgave.titel.trim(), slags: 'DAA-udgave',
      udgave: nyUdgave.udgave.trim() || null, aar: nyUdgave.aar.trim() ? Number(nyUdgave.aar) : null } };
    try {
      const res = await submitChange(change, { dryRun, role });
      setWriteView({ title: dryRun ? 'Dry-run · dette ville blive sendt' : (res.direkte ? 'Sendt til basen' : 'Forslag sendt til staging'),
        lines: [describeCall(res.call)], error: '', done: !dryRun, dryRun, direkte: res.direkte });
      if (!res.dryRun && res.direkte && res.result != null) {
        setSources(await fetchSources());
        setNyUdgave(null); setAktivSourceId(Number(res.result));
        setNarrativUdkast({ tekst: '', privat: false, side: '' });
      }
    } catch (e) { setWriteView({ title: 'Ny udgave fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false }); }
  }, [nyUdgave, dryRun, role]);
  useEffect(() => {
    if (entity === 'person' && recordId) loadPerson(recordId);
  }, [entity, recordId, loadPerson]);

  // Sørg for at picker-entiteten (org/estate) er hentet når picker åbner.
  useEffect(() => {
    const ent = picker?.kind === 'hverv' ? 'org' : picker?.kind === 'gods' ? 'estate' : null;
    if (ent && !recCache[ent]) fetchEntityRecords(ent).then((rs) => setRecCache((c) => ({ ...c, [ent]: rs }))).catch(() => {});
  }, [picker, recCache]);
  useEffect(() => {
    if (!mediaTilknytPicker) return;
    const ent = mediaTilknytPicker.maalType === 'estate' ? 'estate'
      : mediaTilknytPicker.maalType === 'coat_of_arms' ? 'arms' : null;
    if (ent && !recCache[ent]) fetchEntityRecords(ent).then((rs) => setRecCache((c) => ({ ...c, [ent]: rs }))).catch(() => {});
    if (mediaTilknytPicker.maalType === 'lineage' && lineages.length === 0) fetchLineages().then(setLineages).catch(() => setLineages([]));
  }, [mediaTilknytPicker, recCache, lineages.length]);

  const curPerson = persons.find((p) => p.id === recordId) ?? null;
  const curRecord = records.find((r) => r.id === recordId) ?? null;

  // Slægts/linje-narrativ-editor (billeder-i-narrativer 2026-07-05, Slice C3): recordId 'generelt'
  // → den faste sentinel (SLAEGT_SUBJEKT_ID, ikke en fremmednøgle); ethvert andet recordId → et
  // lineage.id (fra fetchLineages, valgt i renderList's slaegt-gren).
  const slaegtSubjekt = useMemo(() => {
    if (entity !== 'slaegt' || !recordId) return null;
    if (recordId === 'generelt') return { type: 'slaegt' as const, id: SLAEGT_SUBJEKT_ID, label: 'Generelt' };
    const l = lineages.find((x) => String(x.id) === recordId);
    return l ? { type: 'lineage' as const, id: l.id, label: l.navn ?? `Linje ${l.kode}` } : null;
  }, [entity, recordId, lineages]);
  useEffect(() => {
    if (!slaegtSubjekt) return;
    loadNarrativer(slaegtSubjekt.type, slaegtSubjekt.id);
    setMedia([]); setMediaPick(null); setMediaForm({ slags: 'foto', titel: '', kunstner: '', datering: '', rettighederStatus: 'ukendt', maaPubliceres: false }); setMediaDetalje(null);
    if (slaegtSubjekt.type === 'lineage') {
      fetchRedObjectMedia('lineage', String(slaegtSubjekt.id)).then(setMedia).catch(() => setMedia([]));
    }
  }, [slaegtSubjekt, loadNarrativer]);

  // Objekt-foto (Slice 0h): estate/arms er de eneste generiske entiteter med et materiale-galleri
  // (jf. renderGenericEditor). Genbruger person-editorens media/mediaPick/mediaForm-state — de to
  // render-stier er gensidigt udelukkende via `entity`, så der er ingen race på delt state.
  const refreshObjMedia = useCallback(() => {
    if (!HAR_OBJEKT_MATERIALE.has(entity) || !curRecord) return;
    const db = ENTITY_DB[entity];
    fetchRedObjectMedia(db.type, curRecord.id).then(setMedia).catch(() => setMedia([]));
  }, [entity, curRecord]);
  useEffect(() => {
    if (!HAR_OBJEKT_MATERIALE.has(entity)) return;
    setMedia([]); setMediaPick(null); setMediaForm({ slags: 'foto', titel: '', kunstner: '', datering: '', rettighederStatus: 'ukendt', maaPubliceres: false }); setMediaDetalje(null);
    refreshObjMedia();
    // refreshObjMedia afhænger kun af entity+curRecord.id reelt (curRecord-objektet skifter
    // reference oftere end det); undgår gen-fetch-loop på uændret post.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entity, curRecord?.id]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? records.filter((r) => (r.label + ' ' + r.sub).toLowerCase().includes(q)) : records;
  }, [records, query]);

  // Person-browse spejler Følgesvend: driv af den redaktør-authoritative `persons` (RedPerson har
  // allerede id/navn/born) + linje-metadata fra `model.lineage`. id-rummene flugter fordi redaktør-
  // modellen loades `collapse:false` (model-person-id == rå RedPerson-id); et `name`-alias lader
  // RedPerson opfylde buildBrowse's minimale BrowsePerson-shape. Kun beregnet for person-entiteten
  // (null ellers) — så et søge-tastetryk under fx Kilder ikke browser hele slægten unødigt.
  const linjeList = model?.lineage?.list ?? [];
  const linjeByPerson = model?.lineage?.byPerson;
  const personBrowse = useMemo(
    () => entity !== 'person' ? null
      : buildBrowse(persons.map((p) => ({ ...p, name: p.navn })), query, browseSort, activeLetter, { linjeByPerson, activeLinje }),
    [entity, persons, query, browseSort, activeLetter, linjeByPerson, activeLinje],
  );

  // Udgaver personen endnu ikke har en narrativ i — kandidater til "+ Ny udgave"-picker.
  const ledigeSources = useMemo(
    () => sources.filter((s) => !narrativer.some((n) => n.sourceId === s.id)),
    [sources, narrativer],
  );
  const tidslinje = useMemo(
    () => buildTidslinje(haendelser, evidence ?? { felter: {}, koen: null }),
    [haendelser, evidence],
  );

  const hopTilHaendelse = useCallback((post: (typeof tidslinje)[number]) => {
    if (post.narrativeId == null) return;
    const n = narrativer.find((x) => x.id === post.narrativeId);
    if (!n) { setHaendelseNotice('Kildenarrativet er ikke længere tilgængeligt.'); return; }
    const tekst = n.sourceId === aktivSourceId ? narrativUdkast.tekst : n.tekst;
    let start = post.spanStart ?? -1;
    const length = post.spanLaengde ?? post.klausul.length;
    if (start < 0 || tekst.slice(start, start + length) !== post.klausul) start = tekst.indexOf(post.klausul);
    if (start < 0) {
      setHaendelseNotice('Klausul ikke længere i narrativet — gen-kør hændelses-passet.');
      return;
    }
    setHaendelseNotice(''); setAktivSourceId(n.sourceId); setNyUdgave(null);
    setNarrativUdkast({ tekst, privat: n.privat, side: n.side ?? '' });
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const el = narrativTextareaRef.current;
      if (!el) return;
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      el.focus(); el.setSelectionRange(start, start + post.klausul.length);
    }));
  }, [tidslinje, narrativer, aktivSourceId, narrativUdkast.tekst]);

  // --- Skrivning ---
  const run = useCallback(async (change: Change, titel: string, options?: { refresh?: boolean }) => {
    try {
      const res = await submitChange(change, { dryRun, role });
      setWriteView({
        title: dryRun ? 'Dry-run · dette ville blive sendt' : (res.direkte ? 'Sendt til basen' : 'Forslag sendt til staging'),
        lines: [describeCall(res.call)], error: '', done: !dryRun, dryRun, direkte: res.direkte,
      });
      // sletRelation dækker også ikke-media unlinks (hverv/gods) — en ekstra, harmløs medie-refetch
      // for dem er billigere end at holde to separate art-lister i sync (/simplify-fund).
      const mediaChanged = MEDIA_ARTER.has(change.art);
      if (!dryRun && options?.refresh !== false && entity === 'person' && recordId) loadPerson(recordId, { skipMedia: !mediaChanged });
      if (!dryRun && HAR_OBJEKT_MATERIALE.has(entity) && mediaChanged) refreshObjMedia();
      // Linje-materiale (Slice C3) — "Generelt" (recordId 'generelt') har ingen billed-samling.
      if (!dryRun && entity === 'slaegt' && recordId && recordId !== 'generelt' && mediaChanged) {
        fetchRedObjectMedia('lineage', recordId).then(setMedia).catch(() => setMedia([]));
      }
      if (!dryRun && mediaChanged && entity === 'media') refreshMediaBibliotek();
      if (!dryRun && mediaChanged && mediaDetalje) {
        const detaljeId = mediaDetalje.id;
        if (mediaDetaljeRef.current?.id === detaljeId) {
          setMediaAnvendelse(undefined); setMediaAnvendelseFejl('');
          fetchMediaAnvendelse(detaljeId).then((a) => {
            if (mediaDetaljeRef.current?.id === detaljeId) setMediaAnvendelse(a);
          }).catch(() => {
            if (mediaDetaljeRef.current?.id === detaljeId) setMediaAnvendelseFejl('Kunne ikke kontrollere anvendelser. Sletning er derfor blokeret.');
          });
        }
      }
      return res;
    } catch (e) {
      setWriteView({ title: titel + ' fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false });
      return undefined;
    }
  }, [dryRun, role, entity, recordId, loadPerson, refreshObjMedia, refreshMediaBibliotek, mediaDetalje]);

  const nyStoryFraPost = useCallback((post: TidslinjePost) => {
    if (storySaveGuardRef.current.busy) return;
    storySaveGuardRef.current.invalidate();
    const p = storyPrefillFraPost(post);
    setStoryEditor({
      storyId: null, titel: '', tekst: p.tekst, privat: false,
      haendelseId: p.haendelseId, dateMin: p.dateMin ?? '', dateMax: p.dateMax ?? '',
      dateQualifier: p.dateQualifier ?? '', dateRaw: p.dateRaw ?? '',
      kilder: p.kilder.map((k) => ({ sourceId: k.sourceId, side: k.side ?? '' })),
    });
  }, []);

  const redigerStory = useCallback((story: StoryPost) => {
    if (storySaveGuardRef.current.busy) return;
    storySaveGuardRef.current.invalidate();
    setStoryEditor({
      storyId: story.id, titel: story.titel ?? '', tekst: story.tekst, privat: story.privat,
      haendelseId: story.haendelseId, dateMin: story.dato.min ?? '', dateMax: story.dato.max ?? '',
      dateQualifier: story.dato.qualifier ?? '', dateRaw: story.dato.raw ?? '',
      kilder: story.kilder.map((k) => ({ sourceId: k.sourceId, side: k.side ?? '' })),
    });
  }, []);

  const gemStory = useCallback(async (personId: string) => {
    if (!storyEditor?.tekst.trim()) return;
    const saveToken = storySaveGuardRef.current.start();
    if (saveToken == null) return;
    setStorySaving(true);
    const payload = {
      titel: storyEditor.titel.trim() || null, tekst: storyEditor.tekst.trim(),
      haendelseId: storyEditor.haendelseId, dateMin: storyEditor.dateMin || null,
      dateMax: storyEditor.dateMax || null, dateQualifier: storyEditor.dateQualifier || null,
      dateRaw: storyEditor.dateRaw || null, privat: storyEditor.privat,
    };
    const kilder = storyEditor.kilder.map((k) => ({
      sourceId: k.sourceId, ...(k.side.trim() ? { side: k.side.trim() } : {}),
    }));
    const change: Change = storyEditor.storyId == null
      ? { art: 'opretStory', subjektType: 'person', subjektId: personId, payload, kilder }
      : { art: 'redigerStory', subjektType: 'person', subjektId: personId,
          storyId: storyEditor.storyId, payload, kilder };
    try {
      const outcome = await saveStoryWithSources(change, kilder, run);
      if (!storySaveGuardRef.current.isCurrent(saveToken)) return;
      if (outcome.status === 'sources-failed') {
        setStoryEditor((draft) => draft ? { ...draft, storyId: outcome.storyId } : draft);
        return;
      }
      if (outcome.status === 'invalid-story-id') {
        setWriteView({ title: 'Opret historie fejlede', lines: [],
          error: 'Basen returnerede ikke et gyldigt historie-id.', done: false, dryRun, direkte: false });
        return;
      }
      if (storySaveClosesEditor(outcome)) {
        if (outcome.status === 'saved') loadPerson(personId);
        setStoryEditor(null);
      }
    } finally {
      storySaveGuardRef.current.finish(saveToken);
      setStorySaving(false);
    }
  }, [storyEditor, run, dryRun, loadPerson]);

  const doLogin = async () => {
    if (!login.email.trim() || !login.pw) { setLogin((l) => ({ ...l, err: 'Udfyld e-mail og adgangskode' })); return; }
    setLogin((l) => ({ ...l, busy: true, err: '' }));
    try { const s = await signIn(login.email, login.pw); setSession(s); setLogin({ open: false, email: '', pw: '', err: '', busy: false }); }
    catch (e) { setLogin((l) => ({ ...l, busy: false, err: oversaetFejl(String((e as Error)?.message ?? e)) })); }
  };
  const doLogout = () => { signOut().catch(() => {}); setSession(null); };

  const requestDelete = (id: string, label: string) => {
    setConfirmDel({ id, label, preview: null, ack: false });
    if (entity === 'person') fetchSletPreview(id).then((pv) => setConfirmDel((c) => c && c.id === id ? { ...c, preview: pv } : c)).catch(() => {});
  };
  const performDelete = () => {
    if (!confirmDel || !confirmDel.ack) return;
    const id = confirmDel.id;
    run({ art: 'sletPerson', subjektType: 'person', subjektId: id }, 'Sletning');
    setConfirmDel(null);
  };

  // ============ RENDER ============
  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.pageBg, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      {renderTopBar()}
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {renderSidebar()}
        {entity === 'feed' || entity === 'sammenlign' || entity === 'foraeldre-konflikter' ? (
          <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto', background: T.paper }}>
            {entity === 'feed'
              ? <FeedStyring role={role} model={model} run={run} />
              : entity === 'sammenlign'
              ? <SammenlignUdgaver role={role} />
              : <ForaeldreKonflikterListe onOpen={(id) => openRecord('person', id)} />}
          </div>
        ) : (
          <>
            {renderList()}
            <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto', background: T.paper }}>
              {loadErr && <pre style={{ margin: 18, color: T.red, fontSize: 12, whiteSpace: 'pre-wrap' }}>{loadErr}</pre>}
              {entity === 'person' ? renderPersonEditor() : entity === 'slaegt' ? renderSlaegtEditor() : entity === 'media' ? renderMediaBibliotekEditor() : renderGenericEditor()}
            </div>
          </>
        )}
      </div>
      {renderLoginModal()}
      {renderConfirmModal()}
      {renderWriteModal()}
      {renderPicker()}
      {renderSammeSomConfirm()}
      {renderFlytBarnPicker()}
      {renderMediaPicker()}
      {renderMediaTilknytPicker()}
      {renderMediaDetalje()}
      {renderMediaDedupDialog()}
    </div>
  );

  // ---- Top bar ----
  function renderTopBar() {
    return (
      <div style={{ flex: 'none', height: 66, display: 'flex', alignItems: 'center', gap: 22, padding: '0 26px', background: T.paper, borderBottom: '1px solid rgba(34,31,26,.1)', zIndex: 30 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 13, flex: 'none' }}>
          <img src="/daf-logo.png" alt="Dansk Adels Forening" style={{ width: 40, height: 40, objectFit: 'contain' }} />
          <div>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600, lineHeight: 1, color: T.ink }}>Danmarks Adels Aarbog</div>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.16em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Redaktion · Dansk Adels Forening</div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '6px 12px', flex: 'none' }}>
          <span style={{ width: 26, height: 26, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', boxShadow: 'inset 0 0 0 2px #f4efe6, inset 0 0 0 2.5px rgba(136,26,51,.28)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>R</span>
          <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.ink }}>Reventlow</span>
          <span style={{ fontFamily: T.sans, fontSize: 11, color: T.muted2 }}>▾</span>
        </div>
        <div style={{ flex: 1 }} />
        <div onClick={() => setShowAnno((v) => !v)} style={{ display: 'flex', alignItems: 'center', gap: 7, cursor: 'pointer', border: '1px solid rgba(34,31,26,.18)', borderRadius: 8, padding: '5px 11px' }}>
          <span style={{ width: 9, height: 9, borderRadius: '50%', background: showAnno ? '#1f8a5b' : T.muted }} />
          <span style={{ fontSize: 11.5, color: T.muted }}>Forklaringer</span>
        </div>
        <div onClick={() => setDryRun((v) => !v)} style={{ display: 'flex', alignItems: 'center', gap: 7, cursor: 'pointer', background: dryRun ? T.beige : '#7a2230', border: `1px solid ${dryRun ? 'rgba(34,31,26,.2)' : '#a83246'}`, borderRadius: 8, padding: '6px 11px' }}>
          <span style={{ width: 9, height: 9, borderRadius: '50%', background: dryRun ? T.goldLight : '#ff6b6b' }} />
          <span style={{ fontSize: 11.5, fontWeight: 600, color: dryRun ? T.ink : '#fff' }}>{dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}</span>
        </div>
        {session ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: '#f8ecef', border: `1px solid ${T.bordeaux}`, borderRadius: 9, padding: '5px 10px' }}>
            <span style={{ width: 26, height: 26, borderRadius: '50%', background: T.bordeaux, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 11, fontWeight: 600, color: T.paperText }}>{(session.email || '?').slice(0, 2).toUpperCase()}</span>
            <div>
              <div style={{ fontSize: 11.5, fontWeight: 600, color: T.ink, lineHeight: 1, maxWidth: 150, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{session.email}</div>
              <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted2, marginTop: 1 }}>{session.role === 'redaktion' ? 'redaktion · skriver direkte' : `${session.role} · forslag til staging`}</div>
            </div>
            <span onClick={doLogout} style={{ fontSize: 10.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginLeft: 4 }}>Log ud</span>
          </div>
        ) : (
          <div onClick={() => setLogin((l) => ({ ...l, open: true, err: '' }))} style={{ display: 'flex', alignItems: 'center', gap: 7, background: T.goldLight, borderRadius: 8, padding: '7px 14px', cursor: 'pointer' }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: T.dark }}>Log ind</span>
          </div>
        )}
      </div>
    );
  }

  // ---- Sidebar ----
  function renderSidebar() {
    return (
      <div data-scroll style={{ flex: 'none', width: 226, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', padding: '14px 12px' }}>
        <div style={{ padding: '0 8px 8px', fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3 }}>Entiteter</div>
        {ENTITIES.map((e) => {
          const active = e.key === entity;
          return (
            <div key={e.key} onClick={() => goToEntity(e.key)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 10px', borderRadius: 9, cursor: 'pointer', background: active ? T.paper : 'transparent', marginBottom: 2 }}>
              <span style={{ width: 24, height: 24, borderRadius: 6, background: active ? T.bordeaux : T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: active ? T.paperText : '#8a8170' }}>{e.icon}</span>
              <span style={{ flex: 1, fontSize: 13, fontWeight: 600, color: active ? T.ink : '#3d382f' }}>{e.label}</span>
              <span style={{ fontFamily: T.mono, fontSize: 9.5, color: active ? T.bordeaux : T.muted3 }}>{e.key === 'person' ? persons.length || '' : (recCache[e.key]?.length ?? '')}</span>
            </div>
          );
        })}
      </div>
    );
  }

  // ---- Record-liste ----
  function renderList() {
    const title = ENTITIES.find((e) => e.key === entity)?.label ?? '';
    const b = personBrowse; // non-null ⇔ entity === 'person' (fungerer som person-diskriminator)
    const mediaQuery = query.trim().toLowerCase();
    const mediaFiltered = mediaBibliotek.filter((m) => {
      if (mediaKoe !== 'alle' && !m.koeer.includes(mediaKoe)) return false;
      return !mediaQuery || [m.titel, m.kunstner, m.originalFilnavn].filter(Boolean).join(' ').toLowerCase().includes(mediaQuery);
    });
    const mediaKoer: { key: MedieKoe | 'alle'; label: string }[] = [
      { key: 'alle', label: 'Alle' }, { key: 'rettigheder', label: 'Rettigheder' },
      { key: 'loese', label: 'Løse' }, { key: 'strandede', label: 'Strandede' },
      { key: 'papirkurv', label: 'Papirkurv' },
    ];
    // Fælles liste-række (person + generiske entiteter): round = avatar-form, tail = valgfrit suffiks.
    const listRow = (o: { id: string; badge: string; label: string; sub: string; round: number | string; tail?: ReactNode }) => (
      <div key={o.id} onClick={() => openRecord(entity, o.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 9px', borderRadius: 9, cursor: 'pointer', background: o.id === recordId ? '#efe7d7' : 'transparent' }}>
        <span style={{ width: 30, height: 30, borderRadius: o.round, background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{o.badge}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: T.serif, fontSize: 15.5, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.label}</div>
          <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.sub}</div>
        </div>
        {o.tail}
      </div>
    );
    const pRow = (p: { id: string; navn: string; aar: string; privat: boolean }) => listRow({
      id: p.id, badge: initials(p.navn), label: p.navn, sub: p.aar || '—', round: '50%',
      tail: p.privat ? <span style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.06em', textTransform: 'uppercase', color: T.red, flex: 'none' }}>privat</span> : undefined,
    });
    return (
      <div data-scroll style={{ flex: 'none', width: 286, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '16px 16px 10px', position: 'sticky', top: 0, background: T.panel, zIndex: 2 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 9 }}>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{title}</div>
          </div>
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Søg…" style={{ width: '100%', fontSize: 13, color: T.ink, background: T.paper, border: '1px solid rgba(34,31,26,.14)', borderRadius: 8, padding: '9px 11px', outline: 'none' }} />
        </div>

        {entity === 'media' ? (
          <>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, padding: '0 14px 10px' }}>
              {mediaKoer.map((k) => {
                const aktiv = mediaKoe === k.key;
                const antal = k.key === 'alle' ? mediaBibliotek.length : mediaBibliotek.filter((m) => m.koeer.includes(k.key as MedieKoe)).length;
                return <button type="button" key={k.key} onClick={() => setMediaKoe(k.key)}
                  style={{ border: 0, borderRadius: 6, padding: '5px 8px', cursor: 'pointer', background: aktiv ? T.bordeaux : T.beige, color: aktiv ? T.paperText : T.muted, fontFamily: T.mono, fontSize: 8.5 }}>
                  {k.label} ({antal})
                </button>;
              })}
            </div>
            <div style={{ padding: '2px 10px 12px' }}>
              {mediaFiltered.map((m) => {
                const erBillede = m.mimeType?.startsWith('image/') === true && !!m.thumbUrl;
                const antalBrug = m.antalAfbildet + m.antalMentions;
                return (
                  <div key={m.id} onClick={() => { openRecord('media', m.id); setMediaDetalje({ id: m.id, subjektType: 'media', subjektId: m.id }); }}
                    style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px', borderRadius: 9, cursor: 'pointer', background: m.id === recordId ? '#efe7d7' : 'transparent', opacity: m.uploadStatus === 'fjernet' ? .55 : 1 }}>
                    {erBillede ? <img src={m.thumbUrl!} alt={m.titel ?? m.slags} style={{ width: 42, height: 42, borderRadius: 7, objectFit: 'cover', background: T.beige, flex: 'none' }} />
                      : <span style={{ width: 42, height: 42, borderRadius: 7, background: T.beige, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: T.muted, flex: 'none', fontSize: 16 }}>▤<small style={{ fontSize: 7 }}>{m.slags}</small></span>}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontFamily: T.serif, fontSize: 14.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{m.titel || '(uden titel)'}</div>
                      <div style={{ fontFamily: T.mono, fontSize: 8, color: T.muted2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {m.slags}{m.uploadStatus !== 'klar' ? ` · ${m.uploadStatus}` : ''}{m.maaPubliceres ? '' : ' · ej publiceret'}
                      </div>
                      <div style={{ fontSize: 9.5, color: T.muted, marginTop: 2 }}>bruges {antalBrug} {antalBrug === 1 ? 'sted' : 'steder'}</div>
                    </div>
                  </div>
                );
              })}
              {!mediaFiltered.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{mediaBibliotek.length ? 'Ingen træffere' : 'Henter medier…'}</div>}
            </div>
          </>
        ) : b ? (
          <>
            {/* Linje-filter (§9.2) — filtrerer kun listen; redaktør har intet stamtræ at hoppe fokus i. */}
            {linjeList.length > 0 && (
              <div style={{ padding: '0 14px 8px' }}>
                <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted2, marginBottom: 7 }}>Linjer</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {[{ linje: null as string | null, navn: null as string | null }, ...linjeList].map((l) => {
                    const on = activeLinje === l.linje;
                    return (
                      <div key={l.linje ?? 'all'} onClick={() => setActiveLinje(l.linje)} title={l.navn ?? undefined} style={{ padding: '5px 11px', borderRadius: 15, fontFamily: T.sans, fontSize: 11.5, fontWeight: 600, cursor: 'pointer', background: on ? T.bordeaux : 'transparent', color: on ? T.paper : T.muted, border: `1px solid ${on ? T.bordeaux : 'rgba(34,31,26,.18)'}` }}>{l.linje ? `Linje ${l.linje}` : 'Hele slægten'}</div>
                    );
                  })}
                </div>
              </div>
            )}

            <div style={{ padding: '0 14px 8px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
              <span style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted3 }}>{`${activeLinje ? `Linje ${activeLinje} · ` : ''}${b.flat.length} ${query ? 'træffere' : 'personer'}`}</span>
              <div style={{ display: 'flex', background: '#e6ddcc', borderRadius: 7, padding: 2, gap: 2, flex: 'none' }}>
                {(['navn', 'aar'] as const).map((s) => (
                  <span key={s} onClick={() => setBrowseSort(s)} style={{ fontFamily: T.sans, fontSize: 10, fontWeight: 600, padding: '3px 8px', borderRadius: 5, cursor: 'pointer', background: browseSort === s ? T.bordeaux : 'transparent', color: browseSort === s ? T.paper : '#3d382f' }}>{s === 'navn' ? 'A–Å' : 'Født'}</span>
                ))}
              </div>
            </div>

            {b.grouped && b.letters.length > 1 && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 3, padding: '0 14px 9px' }}>
                {[{ key: null as string | null, label: 'Alle' }, ...b.letters.map((l) => ({ key: l as string | null, label: l }))].map((L) => {
                  const on = activeLetter === L.key;
                  return (
                    <span key={L.label} onClick={() => setActiveLetter(L.key)} style={{ fontFamily: T.mono, fontSize: 10, fontWeight: 500, minWidth: 19, height: 19, padding: '0 3px', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 5, cursor: 'pointer', background: on ? T.bordeaux : T.beige, color: on ? T.paper : T.muted }}>{L.label}</span>
                  );
                })}
              </div>
            )}

            <div style={{ padding: '2px 10px 12px' }}>
              {b.grouped
                ? b.groups.map((g) => (
                    <div key={g.letter}>
                      <div style={{ padding: '7px 9px 3px', fontFamily: T.serif, fontSize: 15, fontWeight: 600, color: T.gold, borderBottom: '1px solid rgba(34,31,26,.07)' }}>{g.letter}</div>
                      {g.people.map(pRow)}
                    </div>
                  ))
                : b.flat.map(pRow)}
              {!b.flat.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{persons.length ? 'Ingen træffere' : 'Henter…'}</div>}
            </div>
          </>
        ) : entity === 'slaegt' ? (
          // Slægts/linje-narrativ-editor (Slice C3): "Generelt" (fast sentinel) + én række pr.
          // navngiven linje — IKKE via fetchEntityRecords/records (ingen bagvedliggende tabel for
          // "Generelt"), egen lille liste af de 5 lineage-rækker + sentinellen.
          <div style={{ padding: '2px 10px 12px' }}>
            {[{ id: 'generelt', badge: '⚘', label: 'Generelt', sub: 'hele slægten' },
              ...lineages.map((l) => ({ id: String(l.id), badge: l.kode, label: l.navn ?? `Linje ${l.kode}`, sub: 'linje' }))]
              .filter((r) => !query.trim() || r.label.toLowerCase().includes(query.trim().toLowerCase()))
              .map((r) => listRow({ id: r.id, badge: r.badge, label: r.label, sub: r.sub, round: 7 }))}
          </div>
        ) : (
          <div style={{ padding: '2px 10px 12px' }}>
            {filtered.map((r) => listRow({ id: r.id, badge: r.badge, label: r.label, sub: r.sub, round: 7 }))}
            {!filtered.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{query ? 'Ingen træffere' : 'Ingen liste-kilde endnu'}</div>}
          </div>
        )}
      </div>
    );
  }

  function renderMediaBibliotekEditor() {
    const valgt = mediaBibliotek.find((m) => m.id === recordId);
    return (
      <div style={{ padding: '28px 30px', maxWidth: 760 }}>
        <div style={{ fontFamily: T.serif, fontSize: 29, fontWeight: 600 }}>Mediebibliotek</div>
        <div style={{ marginTop: 8, color: T.muted, fontSize: 13, lineHeight: 1.5 }}>
          {valgt ? <>Valgt: <b>{valgt.titel || '(uden titel)'}</b>. Klik på rækken igen for at åbne filsiden.</>
            : 'Vælg et medie i listen for at åbne filsiden, redigere metadata og se hvor det bruges.'}
        </div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginTop: 18 }}>
          {([['rettigheder', 'Rettigheder'], ['loese', 'Løse'], ['strandede', 'Strandede'], ['papirkurv', 'Papirkurv']] as const).map(([key, label]) => (
            <div key={key} style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '12px 15px', minWidth: 120 }}>
              <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>{mediaBibliotek.filter((m) => m.koeer.includes(key)).length}</div>
              <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2 }}>{label}</div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  // ---- Person-editor ----
  function renderPersonEditor() {
    if (!curPerson) return <div style={{ padding: 30, color: T.muted3 }}>Vælg en person.</div>;
    const p = curPerson;
    return (
      <div style={{ padding: '24px 30px 60px', maxWidth: 780 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
          <div style={{ width: 64, height: 64, borderRadius: '50%', background: '#f8ecef', border: `1.5px solid ${T.bordeaux}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 24, fontWeight: 600, color: T.bordeaux }}>{initials(p.navn)}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1 }}>{p.navn}</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 7 }}>
              <span style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2 }}>{p.aar || '—'}</span>
              <span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted, background: T.beige, borderRadius: 5, padding: '3px 7px' }}>id {p.id}</span>
              <span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted, background: T.beige, borderRadius: 5, padding: '3px 7px' }}>{evidence?.koen ?? 'køn ?'}</span>
              {p.efternavnAfledt && <span title="Efternavnet er afledt af linje-medlemskab, ikke en del af bogens rå navn" style={{ fontFamily: T.mono, fontSize: 9, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', borderRadius: 5, padding: '3px 7px' }}>efternavn afledt af linje</span>}
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7, alignItems: 'flex-end' }}>
            <div onClick={() => run({ art: 'setPrivat', subjektType: 'person', subjektId: p.id, payload: { privat: !p.privat } }, 'Privat')} style={{ display: 'flex', alignItems: 'center', gap: 8, background: p.privat ? '#f8ecef' : T.panel, border: `1.5px solid ${p.privat ? T.bordeaux : 'rgba(34,31,26,.16)'}`, borderRadius: 8, padding: '6px 11px', cursor: 'pointer' }}>
              <span style={{ width: 26, height: 15, borderRadius: 8, background: p.privat ? T.bordeaux : '#cfc6b5', position: 'relative' }}><span style={{ position: 'absolute', top: 1.5, left: p.privat ? 12.5 : 1.5, width: 11, height: 11, borderRadius: '50%', background: '#fff' }} /></span>
              <span style={{ fontSize: 12, fontWeight: 600, color: p.privat ? T.bordeaux : T.muted }}>Privat</span>
            </div>
            <div onClick={() => requestDelete(p.id, p.navn)} style={{ display: 'flex', alignItems: 'center', gap: 7, background: T.paper, border: '1.5px solid rgba(138,43,43,.3)', borderRadius: 8, padding: '6px 11px', cursor: 'pointer' }}>
              <span style={{ fontSize: 12, color: T.red }}>🗑</span><span style={{ fontSize: 12, fontWeight: 600, color: T.red }}>Slet person</span>
            </div>
          </div>
        </div>

        <ForaeldreUkendtControl personId={p.id} run={run} />
        <ForaeldrePaastandeControl personId={p.id} run={run} sammeSom={sammeSom} />

        {showAnno && (
          <div style={{ marginTop: 16, ...annoBox }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux, marginBottom: 4 }}>Sådan virker evidens-laget</div>
            <div style={{ fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>Hvert <b>faktum</b> vises som en <b>konklusion</b> (den blåstemplede værdi) ovenpå en eller flere <b>oplysninger</b>, hver med sin <b>kildeangivelse</b>. Redaktøren tilføjer oplysninger og vælger konklusionen; intet overskrives destruktivt.</div>
          </div>
        )}

        <div style={sectionHeader(22)}>Kerne-fakta · konklusion ← oplysninger</div>
        {!evidence && <div style={{ color: T.muted3, fontSize: 12.5 }}>Henter evidens…</div>}
        {evidence && FELT_DEFS.flatMap(([felt, label]) => (evidence.felter[felt] ?? [{ felt, faktatype: felt, factId: -1, konklusionAssertionId: null, oplysninger: [], uenig: false } as FeltEvidens]).map((f) => renderFactCard(p.id, label, f)))}

        <div style={sectionHeader(22)}>Hændelser · tidslinje fra prosaen</div>
        {haendelseNotice && <div style={{ ...annoBox, color: T.bordeaux, fontSize: 11.5, marginBottom: 8 }}>{haendelseNotice}</div>}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
          {tidslinje.map((post) => {
            const dato = post.dato.raw ?? (post.dato.min && post.dato.max && post.dato.min !== post.dato.max
              ? `${post.dato.min} – ${post.dato.max}` : post.dato.min ?? post.dato.max ?? 'udateret');
            const statusser = ['kandidat','interessant','skjult'] as const;
            return <div key={post.id} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '10px 12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 5 }}>
                <span style={{ fontFamily: T.mono, fontSize: 9, color: T.bordeaux }}>{dato}</span>
                <span style={{ fontFamily: T.mono, fontSize: 8, color: T.muted, background: T.beige, borderRadius: 5, padding: '2px 5px' }}>{post.art === 'rygrad' ? 'RYGRAD' : (post.kategori ?? 'ANDET').toUpperCase()}</span>
                <span style={{ flex: 1 }} />
                <button type="button" disabled={storySaving} onClick={() => nyStoryFraPost(post)}
                  style={{ border: '1px solid rgba(136,26,51,.28)', background: T.paper, color: T.bordeaux, borderRadius: 6, padding: '3px 7px', fontFamily: T.mono, fontSize: 8, cursor: storySaving ? 'default' : 'pointer' }}>
                  + Historie
                </button>
                {post.art === 'haendelse' && post.haendelseId != null && <span style={{ display: 'flex', gap: 3 }}>
                  {statusser.map((status) => <span key={status}
                    onClick={() => run({ art: 'haendelseStatus', subjektType: 'person', subjektId: p.id, haendelseId: post.haendelseId, status }, 'Feed-status')}
                    style={{ fontFamily: T.mono, fontSize: 8, fontWeight: 600, padding: '3px 6px', borderRadius: 5, cursor: 'pointer', background: post.feedStatus === status ? T.bordeaux : T.beige, color: post.feedStatus === status ? T.paperText : T.muted }}>
                    {status}
                  </span>)}
                </span>}
              </div>
              <div onClick={() => hopTilHaendelse(post)} style={{ fontFamily: T.serif, fontSize: 16, fontStyle: 'italic', lineHeight: 1.35, cursor: post.narrativeId != null ? 'pointer' : 'default' }}>“{post.klausul}”</div>
              <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted2, marginTop: 4 }}>{[post.sourceTitel, post.side ? `s. ${post.side}` : null].filter(Boolean).join(', ') || 'kilde mangler'}</div>
            </div>;
          })}
          {!tidslinje.length && <div style={{ color: T.muted3, fontSize: 12 }}>Ingen daterede poster endnu.</div>}
        </div>

        <div style={sectionHeader(18)}>Minihistorier · alle statusser</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
          {stories.map((story) => (
            <div key={story.id} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '10px 12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ fontFamily: T.serif, fontWeight: 600, fontSize: 16 }}>{story.titel || 'Historie uden titel'}</span>
                <span style={{ flex: 1 }} />
                {(['kladde', 'klar', 'publiceret', 'arkiveret'] as const).map((status) => (
                  <button key={status} type="button"
                    onClick={() => run({ art: 'setStoryStatus', subjektType: 'person', subjektId: p.id,
                      storyId: story.id, storyStatus: status }, 'Story-status')}
                    style={{ border: 0, borderRadius: 5, padding: '3px 6px', cursor: 'pointer', fontFamily: T.mono,
                      fontSize: 8, fontWeight: 600, background: story.status === status ? T.bordeaux : T.beige,
                      color: story.status === status ? T.paperText : T.muted }}>
                    {status}
                  </button>
                ))}
                <button type="button" disabled={storySaving} onClick={() => redigerStory(story)}
                  style={{ border: '1px solid rgba(34,31,26,.15)', background: T.panel, color: T.ink,
                    borderRadius: 6, padding: '3px 7px', fontFamily: T.mono, fontSize: 8, cursor: storySaving ? 'default' : 'pointer' }}>
                  Redigér
                </button>
              </div>
              <div style={{ marginTop: 5, fontSize: 12.5, lineHeight: 1.45, color: T.muted }}>{story.tekst}</div>
              <div style={{ marginTop: 5, fontFamily: T.mono, fontSize: 8.5, color: T.muted2 }}>
                {story.dato.raw || story.dato.min || 'udateret'} · {story.kilder.map((k) => [k.sourceTitel, k.side ? `s. ${k.side}` : null].filter(Boolean).join(', ')).filter(Boolean).join(' · ') || 'kilde mangler'}
              </div>
            </div>
          ))}
          {!stories.length && <div style={{ color: T.muted3, fontSize: 12 }}>Ingen historier endnu.</div>}
        </div>

        {storyEditor && (
          <div aria-busy={storySaving} style={{ marginTop: 10, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: 10 }}>
              <span style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600 }}>{storyEditor.storyId == null ? 'Ny minihistorie' : `Redigér historie #${storyEditor.storyId}`}</span>
              <span style={{ flex: 1 }} />
              <button type="button" disabled={storySaving} onClick={() => {
                if (storySaveGuardRef.current.busy) return;
                storySaveGuardRef.current.invalidate();
                setStoryEditor(null);
              }} style={{ border: 0, background: 'transparent', color: T.muted, cursor: storySaving ? 'default' : 'pointer' }}>Luk</button>
            </div>
            <fieldset disabled={storySaving} style={{ border: 0, padding: 0, margin: 0, minWidth: 0 }}>
            <input value={storyEditor.titel} placeholder="Titel (valgfri)"
              onChange={(e) => setStoryEditor((s) => s && ({ ...s, titel: e.target.value }))}
              style={{ width: '100%', border: '1px solid rgba(34,31,26,.16)', borderRadius: 7, padding: '8px 9px', background: T.paper, color: T.ink }} />
            <textarea value={storyEditor.tekst} rows={5} placeholder="Omskriv til en minihistorie på cirka 40–90 ord"
              onChange={(e) => setStoryEditor((s) => s && ({ ...s, tekst: e.target.value }))}
              style={{ width: '100%', marginTop: 8, resize: 'vertical', border: '1px solid rgba(34,31,26,.16)', borderRadius: 7, padding: '8px 9px', background: T.paper, color: T.ink, lineHeight: 1.5 }} />
            <div style={{ marginTop: 3, fontFamily: T.mono, fontSize: 8.5, color: T.muted2 }}>
              {storyEditor.tekst.trim() ? storyEditor.tekst.trim().split(/\s+/).length : 0} ord · vejledende norm 40–90
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', gap: 7, marginTop: 9 }}>
              {([['dateMin', 'Dato min'], ['dateMax', 'Dato max'], ['dateQualifier', 'Kvalifikator'], ['dateRaw', 'Dato som skrevet']] as const).map(([key, label]) => (
                <input key={key} value={storyEditor[key]} placeholder={label}
                  onChange={(e) => setStoryEditor((s) => s && ({ ...s, [key]: e.target.value }))}
                  style={{ minWidth: 0, border: '1px solid rgba(34,31,26,.16)', borderRadius: 7, padding: '7px 8px', background: T.paper, color: T.ink }} />
              ))}
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, fontSize: 11.5, color: T.muted }}>
              <input type="checkbox" checked={storyEditor.privat}
                onChange={(e) => setStoryEditor((s) => s && ({ ...s, privat: e.target.checked }))} /> Privat
            </label>
            <div style={{ marginTop: 10, fontFamily: T.mono, fontSize: 9, color: T.gold }}>KILDER</div>
            {storyEditor.kilder.map((k, i) => (
              <div key={`${k.sourceId}-${i}`} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr auto', gap: 7, marginTop: 6 }}>
                <select value={k.sourceId} onChange={(e) => setStoryEditor((s) => s && ({ ...s,
                  kilder: s.kilder.map((x, j) => j === i ? { ...x, sourceId: Number(e.target.value) } : x) }))}
                  style={{ border: '1px solid rgba(34,31,26,.16)', borderRadius: 7, padding: '7px 8px', background: T.paper, color: T.ink }}>
                  {sources.map((source) => <option key={source.id} value={source.id}>{source.titel ?? source.udgave ?? `Kilde #${source.id}`}</option>)}
                </select>
                <input value={k.side} placeholder="Side" onChange={(e) => setStoryEditor((s) => s && ({ ...s,
                  kilder: s.kilder.map((x, j) => j === i ? { ...x, side: e.target.value } : x) }))}
                  style={{ border: '1px solid rgba(34,31,26,.16)', borderRadius: 7, padding: '7px 8px', background: T.paper, color: T.ink }} />
                <button type="button" onClick={() => setStoryEditor((s) => s && ({ ...s, kilder: s.kilder.filter((_, j) => j !== i) }))}
                  style={{ border: 0, background: T.beige, color: T.bordeaux, borderRadius: 6, cursor: 'pointer' }}>Fjern</button>
              </div>
            ))}
            <div style={{ display: 'flex', gap: 8, marginTop: 9 }}>
              <button type="button" disabled={!sources.length}
                onClick={() => setStoryEditor((s) => s && ({ ...s, kilder: [...s.kilder, { sourceId: sources[0].id, side: '' }] }))}
                style={{ border: '1px solid rgba(34,31,26,.15)', background: T.paper, color: T.ink, borderRadius: 7, padding: '7px 10px', cursor: sources.length ? 'pointer' : 'default' }}>+ Kilde</button>
              <button type="button" disabled={!storyEditor.tekst.trim()} onClick={() => gemStory(p.id)}
                style={{ border: 0, background: T.bordeaux, color: T.paperText, borderRadius: 7, padding: '8px 13px', cursor: storyEditor.tekst.trim() ? 'pointer' : 'default' }}>Gem historie</button>
            </div>
            </fieldset>
          </div>
        )}

        {renderFamilieRelationer(p.id)}

        {renderNarrativEditor({ type: 'person', id: p.id })}

        {renderMateriale({ subjektType: 'person', subjektId: p.id, uploadTarget: { afbildetPersonId: p.id } })}
      </div>
    );
  }

  // Narrativ-editor (udgave-faner + tekstfelt + billed-indsættelse + forhåndsvisning) —
  // generaliseret fra person-only (billeder-i-narrativer 2026-07-05, Slice C3) til ethvert subjekt
  // ('person' | 'slaegt' | 'lineage'), så person-editoren og den nye slægts/linje-editor genbruger
  // ÉN implementering i stedet for en parallel kopi. Læser stadig den fælles narrativer/
  // aktivSourceId/narrativUdkast/nyUdgave-state (sat af loadNarrativer for det aktuelle subjekt).
  function renderNarrativEditor(subjekt: { type: string; id: number | string }) {
    const subjektId = String(subjekt.id);
    return (
      <>
        <div style={sectionHeader(24)}>Narrativ · biografi</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          {/* Udgave-faner: én pr. kilde subjektet har en narrativ i, + evt. ny (ugemt) udgave + "+ Ny udgave" */}
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 10 }}>
            {narrativer.map((n) => (
              <div key={n.id} onClick={() => vaelgUdgave(n.sourceId)} style={{ fontSize: 11.5, padding: '4px 10px', borderRadius: 7, cursor: 'pointer',
                background: n.sourceId === aktivSourceId ? T.bordeaux : 'transparent', color: n.sourceId === aktivSourceId ? T.paper : T.muted,
                border: `1px solid ${n.sourceId === aktivSourceId ? T.bordeaux : 'rgba(34,31,26,.16)'}` }}>
                {n.udgave ?? n.sourceTitel ?? `Kilde ${n.sourceId ?? '—'}`}{n.privat ? ' · privat' : ''}
              </div>
            ))}
            {aktivSourceId != null && !narrativer.some((n) => n.sourceId === aktivSourceId) && (
              <div style={{ fontSize: 11.5, padding: '4px 10px', borderRadius: 7, background: T.bordeaux, color: T.paper, border: `1px solid ${T.bordeaux}` }}>
                {sources.find((s) => s.id === aktivSourceId)?.udgave ?? `Kilde ${aktivSourceId}`} · ny
              </div>
            )}
            <div onClick={() => setNyUdgave({ titel: '', udgave: '', aar: '' })} style={{ fontSize: 11.5, padding: '4px 10px', borderRadius: 7, cursor: 'pointer', border: '1px dashed rgba(34,31,26,.3)', color: T.muted2 }}>+ Ny udgave</div>
          </div>

          {/* Ny udgave: vælg eksisterende kilde subjektet ikke har endnu, ELLER opret en ny DAA-udgave */}
          {nyUdgave != null && (
            <div style={{ ...annoBox, marginBottom: 10, padding: '10px 11px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ fontSize: 10.5, color: T.muted }}>Vælg en udgave subjektet ikke har endnu:</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {ledigeSources.map((s) => (
                  <div key={s.id} onClick={() => vaelgUdgave(s.id)} style={{ fontSize: 11.5, padding: '4px 9px', borderRadius: 6, cursor: 'pointer', border: '1px solid rgba(34,31,26,.16)', color: T.muted }}>
                    {s.udgave ?? s.titel ?? `Kilde ${s.id}`}
                  </div>
                ))}
                {ledigeSources.length === 0 && <span style={{ fontSize: 11, color: T.muted3 }}>(ingen ledige)</span>}
              </div>
              <div style={{ fontSize: 10.5, color: T.muted, marginTop: 2 }}>… eller opret en ny DAA-udgave:</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                <input placeholder="Titel" value={nyUdgave.titel} onChange={(e) => setNyUdgave((u) => ({ ...u!, titel: e.target.value }))} style={{ fontSize: 11.5, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, background: '#fff', color: '#3d382f', outline: 'none', flex: 1, minWidth: 120 }} />
                <input placeholder="Udgave (DAA 1982-84)" value={nyUdgave.udgave} onChange={(e) => setNyUdgave((u) => ({ ...u!, udgave: e.target.value }))} style={{ fontSize: 11.5, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, background: '#fff', color: '#3d382f', outline: 'none', width: 150 }} />
                <input placeholder="År" value={nyUdgave.aar} onChange={(e) => setNyUdgave((u) => ({ ...u!, aar: e.target.value }))} style={{ fontSize: 11.5, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, background: '#fff', color: '#3d382f', outline: 'none', width: 64 }} />
                <div onClick={opretUdgave} style={{ fontSize: 11.5, fontWeight: 600, color: T.paper, background: T.green, borderRadius: 6, padding: '6px 11px', cursor: 'pointer' }}>Opret</div>
              </div>
            </div>
          )}

          <div style={{ marginBottom: 6 }}>
            <span onClick={() => setMediaPickerOpen(true)} style={{ fontSize: 11.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>🖼 Indsæt billede</span>
          </div>
          <textarea ref={narrativTextareaRef} value={narrativUdkast.tekst}
            onChange={(e) => setNarrativUdkast((u) => ({ ...u, tekst: e.target.value }))}
            onSelect={(e) => { narrativSelPos.current = e.currentTarget.selectionStart ?? 0; }}
            style={{ width: '100%', height: 104, fontSize: 13, lineHeight: 1.55, color: '#3d382f', background: '#fff', border: '1px solid rgba(34,31,26,.16)', borderRadius: 9, padding: '11px 12px', outline: 'none', resize: 'vertical' }} />
          {/* Passiv forhåndsvisning — viser hvordan [[type:id|tekst]]-links renderes for publikum,
              så redaktøren kan se om en redigering har brudt et eksisterende link. Ikke klikbar
              (undgår at navigere væk fra en igangværende redigering, jf. review 12 fund om
              korrumperbare tokens i den rå textarea). Fanger KUN knækket token-grammatik — et
              syntaktisk gyldigt token der peger på forkert id ser identisk ud med et korrekt. */}
          {!!narrativUdkast.tekst && (
            <div style={{ marginTop: 8, ...annoBox, fontSize: 11.5, lineHeight: 1.5, color: T.muted }}>
              <div style={{ fontSize: 9.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, marginBottom: 3 }}>Sådan vises det for besøgende</div>
              <NarrativRenderer tekst={narrativUdkast.tekst} onPickPerson={() => {}} linkColor={T.bordeaux} inactiveColor={T.muted2} />
            </div>
          )}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 9 }}>
            <label style={{ fontSize: 11, color: T.muted, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
              <input type="checkbox" checked={narrativUdkast.privat} onChange={(e) => setNarrativUdkast((u) => ({ ...u, privat: e.target.checked }))} /> privat
            </label>
            <label style={{ fontSize: 11, color: T.muted, display: 'flex', alignItems: 'center', gap: 5 }}>
              side <input value={narrativUdkast.side} onChange={(e) => setNarrativUdkast((u) => ({ ...u, side: e.target.value }))} placeholder="fx 209-211" style={{ fontSize: 11, padding: '4px 7px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, background: '#fff', color: '#3d382f', outline: 'none', width: 78 }} />
            </label>
            <div style={{ flex: 1 }} />
            <div onClick={() => run({ art: 'narrativ', subjektType: subjekt.type, subjektId, vaerdi: narrativUdkast.tekst, payload: { privat: narrativUdkast.privat, sourceId: aktivSourceId, side: narrativUdkast.side.trim() || null } }, 'Narrativ')} style={{ fontSize: 12, fontWeight: 600, color: T.paper, background: T.green, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>Gem narrativ</div>
          </div>
        </div>
      </>
    );
  }

  // Slægts/linje-narrativ-editor (billeder-i-narrativer 2026-07-05, Slice C3) — vælger mellem den
  // faste "Generelt"-beskrivelse og en af de 5 navngivne linjer (venstre liste, renderList's
  // slaegt-gren), genbruger narrativ-editoren fuldt ud + Materiale for linjer (ikke "Generelt",
  // der er en sentinel uden egen billed-samling).
  function renderSlaegtEditor() {
    if (!slaegtSubjekt) return <div style={{ padding: 30, color: T.muted3 }}>Vælg "Generelt" eller en linje.</div>;
    return (
      <div style={{ padding: '24px 30px 60px', maxWidth: 780 }}>
        <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1, marginBottom: 16 }}>{slaegtSubjekt.label}</div>
        {renderNarrativEditor(slaegtSubjekt)}
        {slaegtSubjekt.type === 'lineage' && renderMateriale({
          subjektType: 'lineage', subjektId: String(slaegtSubjekt.id),
          uploadTarget: { objektType: 'lineage', objektId: String(slaegtSubjekt.id) },
        })}
      </div>
    );
  }

  // Materiale-galleri + upload/fjern/slet — delt mellem person-editoren (afbildetPersonId) og
  // objekt-foto på generiske entiteter (estate/coat_of_arms via objektType/objektId, Slice 0h).
  // subjektType/subjektId styrer KUN red_suggest-fallbacken (buildRpcCall's uploadMedia/fjernMedia/
  // sletRelation-grene læser dem ikke) — sat til noget meningsfuldt for audit-sporet alligevel.
  function renderMateriale({ subjektType, subjektId, uploadTarget }: {
    subjektType: string; subjektId: string; uploadTarget: Record<string, unknown>;
  }) {
    const mayUpload = role === 'redaktion';
    // Lightbox (Slice A): kun url-bærende rækker er navigerbare (nogle kan mangle url, fx
    // 'kladde' eller mislykket signering) — filtrér FØR indeksering, ellers kan pil-navigation
    // lande på en url-løs post og lukke lightboxen uventet.
    const mediaMedLightbox = withUrl(media.filter((m) => m.uploadStatus === 'klar' && m.mimeType?.startsWith('image/') === true && !!m.thumbUrl));
    return (
      <>
        <div style={sectionHeader(24)}>Materiale</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          {media.length ? (
            <div style={{ display: 'flex', gap: 9, flexWrap: 'wrap', marginBottom: 12 }}>
              {media.map((m) => {
                const erBillede = m.mimeType?.startsWith('image/') === true && !!m.thumbUrl && !!m.url;
                return <div key={m.id} style={{ width: 96 }}>
                  {erBillede ? (
                    <img src={m.thumbUrl!} alt={m.titel ?? m.slags}
                      onClick={() => {
                        if (mayUpload) setMediaDetalje({ id: m.id, subjektType, subjektId });
                        else {
                          const i = mediaMedLightbox.findIndex((x) => x.id === m.id);
                          if (i >= 0) setMediaLightbox(i);
                        }
                      }}
                      style={{ width: 96, height: 96, objectFit: 'cover', borderRadius: 10, background: T.beige,
                        cursor: mayUpload ? 'pointer' : 'zoom-in', opacity: m.uploadStatus === 'fjernet' ? .45 : 1 }} />
                  ) : (
                    <div onClick={() => { if (mayUpload) setMediaDetalje({ id: m.id, subjektType, subjektId }); }}
                      style={{ width: 96, height: 96, borderRadius: 10, background: T.beige,
                        cursor: mayUpload ? 'pointer' : 'default', opacity: m.uploadStatus === 'fjernet' ? .45 : 1,
                        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: T.muted }}>
                      <span style={{ fontSize: 28 }}>▤</span><span style={{ fontSize: 9 }}>{m.slags || 'dokument'}</span>
                    </div>
                  )}
                  <div style={{ fontFamily: T.mono, fontSize: 8, color: T.muted2, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {m.slags}{m.uploadStatus !== 'klar' ? ` · ${m.uploadStatus}` : ''}{m.maaPubliceres ? '' : ' · ej publiceret'}
                  </div>
                  {mayUpload ? (
                    <div style={{ display: 'flex', gap: 8, marginTop: 3 }}>
                      {m.uploadStatus === 'fjernet' ? (
                        <span onClick={() => run({ art: 'genopretMedia', subjektType, subjektId, mediaId: m.id }, 'Genopret billede')}
                          style={{ fontFamily: T.mono, fontSize: 9, color: T.green, cursor: 'pointer' }}>Genopret</span>
                      ) : <>
                        <span onClick={() => m.relationId && run({ art: 'sletRelation', subjektType, subjektId, relationId: m.relationId }, 'Fjern billede')}
                          style={{ fontFamily: T.mono, fontSize: 9, color: m.relationId ? T.muted : T.muted3, cursor: m.relationId ? 'pointer' : 'default' }}>Fjern</span>
                      </>}
                    </div>
                  ) : null}
                </div>;
              })}
            </div>
          ) : (
            <div style={{ fontSize: 12, color: T.muted3, marginBottom: 10 }}>Intet materiale endnu.</div>
          )}

          {mayUpload ? (
            <>
              <input ref={mediaInputRef} type="file" accept="image/*" style={{ display: 'none' }}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  e.target.value = '';
                  if (!file) return;
                  setMediaDedup(null);
                  setMediaPick({ file, previewUrl: URL.createObjectURL(file) });
                  if (!mediaForm.titel) setMediaForm((f) => ({ ...f, titel: file.name.replace(/\.[^.]+$/, '') }));
                }} />

              {!mediaPick ? (
                <div onClick={() => mediaInputRef.current?.click()} style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, border: '1px solid rgba(136,26,51,.3)', borderRadius: 7, padding: '8px 13px', display: 'inline-block', cursor: 'pointer' }}>
                  + Vælg billede
                </div>
              ) : (
                <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
                  <img src={mediaPick.previewUrl} alt="" style={{ width: 96, height: 96, objectFit: 'cover', borderRadius: 10, flex: 'none' }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginBottom: 8 }}>
                      {MEDIA_SLAGS.map((s) => (
                        <span key={s} onClick={() => setMediaForm((f) => ({ ...f, slags: s }))}
                          style={{ fontFamily: T.mono, fontSize: 10, fontWeight: 600, padding: '4px 8px', borderRadius: 6, cursor: 'pointer', background: mediaForm.slags === s ? T.bordeaux : T.beige, color: mediaForm.slags === s ? T.paperText : T.muted }}>
                          {s}
                        </span>
                      ))}
                    </div>
                    <input value={mediaForm.titel} onChange={(e) => setMediaForm((f) => ({ ...f, titel: e.target.value }))}
                      placeholder="Titel" style={inp} />
                    <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                      <input value={mediaForm.kunstner} onChange={(e) => setMediaForm((f) => ({ ...f, kunstner: e.target.value }))} placeholder="Kunstner" style={inp} />
                      <input value={mediaForm.datering} onChange={(e) => setMediaForm((f) => ({ ...f, datering: e.target.value }))} placeholder="Datering" style={inp} />
                    </div>
                    <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginTop: 8 }}>
                      {MEDIA_RETTIGHED_STATUS.map((s) => (
                        <span key={s} onClick={() => setMediaForm((f) => ({ ...f, rettighederStatus: s }))}
                          style={{ fontFamily: T.mono, fontSize: 9, padding: '4px 7px', borderRadius: 6, cursor: 'pointer', background: mediaForm.rettighederStatus === s ? T.bordeaux : T.beige, color: mediaForm.rettighederStatus === s ? T.paperText : T.muted }}>
                          {s}
                        </span>
                      ))}
                    </div>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: T.muted, marginTop: 8 }}>
                      <input type="checkbox" checked={mediaForm.maaPubliceres} onChange={(e) => setMediaForm((f) => ({ ...f, maaPubliceres: e.target.checked }))} />
                      Må publiceres (rettigheder afklaret)
                    </label>
                    <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                      <div onClick={mediaBusy ? undefined : async () => {
                        if (!mediaForm.titel.trim()) return;
                        setMediaBusy(true);
                        try {
                          const built = await buildVariants(mediaPick.file);
                          const { thumb, medium, large, sha256 } = built;
                          const { data: existing, error: lookupError } = await supabase.from('media')
                            .select('id,titel,upload_status,storage_path')
                            .eq('sha256', sha256)
                            .maybeSingle();
                          if (lookupError) throw new Error(lookupError.message);
                          if (existing) {
                            setMediaDedup({
                              existing: { ...existing, id: String(existing.id) }, built,
                              uploadTarget, originalFilnavn: mediaPick.file.name,
                            });
                            return;
                          }
                          await run({ art: 'uploadMedia', subjektType, subjektId, payload: {
                            ...uploadTarget, slags: mediaForm.slags, titel: mediaForm.titel.trim(),
                            kunstner: mediaForm.kunstner.trim() || null, datering: mediaForm.datering.trim() || null,
                            rettighederStatus: mediaForm.rettighederStatus, maaPubliceres: mediaForm.maaPubliceres,
                            file: large.file, mimeType: large.mimeType,
                            byteSize: large.byteSize, bredde: large.bredde, hoejde: large.hoejde,
                            originalFilnavn: mediaPick.file.name, storagePath: large.storagePath, sha256,
                            varianter: [thumb, medium],
                          } }, 'Materiale');
                          setMediaPick(null);
                        } catch (e) {
                          setWriteView({ title: 'Materiale fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false });
                        } finally {
                          setMediaBusy(false);
                        }
                      }} style={btnGreen}>{mediaBusy ? 'Behandler…' : 'Gem'}</div>
                      <div onClick={() => { setMediaDedup(null); setMediaPick(null); }} style={btnGhost}>Annullér</div>
                    </div>
                  </div>
                </div>
              )}
            </>
          ) : (
            // Upload kan ikke degradere til red_suggest (forslags-laget ejer ingen fil-bytes at
            // pege på) — modsat tekst-redigering vises knappen derfor slet ikke for ikke-redaktion.
            <div style={{ fontSize: 11.5, color: T.muted3 }}>Kun redaktion kan tilføje materiale.</div>
          )}
        </div>
        {mediaLightbox != null && (
          <Lightbox items={mediaMedLightbox} index={mediaLightbox} onClose={() => setMediaLightbox(null)} onNavigate={setMediaLightbox} />
        )}
      </>
    );
  }


  function renderMediaDetalje() {
    if (!mediaDetalje || role !== 'redaktion') return null;
    const m = entity === 'media'
      ? mediaBibliotek.find((x) => x.id === mediaDetalje.id)
      : media.find((x) => x.id === mediaDetalje.id);
    if (!m) return null;
    const base = entity === 'media' ? mediaBibliotek : media;
    const lightboxItems = withUrl(base.filter((x) => x.uploadStatus === 'klar' && x.mimeType?.startsWith('image/') === true && !!x.thumbUrl));
    const relationId = 'relationId' in m ? m.relationId : undefined;
    return <>
      <MediaDetaljeOverlay
        media={m}
        anvendelse={mediaAnvendelse}
        anvendelseFejl={mediaAnvendelseFejl}
        onClose={() => {
          setMediaDetalje(null); setMediaLightbox(null);
          if (entity === 'media') { setRecordId(null); navigate(redaktionPath('media', null)); }
        }}
        onPreview={() => {
          const i = lightboxItems.findIndex((x) => x.id === m.id);
          if (i >= 0) setMediaLightbox(i);
        }}
        onGemMetadata={(payload) => run({ art: 'opdaterMedia', subjektType: mediaDetalje.subjektType,
          subjektId: mediaDetalje.subjektId, mediaId: m.id, payload }, 'Opdater medie')}
        onGemRettigheder={(payload) => run({ art: 'mediaRettigheder', subjektType: mediaDetalje.subjektType,
          subjektId: mediaDetalje.subjektId, mediaId: m.id, payload }, 'Gem rettigheder')}
        onFjern={() => relationId && run({ art: 'sletRelation', subjektType: mediaDetalje.subjektType,
          subjektId: mediaDetalje.subjektId, relationId }, 'Fjern billede')}
        onFjernTilknytning={(id) => run({ art: 'sletRelation', subjektType: 'media', subjektId: m.id, relationId: id }, 'Fjern tilknytning')}
        onTilknyt={() => setMediaTilknytPicker({ mediaId: m.id, maalType: 'person' })}
        onSlet={() => run({ art: 'fjernMedia', subjektType: mediaDetalje.subjektType,
          subjektId: mediaDetalje.subjektId, mediaId: m.id }, 'Slet billede')}
        onGenopret={() => run({ art: 'genopretMedia', subjektType: mediaDetalje.subjektType,
          subjektId: mediaDetalje.subjektId, mediaId: m.id }, 'Genopret billede')}
      />
      {entity === 'media' && mediaLightbox != null ? <Lightbox items={lightboxItems} index={mediaLightbox} onClose={() => setMediaLightbox(null)} onNavigate={setMediaLightbox} /> : null}
    </>;
  }

  function renderFactCard(pid: string, label: string, f: FeltEvidens) {
    const konk = konklusionAf(f);
    const ek = pid + ':' + f.factId + ':' + label;
    const open = !!expanded[ek];
    return (
      <div key={ek} style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, marginBottom: 9, overflow: 'hidden' }}>
        <div onClick={() => setExpanded((s) => ({ ...s, [ek]: !s[ek] }))} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '12px 15px', cursor: 'pointer' }}>
          <span style={{ flex: 'none', width: 78, fontFamily: T.mono, fontSize: 9.5, textTransform: 'uppercase', color: T.muted2 }}>{label}</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, lineHeight: 1.1 }}>{konk?.vaerdi || '—'}</div>
            <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>⮡ {konk ? kildeAf(konk) : 'ingen oplysninger'}</div>
          </div>
          {f.uenig && <span style={{ fontFamily: T.mono, fontSize: 8, textTransform: 'uppercase', color: T.red, background: '#f2dede', borderRadius: 5, padding: '3px 7px' }}>uenige kilder</span>}
          <span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted, background: T.beige, borderRadius: 5, padding: '3px 7px' }}>{f.oplysninger.length} {f.oplysninger.length === 1 ? 'oplysning' : 'oplysninger'}</span>
          <span style={{ color: '#bcae93', fontSize: 11 }}>{open ? '▾' : '▸'}</span>
        </div>
        {open && (
          <div style={{ padding: '2px 15px 14px' }}>
            {f.oplysninger.map((o) => renderOplysning(pid, f, o))}
            {f.factId > 0 && (addingFact === f.factId ? (
              <div style={{ background: T.paper, border: '1px solid rgba(34,31,26,.16)', borderRadius: 10, padding: 12, marginTop: 3 }}>
                <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux, marginBottom: 8 }}>Ny oplysning</div>
                <input value={sc('add:' + f.factId + ':v')} onChange={(e) => setSc('add:' + f.factId + ':v', e.target.value)} placeholder="Værdi" style={inp} />
                <input value={sc('add:' + f.factId + ':src')} onChange={(e) => setSc('add:' + f.factId + ':src', e.target.value)} placeholder="Kildeangivelse — kilde, side/linje/nr" style={{ ...inp, marginTop: 7 }} />
                <div style={{ display: 'flex', gap: 8, marginTop: 9 }}>
                  <div onClick={() => { run({ art: 'tilfoejOplysning', subjektType: 'person', subjektId: pid, factId: String(f.factId), felt: f.felt, vaerdi: sc('add:' + f.factId + ':v'), kildeFritekst: sc('add:' + f.factId + ':src') || undefined }, 'Tilføj oplysning'); setAddingFact(null); }} style={btnGreen}>Registrér oplysning</div>
                  <div onClick={() => setAddingFact(null)} style={btnGhost}>Annullér</div>
                </div>
              </div>
            ) : (
              <div onClick={() => setAddingFact(f.factId)} style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', padding: '4px 2px' }}>+ Tilføj oplysning</div>
            ))}
          </div>
        )}
      </div>
    );
  }

  function renderOplysning(pid: string, f: FeltEvidens, o: Oplysning) {
    const editing = editingAssert === o.assertionId;
    return (
      <div key={o.assertionId} style={{ display: 'flex', alignItems: 'flex-start', gap: 11, background: o.erKonklusion ? '#eaf3ec' : T.paper, border: `1px solid ${o.erKonklusion ? 'rgba(31,91,58,.32)' : 'rgba(34,31,26,.1)'}`, borderRadius: 10, padding: '10px 12px', marginBottom: 7 }}>
        <span style={{ width: 11, height: 11, borderRadius: '50%', background: o.erKonklusion ? T.green : '#bcae93', marginTop: 4 }} />
        {!editing ? (
          <>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600 }}>{o.vaerdi || '—'}</span>
                <span style={{ fontFamily: T.mono, fontSize: 8, textTransform: 'uppercase', color: o.erKonklusion ? T.green : T.muted2 }}>{o.erKonklusion ? 'konklusion' : 'oplysning'}</span>
              </div>
              <div style={{ fontSize: 12, color: T.muted, marginTop: 3 }}>§ {kildeAf(o)}</div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
              {!o.erKonklusion && <div onClick={() => run({ art: 'setKonklusion', subjektType: 'person', subjektId: pid, assertionId: String(o.assertionId) }, 'Konklusion')} style={{ fontSize: 11, fontWeight: 600, color: T.green, border: '1px solid rgba(31,91,58,.4)', borderRadius: 7, padding: '6px 9px', cursor: 'pointer', whiteSpace: 'nowrap' }}>Gør til konklusion</div>}
              <div style={{ display: 'flex', gap: 4 }}>
                <span onClick={() => { setEditingAssert(o.assertionId); setAddingFact(null); setSc('ed:' + o.assertionId + ':v', o.vaerdi); setSc('ed:' + o.assertionId + ':src', kildeAf(o) === 'ingen kilde' ? '' : kildeAf(o)); }} title="Redigér" style={iconBtn}>✎</span>
                <span onClick={() => run({ art: 'sletOplysning', subjektType: 'person', subjektId: pid, assertionId: String(o.assertionId) }, 'Slet oplysning')} title="Slet" style={{ ...iconBtn, border: '1px solid rgba(138,43,43,.3)', color: T.red }}>🗑</span>
              </div>
            </div>
          </>
        ) : (
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux, marginBottom: 7 }}>Redigér oplysning</div>
            <input value={sc('ed:' + o.assertionId + ':v', o.vaerdi)} onChange={(e) => setSc('ed:' + o.assertionId + ':v', e.target.value)} placeholder="Værdi" style={inp} />
            <input value={sc('ed:' + o.assertionId + ':src')} onChange={(e) => setSc('ed:' + o.assertionId + ':src', e.target.value)} placeholder="Kildeangivelse" style={{ ...inp, marginTop: 7 }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 9 }}>
              <div onClick={() => { run({ art: 'redigerOplysning', subjektType: 'person', subjektId: pid, assertionId: String(o.assertionId), felt: f.felt, vaerdi: sc('ed:' + o.assertionId + ':v', o.vaerdi), kildeFritekst: sc('ed:' + o.assertionId + ':src') || undefined }, 'Redigér'); setEditingAssert(null); }} style={btnGreen}>Gem ændring</div>
              <div onClick={() => setEditingAssert(null)} style={btnGhost}>Annullér</div>
            </div>
          </div>
        )}
      </div>
    );
  }

  // ---- Generisk editor (entiteter uden direkte RPC → red_suggest) ----
  // ---- Familie & relationer (2C-2b/2C-2a, web) ----
  function renderFamilieRelationer(pid: string) {
    const KONF = ['sikker', 'sandsynlig', 'formodet', 'omstridt'] as const;
    const hverv = (relationer ?? []).filter((r) => r.art === 'hverv');
    const godser = (relationer ?? []).filter((r) => r.art === 'gods');
    const subHeader = (label: string, onAdd: () => void, addLabel: string, mt = 0) => (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 7, marginTop: mt }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: T.muted }}>{label}</span>
        <span onClick={onAdd} style={{ fontSize: 11, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>{addLabel}</span>
      </div>
    );
    const konfidensChips = (current: string | null, onChange: (k: string) => void) => (
      <div style={{ display: 'flex', gap: 3, flex: 'none' }}>
        {KONF.map((k) => (
          <span key={k} onClick={() => onChange(k)} title={k} style={{ fontFamily: T.mono, fontSize: 8, fontWeight: 600, padding: '3px 5px', borderRadius: 5, cursor: 'pointer', background: current === k ? T.bordeaux : T.beige, color: current === k ? T.paperText : T.muted }}>{k.slice(0, 3)}</span>
        ))}
      </div>
    );
    // onOpen (valgfri): gør navnet klikbart → naviger til den person (kun for person-rækker,
    // ikke hverv/godser). Skifter recordId som browse-listen gør; ugemte narrativ-edits kasseres
    // stille — samme adfærd som person-listen (bevidst konsistent, ingen ny advarsel).
    const linkRow = (navn: string, meta: string, onRemove: () => void, extra?: React.ReactNode, onOpen?: () => void) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '8px 11px', marginBottom: 6 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div onClick={onOpen} title={onOpen ? 'Åbn person' : undefined}
            style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600, lineHeight: 1.05, cursor: onOpen ? 'pointer' : 'default', color: onOpen ? T.bordeaux : undefined, display: 'inline-flex', alignItems: 'center', gap: 5 }}>
            {navn}{onOpen && <span style={{ fontSize: 10, opacity: .55 }}>↗</span>}
          </div>
          {meta && <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted2, marginTop: 1 }}>{meta}</div>}
        </div>
        {extra}
        <span onClick={onRemove} title="Fjern" style={{ color: '#bcae93', fontSize: 13, cursor: 'pointer', flex: 'none' }}>✕</span>
      </div>
    );
    return (
      <>
        <div style={sectionHeader(26)}>Familie</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          {!familie ? <div style={{ fontSize: 12.5, color: T.muted3 }}>Henter familie…</div> : (
            <>
              {familie.somPartner.map((u) => (
                <div key={u.familyId} style={{ marginBottom: 13 }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 7 }}>
                    <span style={{ fontSize: 12, fontWeight: 600, color: T.muted }}>
                      {u.type || 'partnerskab'} ·{' '}
                      {u.partnere.length ? u.partnere.map((p, idx) => (
                        <span key={p.personId}>
                          <span onClick={() => openRecord('person', p.personId)} title="Åbn person" style={{ color: T.bordeaux, cursor: 'pointer' }}>{p.navn}</span>
                          {p.aar ? <span style={{ color: T.muted3, fontWeight: 500 }}> ({p.aar})</span> : null}
                          {idx < u.partnere.length - 1 ? ', ' : ''}
                        </span>
                      )) : '(ukendt partner)'}
                    </span>
                    <span onClick={() => setPicker({ kind: 'barn', familyId: u.familyId })} style={{ fontSize: 11, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>+ Tilføj barn</span>
                  </div>
                  {u.boern.map((b, i) => {
                    const opOrdinal = nudgeOrdinal(u.boern, i, 'op');
                    const nedOrdinal = nudgeOrdinal(u.boern, i, 'ned');
                    const pil = (retning: '↑' | '↓', ordinal: number | null, titel: string) => (
                      <span key={retning} onClick={ordinal == null ? undefined : () => run({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle, ordinal }, titel)}
                        style={{ fontSize: 12, cursor: ordinal == null ? 'default' : 'pointer', color: ordinal == null ? T.muted3 : T.muted, padding: '0 2px' }}>{retning}</span>
                    );
                    return linkRow(b.navn, [b.rolle, b.aar].filter(Boolean).join(' · '), () => run({ art: 'sletFamilieLink', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle }, 'Fjern barn'),
                      <>
                        {pil('↑', opOrdinal, 'Flyt op')}
                        {pil('↓', nedOrdinal, 'Flyt ned')}
                        {konfidensChips(b.konfidens, (k) => run({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle, konfidens: k }, 'Konfidens'))}
                        <span onClick={() => setFlytBarn({ fraFamilyId: u.familyId, personId: b.personId, rolle: b.rolle, navn: b.navn })}
                          style={{ fontFamily: T.mono, fontSize: 9, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>flyt→</span>
                      </>,
                      () => openRecord('person', b.personId));
                  })}
                </div>
              ))}
              {familie.somBarn.map((sb, i) => (
                <div key={sb.familyId + i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', fontSize: 12.5 }}>
                  <span style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.gold }}>Barn af</span>
                  <span style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600 }}>
                    {sb.foraeldre.length ? sb.foraeldre.map((f, j) => (
                      <span key={f.personId}>
                        <span onClick={() => openRecord('person', f.personId)} title="Åbn person" style={{ color: T.bordeaux, cursor: 'pointer' }}>{f.navn}</span>
                        {j < sb.foraeldre.length - 1 ? ' & ' : ''}
                      </span>
                    )) : '(ukendt)'}
                  </span>
                  <span style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted2 }}>{sb.rolle}{sb.konfidens ? ` · ${sb.konfidens}` : ''}</span>
                </div>
              ))}
              <div onClick={() => setPicker({ kind: 'partner' })} style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginTop: 6 }}>+ Nyt partnerskab</div>
            </>
          )}
        </div>

        <div style={sectionHeader(24)}>Embeder & godser</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          {!relationer ? <div style={{ fontSize: 12.5, color: T.muted3 }}>Henter relationer…</div> : (
            <>
              {subHeader('Embeder, rang & hverv', () => setPicker({ kind: 'hverv' }), '+ Tilføj hverv')}
              {hverv.length ? hverv.map((r) => linkRow(r.navn, [r.rolle, r.periode].filter(Boolean).join(' · '), () => run({ art: 'sletRelation', subjektType: 'person', subjektId: pid, relationId: String(r.relationId) }, 'Fjern hverv'))) : <div style={{ fontSize: 11.5, color: T.muted3, marginBottom: 8 }}>Ingen hverv.</div>}
              {subHeader('Godser & besiddelser', () => setPicker({ kind: 'gods' }), '+ Tilføj gods', 10)}
              {godser.length ? godser.map((r) => linkRow(r.navn, [r.rolle, r.periode].filter(Boolean).join(' · '), () => run({ art: 'sletRelation', subjektType: 'person', subjektId: pid, relationId: String(r.relationId) }, 'Fjern gods'))) : <div style={{ fontSize: 11.5, color: T.muted3 }}>Ingen godser.</div>}
              {subHeader('Samme person', () => setPicker({ kind: 'sammeSom' }), '+ Marker som samme person', 10)}
              {sammeSom.length ? sammeSom.map((l) => linkRow(
                persons.find((p) => p.id === l.modpartId)?.navn ?? `#${l.modpartId}`,
                l.retning === 'alias' ? 'denne foldes ind i' : 'foldes ind i denne',
                () => run({ art: 'fjernSammeSom', subjektType: 'person', subjektId: pid, relationId: l.relationId }, 'Fjern samme-person-link'),
              )) : <div style={{ fontSize: 11.5, color: T.muted3 }}>Ingen identitets-links.</div>}
            </>
          )}
        </div>
      </>
    );
  }

  function renderPicker() {
    if (!picker) return null;
    const isPerson = picker.kind === 'barn' || picker.kind === 'partner' || picker.kind === 'sammeSom';
    const q = pickQuery.trim().toLowerCase();
    const items: { id: string; label: string; sub: string }[] = isPerson
      ? persons.filter((p) => p.id !== recordId && p.navn.toLowerCase().includes(q)).slice(0, 40).map((p) => ({ id: p.id, label: p.navn, sub: p.aar || '—' }))
      : (recCache[picker.kind === 'hverv' ? 'org' : 'estate'] ?? []).filter((r) => (r.label + ' ' + r.sub).toLowerCase().includes(q)).slice(0, 40).map((r) => ({ id: r.id, label: r.label, sub: r.sub }));
    const titel = picker.kind === 'barn' ? 'Vælg barn' : picker.kind === 'partner' ? 'Vælg partner' : picker.kind === 'sammeSom' ? 'Vælg samme person' : picker.kind === 'hverv' ? 'Vælg organisation' : 'Vælg gods';
    const onPick = (id: string) => {
      const sid = recordId!;
      if (picker.kind === 'sammeSom') {
        setSsConfirm({ personId: id, navn: persons.find((p) => p.id === id)?.navn ?? id, kanoniskId: sid });
        setPicker(null); setPickQuery('');
        return;
      }
      // type 'vielse' matcher mobilens UNION_TYPER (ikke 'ægteskab'); roller medlem/ejer er DB-fritekst.
      const changes: Record<Exclude<typeof picker.kind, 'sammeSom'>, Change> = {
        barn: { art: 'tilfoejBarn', subjektType: 'person', subjektId: sid, payload: { familyId: picker.familyId, barnId: id, rolle: 'barn', konfidens: null } },
        partner: { art: 'opretUnion', subjektType: 'person', subjektId: sid, payload: { partnerA: sid, partnerB: id, type: 'vielse', ordinal: null } },
        hverv: { art: 'tilfoejRelation', subjektType: 'person', subjektId: sid, payload: { objektType: 'organisation', objektId: id, rolle: 'medlem', periodeRaw: null } },
        gods: { art: 'tilfoejRelation', subjektType: 'person', subjektId: sid, payload: { objektType: 'estate', objektId: id, rolle: 'ejer', periodeRaw: null } },
      };
      run(changes[picker.kind], 'Tilføj');
      setPicker(null); setPickQuery('');
    };
    return (
      <div onClick={() => { setPicker(null); setPickQuery(''); }} style={overlay(96)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 420, maxWidth: '100%', maxHeight: '70vh', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '16px 18px 12px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, marginBottom: 9 }}>{titel}</div>
            <input autoFocus value={pickQuery} onChange={(e) => setPickQuery(e.target.value)} placeholder="Søg…" style={{ ...inp, background: '#fff' }} />
          </div>
          <div data-scroll style={{ flex: 1, overflowY: 'auto', padding: '0 10px 12px' }}>
            {items.map((it) => (
              <div key={it.id} onClick={() => onPick(it.id)} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 9px', borderRadius: 9, cursor: 'pointer' }}>
                <span style={{ width: 28, height: 28, borderRadius: isPerson ? '50%' : 7, background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 11, fontWeight: 600, color: T.bordeaux }}>{isPerson ? initials(it.label) : '⌂'}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{it.label}</div>
                  <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2 }}>{it.sub}</div>
                </div>
              </div>
            ))}
            {!items.length && <div style={{ padding: '18px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>Ingen træffere.</div>}
          </div>
        </div>
      </div>
    );
  }

  function renderMediaTilknytPicker() {
    if (!mediaTilknytPicker) return null;
    const q = mediaTilknytQuery.trim().toLowerCase();
    const maalType = mediaTilknytPicker.maalType;
    const typer: { key: typeof maalType; label: string }[] = [
      { key: 'person', label: 'Person' }, { key: 'estate', label: 'Gods' },
      { key: 'coat_of_arms', label: 'Våben' }, { key: 'lineage', label: 'Linje' },
    ];
    const items: { id: string; label: string; sub: string }[] = maalType === 'person'
      ? persons.map((p) => ({ id: p.id, label: p.navn, sub: p.aar || '—' }))
      : maalType === 'lineage'
        ? lineages.map((l) => ({ id: String(l.id), label: l.navn ?? `Linje ${l.kode}`, sub: `Linje ${l.kode}` }))
        : (recCache[maalType === 'estate' ? 'estate' : 'arms'] ?? []).map((r) => ({ id: r.id, label: r.label, sub: r.sub }));
    const tilknyttede = new Set((mediaAnvendelse?.afbildet ?? []).map((a) => `${a.type}:${a.id}`));
    const synlige = items
      .filter((it) => !tilknyttede.has(`${maalType}:${it.id}`))
      .filter((it) => !q || `${it.label} ${it.sub}`.toLowerCase().includes(q)).slice(0, 50);
    const luk = () => { setMediaTilknytPicker(null); setMediaTilknytQuery(''); };
    return (
      <div onClick={luk} style={overlay(130)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 460, maxWidth: '100%', maxHeight: '75vh', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '16px 18px 12px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, marginBottom: 9 }}>Tilknyt medie</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 10 }}>
              {typer.map((t) => <button type="button" key={t.key} onClick={() => setMediaTilknytPicker((p) => p && ({ ...p, maalType: t.key }))}
                style={{ border: 0, borderRadius: 6, padding: '5px 9px', cursor: 'pointer', background: maalType === t.key ? T.bordeaux : T.beige, color: maalType === t.key ? T.paperText : T.muted }}>{t.label}</button>)}
            </div>
            <input autoFocus value={mediaTilknytQuery} onChange={(e) => setMediaTilknytQuery(e.target.value)} placeholder="Søg…" style={{ ...inp, background: '#fff' }} />
          </div>
          <div data-scroll style={{ flex: 1, overflowY: 'auto', padding: '0 10px 12px' }}>
            {synlige.map((it) => <div key={it.id} onClick={() => {
              run({ art: 'tilknytMedia', subjektType: 'media', subjektId: mediaTilknytPicker.mediaId, mediaId: mediaTilknytPicker.mediaId, payload: { maalType, maalId: it.id } }, 'Tilknyt medie');
              luk();
            }} style={{ padding: '9px 10px', borderRadius: 8, cursor: 'pointer' }}>
              <div style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600 }}>{it.label}</div>
              <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2 }}>{it.sub}</div>
            </div>)}
            {!synlige.length && <div style={{ padding: '18px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>Ingen træffere.</div>}
          </div>
        </div>
      </div>
    );
  }

  function renderMediaDedupDialog() {
    if (!mediaDedup) return null;
    const { existing, built, uploadTarget } = mediaDedup;
    const maalType = uploadTarget.afbildetPersonId != null ? 'person'
      : typeof uploadTarget.objektType === 'string' ? uploadTarget.objektType : null;
    const maalId = uploadTarget.afbildetPersonId != null ? String(uploadTarget.afbildetPersonId)
      : uploadTarget.objektId != null ? String(uploadTarget.objektId) : null;
    const gyldigtMaal = maalType === 'person' || maalType === 'estate'
      || maalType === 'coat_of_arms' || maalType === 'lineage';
    const alleredeTilknyttet = media.some((m) => m.id === existing.id);
    const subjektLabel = maalType === 'person'
      ? persons.find((p) => p.id === maalId)?.navn
      : maalType === 'lineage'
        ? lineages.find((l) => String(l.id) === maalId)?.navn
        : (recCache[maalType === 'coat_of_arms' ? 'arms' : 'estate'] ?? []).find((r) => r.id === maalId)?.label;

    const luk = () => setMediaDedup(null);
    const tilknytEksisterende = async (): Promise<boolean> => {
      if (!gyldigtMaal || !maalId) throw new Error('Uploadmålet kan ikke tilknyttes.');
      const result = await run({
        art: 'tilknytMedia', subjektType: 'media', subjektId: existing.id, mediaId: existing.id,
        payload: { maalType, maalId },
      }, 'Tilknyt eksisterende medie');
      return result != null;
    };
    const refreshAktueltMateriale = async () => {
      if (maalType === 'person' && maalId) setMedia(await fetchRedPersonMedia(maalId));
      else if (gyldigtMaal && maalId) setMedia(await fetchRedObjectMedia(maalType, maalId));
    };
    const afslut = () => { setMediaDedup(null); setMediaPick(null); };

    const tilknyt = async () => {
      setMediaBusy(true);
      try {
        if (await tilknytEksisterende()) afslut();
        else setMediaDedup(null);
      } catch (e) {
        setWriteView({ title: 'Tilknytning fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false });
        setMediaDedup(null);
      } finally { setMediaBusy(false); }
    };
    const genoptag = async () => {
      if (dryRun) {
        setWriteView({
          title: 'Dry-run · afbrudt upload ville blive færdiggjort',
          lines: [`Eksisterende medie ${existing.id}: upload large + 2 varianter, bekræft og tilknyt om nødvendigt.`],
          error: '', done: false, dryRun: true, direkte: true,
        });
        setMediaDedup(null);
        return;
      }
      setMediaBusy(true);
      try {
        await resumeMediaUpload(existing.id, built.large, [built.thumb, built.medium]);
        if (!alleredeTilknyttet) {
          if (!await tilknytEksisterende()) { setMediaDedup(null); return; }
        } else {
          await refreshAktueltMateriale();
          setWriteView({ title: 'Afbrudt upload færdiggjort', lines: [`Eksisterende medie ${existing.id} er bekræftet og varianterne registreret.`], error: '', done: true, dryRun: false, direkte: true });
        }
        afslut();
      } catch (e) {
        setWriteView({ title: 'Færdiggørelse fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun: false, direkte: false });
        setMediaDedup(null);
      } finally { setMediaBusy(false); }
    };

    return (
      <div onClick={luk} style={overlay(150)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 470, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '18px 20px' }}>
          <div style={{ display: 'flex', gap: 13, alignItems: 'center', marginBottom: 14 }}>
            {mediaPick?.previewUrl ? <img src={mediaPick.previewUrl} alt="" style={{ width: 72, height: 72, objectFit: 'cover', borderRadius: 9, background: T.beige }} /> : null}
            <div>
              <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600 }}>
                {existing.upload_status === 'klar' ? 'Billedet findes allerede'
                  : existing.upload_status === 'fjernet' ? 'Billedet ligger i papirkurven'
                  : existing.upload_status === 'kladde' ? 'Afbrudt upload fundet' : 'Eksisterende billede fundet'}
              </div>
              <div style={{ fontSize: 12.5, color: T.muted, marginTop: 3 }}>{existing.titel || mediaDedup.originalFilnavn}</div>
            </div>
          </div>

          {existing.upload_status === 'klar' ? (
            alleredeTilknyttet
              ? <div style={{ fontSize: 12.5, color: T.muted }}>Mediet er allerede tilknyttet dette subjekt.</div>
              : <div onClick={mediaBusy ? undefined : tilknyt} style={btnGreen}>{mediaBusy ? 'Behandler…' : `Tilknyt til ${subjektLabel || 'dette subjekt'} i stedet`}</div>
          ) : existing.upload_status === 'fjernet' ? (
            <>
              <div style={{ fontSize: 12.5, color: T.muted, lineHeight: 1.5, marginBottom: 11 }}>
                Mediet skal genoprettes fra filsiden. Upload-arket genopretter det ikke automatisk.
              </div>
              <a href={`/redaktion/media/${existing.id}`} onClick={(e) => { e.preventDefault(); afslut(); navigate(`/redaktion/media/${existing.id}`); }}
                style={{ ...btnGreen, display: 'inline-block', textDecoration: 'none' }}>Åbn filsiden</a>
            </>
          ) : existing.upload_status === 'kladde' ? (
            <>
              <div style={{ fontSize: 12.5, color: T.muted, lineHeight: 1.5, marginBottom: 11 }}>
                Uploaden blev afbrudt. De indholdsadresserede filer genbruges, og den eksisterende mediepost færdiggøres.
              </div>
              <div onClick={mediaBusy ? undefined : genoptag} style={btnGreen}>{mediaBusy ? 'Behandler…' : 'Færdiggør afbrudt upload'}</div>
            </>
          ) : (
            <div style={{ fontSize: 12.5, color: T.red }}>Mediets status “{existing.upload_status}” kan ikke håndteres fra upload-arket.</div>
          )}
          <div onClick={luk} style={{ ...btnGhost, display: 'inline-block', marginTop: 9 }}>Tilbage</div>
        </div>
      </div>
    );
  }

  // Billed-vælger til narrativ-indsættelse (billeder-i-narrativer 2026-07-05, Slice C2). Viser
  // DENNE subjekts allerede indlæste egne uploadede billeder (samme `media`-state som Materiale-
  // galleriet nedenfor allerede henter — intet nyt fetch-kald).
  function renderMediaPicker() {
    if (!mediaPickerOpen) return null;
    const brugbar = media.filter((m) => m.uploadStatus === 'klar' && m.mimeType?.startsWith('image/') === true && m.thumbUrl);
    return (
      <div onClick={() => setMediaPickerOpen(false)} style={overlay(96)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 460, maxWidth: '100%', maxHeight: '70vh', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '16px 18px 12px', fontFamily: T.serif, fontSize: 19, fontWeight: 600 }}>Indsæt billede</div>
          <div data-scroll style={{ flex: 1, overflowY: 'auto', padding: '0 14px 16px', display: 'flex', flexWrap: 'wrap', gap: 10 }}>
            {brugbar.map((m) => (
              <div key={m.id} onClick={() => { insertNarrativToken(makeToken('media', Number(m.id), m.titel ?? '')); setMediaPickerOpen(false); }}
                style={{ width: 100, cursor: 'pointer' }}>
                <img src={m.thumbUrl!} style={{ width: 100, height: 100, objectFit: 'cover', borderRadius: 8, background: T.beige, display: 'block' }} />
                {m.titel && <div style={{ fontSize: 10, color: T.muted, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{m.titel}</div>}
              </div>
            ))}
            {!brugbar.length && <div style={{ padding: '18px 4px', fontSize: 12.5, color: T.muted3 }}>Ingen billeder uploadet endnu.</div>}
          </div>
        </div>
      </div>
    );
  }

  function renderSammeSomConfirm() {
    if (!ssConfirm) return null;
    const sid = recordId!;
    const redigeretNavn = persons.find((p) => p.id === sid)?.navn ?? sid;
    const kanonisk = ssConfirm.kanoniskId === sid ? { id: sid, navn: redigeretNavn } : { id: ssConfirm.personId, navn: ssConfirm.navn };
    const alias = ssConfirm.kanoniskId === sid ? { id: ssConfirm.personId, navn: ssConfirm.navn } : { id: sid, navn: redigeretNavn };
    // Rå-db til rådgivende pre-flight (rekonstrueret fra redaktionsmodellen; kun personer + forældre-kanter bruges).
    const rawDb = {
      persons: model?.persons ?? [],
      unions: [],
      parentChild: Object.entries(model?.indexes.parentsByChild ?? {}).flatMap(
        ([child, parents]) => parents.map((parent) => ({ child, parent, union: '' })),
      ),
    };
    const preview = previewSammeSom(rawDb, [], { alias: alias.id, canonical: kanonisk.id });
    return (
      <div onClick={() => setSsConfirm(null)} style={overlay(96)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 420, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: 20 }}>
          <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, marginBottom: 14 }}>Samme person</div>
          <div style={{ fontFamily: T.mono, fontSize: 9, color: T.gold, marginBottom: 3 }}>KANONISK (beholdes)</div>
          <div style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, marginBottom: 10 }}>{kanonisk.navn}</div>
          <div style={{ fontFamily: T.mono, fontSize: 9, color: T.gold, marginBottom: 3 }}>FOLDES IND I OVENSTÅENDE</div>
          <div style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, marginBottom: 12 }}>{alias.navn}</div>
          <div onClick={() => setSsConfirm({ ...ssConfirm, kanoniskId: ssConfirm.kanoniskId === sid ? ssConfirm.personId : sid })}
            style={{ fontFamily: T.mono, fontSize: 11, color: T.bordeaux, cursor: 'pointer', marginBottom: 12 }}>⇅ Byt retning</div>
          {!preview.folder ? (
            <div style={{ fontSize: 11.5, color: T.bordeaux, marginBottom: 12, lineHeight: 1.4 }}>
              ⚠ Foldes ikke endnu — {preview.grund}. Linket oprettes, men personerne vises separat til konflikten er løst. (redaktionel projektion — offentlig visning kan afvige)
            </div>
          ) : null}
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <div onClick={() => setSsConfirm(null)} style={{ padding: '9px 16px', borderRadius: 9, background: T.beige, cursor: 'pointer', fontSize: 13, fontWeight: 600 }}>Annullér</div>
            <div onClick={() => { run({ art: 'sammeSom', subjektType: 'person', subjektId: sid, payload: { aliasId: alias.id, objektId: kanonisk.id } }, 'Marker som samme person'); setSsConfirm(null); }}
              style={{ padding: '9px 16px', borderRadius: 9, background: T.bordeaux, color: '#fff', cursor: 'pointer', fontSize: 13, fontWeight: 600 }}>Gem</div>
          </div>
        </div>
      </div>
    );
  }

  function renderFlytBarnPicker() {
    if (!flytBarn) return null;
    const pid = recordId!;
    const andre = (familie?.somPartner ?? []).filter((u) => u.familyId !== flytBarn.fraFamilyId);
    const onVael = (tilFamilyId: string) => {
      run({ art: 'flytBarn', subjektType: 'person', subjektId: pid,
        familyId: flytBarn.fraFamilyId, tilFamilyId, personId: flytBarn.personId, rolle: flytBarn.rolle }, 'Flyt barn');
      setFlytBarn(null);
    };
    return (
      <div onClick={() => setFlytBarn(null)} style={overlay(96)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 420, maxWidth: '100%', maxHeight: '70vh', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '16px 18px 12px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, marginBottom: 4 }}>Flyt {flytBarn.navn} til…</div>
            <div style={{ fontSize: 11.5, color: T.muted2 }}>Kun personens egne andre forhold — ikke en fri søgning.</div>
          </div>
          <div data-scroll style={{ flex: 1, overflowY: 'auto', padding: '0 10px 12px' }}>
            {andre.map((u) => (
              <div key={u.familyId} onClick={() => onVael(u.familyId)} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 9px', borderRadius: 9, cursor: 'pointer' }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600, lineHeight: 1.05 }}>{u.partnere.map((p) => p.navn).join(' & ') || '(ukendt partner)'}</div>
                  <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2 }}>{u.type}</div>
                </div>
              </div>
            ))}
            {!andre.length && <div style={{ padding: '18px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>Personen har ingen andre registrerede forhold.</div>}
          </div>
        </div>
      </div>
    );
  }

  function renderGenericEditor() {
    const ent = ENTITIES.find((e) => e.key === entity);
    const db = ENTITY_DB[entity] ?? { type: entity, felt: 'navn' };
    if (!curRecord) return <div style={{ padding: 30, color: T.muted3 }}>{records.length ? 'Vælg en post.' : 'Ingen liste-kilde for denne entitet endnu.'}</div>;
    return (
      <div style={{ padding: '24px 30px 60px', maxWidth: 760 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
          <span style={{ width: 54, height: 54, borderRadius: 12, background: '#f8ecef', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, color: T.bordeaux }}>{ent?.icon}</span>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: T.muted2 }}>{ent?.label}</div>
            <div style={{ fontFamily: T.serif, fontSize: 28, fontWeight: 600, lineHeight: 1.05, marginTop: 2 }}>{curRecord.label}</div>
          </div>
        </div>
        {showAnno && (
          <div style={{ marginTop: 16, ...annoBox, fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>
            Generiske entiteter har endnu ingen direkte skrive-RPC. Ændringer sendes som <b>forslag til staging</b> (red_suggest) og afventer redaktionel godkendelse. Dedikerede red_*-RPC'er er en follow-up.
          </div>
        )}
        <div style={{ marginTop: 18 }}>
          <label style={{ display: 'block', fontSize: 11, fontWeight: 600, color: T.muted, marginBottom: 5 }}>Primær værdi · {db.felt}</label>
          <input value={sc('gen:' + entity + ':' + curRecord.id, curRecord.label)} onChange={(e) => setSc('gen:' + entity + ':' + curRecord.id, e.target.value)} style={{ ...inp, background: '#fff' }} />
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <div onClick={() => run({ art: 'forslag', subjektType: db.type, subjektId: curRecord.id, felt: db.felt, vaerdi: sc('gen:' + entity + ':' + curRecord.id, curRecord.label) }, 'Forslag')} style={{ ...btnGreen, background: T.bordeaux }}>Foreslå ændring</div>
          </div>
        </div>
        {/* Objekt-foto (Slice 0h): kun estate/arms har et materiale-galleri — øvrige generiske
            entiteter (kilder, organisationer, …) har endnu intet naturligt sted at hænge det op. */}
        {HAR_OBJEKT_MATERIALE.has(entity)
          ? renderMateriale({ subjektType: db.type, subjektId: curRecord.id, uploadTarget: { objektType: db.type, objektId: curRecord.id } })
          : null}
      </div>
    );
  }

  // ---- Modaler ----
  function renderLoginModal() {
    if (!login.open) return null;
    return (
      <div onClick={() => setLogin((l) => ({ ...l, open: false }))} style={overlay(95)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 380, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '22px 24px 20px' }}>
          <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>Redaktør-login</div>
          <div style={{ fontSize: 12, color: T.muted, marginTop: 3, marginBottom: 15 }}>Supabase Auth · adgang og skriverettigheder afgøres af din rolle.</div>
          <label style={lbl}>E-mail</label>
          <input value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} placeholder="redaktion@adelsaarbog.dk" style={{ ...inp, background: '#fff' }} />
          <label style={{ ...lbl, marginTop: 11 }}>Adgangskode</label>
          <input value={login.pw} type="password" onChange={(e) => setLogin((l) => ({ ...l, pw: e.target.value }))} style={{ ...inp, background: '#fff' }} />
          {login.err && <div style={{ fontSize: 11.5, color: T.red, marginTop: 9 }}>{login.err}</div>}
          <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end' }}>
            <div onClick={() => setLogin((l) => ({ ...l, open: false }))} style={btnGhost}>Annullér</div>
            <div onClick={doLogin} style={{ ...btnGreen, background: T.bordeaux }}>{login.busy ? 'Logger ind…' : 'Log ind'}</div>
          </div>
        </div>
      </div>
    );
  }

  function renderConfirmModal() {
    if (!confirmDel) return null;
    const pv = confirmDel.preview;
    return (
      <div style={overlay(90)}>
        <div style={{ width: 460, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', overflow: 'hidden' }}>
          <div style={{ padding: '20px 22px 16px', display: 'flex', alignItems: 'flex-start', gap: 14 }}>
            <span style={{ width: 42, height: 42, borderRadius: '50%', background: '#f2dede', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 19, color: T.red }}>⚠</span>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, lineHeight: 1.1 }}>Slet person?</div>
              <div style={{ fontSize: 13, lineHeight: 1.5, color: '#3d382f', marginTop: 5 }}>Du er ved at slette <b>{confirmDel.label}</b>. Posten fjernes permanent fra basen.</div>
            </div>
          </div>
          <div style={{ margin: '0 22px', background: '#f8ecef', border: '1px solid rgba(138,43,43,.25)', borderRadius: 11, padding: '13px 15px' }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.red, marginBottom: 6 }}>Relationer der brydes</div>
            <div style={{ fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>{pv ? `${pv.antalRelationer} relation(er) og ${pv.antalFacts} fakta knyttet til personen.` : 'Henter relations-overblik…'}</div>
          </div>
          <div style={{ padding: '16px 22px 4px' }}>
            <label onClick={() => setConfirmDel((c) => c && { ...c, ack: !c.ack })} style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <span style={{ width: 18, height: 18, borderRadius: 5, border: `1.5px solid ${confirmDel.ack ? T.red : 'rgba(34,31,26,.3)'}`, background: confirmDel.ack ? T.red : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, color: '#fff' }}>{confirmDel.ack ? '✓' : ''}</span>
              <span style={{ fontSize: 12, color: '#3d382f' }}>Jeg forstår at relationerne brydes</span>
            </label>
          </div>
          <div style={{ display: 'flex', gap: 9, padding: '16px 22px 20px', justifyContent: 'flex-end' }}>
            <div onClick={() => setConfirmDel(null)} style={btnGhost}>Annullér</div>
            <div onClick={performDelete} style={{ fontSize: 12.5, fontWeight: 600, color: confirmDel.ack ? '#fff' : '#b79c9c', background: confirmDel.ack ? T.red : '#e7d9d9', borderRadius: 9, padding: '10px 16px', cursor: confirmDel.ack ? 'pointer' : 'not-allowed' }}>Slet endeligt</div>
          </div>
        </div>
      </div>
    );
  }

  function renderWriteModal() {
    if (!writeView) return null;
    const w = writeView;
    return (
      <div onClick={() => setWriteView(null)} style={overlay(92)}>
        <div onClick={(e) => e.stopPropagation()} style={{ width: 600, maxWidth: '100%', maxHeight: '80vh', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '18px 22px 14px', borderBottom: '1px solid rgba(34,31,26,.1)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
              <span style={{ width: 9, height: 9, borderRadius: '50%', background: w.error ? '#ff6b6b' : (w.dryRun ? T.goldLight : '#1f8a5b') }} />
              <span style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{w.title}</span>
            </div>
            <div style={{ fontSize: 12, color: T.muted, marginTop: 5 }}>{w.direkte ? 'Direkte til evidens-/data-tabellerne (red_*-RPC).' : 'Forslag i staging (red_suggest) — afventer redaktionel godkendelse.'}</div>
          </div>
          <div data-scroll style={{ flex: 1, overflowY: 'auto', padding: '14px 22px' }}>
            {w.error && <div style={{ fontFamily: T.mono, fontSize: 12, lineHeight: 1.5, color: T.red, whiteSpace: 'pre-wrap' }}>{w.error}</div>}
            {w.lines.map((ln, i) => (
              <div key={i} style={{ background: T.dark, borderRadius: 9, padding: '11px 13px', marginBottom: 9 }}>
                <pre style={{ margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: 1.5, color: '#e7e0d2', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{ln}</pre>
              </div>
            ))}
            {w.done && <div style={{ fontSize: 12.5, color: T.green, fontWeight: 600 }}>✓ Udført.</div>}
          </div>
          <div style={{ padding: '14px 22px', borderTop: '1px solid rgba(34,31,26,.1)', display: 'flex', justifyContent: 'flex-end' }}>
            <div onClick={() => setWriteView(null)} style={{ ...btnGreen, background: T.bordeaux }}>Luk</div>
          </div>
        </div>
      </div>
    );
  }
}

// --- delte små stilarter ---
const inp: React.CSSProperties = { width: '100%', fontSize: 13, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none' };
const lbl: React.CSSProperties = { display: 'block', fontSize: 11, fontWeight: 600, color: '#6f675b', marginBottom: 4 };
const btnGreen: React.CSSProperties = { fontSize: 12, fontWeight: 600, color: '#fbf8f1', background: '#1f5b3a', borderRadius: 7, padding: '8px 13px', cursor: 'pointer' };
const btnGhost: React.CSSProperties = { fontSize: 12, fontWeight: 600, color: '#6f675b', padding: '8px 10px', cursor: 'pointer' };
const iconBtn: React.CSSProperties = { display: 'flex', alignItems: 'center', justifyContent: 'center', width: 26, height: 26, borderRadius: 6, border: '1px solid rgba(34,31,26,.16)', color: '#6f675b', fontSize: 12, cursor: 'pointer' };
const overlay = (z: number): React.CSSProperties => ({ position: 'fixed', inset: 0, background: 'rgba(34,27,22,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: z, padding: 24 });
const sectionHeader = (mt: number): React.CSSProperties => ({ marginTop: mt, fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold, marginBottom: 10 });
const annoBox: React.CSSProperties = { border: '1px dashed rgba(136,26,51,.4)', borderRadius: 11, padding: '13px 15px', background: '#f8ecef' };

// "Forældre ukendt"-markering (docs/reviews/25): redaktør-kontrol til at markere at KILDEN ikke
// angiver en forbindelse opad. Skriver via red_upsert_fakta (grad) / red_tilbagetraek_fakta (fjern —
// retract af konklusionen, review 26 HIGH 2) gennem det almindelige `run`/submitChange-flow (dry-run/
// LIVE respekteres). Selvstændig fetch af nuværende markering (undgår at tråde state gennem editoren).
function ForaeldreUkendtControl({ personId, run }: { personId: string; run: (c: Change, label: string) => void }) {
  const [mk, setMk] = useState<ForaeldreUkendtMarkering | null | undefined>(undefined);
  const [grade, setGrade] = useState<string>(GRADE_FORAELDER_UKENDT);
  const [kilde, setKilde] = useState('');
  const [reloadKey, setReloadKey] = useState(0);
  useEffect(() => {
    let alive = true;
    setMk(undefined);
    fetchForaeldreUkendtMarkering(personId)
      .then((m) => { if (!alive) return; setMk(m); if (m) { setGrade(m.grade || GRADE_FORAELDER_UKENDT); setKilde(m.kilde ?? ''); } })
      .catch(() => { if (alive) setMk(null); });
    return () => { alive = false; };
  }, [personId, reloadKey]);
  const refetchSoon = () => setTimeout(() => setReloadKey((k) => k + 1), 700);
  const marker = () => {
    run({ art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: personId, vaerdi: grade, kildeFritekst: kilde.trim() || undefined }, 'Forældre ukendt');
    refetchSoon();
  };
  const fjern = () => {
    if (!mk) return;
    run({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: personId, factId: String(mk.factId) }, 'Fjern forældre-ukendt');
    refetchSoon();
  };
  const gradeLabel = (g: string) => g === GRADE_FORAELDER_UKENDT ? 'Forælder findes, men er ukendt for os' : 'Bogen forbinder ikke personen opad';
  return (
    <div style={{ marginTop: 14, border: `1px solid ${mk ? 'rgba(136,26,51,.25)' : 'rgba(34,31,26,.14)'}`, borderRadius: 11, padding: '12px 14px', background: mk ? '#faf1dc' : T.panel }}>
      <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: T.gold, marginBottom: 8 }}>
        Forældre ukendt — kilden forbinder ikke opad
      </div>
      {mk === undefined ? (
        <div style={{ fontSize: 12, color: T.muted }}>Henter markering…</div>
      ) : (
        <>
          {mk && (
            <div style={{ fontSize: 12.5, color: '#3d382f', marginBottom: 9, lineHeight: 1.45 }}>
              Markeret: <b>{gradeLabel(mk.grade)}</b>{mk.kilde ? <> · kilde: <i>{mk.kilde}</i></> : ''}.
              Personen viser en kandidat-kolonne (forrige slægtled) i stamtræet.
            </div>
          )}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>
            <select value={grade} onChange={(e) => setGrade(e.target.value)} style={{ fontFamily: T.sans, fontSize: 12, padding: '6px 8px', borderRadius: 7, border: '1px solid rgba(34,31,26,.18)', background: T.paper, color: T.ink }}>
              <option value={GRADE_FORAELDER_UKENDT}>Forælder ukendt (findes, men ukendt)</option>
              <option value={GRADE_INGEN_FORBINDELSE}>Ingen forbindelse angivet</option>
            </select>
            <input value={kilde} onChange={(e) => setKilde(e.target.value)} placeholder="Kilde (fx DAA 1939 s.97)" style={{ flex: 1, minWidth: 160, fontFamily: T.sans, fontSize: 12, padding: '6px 9px', borderRadius: 7, border: '1px solid rgba(34,31,26,.18)', background: T.paper, color: T.ink }} />
            <div onClick={marker} style={{ fontSize: 12, fontWeight: 600, color: '#fff', background: T.bordeaux, borderRadius: 7, padding: '7px 13px', cursor: 'pointer' }}>{mk ? 'Opdatér' : 'Markér'}</div>
            {mk && <div onClick={fjern} style={{ fontSize: 12, fontWeight: 600, color: T.red, border: '1px solid rgba(138,43,43,.3)', borderRadius: 7, padding: '6px 12px', cursor: 'pointer' }}>Fjern</div>}
          </div>
        </>
      )}
    </div>
  );
}

// Forældrefamilie-slot (Problem 2): konkurrerende forældre-påstande for DENNE person. Renderes kun
// når der findes påstande (typisk efter en tværudgave-konflikt); mirrorer fact-card-oplysnings-listen
// (kilde-badge + valgt-markering + "vælg denne"). Adjudikation = red_vaelg_foraeldre via run().
function ForaeldrePaastandeControl({ personId, run, sammeSom }: { personId: string; run: (c: Change, label: string) => void; sammeSom: SammeSomLink[] }) {
  const [slot, setSlot] = useState<ForaeldreSlot | null | undefined>(undefined);
  const [egen, setEgen] = useState<BarnFamilie | null>(null); // personens EGEN fødselsfamilie + udgave
  const [rivaler, setRivaler] = useState<{ fraId: string; fam: BarnFamilie }[]>([]);
  const [konfidens, setKonfidens] = useState('sikker');
  const [reloadKey, setReloadKey] = useState(0);
  useEffect(() => {
    let alive = true; setSlot(undefined); setRivaler([]); setEgen(null);
    fetchForaeldreSlot(personId).then((s) => { if (alive) setSlot(s); }).catch(() => { if (alive) setSlot(null); });
    fetchBarnFamilie(personId).then((f) => { if (alive) setEgen(f); }).catch(() => {});
    // §6 trin (a): hent samme_som-linkede personers fødselsfamilier (rival-udgavers forældre).
    // Ekskludér reflexive self-links (samme_som bruges også til within-udgave-dubletter).
    Promise.all(sammeSom.filter((l) => l.modpartId !== personId).map((l) => fetchBarnFamilie(l.modpartId).then((f) => f ? { fraId: l.modpartId, fam: f } : null)))
      .then((rs) => { if (alive) setRivaler(rs.filter((r): r is { fraId: string; fam: BarnFamilie } => r != null)); }).catch(() => {});
    return () => { alive = false; };
  }, [personId, reloadKey, sammeSom]);
  const refetchSoon = () => setTimeout(() => setReloadKey((k) => k + 1), 700);
  const vaelg = (assertionId: number) => {
    run({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: personId, payload: { assertionId, konfidens } }, 'Vælg forældrefamilie');
    refetchSoon();
  };
  const importer = (fam: BarnFamilie) => {
    run({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: personId,
      payload: { barnId: personId, familyId: fam.familyId, sourceId: fam.sourceId ?? undefined, citat: fam.udgave ? `Importeret fra ${fam.udgave} (samme_som)` : undefined } }, 'Importér forældre-påstand');
    refetchSoon();
  };
  const kendteFams = new Set((slot?.paastande ?? []).map((p) => p.familyId));
  // Kun ægte tværudgave-rivaler: anden familie end personens egen, ikke allerede på slottet, OG en
  // anden KILDE (samme_som dækker også within-udgave-dubletter → ellers evidens-teater). Kræver at
  // personens egen fødselsfamilie er kendt (ellers kan tværudgave ikke verificeres → intet tilbydes).
  const importable = (egen && egen.sourceId != null) ? rivaler.filter((r) =>
    r.fam.familyId !== egen.familyId && !kendteFams.has(r.fam.familyId) && r.fam.sourceId != null && r.fam.sourceId !== egen.sourceId) : [];
  if ((!slot || slot.paastande.length === 0) && importable.length === 0) return null; // intet at vise
  const omstridt = slot?.status === 'omstridt' || (slot?.paastande.length ?? 0) > 1;
  return (
    <div style={{ marginTop: 14, border: `1px solid ${omstridt ? 'rgba(136,26,51,.35)' : 'rgba(34,31,26,.14)'}`, borderRadius: 11, padding: '12px 14px', background: omstridt ? '#faf1dc' : T.panel }}>
      <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: omstridt ? T.bordeaux : T.gold, marginBottom: 8 }}>
        Forældrefamilie{omstridt ? ' · konkurrerende påstande' : ''}
      </div>
      {(slot?.paastande ?? []).map((pp) => (
        <div key={pp.assertionId} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 0', borderTop: '1px dashed rgba(34,31,26,.1)' }}>
          <span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted, background: T.beige, borderRadius: 5, padding: '3px 7px', whiteSpace: 'nowrap' }}>{pp.udgave ?? 'redaktionel'}</span>
          <div style={{ flex: 1, fontSize: 12.5, color: '#3d382f' }}>
            {pp.foraeldre.map((f) => f.navn).join(' & ') || '(ukendt familie)'}
            {pp.side ? <span style={{ color: T.muted2 }}> · {pp.side}</span> : null}
            {pp.valgt ? <span style={{ color: T.bordeaux, fontWeight: 600 }}> · ✓ valgt</span> : null}
          </div>
          {pp.valgt ? null : (
            <div onClick={() => vaelg(pp.assertionId)} style={{ fontSize: 12, fontWeight: 600, color: '#fff', background: T.bordeaux, borderRadius: 7, padding: '6px 12px', cursor: 'pointer', whiteSpace: 'nowrap' }}>Vælg denne</div>
          )}
        </div>
      ))}
      {/* §6 trin (a): importér en samme_som-linket persons (anden udgaves) forældre som rival-påstand */}
      {importable.map((r) => (
        <div key={r.fraId} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 0', borderTop: '1px dashed rgba(34,31,26,.1)' }}>
          <span style={{ fontFamily: T.mono, fontSize: 9, color: T.gold, background: T.beige, borderRadius: 5, padding: '3px 7px', whiteSpace: 'nowrap' }}>{r.fam.udgave ?? 'anden udgave'}</span>
          <div style={{ flex: 1, fontSize: 12.5, color: T.muted }}>{r.fam.foraeldre.map((f) => f.navn).join(' & ') || '(ukendt familie)'}</div>
          <div onClick={() => importer(r.fam)} style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, border: '1px solid rgba(136,26,51,.3)', borderRadius: 7, padding: '6px 12px', cursor: 'pointer', whiteSpace: 'nowrap' }}>Importér som påstand</div>
        </div>
      ))}
      {omstridt && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 9 }}>
          <span style={{ fontSize: 11.5, color: T.muted }}>Tillid ved valg:</span>
          <select value={konfidens} onChange={(e) => setKonfidens(e.target.value)} style={{ fontFamily: T.sans, fontSize: 12, padding: '5px 8px', borderRadius: 7, border: '1px solid rgba(34,31,26,.18)', background: T.paper, color: T.ink }}>
            {['sikker', 'sandsynlig', 'formodet', 'omstridt'].map((k) => <option key={k} value={k}>{k}</option>)}
          </select>
        </div>
      )}
    </div>
  );
}

// Dashboard-worklist (Problem 2 §6): personer m. konkurrerende forældre-påstande (red_foraeldre_konflikt).
// Klik → åbn personen i editoren, hvor ForaeldrePaastandeControl adjudicerer.
function ForaeldreKonflikterListe({ onOpen }: { onOpen: (personId: string) => void }) {
  const [rows, setRows] = useState<ForaeldreKonflikt[] | undefined>(undefined);
  const [fejl, setFejl] = useState<string | null>(null); // review 30/Codex #2: fejl må ikke maskeres som "ingen konflikter"
  useEffect(() => {
    let alive = true;
    fetchForaeldreKonflikter().then((r) => { if (alive) setRows(r); }).catch((e) => { if (alive) setFejl(String((e as { message?: string })?.message ?? e)); });
    return () => { alive = false; };
  }, []);
  return (
    <div style={{ padding: '18px 22px', maxWidth: 720 }}>
      <div style={{ fontFamily: T.serif, fontSize: 22, color: T.ink, marginBottom: 6 }}>Forældre-konflikter</div>
      <div style={{ fontSize: 12.5, color: T.muted, marginBottom: 16, lineHeight: 1.5 }}>
        Personer hvor to udgaver påstår forskellige forældrefamilier. Åbn personen for at se påstandene side om side og vælge den kanoniske (bevarer begge, kildebundet).
      </div>
      {fejl ? (
        <div style={{ fontSize: 12.5, color: T.red, background: '#faf1dc', border: '1px solid rgba(136,26,51,.3)', borderRadius: 8, padding: '10px 13px' }}>Kunne ikke hente konflikt-listen: {fejl}. (Konflikter kan ikke vises — ikke nødvendigvis fordi der ingen er.)</div>
      ) : rows === undefined ? (
        <div style={{ fontSize: 12.5, color: T.muted }}>Henter…</div>
      ) : rows.length === 0 ? (
        <div style={{ fontSize: 12.5, color: T.muted }}>Ingen forældre-konflikter — alle personer har én afklaret forældrefamilie.</div>
      ) : (
        rows.map((r) => (
          <div key={r.factId} onClick={() => onOpen(String(r.personId))}
            style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 13px', marginBottom: 8, cursor: 'pointer',
              border: '1px solid rgba(136,26,51,.25)', borderRadius: 10, background: '#faf1dc' }}>
            <span style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux }}>{r.status ?? 'omstridt'}</span>
            <div style={{ flex: 1, fontSize: 13.5, color: '#3d382f', fontWeight: 600 }}>{r.navn ?? `Person ${r.personId}`}</div>
            <span style={{ fontSize: 11.5, color: T.muted }}>{r.antalFamilier} familier · {r.antalPaastande} påstande</span>
            <span style={{ color: T.bordeaux, fontSize: 15 }}>→</span>
          </div>
        ))
      )}
    </div>
  );
}
