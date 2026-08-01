// Blok-niveau visning af fri-tekst med hyperlink-tokens + indlejrede billeder (billedstørrelser
// 2026-07-05, Slice C — udvider Slice A/§5.2's inline-only renderer). PORTERET-koncept fra
// mobile/src/components/NarrativRenderer.tsx (web har ingen router — bruger en onPickPerson-
// callback i stedet for expo-router). Kun 'person'-tokens er klikbare inline; 'media'-tokens
// bliver egne billed-blokke (klikbare til en lokal lightbox, planens §7.1e — navigerer KUN blandt
// DENNE narrativs egne billeder, ikke subjektets fulde galleri); øvrige typer inaktiv tekst.
import { useEffect, useMemo, useState } from 'react';
import { parseNarrativ, groupBlocks, type Block, type Segment } from '@daa/core';
import { fetchMediaByIds, mediaCaption, type EmbeddedMedia } from '../data/media';
import { Lightbox, type LightboxItem } from './Lightbox';
import { Link } from '../Link';
import { personPath } from '../data/nav';

function renderInline(
  segs: Segment[],
  onPickPerson: (id: string) => void,
  linkColor: string,
  inactiveColor: string,
  hrefFor: (id: string) => string,
) {
  return segs.map((s, i) => {
    if (s.kind === 'text') return <span key={i}>{s.text}</span>;
    if (s.maalType === 'person') {
      const id = String(s.maalId);
      return (
        <Link key={i} href={hrefFor(id)} onNavigate={() => onPickPerson(id)}
          style={{ color: linkColor, textDecoration: 'underline' }}>
          {s.label}
        </Link>
      );
    }
    return <span key={i} style={{ color: inactiveColor }}>{s.label}</span>;
  });
}

export function NarrativRenderer(props: {
  tekst: string;
  onPickPerson: (id: string) => void;
  linkColor: string;
  inactiveColor: string;
  // Hvor person-tokens peger hen. Default er publikumsfladen; redaktøren overstyrer til sin egen
  // record-sti, så et cmd-klik i narrativ-preview'et ikke sender redaktøren over i læser-fladen.
  hrefFor?: (id: string) => string;
}) {
  const { tekst, onPickPerson, linkColor, inactiveColor, hrefFor = personPath } = props;
  const blocks = useMemo(() => groupBlocks(parseNarrativ(tekst)), [tekst]);
  const mediaIds = useMemo(
    () => [...new Set(blocks.filter((b): b is Extract<Block, { kind: 'media' }> => b.kind === 'media').map((b) => b.maalId))],
    [blocks],
  );
  const idsKey = mediaIds.join(',');
  const [resolved, setResolved] = useState<Map<string, EmbeddedMedia>>(new Map());
  useEffect(() => {
    let cancelled = false;
    if (!mediaIds.length) { setResolved(new Map()); return; }
    fetchMediaByIds(mediaIds).then((m) => { if (!cancelled) setResolved(m); });
    return () => { cancelled = true; };
    // idsKey dækker mediaIds-indholdet; blocks selv er stabile pr. tekst.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idsKey]);

  const [lightbox, setLightbox] = useState<number | null>(null);
  // Lightbox-rækkefølgen følger blokkenes rækkefølge i teksten, men SPRINGER uopløselige id'er over
  // (samme id kan i teorien optræde to gange — indekset er derfor blokkens position blandt de
  // OPLØSTE billeder, ikke blandt alle media-blokke).
  const { lightboxItems, lightboxIndexByBlock } = useMemo(() => {
    const items: LightboxItem[] = [];
    const indexByBlock = blocks.map((b) => {
      if (b.kind !== 'media') return null;
      const m = resolved.get(String(b.maalId));
      if (!m) return null;
      items.push({ id: String(items.length), url: m.largeUrl, titel: b.label || m.titel });
      return items.length - 1;
    });
    return { lightboxItems: items, lightboxIndexByBlock: indexByBlock };
  }, [blocks, resolved]);

  return (
    <>
      {blocks.map((b, i) => {
        if (b.kind === 'heading') {
          return <div key={i} style={{ fontWeight: 600, fontSize: '1.15em', margin: '0.7em 0 0.3em' }}>{b.text}</div>;
        }
        if (b.kind === 'media') {
          const m = resolved.get(String(b.maalId));
          const lightboxIndex = lightboxIndexByBlock[i];
          if (!m || lightboxIndex == null) {
            return <div key={i} style={{ color: inactiveColor, fontStyle: 'italic', margin: '0.5em 0' }}>{b.label || '[billede]'}</div>;
          }
          const cap = b.label || mediaCaption(m);
          return (
            <div key={i} style={{ margin: '0.7em 0' }}>
              <img src={m.mediumUrl} alt={cap || 'billede'} onClick={() => setLightbox(lightboxIndex)}
                style={{ maxWidth: '100%', borderRadius: 8, cursor: 'zoom-in', display: 'block' }} />
              {cap && <div style={{ fontSize: '0.8em', opacity: 0.75, marginTop: 4 }}>{cap}</div>}
            </div>
          );
        }
        return <p key={i} style={{ margin: '0 0 0.6em', whiteSpace: 'pre-line' }}>{renderInline(b.segs, onPickPerson, linkColor, inactiveColor, hrefFor)}</p>;
      })}
      {lightbox != null && (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </>
  );
}
