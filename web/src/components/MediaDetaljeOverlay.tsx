import { useEffect, useState, type CSSProperties } from 'react';
import type { PersonMedia } from '../data/redaktionRead';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;

const C = {
  paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6', ink: '#221f1a', muted: '#6f675b',
  muted2: '#9a8f78', bordeaux: '#881A33', green: '#1f5b3a', red: '#8a2b2b', gold: '#b9a06a',
};
const input: CSSProperties = { width: '100%', fontSize: 13, color: C.ink, background: '#fff', border: '1px solid rgba(34,31,26,.16)', borderRadius: 8, padding: '8px 10px', outline: 'none' };
const label: CSSProperties = { fontSize: 10, letterSpacing: '.08em', textTransform: 'uppercase', color: C.muted2, margin: '10px 0 4px' };

export function MediaDetaljeOverlay({ media, onClose, onPreview, onGemMetadata, onGemRettigheder, onFjern, onSlet, onGenopret }: {
  media: PersonMedia;
  onClose: () => void;
  onPreview: () => void;
  onGemMetadata: (payload: Record<string, unknown>) => void;
  onGemRettigheder: (payload: Record<string, unknown>) => void;
  onFjern: () => void;
  onSlet: () => void;
  onGenopret: () => void;
}) {
  const [meta, setMeta] = useState({ titel: '', slags: 'foto', kunstner: '', datering: '' });
  const [ret, setRet] = useState({ status: 'ukendt', maaPubliceres: false, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
  useEffect(() => {
    setMeta({ titel: media.titel ?? '', slags: media.slags || 'foto', kunstner: media.kunstner ?? '', datering: media.datering ?? '' });
    setRet({ status: media.rettighederStatus || 'ukendt', maaPubliceres: media.maaPubliceres, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
  }, [media.id, media.titel, media.slags, media.kunstner, media.datering, media.rettighederStatus, media.maaPubliceres]);

  const metadataPayload: Record<string, unknown> = {};
  if (meta.titel !== (media.titel ?? '')) metadataPayload.titel = meta.titel.trim();
  if (meta.slags !== media.slags) metadataPayload.slags = meta.slags;
  if (meta.kunstner !== (media.kunstner ?? '')) metadataPayload.kunstner = meta.kunstner.trim();
  if (meta.datering !== (media.datering ?? '')) metadataPayload.datering = meta.datering.trim();
  const warning = ret.maaPubliceres && (ret.status === 'spaerret' || ret.status === 'begraenset');
  const statusLine = [media.slags, media.uploadStatus,
    media.bredde && media.hoejde ? `${media.bredde}×${media.hoejde}` : null,
    media.byteSize != null ? `${Math.round(media.byteSize / 1024)} KB` : null,
    media.originalFilnavn].filter(Boolean).join(' · ');

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(34,31,26,.55)', zIndex: 120, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 18 }}>
      <div onClick={(e) => e.stopPropagation()} style={{ width: 720, maxWidth: '100%', maxHeight: '92vh', overflowY: 'auto', background: C.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.16)', boxShadow: '0 24px 70px rgba(0,0,0,.35)', padding: 20 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14 }}>
          <div style={{ fontFamily: "'Cormorant Garamond',serif", fontSize: 25, fontWeight: 600, flex: 1 }}>{media.titel || 'Medie'}</div>
          <button type="button" onClick={onClose} style={{ border: 0, background: 'transparent', cursor: 'pointer', fontSize: 20, color: C.muted }}>×</button>
        </div>
        {media.url ? (
          <img src={media.url} alt={media.titel ?? media.slags} onClick={media.uploadStatus === 'klar' ? onPreview : undefined}
            style={{ width: '100%', maxHeight: 330, objectFit: 'contain', borderRadius: 10, background: C.beige, cursor: media.uploadStatus === 'klar' ? 'zoom-in' : 'default', opacity: media.uploadStatus === 'fjernet' ? .5 : 1 }} />
        ) : <div style={{ height: 180, borderRadius: 10, background: C.beige }} />}
        <div style={{ fontFamily: "'JetBrains Mono',monospace", fontSize: 9.5, color: C.muted2, marginTop: 6 }}>{statusLine || 'ingen filmetadata'}</div>

        <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontWeight: 700, fontSize: 13 }}>Metadata</div>
          <div style={label}>Slags</div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {MEDIA_SLAGS.map((s) => <button type="button" key={s} onClick={() => setMeta((m) => ({ ...m, slags: s }))}
              style={{ border: 0, borderRadius: 6, padding: '5px 9px', cursor: 'pointer', background: meta.slags === s ? C.bordeaux : C.beige, color: meta.slags === s ? '#fff' : C.muted }}>{s}</button>)}
          </div>
          <div style={label}>Titel</div><input value={meta.titel} onChange={(e) => setMeta((m) => ({ ...m, titel: e.target.value }))} style={input} />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div><div style={label}>Kunstner</div><input value={meta.kunstner} onChange={(e) => setMeta((m) => ({ ...m, kunstner: e.target.value }))} style={input} /></div>
            <div><div style={label}>Datering</div><input value={meta.datering} onChange={(e) => setMeta((m) => ({ ...m, datering: e.target.value }))} style={input} /></div>
          </div>
          <button type="button" disabled={!Object.keys(metadataPayload).length} onClick={() => onGemMetadata(metadataPayload)}
            style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: Object.keys(metadataPayload).length ? 'pointer' : 'default', background: C.green, color: '#fff', opacity: Object.keys(metadataPayload).length ? 1 : .45 }}>Gem metadata</button>
        </section>

        <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontWeight: 700, fontSize: 13 }}>Rettigheder og publicering</div>
          <div style={label}>Status</div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {RETTIGHED_STATUS.map((s) => <button type="button" key={s} onClick={() => setRet((r) => ({ ...r, status: s }))}
              style={{ border: 0, borderRadius: 6, padding: '5px 9px', cursor: 'pointer', background: ret.status === s ? C.bordeaux : C.beige, color: ret.status === s ? '#fff' : C.muted }}>{s}</button>)}
          </div>
          <label style={{ display: 'flex', gap: 7, alignItems: 'center', marginTop: 12, fontSize: 12.5, color: C.muted }}>
            <input type="checkbox" checked={ret.maaPubliceres} onChange={(e) => setRet((r) => ({ ...r, maaPubliceres: e.target.checked }))} /> Må publiceres
          </label>
          {warning && <div style={{ marginTop: 8, color: C.red, fontSize: 12 }}>Advarsel: status er {ret.status}, men mediet er markeret til publicering.</div>}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div><div style={label}>Licens</div><input value={ret.licens} onChange={(e) => setRet((r) => ({ ...r, licens: e.target.value }))} style={input} /></div>
            <div><div style={label}>Kildehenvisning</div><input value={ret.kildehenvisning} onChange={(e) => setRet((r) => ({ ...r, kildehenvisning: e.target.value }))} style={input} /></div>
            <div><div style={label}>Gengivelsestilladelse</div><input value={ret.gengivelsestilladelse} onChange={(e) => setRet((r) => ({ ...r, gengivelsestilladelse: e.target.value }))} style={input} /></div>
            <div><div style={label}>Kildenote</div><input value={ret.kildeFritekst} onChange={(e) => setRet((r) => ({ ...r, kildeFritekst: e.target.value }))} style={input} /></div>
          </div>
          <button type="button" onClick={() => onGemRettigheder(ret)} style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: 'pointer', background: C.green, color: '#fff' }}>Gem rettigheder</button>
        </section>

        <section style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 20, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          {media.uploadStatus === 'fjernet' ? (
            <button type="button" onClick={onGenopret} style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: 'pointer', background: C.green, color: '#fff' }}>Genopret</button>
          ) : <>
            <button type="button" disabled={!media.relationId} onClick={onFjern} style={{ border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 13px', cursor: media.relationId ? 'pointer' : 'default', background: C.beige, color: C.muted }}>Fjern tilknytning</button>
            <button type="button" onClick={onSlet} style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: 'pointer', background: C.red, color: '#fff' }}>Slet billede</button>
          </>}
        </section>
      </div>
    </div>
  );
}
