// »Slægter« i sidehovedet (navigation model 2, tegningen »Navigation model 2 · Slægter-menuen«):
// kun en vælger, der fører til slægtens forside. Find slægt, A–Å og senest besøgt. Panelet er en
// disclosure med links (ikke role="menu"): knappen styrer aria-expanded, Esc lukker og sender
// fokus tilbage til knappen, klik udenfor lukker. data-overlay gør, at Følgesvends Esc-lytter
// ikke samtidig lukker personpanelet.
//
// »Hele registret« fører til hovedsiden (fase 4), hvor slægtsregistret står.
// Bevidst udeladt (data findes ikke endnu): slægtsbeskrivelser (»uradel · 5 linjer«) og »slægter
// med nyt« ved første besøg.
import { useEffect, useMemo, useRef, useState, type RefObject } from 'react';
import { Link } from '../Link';
import { slaegtPath, type Slaegt } from '../data/nav';
import { T } from '../theme';
import { shadow } from '@daa/theme';

export function SlaegterMenu({ id, open, onClose, slaegter, senest, aktiv, onVaelg, opener }: {
  id: string;
  open: boolean;
  onClose: (returFokus: boolean) => void;
  slaegter: readonly Slaegt[];
  senest: string | null;
  aktiv: string | null; // slug for den slægt, man står i (aria-current)
  onVaelg: (slug: string) => void;
  opener: RefObject<HTMLElement | null>; // knappen der åbnede panelet (klik på den lukker ikke to gange)
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const soegRef = useRef<HTMLInputElement>(null);
  const [soeg, setSoeg] = useState('');
  const [bogstav, setBogstav] = useState<string | null>(null);

  useEffect(() => {
    if (!open) { setSoeg(''); setBogstav(null); return; }
    soegRef.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); onClose(true); } };
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (panelRef.current?.contains(t) || opener.current?.contains(t)) return;
      onClose(false);
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onDown);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('mousedown', onDown); };
  }, [open, onClose, opener]);

  const sorteret = useMemo(() => [...slaegter].sort((a, b) => a.navn.localeCompare(b.navn, 'da')), [slaegter]);
  const bogstaver = useMemo(() => [...new Set(sorteret.map((s) => s.navn[0].toLocaleUpperCase('da')))], [sorteret]);
  const vist = sorteret.filter((s) =>
    (!soeg.trim() || s.navn.toLocaleLowerCase('da').includes(soeg.trim().toLocaleLowerCase('da')))
    && (!bogstav || s.navn[0].toLocaleUpperCase('da') === bogstav));
  const senestSlaegt = slaegter.find((s) => s.slug === senest) ?? null;

  if (!open) return null;
  const etiket = { margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldInk } as const;
  const slaegtLink = (s: Slaegt, stor = false) => (
    <Link href={slaegtPath(s.slug)} onNavigate={() => onVaelg(s.slug)} aria-current={s.slug === aktiv ? 'page' : undefined}
      style={{ display: 'flex', alignItems: 'center', gap: 10, padding: stor ? '8px' : '9px 0', margin: stor ? '0 -8px' : 0, borderRadius: stor ? 11 : 0,
        borderBottom: stor ? 'none' : `1px solid ${T.line}`, textDecoration: 'none', color: T.ink, background: s.slug === aktiv && stor ? T.bordeauxTint : 'transparent' }}>
      <span style={{ fontFamily: T.serif, fontSize: stor ? 22 : 19, fontWeight: 600, lineHeight: 1.1 }}>{s.navn}</span>
    </Link>
  );

  return (
    <div ref={panelRef} id={id} data-overlay style={{ position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 40, background: T.surfaceRaised, borderBottom: `1px solid ${T.line}`, boxShadow: shadow.popover }}>
      <div style={{ maxWidth: 1240, margin: '0 auto', padding: '28px 24px 32px', display: 'flex', flexDirection: 'column', gap: 22 }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <h2 style={{ margin: 0, fontFamily: T.serif, fontSize: 28, fontWeight: 600, color: T.ink }}>Vælg en slægt</h2>
            <p style={{ margin: 0, fontSize: 13.5, color: T.inkMuted }}>Du kommer til slægtens forside. Derfra når du stamtræ, besiddelser og våben.</p>
          </div>
          <div style={{ flex: '0 1 380px', minWidth: 0, display: 'flex' }}>
            <label htmlFor={`${id}-soeg`} style={{ position: 'absolute', left: -9999 }}>Find slægt</label>
            <input ref={soegRef} id={`${id}-soeg`} type="search" value={soeg} onChange={(e) => { setSoeg(e.target.value); setBogstav(null); }} placeholder="Find slægt"
              style={{ flex: 1, minWidth: 0, fontFamily: T.sans, fontSize: 15, lineHeight: '20px', padding: '11px 14px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceGround, color: T.ink }} />
          </div>
        </div>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 40 }}>
          {senestSlaegt && (
            <section aria-labelledby={`${id}-senest`} style={{ flex: '1 1 260px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 10, paddingRight: 32, borderRight: `1px solid ${T.line}` }}>
              <h3 id={`${id}-senest`} style={etiket}>Senest besøgt</h3>
              {slaegtLink(senestSlaegt, true)}
            </section>
          )}
          <section aria-labelledby={`${id}-alle`} style={{ flex: '3 1 600px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'baseline', justifyContent: 'space-between' }}>
              <h3 id={`${id}-alle`} style={etiket}>Alle slægter A–Å</h3>
              <div role="group" aria-label="Forbogstav" style={{ display: 'flex', flexWrap: 'wrap', gap: 2 }}>
                {bogstaver.map((b) => (
                  <button key={b} type="button" aria-pressed={bogstav === b} onClick={() => setBogstav((cur) => (cur === b ? null : b))}
                    style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', padding: '4px 8px', borderRadius: 8, border: 0, cursor: 'pointer',
                      background: bogstav === b ? T.bordeaux : 'transparent', color: bogstav === b ? T.onBordeaux : T.inkMuted }}>{b}</button>
                ))}
              </div>
            </div>
            {vist.length ? (
              <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 220px), 1fr))', gap: '2px 28px' }}>
                {vist.map((s) => <li key={s.slug}>{slaegtLink(s)}</li>)}
              </ul>
            ) : (
              <p style={{ margin: 0, fontSize: 14, color: T.inkSecondary }}>Ingen slægt i Aarbogen hedder »{soeg.trim()}«.</p>
            )}
          </section>
        </div>
        <Link href="/" onNavigate={() => onClose(false)} style={{ alignSelf: 'flex-start', fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Hele registret →</Link>
      </div>
    </div>
  );
}
