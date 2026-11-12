// Sidehovedet (navigation model 2): Personer · Slægter ▾ · Slægtskab, søgefelt på tværs af
// slægterne, login og »Redaktion ↗« kun for redaktionen. Menuen åbnes ved klik, Enter eller pil
// ned — aldrig ved hover. »Historie« vises ikke, før dens sider findes (overdragelsen: kun sider,
// der findes; ingen »kommer«-punkter).
import { useState, type ReactNode, type RefObject } from 'react';
import { Link } from '../Link';
import { navigate } from '../router';
import { soegPath, type Slaegt } from '../data/nav';
import { SlaegterMenu } from './SlaegterMenu';
import { T } from '../theme';

export type HovedpunktAktiv = 'personer' | 'slaegter' | 'slaegtskab' | null;

const MENU_ID = 'slaegter-menu';

export function Sidehoved({ aktiv, menuAaben, setMenuAaben, menuKnap, slaegter, senestSlaegt, aktivSlaegt, onVaelgSlaegt,
  onPersoner, onSlaegtskab, onForside, loggetInd, onLogin, onLogout, visRedaktion, ekstra }: {
  aktiv: HovedpunktAktiv;
  menuAaben: boolean;
  setMenuAaben: (aaben: boolean, returFokus?: boolean) => void;
  menuKnap: RefObject<HTMLButtonElement>;
  slaegter: readonly Slaegt[];
  senestSlaegt: string | null;
  aktivSlaegt: string | null;
  onVaelgSlaegt: (slug: string) => void;
  onPersoner: () => void;
  onSlaegtskab: () => void;
  onForside: () => void;
  loggetInd: boolean;
  onLogin: () => void;
  onLogout: () => void;
  visRedaktion: boolean;
  ekstra?: ReactNode; // fx »Det er mig«-monogrammet
}) {
  const [q, setQ] = useState('');
  const punkt = (on: boolean) => ({
    display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600,
    color: on ? T.bordeaux : T.inkSecondary, background: on ? T.bordeauxTint : 'transparent',
    padding: '10px 14px', borderRadius: 11, border: 0, textDecoration: 'none', cursor: 'pointer',
  } as const);
  const slaegterAktiv = aktiv === 'slaegter' || menuAaben;
  const sekundaer = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '10px 18px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' } as const;

  return (
    <header style={{ flex: 'none', position: 'relative', zIndex: 30, background: T.surfaceRaised, borderBottom: `1px solid ${T.line}` }}>
      <div style={{ maxWidth: 1440, margin: '0 auto', padding: '12px 24px', display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '12px 28px' }}>
        <Link href="/" onNavigate={onForside} style={{ display: 'flex', alignItems: 'center', gap: 12, textDecoration: 'none', color: T.ink }}>
          <img src="/daf-logo.png" alt="" style={{ width: 40, height: 40, objectFit: 'contain' }} />
          <span style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, lineHeight: 1 }}>Danmarks Adels Aarbog</span>
        </Link>
        <nav aria-label="Hovedmenu" style={{ display: 'flex', flexWrap: 'wrap', gap: 4, flex: '1 1 auto' }}>
          <Link href={soegPath()} onNavigate={onPersoner} aria-current={aktiv === 'personer' ? 'page' : undefined} style={punkt(aktiv === 'personer')}>Personer</Link>
          <button ref={menuKnap} type="button" aria-expanded={menuAaben} aria-controls={MENU_ID}
            onClick={() => setMenuAaben(!menuAaben)}
            onKeyDown={(e) => { if (e.key === 'ArrowDown') { e.preventDefault(); setMenuAaben(true); } }}
            style={punkt(slaegterAktiv)}>
            Slægter
            <svg width={12} height={12} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
              <path d={menuAaben ? 'M5 12.5 10 7l5 5.5' : 'M5 7.5 10 13l5-5.5'} />
            </svg>
          </button>
          <Link href="/slaegtskab" onNavigate={onSlaegtskab} aria-current={aktiv === 'slaegtskab' ? 'page' : undefined} style={punkt(aktiv === 'slaegtskab')}>Slægtskab</Link>
        </nav>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 12 }}>
          <form role="search" onSubmit={(e) => { e.preventDefault(); navigate(soegPath(q.trim())); setQ(''); }} style={{ display: 'flex' }}>
            <label htmlFor="sidehoved-soeg" style={{ position: 'absolute', left: -9999 }}>Søg i Aarbogen</label>
            <input id="sidehoved-soeg" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Søg person i Aarbogen"
              style={{ width: 240, maxWidth: '100%', fontFamily: T.sans, fontSize: 14, lineHeight: '20px', padding: '10px 14px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceGround, color: T.ink }} />
          </form>
          {loggetInd
            ? <button type="button" onClick={onLogout} style={sekundaer}>Log ud</button>
            : <button type="button" onClick={onLogin} style={sekundaer}>Log ind</button>}
          {ekstra}
          {visRedaktion && <Link href="/redaktion" style={{ fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux }}>Redaktion ↗</Link>}
        </div>
      </div>
      <SlaegterMenu id={MENU_ID} open={menuAaben} onClose={(retur) => setMenuAaben(false, retur)} slaegter={slaegter}
        senest={senestSlaegt} aktiv={aktivSlaegt} onVaelg={onVaelgSlaegt} opener={menuKnap} />
    </header>
  );
}
