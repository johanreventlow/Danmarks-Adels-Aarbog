// Review 37 P11 (projektejeren 2026-11-22): »kan fortrydes« skal holde efter genindlæsning. Redaktionens fælles liste over
// personer slettet med den fortrydelige sletning (red_slettede_personer), med »Fortryd sletning« pr. sletning
// (red_fortryd_change_set). En person slettet helt (GDPR) står ikke her: den sletning tager historikken med.
import { useEffect, useRef, useState } from 'react';
import { fetchSlettedePersoner, type SlettetPerson } from '../data/redaktionRead';
import { erFortrydKonflikt, oversaetFejl } from '../data/redaktionWrite';
import { T } from '../theme';

type Props = {
  role: string | undefined; dryRun: boolean;
  load?: (limit: number) => Promise<SlettetPerson[]>;
  // Fortryd ét ændringssæt (force: overskriv nyere ændringer). Returnerer om det kun var dry-run; kaster ved fejl.
  fortryd: (r: SlettetPerson, opts?: { force?: boolean }) => Promise<{ dryRun: boolean }>;
  revision?: number;
};

// Review 37 R37P11-1 (ceremoni 2): listen hentes 100 ad gangen op til databasens loft (red_slettede_personer: 500).
const SIDE = 100;
const LOFT = 500;

const naar = (iso: string) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString('da-DK', { dateStyle: 'medium', timeStyle: 'short' });
};

export function SlettedePersoner({ role, dryRun, load = fetchSlettedePersoner, fortryd, revision = 0 }: Props) {
  const [rows, setRows] = useState<SlettetPerson[] | null>(null);
  const [fejl, setFejl] = useState('');
  const [genhent, setGenhent] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [rowFejl, setRowFejl] = useState<Record<string, string>>({});
  const [status, setStatus] = useState('');
  const [konfliktId, setKonfliktId] = useState<string | null>(null);
  const [limit, setLimit] = useState(SIDE);
  const writing = useRef(false);
  const redaktion = role === 'redaktion';

  useEffect(() => {
    if (!redaktion) return;
    let active = true;
    setFejl('');
    load(limit).then((r) => { if (active) setRows(r); })
      .catch((e: unknown) => { if (active) setFejl(oversaetFejl(String((e as Error)?.message ?? e))); });
    return () => { active = false; };
  }, [load, redaktion, revision, genhent, limit]);

  if (!redaktion) return <div style={{ padding: 24 }}>Kun redaktionen kan se slettede personer.</div>;

  const udfoer = async (r: SlettetPerson, force = false) => {
    if (writing.current) return;
    writing.current = true; setBusy(r.changeSetId); setStatus(''); setKonfliktId(null);
    setRowFejl((f) => { const n = { ...f }; delete n[r.changeSetId]; return n; });
    try {
      const res = force ? await fortryd(r, { force: true }) : await fortryd(r);
      if (res.dryRun) {
        setStatus('Dry-run: intet er fortrudt.');
      } else {
        setRows((rs) => (rs ?? []).filter((x) => x.changeSetId !== r.changeSetId));
        setStatus(`${r.navn ?? `Person ${r.personId}`} (id ${r.personId}) er genskabt.`);
      }
    } catch (e) {
      const raw = String((e as Error)?.message ?? e);
      // Nyere ændringer rører samme data: tilbyd tvangsvalget som i historikpanelet (HistorikPanel.tsx).
      if (!force && erFortrydKonflikt(raw)) setKonfliktId(r.changeSetId);
      else setRowFejl((f) => ({ ...f, [r.changeSetId]: oversaetFejl(raw) }));
    } finally { writing.current = false; setBusy(null); }
  };

  return <section aria-labelledby="slettede-titel" style={{ padding: '24px 30px 60px', maxWidth: 860 }}>
    <h2 id="slettede-titel" style={{ fontFamily: T.serif, fontSize: 26, fontWeight: 600, margin: 0 }}>Slettede personer</h2>
    <p style={{ fontSize: 14, lineHeight: 1.5, color: T.inkSecondary }}>Personer slettet med »Slet (kan fortrydes)«. Fortryd sletningen for at få personen og dens oplysninger tilbage. Personer, der er slettet helt (GDPR), står ikke her — den sletning kan ikke fortrydes.</p>
    {status && <p role="status">{status}</p>}
    {!rows && !fejl && <p role="status">Henter slettede personer…</p>}
    {fejl && <div role="alert"><p>Listen kunne ikke hentes: {fejl}</p>
      <button type="button" onClick={() => setGenhent((n) => n + 1)}>Hent igen</button></div>}
    {rows && rows.length === 0 && <p>Ingen slettede personer, der kan fortrydes.</p>}
    {rows && rows.length > 0 && <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
      <thead><tr style={{ textAlign: 'left', color: T.inkMuted, fontSize: 12 }}>
        <th style={{ padding: '6px 8px' }}>Navn</th><th style={{ padding: '6px 8px' }}>Id</th>
        <th style={{ padding: '6px 8px' }}>Slettet</th><th style={{ padding: '6px 8px' }}>Af</th><th style={{ padding: '6px 8px' }} />
      </tr></thead>
      <tbody>{rows.map((r) => <tr key={r.changeSetId} style={{ borderTop: `1px solid ${T.line}` }}>
        <td style={{ padding: '8px' }}>{r.navn ?? '(uden navn)'}</td>
        <td style={{ padding: '8px', fontFamily: T.mono, fontSize: 12 }}>{r.personId}</td>
        <td style={{ padding: '8px' }}>{naar(r.slettetNaar)}</td>
        <td style={{ padding: '8px' }}>{r.actorNavn ?? 'ukendt'}</td>
        <td style={{ padding: '8px', textAlign: 'right' }}>
          <button type="button" disabled={busy !== null} onClick={() => udfoer(r)}
            aria-label={`Fortryd sletning af ${r.navn ?? `person ${r.personId}`}`}
            style={{ fontSize: 13, fontWeight: 600, borderRadius: 8, padding: '6px 12px', border: `1px solid ${T.bordeaux}`, background: T.surfaceRaised, color: T.bordeaux, cursor: busy ? 'not-allowed' : 'pointer' }}>
            {busy === r.changeSetId ? 'Fortryder…' : 'Fortryd sletning'}
          </button>
          {rowFejl[r.changeSetId] && <p role="alert" style={{ color: T.danger, margin: '6px 0 0', textAlign: 'left' }}>{rowFejl[r.changeSetId]}</p>}
          {konfliktId === r.changeSetId && <div role="alert" style={{ margin: '6px 0 0', textAlign: 'left' }}>
            <p style={{ margin: '0 0 6px' }}>Nyere ændring rører samme data — fortrydes der alligevel, overskrives den.</p>
            <button type="button" disabled={busy !== null} onClick={() => udfoer(r, true)}
              aria-label={`Fortryd alligevel: ${r.navn ?? `person ${r.personId}`}`}
              style={{ fontSize: 13, fontWeight: 600, borderRadius: 8, padding: '6px 12px', border: `1px solid ${T.danger}`, background: T.surfaceRaised, color: T.danger, marginRight: 8 }}>
              Fortryd alligevel
            </button>
            <button type="button" onClick={() => setKonfliktId(null)}
              style={{ fontSize: 13, borderRadius: 8, padding: '6px 12px', border: `1px solid ${T.line}`, background: T.surfaceRaised }}>Annullér</button>
          </div>}
        </td>
      </tr>)}</tbody>
    </table>}
    {rows && rows.length >= limit && limit < LOFT && <button type="button" onClick={() => setLimit((n) => Math.min(n + SIDE, LOFT))}
      style={{ marginTop: 12, fontSize: 13, borderRadius: 8, padding: '6px 12px', border: `1px solid ${T.line}`, background: T.surfaceRaised }}>Vis flere</button>}
    {rows && rows.length >= LOFT && <p style={{ fontSize: 12.5, color: T.inkMuted }}>Viser de 500 nyeste sletninger.</p>}
    {dryRun && <p style={{ fontSize: 12.5 }}>Dry-run er slået til.</p>}
  </section>;
}
