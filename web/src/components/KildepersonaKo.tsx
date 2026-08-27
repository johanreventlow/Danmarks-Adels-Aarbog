import { useEffect, useState } from 'react';
import { fetchRedaktionPersoner, type RedPerson } from '../data/redaktionRead';
import {
  decideSourcePersona, fetchSourcePersonaDetail, fetchSourcePersonaQueue, type SourcePersonaAction, type SourcePersonaDetail, type SourcePersonaQueueRow,
} from '../data/sourcePersona';

const PAGE_SIZE = 50;

function sourceIdFromInput(value: string): number | null {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

// Denne flade behandler kildepersoner; den viser eller muterer aldrig den
// offentlige personprojektion. Et menneske vælger kun "samme" efter at have
// åbnet og set mindst én ordret kildemention.
export function KildepersonaKo({ role }: { role?: string }) {
  const [rows, setRows] = useState<SourcePersonaQueueRow[]>([]);
  const [status, setStatus] = useState('proposed');
  const [sourceIdInput, setSourceIdInput] = useState('');
  const [hasMore, setHasMore] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [detail, setDetail] = useState<SourcePersonaDetail | null>(null);
  const [candidates, setCandidates] = useState<RedPerson[]>([]);
  const [candidateId, setCandidateId] = useState('');
  const [note, setNote] = useState('');
  const sourceId = sourceIdFromInput(sourceIdInput);

  const load = async (cursor: string | null = null, append = false) => {
    try {
      setError('');
      const page = await fetchSourcePersonaQueue(status, sourceId, cursor);
      setRows((previous) => append ? [...previous, ...page] : page);
      setHasMore(page.length === PAGE_SIZE);
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    }
  };

  useEffect(() => {
    if (role !== 'redaktion') return;
    setDetail(null);
    setCandidates([]);
    setCandidateId('');
    setNote('');
    void load();
  }, [role, status, sourceIdInput]);

  if (role !== 'redaktion') return <div style={{ padding: 24 }}>Kun redaktionen kan se kildepersonaer.</div>;

  const showEvidence = async (row: SourcePersonaQueueRow) => {
    try {
      setError('');
      const [loadedDetail, loadedCandidates] = await Promise.all([
        fetchSourcePersonaDetail(row.sourcePersonaId), fetchRedaktionPersoner(),
      ]);
      setDetail(loadedDetail);
      setCandidates(loadedCandidates);
      setCandidateId('');
      setNote('');
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    }
  };

  const decide = async (row: SourcePersonaQueueRow, action: SourcePersonaAction) => {
    if (!detail || detail.persona.sourcePersonaId !== row.sourcePersonaId || !detail.mentions.length) {
      setError('Åbn først den ordrette kildevisning; uden synligt grundlag må der ikke afgøres.');
      return;
    }
    const target = action === 'same' ? sourceIdFromInput(candidateId) : null;
    if (action === 'same' && target === null) {
      setError('Vælg en kanonisk kandidat før samme-afgørelsen.');
      return;
    }
    if (!note.trim()) {
      setError('Skriv en begrundelse med det synlige kildegrundlag.');
      return;
    }
    setBusy(row.sourcePersonaId);
    setError('');
    try {
      await decideSourcePersona(row.sourcePersonaId, row.version, action, target, note);
      await load();
      setDetail(null);
      setCandidates([]);
      setCandidateId('');
      setNote('');
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    } finally {
      setBusy(null);
    }
  };

  return <section style={{ padding: 24, maxWidth: 920 }}>
    <h1 style={{ marginTop: 0 }}>Kildepersonaer</h1>
    <p>Forekomster i en bogkilde. En afgørelse ændrer ikke den offentlige visning og er altid versionskontrolleret.</p>
    <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
      <label>Status <select value={status} onChange={(e) => setStatus(e.target.value)}>
        {['proposed', 'accepted', 'rejected', 'unresolved'].map((item) => <option key={item}>{item}</option>)}
      </select></label>
      <label>Kilde-id <input value={sourceIdInput} inputMode="numeric" onChange={(e) => setSourceIdInput(e.target.value)} /></label>
    </div>
    {error && <p role="alert" style={{ color: '#8a2b2b' }}>{error}</p>}
    {rows.map((row) => <article key={row.sourcePersonaId} style={{ marginTop: 12, padding: 12, border: '1px solid #cabfa9', borderRadius: 8 }}>
      <strong>{row.personaKey}</strong> · kilde {row.sourceId} · {row.mentionCount} omtaler · v{row.version}
      <div style={{ marginTop: 8, display: 'flex', gap: 8 }}>
        <button onClick={() => void showEvidence(row)}>Vis kildegrundlag</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => void decide(row, 'same')}>Samme person</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => void decide(row, 'different')}>Forskellig</button>
        <button disabled={busy === row.sourcePersonaId} onClick={() => void decide(row, 'unresolved')}>Uafklaret</button>
      </div>
    </article>)}
    {hasMore && <button style={{ marginTop: 12 }} onClick={() => void load(rows[rows.length - 1]?.sourcePersonaId ?? null, true)}>Hent næste side</button>}
    {detail && <aside style={{ marginTop: 16, padding: 12, background: '#f4efe6', borderRadius: 8 }}>
      <strong>Ordret kildegrundlag</strong>
      {detail.mentions.map((mention, index) => <div key={index} style={{ marginTop: 8 }}>
        <q>{mention.verbatimText}</q> · s. {mention.pageFrom}{mention.pageTo !== mention.pageFrom ? `–${mention.pageTo}` : ''}
        {mention.textVersions.map((version) => <div key={version.version} style={{ fontSize: 12 }}>tekst v{version.version}: {version.verbatimText}</div>)}
      </div>)}
      {detail.interpretations.map((interpretation, index) => <div key={index} style={{ marginTop: 8, fontSize: 12 }}>
        Fortolkning: {interpretation.predicate} · {interpretation.status} · sikkerhed {interpretation.confidence}
      </div>)}
      <div style={{ display: 'grid', gap: 8, marginTop: 12 }}>
        <label>Kanonisk kandidat <select value={candidateId} onChange={(e) => setCandidateId(e.target.value)}>
          <option value="">Vælg kun ved “samme”</option>
          {candidates.map((candidate) => <option key={candidate.id} value={candidate.id}>{candidate.navn} · #{candidate.id} · {candidate.aar}</option>)}
        </select></label>
        <label>Begrundelse <textarea value={note} onChange={(e) => setNote(e.target.value)} /></label>
      </div>
    </aside>}
    {!rows.length && !error && <p>Ingen forekomster i denne kø.</p>}
  </section>;
}
