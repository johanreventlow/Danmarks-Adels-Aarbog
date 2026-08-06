// Lightbox (mediehåndtering Slice A — planlagt i docs/superpowers/plans/
// 2026-07-05-billedstoerrelser-artikler-lightbox.md). Fuldskærms-overlay til at se et billede i
// fuld størrelse. Bevidst KUN statisk visning (bruger-afklaring 2026-07-05: intet pinch-zoom).
// Selvstændig implementering (ikke delt kode) — spejles på mobile, samme princip som
// buildBidirectionalColumns: ét beskrevet interaktionsmønster, to uafhængige implementeringer.
// `url` er i dag den samme fil som thumbnailen (kun én størrelse findes endnu) — Slice B
// (media_variant, planen §1-2) skifter kaldernes url til en 'large'-variant; denne komponent
// rører ikke ved dét, den viser bare den url den får.
import { useEffect } from 'react';
import { T } from '../theme';
import { mediaCaption } from '../data/media';

// MM-11: kilde_url whitelist — kun http(s)-URLs vises som klikbart link (spejler
// MediaDetaljeOverlay.tsx's KILDE_URL_RE, som håndhæver det samme ved skrivning).
const KILDE_URL_RE = /^https?:\/\//i;

// Alle nye felter valgfrie (bagudkompatibelt — narrativ-indlejrede billeder (EmbeddedMedia) og
// andre kaldere uden medie-metadata sender bare id/url/titel/kunstner/datering som hidtil).
export type LightboxItem = {
  id: string; url: string | null; titel?: string | null; kunstner?: string | null; datering?: string | null;
  altTekst?: string | null; kreditlinje?: string | null; kildeUrl?: string | null;
  kildeInstitution?: string | null; beskrivelse?: string | null; dateringFakt?: string | null;
};

export function Lightbox({ items, index, onClose, onNavigate }: {
  items: LightboxItem[];
  index: number;
  onClose: () => void;
  onNavigate: (nextIndex: number) => void;
}) {
  const harForrige = index > 0;
  const harNaeste = index < items.length - 1;

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
      else if (e.key === 'ArrowLeft' && harForrige) onNavigate(index - 1);
      else if (e.key === 'ArrowRight' && harNaeste) onNavigate(index + 1);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [index, harForrige, harNaeste, onClose, onNavigate]);

  const m = items[index];
  if (!m?.url) return null;
  const cap = mediaCaption(m);
  // MM-11: kildelinket vises kun for en gyldig http(s)-url — alt andet (fx en injiceret
  // 'javascript:'-streng) udelades stille i stedet for at blive et klikbart, aktivt link.
  const kildeLinkOk = !!m.kildeUrl && KILDE_URL_RE.test(m.kildeUrl);
  const visInfoBlok = cap || items.length > 1 || m.kreditlinje || kildeLinkOk || m.beskrivelse;

  return (
    <div onClick={onClose} data-overlay style={{
      position: 'fixed', inset: 0, background: 'rgba(10,8,6,.92)', zIndex: 300,
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24,
    }}>
      <span onClick={onClose} title="Luk (Esc)"
        style={{ position: 'absolute', top: 18, right: 22, fontSize: 30, lineHeight: 1, color: T.paper, cursor: 'pointer' }}>
        ×
      </span>
      {items.length > 1 && harForrige && (
        <span onClick={(e) => { e.stopPropagation(); onNavigate(index - 1); }} title="Forrige billede"
          style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', fontSize: 38, color: T.paper, cursor: 'pointer', userSelect: 'none' }}>
          ‹
        </span>
      )}
      {items.length > 1 && harNaeste && (
        <span onClick={(e) => { e.stopPropagation(); onNavigate(index + 1); }} title="Næste billede"
          style={{ position: 'absolute', right: 14, top: '50%', transform: 'translateY(-50%)', fontSize: 38, color: T.paper, cursor: 'pointer', userSelect: 'none' }}>
          ›
        </span>
      )}
      <img src={m.url} alt={m.altTekst || m.titel || 'billede'} onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: '92vw', maxHeight: '82vh', objectFit: 'contain', borderRadius: 6, boxShadow: '0 24px 70px rgba(0,0,0,.55)' }} />
      {visInfoBlok && (
        <div onClick={(e) => e.stopPropagation()} style={{ marginTop: 14, textAlign: 'center', maxWidth: '80vw' }}>
          {cap && <div style={{ fontFamily: T.sans, fontSize: 14, color: T.cream }}>{cap}</div>}
          {/* Kreditlinjen vises ALTID når udfyldt — aldrig bag fold (juridisk krav ved
              CC-licenser, fx Deutsche Digitale Bibliothek kræver deres Quellenangabe vist). */}
          {m.kreditlinje && (
            <div style={{ fontFamily: T.sans, fontSize: 12, color: T.muted3, marginTop: 4 }}>{m.kreditlinje}</div>
          )}
          {kildeLinkOk && (
            <div style={{ marginTop: 4 }}>
              <a href={m.kildeUrl!} target="_blank" rel="noopener noreferrer" onClick={(e) => e.stopPropagation()}
                style={{ fontFamily: T.sans, fontSize: 12, color: T.cream }}>
                Se hos {m.kildeInstitution || 'kilden'} ↗
              </a>
            </div>
          )}
          {m.beskrivelse && (
            <details onClick={(e) => e.stopPropagation()}
              style={{ marginTop: 6, textAlign: 'left', fontFamily: T.sans, fontSize: 12, color: T.cream }}>
              <summary style={{ cursor: 'pointer', textAlign: 'center' }}>Om billedet</summary>
              <div style={{ marginTop: 4 }}>{m.beskrivelse}</div>
            </details>
          )}
          {items.length > 1 && (
            <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted3, marginTop: 4 }}>{index + 1} / {items.length}</div>
          )}
        </div>
      )}
    </div>
  );
}
