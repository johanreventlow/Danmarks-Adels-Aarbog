// GeoMap (mobil) — WebView der hoster MapLibre GL JS via CDN, samme kort-logik og gratis
// demo-vektorstil som web/src/components/GeoMap.tsx. Ingen native modul, ingen custom dev
// client-genbygning: virker i almindelig Expo Go. Se claude.md kort-plan for begrundelsen
// (native @maplibre/maplibre-react-native kan efterfølges senere — grænsefladen her er ens).
//
// v1-forenkling: punkterne bages ind i HTML'en ved mount (ingen postMessage-datastrøm efter
// load) — komponenten remountes naturligt når screenet skifter (ny person/gods), så det er
// tilstrækkeligt for nu. Klynge-/marker-logikken er BEVIDST duplikeret fra web (vanilla JS i en
// statisk HTML-streng kan ikke importere web's TS-modul) — en fælles kerne er en senere /simplify.
import { useEffect, useMemo, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import { boundsOf } from '../data/geoSelectors';
import { Colors, Radius } from '../theme/tokens';
import type { GeoPoint } from '../data/types';

const DEMO_STYLE = 'https://demotiles.maplibre.org/style.json';
// Matcher web/package.json's maplibre-gl-version. SRI-hashes beregnet lokalt via
// `curl -sL https://unpkg.com/maplibre-gl@X.Y.Z/dist/maplibre-gl.js | openssl dgst -sha384 -binary | openssl base64 -A`
// (samme for .css) — genberegn begge ved enhver version-bump, ellers fejler CDN-loadet stille.
const MAPLIBRE_VERSION = '5.24.0';
const MAPLIBRE_JS_SRI = 'sha384-5+cfbwT0iiub6VsQAdn6yz16nr6sDiQoHx6tm4O8OVYXHYOxcffFmCJBL0dgdvGp';
const MAPLIBRE_CSS_SRI = 'sha384-uTttxo/aOKbdE5RlD/SPzSDoDmNvGlUYPjONi2MN/b7c9HPSvW07OIuyP7uL6jxK';

function buildHtml(points: GeoPoint[], mode: 'mini' | 'explorer'): string {
  const bounds = boundsOf(points);
  const fitBounds = bounds
    ? `[[${bounds.minLon},${bounds.minLat}],[${bounds.maxLon},${bounds.maxLat}]]`
    : null;
  const interactive = mode === 'explorer';
  // Pinned nøjagtig samme version som web's npm-installerede maplibre-gl (package.json) +
  // Subresource Integrity — undgår at et kompromitteret CDN kan injicere kode (sikkerhedsreview).
  // Ved version-bump: opdatér MAPLIBRE_VERSION + de to SRI-hashes samlet (se README-note nedenfor).
  return `<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<script src="https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION}/dist/maplibre-gl.js" integrity="${MAPLIBRE_JS_SRI}" crossorigin="anonymous"></script>
<link href="https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION}/dist/maplibre-gl.css" integrity="${MAPLIBRE_CSS_SRI}" crossorigin="anonymous" rel="stylesheet" />
<style>html,body,#map{margin:0;padding:0;height:100%;width:100%;background:${Colors.paperBg}}</style>
</head><body><div id="map"></div><script>
  // escape </script>-breakout + linjeseparatorer i WebView-HTML (review 27 S1)
  const POINTS = ${JSON.stringify(points).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029')};
  const map = new maplibregl.Map({
    container: 'map', style: '${DEMO_STYLE}', center: [10, 55.5], zoom: 5,
    interactive: ${interactive}, attributionControl: ${interactive},
  });
  ${interactive ? "map.addControl(new maplibregl.NavigationControl({showCompass:false}),'top-right');" : ''}
  map.on('load', () => {
    map.addSource('geo-points', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: POINTS.map(p => ({
        type: 'Feature', geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
        properties: { pointJson: JSON.stringify(p) },
      })) },
      cluster: true, clusterRadius: 50, clusterMaxZoom: 14,
    });
    map.addLayer({ id: 'clusters', type: 'circle', source: 'geo-points', filter: ['has','point_count'],
      paint: { 'circle-color': '${Colors.bordeaux}', 'circle-opacity': 0.85,
        'circle-radius': ['step', ['get','point_count'], 14, 5, 18, 20, 24] } });
    map.addLayer({ id: 'cluster-count', type: 'symbol', source: 'geo-points', filter: ['has','point_count'],
      layout: { 'text-field': '{point_count_abbreviated}', 'text-size': 11 },
      paint: { 'text-color': '#fff' } });
    map.addLayer({ id: 'unclustered-point', type: 'circle', source: 'geo-points', filter: ['!',['has','point_count']],
      paint: { 'circle-color': '${Colors.bordeaux}', 'circle-radius': 7,
        'circle-stroke-width': 2, 'circle-stroke-color': '${Colors.paperBg}' } });
    map.on('click', 'clusters', (e) => {
      const f = e.features[0]; const id = f.properties.cluster_id;
      map.getSource('geo-points').getClusterExpansionZoom(id).then((zoom) => {
        map.easeTo({ center: f.geometry.coordinates, zoom });
      });
    });
    map.on('click', 'unclustered-point', (e) => {
      const raw = e.features[0]?.properties?.pointJson;
      if (raw && window.ReactNativeWebView) window.ReactNativeWebView.postMessage(raw);
    });
    ${fitBounds ? `map.fitBounds(${fitBounds}, { padding: ${mode === 'mini' ? 24 : 60}, maxZoom: ${mode === 'mini' ? 12 : 15}, duration: 0 });` : ''}
  });
  ${mode === 'mini' ? "map.scrollZoom.disable(); map.dragPan.disable(); map.dragRotate.disable(); map.doubleClickZoom.disable(); map.touchZoomRotate.disable();" : ''}
</script></body></html>`;
}

export function GeoMap({
  points, mode = 'explorer', onPointPress, height,
}: {
  points: GeoPoint[];
  mode?: 'mini' | 'explorer';
  onPointPress?: (point: GeoPoint) => void;
  height?: number;
}) {
  const onPointPressRef = useRef(onPointPress);
  // Ref-opdatering SKAL ske i en effect, ikke under render (react-hooks/refs).
  useEffect(() => { onPointPressRef.current = onPointPress; });
  // useMemo: undgår at genopbygge (og dermed genindlæse) HTML-strengen ved hver render —
  // kun når selve punkterne eller mode reelt ændrer sig.
  const html = useMemo(() => buildHtml(points, mode), [points, mode]);

  const handleMessage = (e: WebViewMessageEvent) => {
    try {
      const point = JSON.parse(e.nativeEvent.data) as GeoPoint;
      onPointPressRef.current?.(point);
    } catch {
      // ignorér ugyldige beskeder
    }
  };

  return (
    <View style={[styles.container, { height: height ?? (mode === 'mini' ? 160 : undefined), flex: height ? undefined : mode === 'mini' ? undefined : 1 }]}>
      <WebView
        originWhitelist={['*']}
        source={{ html }}
        onMessage={handleMessage}
        scrollEnabled={false}
        style={{ backgroundColor: Colors.paperBg }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    borderRadius: Radius.card,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(34,31,26,0.1)',
  },
});
