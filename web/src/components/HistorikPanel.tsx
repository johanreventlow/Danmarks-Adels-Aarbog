// Ændringshistorik + fortryd-knap på person-siden i redaktøren (issue #144).
// Mobilens historik-skærm som skabelon (mobile/src/app/redaktion/historik/[id].tsx).
// Panelet henter selv sin liste men skriver ALDRIG selv: fortryd delegeres til onFortryd,
// som Redaktion.tsx implementerer gennem det delte submitChange-flow (dry-run/rolle/
// writeView). 'konflikt' er B9-divergensen ("nyere ændring rører samme data") — den vises
// som et eksplicit force-valg i panelet; tavs overskrivning findes ikke.
import { useCallback, useEffect, useRef, useState } from 'react';
import { T } from '../theme';
import { fetchHistorik, type HistPost } from '../data/historik';

export type FortrydUdfald = 'ok' | 'konflikt' | 'fejl';

export function HistorikPanel({ personId, onFortryd }: {
  personId: string;
  onFortryd: (post: HistPost, force: boolean) => Promise<FortrydUdfald>;
}) {
  const [poster, setPoster] = useState<HistPost[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState('');
  const [konfliktId, setKonfliktId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  // Review 37 W2: kun det nyeste svar for den NUVÆRENDE person må sætte state. Et sent svar for en
  // tidligere person ville ellers vise dennes historik (og »Fortryd« med dens changeSetId) her.
  const genRef = useRef(0);
  const mountedRef = useRef(true);
  useEffect(() => { mountedRef.current = true; return () => { mountedRef.current = false; }; }, []);
  const personRef = useRef(personId);
  personRef.current = personId;
  useEffect(() => () => { genRef.current++; }, [personId]);
  const indlaes = useCallback(() => {
    const gen = ++genRef.current;
    setStatus('loading');
    fetchHistorik(personId)
      .then((hist) => { if (gen === genRef.current) { setPoster(hist); setStatus('ready'); } })
      .catch((e) => { if (gen === genRef.current) { setFejl(String((e as Error)?.message ?? e)); setStatus('error'); } });
  }, [personId]);
  useEffect(() => { setPoster([]); setKonfliktId(null); setBusyId(null); indlaes(); }, [indlaes]);

  const startFortryd = useCallback(async (post: HistPost, force: boolean) => {
    setKonfliktId(null);
    setBusyId(post.id);
    try {
      const udfald = await onFortryd(post, force);
      if (personRef.current !== personId) return; // personen er skiftet undervejs
      if (!mountedRef.current) return;
      if (udfald === 'konflikt') setKonfliktId(post.id);
      if (udfald === 'ok') indlaes();
    } finally {
      setBusyId(null);
    }
  }, [onFortryd, indlaes, personId]);

  // Fire gensidigt udelukkende handlings-tilstande pr. post — tidlige returns frem for
  // indlejrede ternaries, så hver gren kan læses isoleret (/simplify-fund).
  function fortrydAction(post: HistPost) {
    if (post.undoKind === 'publication_event' && post.canReverse === false) {
      return <div style={{ fontSize: 11, color: T.inkMuted, marginTop: 5 }}>{post.blockingReason ?? 'Denne publiceringshændelse kan ikke fortrydes.'}</div>;
    }
    if (post.reverteret) return <div style={{ fontSize: 11, color: T.inkMuted, marginTop: 5 }}>Fortrudt</div>;
    if (post.erFortryd) return null; // ingen events at spille baglæns — knappen ville være et tavst no-op
    if (konfliktId === post.id) {
      return (
        <div style={{ marginTop: 7, padding: '8px 10px', background: T.surfaceSunken, border: '1px solid rgba(34,31,26,.15)', borderRadius: 8 }}>
          <div style={{ fontSize: 12.5, color: T.ink, marginBottom: 6 }}>
            Nyere ændring rører samme data — fortrydes der alligevel, overskrives den.
          </div>
          <button type="button" onClick={() => startFortryd(post, true)}
            style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', marginRight: 14, border: 0, background: 'transparent', padding: 0 }}>
            Fortryd alligevel
          </button>
          <button type="button" onClick={() => setKonfliktId(null)}
            style={{ fontSize: 12, fontWeight: 600, color: T.inkMuted, cursor: 'pointer', border: 0, background: 'transparent', padding: 0 }}>
            Annullér
          </button>
        </div>
      );
    }
    return (
      <button type="button" disabled={busyId !== null} onClick={() => startFortryd(post, false)}
        style={{ display: 'inline-block', marginTop: 5, fontSize: 12, fontWeight: 600,
          color: T.bordeaux, cursor: busyId ? 'wait' : 'pointer', opacity: busyId === post.id ? 0.5 : 1, border: 0, background: 'transparent', padding: 0 }}>
        Fortryd
      </button>
    );
  }

  return (
    <div style={{ background: T.surfaceGround, border: `1px solid ${T.line}`, borderRadius: 12, padding: '14px 15px' }}>
      {status === 'loading' ? <div style={{ fontSize: 13.5, color: T.inkMuted }}>Henter historik…</div> : null}
      {status === 'error' ? <div style={{ fontSize: 13, color: T.bordeaux }}>{fejl}</div> : null}
      {status === 'ready' && poster.length === 0 ? (
        <div style={{ fontSize: 12.5, color: T.inkMuted }}>Ingen ændringer registreret.</div>
      ) : null}
      {status === 'ready' ? poster.map((post) => (
        <div key={post.id} style={{
          padding: '9px 0', borderBottom: '1px solid rgba(34,31,26,.07)',
          opacity: post.reverteret ? 0.55 : 1,
        }}>
          <div style={{ fontSize: 13.5, color: T.ink }}>{post.resume}</div>
          <div style={{ fontSize: 11.5, color: T.inkMuted, marginTop: 3, fontFamily: 'ui-monospace, monospace' }}>
            {post.hvem} · {post.hvornaar}
          </div>
          {fortrydAction(post)}
        </div>
      )) : null}
    </div>
  );
}
