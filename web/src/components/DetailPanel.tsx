// ---- Person-detalje (højre panel) ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { Suspense, useEffect, useState } from 'react';
import { T } from '../theme';
import { initials } from '../data/format';
import { childrenOf, parentsOf } from '../data/model';
import { pickPortrait, withUrl } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { lifeJourney } from '@daa/core';
import { NarrativRenderer } from './NarrativRenderer';
import { Lightbox } from './Lightbox';
import { MediaThumb, BookmarkFlag, Label } from './primitives';
import { ExpandableMiniMap, MapFallback } from './lazyMaps';

export function DetailPanel({ model, focusId, detail, onPick, backName, onBack, onClose, onFocusTree, onRelate, isMe, onToggleMe, isBookmarked, onToggleBookmark, geoLoading }: {
  model: Model; focusId: string; detail: PersonDetailData | null; onPick: (id: string) => void;
  backName: string | null; onBack: () => void; onClose?: () => void; onFocusTree: () => void; onRelate: () => void;
  isMe: boolean; onToggleMe: () => void; isBookmarked: boolean; onToggleBookmark: () => void;
  geoLoading: boolean;
}) {
  // Lightbox (Slice A): useState skal stå FØR den betingede return nedenfor (Rules of Hooks) —
  // portræt + galleri bliver ÉT navigerbart sæt (portræt først), så pil-tasterne bladrer gennem
  // alle personens billeder uanset hvilket der blev klikket på.
  const [lightbox, setLightbox] = useState<number | null>(null);
  // Udgave-versionsvælger (§7.18): index i detail.bioVersions, nulstillet når man skifter person
  // (ny focusId) — ellers ville et tidligere valgt ældre-udgave-valg lække over på næste person.
  const [bioVersionIdx, setBioVersionIdx] = useState(0);
  useEffect(() => { setBioVersionIdx(0); }, [focusId]);
  const p = model.byId[focusId];
  if (!p) return null;
  const parents = parentsOf(model, focusId);
  const spouses = (model.indexes.spousesBy[focusId] ?? []);
  const children = childrenOf(model, focusId);
  const linjer = model.lineage?.byPerson[focusId] ?? [];
  const sources = model.sourcesBy?.[focusId] ?? [];
  // Portræt = hovedbilledet; galleri = de øvrige medier (materiale). RLS-gatet i data-laget.
  const media = detail?.media ?? [];
  const portrait = pickPortrait(media);
  const gallery = media.filter((m) => m.url && m.id !== portrait?.id);
  const lightboxItems = withUrl([portrait, ...gallery]);
  // Proveniens: er personen foldet af flere DAA-poster (samme_som), vis hvilke linjer/numre.
  const mergedFrom = p.mergedFrom ?? [];
  const proveniens =
    mergedFrom.length > 1
      ? mergedFrom
          .map((m) => {
            const navn = m.linje ? model.lineage?.navn[m.linje] ?? `linje ${m.linje}` : 'ukendt linje';
            const ref = m.linje && m.nr != null ? ` (${m.linje}-${m.nr})` : '';
            return `${navn}${ref}`;
          })
          .join(' og ')
      : null;
  return (
    <>
    <div data-scroll style={{ flex: 'none', width: '50%', maxWidth: 760, minWidth: 430, borderLeft: '1px solid rgba(34,31,26,.1)', background: T.paper, overflowY: 'auto' }}>
      <div style={{ padding: '24px 24px 36px' }}>
        {(backName || onClose) && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 14 }}>
            {backName ? (
              <div onClick={onBack} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>‹ Tilbage til {backName}</div>
            ) : <span />}
            {/* Luk detaljen (§5): navigerer til /stamtrae → fuldt-bredt træ, samme centrum. */}
            {onClose && (
              <div onClick={onClose} title="Luk detalje (Esc)" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.muted, cursor: 'pointer', padding: '4px 9px', borderRadius: 8, background: T.panel, border: '1px solid rgba(34,31,26,.12)', flex: 'none' }}>
                Luk
                <svg viewBox="0 0 24 24" width={13} height={13} fill="none" stroke={T.muted} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
              </div>
            )}
          </div>
        )}
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
          {portrait ? (
            <div style={{ flex: 'none' }}><MediaThumb m={portrait} w={92} h={116} radius={11} onClick={() => setLightbox(0)} /></div>
          ) : (
            <div style={{ width: 92, height: 116, borderRadius: 11, background: 'repeating-linear-gradient(45deg,#ece4d6 0 9px,#e2d8c8 9px 18px)', border: '1px solid rgba(34,31,26,.1)', flex: 'none', display: 'flex', alignItems: 'flex-end', padding: 8 }}><span style={{ fontFamily: T.mono, fontSize: 9, color: T.muted }}>portræt</span></div>
          )}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1, fontWeight: 600, minWidth: 0 }}>{p.name}</div>
              <BookmarkFlag active={isBookmarked} onClick={onToggleBookmark} />
            </div>
            {p.years && <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 6 }}>{p.years}</div>}
            {/* Badges: ★ Dig + Linje(r) + titel. */}
            {(isMe || linjer.length > 0 || p.title) && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 9 }}>
                {isMe && <div style={{ fontFamily: T.sans, fontSize: 10.5, fontWeight: 700, color: T.paper, background: T.bordeaux, padding: '4px 9px', borderRadius: 6 }}>★ Dig</div>}
                {linjer.map((lk) => (
                  <div key={lk} style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '4px 8px', borderRadius: 6 }}>{model.lineage?.navn[lk] ?? `Linje ${lk}`}</div>
                ))}
                {p.title && <div style={{ fontSize: 11, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '4px 9px', borderRadius: 6 }}>{p.title}</div>}
              </div>
            )}
            {proveniens && (
              <div style={{ fontFamily: T.sans, fontSize: 11, color: T.muted2, marginTop: 8, lineHeight: 1.45 }}>
                Optræder i Aarbogen som {proveniens}.
              </div>
            )}
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

        {/* Udgave-versionsvælger (§7.18): kun vist når personen har mere end én offentlig
            DAA-udgave-bio (fx foldet 1939 + 2018-20-post) — ellers uændret enkelt-visning. */}
        {(() => {
          const versions = detail?.bioVersions ?? [];
          const active = versions[bioVersionIdx] ?? versions[0];
          const bioText = active?.tekst ?? detail?.bio ?? '';
          if (!bioText) return null;
          return (
            <div style={{ marginTop: 14 }}>
              {versions.length > 1 && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 9 }}>
                  {versions.map((v, i) => (
                    <div key={v.sourceId ?? i} onClick={() => setBioVersionIdx(i)} style={{
                      fontFamily: T.mono, fontSize: 9.5, fontWeight: 600, cursor: 'pointer',
                      color: i === bioVersionIdx ? T.paper : T.muted,
                      background: i === bioVersionIdx ? T.bordeaux : T.beige,
                      border: '1px solid rgba(34,31,26,.12)', padding: '4px 9px', borderRadius: 6,
                    }}>
                      {v.udgave || (v.aar != null ? String(v.aar) : 'udgave')}
                    </div>
                  ))}
                </div>
              )}
              {versions.length > 1 && bioVersionIdx > 0 && (
                <div style={{ fontFamily: T.sans, fontSize: 10.5, color: T.muted2, marginBottom: 5 }}>Tidligere udgave</div>
              )}
              <div style={{ fontSize: 13.5, lineHeight: 1.55, color: '#3d382f' }}>
                <NarrativRenderer tekst={bioText} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} />
              </div>
            </div>
          );
        })()}

        {/* Livskort: kun hvis personen har mindst ét geo-punkt (undgår tom-boks-støj for de fleste). */}
        {/* geo er tomt indtil loadGeo() er kaldt (review 27 P3, "lazy geo-kæde") — de FLESTE
            personer ender uden geo-punkter, så vi viser IKKE en midlertidig boks mens den henter
            (ville ellers dukke op og forsvinde igen for langt de fleste — "skal ikke flimre").
            Godser-kort/Slægtens kort er eksplicitte kort-flader med egen "Indlæser kort…"-plads;
            minikortet her er blot spekulativt. */}
        {!geoLoading && model.geo && lifeJourney(model.geo, focusId).length > 0 && (
          <div style={{ marginTop: 14 }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted2, marginBottom: 6 }}>Livsrejse</div>
            <Suspense fallback={<MapFallback />}>
              <ExpandableMiniMap points={lifeJourney(model.geo, focusId)} />
            </Suspense>
          </div>
        )}

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

        {gallery.length > 0 && (
          <>
            <Label>Materiale</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {gallery.map((m) => (
                <MediaThumb key={m.id} m={m} w={84} h={84} radius={9}
                  onClick={() => setLightbox(lightboxItems.findIndex((x) => x.id === m.id))} />
              ))}
            </div>
          </>
        )}

        {detail === null && <div style={{ marginTop: 18, fontSize: 12, color: T.muted3 }}>Henter detaljer…</div>}

        {/* Kilde i Aarbogen (§ + trykt værk + "Linje X, nr. N"). */}
        {sources.length > 0 && (
          <>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '22px 0 8px' }}>Kilde i Aarbogen</div>
            {sources.map((s, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 0', borderBottom: '1px solid rgba(34,31,26,.08)' }}>
                <span style={{ fontFamily: T.serif, fontSize: 18, color: T.bordeaux, flex: 'none' }}>§</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.ink, lineHeight: 1.25 }}>{s.work}</div>
                  {s.ref && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 2 }}>{s.ref}</div>}
                </div>
              </div>
            ))}
          </>
        )}

        {/* Handlinger: fokus · slægtskab · "det er mig"-toggle. */}
        <div onClick={onFocusTree} style={{ marginTop: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: '#3d382f', background: T.panel, border: '1.5px solid rgba(34,31,26,.16)', padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>
          <span style={{ fontSize: 13 }}>⊹</span> Sæt i fokus i stamtræet
        </div>
        <div style={{ marginTop: 9, display: 'flex', gap: 9 }}>
          <div onClick={onRelate} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.paper, background: T.bordeaux, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>Find slægtskab</div>
          <div onClick={onToggleMe} title={isMe ? 'Fjern din markering' : 'Marker denne person som dig'} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: isMe ? T.bordeaux : '#3d382f', background: isMe ? '#f8ecef' : T.panel, border: `1.5px solid ${isMe ? T.bordeaux : 'rgba(34,31,26,.16)'}`, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>{isMe ? '★ Dette er dig' : 'Det er mig'}</div>
        </div>
      </div>
    </div>
    {lightbox != null && (
      <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
    )}
    </>
  );
}
