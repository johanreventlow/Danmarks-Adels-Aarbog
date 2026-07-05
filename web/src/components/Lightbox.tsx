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

export type LightboxItem = { id: string; url: string | null; titel?: string | null; kunstner?: string | null; datering?: string | null };

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

  return (
    <div onClick={onClose} style={{
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
      <img src={m.url} alt={m.titel || 'billede'} onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: '92vw', maxHeight: '82vh', objectFit: 'contain', borderRadius: 6, boxShadow: '0 24px 70px rgba(0,0,0,.55)' }} />
      {(cap || items.length > 1) && (
        <div onClick={(e) => e.stopPropagation()} style={{ marginTop: 14, textAlign: 'center', maxWidth: '80vw' }}>
          {cap && <div style={{ fontFamily: T.sans, fontSize: 13, color: T.cream }}>{cap}</div>}
          {items.length > 1 && (
            <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted3, marginTop: 4 }}>{index + 1} / {items.length}</div>
          )}
        </div>
      )}
    </div>
  );
}
