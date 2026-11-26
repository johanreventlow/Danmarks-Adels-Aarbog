import { useEffect, useState } from 'react';
import type { Change } from '../data/redaktionWrite';
import { T } from '../theme';

// Review 37 R37P11-2 (projektejeren 26/11: »begge veje, med advarsel«). Levende → afdød kan gøre personen synlig for
// gæster, så den retning kræver en ekstra bekræftelse; afdød → levende skjuler og sendes straks. Ændringen er
// fortrydelig i historikken (red_set_levende åbner sit eget ændringssæt).
type Props = {
  personId: string; levende: boolean; privat: boolean;
  run: (c: Change, label: string) => Promise<unknown>;
};

export function LevendeKnap({ personId, levende, privat, run }: Props) {
  const [bekraeft, setBekraeft] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => { setBekraeft(false); }, [personId, levende]);
  const saet = async (ny: boolean) => {
    setBusy(true);
    try { await run({ art: 'setLevende', subjektType: 'person', subjektId: personId, payload: { levende: ny } }, 'Levende'); }
    finally { setBusy(false); setBekraeft(false); }
  };
  const knap = { fontSize: 12.5, fontWeight: 600, borderRadius: 7, padding: '5px 10px', cursor: 'pointer', fontFamily: 'inherit' } as const;
  return <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
    <button type="button" aria-pressed={levende} disabled={busy}
      onClick={() => (levende ? setBekraeft(true) : void saet(true))}
      style={{ display: 'flex', alignItems: 'center', gap: 8, background: levende ? T.bordeauxTint : T.surfaceGround,
        border: `1.5px solid ${levende ? T.bordeaux : 'rgba(34,31,26,.16)'}`, borderRadius: 8, padding: '6px 11px',
        cursor: 'pointer', fontFamily: 'inherit' }}>
      <span aria-hidden="true" style={{ width: 26, height: 15, borderRadius: 8, background: levende ? T.bordeaux : '#cfc6b5', position: 'relative' }}>
        <span style={{ position: 'absolute', top: 1.5, left: levende ? 12.5 : 1.5, width: 11, height: 11, borderRadius: '50%', background: '#fff' }} />
      </span>
      <span style={{ fontSize: 13, fontWeight: 600, color: levende ? T.bordeaux : T.inkMuted }}>Levende</span>
    </button>
    {bekraeft && <div role="alertdialog" aria-labelledby={`levende-advarsel-${personId}`}
      style={{ maxWidth: 300, background: T.dangerTint, borderRadius: 9, padding: '10px 12px', fontSize: 13 }}>
      <p id={`levende-advarsel-${personId}`} style={{ margin: 0, fontWeight: 600 }}>Sæt personen som afdød?</p>
      <p style={{ margin: '6px 0 0' }}>{privat
        ? 'Personen er markeret privat og forbliver skjult for gæster, indtil privat slås fra.'
        : 'Personen og dens oplysninger bliver synlige for gæster på siden. Vil du skjule personen alligevel, så slå »Privat« til først.'}
        {' '}Ændringen kan fortrydes i historikken.</p>
      <div style={{ display: 'flex', gap: 8, marginTop: 8, justifyContent: 'flex-end' }}>
        <button type="button" disabled={busy} onClick={() => setBekraeft(false)} style={{ ...knap, background: T.surfaceRaised, border: '1px solid rgba(34,31,26,.2)' }}>Annullér</button>
        <button type="button" disabled={busy} onClick={() => void saet(false)} style={{ ...knap, background: T.danger, color: '#fff', border: 'none' }}>Ja, sæt som afdød</button>
      </div>
    </div>}
  </div>;
}
