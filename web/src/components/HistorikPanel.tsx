// Ændringshistorik + fortryd-knap på person-siden i redaktøren (issue #144).
// Mobilens historik-skærm som skabelon (mobile/src/app/redaktion/historik/[id].tsx).
// Panelet henter selv sin liste men skriver ALDRIG selv: fortryd delegeres til onFortryd,
// som Redaktion.tsx implementerer gennem det delte submitChange-flow (dry-run/rolle/
// writeView). 'konflikt' er B9-divergensen ("nyere ændring rører samme data") — den vises
// som et eksplicit force-valg i panelet; tavs overskrivning findes ikke.
import { useCallback, useEffect, useState } from 'react';
import { T } from '../theme';
import { fetchHistorik, type HistPost } from '../data/historik';

export type FortrydUdfald = 'ok' | 'konflikt' | 'fejl';

export function HistorikPanel({ personId, onFortryd }: {
  personId: string;
  onFortryd: (changeSetId: string, force: boolean) => Promise<FortrydUdfald>;
}) {
  const [poster, setPoster] = useState<HistPost[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState('');
  const [konfliktId, setKonfliktId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const indlaes = useCallback(() => {
    setStatus('loading');
    fetchHistorik(personId)
      .then((hist) => { setPoster(hist); setStatus('ready'); })
      .catch((e) => { setFejl(String((e as Error)?.message ?? e)); setStatus('error'); });
  }, [personId]);
  useEffect(() => { indlaes(); }, [indlaes]);

  const startFortryd = useCallback(async (post: HistPost, force: boolean) => {
    setKonfliktId(null);
    setBusyId(post.id);
    try {
      const udfald = await onFortryd(post.id, force);
      if (udfald === 'konflikt') setKonfliktId(post.id);
      if (udfald === 'ok') indlaes();
    } finally {
      setBusyId(null);
    }
  }, [onFortryd, indlaes]);

  // Fire gensidigt udelukkende handlings-tilstande pr. post — tidlige returns frem for
  // indlejrede ternaries, så hver gren kan læses isoleret (/simplify-fund).
  function fortrydAction(post: HistPost) {
    if (post.reverteret) return <div style={{ fontSize: 11, color: T.muted3, marginTop: 5 }}>Fortrudt</div>;
    if (post.erFortryd) return null; // ingen events at spille baglæns — knappen ville være et tavst no-op
    if (konfliktId === post.id) {
      return (
        <div style={{ marginTop: 7, padding: '8px 10px', background: T.beige, border: '1px solid rgba(34,31,26,.15)', borderRadius: 8 }}>
          <div style={{ fontSize: 12.5, color: T.ink, marginBottom: 6 }}>
            Nyere ændring rører samme data — fortrydes der alligevel, overskrives den.
          </div>
          <span onClick={() => startFortryd(post, true)}
            style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginRight: 14 }}>
            Fortryd alligevel
          </span>
          <span onClick={() => setKonfliktId(null)}
            style={{ fontSize: 12, fontWeight: 600, color: T.muted, cursor: 'pointer' }}>
            Annullér
          </span>
        </div>
      );
    }
    return (
      <span onClick={() => (busyId ? undefined : startFortryd(post, false))}
        style={{ display: 'inline-block', marginTop: 5, fontSize: 12, fontWeight: 600,
          color: T.bordeaux, cursor: busyId ? 'wait' : 'pointer', opacity: busyId === post.id ? 0.5 : 1 }}>
        Fortryd
      </span>
    );
  }

  return (
    <div style={{ background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 12, padding: '14px 15px' }}>
      {status === 'loading' ? <div style={{ fontSize: 13.5, color: T.muted3 }}>Henter historik…</div> : null}
      {status === 'error' ? <div style={{ fontSize: 13, color: T.bordeaux }}>{fejl}</div> : null}
      {status === 'ready' && poster.length === 0 ? (
        <div style={{ fontSize: 12.5, color: T.muted3 }}>Ingen ændringer registreret.</div>
      ) : null}
      {status === 'ready' ? poster.map((post) => (
        <div key={post.id} style={{
          padding: '9px 0', borderBottom: '1px solid rgba(34,31,26,.07)',
          opacity: post.reverteret ? 0.55 : 1,
        }}>
          <div style={{ fontSize: 13.5, color: T.ink }}>{post.resume}</div>
          <div style={{ fontSize: 11.5, color: T.muted3, marginTop: 3, fontFamily: 'ui-monospace, monospace' }}>
            {post.hvem} · {post.hvornaar}
          </div>
          {fortrydAction(post)}
        </div>
      )) : null}
    </div>
  );
}
