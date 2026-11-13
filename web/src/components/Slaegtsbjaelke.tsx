// Slægtsbjælken (navigation model 2, tegningen »Navigation model 2 · slægtsbjælken (web)«): vises
// under sidehovedet på /slaegt/<slug>/* og navigerer mellem slægtens sider. Ikke på /person,
// /slaegtskab, /soeg, /min-side.
//
// Mærket er slægtens våben i sepia (SlaegtsMaerke), ellers monogrammet. Præsenslisten vises kun
// for redaktionen (fase 0; medlemmer får den i fase 8). Artikler vises ikke, før siden findes.
import { Link } from '../Link';
import { pathForMode, slaegtPath, type Mode, type Slaegt } from '../data/nav';
import { T } from '../theme';
import { SlaegtsMaerke } from './SlaegtsMaerke';

type Side = { mode: Mode; label: string; aktivFor: Mode[] };

export function Slaegtsbjaelke({ slaegt, aktivMode, visPraesens, onGaaTil, onSkiftSlaegt }: {
  slaegt: Slaegt;
  aktivMode: Mode;
  visPraesens: boolean;
  onGaaTil: (m: Mode) => void;
  onSkiftSlaegt: (knap: HTMLElement) => void;
}) {
  const sider: Side[] = [
    { mode: 'about', label: 'Forside', aktivFor: ['about'] },
    { mode: 'tree', label: 'Stamtræ', aktivFor: ['tree'] },
    ...(visPraesens ? [{ mode: 'praesens' as Mode, label: 'Præsensliste', aktivFor: ['praesens' as Mode] }] : []),
    { mode: 'estates', label: 'Besiddelser', aktivFor: ['estates', 'kort'] },
    { mode: 'arms', label: 'Våben', aktivFor: ['arms'] },
  ];
  return (
    <nav aria-label={`Slægten ${slaegt.navn}`} style={{ flex: 'none', background: T.surfaceSunken, borderBottom: `1px solid ${T.line}` }}>
      <div style={{ maxWidth: 1440, margin: '0 auto', padding: '8px 24px', display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '8px 20px' }}>
        <Link href={slaegtPath(slaegt.slug)} onNavigate={() => onGaaTil('about')}
          style={{ display: 'flex', alignItems: 'center', gap: 10, textDecoration: 'none', color: T.ink, paddingRight: 16, borderRight: `1px solid ${T.lineStrong}` }}>
          <SlaegtsMaerke slaegt={slaegt} size={32} monogram={
            <span aria-hidden="true" style={{ width: 28, height: 28, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', boxShadow: `inset 0 0 0 2px ${T.surfaceSunken}, inset 0 0 0 2.5px rgba(136,26,51,.28)`, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 15, fontWeight: 600, color: T.bordeaux }}>{slaegt.navn[0]}</span>
          } />
          <span style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{slaegt.navn}</span>
        </Link>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 2, flex: '1 1 auto' }}>
          {sider.map((s) => {
            const aktiv = s.aktivFor.includes(aktivMode);
            return (
              <Link key={s.mode} href={pathForMode(s.mode, slaegt.slug)} onNavigate={() => onGaaTil(s.mode)} aria-current={aktiv ? 'page' : undefined}
                style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, lineHeight: '20px', textDecoration: 'none', padding: '8px 12px', borderRadius: 9,
                  color: aktiv ? T.bordeaux : T.inkSecondary, background: aktiv ? T.surfaceRaised : 'transparent' }}>{s.label}</Link>
            );
          })}
        </div>
        <button type="button" onClick={(e) => onSkiftSlaegt(e.currentTarget)}
          style={{ fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux, background: 'transparent', border: 0, padding: '8px 4px', cursor: 'pointer' }}>Skift slægt</button>
      </div>
    </nav>
  );
}
