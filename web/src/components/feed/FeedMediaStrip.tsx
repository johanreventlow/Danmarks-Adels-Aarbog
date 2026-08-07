import { useState } from 'react';
import { T } from '../../theme';
import { Lightbox } from '../Lightbox';
import type { WebFeedMediaItem } from '../../data/feedMedia';

export function FeedMediaStrip({ media }: { media: WebFeedMediaItem[] }) {
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  if (media.length === 0) return null;

  return (
    <>
      <div style={{ display: 'flex', overflowX: 'auto', scrollSnapType: 'x mandatory', gap: 8, overscrollBehaviorInline: 'contain', marginTop: 14 }}>
        {media.map((item, index) => {
          const label = item.titel || item.slags || 'medie';
          return (
            <button
              key={item.id}
              type="button"
              aria-label={`Åbn billede: ${label}`}
              onClick={(event) => { event.stopPropagation(); setOpenIndex(index); }}
              style={{ flex: `0 0 ${media.length === 1 ? '100%' : '78%'}`, flexBasis: media.length === 1 ? '100%' : '78%', border: 0, padding: 0, background: T.beige, borderRadius: 10, cursor: 'zoom-in', overflow: 'hidden', scrollSnapAlign: 'start' }}
            >
              <img src={item.mediumUrl} alt={item.altTekst || label} style={{ width: '100%', height: 240, maxHeight: '42vh', objectFit: 'contain', display: 'block' }} />
            </button>
          );
        })}
      </div>
      {openIndex !== null ? <div onClick={(event) => event.stopPropagation()}>
        <Lightbox
          items={media.map((item) => ({ id: item.id, url: item.largeUrl, titel: item.titel, kunstner: item.kunstner, datering: item.datering, altTekst: item.altTekst }))}
          index={openIndex}
          onClose={() => setOpenIndex(null)}
          onNavigate={setOpenIndex}
        />
      </div> : null}
    </>
  );
}
