import { useEffect, useState, type CSSProperties } from 'react';
import type { MediaAnvendelse, PersonMedia, UdrensPreview } from '../data/redaktionRead';
import { MEDIA_FAKTATYPER, type MediaFakta, type MediaFaktatype } from '../data/media';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;
const RET_FRITEKST_FELTER = ['licens', 'kildehenvisning', 'gengivelsestilladelse'] as const;

// Kilde/beskrivelse-feltgrupper (medie-metadata Task 4). 'datering' er den eneste faktatype med
// datofelter og håndteres separat; resten er rene tekstfelter.
type TekstFaktatype = Exclude<MediaFaktatype, 'datering'>;
const TEKST_FAKTATYPER = MEDIA_FAKTATYPER.filter((t): t is TekstFaktatype => t !== 'datering');
type FaktaFelt = { type: TekstFaktatype; label: string; inputType?: 'url' | 'date'; rows?: number; hjaelp?: string };
const FAKTA_GRUPPER: { titel: string; felter: FaktaFelt[] }[] = [
  { titel: 'Kilde', felter: [
    { type: 'kilde_url', label: 'Kilde-URL', inputType: 'url' },
    { type: 'kilde_institution', label: 'Kilde-institution' },
    { type: 'ekstern_objekt_id', label: 'Eksternt objekt-ID' },
    { type: 'hentedato', label: 'Hentedato', inputType: 'date' },
  ] },
  { titel: 'Ophav', felter: [
    { type: 'fotograf', label: 'Fotograf' },
    { type: 'rettighedshaver', label: 'Rettighedshaver' },
  ] },
  { titel: 'Kreditlinje', felter: [
    { type: 'kreditlinje', label: 'Kreditlinje', rows: 2, hjaelp: 'Indsæt institutionens krævede kreditlinje ordret' },
  ] },
  { titel: 'Beskrivelse', felter: [
    { type: 'beskrivelse', label: 'Beskrivelse', rows: 4 },
    { type: 'alt_tekst', label: 'Alt-tekst' },
  ] },
  { titel: 'Fysisk', felter: [
    { type: 'teknik', label: 'Teknik' },
    { type: 'fysiske_maal', label: 'Fysiske mål' },
  ] },
];
// MM-07: kanoniske ENGELSKE værdier som value (schema.sql date_qualifier-check); danske labels i UI.
const DATE_QUALIFIERS = [['', 'ikke sat'], ['about', 'ca.'], ['before', 'før'], ['after', 'efter']] as const;
// MM-11: kilde_url whitelist — kun http(s)-URLs; alt andet vises som fejl og udelades af payload.
const KILDE_URL_RE = /^https?:\/\//i;
const tomFaktaForm = () => Object.fromEntries(TEKST_FAKTATYPER.map((t) => [t, ''])) as Record<TekstFaktatype, string>;
export type MediaFaktaChange = {
  faktatype: MediaFaktatype; vaerdi: string;
  dateMin?: string | null; dateMax?: string | null; dateQualifier?: string | null;
};

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

export function MediaDetaljeOverlay({ media, anvendelse, anvendelseFejl, fletKandidater = [], fakta, onClose, onPreview, onGemMetadata, onGemRettigheder, onGemFakta, onFjernFakta, onFjern, onFjernTilknytning, onTilknyt, onFlet, onSlet, onGenopret, onErstatFil, onUdrens, udrensPreview, onSaetPortraet }: {
  media: DetaljeMedia;
  anvendelse?: MediaAnvendelse;
  anvendelseFejl?: string;
  fletKandidater?: FletKandidat[];
  fakta: MediaFakta | undefined; // undefined = henter stadig (Kilde og beskrivelse viser loader)
  onClose: () => void;
  onPreview: () => void;
  onGemMetadata: (payload: Record<string, unknown>) => void;
  onGemRettigheder: (payload: Record<string, unknown>) => void;
  // Required (Task 5 wirer dem i Redaktion.tsx): en fremtidig glemt wiring bliver hermed en
  // kompileringsfejl i stedet for en tavst manglende "Kilde og beskrivelse"-sektion.
  onGemFakta: (changes: MediaFaktaChange[], kildeFritekst: string) => void;
  onFjernFakta: (factId: string) => void; // wiring: tilbagetraekFakta
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
  const [faktaForm, setFaktaForm] = useState<Record<TekstFaktatype, string>>(tomFaktaForm);
  const [vaerkDatering, setVaerkDatering] = useState({ vaerdi: '', dateMin: '', dateMax: '', dateQualifier: '' });
  const [faktaKildeNote, setFaktaKildeNote] = useState('');
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
    // De tre rettigheds-fritekstfelter nulstilles IKKE her — de præudfyldes fra fakta-prop'en i
    // effekten nedenfor (MM-12), og et media.titel-refresh må ikke blanke dem undervejs.
    setRet((r) => ({ ...r, status: media.rettighederStatus || 'ukendt', maaPubliceres: media.maaPubliceres, kildeFritekst: '' }));
    setBekraeftSlet(false);
    setBekraeftUdrens(false);
    setMedieAktionBusy(false);
    setFletOpen(false); setFletOriginalId(''); setFletBusy(false); setFletFejl(''); setFletResultat(null); setFletReviewMentions(null);
  }, [media.id, media.titel, media.slags, media.kunstner, media.datering, media.rettighederStatus, media.maaPubliceres]);

  // Præudfyld fra fakta-prop'en (MM-12): kilde/beskrivelse-felterne OG de tre rettigheds-
  // fritekstfelter, der før var write-only (nulstillet til '' ved hver åbning).
  useEffect(() => {
    setFaktaForm(Object.fromEntries(TEKST_FAKTATYPER.map((t) => [t, fakta?.[t]?.vaerdi ?? ''])) as Record<TekstFaktatype, string>);
    setVaerkDatering({
      vaerdi: fakta?.datering?.vaerdi ?? '', dateMin: fakta?.datering?.dateMin ?? '',
      dateMax: fakta?.datering?.dateMax ?? '', dateQualifier: fakta?.datering?.dateQualifier ?? '',
    });
    setFaktaKildeNote('');
    setRet((r) => ({
      ...r,
      licens: fakta?.licens?.vaerdi ?? '',
      kildehenvisning: fakta?.kildehenvisning?.vaerdi ?? '',
      gengivelsestilladelse: fakta?.gengivelsestilladelse?.vaerdi ?? '',
    }));
  }, [media.id, fakta]);

  const metadataPayload: Record<string, unknown> = {};
  if (meta.titel !== (media.titel ?? '')) metadataPayload.titel = meta.titel.trim();
  if (meta.slags !== media.slags) metadataPayload.slags = meta.slags;
  if (meta.kunstner !== (media.kunstner ?? '')) metadataPayload.kunstner = meta.kunstner.trim();
  if (meta.datering !== (media.datering ?? '')) metadataPayload.datering = meta.datering.trim();

  // Gem-payload = KUN ændrede felter (MM-03, samme diff-mønster som metadataPayload ovenfor).
  // Gensend af en uændret værdi ville oprette en ny assertion med citation "(kilde mangler)" og
  // degradere proveniensen. Tømt felt der havde værdi medtages heller ikke — fjernelse sker
  // eksplicit via Fjern-knappen (undgår utilsigtet tilbagetræk).
  const kildeUrlUgyldig = faktaForm.kilde_url.trim() !== '' && !KILDE_URL_RE.test(faktaForm.kilde_url.trim());
  const faktaChanges: MediaFaktaChange[] = [];
  if (fakta) {
    for (const t of TEKST_FAKTATYPER) {
      const v = faktaForm[t].trim();
      if (!v || v === (fakta[t]?.vaerdi ?? '')) continue;
      if (t === 'kilde_url' && kildeUrlUgyldig) continue; // MM-11: udelades af payload
      faktaChanges.push({ faktatype: t, vaerdi: v });
    }
    const d = vaerkDatering; const eks = fakta.datering;
    const dateringAendret = d.vaerdi.trim() !== (eks?.vaerdi ?? '') || d.dateMin !== (eks?.dateMin ?? '')
      || d.dateMax !== (eks?.dateMax ?? '') || d.dateQualifier !== (eks?.dateQualifier ?? '');
    if (dateringAendret && (d.vaerdi.trim() || d.dateMin || d.dateMax)) {
      faktaChanges.push({ faktatype: 'datering', vaerdi: d.vaerdi.trim(),
        dateMin: d.dateMin || null, dateMax: d.dateMax || null, dateQualifier: d.dateQualifier || null });
    }
  }

  // MM-03 gælder OGSÅ rettighedsfelterne: licens/kildehenvisning/gengivelsestilladelse medtages
  // kun når de er ÆNDREDE ift. fakta-prop'en (og ikke blot tømt — fjernelse går via Fjern/fakta).
  const retPayload: Record<string, unknown> = { status: ret.status, maaPubliceres: ret.maaPubliceres, kildeFritekst: ret.kildeFritekst };
  for (const f of RET_FRITEKST_FELTER) {
    const v = ret[f].trim();
    if (v && v !== (fakta?.[f]?.vaerdi ?? '')) retPayload[f] = v;
  }

  const faktaFeltId = (t: string) => `media-fakta-${media.id}-${t}`;
  // Ægte <label htmlFor> (tilgængelighedskrav) + pr.-felt Fjern-knap når der findes et fakt.
  const renderFaktaLabel = (id: string, tekst: string, factId?: string) => (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
      <label htmlFor={id} style={{ display: 'block', flex: 1, ...label }}>{tekst}</label>
      {factId ? <button type="button" aria-label={`Fjern ${tekst}`} onClick={() => { if (!fletBusy) onFjernFakta(factId); }}
        style={{ border: 0, background: 'transparent', color: C.red, cursor: fletBusy ? 'default' : 'pointer', fontSize: 11.5, padding: 0 }}>Fjern</button> : null}
    </div>
  );
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
          <div style={{ fontWeight: 700, fontSize: 14 }}>Kilde og beskrivelse</div>
          {!fakta ? <div style={{ marginTop: 9, fontSize: 13, color: C.muted2 }}>Henter kildefelter…</div> : <>
            {FAKTA_GRUPPER.map((g) => (
              <div key={g.titel}>
                <div style={{ marginTop: 12, fontSize: 12.5, fontWeight: 650, color: C.muted }}>{g.titel}</div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', columnGap: 10 }}>
                  {g.felter.map((f) => {
                    const id = faktaFeltId(f.type);
                    return (
                      <div key={f.type} style={f.rows != null ? { gridColumn: '1 / -1' } : undefined}>
                        {renderFaktaLabel(id, f.label, fakta[f.type]?.factId)}
                        {f.rows != null
                          ? <textarea id={id} rows={f.rows} value={faktaForm[f.type]} onChange={(e) => setFaktaForm((s) => ({ ...s, [f.type]: e.target.value }))} style={{ ...input, resize: 'vertical', fontFamily: 'inherit' }} />
                          : <input id={id} type={f.inputType ?? 'text'} value={faktaForm[f.type]} onChange={(e) => setFaktaForm((s) => ({ ...s, [f.type]: e.target.value }))} style={input} />}
                        {f.type === 'kilde_url' && kildeUrlUgyldig ? <div role="alert" style={{ marginTop: 4, color: C.red, fontSize: 12.5 }}>Kilde-URL skal starte med http:// eller https:// — feltet gemmes ikke.</div> : null}
                        {f.hjaelp ? <div style={{ marginTop: 4, fontSize: 12, color: C.muted2 }}>{f.hjaelp}</div> : null}
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
            <div style={{ marginTop: 12, fontSize: 12.5, fontWeight: 650, color: C.muted }}>Datering (værk)</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', columnGap: 10 }}>
              <div style={{ gridColumn: '1 / -1' }}>
                {renderFaktaLabel(faktaFeltId('datering'), 'Datering (rå tekst)', fakta.datering?.factId)}
                <input id={faktaFeltId('datering')} value={vaerkDatering.vaerdi} onChange={(e) => setVaerkDatering((s) => ({ ...s, vaerdi: e.target.value }))} style={input} />
              </div>
              <div>
                <label htmlFor={faktaFeltId('datering-min')} style={{ display: 'block', ...label }}>Datering tidligst</label>
                <input id={faktaFeltId('datering-min')} type="date" value={vaerkDatering.dateMin} onChange={(e) => setVaerkDatering((s) => ({ ...s, dateMin: e.target.value }))} style={input} />
              </div>
              <div>
                <label htmlFor={faktaFeltId('datering-max')} style={{ display: 'block', ...label }}>Datering senest</label>
                <input id={faktaFeltId('datering-max')} type="date" value={vaerkDatering.dateMax} onChange={(e) => setVaerkDatering((s) => ({ ...s, dateMax: e.target.value }))} style={input} />
              </div>
              <div>
                <label htmlFor={faktaFeltId('datering-kval')} style={{ display: 'block', ...label }}>Datering kvalifikator</label>
                <select id={faktaFeltId('datering-kval')} value={vaerkDatering.dateQualifier} onChange={(e) => setVaerkDatering((s) => ({ ...s, dateQualifier: e.target.value }))} style={input}>
                  {DATE_QUALIFIERS.map(([v, l]) => <option key={v || 'tom'} value={v}>{l}</option>)}
                </select>
              </div>
            </div>
            <label htmlFor={faktaFeltId('kildenote')} style={{ display: 'block', ...label }}>Kildenote</label>
            <input id={faktaFeltId('kildenote')} value={faktaKildeNote} onChange={(e) => setFaktaKildeNote(e.target.value)} style={input} />
            <button type="button" disabled={fletBusy || !faktaChanges.length} onClick={() => { if (!fletBusy && faktaChanges.length) onGemFakta(faktaChanges, faktaKildeNote.trim()); }}
              style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: faktaChanges.length ? 'pointer' : 'default', background: C.green, color: '#fff', opacity: faktaChanges.length ? 1 : .45 }}>Gem kilde & beskrivelse</button>
          </>}
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
            {/* De tre fritekstfelter (ikke Kildenote) er gated på `fakta` (Task 4-reviewets Minor):
                deres diff mod fakta-prop'en (retPayload ovenfor) forudsætter den er indlæst — mens
                den stadig er undefined ville en uændret værdi fejlagtigt se "ny" ud og skabe en
                dublet-assertion med "(kilde mangler)". Kun FELTERNE spærres, ikke Gem-knappen: en
                fejlet/langsom fakta-hentning må ikke bricke status/må-publiceres, som intet har med
                `fakta` at gøre. */}
            <div><div style={label}>Licens</div><input disabled={fletBusy || !fakta} value={ret.licens} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, licens: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Kildehenvisning</div><input disabled={fletBusy || !fakta} value={ret.kildehenvisning} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, kildehenvisning: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Gengivelsestilladelse</div><input disabled={fletBusy || !fakta} value={ret.gengivelsestilladelse} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, gengivelsestilladelse: e.target.value })); }} style={input} /></div>
            <div><div style={label}>Kildenote</div><input disabled={fletBusy} value={ret.kildeFritekst} onChange={(e) => { if (!fletBusy) setRet((r) => ({ ...r, kildeFritekst: e.target.value })); }} style={input} /></div>
          </div>
          <button type="button" disabled={fletBusy} onClick={() => { if (!fletBusy) onGemRettigheder(retPayload); }} style={{ marginTop: 12, border: 0, borderRadius: 7, padding: '8px 13px', cursor: fletBusy ? 'default' : 'pointer', background: C.green, color: '#fff' }}>Gem rettigheder</button>
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
                <div style={{ fontSize: 12.5, color: C.muted, marginTop: 3 }}>Blød flet flytter tilknytninger og parkerer kopien i papirkurven. Filen udrenses ikke. Metadata-fakta på kopien flyttes ikke og bliver stående.</div>
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
