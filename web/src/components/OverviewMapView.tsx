// ---- Slægtens kort (overbliks-kort) ----
// Fuldskærms-kort over ALLE geo-punkter (personhændelser + godser), filtrerbart pr. linje.
// v1: kun linje-filter (type-filter/år-slider/"nær mig" er senere skiver — se claude.md kort-plan).
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { Suspense, useState, type CSSProperties } from 'react';
import { T } from '../theme';
import type { Model } from '../data/types';
import { filterByLineage } from '@daa/core';
import { ViewHeader } from './primitives';
import { GeoMap, MapFallback } from './lazyMaps';

export function OverviewMapView({ model, geoLoading, onPickPerson, onPickEstate }: {
  model: Model | null; geoLoading: boolean; onPickPerson: (id: string) => void; onPickEstate: (id: string) => void;
}) {
  const [linje, setLinje] = useState<string | null>(null);
  const allPoints = model?.geo?.points ?? [];
  const linjeList = model?.lineage?.list ?? [];
  const points = linje ? filterByLineage(allPoints, model?.lineage?.byPerson ?? {}, linje, { includeNonPerson: true }) : allPoints;
  const chip = (active: boolean): CSSProperties => ({
    fontSize: 11.5, fontWeight: 600, padding: '6px 12px', borderRadius: 999, cursor: 'pointer',
    border: '1px solid ' + (active ? 'rgba(136,26,51,.3)' : 'rgba(34,31,26,.1)'),
    background: active ? '#f4e2e6' : T.beige, color: active ? T.bordeaux : T.muted,
  });
  return (
    <div style={{ padding: '30px 40px 0', height: 'calc(100vh - 60px)', display: 'flex', flexDirection: 'column' }}>
      <ViewHeader title="Slægtens kort" />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 12 }}>
        {geoLoading ? 'Indlæser kortlagte steder…' : `${points.length} ${points.length === 1 ? 'sted' : 'steder'} kortlagt${linje ? ` for ${linjeList.find((l) => l.linje === linje)?.navn ?? 'linje ' + linje}` : ' — flere følger efterhånden som slægtens steder kortlægges'}.`}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 16 }}>
        <button onClick={() => setLinje(null)} style={chip(linje === null)}>Hele slægten</button>
        {linjeList.map((l) => (
          <button key={l.linje} onClick={() => setLinje(l.linje)} style={chip(linje === l.linje)}>
            {l.navn ?? `Linje ${l.linje}`}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, paddingBottom: 24 }}>
        {geoLoading ? (
          <MapFallback height="100%" />
        ) : points.length ? (
          <Suspense fallback={<MapFallback height="100%" />}>
            <GeoMap
              points={points}
              mode="explorer"
              onPointPress={(p) => { if (p.personId) onPickPerson(p.personId); else if (p.estateId) onPickEstate(p.estateId); }}
            />
          </Suspense>
        ) : <div style={{ color: T.muted3 }}>Ingen steder kortlagt endnu{linje ? ' for denne linje' : ''}.</div>}
      </div>
    </div>
  );
}
