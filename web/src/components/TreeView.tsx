// ---- Stamtræ (variant A "Fokus" + variant B "Kolonner") ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
// Eksporteret så drill-down/toggle/reset-adfærden kan komponent-testes uden hele Folgesvend.
// onPick = fokus-hop MED historik (variant A-kort, matcher designets goToPerson). onFocus =
// drill-valg UDEN historik (variant B-kolonner, matcher designets selectAt) — så en dyb drill
// ikke fylder detalje-panelets tilbage-stak med hvert generations-trin.
import { useLayoutEffect, useEffect, useMemo, useRef, useState } from 'react';
import { T } from '../theme';
import { childrenOf, parentsOf } from '../data/model';
import type { Model } from '../data/types';
import { buildBidirectionalColumns } from '@daa/core';
import { ViewHeader, Avatar, BookmarkFlag, Crest, Label, Stem } from './primitives';
import { TreeSearch, type TreeSearchBundle } from './TreeSearch';

export function TreeView({ model, focusId, onPick, onFocus, hasBookmark, onToggleBookmark, search }: {
  model: Model | null; focusId: string | null; onPick: (id: string) => void; onFocus: (id: string) => void;
  hasBookmark: (id: string) => boolean; onToggleBookmark: (id: string) => void; search: TreeSearchBundle;
}) {
  // Visnings-variant (segmenteret kontrol) — bevares på tværs af fokus-skift (nulstilles kun når
  // TreeView unmountes ved mode-skift til Godser/Våben/Slægtskab). Matcher designets state.variant.
  const [variant, setVariant] = useState<'A' | 'B'>('A');
  // Bidirektionel drill-tilstand (variant B): fast anker + valgte aner (op) + valgte efterkommere (ned).
  // up[i] = valgt forælder i ane-ring i+1; down[i] = valgt barn i efterkommer-ring i+1.
  const [anchorId, setAnchorId] = useState<string | null>(null);
  const [up, setUp] = useState<string[]>([]);
  const [down, setDown] = useState<string[]>([]);
  const colsRef = useRef<HTMLDivElement>(null);
  const anchorIdxRef = useRef(0);           // indeks på anker-kolonnen (til centrering)
  const prevUp = useRef(0), prevDown = useRef(0), prevAnchor = useRef<string | null>(null), prevVariant = useRef<'A' | 'B'>('A');
  const STRIDE = 222;                        // kolonnebredde 208 + gap 14
  // Memoiseret som mobil (tree.tsx): undgår gen-beregning ved urelaterede parent-re-renders
  // (browse-tastetryk, bogmærke-toggle) — den delte bygger er byte-identisk, memo er kun call-site.
  const cols = useMemo(
    () => (model && variant === 'B' && anchorId ? buildBidirectionalColumns(model, anchorId, up, down, childrenOf, parentsOf, model.genCoordsByPerson, model.parentsUnknownByPerson) : []),
    [model, variant, anchorId, up, down],
  );

  // Ankeret følger fokus-personen. Nulstil (ryd begge drill-retninger) KUN ved EKSTERN navigation.
  // Frontier-tjek (IKKE fuldt medlemskab, jf. spec §5.3): efter en drill er focusId altid den
  // YDERSTE valgte ane/efterkommer, så et frontier-match betyder "drill", ellers "ekstern nav →
  // nulstil". Invariant: focusId + alle up/down-id'er er KANONISKE (focusId post-canon; up/down
  // udvides kun med parentsOf/childrenOf-id'er) → korrekt lighed i tjekket.
  useEffect(() => {
    if (!focusId) return;
    const keep =
      (up.length === 0 && down.length === 0 && focusId === anchorId) ||
      focusId === up[up.length - 1] ||
      focusId === down[down.length - 1];
    if (!keep) {
      // Ekstern navigation (søgning/link/"det er mig"/deep-link) → nyt anker, ryd drill-retninger.
      setAnchorId(focusId);
      setUp([]); setDown([]);
    }
  }, [focusId]);

  // Kompensér FØR paint når en ane-kolonne prepend'es, så ankeret ikke "hopper" (spec §5.5, fase 1).
  useLayoutEffect(() => {
    const el = colsRef.current;
    if (el && variant === 'B' && up.length > prevUp.current) el.scrollLeft += (up.length - prevUp.current) * STRIDE;
  }, [up.length, variant]);

  // Efter paint (spec §5.5, fase 2): centrér anker ved reset/B-skift; afslør nyeste kolonne ved drill.
  // scrollTo feature-detekteres (findes ikke i jsdom).
  useEffect(() => {
    const el = colsRef.current;
    const sync = () => { prevUp.current = up.length; prevDown.current = down.length; prevAnchor.current = anchorId; prevVariant.current = variant; };
    if (variant !== 'B' || !el?.scrollTo) { sync(); return; }
    if (anchorId !== prevAnchor.current || prevVariant.current !== 'B') {
      const target = Math.max(0, anchorIdxRef.current * STRIDE - (el.clientWidth - 208) / 2);
      el.scrollTo({ left: target, behavior: 'smooth' });          // centrér anker
    } else if (down.length > prevDown.current) {
      el.scrollTo({ left: el.scrollWidth, behavior: 'smooth' });  // ny efterkommer → højre
    } else if (up.length > prevUp.current) {
      el.scrollTo({ left: Math.max(0, el.scrollLeft - STRIDE), behavior: 'smooth' }); // ny ane → afslør venstre
    }
    sync();
  }, [variant, anchorId, up.length, down.length]);

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
  const hasParents = (id: string) => (model.indexes.parentsByChild[id]?.length ?? 0) > 0;

  // Drill-valg (variant B). onFocus opdaterer fokus UDEN historik, så detalje-panelet følger valget.
  // Vi udvider up/down KUN med parentsOf/childrenOf-id'er (kanoniske) → frontier-invarianten holder.
  const selectAncestor = (depth: number, id: string) => { setUp((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const selectDescendant = (depth: number, id: string) => { setDown((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const anchorColIdx = cols.findIndex((c) => c.kind === 'anchor');
  anchorIdxRef.current = Math.max(0, anchorColIdx);

  return (
    <div style={{ padding: '30px 40px 50px', position: 'relative', minHeight: '100%' }}>
      {/* Dekorativt våbenskjold-vandmærke (delt Crest-primitiv). */}
      <Crest opacity={0.09} size={116} style={{ position: 'absolute', top: 104, right: 34, zIndex: 0 }} />
      <div style={{ position: 'relative', zIndex: 1 }}>
      {/* Header: titel til venstre, segmenteret kontrol (Fokus/Kolonner) til højre. */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <ViewHeader title="Stamtræ" mb="0" />
        </div>
        <div style={{ display: 'flex', background: T.beige, borderRadius: 10, padding: 3, gap: 3, flex: 'none' }}>
          {(['A', 'B'] as const).map((v) => {
            const active = variant === v;
            return (
              <div key={v} onClick={() => setVariant(v)} style={{ padding: '7px 16px', borderRadius: 7, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, cursor: 'pointer', background: active ? T.paper : 'transparent', color: active ? T.bordeaux : '#8a8170' }}>{v === 'A' ? 'Fokus' : 'Kolonner'}</div>
            );
          })}
        </div>
      </div>

      {/* Søgning-i-træet (§4): søgefelt + fane-bånd + resultat-grid, over selve træet. */}
      <TreeSearch {...search} />

      {!search.showResults && (variant === 'B' ? (
        <div ref={colsRef} data-scroll style={{ display: 'flex', gap: 14, overflowX: 'auto', padding: '10px 0 16px', alignItems: 'flex-start' }}>
          {cols.map((col) => (
            <div key={col.key} style={{ flex: 'none', width: 208, display: 'flex', flexDirection: 'column', gap: 9 }}>
              <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.gold, padding: '0 2px 4px', borderBottom: '1px solid rgba(34,31,26,.1)' }}>{col.label}</div>
              {col.candidate && col.candidateNote && (
                <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, padding: '0 2px', marginTop: -4, lineHeight: 1.3 }}>{col.candidateNote}</div>
              )}
              {col.candidate ? (
                <>
                  {Object.entries(col.kuldGroups ?? {}).map(([kuld, people]) => (
                    <div key={kuld} style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
                      {kuld !== '—' && (
                        <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, padding: '2px 2px 0' }}>Kuld {kuld}</div>
                      )}
                      {people.map((p) => (
                        <div key={p.id} onClick={() => onFocus(p.id)} style={{ background: '#faf1dc', border: `1.5px dashed ${T.gold}`, borderRadius: 12, padding: '11px 13px', cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                          <Avatar n={p.name} size={34} />
                          <div style={{ minWidth: 0, flex: 1 }}>
                            <div style={{ fontFamily: T.serif, fontSize: 17, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                            {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 2 }}>{p.years}</div>}
                            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.06em', textTransform: 'uppercase', color: T.gold, marginTop: 2 }}>muligt slægtled</div>
                          </div>
                          <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                        </div>
                      ))}
                    </div>
                  ))}
                  {col.kilde && (
                    <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted3, padding: '4px 2px 0', lineHeight: 1.35, borderTop: '1px dashed rgba(34,31,26,.12)', marginTop: 2 }}>Kilde: {col.kilde}</div>
                  )}
                </>
              ) : col.people.map((p) => {
                const sel = p.id === col.selectedId;
                // Kort-chevron peger i drill-retningen: aner ‹ (venstre), efterkommere › (højre).
                // Ankeret (kind==='anchor', altid sel) er ikke-klikbart: onTap undefined + default-cursor,
                // ingen chevrons (canAnc/canDesc falske) — samme bordeaux-fokus-kort uden en tredje JSX-kopi.
                const canAnc = col.kind === 'ancestor' && hasParents(p.id);
                const canDesc = col.kind === 'descendant' && childCount(p.id) > 0;
                const onTap = col.kind === 'anchor' ? undefined
                  : col.kind === 'ancestor' ? () => selectAncestor(col.depth, p.id)
                  : () => selectDescendant(col.depth, p.id);
                return (
                  <div key={p.id} onClick={onTap} style={{ background: sel ? '#f8ecef' : T.paper, border: `1.5px solid ${sel ? T.bordeaux : 'rgba(34,31,26,.1)'}`, borderRadius: 12, padding: '11px 13px', cursor: col.kind === 'anchor' ? 'default' : 'pointer', boxShadow: sel ? '0 4px 14px rgba(136,26,51,.12)' : '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                    {canAnc && <span style={{ color: '#bcae93', fontSize: 17, flex: 'none' }}>‹</span>}
                    <Avatar n={p.name} size={34} />
                    <div style={{ minWidth: 0, flex: 1 }}>
                      <div style={{ fontFamily: T.serif, fontSize: 17, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                      {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 2 }}>{p.years}</div>}
                    </div>
                    <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                    {canDesc && <span style={{ color: '#bcae93', fontSize: 17, flex: 'none' }}>›</span>}
                  </div>
                );
              })}
              {col.unconnectedChildren && col.unconnectedChildren.length > 0 && (
                <div style={{ marginTop: 4, paddingTop: 8, borderTop: '1px dashed rgba(34,31,26,.16)' }}>
                  <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.08em', textTransform: 'uppercase', color: T.muted3, padding: '0 2px 6px' }}>Uforbundne — placeret efter slægtled, ikke forældreskab</div>
                  {col.unconnectedChildren.map((group) => (
                    <div key={group.grade} style={{ display: 'flex', flexDirection: 'column', gap: 9, marginBottom: 6 }}>
                      <div style={{ fontFamily: T.sans, fontSize: 11, color: T.muted2, padding: '0 2px', lineHeight: 1.3 }}>{group.note}</div>
                      {group.people.map(({ person, kilde }) => (
                        <div key={person.id} onClick={() => onFocus(person.id)} style={{ background: '#faf1dc', border: `1.5px dashed ${T.gold}`, borderRadius: 12, padding: '9px 11px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 9 }}>
                          <Avatar n={person.name} size={30} />
                          <div style={{ minWidth: 0, flex: 1 }}>
                            <div style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{person.name}</div>
                            {person.years && <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2, marginTop: 1 }}>{person.years}</div>}
                            {kilde && <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted3, marginTop: 2 }}>Kilde: {kilde}</div>}
                          </div>
                          <BookmarkFlag active={hasBookmark(person.id)} onClick={() => onToggleBookmark(person.id)} />
                        </div>
                      ))}
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        {grand && (
          <>
            <div onClick={() => onPick(grand.id)} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 16px', borderRadius: 20, background: T.beige, border: '1px solid rgba(34,31,26,.08)', cursor: 'pointer', opacity: 0.85 }}>
              <span style={{ color: T.muted2, fontSize: 13 }}>▲</span>
              <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: '#5a5246' }}>{grand.name}</span>
            </div>
            <Stem h={18} />
          </>
        )}
        {parent && (
          <>
            <div onClick={() => onPick(parent.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: '11px 18px 11px 12px', cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)' }}>
              <Avatar n={parent.name} size={40} />
              <div>
                <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: T.gold }}>Forælder ▲</div>
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
                <div style={{ position: 'absolute', top: 12, left: 13 }}><BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} /></div>
                {sel && <div style={{ position: 'absolute', top: 12, right: 13, fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.1em', textTransform: 'uppercase', color: T.bordeaux }}>I fokus</div>}
                <Avatar n={p.name} size={56} />
                <div style={{ fontFamily: T.serif, fontSize: 21, lineHeight: 1.04, fontWeight: 600, marginTop: 11 }}>{p.name}</div>
                {p.years && <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 4 }}>{p.years}</div>}
                {p.title && <div style={{ fontSize: 12.5, fontWeight: 500, color: T.bordeaux, marginTop: 6, lineHeight: 1.3 }}>{p.title}</div>}
                {childCount(p.id) > 0 && <div style={{ fontSize: 11.5, color: T.muted, marginTop: 8 }}>↓ {childCount(p.id)} {childCount(p.id) === 1 ? 'barn' : 'børn'}</div>}
              </div>
            );
          })}
        </div>
        {spouses.length > 0 && <div style={{ marginTop: 12, fontFamily: T.serif, fontSize: 16, fontStyle: 'italic', color: T.muted }}>⚭ gift med {spouses.join(', ')}</div>}
        {children.length > 0 ? (
          <>
            <Stem h={22} mt={16} />
            <Label>Børn &amp; grene</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 11, justifyContent: 'center', maxWidth: 820 }}>
              {children.map((p) => (
                <div key={p.id} onClick={() => onPick(p.id)} style={{ width: 150, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: 13, cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)' }}>
                  <Avatar n={p.name} size={40} />
                  <div style={{ fontFamily: T.serif, fontSize: 17, lineHeight: 1.05, fontWeight: 600, marginTop: 9 }}>{p.name}</div>
                  {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 3 }}>{p.years}</div>}
                  {childCount(p.id) > 0 && <div style={{ fontSize: 11, color: T.bordeaux, marginTop: 6 }}>↓ {childCount(p.id)}</div>}
                </div>
              ))}
            </div>
          </>
        ) : (
          <div style={{ marginTop: 18, fontSize: 13.5, color: T.muted3 }}>Ingen registrerede efterkommere</div>
        )}
      </div>
      ))}
      </div>
    </div>
  );
}
