import { useEffect, useRef, useState } from 'react';
import { executePurgeOprydning, fetchPurgeUdbakke, purgeFejl, purgeStorage, type PurgeFil } from '../data/personPurge';
import { submitChange } from '../data/redaktionWrite';

export function PersonPurgeUdbakke({ dryRun, role, revision }: { dryRun: boolean; role?: string; revision: number }) {
  const [rows, setRows] = useState<PurgeFil[]>([]);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [refresh, setRefresh] = useState(0);
  const running = useRef(false);
  useEffect(() => {
    let active = true;
    if (role !== 'redaktion') { setRows([]); setLoading(false); return; }
    setLoading(true); setError('');
    fetchPurgeUdbakke().then((files) => { if (active) setRows(files); })
      .catch((e: unknown) => { if (active) { setRows([]); setError(purgeFejl(e).tekst); } })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [revision, refresh, role]);
  const clean = async () => {
    if (running.current || role !== 'redaktion') return;
    running.current = true; setBusy(true); setNotice('');
    try {
      const res = await executePurgeOprydning({ dryRun, role }, { ...purgeStorage, submit: submitChange });
      setNotice(res.kind === 'dry-run' ? 'Dry-run: ingen filer er slettet eller kvitteret.' : res.storageAdvarsel ?? 'Oprydningen er gennemført.');
      setRefresh((n) => n + 1);
    } catch (e) { setError(purgeFejl(e).tekst); }
    finally { running.current = false; setBusy(false); }
  };
  if (role !== 'redaktion') return null;
  return <section aria-label="Filer der venter på sletning" style={{ padding: '16px 4px', borderTop: '1px solid #ccc', overflowWrap: 'anywhere' }}>
    <h3>Filer der venter på sletning</h3>
    {loading ? <p role="status">Henter filer…</p> : <>
      {!error && !rows.length && <p>Ingen filer venter.</p>}
      {!!rows.length && <ul>{rows.map((row) => <li key={JSON.stringify([row.bucket, row.sti])}>
        {row.bucket} / {row.sti} · {row.oprettet}
      </li>)}</ul>}
    </>}
    {error && <p role="alert">{error}</p>}
    {notice && <p role="status">{notice}</p>}
    <button type="button" disabled={busy || loading} onClick={() => setRefresh((n) => n + 1)}>Genindlæs filer</button>{' '}
    <button type="button" disabled={busy || loading || !rows.length || role !== 'redaktion'} onClick={clean}>Prøv oprydning igen</button>
  </section>;
}
