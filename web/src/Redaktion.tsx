// Redaktør-arbejdsbord (web) — port af design/project/Reventlow-redaktion.dc.html.
// Tre paneler: entitets-nav · record-liste · editor. Person-editoren redigerer evidens-laget
// (konklusion ← oplysninger) via de rigtige red_*-RPC'er; generiske entiteter foreslås til
// staging (red_suggest). Dry-run viser hvad der sendes; live skriver. Pixel-tro mod designet,
// men struktur er ren React (ikke prototypens DCLogic).
import { useCallback, useEffect, useMemo, useState } from 'react';
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
import {
  fetchRedaktionPersoner, fetchPersonEvidence, fetchPersonNarrativ, fetchSletPreview,
  fetchEntityRecords, type RedPerson, type PersonEvidence, type FeltEvidens, type Oplysning,
  type SletPreview, type EntityRecord,
} from './data/redaktionRead';
import { submitChange, describeCall, oversaetFejl, type Change, type RpcCall } from './data/redaktionWrite';

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
const initials = (navn: string) => navn.split(' ').filter(Boolean).map((s) => s[0]).slice(0, 2).join('').toUpperCase();
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

  const [persons, setPersons] = useState<RedPerson[]>([]);
  const [recCache, setRecCache] = useState<Record<string, EntityRecord[]>>({});
  const [evidence, setEvidence] = useState<PersonEvidence | null>(null);
  const [narrativ, setNarrativ] = useState<{ tekst: string; privat: boolean } | null>(null);
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

  useEffect(() => {
    if (entity === 'person' || recCache[entity]) return;
    fetchEntityRecords(entity).then((rs) => setRecCache((c) => ({ ...c, [entity]: rs }))).catch(() => {});
  }, [entity, recCache]);

  // Evidens + narrativ når en person vælges.
  const loadPerson = useCallback((id: string) => {
    setEvidence(null); setNarrativ(null); setEditingAssert(null); setAddingFact(null);
    fetchPersonEvidence(id).then(setEvidence).catch((e) => setLoadErr(oversaetFejl(String(e?.message ?? e))));
    fetchPersonNarrativ(id).then((n) => setNarrativ(n ?? { tekst: '', privat: false })).catch(() => setNarrativ({ tekst: '', privat: false }));
  }, []);
  useEffect(() => {
    if (entity === 'person' && recordId) loadPerson(recordId);
  }, [entity, recordId, loadPerson]);

  const curPerson = persons.find((p) => p.id === recordId) ?? null;
  const curRecord = records.find((r) => r.id === recordId) ?? null;
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? records.filter((r) => (r.label + ' ' + r.sub).toLowerCase().includes(q)) : records;
  }, [records, query]);

  // --- Skrivning ---
  const run = useCallback(async (change: Change, titel: string) => {
    try {
      const res = await submitChange(change, { dryRun, role });
      const call: RpcCall = res.call;
      setWriteView({
        title: dryRun ? 'Dry-run · dette ville blive sendt' : (res.direkte ? 'Sendt til basen' : 'Forslag sendt til staging'),
        lines: [describeCall(call)], error: '', done: !dryRun, dryRun, direkte: res.direkte,
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
    </div>
  );

  // ---- Top bar ----
  function renderTopBar() {
    return (
      <div style={{ flex: 'none', height: 60, display: 'flex', alignItems: 'center', gap: 14, padding: '0 24px', background: T.paper, borderBottom: '1px solid rgba(34,31,26,.12)', zIndex: 30 }}>
        <span style={{ width: 34, height: 34, borderRadius: 8, background: T.bordeaux, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: T.paperText }}>R</span>
        <div>
          <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, lineHeight: 1, color: T.ink }}>Redaktion · Reventlow</div>
          <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Danmarks Adels Aarbog · evidens-base</div>
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
    return (
      <div data-scroll style={{ flex: 'none', width: 286, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '16px 16px 10px', position: 'sticky', top: 0, background: T.panel, zIndex: 2 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 9 }}>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{title}</div>
          </div>
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Søg…" style={{ width: '100%', fontSize: 13, color: T.ink, background: T.paper, border: '1px solid rgba(34,31,26,.14)', borderRadius: 8, padding: '9px 11px', outline: 'none' }} />
        </div>
        <div style={{ padding: '2px 10px 12px' }}>
          {filtered.map((r) => {
            const active = r.id === recordId;
            return (
              <div key={r.id} onClick={() => setRecordId(r.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 9px', borderRadius: 9, cursor: 'pointer', background: active ? '#efe7d7' : 'transparent' }}>
                <span style={{ width: 30, height: 30, borderRadius: entity === 'person' ? '50%' : 7, background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux }}>{r.badge}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.serif, fontSize: 15.5, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.label}</div>
                  <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.sub}</div>
                </div>
              </div>
            );
          })}
          {!filtered.length && <div style={{ padding: '22px 10px', textAlign: 'center', fontSize: 12.5, color: T.muted3 }}>{query ? 'Ingen træffere' : (entity === 'person' ? 'Henter…' : 'Ingen liste-kilde endnu')}</div>}
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
          <div style={{ marginTop: 16, border: '1px dashed rgba(136,26,51,.4)', borderRadius: 11, padding: '13px 15px', background: '#f8ecef' }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux, marginBottom: 4 }}>Sådan virker evidens-laget</div>
            <div style={{ fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>Hvert <b>faktum</b> vises som en <b>konklusion</b> (den blåstemplede værdi) ovenpå en eller flere <b>oplysninger</b>, hver med sin <b>kildeangivelse</b>. Redaktøren tilføjer oplysninger og vælger konklusionen; intet overskrives destruktivt.</div>
          </div>
        )}

        <div style={{ marginTop: 22, fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold, marginBottom: 10 }}>Kerne-fakta · konklusion ← oplysninger</div>
        {!evidence && <div style={{ color: T.muted3, fontSize: 12.5 }}>Henter evidens…</div>}
        {evidence && FELT_DEFS.flatMap(([felt, label]) => (evidence.felter[felt] ?? [{ felt, faktatype: felt, factId: -1, konklusionAssertionId: null, oplysninger: [], uenig: false } as FeltEvidens]).map((f) => renderFactCard(p.id, label, f)))}

        {/* Familie/relationer/sektioner — visning porteres senere; redigér via mobil i dag. */}
        <div style={{ marginTop: 26, fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold, marginBottom: 10 }}>Familie, relationer & sektioner</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '16px 16px', fontSize: 12.5, color: T.muted }}>
          Familie- og relations-redigering (partnere · børn · hverv · godser · våben) findes i mobil-redaktøren og porteres til web som næste skive.
        </div>

        {/* Narrativ */}
        <div style={{ marginTop: 24, fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold, marginBottom: 10 }}>Narrativ · biografi</div>
        <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
          <textarea value={narrativ ? sc('bio:' + p.id, narrativ.tekst) : ''} onChange={(e) => setSc('bio:' + p.id, e.target.value)} style={{ width: '100%', height: 104, fontSize: 13, lineHeight: 1.55, color: '#3d382f', background: '#fff', border: '1px solid rgba(34,31,26,.16)', borderRadius: 9, padding: '11px 12px', outline: 'none', resize: 'vertical' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 9 }}>
            <label style={{ fontSize: 11, color: T.muted, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
              <input type="checkbox" checked={!!narrativ?.privat} onChange={(e) => setNarrativ((n) => ({ tekst: n?.tekst ?? '', privat: e.target.checked }))} /> privat
            </label>
            <div style={{ flex: 1 }} />
            <div onClick={() => run({ art: 'narrativ', subjektType: 'person', subjektId: p.id, vaerdi: sc('bio:' + p.id, narrativ?.tekst ?? ''), payload: { privat: !!narrativ?.privat } }, 'Narrativ')} style={{ fontSize: 12, fontWeight: 600, color: T.paper, background: T.green, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>Gem narrativ</div>
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
  function renderGenericEditor() {
    const ent = ENTITIES.find((e) => e.key === entity);
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
          <div style={{ marginTop: 16, border: '1px dashed rgba(136,26,51,.4)', borderRadius: 11, padding: '13px 15px', background: '#f8ecef', fontSize: 12.5, lineHeight: 1.5, color: '#3d382f' }}>
            Generiske entiteter har endnu ingen direkte skrive-RPC. Ændringer sendes som <b>forslag til staging</b> (red_suggest) og afventer redaktionel godkendelse. Dedikerede red_*-RPC'er er en follow-up.
          </div>
        )}
        <div style={{ marginTop: 18 }}>
          <label style={{ display: 'block', fontSize: 11, fontWeight: 600, color: T.muted, marginBottom: 5 }}>Primær værdi (navn/titel)</label>
          <input value={sc('gen:' + entity + ':' + curRecord.id, curRecord.label)} onChange={(e) => setSc('gen:' + entity + ':' + curRecord.id, e.target.value)} style={{ ...inp, background: '#fff' }} />
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <div onClick={() => run({ art: 'forslag', subjektType: entity, subjektId: curRecord.id, felt: 'navn', vaerdi: sc('gen:' + entity + ':' + curRecord.id, curRecord.label) }, 'Forslag')} style={{ ...btnGreen, background: T.bordeaux }}>Foreslå ændring</div>
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
