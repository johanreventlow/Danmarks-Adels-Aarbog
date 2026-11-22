// Review 37 P11 (projektejeren 2026-11-22): ÉN knap »Slet person…«, systemet vælger vejen. Forhåndsvisningen
// (red_slet_person_preview) siger, om personen kan slettes, så det kan fortrydes (kun en offentlig person). Ellers går
// dialogen direkte til den fulde sletning (SletHeltDialog: forhåndsvisning, id-bekræftelse og fil-udbakke) med en
// forklaring på hvorfor, og hvordan man ellers kunne få en sletning, der kan fortrydes. Fra den fortrydelige vej kan
// redaktøren selv vælge den fulde sletning. Ændrer personens status sig mellem forhåndsvisning og klik, afviser databasen
// med SLET_KRAEVER_SLET_HELT, og dialogen tilbyder »Slet helt«.
import { useEffect, useRef, useState } from 'react';
import { sletAarsagTekst, sletKraeverSletHelt, type SletAarsag } from '@daa/core';
import { fetchSletPreview, type SletPreview } from '../data/redaktionRead';
import { oversaetFejl } from '../data/redaktionWrite';
import { SletHeltDialog } from './SletHeltDialog';
import type { PurgePreview, PurgeResult } from '../data/personPurge';
import { T } from '../theme';

type Props = {
  personId: string; navn: string; dryRun: boolean; role: string | undefined;
  loadPreview?: (id: string) => Promise<SletPreview>;
  // Den fortrydelige sletning (red_slet_person). Kaster ved fejl, så dialogen kan vise den og skifte vej.
  sletFortrydeligt: () => Promise<void>;
  // Den fulde sletning, som SletHeltDialog kalder den.
  executeHelt: (opts: { personId: string; previewSha256: string; dryRun: boolean }) => Promise<PurgeResult>;
  loadPurgePreview?: (id: string) => Promise<PurgePreview>;
  onHeltSlettet: () => void;
  onClose: () => void;
};

const knap = { fontSize: 13.5, fontWeight: 600, borderRadius: 9, padding: '10px 16px', cursor: 'pointer' } as const;

export function SletPersonDialog({ personId, navn, dryRun, role, loadPreview = fetchSletPreview, sletFortrydeligt,
  executeHelt, loadPurgePreview, onHeltSlettet, onClose }: Props) {
  const redaktion = role === 'redaktion';
  const [preview, setPreview] = useState<SletPreview | null>(null);
  const [previewFejl, setPreviewFejl] = useState('');
  const [revision, setRevision] = useState(0);
  const [ack, setAck] = useState(false);
  const [busy, setBusy] = useState(false);
  const [fejl, setFejl] = useState('');
  // Status ændret mellem forhåndsvisning og klik: databasen kræver nu den fulde sletning.
  const [raceAarsag, setRaceAarsag] = useState<SletAarsag | null>(null);
  const [helt, setHelt] = useState<{ grund: 'valgt' } | { grund: 'paakraevet'; aarsag: SletAarsag } | null>(null);
  const writing = useRef(false);

  useEffect(() => {
    if (!redaktion) return; // forhåndsvisningen er kun for redaktionen; andre sender et forslag
    let active = true;
    setPreview(null); setPreviewFejl('');
    loadPreview(personId).then((p) => { if (active) setPreview(p); })
      .catch((e: unknown) => { if (active) setPreviewFejl(oversaetFejl(String((e as Error)?.message ?? e))); });
    return () => { active = false; };
  }, [personId, loadPreview, redaktion, revision]);

  // Den fulde sletning: påkrævet (personen er ikke offentlig) eller valgt af redaktøren.
  const heltAarsag: SletAarsag | null = helt?.grund === 'paakraevet' ? helt.aarsag
    : preview && !preview.kanFortrydes && !helt ? (preview.aarsag ?? 'ukendt') : null;
  if (redaktion && (helt || heltAarsag)) {
    const tekst = heltAarsag ? sletAarsagTekst(heltAarsag) : null;
    return <SletHeltDialog personId={personId} navn={navn} dryRun={dryRun} execute={executeHelt}
      {...(loadPurgePreview ? { loadPreview: loadPurgePreview } : {})}
      onDeleted={onHeltSlettet} onClose={onClose} overskrift="Slet helt — kan ikke fortrydes"
      intro={tekst
        ? <div data-testid="slet-helt-hvorfor" style={{ background: T.dangerTint, borderRadius: 11, padding: '12px 14px', margin: '8px 0 12px' }}>
            <p style={{ margin: 0, fontWeight: 600 }}>Personen kan ikke slettes, så det kan fortrydes.</p>
            <p style={{ margin: '6px 0 0' }}>{tekst.hvorfor}</p>
            <p style={{ margin: '6px 0 0' }}><b>Vil du hellere kunne fortryde?</b> {tekst.hvordan}</p>
            <p style={{ margin: '6px 0 0' }}>Den fulde sletning fjerner personen, dens oplysninger, historik og filer. Den kan ikke fortrydes.</p>
          </div>
        : <div data-testid="slet-helt-valgt" style={{ background: T.dangerTint, borderRadius: 11, padding: '12px 14px', margin: '8px 0 12px' }}>
            <p style={{ margin: 0 }}>Du har valgt den fulde sletning (GDPR): personen, dens oplysninger, historik og filer slettes, og det kan ikke fortrydes. Vil du hellere kunne fortryde, så luk og vælg »Slet (kan fortrydes)«.</p>
          </div>} />;
  }

  const perform = async () => {
    if (writing.current || busy || !ack) return;
    writing.current = true; setBusy(true); setFejl(''); setRaceAarsag(null);
    try {
      await sletFortrydeligt();
      onClose();
    } catch (e) {
      const msg = String((e as Error)?.message ?? e);
      setRaceAarsag(sletKraeverSletHelt(msg));
      setFejl(oversaetFejl(msg));
    } finally { writing.current = false; setBusy(false); }
  };

  const pv = preview;
  const kanSlette = redaktion ? !!pv && pv.kanFortrydes && !pv.sletningBlokeret && ack && !busy && !raceAarsag : ack && !busy;
  const titel = !redaktion ? 'Foreslå sletning' : 'Slet person — kan fortrydes';
  return <div style={{ position: 'fixed', inset: 0, zIndex: 100, background: 'rgba(0,0,0,.4)', display: 'grid', placeItems: 'center' }}>
    <section role="dialog" aria-modal="true" aria-labelledby="slet-person-titel"
      style={{ background: T.surfaceRaised, color: T.ink, borderRadius: 16, padding: '20px 22px', width: 'min(520px, 92vw)', maxHeight: '90vh', overflowY: 'auto', fontFamily: T.sans }}>
      <h2 id="slet-person-titel" style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, margin: 0 }}>{titel}</h2>
      {!redaktion && <>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: T.inkSecondary }}>Du er ikke redaktør, så sletningen af <b>{navn}</b> sendes som et forslag. En redaktør afgør, om personen skal slettes — og om det skal kunne fortrydes.</p>
      </>}
      {redaktion && !pv && !previewFejl && <p role="status">Henter forhåndsvisning…</p>}
      {redaktion && previewFejl && <div role="alert">
        <p>Forhåndsvisningen kunne ikke hentes: {previewFejl}</p>
        <button type="button" onClick={() => setRevision((n) => n + 1)}>Hent igen</button>
      </div>}
      {redaktion && pv && <>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: T.inkSecondary }}>Du er ved at slette <b>{navn}</b> (id {personId}). Personen og dens oplysninger fjernes fra siden.</p>
        <div style={{ background: T.bordeauxTint, borderRadius: 11, padding: '12px 14px' }}>
          <p style={{ margin: 0, fontSize: 13.5, lineHeight: 1.5 }}>{`Det her forsvinder: ${pv.antalRelationer} relation(er), ${pv.antalFacts} fakta, ${pv.antalNarrativer} biografi(er) og ${pv.antalMedlemskaber} slægts-/linjemedlemskab(er).`}</p>
          {pv.antalBindinger > 0 && <p style={{ margin: '6px 0 0', fontSize: 12.5 }}>{`Heraf er ${pv.antalBindinger} biografi(er) bundet til en kildepost. Bindingen fjernes med biografien — selve registreringen af, at teksten står på siden, bevares.`}</p>}
        </div>
        <p style={{ fontSize: 14, lineHeight: 1.5 }}><b>Historikken gemmes</b>, så sletningen kan fortrydes bagefter under »Slettede personer« i redaktionen (og straks fra personens ændringshistorik, hvor den står som »Slettede person {personId}«).</p>
        {pv.sletningBlokeret && <p role="alert">Personen har narrativ-publiceringshistorik og kan ikke slettes, så det kan fortrydes. Brug den fulde sletning nedenfor.</p>}
      </>}
      {(!redaktion || pv) && <label style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '12px 0', fontSize: 13 }}>
        <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} disabled={busy} />
        Jeg forstår, at relationerne brydes
      </label>}
      {fejl && <div role="alert" style={{ color: T.danger }}><p>{fejl}</p>
        {raceAarsag && redaktion && <button type="button" onClick={() => setHelt({ grund: 'paakraevet', aarsag: raceAarsag })}>Slet helt…</button>}
      </div>}
      <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
        <button type="button" onClick={onClose} disabled={busy} style={{ ...knap, background: 'transparent', border: `1px solid ${T.line}`, color: T.ink }}>Annullér</button>
        <button type="button" onClick={perform} disabled={!kanSlette}
          style={{ ...knap, border: 'none', color: '#fff', background: T.danger, opacity: kanSlette ? 1 : 0.45, cursor: kanSlette ? 'pointer' : 'not-allowed' }}>
          {redaktion ? 'Slet (kan fortrydes)' : 'Send forslag om sletning'}
        </button>
      </div>
      {redaktion && (pv || previewFejl) && <div style={{ borderTop: `1px solid ${T.line}`, marginTop: 16, paddingTop: 12 }}>
        <p style={{ fontSize: 12.5, color: T.inkSecondary, margin: '0 0 8px' }}>Må personens oplysninger heller ikke blive stående i historikken (fx efter et GDPR-krav), så slet helt i stedet.</p>
        <button type="button" onClick={() => setHelt({ grund: 'valgt' })} disabled={busy}
          style={{ ...knap, background: 'transparent', border: `1px solid ${T.danger}`, color: T.danger }}>Slet helt i stedet (GDPR, kan ikke fortrydes)…</button>
      </div>}
      {dryRun && <p style={{ fontSize: 12.5 }}>Dry-run er slået til.</p>}
    </section>
  </div>;
}
