// Sidehovedet (navigation model 2): Personer · Slægter ▾ · Slægtskab, søgefelt på tværs af
// slægterne, login og »Redaktion ↗« kun for redaktionen. Menuen åbnes ved klik, Enter eller pil
// ned — aldrig ved hover. »Historie« vises ikke, før dens sider findes (overdragelsen: kun sider,
// der findes; ingen »kommer«-punkter).
//
// Smal skærm (fase 9, tegningerne »Mobil – hovedside/personside«): én række med forsiden, »Din plads« og en menuknap.
// Menuen (søgefelt, hovedmenu, login, Redaktion) er en disclosure under sidehovedet med samme regler som Slægter-menuen.
// Går man Menu → Slægter, lukker menuen, og menuknappen er åbner for slægtsvælgeren (aria-controls skifter med), så
// der altid er én tilstedeværende knap, der styrer det åbne panel.
import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { useSmalSkaerm } from '../useSmalSkaerm';
import { Link } from '../Link';
import { navigate } from '../router';
import { soegPath, type Slaegt } from '../data/nav';
import { SlaegterMenu } from './SlaegterMenu';
import { T } from '../theme';
import { shadow } from '@daa/theme';

export type HovedpunktAktiv = 'personer' | 'slaegter' | 'slaegtskab' | null;

const MENU_ID = 'slaegter-menu';
const MOBILMENU_ID = 'mobilmenu';

export function Sidehoved({ aktiv, menuAaben, setMenuAaben, menuKnap, slaegter, senestSlaegt, aktivSlaegt, onVaelgSlaegt,
  onPersoner, onSlaegtskab, onForside, loggetInd, onLogin, onLogout, visRedaktion, ekstra, sti }: {
  aktiv: HovedpunktAktiv;
  menuAaben: boolean;
  setMenuAaben: (aaben: boolean, returFokus?: boolean, aabner?: HTMLElement | null) => void;
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
  sti: string; // aktuel adresse; et skift lukker mobilmenuen (også browserens tilbage-knap)
}) {
  const [q, setQ] = useState('');
  const smal = useSmalSkaerm();
  const [mobilAaben, setMobilAaben] = useState(false);
  const mobilPanel = useRef<HTMLDivElement>(null);
  useEffect(() => { setMobilAaben(false); }, [sti, smal]);
  useEffect(() => {
    if (!mobilAaben) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); setMobilAaben(false); menuKnap.current?.focus(); } };
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (mobilPanel.current?.contains(t) || menuKnap.current?.contains(t)) return;
      setMobilAaben(false);
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onDown);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('mousedown', onDown); };
  }, [mobilAaben, menuKnap]);
  const punkt = (on: boolean) => ({
    display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600,
    color: on ? T.bordeaux : T.inkSecondary, background: on ? T.bordeauxTint : 'transparent',
    padding: '10px 14px', borderRadius: 11, border: 0, textDecoration: 'none', cursor: 'pointer',
  } as const);
  const slaegterAktiv = aktiv === 'slaegter' || menuAaben;
  const sekundaer = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '10px 18px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' } as const;

  const soegeform = (
    <form role="search" onSubmit={(e) => { e.preventDefault(); navigate(soegPath(q.trim())); setQ(''); setMobilAaben(false); }} style={{ display: 'flex' }}>
      <label htmlFor="sidehoved-soeg" style={{ position: 'absolute', left: -9999 }}>Søg i Aarbogen</label>
      <input id="sidehoved-soeg" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Søg person i Aarbogen"
        style={{ width: smal ? '100%' : 240, maxWidth: '100%', fontFamily: T.sans, fontSize: 14, lineHeight: '20px', padding: smal ? '12px 14px' : '10px 14px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceGround, color: T.ink }} />
    </form>
  );
  const logind = loggetInd
    ? <button type="button" onClick={onLogout} style={sekundaer}>Log ud</button>
    : <button type="button" onClick={onLogin} style={sekundaer}>Log ind</button>;
  const redaktion = visRedaktion && <Link href="/redaktion" style={{ fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux }}>Redaktion ↗</Link>;
  const slaegterMenu = (
    <SlaegterMenu id={MENU_ID} open={menuAaben} onClose={(retur) => setMenuAaben(false, retur)} slaegter={slaegter}
      senest={senestSlaegt} aktiv={aktivSlaegt} onVaelg={onVaelgSlaegt} opener={menuKnap} />
  );

  if (smal) {
    const mobilPunkt = (on: boolean) => ({ ...punkt(on), display: 'flex', width: '100%', minHeight: 44, textAlign: 'left' } as const);
    const lukOg = (f: () => void) => () => { setMobilAaben(false); f(); };
    return (
      <header style={{ flex: 'none', position: 'relative', zIndex: 30, background: T.surfaceRaised, borderBottom: `1px solid ${T.line}` }}>
        <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <Link href="/" onNavigate={onForside} style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 1, minWidth: 0, textDecoration: 'none', color: T.ink }}>
            <img src="/daf-logo.png" alt="" style={{ width: 32, height: 32, objectFit: 'contain', flex: 'none' }} />
            <span style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, lineHeight: 1 }}>Danmarks Adels Aarbog</span>
          </Link>
          {ekstra}
          <button ref={menuKnap} type="button" aria-label="Menu" aria-expanded={mobilAaben || menuAaben}
            aria-controls={menuAaben ? MENU_ID : MOBILMENU_ID}
            onClick={() => { if (menuAaben) setMenuAaben(false); else setMobilAaben((a) => !a); }}
            style={{ flex: 'none', width: 44, height: 44, borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: (mobilAaben || menuAaben) ? T.bordeauxTint : T.surfaceRaised, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <svg width={20} height={20} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke={T.ink} strokeWidth={1.6} strokeLinecap="round">
              <path d={mobilAaben ? 'M5 5l10 10M15 5 5 15' : 'M3 6h14M3 10h14M3 14h14'} />
            </svg>
          </button>
        </div>
        {mobilAaben && (
          <div ref={mobilPanel} id={MOBILMENU_ID} data-overlay
            style={{ position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 40, maxHeight: 'calc(100dvh - 64px)', overflowY: 'auto', background: T.surfaceRaised, borderBottom: `1px solid ${T.line}`, boxShadow: shadow.popover, padding: '16px 16px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
            {soegeform}
            <nav aria-label="Hovedmenu" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <Link href={soegPath()} onNavigate={lukOg(onPersoner)} aria-current={aktiv === 'personer' ? 'page' : undefined} style={mobilPunkt(aktiv === 'personer')}>Personer</Link>
              <button type="button" aria-expanded={false} aria-controls={MENU_ID}
                onClick={() => { setMobilAaben(false); setMenuAaben(true, false, menuKnap.current); }}
                style={{ ...mobilPunkt(aktiv === 'slaegter'), justifyContent: 'space-between' }}>
                Slægter
                <svg width={12} height={12} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round"><path d="M5 7.5 10 13l5-5.5" /></svg>
              </button>
              <Link href="/slaegtskab" onNavigate={lukOg(onSlaegtskab)} aria-current={aktiv === 'slaegtskab' ? 'page' : undefined} style={mobilPunkt(aktiv === 'slaegtskab')}>Slægtskab</Link>
            </nav>
            <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 14, borderTop: `1px solid ${T.line}`, paddingTop: 14 }}>
              {logind}
              {redaktion}
            </div>
          </div>
        )}
        {slaegterMenu}
      </header>
    );
  }

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
            onClick={(e) => setMenuAaben(!menuAaben, false, e.currentTarget)}
            onKeyDown={(e) => { if (e.key === 'ArrowDown') { e.preventDefault(); setMenuAaben(true, false, e.currentTarget); } }}
            style={punkt(slaegterAktiv)}>
            Slægter
            <svg width={12} height={12} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
              <path d={menuAaben ? 'M5 12.5 10 7l5 5.5' : 'M5 7.5 10 13l5-5.5'} />
            </svg>
          </button>
          <Link href="/slaegtskab" onNavigate={onSlaegtskab} aria-current={aktiv === 'slaegtskab' ? 'page' : undefined} style={punkt(aktiv === 'slaegtskab')}>Slægtskab</Link>
        </nav>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 12 }}>
          {soegeform}
          {logind}
          {ekstra}
          {redaktion}
        </div>
      </div>
      {slaegterMenu}
    </header>
  );
}
