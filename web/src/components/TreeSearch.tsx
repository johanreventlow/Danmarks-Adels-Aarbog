// Søgning-i-træet (§4): søgefelt + universel-klart fane-bånd + browse-værktøjer + resultat-grid
// som personkort. Bundtet (state + handlers) ejes af Folgesvend og deles af TreeView (onPick =
// centrér træet) og RelateView (onPick = fyld A/B-plads, §5.6). `showResults` gater om
// resultaterne eller selve fladen (træ / A-B-sti) vises.
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme bundt-kontrakt, blot flyttet fil.
import { useEffect, useRef, type CSSProperties } from 'react';
import { T } from '../theme';
import { SearchIcon, PersonCard, LinjeChip } from './primitives';
import { personPath } from '../data/nav';
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
  // Adressen et resultat linker til (samme som onPick navigerer til). Default /person/<id>.
  personHref?: (id: string) => string;
};

export function TreeSearch(s: TreeSearchBundle) {
  const inputRef = useRef<HTMLInputElement>(null);
  // Consume-and-reset (dual-review M1): fokusér ved et bump og nulstil straks tokenet, ellers ville
  // TreeSearch (der re-mountes ved hvert mode-skift) stjæle fokus på ENHVER senere tree/relate-entry
  // — fx når man klikker "Find slægtskab" uden at ville søge.
  useEffect(() => { if (s.focusToken > 0) { inputRef.current?.focus(); s.resetFocus(); } }, [s.focusToken]);
  return (
    <div style={{ marginBottom: 16 }}>
      {/* Søgefelt */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, background: T.surfaceRaised, border: '1px solid rgba(34,31,26,.16)', borderRadius: 12, padding: '13px 17px', boxShadow: '0 2px 8px rgba(20,17,13,.04)' }}>
        <SearchIcon size={19} />
        <input ref={inputRef} type="search" aria-label="Søg person" value={s.query} onChange={(e) => s.setQuery(e.target.value)} placeholder="Søg i slægten…" style={{ flex: 1, minWidth: 0, fontFamily: T.sans, fontSize: 16, color: T.ink, background: 'transparent', border: 'none', outline: 'none' }} />
        {s.showResults && (
          <>
            <span style={{ fontFamily: T.sans, fontSize: 13, color: T.inkMuted, whiteSpace: 'nowrap', flex: 'none' }}>{`${s.browse.flat.length} ${s.query.trim() ? 'træffere' : 'personer'}`}</span>
            <button type="button" onClick={s.clearSearch} title="Ryd søgning" aria-label="Ryd søgning" style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', flex: 'none', background: 'transparent', border: 0, padding: 2 }}>
              <svg viewBox="0 0 24 24" width={15} height={15} fill="none" stroke={T.inkMuted} strokeWidth={2} strokeLinecap="round" aria-hidden="true"><path d="M18 6L6 18M6 6l12 12" /></svg>
            </button>
          </>
        )}
      </div>

      {/* Fanerne Godser · Steder · Artikler er fjernet (webredesign fase 2): de var »kommer«-punkter.
          Søgning på tværs af typer kommer med søgesiden i fase 6. */}
      {!s.showResults && (
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 8, borderBottom: `1px solid ${T.line}` }}>
          <button type="button" onClick={() => s.setBrowsing(true)} style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux, background: 'transparent', border: 0, cursor: 'pointer', padding: '8px 0', whiteSpace: 'nowrap' }}>Gennemse hele slægten ›</button>
        </div>
      )}

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
                <span onClick={() => s.setBmOnly(!s.bmOnly)} title="Vis kun bogmærkede" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 12px', borderRadius: 15, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', background: s.bmOnly ? T.bordeaux : T.surfaceRaised, color: s.bmOnly ? T.onBordeaux : T.inkSecondary, border: `1px solid ${s.bmOnly ? T.bordeaux : 'rgba(34,31,26,.14)'}` }}>
                  {/* Samme ribbon-form som BookmarkFlag-primitiven (bruger-bestemt, konsistent). */}
                  <svg viewBox="0 0 14 17" width={11} height={13} fill={s.bmOnly ? T.surfaceRaised : 'none'} stroke={s.bmOnly ? T.surfaceRaised : T.inkMuted} strokeWidth={1.5} strokeLinejoin="round"><path d="M3 1.5 H11 V15.5 L7 11.8 L3 15.5 Z" /></svg>
                  Bogmærker
                </span>
              )}
            </div>
            <div style={{ display: 'flex', background: T.surfaceSunken, borderRadius: 7, padding: 2, gap: 2, flex: 'none' }}>
              {(['navn', 'aar'] as const).map((so) => (
                <span key={so} onClick={() => s.setSort(so)} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, padding: '4px 11px', borderRadius: 5, cursor: 'pointer', background: s.sort === so ? T.bordeaux : 'transparent', color: s.sort === so ? T.onBordeaux : T.inkSecondary }}>{so === 'navn' ? 'A–Å' : 'Født'}</span>
              ))}
            </div>
          </div>

          {/* Alfabet-hop */}
          {s.browse.grouped && s.browse.letters.length > 1 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 16 }}>
              {[{ key: null as string | null, label: 'Alle' }, ...s.browse.letters.map((l) => ({ key: l as string | null, label: l }))].map((L) => {
                const on = s.activeLetter === L.key;
                return <span key={L.label} onClick={() => s.setActiveLetter(L.key)} style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 500, minWidth: 24, height: 24, padding: '0 5px', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 6, cursor: 'pointer', background: on ? T.bordeaux : T.surfaceSunken, color: on ? T.onBordeaux : T.inkMuted }}>{L.label}</span>;
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
                  <div style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.goldInk, margin: '6px 0 10px', paddingBottom: 5, borderBottom: '1px solid rgba(34,31,26,.08)' }}>{g.letter}</div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginBottom: 14 }}>
                    {g.people.map((p) => <PersonCard key={p.id} p={p} width={186} href={(s.personHref ?? personPath)(p.id)} onClick={() => s.onPick(p.id)} />)}
                  </div>
                </div>
              ))
            : <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>{s.browse.flat.map((p) => <PersonCard key={p.id} p={p} width={186} href={(s.personHref ?? personPath)(p.id)} onClick={() => s.onPick(p.id)} />)}</div>}
          {s.browse.flat.length === 0 && (
            <div style={{ padding: '20px 4px', fontFamily: T.sans }}>
              <div style={{ fontFamily: T.serif, fontSize: 24, fontWeight: 600, color: T.ink }}>{s.query.trim() ? `Ingen hedder »${s.query.trim()}«` : 'Ingen personer at vise'}</div>
              <div style={{ fontSize: 14.5, lineHeight: 1.5, color: T.inkSecondary, marginTop: 6 }}>{s.query.trim() ? 'Prøv en anden stavemåde. Stavemåder skifter gennem udgaverne.' : 'Ingen personer passer til de valgte filtre.'}</div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
