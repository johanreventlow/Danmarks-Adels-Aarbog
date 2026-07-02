// Redaktør-arbejdsbord (web) — port af design/project/Reventlow-redaktion.dc.html.
// Tre paneler: entitets-nav · record-liste · editor. Person-editoren redigerer evidens-laget
// (konklusion ← oplysninger) via de rigtige red_*-RPC'er; generiske entiteter foreslås til
// staging (red_suggest). Dry-run viser hvad der sendes; live skriver. Pixel-tro mod designet,
// men struktur er ren React (ikke prototypens DCLogic).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
import {
  fetchRedaktionPersoner, fetchPersonEvidence, fetchPersonNarrativ, fetchSletPreview,
  fetchEntityRecords, fetchPersonFamilie, fetchPersonRelationer, fetchSammeSomLinks, nudgeOrdinal, type RedPerson, type PersonEvidence,
  type FeltEvidens, type Oplysning, type SletPreview, type EntityRecord, type PersonFamilie, type PersonRelation, type SammeSomLink,
} from './data/redaktionRead';
import { previewSammeSom } from './data/sammeSomPreflight';
import { loadModel } from './data/model';
import type { Model } from './data/types';
import { submitChange, describeCall, oversaetFejl, type Change } from './data/redaktionWrite';
import { buildBrowse } from './data/browse';
import { initials } from './data/format';
import { NarrativRenderer } from './components/NarrativRenderer';

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
  { key: 'narrative', label: 'Narrativer', icon: '¶' },
  { key: 'office', label: 'Embeder & hverv', icon: '❦' },
  { key: 'estate', label: 'Godser', icon: '⌂' },
  { key: 'majorat', label: 'Majorater', icon: '⚜' },
  { key: 'org', label: 'Organisationer', icon: '◈' },
  { key: 'source', label: 'Kilder', icon: '§' },
  { key: 'arms', label: 'Våben', icon: '⛨' },
  { key: 'media', label: 'Medier', icon: '▦' },
];
const FELT_DEFS: [string, string][] = [['navn', 'Navn'], ['foedt', 'Født'], ['doed', 'Død'], ['titel', 'Titel/rang']];
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
  const [session, setSession] = useState<RedSession | null>(null);
  const [dryRun, setDryRun] = useState(true);
  const [showAnno, setShowAnno] = useState(true);
  const [entity, setEntity] = useState('person');
  const [recordId, setRecordId] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  // Person-browse (spejler Følgesvend §9.1/§9.2): sortér (navn/fødeår), alfabet-hop, linje-filter.
  const [browseSort, setBrowseSort] = useState<'navn' | 'aar'>('navn');
  const [activeLetter, setActiveLetter] = useState<string | null>(null);
  const [activeLinje, setActiveLinje] = useState<string | null>(null);

  const [persons, setPersons] = useState<RedPerson[]>([]);
  const [recCache, setRecCache] = useState<Record<string, EntityRecord[]>>({});
  const [evidence, setEvidence] = useState<PersonEvidence | null>(null);
  const [narrativ, setNarrativ] = useState<{ tekst: string; privat: boolean } | null>(null);
  const [model, setModel] = useState<Model | null>(null);
  const [familie, setFamilie] = useState<PersonFamilie | null>(null);
  const [relationer, setRelationer] = useState<PersonRelation[] | null>(null);
  const [sammeSom, setSammeSom] = useState<SammeSomLink[]>([]);
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

  // --- Initial load ---
  useEffect(() => { currentSession().then(setSession).catch(() => {}); }, []);
  // Redaktion collapser IKKE: navne slås op på de rå DB-poster (spec §8 — model holdes separat).
  useEffect(() => { loadModel({ collapse: false }).then(setModel).catch(() => {}); }, []);
  useEffect(() => {
    fetchRedaktionPersoner().then((ps) => {
      setPersons(ps);
      setRecordId((cur) => cur ?? ps[0]?.id ?? null);
    }).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
  }, []);

  // Records for aktuel entitet (person = live person-liste; øvrige = lazy fetch + cache).
  const records: EntityRecord[] = useMemo(() => {
    if (entity === 'person') {
      return persons.map((p) => ({ id: p.id, label: p.navn, sub: p.aar || '—', badge: initials(p.navn) }));
    }
    return recCache[entity] ?? [];
  }, [entity, persons, recCache]);

  // Lazy entitets-liste pr. type, kun ÉN gang (ref-dedup → effekten genkører ikke når cachen fyldes).
  const fetchedRef = useRef<Set<string>>(new Set());
  useEffect(() => {
    if (entity === 'person' || fetchedRef.current.has(entity)) return;
    fetchedRef.current.add(entity);
    fetchEntityRecords(entity).then((rs) => setRecCache((c) => ({ ...c, [entity]: rs }))).catch(() => fetchedRef.current.delete(entity));
  }, [entity]);

  // Evidens + narrativ når en person vælges.
  const loadPerson = useCallback((id: string) => {
    setEvidence(null); setNarrativ(null); setFamilie(null); setRelationer(null); setEditingAssert(null); setAddingFact(null);
    fetchPersonEvidence(id).then(setEvidence).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
    fetchPersonNarrativ(id).then((n) => setNarrativ(n ?? { tekst: '', privat: false })).catch(() => setNarrativ({ tekst: '', privat: false }));
    fetchPersonFamilie(id, model).then(setFamilie).catch(() => setFamilie({ somPartner: [], somBarn: [] }));
    fetchPersonRelationer(id).then(setRelationer).catch(() => setRelationer([]));
    fetchSammeSomLinks(id).then(setSammeSom).catch(() => setSammeSom([]));
  }, [model]);
  useEffect(() => {
    if (entity === 'person' && recordId) loadPerson(recordId);
  }, [entity, recordId, loadPerson]);

  // Sørg for at picker-entiteten (org/estate) er hentet når picker åbner.
  useEffect(() => {
    const ent = picker?.kind === 'hverv' ? 'org' : picker?.kind === 'gods' ? 'estate' : null;
    if (ent && !recCache[ent]) fetchEntityRecords(ent).then((rs) => setRecCache((c) => ({ ...c, [ent]: rs }))).catch(() => {});
  }, [picker, recCache]);

  const curPerson = persons.find((p) => p.id === recordId) ?? null;
  const curRecord = records.find((r) => r.id === recordId) ?? null;
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? records.filter((r) => (r.label + ' ' + r.sub).toLowerCase().includes(q)) : records;
  }, [records, query]);

  // Person-browse spejler Følgesvend: driv af den redaktør-authoritative `persons` (RedPerson har
  // allerede id/navn/born) + linje-metadata fra `model.lineage` (samme id-rum, collapse:false). Et
  // `name`-alias lader RedPerson opfylde buildBrowse's minimale BrowsePerson-shape.
  const linjeList = model?.lineage?.list ?? [];
  const browseInput = useMemo(() => persons.map((p) => ({ ...p, name: p.navn })), [persons]);
  const personBrowse = useMemo(
    () => buildBrowse(browseInput, query, browseSort, activeLetter, { linjeByPerson: model?.lineage?.byPerson, activeLinje }),
    [browseInput, query, browseSort, activeLetter, model, activeLinje],
  );

  // --- Skrivning ---
  const run = useCallback(async (change: Change, titel: string) => {
    try {
      const res = await submitChange(change, { dryRun, role });
      setWriteView({
        title: dryRun ? 'Dry-run · dette ville blive sendt' : (res.direkte ? 'Sendt til basen' : 'Forslag sendt til staging'),
        lines: [describeCall(res.call)], error: '', done: !dryRun, dryRun, direkte: res.direkte,
      });
      if (!dryRun && entity === 'person' && recordId) loadPerson(recordId);
    } catch (e) {
      setWriteView({ title: titel + ' fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false });
    }
  }, [dryRun, role, entity, recordId, loadPerson]);

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
        {renderList()}
        <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto', background: T.paper }}>
          {loadErr && <pre style={{ margin: 18, color: T.red, fontSize: 12, whiteSpace: 'pre-wrap' }}>{loadErr}</pre>}
          {entity === 'person' ? renderPersonEditor() : renderGenericEditor()}
        </div>
      </div>
      {renderLoginModal()}
      {renderConfirmModal()}
      {renderWriteModal()}
      {renderPicker()}
      {renderSammeSomConfirm()}
      {renderFlytBarnPicker()}
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
            <div key={e.key} onClick={() => { setEntity(e.key); setRecordId(null); setQuery(''); }} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 10px', borderRadius: 9, cursor: 'pointer', background: active ? T.paper : 'transparent', marginBottom: 2 }}>
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
    const isPerson = entity === 'person';
    const b = personBrowse;
    const personRow = (p: (typeof browseInput)[number]) => {
      const active = p.id === recordId;
      return (
        <div key={p.id} onClick={() => setRecordId(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 9px', borderRadius: 9, cursor: 'pointer', background: active ? '#efe7d7' : 'transparent' }}>
          <span style={{ width: 30, height: 30, borderRadius: '50%', background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(p.navn)}</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.serif, fontSize: 15.5, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.navn}</div>
            <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.aar || '—'}</div>
          </div>
          {p.privat && <span style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.06em', textTransform: 'uppercase', color: T.red, flex: 'none' }}>privat</span>}
        </div>
      );
    };
    return (
      <div data-scroll style={{ flex: 'none', width: 286, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '16px 16px 10px', position: 'sticky', top: 0, background: T.panel, zIndex: 2 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 9 }}>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{title}</div>
          </div>
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Søg…" style={{ width: '100%', fontSize: 13, color: T.ink, background: T.paper, border: '1px solid rgba(34,31,26,.14)', borderRadius: 8, padding: '9px 11px', outline: 'none' }} />
        </div>

        {isPerson ? (
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
                      {g.people.map(personRow)}
                    </div>
                  ))
                : b.flat.map(personRow)}
              {!b.flat.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{persons.length ? 'Ingen træffere' : 'Henter…'}</div>}
            </div>
          </>
        ) : (
          <div style={{ padding: '2px 10px 12px' }}>
            {filtered.map((r) => {
              const active = r.id === recordId;
              return (
                <div key={r.id} onClick={() => setRecordId(r.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 9px', borderRadius: 9, cursor: 'pointer', background: active ? '#efe7d7' : 'transparent' }}>
                  <span style={{ width: 30, height: 30, borderRadius: 7, background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux }}>{r.badge}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: T.serif, fontSize: 15.5, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.label}</div>
                    <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.sub}</div>
                  </div>
                </div>
              );
            })}
            {!filtered.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{query ? 'Ingen træffere' : 'Ingen liste-kilde endnu'}</div>}
          </div>
        )}
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

        {showAnno && (
          <div style={{ marginTop: 16, ...annoBox }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux, marginBottom: 4 }}>Sådan virker evidens-laget</div>
            <div style={{ fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>Hvert <b>faktum</b> vises som en <b>konklusion</b> (den blåstemplede værdi) ovenpå en eller flere <b>oplysninger</b>, hver med sin <b>kildeangivelse</b>. Redaktøren tilføjer oplysninger og vælger konklusionen; intet overskrives destruktivt.</div>
          </div>
        )}

        <div style={sectionHeader(22)}>Kerne-fakta · konklusion ← oplysninger</div>
        {!evidence && <div style={{ color: T.muted3, fontSize: 12.5 }}>Henter evidens…</div>}
        {evidence && FELT_DEFS.flatMap(([felt, label]) => (evidence.felter[felt] ?? [{ felt, faktatype: felt, factId: -1, konklusionAssertionId: null, oplysninger: [], uenig: false } as FeltEvidens]).map((f) => renderFactCard(p.id, label, f)))}

        {renderFamilieRelationer(p.id)}

        {/* Narrativ */}
        <div style={sectionHeader(24)}>Narrativ · biografi</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          <textarea value={narrativ?.tekst ?? ''} onChange={(e) => setNarrativ((n) => ({ tekst: e.target.value, privat: n?.privat ?? false }))} style={{ width: '100%', height: 104, fontSize: 13, lineHeight: 1.55, color: '#3d382f', background: '#fff', border: '1px solid rgba(34,31,26,.16)', borderRadius: 9, padding: '11px 12px', outline: 'none', resize: 'vertical' }} />
          {/* Passiv forhåndsvisning — viser hvordan [[type:id|tekst]]-links renderes for publikum,
              så redaktøren kan se om en redigering har brudt et eksisterende link. Ikke klikbar
              (undgår at navigere væk fra en igangværende redigering, jf. review 12 fund om
              korrumperbare tokens i den rå textarea). Fanger KUN knækket token-grammatik — et
              syntaktisk gyldigt token der peger på forkert id ser identisk ud med et korrekt. */}
          {!!narrativ?.tekst && (
            <div style={{ marginTop: 8, ...annoBox, fontSize: 11.5, lineHeight: 1.5, color: T.muted }}>
              <div style={{ fontSize: 9.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, marginBottom: 3 }}>Sådan vises det for besøgende</div>
              <NarrativRenderer tekst={narrativ.tekst} onPickPerson={() => {}} linkColor={T.bordeaux} inactiveColor={T.muted2} />
            </div>
          )}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 9 }}>
            <label style={{ fontSize: 11, color: T.muted, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
              <input type="checkbox" checked={!!narrativ?.privat} onChange={(e) => setNarrativ((n) => ({ tekst: n?.tekst ?? '', privat: e.target.checked }))} /> privat
            </label>
            <div style={{ flex: 1 }} />
            <div onClick={() => run({ art: 'narrativ', subjektType: 'person', subjektId: p.id, vaerdi: narrativ?.tekst ?? '', payload: { privat: !!narrativ?.privat } }, 'Narrativ')} style={{ fontSize: 12, fontWeight: 600, color: T.paper, background: T.green, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>Gem narrativ</div>
          </div>
        </div>
      </div>
    );
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
    const linkRow = (navn: string, meta: string, onRemove: () => void, extra?: React.ReactNode) => (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 10, padding: '8px 11px', marginBottom: 6 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600, lineHeight: 1.05 }}>{navn}</div>
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
                    <span style={{ fontSize: 12, fontWeight: 600, color: T.muted }}>{u.type || 'partnerskab'} · {u.partnere.map((p) => p.navn).join(', ') || '(ukendt partner)'}</span>
                    <span onClick={() => setPicker({ kind: 'barn', familyId: u.familyId })} style={{ fontSize: 11, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>+ Tilføj barn</span>
                  </div>
                  {u.boern.map((b, i) => {
                    const opOrdinal = nudgeOrdinal(u.boern, i, 'op');
                    const nedOrdinal = nudgeOrdinal(u.boern, i, 'ned');
                    const pil = (retning: '↑' | '↓', ordinal: number | null, titel: string) => (
                      <span key={retning} onClick={ordinal == null ? undefined : () => run({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle, ordinal }, titel)}
                        style={{ fontSize: 12, cursor: ordinal == null ? 'default' : 'pointer', color: ordinal == null ? T.muted3 : T.muted, padding: '0 2px' }}>{retning}</span>
                    );
                    return linkRow(b.navn, b.rolle, () => run({ art: 'sletFamilieLink', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle }, 'Fjern barn'),
                      <>
                        {pil('↑', opOrdinal, 'Flyt op')}
                        {pil('↓', nedOrdinal, 'Flyt ned')}
                        {konfidensChips(b.konfidens, (k) => run({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: pid, familyId: u.familyId, personId: b.personId, rolle: b.rolle, konfidens: k }, 'Konfidens'))}
                        <span onClick={() => setFlytBarn({ fraFamilyId: u.familyId, personId: b.personId, rolle: b.rolle, navn: b.navn })}
                          style={{ fontFamily: T.mono, fontSize: 9, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>flyt→</span>
                      </>);
                  })}
                </div>
              ))}
              {familie.somBarn.map((sb, i) => (
                <div key={sb.familyId + i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', fontSize: 12.5 }}>
                  <span style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.gold }}>Barn af</span>
                  <span style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600 }}>{sb.foraeldre.map((f) => f.navn).join(' & ') || '(ukendt)'}</span>
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
