// Delte UI-byggeklodser for publikums-følgesvenden (Folgesvend.tsx + dens komponentfiler).
// Udtrukket sammen med theme.ts (samme begrundelse: undgår cirkulær import Folgesvend →
// komponent → Folgesvend). /simplify-fund (review 19b): BookmarksView/SlaegtPicker
// reimplementerede Avatar/ViewHeader inline i stedet for at importere dem herfra.
import { T } from '../theme';
import { KlikbarFlade } from '../Link';
import { initials } from '../data/format';
import { mediaCaption, type MediaItem } from '../data/media';

export const Kicker = ({ children }: { children: React.ReactNode }) => (
  <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.2em', textTransform: 'uppercase', color: T.gold, marginBottom: 6 }}>{children}</div>
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
  <button
    type="button"
    onClick={(e) => { e.stopPropagation(); onClick(); }}
    title={active ? 'Fjern bogmærke' : 'Bogmærk denne person'}
    aria-label={active ? 'Fjern bogmærke' : 'Bogmærk denne person'}
    style={{ cursor: 'pointer', lineHeight: 1, flex: 'none', display: 'inline-flex', border: 0, padding: 0, background: 'transparent' }}
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
  </button>
);

// Medie-billede med fallback: intet render hvis signering fejlede (url=null). Klik åbner en
// lightbox (Slice A) — RLS har allerede gatet at brugeren må se den. Delt af person-portræt/
// -galleri + gods/våben-visningerne. onClick er PÅKRÆVET: alle 6 kaldesteder kobler en lightbox
// på; en valgfri prop med en window.open-fallback ville lade en glemt 7. kaldested falde tavst
// tilbage til den gamle ny-fane-adfærd i stedet for en type-fejl (/simplify-fund, Slice A).
export const MediaThumb = ({ m, w, h, radius = 10, onClick }: { m: MediaItem; w: number | string; h: number | string; radius?: number; onClick: () => void }) => {
  if (!m.url) return null;
  const cap = mediaCaption(m);
  return (
    <img src={m.thumbUrl ?? m.url} alt={m.altTekst || m.titel || m.slags || 'billede'} title={cap || undefined}
      onClick={onClick}
      style={{ width: w, height: h, objectFit: 'cover', borderRadius: radius, border: '1px solid rgba(34,31,26,.1)', cursor: 'zoom-in', display: 'block' }} />
  );
};

// Personkortet — den gennemgående primitiv (brief §8.1): avatar + serif-navn + mono-år +
// valgfri titel. Bruges af forsidens kuraterede grid nu; tænkt genbrugt af søgeresultater og
// træet i senere slices (§4/§5), så appen føles som ét system. Tager kun de felter et kort
// har brug for (ikke hele ModelPerson) så primitiven forbliver løst koblet.
// href: kortet rummer intet andet klikbart, så HELE kortet bliver ankeret — højreklik/cmd-klik
// åbner personen i ny fane. Uden href opfører kortet sig præcis som før.
export const PersonCard = ({ p, onClick, href, width = 210 }: {
  p: { name: string; years?: string; title?: string };
  onClick?: () => void; href?: string; width?: number | string;
}) => (
  <KlikbarFlade href={href} onClick={onClick} style={{ width, background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14, padding: 16, boxShadow: '0 1px 2px rgba(34,31,26,.04)' }}>
    <Avatar n={p.name} size={50} />
    <div style={{ fontFamily: T.serif, fontSize: 19, lineHeight: 1.05, fontWeight: 600, color: T.ink, marginTop: 11 }}>{p.name}</div>
    {p.years ? <div style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted2, marginTop: 4 }}>{p.years}</div> : null}
    {p.title ? <div style={{ fontFamily: T.sans, fontSize: 12.5, fontWeight: 500, color: T.bordeaux, marginTop: 6, lineHeight: 1.3 }}>{p.title}</div> : null}
  </KlikbarFlade>
);

// Forstørrelsesglas — delt af header-søgeknappen og forsidens søge-hero (/simplify-fund:
// var to identiske inline-SVG'er der kunne drive fra hinanden).
export const SearchIcon = ({ size = 17, color = T.bordeaux }: { size?: number; color?: string }) => (
  <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round"><circle cx={11} cy={11} r={7} /><path d="M21 21l-4.3-4.3" /></svg>
);

// Slægtens våben som let vandmærke-motiv (dobbelt-skjold). Parametriseret farve/opacitet/
// størrelse + valgfri positionering, så samme motiv kan bruges på lyse (bordeaux) og mørke
// (guld) flader (/simplify-fund: inline-dupleret i træet og på forsiden).
export const Crest = ({ stroke = T.bordeaux, inner = T.gold, opacity = 0.12, size = 116, style }: {
  stroke?: string; inner?: string; opacity?: number; size?: number; style?: React.CSSProperties;
}) => (
  <svg viewBox="0 0 100 120" fill="none" style={{ width: size, height: 'auto', opacity, pointerEvents: 'none', ...style }}>
    <path d="M10,8 H90 V58 C90,90 50,113 50,113 C50,113 10,90 10,58 Z" stroke={stroke} strokeWidth={1.4} />
    <path d="M19,18 H81 V57 C81,82 50,100 50,100 C50,100 19,82 19,57 Z" stroke={inner} strokeWidth={1} />
  </svg>
);

// (SidebarMiniRow fjernet — ctx/bmQuick-sidebaren udgik da søgning flyttede ind i træet, §4.)

// ---- Små byggeklodser (udtrukket fra Folgesvend.tsx ved W-K1-splittet, review 27) ----
// Sidebar-/tæller-celle (tal over label). Bruges af AboutView.
export const Counter = ({ n, label }: { n: number; label: string }) => (
  <div><span style={{ fontFamily: T.serif, fontSize: 28, fontWeight: 600, color: T.bordeaux }}>{n.toLocaleString('da')}</span> <span style={{ fontSize: 13.5, color: T.muted }}>{label}</span></div>
);
// Gren-filter-chip (§9.2). Aktiv = bordeaux fyld. Bruges af TreeSearch.
export const LinjeChip = ({ label, active, onClick, title }: { label: string; active: boolean; onClick: () => void; title?: string }) => (
  <div onClick={onClick} title={title} style={{ padding: '5px 11px', borderRadius: 15, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', background: active ? T.bordeaux : 'transparent', color: active ? T.paper : T.muted, border: `1px solid ${active ? T.bordeaux : 'rgba(34,31,26,.18)'}` }}>{label}</div>
);
// Sektionslabel (mono, kapitæler). Bruges af TreeView/DetailPanel/EstatesView/ArmsView.
export const Label = ({ children }: { children: React.ReactNode }) => <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 12px' }}>{children}</div>;
// Lodret forbindelses-streg mellem generationer. Bruges af TreeView (variant A).
export const Stem = ({ h, mt = 0 }: { h: number; mt?: number }) => <div style={{ width: 1, height: h, background: 'rgba(34,31,26,.22)', marginTop: mt }} />;
