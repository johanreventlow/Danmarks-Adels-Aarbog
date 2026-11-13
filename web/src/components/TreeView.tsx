// ---- Stamtræ (variant A "Fokus" + variant B "Kolonner") ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
// Eksporteret så drill-down/toggle/reset-adfærden kan komponent-testes uden hele Folgesvend.
// onPick = fokus-hop MED historik (variant A-kort, matcher designets goToPerson). onFocus =
// drill-valg UDEN historik (variant B-kolonner, matcher designets selectAt) — så en dyb drill
// ikke fylder detalje-panelets tilbage-stak med hvert generations-trin.
import { useLayoutEffect, useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { T } from '../theme';
import { childrenOf, parentsOf } from '../data/model';
import type { Model } from '../data/types';
import { buildBidirectionalColumns } from '@daa/core';
import { ViewHeader, Avatar, BookmarkFlag } from './primitives';
import { FokusTrae } from './FokusTrae';
import { useSmalSkaerm } from '../useSmalSkaerm';
import { TreeSearch, type TreeSearchBundle } from './TreeSearch';
import { Link } from '../Link';
import { personPath } from '../data/nav';

export function TreeView({ model, focusId, onPick, onFocus, hasBookmark, onToggleBookmark, search, personHref = personPath }: {
  model: Model | null; focusId: string | null; onPick: (id: string) => void; onFocus: (id: string) => void;
  // Adressen et navn linker til (samme som klikket navigerer til). Default /person/<id>.
  personHref?: (id: string) => string;
  hasBookmark: (id: string) => boolean; onToggleBookmark: (id: string) => void; search: TreeSearchBundle;
}) {
  // Visnings-variant (segmenteret kontrol) — bevares på tværs af fokus-skift (nulstilles kun når
  // TreeView unmountes ved mode-skift til Godser/Våben/Slægtskab). Matcher designets state.variant.
  const [variant, setVariant] = useState<'A' | 'B'>('A');
  const smal = useSmalSkaerm();
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

  if (!model || !focusId) return <div style={{ padding: 40, color: T.inkMuted }}>Henter…</div>;
  const f = model.byId[focusId];
  if (!f) return <div style={{ padding: 40, color: T.inkMuted }}>Ukendt person.</div>;
  // Fokusvisningen (variant A) bor i FokusTrae.tsx (fase 5c); her er kun Kolonner (variant B).
  const childCount = (id: string) => model.indexes.childIdx[id]?.size ?? 0;
  const hasParents = (id: string) => (model.indexes.parentsByChild[id]?.length ?? 0) > 0;

  // Navnet i et kort er ankeret (kortet selv rummer BookmarkFlag → ugyldigt som <a>).
  // stopPropagation: kortets egen onClick ville ellers udføre samme navigation én gang til —
  // og ved cmd-klik navigere den aktuelle fane mens browseren åbner en ny.
  // display:block: et <a> er inline, og så virker overflow/ellipsis ikke — navnet løb ind under
  // bogmærkeflaget i Kolonner. title viser hele navnet, når det er afkortet.
  const navnLink = (id: string, navn: string, style: CSSProperties, onTap?: () => void) =>
    onTap
      ? <Link href={personHref(id)} onNavigate={onTap} stopPropagation title={navn} style={{ display: 'block', ...style }}>{navn}</Link>
      : <div title={navn} style={style}>{navn}</div>;

  // Drill-valg (variant B). onFocus opdaterer fokus UDEN historik, så detalje-panelet følger valget.
  // Vi udvider up/down KUN med parentsOf/childrenOf-id'er (kanoniske) → frontier-invarianten holder.
  const selectAncestor = (depth: number, id: string) => { setUp((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const selectDescendant = (depth: number, id: string) => { setDown((prev) => prev.slice(0, depth - 1).concat(id)); onFocus(id); };
  const anchorColIdx = cols.findIndex((c) => c.kind === 'anchor');
  anchorIdxRef.current = Math.max(0, anchorColIdx);

  return (
    <div style={{ padding: 'clamp(16px, 4vw, 30px) clamp(16px, 4vw, 40px) 50px', position: 'relative', minHeight: '100%' }}>
      <div style={{ position: 'relative', zIndex: 1 }}>
      {/* Header: titel til venstre, segmenteret kontrol (Fokus/Kolonner) til højre. */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <ViewHeader title="Stamtræ" mb="0" />
        </div>
        <div role="group" aria-label="Visning" style={{ display: 'flex', background: T.surfaceSunken, borderRadius: 10, padding: 3, gap: 3, flex: 'none' }}>
          {(['A', 'B'] as const).map((v) => {
            const active = variant === v;
            return (
              <button key={v} type="button" aria-pressed={active} onClick={() => setVariant(v)} style={{ padding: '7px 16px', borderRadius: 7, border: 0, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, cursor: 'pointer', background: active ? T.surfaceRaised : 'transparent', color: active ? T.bordeaux : T.inkSecondary }}>{v === 'A' ? 'Fokus' : 'Kolonner'}</button>
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
              <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.goldInk, padding: '0 2px 4px', borderBottom: `1px solid ${T.line}` }}>{col.label}</div>
              {col.candidate && col.candidateNote && (
                <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.inkMuted, padding: '0 2px', marginTop: -4, lineHeight: 1.3 }}>{col.candidateNote}</div>
              )}
              {col.candidate ? (
                <>
                  {Object.entries(col.kuldGroups ?? {}).map(([kuld, people]) => (
                    <div key={kuld} style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
                      {kuld !== '—' && (
                        <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.08em', textTransform: 'uppercase', color: T.inkMuted, padding: '2px 2px 0' }}>Kuld {kuld}</div>
                      )}
                      {people.map((p) => (
                        <div key={p.id} onClick={() => onFocus(p.id)} style={{ background: '#faf1dc', border: `1.5px dashed ${T.gold}`, borderRadius: 12, padding: '11px 13px', cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                          <Avatar n={p.name} size={34} />
                          <div style={{ minWidth: 0, flex: 1 }}>
                            {navnLink(p.id, p.name, { fontFamily: T.serif, fontSize: 17, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, () => onFocus(p.id))}
                            {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.inkMuted, marginTop: 2 }}>{p.years}</div>}
                            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.06em', textTransform: 'uppercase', color: T.goldInk, marginTop: 2 }}>muligt slægtled</div>
                          </div>
                          <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                        </div>
                      ))}
                    </div>
                  ))}
                  {col.kilde && (
                    <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.inkMuted, padding: '4px 2px 0', lineHeight: 1.35, borderTop: '1px dashed rgba(34,31,26,.12)', marginTop: 2 }}>Kilde: {col.kilde}</div>
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
                  <div key={p.id} onClick={onTap} style={{ background: sel ? T.bordeauxTint : T.surfaceRaised, border: `1.5px solid ${sel ? T.bordeaux : T.line}`, borderRadius: 12, padding: '11px 13px', cursor: col.kind === 'anchor' ? 'default' : 'pointer', boxShadow: sel ? '0 4px 14px rgba(136,26,51,.12)' : '0 1px 2px rgba(34,31,26,.04)', display: 'flex', alignItems: 'center', gap: 10 }}>
                    {canAnc && <span style={{ color: '#bcae93', fontSize: 17, flex: 'none' }}>‹</span>}
                    <Avatar n={p.name} size={34} />
                    <div style={{ minWidth: 0, flex: 1 }}>
                      {navnLink(p.id, p.name, { fontFamily: T.serif, fontSize: 17, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, onTap)}
                      {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.inkMuted, marginTop: 2 }}>{p.years}</div>}
                    </div>
                    <BookmarkFlag active={hasBookmark(p.id)} onClick={() => onToggleBookmark(p.id)} />
                    {canDesc && <span style={{ color: '#bcae93', fontSize: 17, flex: 'none' }}>›</span>}
                  </div>
                );
              })}
              {col.unconnectedChildren && col.unconnectedChildren.length > 0 && (
                <div style={{ marginTop: 4, paddingTop: 8, borderTop: '1px dashed rgba(34,31,26,.16)' }}>
                  <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.08em', textTransform: 'uppercase', color: T.inkMuted, padding: '0 2px 6px' }}>Uforbundne — placeret efter slægtled, ikke forældreskab</div>
                  {col.unconnectedChildren.map((group) => (
                    <div key={group.grade} style={{ display: 'flex', flexDirection: 'column', gap: 9, marginBottom: 6 }}>
                      <div style={{ fontFamily: T.sans, fontSize: 11, color: T.inkMuted, padding: '0 2px', lineHeight: 1.3 }}>{group.note}</div>
                      {group.people.map(({ person, kilde }) => (
                        <div key={person.id} onClick={() => onFocus(person.id)} style={{ background: '#faf1dc', border: `1.5px dashed ${T.gold}`, borderRadius: 12, padding: '9px 11px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 9 }}>
                          <Avatar n={person.name} size={30} />
                          <div style={{ minWidth: 0, flex: 1 }}>
                            {navnLink(person.id, person.name, { fontFamily: T.serif, fontSize: 16, lineHeight: 1.02, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }, () => onFocus(person.id))}
                            {person.years && <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.inkMuted, marginTop: 1 }}>{person.years}</div>}
                            {kilde && <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.inkMuted, marginTop: 2 }}>Kilde: {kilde}</div>}
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
        <FokusTrae model={model} focusId={focusId} onPick={onPick} onFocus={onFocus} personHref={personHref}
          hasBookmark={hasBookmark} onToggleBookmark={onToggleBookmark} smal={smal} />
      ))}
      </div>
    </div>
  );
}
