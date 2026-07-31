// MapLightbox — forstørret, interaktiv udgave af et mini-kort i et fuldskærms-overlay.
// Spejler Lightbox.tsx's overlay-chrome (mørk backdrop, backdrop-klik, Escape, ×-luk), men
// Lightbox er bevidst hårdkodet til <img> og mobile-spejlet, så vi genbruger ikke den — vi
// gengiver mønsteret her og renderer i stedet GeoMap i explorer-mode (zoom/pan).
// Ren betragter: intet onPointPress (bruger-afklaring 2026-07-05 — punkter navigerer IKKE fra
// det forstørrede kort; al navigation sker fra de rigtige explorer-kort andre steder).
// Portal til document.body: ExpandableMiniMap kaldes DYBT i indholdstræet, så et fixed-overlay
// ville ellers arve en ancestor-stacking-context (fx TreeViews zIndex:1) og male BAG header/
// sidebar. Portalen hejser overlayet til body-niveau, så backdrop dækker hele viewporten.
import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { GeoMap } from './GeoMap';
import type { GeoPoint } from '../data/types';
import { T } from '../theme';

export function MapLightbox({ points, onClose }: { points: GeoPoint[]; onClose: () => void }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return createPortal(
    <div
      data-testid="map-lightbox-backdrop"
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, background: 'rgba(10,8,6,.92)', zIndex: 300,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24,
      }}
    >
      <span onClick={onClose} title="Luk (Esc)"
        style={{ position: 'absolute', top: 18, right: 22, fontSize: 30, lineHeight: 1, color: T.paper, cursor: 'pointer' }}>
        ×
      </span>
      {/* Kort-container fanger sine egne klik (stopPropagation), så pan/zoom-træk ikke bobler op
          og lukker overlayet — kun backdrop-margin + × lukker. */}
      <div
        data-testid="map-lightbox-content"
        onClick={(e) => e.stopPropagation()}
        style={{ width: 'min(1100px, 92vw)', height: '82vh', borderRadius: 10, overflow: 'hidden', boxShadow: '0 24px 70px rgba(0,0,0,.55)' }}
      >
        <GeoMap points={points} mode="explorer" height="100%" />
      </div>
      <div onClick={(e) => e.stopPropagation()}
        style={{ marginTop: 12, fontFamily: T.mono, fontSize: 11, letterSpacing: '.08em', color: T.muted3 }}>
        Zoom og træk for at udforske
      </div>
    </div>,
    document.body,
  );
}

// ExpandableMiniMap — mini-kort der åbner MapLightbox ved klik. Erstatter de rå <GeoMap mode="mini">
// -kald: en gennemsigtig klik-overlay ovenpå fanger ALLE klik og åbner det forstørrede kort (i stedet
// for at slås med MapLibres interne lag-klik-handlers på mini'en). Hele fladen er klikbar — samme UX
// som billed-thumbnails — med en lille ⤢-badge som affordance.
export function ExpandableMiniMap({ points }: { points: GeoPoint[] }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ position: 'relative' }}>
      <GeoMap points={points} mode="mini" />
      <div
        data-testid="minimap-expand-trigger"
        onClick={() => setOpen(true)}
        title="Forstør kort"
        style={{
          position: 'absolute', inset: 0, cursor: 'pointer',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-end', padding: 8,
        }}
      >
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 5,
          fontFamily: T.mono, fontSize: 10.5, fontWeight: 600, letterSpacing: '.06em', color: T.ink,
          background: 'rgba(247,244,239,.92)', border: '1px solid rgba(34,31,26,.12)', borderRadius: 7,
          padding: '4px 8px', boxShadow: '0 1px 4px rgba(34,31,26,.12)',
        }}>
          ⤢ Forstør
        </span>
      </div>
      {open && <MapLightbox points={points} onClose={() => setOpen(false)} />}
    </div>
  );
}
