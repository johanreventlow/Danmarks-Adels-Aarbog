import { useEffect, useRef, useState } from 'react';
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
  samme_som_knudepunkt: 'Profilen er knudepunkt for andre profiler',
  link_i_tekst: 'En bevaret tekst linker til profilen eller dens data',
};

type Props = {
  personId: string; navn: string; dryRun: boolean;
  loadPreview?: (id: string) => Promise<PurgePreview>;
  execute: (opts: { personId: string; previewSha256: string; dryRun: boolean }) => Promise<PurgeResult>;
  onDeleted: () => void; onClose: () => void;
};
export function SletHeltDialog({ personId, navn, dryRun, loadPreview = fetchPurgePreview, execute, onDeleted, onClose }: Props) {
  const [preview, setPreview] = useState<PurgePreview | null>(null);
  const [typedId, setTypedId] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ReturnType<typeof purgeFejl> | null>(null);
  const [result, setResult] = useState<PurgeResult | null>(null);
  const [revision, setRevision] = useState(0);
  const writing = useRef(false);
  useEffect(() => {
    let active = true;
    setLoading(true); setPreview(null); setTypedId(''); setError(null); setResult(null);
    loadPreview(personId).then((p) => {
      if (!active) return;
      // Et forkert RPC-svar må ikke autorisere sletning af den valgte profil.
      if (String(p.person_id) !== personId || !/^[a-f0-9]{64}$/.test(p.sha256)) throw new Error('Ugyldig forhåndsvisning');
      setPreview(p);
    }).catch((e: unknown) => { if (active) setError(purgeFejl(e)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [personId, loadPreview, revision]);
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
    } catch (e) { setError(purgeFejl(e)); }
    finally { writing.current = false; setBusy(false); }
  };
  return <div style={{ position: 'fixed', inset: 0, zIndex: 100, background: 'rgba(0,0,0,.4)', display: 'grid', placeItems: 'center' }}>
    <section role="dialog" aria-modal="true" aria-labelledby="purge-title"
      style={{ background: T.surfaceRaised, color: T.ink, borderRadius: 12, padding: 24, width: 'min(760px, 90vw)', maxHeight: '90vh', overflowY: 'auto' }}>
      <h2 id="purge-title">Slet helt · {preview?.navn ?? navn} · id {personId}</h2>
      <p>Du sletter den rå profil med dette id, ikke den sammenfoldede person eller de andre profiler i samme_som-komponenten. Sletningen kan ikke fortrydes.</p>
      {loading && <p role="status">Henter forhåndsvisning…</p>}
      {preview && <>
        <h3>Antal pr. sted</h3>
        <ul>{Object.entries(preview.steder).map(([sted, rows]) => <li key={sted}>{sted}: {rows.length}
          <ul>{Object.entries(rows.reduce<Record<string, number>>((counts, row) => {
            const label = `${row.tabel} · ${row.handling}`; counts[label] = (counts[label] ?? 0) + 1; return counts;
          }, {})).map(([label, count]) => <li key={label}>{label}: {count}</li>)}</ul>
        </li>)}</ul>
        <h3>Familier</h3>
        <p>Slettes: {preview.familier_slettes.join(', ') || 'ingen'}. Bevares: {preview.familier_bevares.join(', ') || 'ingen'}.</p>
        <h3>Blokeringer</h3>
        {preview.blokeringer.length ? <ul>{preview.blokeringer.map((b, i) => <li key={i}>{purgeLabels[b.art] ?? b.art}<details><summary>Detaljer</summary><code>{JSON.stringify(b)}</code></details></li>)}</ul> : <p>Ingen blokeringer.</p>}
        <h3>Advarsler</h3>
        {preview.levende_bruger && <p>Profilen er knyttet til en levende bruger. Koblingen til profilen fjernes.</p>}
        {preview.advarsler.length ? <ul>{preview.advarsler.map((a, i) => <li key={i}>{purgeLabels[a.art] ?? a.art}<details><summary>Detaljer</summary><code>{JSON.stringify(a)}</code></details></li>)}</ul> : <p>Ingen øvrige advarsler.</p>}
        <h3>Til kontrol</h3>
        <ul>{preview.til_kontrol.map((k, i) => <li key={i}>
          <a href={`#purge-kontrol-${i}`}>{k.sted} · {k.tabel} · {JSON.stringify(k.pk)}</a>
        </li>)}</ul>
        {/* Også interne steder uden en redaktionseditor har et konkret linkmål og fuld PK. */}
        {preview.til_kontrol.map((k, i) => {
          const entity = k.tabel.replace(/^public\./, '');
          const href = ['person', 'family', 'narrative', 'media', 'source', 'estate'].includes(entity) && k.pk.id != null
            ? `/redaktion/${entity}/${encodeURIComponent(String(k.pk.id))}` : null;
          return <div key={i} id={`purge-kontrol-${i}`} tabIndex={-1} style={{ borderTop: `1px solid ${T.line}`, padding: 8 }}>
            <b>{k.sted} · {k.tabel}</b><p>{JSON.stringify(k.pk)} · {k.grund}</p>
            {href && <a href={href} target="_blank" rel="noreferrer">Åbn stedet i Redaktion</a>}
          </div>;
        })}
        <label>Skriv personens id for at bekræfte
          <input aria-label="Personens id" value={typedId} onChange={(e) => setTypedId(e.target.value)} disabled={busy || done} autoComplete="off" />
        </label>
      </>}
      {error && <div role="alert"><p>{error.tekst}</p></div>}
      {error && !done && <button type="button" disabled={busy || loading} onClick={() => setRevision((n) => n + 1)}>Hent ny forhåndsvisning</button>}
      {result?.kind === 'dry-run' && <p role="status">Dry-run: ingen data eller filer er slettet.</p>}
      {done && <p role="status">Profilen er slettet.</p>}
      {result?.storageAdvarsel && <p role="alert">{result.storageAdvarsel}</p>}
      <div style={{ display: 'flex', gap: 12, marginTop: 20 }}>
        <button type="button" disabled={busy} onClick={onClose}>Luk</button>
        <button type="button" disabled={!canDelete} onClick={perform}>Slet helt (kan ikke fortrydes)</button>
      </div>
      {dryRun && <p>Dry-run er slået til.</p>}
    </section>
  </div>;
}
