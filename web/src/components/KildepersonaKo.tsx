import { useEffect, useState } from 'react';
import {
  decideSourcePersona, fetchSourcePersonaDetail, fetchSourcePersonaQueue, type SourcePersonaAction, type SourcePersonaDetail, type SourcePersonaQueueRow,
} from '../data/sourcePersona';

// Denne flade behandler kildepersoner; den viser eller muterer aldrig den
// offentlige personprojektion. Et menneske vælger kun "samme" efter at have
// åbnet og set mindst én ordret kildemention.
export function KildepersonaKo({ role }: { role: string }) {
  const [rows, setRows] = useState<SourcePersonaQueueRow[]>([]);
  const [status, setStatus] = useState('proposed');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [detail, setDetail] = useState<SourcePersonaDetail | null>(null);
  const load = () => fetchSourcePersonaQueue(status).then(setRows).catch((e) => setError(String(e.message ?? e)));
  useEffect(() => { if (role === 'redaktion') load(); }, [role, status]);
  if (role !== 'redaktion') return <div style={{ padding: 24 }}>Kun redaktionen kan se kildepersonaer.</div>;
  const decide = async (row: SourcePersonaQueueRow, action: SourcePersonaAction) => {
    if (!detail || detail.persona.sourcePersonaId !== row.sourcePersonaId || !detail.mentions.length) {
      setError('Åbn først den ordrette kildevisning; uden synligt grundlag må der ikke afgøres.'); return;
    }
    const note = window.prompt('Begrundelse med det synlige kildegrundlag:')?.trim() ?? '';
    if (!note) return;
    const target = action === 'same' ? Number(window.prompt('Kanonisk person-id:')) : null;
    setBusy(row.sourcePersonaId); setError('');
    try { await decideSourcePersona(row.sourcePersonaId, row.version, action, target, note); await load(); }
    catch (e) { setError(String(e instanceof Error ? e.message : e)); }
    finally { setBusy(null); }
  };
  return <section style={{ padding: 24, maxWidth: 920 }}>
    <h1 style={{ marginTop: 0 }}>Kildepersonaer</h1>
    <p>Forekomster i en bogkilde. En afgørelse ændrer ikke den offentlige visning og er altid versionskontrolleret.</p>
    <label>Status <select value={status} onChange={(e) => setStatus(e.target.value)}>
      {['proposed','accepted','rejected','unresolved'].map((s) => <option key={s}>{s}</option>)}
    </select></label>
    {error && <p role="alert" style={{ color: '#8a2b2b' }}>{error}</p>}
    {rows.map((row) => <article key={row.sourcePersonaId} style={{ marginTop: 12, padding: 12, border: '1px solid #cabfa9', borderRadius: 8 }}>
      <strong>{row.personaKey}</strong> · kilde {row.sourceId} · {row.mentionCount} omtaler · v{row.version}
      <div style={{ marginTop: 8, display: 'flex', gap: 8 }}>
        <button onClick={() => fetchSourcePersonaDetail(row.sourcePersonaId).then(setDetail).catch((e) => setError(String(e.message ?? e)))}>Vis kildegrundlag</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => decide(row, 'same')}>Samme person</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => decide(row, 'different')}>Forskellig</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => decide(row, 'unresolved')}>Uafklaret</button>
      </div>
    </article>)}
    {detail && <aside style={{ marginTop: 16, padding: 12, background: '#f4efe6', borderRadius: 8 }}>
      <strong>Ordret kildegrundlag</strong>
      {detail.mentions.map((mention, i) => <div key={i} style={{ marginTop: 8 }}>
        <q>{mention.verbatimText}</q> · s. {mention.pageFrom}{mention.pageTo !== mention.pageFrom ? `–${mention.pageTo}` : ''}
        {mention.textVersions.map((version) => <div key={version.version} style={{ fontSize: 12 }}>tekst v{version.version}: {version.verbatimText}</div>)}
      </div>)}
      {detail.interpretations.map((interpretation, i) => <div key={i} style={{ marginTop: 8, fontSize: 12 }}>
        Fortolkning: {interpretation.predicate} · {interpretation.status} · sikkerhed {interpretation.confidence}
      </div>)}
    </aside>}
    {!rows.length && !error && <p>Ingen forekomster i denne kø.</p>}
  </section>;
}
