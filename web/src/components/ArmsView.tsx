// ---- Slægtens våben ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { useState } from 'react';
import { T } from '../theme';
import { firstSignable, withUrl } from '../data/media';
import type { ArmsItem } from '../data/public';
import { Lightbox } from './Lightbox';
import { ViewHeader, Label, MediaThumb } from './primitives';

export function ArmsView({ arms }: { arms: ArmsItem[] | null }) {
  const [lightbox, setLightbox] = useState<number | null>(null);
  const main = arms?.[0];
  const rest = (arms ?? []).slice(1);
  const mainCrest = main ? firstSignable(main.media) : null; // første signerbare (ikke blindt media[0])
  const variantImgs = rest.map((v) => firstSignable(v.media));
  // Lightbox (Slice A): hoved-våben + alle varianter er ÉT navigerbart sæt.
  const lightboxItems = withUrl([mainCrest, ...variantImgs]);
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <ViewHeader title="Slægtens våben" mb="18px" />
      {!arms ? <div style={{ color: T.muted3 }}>Henter…</div> : (
        <>
          <div style={{ background: T.ink, borderRadius: 16, padding: 26, display: 'flex', gap: 24, alignItems: 'center' }}>
            {mainCrest ? (
              <div style={{ flex: 'none' }}><MediaThumb m={mainCrest} w={150} h={185} radius={10} onClick={() => setLightbox(0)} /></div>
            ) : (
              <div style={{ width: 150, height: 185, borderRadius: 10, background: 'repeating-linear-gradient(45deg,#3a352c 0 9px,#322d25 9px 18px)', border: '1px solid rgba(231,201,143,.2)', flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ fontFamily: T.mono, fontSize: 10, color: T.gold }}>våbenskjold</span></div>
            )}
            <div>
              <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.goldLight }}>Autoriseret våben</div>
              <div style={{ fontSize: 12, color: T.cream, marginTop: 3 }}>Dansk Adels Forenings gældende gengivelse</div>
              <div style={{ fontFamily: T.serif, fontSize: 17, fontStyle: 'italic', lineHeight: 1.45, color: T.paper, marginTop: 14 }}>{main?.blasonering || 'Blasonering ikke registreret.'}</div>
              {main?.note && <div style={{ fontSize: 11.5, color: T.cream, marginTop: 10, lineHeight: 1.45 }}>{main.note}</div>}
            </div>
          </div>
          {rest.length > 0 && (
            <>
              <Label>Øvrige gengivelser &amp; varianter</Label>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 12 }}>
                {rest.map((v, i) => {
                  const vImg = variantImgs[i]; // første signerbare variant-billede
                  return (
                    <div key={v.id} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: 11 }}>
                      {/* Fast .82-aspekt uanset billede/placeholder, så grid-cellerne flugter. */}
                      {vImg ? (
                        <div style={{ width: '100%', aspectRatio: '.82', borderRadius: 8, overflow: 'hidden' }}>
                          <MediaThumb m={vImg} w="100%" h="100%" radius={8}
                            onClick={() => setLightbox(lightboxItems.findIndex((x) => x.id === vImg.id))} />
                        </div>
                      ) : (
                        <div style={{ width: '100%', aspectRatio: '.82', borderRadius: 8, background: 'repeating-linear-gradient(45deg,#ece4d6 0 8px,#e2d8c8 8px 16px)', border: '1px solid rgba(34,31,26,.08)' }} />
                      )}
                      <div style={{ fontFamily: T.serif, fontSize: 14, fontWeight: 600, marginTop: 7, lineHeight: 1.1 }}>{v.note || v.blasonering.slice(0, 40) || 'variant'}</div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </>
      )}
      {lightbox != null && (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </div>
  );
}
