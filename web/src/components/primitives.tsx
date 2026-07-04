// Delte UI-byggeklodser for publikums-følgesvenden (Folgesvend.tsx + dens komponentfiler).
// Udtrukket sammen med theme.ts (samme begrundelse: undgår cirkulær import Folgesvend →
// komponent → Folgesvend). /simplify-fund (review 19b): BookmarksView/SlaegtPicker
// reimplementerede Avatar/ViewHeader inline i stedet for at importere dem herfra.
import { T } from '../theme';
import { initials } from '../data/format';
import type { MediaItem } from '../data/media';

export const Kicker = ({ children }: { children: React.ReactNode }) => (
  <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.2em', textTransform: 'uppercase', color: T.gold, marginBottom: 6 }}>{children}</div>
);
export const H1 = ({ children }: { children: React.ReactNode }) => (
  <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1 }}>{children}</div>
);
// Fælles visnings-overskrift: kicker + titel + bordeaux-streg. mb='6px' når der følger en
// undertekst, '18px' når overskriften står alene.
export const ViewHeader = ({ title, mb = '6px' }: { title: string; mb?: string }) => (
  <>
    <Kicker>Slægten Reventlow</Kicker>
    <H1>{title}</H1>
    <div style={{ width: 42, height: 1.5, background: T.bordeaux, margin: `11px 0 ${mb}` }} />
  </>
);
export const Avatar = ({ n, size }: { n: string; size: number }) => (
  <div style={{ width: size, height: size, borderRadius: '50%', background: '#f4ece0', border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: size * 0.4, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(n)}</div>
);
// Bogmærke-toggle (§3.3). Sidder ofte inde i et klikbart kort — stopPropagation forhindrer at
// et bogmærke-klik også trigger kortets egen navigation. Rigtig bogmærke-ribbon (rektangel med
// V-hak i bunden), ikke et flag — SVG frem for et Unicode-glyf for konsistent rendering på tværs
// af browsere/fonte (bruger-feedback: den tidligere ⚑/⚐-glyf lignede et flag, ikke et bogmærke).
export const BookmarkFlag = ({ active, onClick }: { active: boolean; onClick: () => void }) => (
  <span
    onClick={(e) => { e.stopPropagation(); onClick(); }}
    title={active ? 'Fjern bogmærke' : 'Bogmærk denne person'}
    style={{ cursor: 'pointer', lineHeight: 1, flex: 'none', display: 'inline-flex' }}
  >
    <svg width={14} height={17} viewBox="0 0 14 17" style={{ display: 'block' }}>
      <path
        d="M3 1.5 H11 V15.5 L7 11.8 L3 15.5 Z"
        fill={active ? T.bordeaux : 'none'}
        stroke={active ? T.bordeaux : T.muted2}
        strokeWidth={1.3}
        strokeLinejoin="round"
      />
    </svg>
  </span>
);

// Medie-billede med fallback: intet render hvis signering fejlede (url=null). Klik åbner den
// fulde (signed) URL i ny fane — RLS har allerede gatet at brugeren må se den. Delt af
// person-portræt/-galleri + gods/våben-visningerne.
export const MediaThumb = ({ m, w, h, radius = 10 }: { m: MediaItem; w: number | string; h: number | string; radius?: number }) => {
  if (!m.url) return null;
  const cap = [m.titel, m.kunstner, m.datering].filter(Boolean).join(' · ');
  return (
    <img src={m.url} alt={m.titel || m.slags || 'medie'} title={cap || undefined}
      onClick={() => window.open(m.url!, '_blank', 'noopener')}
      style={{ width: w, height: h, objectFit: 'cover', borderRadius: radius, border: '1px solid rgba(34,31,26,.1)', cursor: 'zoom-in', display: 'block' }} />
  );
};

// Kompakt sidebar-række (24×24 badge + navn + sekundær-linje), delt af ctx-sektionen og
// bmQuick-sektionen i Folgesvend.tsx (/simplify-fund: var to næsten identiske inline-blokke).
export const SidebarMiniRow = ({ shape = 'circle', badge, kicker, label, sub, onClick, trailing }: {
  shape?: 'circle' | 'square'; badge: string; kicker?: string; label: string; sub?: string;
  onClick?: () => void; trailing?: React.ReactNode;
}) => (
  <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 6px', borderRadius: 8, cursor: onClick ? 'pointer' : 'default' }}>
    <span style={{ width: 24, height: 24, borderRadius: shape === 'circle' ? '50%' : 6, background: T.beige, border: '1px solid rgba(34,31,26,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 10.5, fontWeight: 600, color: T.bordeaux }}>{badge}</span>
    <div style={{ minWidth: 0, flex: 1 }}>
      {kicker && <div style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted3 }}>{kicker}</div>}
      <div style={{ fontFamily: T.serif, fontSize: 14, fontWeight: 600, lineHeight: 1.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</div>
      {sub && <div style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted3 }}>{sub}</div>}
    </div>
    {trailing}
  </div>
);
