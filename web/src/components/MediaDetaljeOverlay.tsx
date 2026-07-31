import { useEffect, useState, type CSSProperties } from 'react';
import type { MediaAnvendelse, PersonMedia, UdrensPreview } from '../data/redaktionRead';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;

const C = {
  paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6', ink: '#221f1a', muted: '#6f675b',
  muted2: '#9a8f78', bordeaux: '#881A33', green: '#1f5b3a', red: '#8a2b2b', gold: '#b9a06a',
};
const input: CSSProperties = { width: '100%', fontSize: 14, color: C.ink, background: '#fff', border: '1px solid rgba(34,31,26,.16)', borderRadius: 8, padding: '8px 10px', outline: 'none' };
const label: CSSProperties = { fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', color: C.muted2, margin: '10px 0 4px' };
type DetaljeMedia = Omit<PersonMedia, 'relationId'> & { relationId?: string };
type FletKandidat = Pick<DetaljeMedia, 'id' | 'titel' | 'slags' | 'thumbUrl' | 'byteSize' | 'bredde' | 'hoejde'>;
export type MediaFletResultat =
  | { kind: 'dry-run' | 'completed'; lines: string[] }
  | { kind: 'mentions-changed'; mentions: MediaAnvendelse['mentions'] };

export function MediaDetaljeOverlay({ media, anvendelse, anvendelseFejl, fletKandidater = [], onClose, onPreview, onGemMetadata, onGemRettigheder, onFjern, onFjernTilknytning, onTilknyt, onFlet, onSlet, onGenopret, onErstatFil, onUdrens, udrensPreview, onSaetPortraet }: {
  media: DetaljeMedia;
  anvendelse?: MediaAnvendelse;
  anvendelseFejl?: string;
  fletKandidater?: FletKandidat[];
  onClose: () => void;
  onPreview: () => void;
  onGemMetadata: (payload: Record<string, unknown>) => void;
  onGemRettigheder: (payload: Record<string, unknown>) => void;
  onFjern: () => void;
  onFjernTilknytning?: (relationId: string) => void;
  onTilknyt?: () => void;
  onFlet?: (originalId: string, confirmedMentions: MediaAnvendelse['mentions']) => Promise<MediaFletResultat>;
  onSlet: () => void;
  onGenopret: () => void;
  onErstatFil?: (file: File) => void | Promise<unknown>;
  onUdrens?: () => void | Promise<unknown>;
  udrensPreview?: UdrensPreview;
  onSaetPortraet?: (personId: string, mediaId: string | null) => void | Promise<unknown>;
}) {
  const [meta, setMeta] = useState({ titel: '', slags: 'foto', kunstner: '', datering: '' });
  const [ret, setRet] = useState({ status: 'ukendt', maaPubliceres: false, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
  const [bekraeftSlet, setBekraeftSlet] = useState(false);
  const [bekraeftUdrens, setBekraeftUdrens] = useState(false);
  // Delt busy-lås for de tre nye skrivehandlinger (erstat fil/slet permanent/portræt), så et
  // hurtigt dobbeltklik ikke starter operationen to gange samtidig (Codex-fund, review af Task 9).
  const [medieAktionBusy, setMedieAktionBusy] = useState(false);
  const [fletOpen, setFletOpen] = useState(false);
  const [fletOriginalId, setFletOriginalId] = useState('');
  const [fletBusy, setFletBusy] = useState(false);
  const [fletFejl, setFletFejl] = useState('');
  const [fletResultat, setFletResultat] = useState<MediaFletResultat | null>(null);
  const [fletReviewMentions, setFletReviewMentions] = useState<MediaAnvendelse['mentions'] | null>(null);
  useEffect(() => {
    setMeta({ titel: media.titel ?? '', slags: media.slags || 'foto', kunstner: media.kunstner ?? '', datering: media.datering ?? '' });
    setRet({ status: media.rettighederStatus || 'ukendt', maaPubliceres: media.maaPubliceres, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
    setBekraeftSlet(false);
    setBekraeftUdrens(false);
    setMedieAktionBusy(false);
    setFletOpen(false); setFletOriginalId(''); setFletBusy(false); setFletFejl(''); setFletResultat(null); setFletReviewMentions(null);
  }, [media.id, media.titel, media.slags, media.kunstner, media.datering, media.rettighederStatus, media.maaPubliceres]);

  const metadataPayload: Record<string, unknown> = {};
  if (meta.titel !== (media.titel ?? '')) metadataPayload.titel = meta.titel.trim();
  if (meta.slags !== media.slags) metadataPayload.slags = meta.slags;
  if (meta.kunstner !== (media.kunstner ?? '')) metadataPayload.kunstner = meta.kunstner.trim();
  if (meta.datering !== (media.datering ?? '')) metadataPayload.datering = meta.datering.trim();
  const mediaSlags = Array.from(new Set<string>([...MEDIA_SLAGS, meta.slags].filter(Boolean)));
  const warning = ret.maaPubliceres && (ret.status === 'spaerret' || ret.status === 'begraenset');
  const statusLine = [media.slags, media.uploadStatus,
    media.bredde && media.hoejde ? `${media.bredde}×${media.hoejde}` : null,
    media.byteSize != null ? `${Math.round(media.byteSize / 1024)} KB` : null,
    media.originalFilnavn].filter(Boolean).join(' · ');
  const erBillede = media.mimeType?.startsWith('image/') === true && !!media.thumbUrl && !!media.url;
  const antalAfbildet = anvendelse?.afbildet.length ?? 0;
  const antalMentions = anvendelse?.mentions.length ?? 0;
  const erIBrug = antalAfbildet + antalMentions > 0;
  const sletAdvarsel = `Bruges på ${antalAfbildet} ${antalAfbildet === 1 ? 'tilknytning' : 'tilknytninger'} og i ${antalMentions} ${antalMentions === 1 ? 'narrativ' : 'narrativer'} — slet alligevel? Mentions bliver stående som inaktive tokens.`;
  const visteFletMentions = fletReviewMentions ?? anvendelse?.mentions ?? [];
  const fletSelectId = `media-flet-original-${media.id}`;

  return (
    <div onClick={() => { if (!fletBusy) onClose(); }} style={{ position: 'fixed', inset: 0, background: 'rgba(34,31,26,.55)', zIndex: 120, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 18 }}>
      <div aria-busy={fletBusy} onClick={(e) => e.stopPropagation()} style={{ width: 720, maxWidth: '100%', maxHeight: '92vh', overflowY: 'auto', background: C.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.16)', boxShadow: '0 24px 70px rgba(0,0,0,.35)', padding: 20 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14 }}>
          <div style={{ fontFamily: "'Cormorant Garamond',serif", fontSize: 25, fontWeight: 600, flex: 1 }}>{media.titel || 'Medie'}</div>
          <button type="button" disabled={fletBusy} onClick={onClose} style={{ border: 0, background: 'transparent', cursor: fletBusy ? 'default' : 'pointer', fontSize: 20, color: C.muted, opacity: fletBusy ? .4 : 1 }}>×</button>
        </div>
        <fieldset disabled={fletBusy} style={{ border: 0, padding: 0, margin: 0, minWidth: 0 }}>
        {erBillede ? (
          <img src={media.url!} alt={media.titel ?? media.slags} aria-disabled={fletBusy}
            onClick={media.uploadStatus === 'klar' && !fletBusy ? onPreview : undefined}
            style={{ width: '100%', maxHeight: 330, objectFit: 'contain', borderRadius: 10, background: C.beige, cursor: media.uploadStatus === 'klar' && !fletBusy ? 'zoom-in' : 'default', opacity: media.uploadStatus === 'fjernet' ? .5 : 1 }} />
        ) : <div style={{ height: 180, borderRadius: 10, background: C.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 7, opacity: media.uploadStatus === 'fjernet' ? .5 : 1 }}>
          <span aria-hidden style={{ fontSize: 34, color: C.muted }}>▤</span>
          <span style={{ fontSize: 13, color: C.muted }}>{media.slags || 'dokument'}</span>
        </div>}
        <div style={{ fontFamily: "'JetBrains Mono',monospace", fontSize: 10.5, color: C.muted2, marginTop: 6 }}>{statusLine || 'ingen filmetadata'}</div>

        <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontWeight: 700, fontSize: 14 }}>Metadata</div>
          <div style={label}>Slags</div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {mediaSlags.map((s) => <button type="button" key={s} disabled={fletBusy} onClick={() => { if (!fletBusy) setMeta((m) => ({ ...m, slags: s })); }}
              style={{ border: 0, borderRadius: 6, padding: '5px 9px', cursor: 'pointer', background: meta.slags === s ? C.bordeaux : C.beige, color: meta.slags === s ? '#fff' : C.muted }}>{s}</button>)}
          </div>
          <div style={label}>Titel</div><input disabled={fletBusy} value={meta.titel} onChange={(e) => { if (!fletBusy) setMeta((m) => ({ ...m, titel: e.target.value })); }} style={input} />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div><div style={label}>Kunstner</div><input disabled={fletBusy} value={meta.kunstner} onChange={(e) => { if (!fletBusy) setMeta((m) => ({ ...m, kunstner: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Datering</div><input disabled={fletBusy} value={meta.datering} onChange={(e) => { if (!fletBusy) setMeta((m) => ({ ...m, datering: e.target.value })); }} style={input} /></div>
          </div>
          <button type="button" disabled={fletBusy || !Object.keys(metadataPayload).length} onClick={() => { if (!fletBusy) onGemMetadata(metadataPayload); }}
            style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: Object.keys(metadataPayload).length ? 'pointer' : 'default', background: C.green, color: '#fff', opacity: Object.keys(metadataPayload).length ? 1 : .45 }}>Gem metadata</button>
        </section>

        <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontWeight: 700, fontSize: 14 }}>Rettigheder og publicering</div>
          <div style={label}>Status</div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {RETTIGHED_STATUS.map((s) => <button type="button" key={s} disabled={fletBusy} onClick={() => { if (!fletBusy) setRet((r) => ({ ...r, status: s })); }}
              style={{ border: 0, borderRadius: 6, padding: '5px 9px', cursor: 'pointer', background: ret.status === s ? C.bordeaux : C.beige, color: ret.status === s ? '#fff' : C.muted }}>{s}</button>)}
          </div>
          <label style={{ display: 'flex', gap: 7, alignItems: 'center', marginTop: 12, fontSize: 13.5, color: C.muted }}>
            <input type="checkbox" disabled={fletBusy} checked={ret.maaPubliceres} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, maaPubliceres: e.target.checked })); }} /> Må publiceres
          </label>
          {warning && <div style={{ marginTop: 8, color: C.red, fontSize: 13 }}>Advarsel: status er {ret.status}, men mediet er markeret til publicering.</div>}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div><div style={label}>Licens</div><input disabled={fletBusy} value={ret.licens} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, licens: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Kildehenvisning</div><input disabled={fletBusy} value={ret.kildehenvisning} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, kildehenvisning: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Gengivelsestilladelse</div><input disabled={fletBusy} value={ret.gengivelsestilladelse} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, gengivelsestilladelse: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Kildenote</div><input disabled={fletBusy} value={ret.kildeFritekst} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, kildeFritekst: e.target.value })); }} style={input} /></div>
          </div>
          <button type="button" disabled={fletBusy} onClick={() => { if (!fletBusy) onGemRettigheder(ret); }} style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: fletBusy ? 'default' : 'pointer', background: C.green, color: '#fff' }}>Gem rettigheder</button>
        </section>

        <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ fontWeight: 700, fontSize: 14, flex: 1 }}>Bruges på</div>
            {onTilknyt ? <button type="button" disabled={fletBusy || !anvendelse} onClick={() => { if (!fletBusy) onTilknyt(); }} style={{ border: '1px solid rgba(136,26,51,.28)', borderRadius: 7, padding: '6px 10px', cursor: anvendelse && !fletBusy ? 'pointer' : 'default', background: C.paper, color: C.bordeaux, opacity: anvendelse && !fletBusy ? 1 : .45 }}>Tilknyt til…</button> : null}
          </div>
          {!anvendelse ? <div style={{ marginTop: 9, fontSize: 13, color: anvendelseFejl ? C.red : C.muted2 }}>{anvendelseFejl || 'Henter anvendelser…'}</div> : (
            <div style={{ marginTop: 8, display: 'grid', gap: 7 }}>
              {anvendelse.afbildet.map((a) => (
                <div key={a.relationId} style={{ display: 'flex', alignItems: 'center', gap: 9, background: C.panel, borderRadius: 8, padding: '8px 10px' }}>
                  <span style={{ flex: 1, minWidth: 0, fontSize: 13.5 }}>
                    {a.navn} <span style={{ color: C.muted2 }}>· {a.type}</span>
                    {a.primaer ? <span style={{ marginLeft: 7, fontSize: 10.5, letterSpacing: '.06em', textTransform: 'uppercase', color: C.bordeaux, border: '1px solid rgba(136,26,51,.28)', borderRadius: 5, padding: '1px 5px' }}>Portræt</span> : null}
                  </span>
                  {a.type === 'person' && onSaetPortraet && media.uploadStatus === 'klar' ? (
                    <button type="button" disabled={fletBusy || medieAktionBusy}
                      onClick={async () => {
                        if (fletBusy || medieAktionBusy) return;
                        setMedieAktionBusy(true);
                        try { await onSaetPortraet(a.id, a.primaer ? null : media.id); }
                        finally { setMedieAktionBusy(false); }
                      }}
                      style={{ border: 0, background: 'transparent', color: C.bordeaux, cursor: fletBusy || medieAktionBusy ? 'default' : 'pointer', padding: 2, fontSize: 13, opacity: medieAktionBusy ? .5 : 1 }}>
                      {a.primaer ? 'Fjern portræt-valg' : 'Sæt som portræt'}
                    </button>
                  ) : null}
                  {onFjernTilknytning ? <button type="button" disabled={fletBusy} onClick={() => { if (!fletBusy) onFjernTilknytning(a.relationId); }} style={{ border: 0, background: 'transparent', color: C.red, cursor: fletBusy ? 'default' : 'pointer', padding: 2 }}>Fjern</button> : null}
                </div>
              ))}
              {anvendelse.mentions.map((m) => (
                <div key={`${m.kildeType}:${m.kildeId}`} style={{ background: C.panel, borderRadius: 8, padding: '8px 10px', fontSize: 13.5 }}>
                  {m.kildeType === 'narrative' ? 'Narrativ' : m.kildeType} på {m.subjektNavn}
                </div>
              ))}
              {!erIBrug ? <div style={{ fontSize: 13, color: C.muted2 }}>Mediet bruges ikke endnu.</div> : null}
            </div>
          )}
        </section>

        {onFlet && fletKandidater.length > 0 ? (
          <section style={{ marginTop: 18, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700, fontSize: 14 }}>Mulig dublet</div>
                <div style={{ fontSize: 12.5, color: C.muted, marginTop: 3 }}>Blød flet flytter tilknytninger og parkerer kopien i papirkurven. Filen udrenses ikke.</div>
              </div>
              {!fletOpen ? <button type="button" onClick={() => setFletOpen(true)} style={{ border: '1px solid rgba(136,26,51,.28)', borderRadius: 7, padding: '7px 11px', cursor: 'pointer', background: C.paper, color: C.bordeaux }}>Flet ind i…</button> : null}
            </div>
            {fletOpen ? (
              <div style={{ marginTop: 11, background: C.panel, borderRadius: 10, padding: 12 }}>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', gap: 10, alignItems: 'center' }}>
                  <div>
                    <div style={label}>Kopi · parkeres</div>
                    <div style={{ fontSize: 13.5, fontWeight: 650 }}>{media.titel || `Medie #${media.id}`}</div>
                    <div style={{ fontFamily: 'monospace', fontSize: 10, color: C.muted2 }}>id {media.id}</div>
                  </div>
                  <span aria-hidden style={{ color: C.bordeaux, fontSize: 18 }}>→</span>
                  <div>
                    <label htmlFor={fletSelectId} style={{ display: 'block', ...label }}>Original · beholdes</label>
                    <select id={fletSelectId} disabled={fletBusy} value={fletOriginalId} onChange={(e) => { setFletOriginalId(e.target.value); setFletFejl(''); setFletResultat(null); setFletReviewMentions(null); }} style={input}>
                      <option value="">Vælg original…</option>
                      {fletKandidater.map((candidate) => (
                        <option key={candidate.id} value={candidate.id}>{candidate.titel || candidate.slags || 'Medie'} · id {candidate.id}</option>
                      ))}
                    </select>
                  </div>
                </div>
                {visteFletMentions.length ? (
                  <div role="alert" style={{ marginTop: 11, padding: '9px 10px', borderRadius: 8, background: '#f8ecef', border: '1px solid rgba(138,43,43,.2)', color: C.red, fontSize: 12.5, lineHeight: 1.45 }}>
                    <b>Advarsel: {visteFletMentions.length} {visteFletMentions.length === 1 ? 'narrativ-mention flyttes' : 'narrativ-mentions flyttes'} ikke.</b>
                    <div>{visteFletMentions.map((mention) => `${mention.kildeType} #${mention.kildeId} på ${mention.subjektNavn}`).join(' · ')}</div>
                  </div>
                ) : <div style={{ marginTop: 9, fontSize: 12.5, color: C.muted }}>Ingen narrativ-mentions på kopien.</div>}
                <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end', marginTop: 11 }}>
                  <button type="button" disabled={fletBusy} onClick={() => { setFletOpen(false); setFletOriginalId(''); setFletFejl(''); setFletResultat(null); }} style={{ border: 0, background: 'transparent', color: C.muted, cursor: fletBusy ? 'default' : 'pointer' }}>Annullér</button>
                  <button type="button" disabled={fletBusy || !fletOriginalId || !anvendelse} onClick={async () => {
                    if (!fletOriginalId || !anvendelse || fletBusy) return;
                    setFletBusy(true); setFletFejl(''); setFletResultat(null);
                    try {
                      const result = await onFlet(fletOriginalId, visteFletMentions);
                      if (result.kind === 'mentions-changed') setFletReviewMentions(result.mentions);
                      setFletResultat(result);
                    }
                    catch (error) { setFletFejl(String((error as Error)?.message ?? error)); }
                    finally { setFletBusy(false); }
                  }} style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: fletBusy || !fletOriginalId || !anvendelse ? 'default' : 'pointer', background: C.bordeaux, color: '#fff', opacity: fletBusy || !fletOriginalId || !anvendelse ? .45 : 1 }}>
                    {fletBusy ? 'Fletter…' : anvendelse
                      ? fletResultat?.kind === 'mentions-changed' ? 'Gennemgået — kør blød flet' : 'Kør blød flet'
                      : 'Henter anvendelser…'}
                  </button>
                </div>
                {fletFejl ? <div role="alert" style={{ marginTop: 9, color: C.red, fontSize: 12.5 }}>Fletning stoppede: {fletFejl}. Tilstanden er bevaret; kontrollér papirkurven og prøv igen.</div> : null}
                {fletResultat?.kind === 'mentions-changed' ? (
                  <div role="alert" style={{ marginTop: 9, color: C.bordeaux, fontSize: 12.5 }}>
                    Mentions er ændret siden din første gennemgang. Ingen ændringer er udført. Gennemgå advarslen og klik igen.
                  </div>
                ) : fletResultat ? (
                  <div style={{ marginTop: 9, color: fletResultat.kind === 'dry-run' ? C.bordeaux : C.green, fontSize: 12.5 }}>
                    {fletResultat.kind === 'dry-run' ? 'Dry-run — ingen ændringer udført:' : 'Fletning gennemført. Kopien ligger i papirkurven.'}
                    {fletResultat.lines.length ? <ol style={{ margin: '6px 0 0', paddingLeft: 19 }}>{fletResultat.lines.map((line, index) => <li key={`${index}:${line}`}>{line}</li>)}</ol> : null}
                  </div>
                ) : null}
              </div>
            ) : null}
          </section>
        ) : null}

        <section style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 20, paddingTop: 14, borderTop: '1px solid rgba(34,31,26,.1)' }}>
          {media.uploadStatus === 'fjernet' ? (
            <>
              <button type="button" disabled={fletBusy} onClick={() => { if (!fletBusy) onGenopret(); }} style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: fletBusy ? 'default' : 'pointer', background: C.green, color: '#fff' }}>Genopret</button>
              {onUdrens ? (
                <button type="button" disabled={fletBusy || medieAktionBusy || !udrensPreview || !udrensPreview.kanUdrenses}
                  title={udrensPreview && !udrensPreview.kanUdrenses ? udrensPreview.blokeringer.join(' · ') : undefined}
                  onClick={async () => {
                    if (fletBusy || medieAktionBusy || !udrensPreview?.kanUdrenses) return;
                    if (!bekraeftUdrens) { setBekraeftUdrens(true); return; }
                    setMedieAktionBusy(true);
                    try { await onUdrens(); }
                    finally { setMedieAktionBusy(false); }
                  }}
                  style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: udrensPreview?.kanUdrenses && !medieAktionBusy ? 'pointer' : 'default', background: C.red, color: '#fff', opacity: udrensPreview?.kanUdrenses && !medieAktionBusy ? 1 : .45 }}>
                  {medieAktionBusy ? 'Sletter permanent…' : bekraeftUdrens
                    ? `${udrensPreview?.stier.length ?? 0} fil(er) slettes permanent — bytes kan IKKE fortrydes. Klik igen for at bekræfte.`
                    : !udrensPreview ? 'Kontrollerer…' : udrensPreview.kanUdrenses ? 'Slet permanent…' : 'Slet permanent (blokeret)'}
                </button>
              ) : null}
              {udrensPreview && !udrensPreview.kanUdrenses ? (
                <div role="alert" style={{ fontSize: 12.5, color: C.red }}>
                  {udrensPreview.blokeringer.map((b) => <div key={b}>· {b}</div>)}
                </div>
              ) : null}
            </>
          ) : <>
            {media.uploadStatus === 'klar' && onErstatFil ? (
              <label style={{ border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 13px', cursor: medieAktionBusy ? 'default' : 'pointer', background: C.beige, color: C.muted, fontSize: 14, opacity: medieAktionBusy ? .5 : 1 }}>
                {medieAktionBusy ? 'Erstatter…' : 'Erstat fil…'}
                <input type="file" accept="image/*" disabled={medieAktionBusy} style={{ display: 'none' }}
                  onChange={async (e) => {
                    const f = e.target.files?.[0]; e.target.value = '';
                    if (!f || medieAktionBusy) return;
                    setMedieAktionBusy(true);
                    try { await onErstatFil(f); }
                    finally { setMedieAktionBusy(false); }
                  }} />
              </label>
            ) : null}
            <button type="button" disabled={fletBusy || !media.relationId} onClick={() => { if (!fletBusy) onFjern(); }} style={{ border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 13px', cursor: media.relationId && !fletBusy ? 'pointer' : 'default', background: C.beige, color: C.muted }}>Fjern tilknytning</button>
            <button type="button" disabled={fletBusy || !anvendelse} title={bekraeftSlet ? sletAdvarsel : undefined} onClick={() => {
              if (fletBusy || !anvendelse) return;
              if (erIBrug && !bekraeftSlet) { setBekraeftSlet(true); return; }
              onSlet();
            }} style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: anvendelse ? 'pointer' : 'default', background: C.red, color: '#fff', opacity: anvendelse ? 1 : .45 }}>
              {bekraeftSlet ? sletAdvarsel : anvendelse ? 'Slet billede' : 'Kontrollerer anvendelser…'}
            </button>
          </>}
        </section>
        </fieldset>
      </div>
    </div>
  );
}
