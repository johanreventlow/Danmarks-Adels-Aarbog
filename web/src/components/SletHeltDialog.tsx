import { useEffect, useRef, useState, type ReactNode } from 'react';
import { fetchPurgePreview, purgeFejl, type PurgePreview, type PurgeResult } from '../data/personPurge';
import { T } from '../theme';

const purgeLabels: Record<string, string> = {
  fortrydelse_mistes: 'Muligheden for at fortryde tidligere ændringer mistes',
  kontrolkoersel_failer: 'En tidligere kontrolkørsel vil ikke længere bestå',
  'forældede_bindinger': 'Kildebindinger bliver forældede',
  anden_paastand: 'En anden persons påstand bruger data, der skal slettes',
  anden_promotion: 'En anden persons kildebinding bruger profilen',
  aaben_koersel: 'En kørsel er stadig åben', aaben_batch: 'En batch er stadig åben',
  afventer_kontrol: 'En kildepersona afventer kontrol',
  // Review 37 R37P11-3 (ceremoni 2): reglen består; teksten viser vejen ud.
  samme_som_knudepunkt: 'Profilen er knudepunkt for andre profiler. Fjern først koblingerne under »Samme person« på profilens redigeringsside, og hent så en ny forhåndsvisning.',
  link_i_tekst: 'En bevaret tekst linker til profilen eller dens data',
  laast_familiefoto: 'Låst familiefoto: tjek billedet, før det frigives igen',
  bevaret_evidens: 'Bevaret kilde/påstand på et låst familiefoto: kan nævne profilen',
  // Review 37 P3/P10 (ceremoni 2): kontrollistens tekstfund.
  fritekst: 'Teksten nævner profilens navn',
  // Ceremoni 2b: profilens eget id under en person-nøgle (fx en identitetskandidat) — en ægte henvisning, vises åbent.
  id_henvisning: 'En kildedata-række henviser til profilen med dens id (fx en identitetskandidat) — tjek den',
  kun_id: 'Teksten rummer profilens eller en families id som tal — ofte et årstal, sidetal eller en anden talværdi i kildedata',
  bevaret_summary: 'Et bevaret ændringssæts beskrivelse kan nævne profilen',
};

// Review 37 P6: tabeller med danske navne i stedet for rå stedkoder (»S37b«); koderne står under »Detaljer«.
const TABEL_NAVN: Record<string, string> = {
  person: 'Profilen', fact: 'Oplysninger (fakta)', assertion: 'Påstande', citation: 'Kildehenvisninger',
  conclusion: 'Konklusioner', relation: 'Relationer', narrative: 'Biografier og tekster', note: 'Noter',
  media: 'Billeder og filer', media_variant: 'Billedstørrelser', family: 'Familier', family_member: 'Familiemedlemskaber',
  story: 'Historier', haendelse: 'Hændelser', suggestion: 'Forslag', feed_pin: 'Forside-fastgørelser',
  bookmark: 'Bogmærker', change_event: 'Historik (ændringer)', change_set: 'Historik (ændringssæt)',
  entity_description: 'Beskrivelser', person_external_id: 'Bogens numre',
};
const HANDLING_NAVN: Record<string, string> = {
  slet: 'slettes', skjul: 'skjules for læserne', nulstil: 'nulstilles', bevar_andres: 'bevares (andres data)',
};
const tabelNavn = (tabel: string) => TABEL_NAVN[tabel]
  ?? (tabel.startsWith('private.') ? `Interne spor (${tabel.slice('private.'.length)})` : tabel);

type Props = {
  personId: string; navn: string; dryRun: boolean;
  loadPreview?: (id: string) => Promise<PurgePreview>;
  execute: (opts: { personId: string; previewSha256: string; dryRun: boolean }) => Promise<PurgeResult>;
  // Review 37 P5: filoprydningen alene. Køres, når profilen allerede er væk (svaret på sletningen gik tabt).
  oprydning?: () => Promise<PurgeResult>;
  onDeleted: () => void; onClose: () => void;
  // Review 37 P11: når »Slet person…« vælger den fulde sletning, står overskrift og begrundelse øverst.
  overskrift?: string; intro?: ReactNode;
};
type KontrolPost = { k: PurgePreview['til_kontrol'][number]; i: number };
// Links til hvert kontrolsted + selve stederne. Også interne steder uden en redaktionseditor har et konkret linkmål og
// fuld PK. Ankrene bruger indekset i hele listen, så de er entydige på tværs af grupperne.
function kontrolListe(poster: KontrolPost[]) {
  return <>
    <ul>{poster.map(({ k, i }) => <li key={i}>
      <a href={`#purge-kontrol-${i}`}>{k.sted} · {k.tabel} · {JSON.stringify(k.pk)}</a>
    </li>)}</ul>
    {poster.map(({ k, i }) => {
      const entity = k.tabel.replace(/^public\./, '');
      const href = ['person', 'family', 'narrative', 'media', 'source', 'estate'].includes(entity) && k.pk.id != null
        ? `/redaktion/${entity}/${encodeURIComponent(String(k.pk.id))}` : null;
      return <div key={i} id={`purge-kontrol-${i}`} tabIndex={-1} style={{ borderTop: `1px solid ${T.line}`, padding: 8 }}>
        <b>{k.sted} · {k.tabel}</b><p>{JSON.stringify(k.pk)} · {purgeLabels[k.grund] ?? k.grund}</p>
        {href && <a href={href} target="_blank" rel="noreferrer">Åbn stedet i Redaktion</a>}
      </div>;
    })}
  </>;
}

export function SletHeltDialog({ personId, navn, dryRun, loadPreview = fetchPurgePreview, execute, oprydning, onDeleted, onClose,
  overskrift = 'Slet helt', intro }: Props) {
  const [preview, setPreview] = useState<PurgePreview | null>(null);
  const [typedId, setTypedId] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ReturnType<typeof purgeFejl> | null>(null);
  const [result, setResult] = useState<PurgeResult | null>(null);
  const [revision, setRevision] = useState(0);
  const writing = useRef(false);
  const [alleredeSlettet, setAlleredeSlettet] = useState(false);
  // Review 37 P5: findes profilen ikke længere (typisk: sletningen lykkedes, men svaret gik tabt), er der intet at
  // slette — men filerne i udbakken skal stadig ryddes op, og listen skal opdateres. I dry-run vises kun beskeden.
  const oprydRef = useRef(oprydning); oprydRef.current = oprydning;
  const deletedRef = useRef(onDeleted); deletedRef.current = onDeleted;
  const haandterFejl = async (e: unknown, erAktiv: () => boolean) => {
    const f = purgeFejl(e);
    if (f.kind !== 'findes_ikke' || dryRun) { if (erAktiv()) setError(f); return; }
    setAlleredeSlettet(true);
    let res: PurgeResult = { kind: 'completed' };
    try { if (oprydRef.current) res = await oprydRef.current(); }
    catch (oe) { res = { kind: 'completed', storageAdvarsel: `Filoprydningen fejlede: ${purgeFejl(oe).tekst}. Prøv igen i »Filer der venter på sletning«.` }; }
    if (!erAktiv()) return;
    setResult(res);
    deletedRef.current();
  };
  useEffect(() => {
    let active = true;
    setLoading(true); setPreview(null); setTypedId(''); setError(null); setResult(null); setAlleredeSlettet(false);
    loadPreview(personId).then((p) => {
      if (!active) return;
      // Et forkert RPC-svar må ikke autorisere sletning af den valgte profil.
      if (String(p.person_id) !== personId || !/^[a-f0-9]{64}$/.test(p.sha256)) throw new Error('Ugyldig forhåndsvisning');
      setPreview(p);
    }).catch((e: unknown) => haandterFejl(e, () => active))
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
    // haandterFejl læser oprydning/onDeleted via refs; dryRun følger med i afhængighederne.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personId, loadPreview, revision, dryRun]);
  const done = result?.kind === 'completed';
  const canDelete = !!preview && !loading && !busy && !done && !error
    && typedId === personId && preview.blokeringer.length === 0;
  const perform = async () => {
    if (!canDelete || !preview || writing.current) return;
    writing.current = true; setBusy(true); setResult(null);
    try {
      const res = await execute({ personId, previewSha256: preview.sha256, dryRun });
      setResult(res);
      if (res.kind === 'completed') onDeleted();
    } catch (e) { await haandterFejl(e, () => true); }
    finally { writing.current = false; setBusy(false); }
  };
  return <div style={{ position: 'fixed', inset: 0, zIndex: 100, background: 'rgba(0,0,0,.4)', display: 'grid', placeItems: 'center' }}>
    <section role="dialog" aria-modal="true" aria-labelledby="purge-title"
      style={{ background: T.surfaceRaised, color: T.ink, borderRadius: 12, padding: 24, width: 'min(760px, 90vw)', maxHeight: '90vh', overflowY: 'auto' }}>
      <h2 id="purge-title">{overskrift} · {preview?.navn ?? navn} · id {personId}</h2>
      {intro}
      <p>Du sletter den rå profil med dette id, ikke den sammenfoldede person eller de andre profiler i samme_som-komponenten. Sletningen kan ikke fortrydes.</p>
      {loading && <p role="status">Henter forhåndsvisning…</p>}
      {preview && <>
        <h3>Det sker med data</h3>
        <ul>{Object.entries(Object.values(preview.steder).flat().reduce<Record<string, number>>((counts, row) => {
          const label = `${tabelNavn(row.tabel)}: ${HANDLING_NAVN[row.handling] ?? row.handling}`;
          counts[label] = (counts[label] ?? 0) + 1; return counts;
        }, {})).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([label, count]) => <li key={label}>{label} ({count})</li>)}</ul>
        <details><summary>Detaljer pr. sted (stedkoder fra sletteplanen)</summary>
          <ul>{Object.entries(preview.steder).map(([sted, rows]) => <li key={sted}>{sted}: {rows.length}
            <ul>{Object.entries(rows.reduce<Record<string, number>>((counts, row) => {
              const label = `${row.tabel} · ${row.handling}`; counts[label] = (counts[label] ?? 0) + 1; return counts;
            }, {})).map(([label, count]) => <li key={label}>{label}: {count}</li>)}</ul>
          </li>)}</ul>
        </details>
        {preview.storage !== undefined && <>
          <h3>Filer der slettes</h3>
          <p>{preview.storage.length ? `${preview.storage.length} fil${preview.storage.length === 1 ? '' : 'er'} i lageret slettes efter databasen.` : 'Ingen filer i lageret.'}</p>
          {preview.storage.length > 0 && <details><summary>Vis filerne</summary>
            <ul>{preview.storage.map((f) => <li key={`${f.bucket}/${f.sti}`}><code>{f.bucket}/{f.sti}</code></li>)}</ul></details>}
        </>}
        {preview.historik !== undefined && <>
          <h3>Historik</h3>
          <p>{preview.historik.events} ændringer i {preview.historik.saet} ændringssæt slettes. Profilen kan derfor ikke genskabes fra historikken.</p>
        </>}
        {preview.samme_som_komponent !== undefined && <>
          <h3>Samme person i andre udgaver</h3>
          {(() => { const andre = preview.samme_som_komponent.filter((id) => String(id) !== personId); return andre.length
            ? <p>Profilen er koblet som samme person som: {andre.join(', ')}. De andre profiler bevares; kun denne slettes.</p>
            : <p>Ingen andre profiler er koblet som samme person.</p>; })()}
        </>}
        {preview['forældes'] !== undefined && (preview['forældes'].narrativer.length + preview['forældes'].bindinger.length) > 0 && <>
          <h3>Bliver forældet</h3>
          <p>{preview['forældes'].narrativer.length} biografier og {preview['forældes'].bindinger.length} kildebindinger bevares, men bygger på data, der slettes, og bliver derfor forældede: {[...preview['forældes'].narrativer, ...preview['forældes'].bindinger].join(', ')}.</p>
        </>}
        <h3>Familier</h3>
        <p>Slettes: {preview.familier_slettes.join(', ') || 'ingen'}. Bevares: {preview.familier_bevares.join(', ') || 'ingen'}.</p>
        {preview.familieindhold_slettes !== undefined && <>
          <p>Bevarede familier, hvis indhold slettes, fordi profilen ikke er offentlig: {preview.familieindhold_slettes.length ? '' : 'ingen.'}</p>
          {preview.familieindhold_slettes.length > 0 && <ul>{preview.familieindhold_slettes.map((f) => <li key={String(f.family_id)}>
            Familie {f.family_id}: {f.fakta.length} fakta, {f.noter.length} noter, {f.narrativer.length} narrativer
            {f.haendelser !== undefined && <>, {f.haendelser.length} hændelser, {(f.stories ?? []).length} historier,{' '}
              {(f.relationer ?? []).length} relationer, {(f.forslag ?? []).length} forslag, {f.historik ?? 0} historik-ændringer</>}</li>)}</ul>}
          <p>Vielser der bliver stående: {(preview.vielser_staar ?? []).join(', ') || 'ingen'}.</p>
        </>}
        {(preview.medier_skjules?.length ?? 0) > 0 && <p>Billeder der bevares med deres koblinger til andre end profilen (også til en bevaret familie), men skjules for læserne (en redaktør kan frigive dem igen): {preview.medier_skjules!.join(', ')}.</p>}
        <h3>Blokeringer</h3>
        {preview.blokeringer.length ? <ul>{preview.blokeringer.map((b, i) => <li key={i}>{purgeLabels[b.art] ?? b.art}<details><summary>Detaljer</summary><code>{JSON.stringify(b)}</code></details></li>)}</ul> : <p>Ingen blokeringer.</p>}
        <h3>Advarsler</h3>
        {preview.levende_bruger && <p>Profilen er knyttet til en levende bruger. Koblingen til profilen fjernes.</p>}
        {preview.advarsler.length ? <ul>{preview.advarsler.map((a, i) => <li key={i}>{purgeLabels[a.art] ?? a.art}<details><summary>Detaljer</summary><code>{JSON.stringify(a)}</code></details></li>)}</ul> : <p>Ingen øvrige advarsler.</p>}
        <h3>Til kontrol</h3>
        {/* Review 37 P10 (ceremoni 2): fund, der kun er et id-tal, står for sig (sammenklappet), så navnefund ikke drukner. */}
        {kontrolListe(preview.til_kontrol.map((k, i) => ({ k, i })).filter(({ k }) => k.grund !== 'kun_id'))}
        {(() => {
          const tal = preview.til_kontrol.map((k, i) => ({ k, i })).filter(({ k }) => k.grund === 'kun_id');
          return tal.length > 0 && <details>
            <summary>Kun et id-tal ({tal.length}) — ofte et årstal, sidetal eller en anden talværdi i kildedata</summary>
            {kontrolListe(tal)}
          </details>;
        })()}
        <label>Skriv personens id for at bekræfte
          <input aria-label="Personens id" value={typedId} onChange={(e) => setTypedId(e.target.value)} disabled={busy || done} autoComplete="off" />
        </label>
      </>}
      {error && <div role="alert"><p>{error.tekst}</p></div>}
      {error && !done && <button type="button" disabled={busy || loading} onClick={() => setRevision((n) => n + 1)}>Hent ny forhåndsvisning</button>}
      {result?.kind === 'dry-run' && <p role="status">Dry-run: ingen data eller filer er slettet.</p>}
      {done && <p role="status">{alleredeSlettet
        ? 'Profilen var allerede slettet (svaret på sletningen nåede ikke frem). Filerne i udbakken er ryddet op.'
        : 'Profilen er slettet.'}</p>}
      {result?.storageAdvarsel && <p role="alert">{result.storageAdvarsel}</p>}
      <div style={{ display: 'flex', gap: 12, marginTop: 20 }}>
        <button type="button" disabled={busy} onClick={onClose}>Luk</button>
        <button type="button" disabled={!canDelete} onClick={perform}>Slet helt (kan ikke fortrydes)</button>
      </div>
      {dryRun && <p>Dry-run er slået til.</p>}
    </section>
  </div>;
}
