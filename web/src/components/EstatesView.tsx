// ---- Godser & ejendomme ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { Suspense, useState } from 'react';
import { T } from '../theme';
import { withUrl } from '../data/media';
import type { EstateInfo, EstateItem, EstateOwner } from '../data/public';
import type { Geo } from '../data/types';
import { estatePoints } from '@daa/core';
import { NarrativRenderer } from './NarrativRenderer';
import { Lightbox } from './Lightbox';
import { ViewHeader, Label, MediaThumb } from './primitives';
import { GeoMap, ExpandableMiniMap, MapFallback } from './lazyMaps';

export function EstatesView({ estates, estateId, estate, info, owners, geo, geoLoading, onOpen, onBack, onPickOwner }: {
  estates: EstateItem[] | null; estateId: string | null; estate: EstateItem | null; info: EstateInfo | null;
  owners: EstateOwner[]; geo?: Geo; geoLoading: boolean; onOpen: (id: string) => void; onBack: () => void; onPickOwner: (id: string) => void;
}) {
  const [lightbox, setLightbox] = useState<number | null>(null); // Slice A — kun brugt i detalje-grenen nedenfor
  const [viewMode, setViewMode] = useState<'liste' | 'kort'>('liste');
  if (estateId && estate) {
    const lightboxItems = withUrl(info?.media ?? []);
    const point = geo?.byEstate[estate.id];
    return (
      <div style={{ padding: '26px 40px 50px', maxWidth: 620 }}>
        <div onClick={onBack} style={{ fontSize: 13.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginBottom: 14 }}>‹ Alle godser</div>
        <div style={{ fontFamily: T.serif, fontSize: 32, fontWeight: 600, lineHeight: 1.02 }}>{estate.navn}</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 9 }}>
          {estate.slags && <span style={{ fontSize: 12.5, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '5px 10px', borderRadius: 7 }}>{estate.slags}</span>}
          {info?.sted && <span style={{ fontSize: 12.5, fontWeight: 600, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '5px 10px', borderRadius: 7 }}>⌖ {info.sted}</span>}
        </div>
        {geoLoading ? (
          <div style={{ marginTop: 14 }}><MapFallback height={140} /></div>
        ) : point && (
          <div style={{ marginTop: 14 }}>
            <Suspense fallback={<MapFallback />}>
              <ExpandableMiniMap points={[point]} />
            </Suspense>
          </div>
        )}
        {info && info.media.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 16 }}>
            {lightboxItems.map((m, i) => (
              <MediaThumb key={m.id} m={m} w={180} h={130} radius={11} onClick={() => setLightbox(i)} />
            ))}
          </div>
        )}
        {/* Vis intet under load (info===null); derefter narrativ eller tom-tilstand. */}
        {info && (info.narrativ ? (
          <div style={{ marginTop: 16, fontFamily: T.serif, fontSize: 16.5, lineHeight: 1.6, color: '#3d382f' }}><NarrativRenderer tekst={info.narrativ} onPickPerson={onPickOwner} linkColor={T.bordeaux} inactiveColor={T.muted2} /></div>
        ) : (
          <div style={{ marginTop: 16, border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 14, background: T.paper, fontSize: 13.5, color: T.muted3 }}>Ingen godshistorik registreret endnu.</div>
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
                  {(o.periode || o.rolle) && <div style={{ fontFamily: T.mono, fontSize: 11.5, color: T.muted2 }}>{[o.periode, o.rolle].filter(Boolean).join(' · ')}</div>}
                  <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 1 }}>{o.navn} ›</div>
                </div>
              </div>
            ))}
          </div>
        ) : <div style={{ fontSize: 13.5, color: T.muted3 }}>Ingen registrerede ejere.</div>}
        {lightbox != null && (
          <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
        )}
      </div>
    );
  }
  const points = geo ? estatePoints(geo) : [];
  return (
    <div style={{ padding: '30px 40px 50px', height: viewMode === 'kort' ? 'calc(100vh - 60px)' : undefined, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
        <ViewHeader title="Godser &amp; ejendomme" />
        <div style={{ display: 'flex', gap: 2, background: T.beige, borderRadius: 8, padding: 2, flex: 'none' }}>
          {(['liste', 'kort'] as const).map((m) => (
            <button key={m} onClick={() => setViewMode(m)} style={{
              border: 'none', cursor: 'pointer', fontSize: 12.5, fontWeight: 600, padding: '6px 12px', borderRadius: 6,
              background: viewMode === m ? T.paper : 'transparent', color: viewMode === m ? T.bordeaux : T.muted,
            }}>{m === 'liste' ? 'Liste' : 'Kort'}</button>
          ))}
        </div>
      </div>
      <div style={{ fontSize: 14, color: T.muted, marginTop: 4, marginBottom: 20 }}>Besiddelser knyttet til slægten — klik for ejerrækken gennem tiden.</div>
      {!estates ? <div style={{ color: T.muted3 }}>Henter…</div> : !estates.length ? <div style={{ color: T.muted3 }}>Ingen godser registreret.</div> : viewMode === 'kort' ? (
        geoLoading ? (
          <div style={{ flex: 1, minHeight: 0 }}><MapFallback height="100%" /></div>
        ) : points.length ? (
          <div style={{ flex: 1, minHeight: 0 }}>
            <Suspense fallback={<MapFallback height="100%" />}>
              <GeoMap points={points} mode="explorer" onPointPress={(p) => p.estateId && onOpen(p.estateId)} />
            </Suspense>
          </div>
        ) : <div style={{ color: T.muted3 }}>Ingen godser er kortlagt endnu.</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(220px,1fr))', gap: 12 }}>
          {estates.map((e) => (
            <div key={e.id} onClick={() => onOpen(e.id)} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: 15, cursor: 'pointer', boxShadow: '0 1px 2px rgba(34,31,26,.03)' }}>
              <span style={{ width: 36, height: 36, borderRadius: 8, background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 17, color: T.bordeaux }}>⌂</span>
              <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 11 }}>{e.navn}</div>
              <div style={{ fontSize: 12.5, color: T.muted, marginTop: 3 }}>{[e.slags, e.ownerCount ? `${e.ownerCount} tilknytning${e.ownerCount === 1 ? '' : 'er'}` : ''].filter(Boolean).join(' · ') || '—'}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
