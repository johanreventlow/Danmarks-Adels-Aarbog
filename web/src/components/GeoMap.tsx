// GeoMap — delt kort-komponent (godskort v1). MapLibre GL JS + gratis demo-vektorstil
// ("let løsning først" — se claude.md kort-plan; opgraderes senere til selvhostet Protomaps).
// mode='mini': lille, statisk (ingen zoom/pan) forhåndsvisning — til gods-/person-detaljer.
// mode='explorer': fuld interaktiv, klynget oversigt — til gods-/overbliks-lister.
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { useEffect, useRef } from 'react';
import { boundsOf } from '@daa/core';
import type { GeoPoint } from '../data/types';
import { T } from '../theme';

const DEMO_STYLE = 'https://demotiles.maplibre.org/style.json';

export function GeoMap({
  points, mode = 'explorer', onPointPress, height,
}: {
  points: GeoPoint[];
  mode?: 'mini' | 'explorer';
  onPointPress?: (point: GeoPoint) => void;
  height?: number | string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const onPointPressRef = useRef(onPointPress);
  // Ref-opdatering SKAL ske i en effect, ikke under render (react-hooks/refs).
  useEffect(() => { onPointPressRef.current = onPointPress; });

  // Kort oprettes ÉN gang pr. mount — points-opdateringer sker via separat effect (data-kilde).
  useEffect(() => {
    if (!containerRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: DEMO_STYLE,
      center: [10, 55.5], // Danmark/Holsten — slægtens kerneområde
      zoom: 5,
      interactive: mode === 'explorer',
      attributionControl: mode === 'explorer' ? undefined : false,
    });
    mapRef.current = map;
    if (mode === 'explorer') map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

    map.on('load', () => {
      map.addSource('geo-points', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] },
        cluster: true, clusterRadius: 50, clusterMaxZoom: 14,
      });
      map.addLayer({
        id: 'clusters', type: 'circle', source: 'geo-points', filter: ['has', 'point_count'],
        paint: {
          'circle-color': T.bordeaux,
          'circle-opacity': 0.85,
          'circle-radius': ['step', ['get', 'point_count'], 14, 5, 18, 20, 24],
        },
      });
      map.addLayer({
        id: 'cluster-count', type: 'symbol', source: 'geo-points', filter: ['has', 'point_count'],
        layout: { 'text-field': '{point_count_abbreviated}', 'text-size': 11 },
        paint: { 'text-color': '#fff' },
      });
      map.addLayer({
        id: 'unclustered-point', type: 'circle', source: 'geo-points', filter: ['!', ['has', 'point_count']],
        paint: {
          'circle-color': T.bordeaux, 'circle-radius': 7,
          'circle-stroke-width': 2, 'circle-stroke-color': T.paper,
        },
      });

      map.on('click', 'clusters', (e) => {
        const feature = e.features?.[0];
        if (!feature) return;
        const clusterId = feature.properties?.cluster_id;
        const source = map.getSource('geo-points') as maplibregl.GeoJSONSource;
        source.getClusterExpansionZoom(clusterId).then((zoom) => {
          map.easeTo({ center: (feature.geometry as GeoJSON.Point).coordinates as [number, number], zoom });
        }).catch(() => {});
      });
      map.on('click', 'unclustered-point', (e) => {
        const feature = e.features?.[0];
        const raw = feature?.properties?.pointJson;
        if (raw && onPointPressRef.current) onPointPressRef.current(JSON.parse(raw));
      });
      ['clusters', 'unclustered-point'].forEach((layer) => {
        map.on('mouseenter', layer, () => { map.getCanvas().style.cursor = 'pointer'; });
        map.on('mouseleave', layer, () => { map.getCanvas().style.cursor = ''; });
      });
    });

    if (mode === 'mini') {
      map.scrollZoom.disable(); map.dragPan.disable(); map.dragRotate.disable();
      map.doubleClickZoom.disable(); map.touchZoomRotate.disable();
    }

    return () => { map.remove(); mapRef.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- kortet genskabes bevidst ikke ved mode-skift
  }, []);

  // Data-opdatering: separat fra opsætning, så et nyt points-array ikke genskaber hele kortet.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const apply = () => {
      const source = map.getSource('geo-points') as maplibregl.GeoJSONSource | undefined;
      if (!source) return;
      source.setData({
        type: 'FeatureCollection',
        features: points.map((p) => ({
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
          properties: { pointJson: JSON.stringify(p) },
        })),
      });
      const bounds = boundsOf(points);
      if (bounds) {
        map.fitBounds(
          [[bounds.minLon, bounds.minLat], [bounds.maxLon, bounds.maxLat]],
          { padding: mode === 'mini' ? 24 : 60, maxZoom: mode === 'mini' ? 12 : 15, duration: 0 },
        );
      }
    };
    if (map.isStyleLoaded()) apply(); else map.once('load', apply);
  }, [points, mode]);

  return (
    <div
      ref={containerRef}
      style={{
        height: height ?? (mode === 'mini' ? 160 : '100%'),
        width: '100%',
        borderRadius: 14,
        overflow: 'hidden',
        border: '1px solid rgba(34,31,26,.1)',
      }}
    />
  );
}
