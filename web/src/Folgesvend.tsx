// Publikums-følgesvend (web) — port af design/project/Reventlow-web-v2.dc.html.
// Header-nav · venstre person-liste/søg · center-visning. To visninger bygget: Stamtræ
// (variant A, fokus-centreret) og Slægtskab ("Er vi i familie?", med multi-linje + konfidens
// + korroboration fra den porterede finder). Søg/Godser/Våben/Om følger.
import { useEffect, useMemo, useState } from 'react';
import { childrenOf, loadModel } from './data/model';
import { initials, konfTekst } from './data/format';
import { computeRelationship, type RelationResult } from './data/relationship';
import { fetchArms, fetchAbout, fetchEstates, fetchEstateInfo, fetchEstateOwners, fetchPersonDetail, type ArmsItem, type EstateInfo, type EstateItem, type EstateOwner, type PersonDetailData } from './data/public';
import type { Model, ModelPerson } from './data/types';
import { NarrativRenderer } from './components/NarrativRenderer';
import { compareDanish, initialOf, sortLetters } from './lib/collation';

const T = {
  pageBg: '#ece6da', paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', bordeaux: '#881A33', gold: '#b9a06a', goldLight: '#e7c98f',
  muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c', cream: '#cabfa9',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};
// Nav matcher designets navDef — Søg er FJERNET (browsing bor nu i sidebaren: søgefelt +
// sortér + alfabet-hop + grupperet liste), så center-fladen har tree/estates/arms/about/relate.
const NAV: [string, string, boolean][] = [
  ['Stamtræ', 'tree', true], ['Godser', 'estates', true], ['Våben', 'arms', true],
  ['Om slægten', 'about', true], ['Slægtskab', 'relate', true],
];
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
  const [browseSort, setBrowseSort] = useState<'navn' | 'aar'>('navn'); // sidebar-sortering (§9.1)
  const [activeLetter, setActiveLetter] = useState<string | null>(null); // alfabet-filter (null = Alle)
  const [relA, setRelA] = useState<string | null>(null);
  const [relB, setRelB] = useState<string | null>(null);
  const [relSlot, setRelSlot] = useState<'A' | 'B'>('A');
  const [estates, setEstates] = useState<EstateItem[] | null>(null);
  const [arms, setArms] = useState<ArmsItem[] | null>(null);
  const [about, setAbout] = useState<string[] | null>(null);
  const [estateId, setEstateId] = useState<string | null>(null);
  const [estateOwners, setEstateOwners] = useState<EstateOwner[]>([]);
  const [estateInfo, setEstateInfo] = useState<EstateInfo | null>(null);
  const [detail, setDetail] = useState<PersonDetailData | null>(null);

  useEffect(() => {
    loadModel().then((m) => {
      setModel(m);
      setFocusId(startFokus(m));
    }).catch((e) => setErr(describeErr(e)));
  }, []);

  // Estates hentes eager (én gang) — bruges både af godser-visningen OG sidebar-statistikkens
  // "godser"-tæller. Én pagineret query; billig nok til mount.
  useEffect(() => { if (!estates) fetchEstates().then(setEstates).catch(() => setEstates([])); }, [estates]);
  useEffect(() => { if (mode === 'arms' && !arms) fetchArms().then(setArms).catch(() => setArms([])); }, [mode, arms]);
  useEffect(() => { if (mode === 'about' && !about) fetchAbout().then(setAbout).catch(() => setAbout([])); }, [mode, about]);
  useEffect(() => { if (estateId) fetchEstateOwners(estateId, model).then(setEstateOwners).catch(() => setEstateOwners([])); }, [estateId, model]);
  useEffect(() => { if (estateId) { setEstateInfo(null); fetchEstateInfo(estateId).then(setEstateInfo).catch(() => setEstateInfo({ narrativ: '', sted: '' })); } }, [estateId]);
  // Detalje (bio/embeder/godser) for fokus-personen — til højre-panelet.
  useEffect(() => { if (!focusId) { setDetail(null); return; } setDetail(null); fetchPersonDetail(focusId).then(setDetail).catch(() => setDetail({ bio: '', offices: [], estates: [] })); }, [focusId]);

  const persons = model?.persons ?? [];
  // Sidebar-browse (§9.1): filtrér på query, sortér (navn dansk / fødeår), og — kun ved
  // navne-sort uden søgning — gruppér på efternavns-initial med sticky bogstav-headers +
  // alfabet-hop. activeLetter filtrerer til ét bogstav (null = Alle).
  const browse = useMemo(() => {
    const q = query.trim().toLowerCase();
    const pool = q ? persons.filter((p) => p.name.toLowerCase().includes(q)) : persons;
    if (browseSort === 'aar') {
      const flat = [...pool].sort((a, b) => (a.born ?? 9999) - (b.born ?? 9999) || compareDanish(a.name, b.name));
      return { grouped: false as const, flat, letters: [] as string[], groups: [] as { letter: string; people: ModelPerson[] }[] };
    }
    const flat = [...pool].sort((a, b) => compareDanish(a.name, b.name));
    if (q) return { grouped: false as const, flat, letters: [] as string[], groups: [] };
    const byL: Record<string, ModelPerson[]> = {};
    flat.forEach((p) => { (byL[initialOf(p.name)] ??= []).push(p); });
    const letters = sortLetters(Object.keys(byL));
    const groups = letters
      .filter((l) => !activeLetter || l === activeLetter)
      .map((l) => ({ letter: l, people: byL[l] }));
    return { grouped: true as const, flat, letters, groups };
  }, [persons, query, browseSort, activeLetter]);

  const rel = useMemo(() => (model && relA && relB ? computeRelationship(model, relA, relB) : null), [model, relA, relB]);

  const pickPerson = (id: string) => {
    if (mode === 'relate') {
      if (relSlot === 'A') { setRelA(id); setRelSlot('B'); } else { setRelB(id); setRelSlot('A'); }
    } else {
      setFocusId(id);
    }
  };

  // Sidebar-liste-række (delt af grupperet + flad visning).
  const personRow = (p: ModelPerson) => {
    const sel = mode === 'relate' ? (p.id === relA || p.id === relB) : p.id === focusId;
    return (
      <div key={p.id} onClick={() => pickPerson(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '7px 9px', borderRadius: 9, cursor: 'pointer', background: sel ? '#efe7d7' : 'transparent' }}>
        <span style={{ width: 32, height: 32, borderRadius: '50%', background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(p.name)}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, lineHeight: 1.05, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
          <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1 }}>{p.years || '—'}{relA === p.id ? ' · A' : relB === p.id ? ' · B' : ''}</div>
        </div>
      </div>
    );
  };

  if (err) return <div style={{ fontFamily: T.sans, padding: 40, color: T.bordeaux, whiteSpace: 'pre-wrap' }}>{err}</div>;

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: T.pageBg, fontFamily: T.sans, color: T.ink, overflow: 'hidden' }}>
      {/* Header (port af design 66px: logo + titel · centreret nav · slægt-chip).
          Udskudt til Fase 2: redigér-knap (inline-redigering) + "din plads"-avatar (mig-koncept). */}
      <div style={{ flex: 'none', height: 66, display: 'flex', alignItems: 'center', gap: 22, padding: '0 26px', background: T.paper, borderBottom: '1px solid rgba(34,31,26,.1)', zIndex: 30 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 13, flex: 'none' }}>
          <img src="/daf-logo.png" alt="Dansk Adels Forening" style={{ width: 40, height: 40, objectFit: 'contain' }} />
          <div>
            <div style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600, lineHeight: 1, color: T.ink }}>Danmarks Adels Aarbog</div>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.16em', textTransform: 'uppercase', color: T.muted2, marginTop: 2 }}>Følgesvend · Dansk Adels Forening</div>
          </div>
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          {NAV.map(([label, m, on]) => (
            <div key={m} onClick={() => { if (on) { setMode(m); if (m === 'estates') setEstateId(null); } }} title={on ? '' : 'Kommer'} style={{ padding: '8px 15px', borderRadius: 9, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, cursor: on ? 'pointer' : 'default', background: mode === m ? T.bordeaux : 'transparent', color: mode === m ? T.paper : (on ? '#3d382f' : T.muted3) }}>{label}</div>
          ))}
        </div>
        <div style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 12 }}>
          {/* Slægt-chip — statisk (multi-slægt-vælger er ikke wired endnu). */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, background: T.panel, border: '1px solid rgba(34,31,26,.12)', borderRadius: 9, padding: '6px 12px' }}>
            <span style={{ width: 26, height: 26, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', boxShadow: 'inset 0 0 0 2px #f4efe6, inset 0 0 0 2.5px rgba(136,26,51,.28)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>R</span>
            <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.ink }}>Reventlow</span>
          </div>
          <a href="#redaktion" style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux, textDecoration: 'none' }}>Redaktion ↗</a>
        </div>
      </div>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* Venstre: sidebar-browse (port af design — stats · søg · sortér/alfabet/grupperet liste).
            Udskudt til Fase 2: "linjer"-stat + linje-filter-chips (kræver lineage-datalag). */}
        <div data-scroll style={{ flex: 'none', width: 312, borderRight: '1px solid rgba(34,31,26,.1)', background: T.panel, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '20px 20px 14px', borderBottom: '1px solid rgba(34,31,26,.08)' }}>
            <div style={{ display: 'flex', gap: 16, alignItems: 'stretch' }}>
              <Stat n={persons.length} label="personer" />
              <div style={{ width: 1, background: 'rgba(34,31,26,.12)' }} />
              <Stat n={estates?.length ?? null} label="godser" />
            </div>
          </div>

          <div style={{ padding: '14px 18px 10px' }}>
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Søg navn…" style={{ width: '100%', fontFamily: T.sans, fontSize: 14, color: T.ink, background: T.paper, border: '1px solid rgba(34,31,26,.14)', borderRadius: 9, padding: '11px 13px', outline: 'none' }} />
            {mode === 'relate' && (
              <div style={{ marginTop: 9, background: '#f8ecef', border: '1px solid rgba(136,26,51,.25)', borderRadius: 9, padding: '9px 12px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
                <span style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux }}>Vælg person {relSlot} i listen</span>
              </div>
            )}
            {!model && <div style={{ fontSize: 12, color: T.muted3, marginTop: 8 }}>Henter slægten…</div>}
          </div>

          <div style={{ padding: '6px 10px 8px', flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
            <div style={{ padding: '0 8px 7px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
              <span style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted3 }}>{browse.flat.length} {query ? 'træffere' : 'personer'}</span>
              <div style={{ display: 'flex', background: '#e6ddcc', borderRadius: 7, padding: 2, gap: 2, flex: 'none' }}>
                {(['navn', 'aar'] as const).map((s) => (
                  <span key={s} onClick={() => setBrowseSort(s)} style={{ fontFamily: T.sans, fontSize: 10, fontWeight: 600, padding: '3px 8px', borderRadius: 5, cursor: 'pointer', background: browseSort === s ? T.bordeaux : 'transparent', color: browseSort === s ? T.paper : '#3d382f' }}>{s === 'navn' ? 'A–Å' : 'Født'}</span>
                ))}
              </div>
            </div>

            {browse.grouped && browse.letters.length > 1 && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 3, padding: '0 8px 9px' }}>
                {[{ key: null as string | null, label: 'Alle' }, ...browse.letters.map((l) => ({ key: l as string | null, label: l }))].map((L) => {
                  const on = activeLetter === L.key;
                  return (
                    <span key={L.label} onClick={() => setActiveLetter(L.key)} style={{ fontFamily: T.mono, fontSize: 10, fontWeight: 500, minWidth: 19, height: 19, padding: '0 3px', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 5, cursor: 'pointer', background: on ? T.bordeaux : T.beige, color: on ? T.paper : T.muted }}>{L.label}</span>
                  );
                })}
              </div>
            )}

            <div style={{ flex: 1 }}>
              {browse.grouped
                ? browse.groups.map((g) => (
                    <div key={g.letter}>
                      <div style={{ position: 'sticky', top: 0, background: T.panel, padding: '7px 9px 3px', fontFamily: T.serif, fontSize: 15, fontWeight: 600, color: T.gold, zIndex: 2, borderBottom: '1px solid rgba(34,31,26,.07)' }}>{g.letter}</div>
                      {g.people.map(personRow)}
                    </div>
                  ))
                : browse.flat.map(personRow)}
              {browse.flat.length === 0 && model && <div style={{ padding: '12px 9px', fontFamily: T.sans, fontSize: 12, color: T.muted3 }}>Ingen træffere</div>}
            </div>
          </div>
        </div>

        {/* Center */}
        <div data-scroll style={{ flex: 1, minWidth: 0, overflowY: 'auto' }}>
          {mode === 'tree' ? <TreeView model={model} focusId={focusId} onPick={setFocusId} />
            : mode === 'relate' ? <RelateView model={model} rel={rel} relA={relA} relB={relB} slot={relSlot} setSlot={setRelSlot} onPickStep={setFocusId} />
            : mode === 'estates' ? <EstatesView estates={estates} estateId={estateId} estate={estates?.find((e) => e.id === estateId) ?? null} info={estateInfo} owners={estateOwners} onOpen={setEstateId} onBack={() => setEstateId(null)} onPickOwner={(id) => { setFocusId(id); setMode('tree'); }} />
            : mode === 'arms' ? <ArmsView arms={arms} />
            : mode === 'about' ? <AboutView about={about} personCount={persons.length} estateCount={estates?.length ?? null} />
            : <Placeholder label={NAV.find((n) => n[1] === mode)?.[0] ?? ''} />}
        </div>

        {/* Højre: person-detalje (kun i person-centriske visninger) */}
        {['tree', 'relate'].includes(mode) && model && focusId && (
          <DetailPanel model={model} focusId={focusId} detail={detail} onPick={setFocusId} />
        )}
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
  // Forenkling: stamtræet viser den PRIMÆRE forælder-linje (f.parentId). Slægtskabsfinderen er
  // bilineal (begge forældre) — så et halvsøskende via den anden forælder kan optræde som
  // beslægtet uden at stå i søskende-rækken her. Bevidst (variant A kan ikke vise to-forælder-celler).
  const parent = f.parentId ? model.byId[f.parentId] : null;
  const grand = parent?.parentId ? model.byId[parent.parentId] : null;
  const siblings = f.parentId ? childrenOf(model, f.parentId) : [f];
  const spouses = (model.indexes.spousesBy[focusId] ?? []).map((s) => s.name).filter(Boolean);
  const children = childrenOf(model, focusId);
  const childCount = (id: string) => model.indexes.childIdx[id]?.size ?? 0;

  return (
    <div style={{ padding: '30px 40px 50px' }}>
      <ViewHeader title="Stamtræ" mb="18px" />
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
      <ViewHeader title="Er vi i familie?" />
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

// ---- Person-detalje (højre panel) ----
function DetailPanel({ model, focusId, detail, onPick }: { model: Model; focusId: string; detail: PersonDetailData | null; onPick: (id: string) => void }) {
  const p = model.byId[focusId];
  if (!p) return null;
  const parents = (model.indexes.parentsByChild[focusId] ?? []).map((id) => model.byId[id]).filter(Boolean) as { id: string; name: string }[];
  const spouses = (model.indexes.spousesBy[focusId] ?? []);
  const children = childrenOf(model, focusId);
  return (
    <div data-scroll style={{ flex: 'none', width: 392, borderLeft: '1px solid rgba(34,31,26,.1)', background: T.paper, overflowY: 'auto' }}>
      <div style={{ padding: '24px 24px 36px' }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
          <div style={{ width: 92, height: 116, borderRadius: 11, background: 'repeating-linear-gradient(45deg,#ece4d6 0 9px,#e2d8c8 9px 18px)', border: '1px solid rgba(34,31,26,.1)', flex: 'none', display: 'flex', alignItems: 'flex-end', padding: 8 }}><span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted }}>portræt</span></div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1, fontWeight: 600 }}>{p.name}</div>
            {p.years && <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 6 }}>{p.years}</div>}
            {p.title && <div style={{ display: 'inline-block', fontSize: 11, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '4px 9px', borderRadius: 6, marginTop: 9 }}>{p.title}</div>}
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

        {detail === null && <div style={{ marginTop: 18, fontSize: 12, color: T.muted3 }}>Henter detaljer…</div>}
      </div>
    </div>
  );
}

// (Søg-center-visningen er fjernet — browsing bor nu i sidebaren: sortér + alfabet-hop §9.1 +
//  grupperet liste med sticky headers. Se `browse`-memo + venstre panel i Folgesvend().)

// ---- Godser & ejendomme ----
function EstatesView({ estates, estateId, estate, info, owners, onOpen, onBack, onPickOwner }: {
  estates: EstateItem[] | null; estateId: string | null; estate: EstateItem | null; info: EstateInfo | null;
  owners: EstateOwner[]; onOpen: (id: string) => void; onBack: () => void; onPickOwner: (id: string) => void;
}) {
  if (estateId && estate) {
    return (
      <div style={{ padding: '26px 40px 50px', maxWidth: 620 }}>
        <div onClick={onBack} style={{ fontSize: 12.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginBottom: 14 }}>‹ Alle godser</div>
        <div style={{ fontFamily: T.serif, fontSize: 32, fontWeight: 600, lineHeight: 1.02 }}>{estate.navn}</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 9 }}>
          {estate.slags && <span style={{ fontSize: 11.5, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '5px 10px', borderRadius: 7 }}>{estate.slags}</span>}
          {info?.sted && <span style={{ fontSize: 11.5, fontWeight: 600, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '5px 10px', borderRadius: 7 }}>⌖ {info.sted}</span>}
        </div>
        {/* Vis intet under load (info===null); derefter narrativ eller tom-tilstand. */}
        {info && (info.narrativ ? (
          <div style={{ marginTop: 16, fontFamily: T.serif, fontSize: 15.5, lineHeight: 1.6, color: '#3d382f', whiteSpace: 'pre-wrap' }}><NarrativRenderer tekst={info.narrativ} onPickPerson={onPickOwner} linkColor={T.bordeaux} inactiveColor={T.muted2} /></div>
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
      </div>
    );
  }
  return (
    <div style={{ padding: '30px 40px 50px' }}>
      <ViewHeader title="Godser &amp; ejendomme" />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 20 }}>Besiddelser knyttet til slægten — klik for ejerrækken gennem tiden.</div>
      {!estates ? <div style={{ color: T.muted3 }}>Henter…</div> : !estates.length ? <div style={{ color: T.muted3 }}>Ingen godser registreret.</div> : (
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

// ---- Slægtens våben ----
function ArmsView({ arms }: { arms: ArmsItem[] | null }) {
  const main = arms?.[0];
  const rest = (arms ?? []).slice(1);
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <ViewHeader title="Slægtens våben" mb="18px" />
      {!arms ? <div style={{ color: T.muted3 }}>Henter…</div> : (
        <>
          <div style={{ background: T.ink, borderRadius: 16, padding: 26, display: 'flex', gap: 24, alignItems: 'center' }}>
            <div style={{ width: 150, height: 185, borderRadius: 10, background: 'repeating-linear-gradient(45deg,#3a352c 0 9px,#322d25 9px 18px)', border: '1px solid rgba(231,201,143,.2)', flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ fontFamily: T.mono, fontSize: 10, color: T.gold }}>våbenskjold</span></div>
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
                {rest.map((v) => (
                  <div key={v.id} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: 11 }}>
                    <div style={{ width: '100%', aspectRatio: '.82', borderRadius: 8, background: 'repeating-linear-gradient(45deg,#ece4d6 0 8px,#e2d8c8 8px 16px)', border: '1px solid rgba(34,31,26,.08)' }} />
                    <div style={{ fontFamily: T.serif, fontSize: 14, fontWeight: 600, marginTop: 7, lineHeight: 1.1 }}>{v.note || v.blasonering.slice(0, 40) || 'variant'}</div>
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}

// ---- Om slægten ----
function AboutView({ about, personCount, estateCount }: { about: string[] | null; personCount: number; estateCount: number | null }) {
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 680 }}>
      <div style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, lineHeight: 1.02 }}>Slægten Reventlow</div>
      <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted2, marginTop: 8 }}>Indledning til stamtavlen · Danmarks Adels Aarbog</div>
      <div style={{ display: 'flex', gap: 22, marginTop: 16 }}>
        <Counter n={personCount} label="personer" />
        {estateCount != null && <Counter n={estateCount} label="godser" />}
      </div>
      <div style={{ height: 1, background: 'rgba(34,31,26,.12)', margin: '20px 0' }} />
      {!about ? <div style={{ color: T.muted3 }}>Henter…</div> : about.length ? about.map((t, i) => (
        <div key={i} style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.6, color: '#3d382f', marginBottom: 16, whiteSpace: 'pre-wrap' }}>{t}</div>
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
const Stat = ({ n, label }: { n: number | null; label: string }) => (
  <div>
    <div style={{ fontFamily: T.serif, fontSize: 23, fontWeight: 600, color: T.bordeaux, lineHeight: 1 }}>{n == null ? '—' : n.toLocaleString('da')}</div>
    <div style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, marginTop: 3 }}>{label}</div>
  </div>
);

// ---- små byggeklodser ----
const Kicker = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.2em', textTransform: 'uppercase', color: T.gold, marginBottom: 6 }}>{children}</div>;
const H1 = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1 }}>{children}</div>;
// Fælles visnings-overskrift: kicker + titel + bordeaux-streg. mb='6px' når der følger en
// undertekst, '18px' når overskriften står alene.
const ViewHeader = ({ title, mb = '6px' }: { title: string; mb?: string }) => (
  <>
    <Kicker>Slægten Reventlow</Kicker>
    <H1>{title}</H1>
    <div style={{ width: 42, height: 1.5, background: T.bordeaux, margin: `11px 0 ${mb}` }} />
  </>
);
const Label = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 12px' }}>{children}</div>;
const Stem = ({ h, mt = 0 }: { h: number; mt?: number }) => <div style={{ width: 1, height: h, background: 'rgba(34,31,26,.22)', marginTop: mt }} />;
const Avatar = ({ n, size }: { n: string; size: number }) => (
  <div style={{ width: size, height: size, borderRadius: '50%', background: '#f4ece0', border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: size * 0.4, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(n)}</div>
);

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
