// Delte lazy-kort-bindinger (review 27 P2 udtrukket videre ved W-K1-splittet): maplibre-gl
// (~276 KB gzip) skal IKKE i initial-bundlen — lazy-load kort-komponenterne, så de først
// trækkes ind når en visning der reelt bruger kort (DetailPanel/EstatesView/OverviewMapView)
// rammes. Ét sted for alle tre forbrugere, frem for at hver fil re-definerer sin egen binding.
import { lazy } from 'react';
import { T } from '../theme';

export const GeoMap = lazy(() => import('./GeoMap').then((m) => ({ default: m.GeoMap })));
export const ExpandableMiniMap = lazy(() => import('./MapLightbox').then((m) => ({ default: m.ExpandableMiniMap })));

export const MapFallback = ({ height }: { height?: number | string }) => (
  <div style={{ height: height ?? 160, width: '100%', borderRadius: 14, border: '1px solid rgba(34,31,26,.1)', background: T.panel, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: T.muted2 }}>Indlæser kort…</div>
);
