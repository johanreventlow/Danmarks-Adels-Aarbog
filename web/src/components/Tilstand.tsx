// Tom side eller fejl, skrevet til læseren (tegningen »Tomme sider og fejl«, webredesign fase 0):
// en lille etiket, en overskrift i ord og en forklaring uden tekniske detaljer. Rå fejl hører
// til i konsollen, ikke her. Handlinger (knapper/links) lægges som children.
import type { ReactNode } from 'react';
import { T } from '../theme';

export function Tilstand({ etiket, titel, children, handlinger, fejl = false }: {
  etiket: string; titel: string; children: ReactNode; handlinger?: ReactNode; fejl?: boolean;
}) {
  return (
    <section role={fejl ? 'alert' : undefined} style={{ maxWidth: 560, background: T.paper, border: `1px solid ${fejl ? T.bordeaux : 'rgba(34,31,26,.10)'}`, borderRadius: 14, padding: 32, display: 'flex', flexDirection: 'column', gap: 12, fontFamily: T.sans }}>
      <p style={{ margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', letterSpacing: '.16em', textTransform: 'uppercase', color: fejl ? T.bordeaux : T.muted }}>{etiket}</p>
      <h2 style={{ margin: 0, fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1.1, color: T.ink }}>{titel}</h2>
      <div style={{ margin: 0, fontSize: 15, lineHeight: '24px', color: '#3d382f' }}>{children}</div>
      {handlinger && <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 6 }}>{handlinger}</div>}
    </section>
  );
}

// Knapstile fra tegningen: primær (bordeaux) og sekundær (papir med kant).
export const tilstandPrimaer = { fontFamily: T.sans, fontSize: 14, fontWeight: 600, lineHeight: '20px', padding: '11px 18px', borderRadius: 11, border: 0, background: T.bordeaux, color: T.paper, cursor: 'pointer', textDecoration: 'none' } as const;
export const tilstandSekundaer = { fontFamily: T.sans, fontSize: 14, fontWeight: 600, lineHeight: '20px', padding: '11px 18px', borderRadius: 11, border: '1px solid rgba(34,31,26,.18)', background: T.paper, color: T.ink, cursor: 'pointer', textDecoration: 'none' } as const;
