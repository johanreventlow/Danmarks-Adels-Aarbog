// Publikums-følgesvend (web) — port af design/project/Reventlow-web-v2.dc.html.
// Header-nav · venstre person-liste/søg · center-visning. To visninger bygget: Stamtræ
// (variant A, fokus-centreret) og Slægtskab ("Er vi i familie?", med multi-linje + konfidens
// + korroboration fra den porterede finder). Søg/Godser/Våben/Om følger.
import { useEffect, useMemo, useState } from 'react';
import { loadModel } from './data/model';
import { computeRelationship, type RelationResult } from './data/relationship';
import type { Konfidens, Model, ModelPerson } from './data/types';

const T = {
  pageBg: '#ece6da', paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', bordeaux: '#881A33', gold: '#b9a06a', goldLight: '#e7c98f',
  muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c', cream: '#cabfa9',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};
const NAV: [string, string, boolean][] = [
  ['Stamtræ', 'tree', true], ['Slægtskab', 'relate', true],
  ['Søg', 'search', false], ['Godser', 'estates', false], ['Våben', 'arms', false], ['Om slægten', 'about', false],
];
const initials = (n: string) => n.split(' ').filter(Boolean).map((s) => s[0]).slice(0, 2).join('').toUpperCase();
const konfTekst = (k?: Konfidens) => (k === 'omstridt' ? 'omstridt' : k === 'formodet' ? 'formodet' : '');

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
  const [model, setModel] = useState<Model | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [mode, setMode] = useState('tree');
  const [focusId, setFocusId] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [relA, setRelA] = useState<string | null>(null);
  const [relB, setRelB] = useState<string | null>(null);
  const [relSlot, setRelSlot] = useState<'A' | 'B'>('A');

  useEffect(() => {
    loadModel().then((m) => {
      setModel(m);
      // Start på personen med flest børn (midt i træet).
      let best: string | null = null; let max = -1;
      for (const p of m.persons) { const n = m.indexes.childIdx[p.id]?.size ?? 0; if (n > max) { max = n; best = p.id; } }
      setFocusId(best ?? m.persons[0]?.id ?? null);
    }).catch((e) => setErr(describeErr(e)));
  }, []);

  const persons = model?.persons ?? [];
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const base = q ? persons.filter((p) => p.name.toLowerCase().includes(q)) : persons;
    return [...base].sort((a, b) => a.name.localeCompare(b.name, 'da')).slice(0, 400);
  }, [persons, query]);

  const rel = useMemo(() => (model && relA && relB ? computeRelationship(model, relA, relB) : null), [model, relA, relB]);

  const pickPerson = (id: string) => {
    if (mode === 'relate') {
      if (relSlot === 'A') { setRelA(id); setRelSlot('B'); } else { setRelB(id); setRelSlot('A'); }
    } else {
      setFocusId(id);
    }
  };

  if (err) return <div style={{ fontFamily: T.sans, padding: 40, color: T.bordeaux, whiteSpace: 'pre-wrap' }}>{err}</div>;

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.pageBg, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      {/* Header */}
      <div style={{ flex: 'none', height: 58, display: 'flex', alignItems: 'center', gap: 18, padding: '0 22px', background: T.paper, borderBottom: '1px solid rgba(34,31,26,.12)' }}>
        <span style={{ width: 32, height: 32, borderRadius: 8, background: T.bordeaux, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.paper }}>R</span>
        <div>
          <div style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, lineHeight: 1 }}>Slægten Reventlow</div>
          <div style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.12em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Danmarks Adels Aarbog · følgesvend</div>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', gap: 4 }}>
          {NAV.map(([label, m, on]) => (
            <div key={m} onClick={() => on && setMode(m)} title={on ? '' : 'Kommer'} style={{ padding: '7px 13px', borderRadius: 8, fontSize: 12.5, fontWeight: 600, cursor: on ? 'pointer' : 'default', background: mode === m ? T.bordeaux : 'transparent', color: mode === m ? T.paper : (on ? '#3d382f' : T.muted3) }}>{label}</div>
          ))}
        </div>
        <a href="#redaktion" style={{ fontSize: 11.5, fontWeight: 600, color: T.bordeaux, textDecoration: 'none', marginLeft: 6 }}>Redaktion ↗</a>
      </div>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* Venstre: søg + person-liste */}
        <div data-scroll style={{ flex: 'none', width: 280, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '14px 14px 10px', position: 'sticky', top: 0, background: T.panel, zIndex: 2 }}>
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={mode === 'relate' ? `Vælg person ${relSlot}…` : 'Søg navn…'} style={{ width: '100%', fontSize: 13, color: T.ink, background: T.paper, border: '1px solid rgba(34,31,26,.14)', borderRadius: 8, padding: '9px 11px', outline: 'none' }} />
            {!model && <div style={{ fontSize: 12, color: T.muted3, marginTop: 8 }}>Henter slægten…</div>}
          </div>
          <div style={{ padding: '2px 10px 14px' }}>
            {filtered.map((p) => {
              const sel = mode === 'relate' ? (p.id === relA || p.id === relB) : p.id === focusId;
              return (
                <div key={p.id} onClick={() => pickPerson(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 9px', borderRadius: 9, cursor: 'pointer', background: sel ? '#efe7d7' : 'transparent' }}>
                  <span style={{ width: 28, height: 28, borderRadius: '50%', background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 11, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(p.name)}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: T.serif, fontSize: 15, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                    <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1 }}>{p.years || '—'}{relA === p.id ? ' · A' : relB === p.id ? ' · B' : ''}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Center */}
        <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto' }}>
          {mode === 'tree' ? <TreeView model={model} focusId={focusId} onPick={setFocusId} />
            : mode === 'relate' ? <RelateView model={model} rel={rel} relA={relA} relB={relB} slot={relSlot} setSlot={setRelSlot} onPickStep={setFocusId} />
            : <Placeholder label={NAV.find((n) => n[1] === mode)?.[0] ?? ''} />}
        </div>
      </div>
    </div>
  );
}

function Placeholder({ label }: { label: string }) {
  return <div style={{ padding: 40, fontFamily: T.serif, fontSize: 22, color: T.muted }}>{label} — visningen porteres som næste skive.</div>;
}

// ---- Stamtræ (variant A) ----
function TreeView({ model, focusId, onPick }: { model: Model | null; focusId: string | null; onPick: (id: string) => void }) {
  if (!model || !focusId) return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  const f = model.byId[focusId];
  if (!f) return <div style={{ padding: 40, color: T.muted3 }}>Ukendt person.</div>;
  const parent = f.parentId ? model.byId[f.parentId] : null;
  const grand = parent?.parentId ? model.byId[parent.parentId] : null;
  const sibIds = f.parentId ? [...(model.indexes.childIdx[f.parentId] ?? new Set<string>())] : [focusId];
  const siblings = (sibIds.length ? sibIds : [focusId]).map((id) => model.byId[id]).filter(Boolean) as ModelPerson[];
  const spouses = (model.indexes.spousesBy[focusId] ?? []).map((s) => s.name).filter(Boolean);
  const children = [...(model.indexes.childIdx[focusId] ?? new Set<string>())].map((id) => model.byId[id]).filter(Boolean) as ModelPerson[];
  const childCount = (id: string) => model.indexes.childIdx[id]?.size ?? 0;

  return (
    <div style={{ padding: '30px 40px 50px' }}>
      <Kicker>Slægten Reventlow</Kicker>
      <H1>Stamtræ</H1>
      <div style={{ width: 42, height: 1.5, background: T.bordeaux, margin: '11px 0 18px' }} />
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
    </div>
  );
}

// ---- Slægtskab ("Er vi i familie?") ----
function RelateView({ model, rel, relA, relB, slot, setSlot, onPickStep }: {
  model: Model | null; rel: RelationResult | null; relA: string | null; relB: string | null;
  slot: 'A' | 'B'; setSlot: (s: 'A' | 'B') => void; onPickStep: (id: string) => void;
}) {
  const a = relA && model ? model.byId[relA] : null;
  const b = relB && model ? model.byId[relB] : null;
  const p0 = rel?.lines[0];
  const korrob = p0 && p0.uafhaengige >= 2 ? `Bekræftet ad ${p0.uafhaengige} uafhængige linjer`
    : (p0?.usikker && rel?.alternativSolidLinje) ? 'Bekræftet ad en anden, sikker linje' : '';
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <Kicker>Slægten Reventlow</Kicker>
      <H1>Er vi i familie?</H1>
      <div style={{ width: 42, height: 1.5, background: T.bordeaux, margin: '11px 0 6px' }} />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 20 }}>Klik et felt for at vælge slot, og vælg en person i listen til venstre.</div>
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
    </div>
  );
}

// ---- små byggeklodser ----
const Kicker = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.2em', textTransform: 'uppercase', color: T.gold, marginBottom: 6 }}>{children}</div>;
const H1 = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1 }}>{children}</div>;
const Label = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 12px' }}>{children}</div>;
const Stem = ({ h, mt = 0 }: { h: number; mt?: number }) => <div style={{ width: 1, height: h, background: 'rgba(34,31,26,.22)', marginTop: mt }} />;
const Avatar = ({ n, size }: { n: string; size: number }) => (
  <div style={{ width: size, height: size, borderRadius: '50%', background: '#f4ece0', border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: size * 0.4, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(n)}</div>
);

function describeErr(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  return /permission|row-level|JWT|PGRST|policy/i.test(m) ? m + '\n\nMangler måske anon-læseadgang — kør web/dev-rls.sql i Supabase.' : m;
}
