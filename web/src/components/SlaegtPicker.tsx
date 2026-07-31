// Slægt-vælger-modal (web v3 Slice 1 — spec §3.3). Kosmetisk, fremadskuende: kun Reventlow findes
// nu, men chippen skal opføre sig som en rigtig vælger. Fixed backdrop + panel øverst-højre.
import { useEffect } from 'react';
import { T } from '../theme';

export type SlaegtOption = { id: string; navn: string };

export function SlaegtPicker({ open, slaegter, activeId, onClose, onPick }: {
  open: boolean; slaegter: SlaegtOption[]; activeId: string | null;
  onClose: () => void; onPick: (id: string) => void;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      data-testid="slaegt-picker-backdrop"
      onClick={onClose}
      style={{ position: 'fixed', inset: 0, background: 'rgba(34,31,26,.32)', zIndex: 100, display: 'flex', justifyContent: 'flex-end', alignItems: 'flex-start', padding: '78px 26px 0 0' }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{ width: 280, background: T.paper, borderRadius: 13, border: '1px solid rgba(34,31,26,.12)', boxShadow: '0 12px 32px rgba(34,31,26,.22)', padding: 10 }}
      >
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, padding: '6px 8px 8px' }}>Vælg slægt</div>
        {slaegter.map((s) => {
          const active = s.id === activeId;
          return (
            <div
              key={s.id}
              onClick={() => onPick(s.id)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 8px', borderRadius: 9, cursor: 'pointer', background: active ? '#f8ecef' : 'transparent' }}
            >
              <span style={{ width: 26, height: 26, borderRadius: '50%', border: `1px solid ${active ? 'rgba(136,26,51,.55)' : 'rgba(34,31,26,.15)'}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 14, fontWeight: 600, color: active ? T.bordeaux : T.muted }}>{s.navn[0]}</span>
              <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: active ? T.bordeaux : T.ink }}>{s.navn}</span>
              {active && <span style={{ marginLeft: 'auto', fontFamily: T.mono, fontSize: 10, color: T.bordeaux }}>✓</span>}
            </div>
          );
        })}
        <div style={{ fontFamily: T.sans, fontSize: 12.5, color: T.muted3, padding: '10px 8px 6px', borderTop: '1px solid rgba(34,31,26,.08)', marginTop: 6 }}>
          Flere slægter kommer til Følgesvend senere.
        </div>
      </div>
    </div>
  );
}
