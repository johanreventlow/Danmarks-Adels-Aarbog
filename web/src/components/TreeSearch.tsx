// Søgning-i-træet (§4): søgefelt + universel-klart fane-bånd + browse-værktøjer + resultat-grid
// som personkort. Bundtet (state + handlers) ejes af Folgesvend og deles af TreeView (onPick =
// centrér træet) og RelateView (onPick = fyld A/B-plads, §5.6). `showResults` gater om
// resultaterne eller selve fladen (træ / A-B-sti) vises.
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme bundt-kontrakt, blot flyttet fil.
import { useEffect, useRef, type CSSProperties } from 'react';
import { T } from '../theme';
import { SearchIcon, PersonCard, LinjeChip } from './primitives';
import type { BrowseResult } from '../data/browse';
import type { LinjeEntry } from '../data/types';

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

export function TreeSearch(s: TreeSearchBundle) {
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
        <input ref={inputRef} value={s.query} onChange={(e) => s.setQuery(e.target.value)} placeholder="Søg i slægten…" style={{ flex: 1, minWidth: 0, fontFamily: T.sans, fontSize: 16, color: T.ink, background: 'transparent', border: 'none', outline: 'none' }} />
        {s.showResults && (
          <>
            <span style={{ fontFamily: T.sans, fontSize: 13, color: T.muted3, whiteSpace: 'nowrap', flex: 'none' }}>{`${s.browse.flat.length} ${s.query.trim() ? 'træffere' : 'personer'}`}</span>
            <span onClick={s.clearSearch} title="Ryd søgning" style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', flex: 'none' }}>
              <svg viewBox="0 0 24 24" width={15} height={15} fill="none" stroke={T.muted2} strokeWidth={2} strokeLinecap="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
            </span>
          </>
        )}
      </div>

      {/* Fane-bånd — universel-klar (brief §4.2); kun Personer aktiv nu */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 2, marginTop: 12, borderBottom: '1px solid rgba(34,31,26,.1)' }}>
        {SEARCH_TABS.map((tb) => (
          <div key={tb.key} title={tb.live ? '' : 'Kommer'} style={{ padding: '9px 3px', marginRight: 16, fontFamily: T.sans, fontSize: 14.5, fontWeight: 600, color: tb.live ? T.bordeaux : T.muted3, borderBottom: `2px solid ${tb.live ? T.bordeaux : 'transparent'}` }}>{tb.label}</div>
        ))}
        <div style={{ flex: 1 }} />
        {!s.showResults && (
          <span onClick={() => s.setBrowsing(true)} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', padding: '8px 0', whiteSpace: 'nowrap' }}>Gennemse hele slægten ›</span>
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
                <LinjeChip key={l.linje} label={l.navn ?? `Linje ${l.linje}`} title={l.navn ?? undefined} active={s.activeLinje === l.linje} onClick={() => s.setActiveLinje(l.linje)} />
              ))}
              {s.hasBookmarks && (
                <span onClick={() => s.setBmOnly(!s.bmOnly)} title="Vis kun bogmærkede" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 12px', borderRadius: 15, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', background: s.bmOnly ? T.bordeaux : T.paper, color: s.bmOnly ? T.paper : '#3d382f', border: `1px solid ${s.bmOnly ? T.bordeaux : 'rgba(34,31,26,.14)'}` }}>
                  {/* Samme ribbon-form som BookmarkFlag-primitiven (bruger-bestemt, konsistent). */}
                  <svg viewBox="0 0 14 17" width={11} height={13} fill={s.bmOnly ? T.paper : 'none'} stroke={s.bmOnly ? T.paper : T.muted2} strokeWidth={1.5} strokeLinejoin="round"><path d="M3 1.5 H11 V15.5 L7 11.8 L3 15.5 Z" /></svg>
                  Bogmærker
                </span>
              )}
            </div>
            <div style={{ display: 'flex', background: '#e6ddcc', borderRadius: 7, padding: 2, gap: 2, flex: 'none' }}>
              {(['navn', 'aar'] as const).map((so) => (
                <span key={so} onClick={() => s.setSort(so)} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, padding: '4px 11px', borderRadius: 5, cursor: 'pointer', background: s.sort === so ? T.bordeaux : 'transparent', color: s.sort === so ? T.paper : '#3d382f' }}>{so === 'navn' ? 'A–Å' : 'Født'}</span>
              ))}
            </div>
          </div>

          {/* Alfabet-hop */}
          {s.browse.grouped && s.browse.letters.length > 1 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 16 }}>
              {[{ key: null as string | null, label: 'Alle' }, ...s.browse.letters.map((l) => ({ key: l as string | null, label: l }))].map((L) => {
                const on = s.activeLetter === L.key;
                return <span key={L.label} onClick={() => s.setActiveLetter(L.key)} style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 500, minWidth: 24, height: 24, padding: '0 5px', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 6, cursor: 'pointer', background: on ? T.bordeaux : T.beige, color: on ? T.paper : T.muted }}>{L.label}</span>;
              })}
            </div>
          )}

          {/* Resultat-grid som personkort (§8.1 én korttype) */}
          {s.browse.grouped
            ? s.browse.groups.map((g) => (
                // content-visibility: 'auto' (review 27 P2) skipper layout/paint for bogstav-grupper der er
                // ude af viewport — ved ~920 personkort giver hvert tastetryk ellers jank. containIntrinsicSize
                // er et groft højde-estimat (undgår scroll-hop når browseren måler første gang).
                <div key={g.letter} style={{ contentVisibility: 'auto', containIntrinsicSize: 'auto 700px' } as CSSProperties}>
                  <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.gold, margin: '6px 0 10px', paddingBottom: 5, borderBottom: '1px solid rgba(34,31,26,.08)' }}>{g.letter}</div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginBottom: 14 }}>
                    {g.people.map((p) => <PersonCard key={p.id} p={p} width={186} onClick={() => s.onPick(p.id)} />)}
                  </div>
                </div>
              ))
            : <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>{s.browse.flat.map((p) => <PersonCard key={p.id} p={p} width={186} onClick={() => s.onPick(p.id)} />)}</div>}
          {s.browse.flat.length === 0 && <div style={{ padding: '20px 4px', fontFamily: T.sans, fontSize: 14, color: T.muted3 }}>Ingen træffere.</div>}
        </div>
      )}
    </div>
  );
}
