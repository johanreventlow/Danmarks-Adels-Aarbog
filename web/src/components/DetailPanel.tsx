// ---- Stamtræets personpanel: en genvej, ikke en erstatning for personsiden ----
// Webredesign fase 5b (tegningen »Stamtræ · fokus (web)«, overdragelsen: »Panelet er en genvej (resumé + »Åbn
// personsiden«)«). Panelet viser portræt, etiket, navn, livsdatoer og én linje om titel og godser; resten —
// biografi, udgaver, fakta, familie med kilder, embeder, billeder, livsrejse, »Det er mig« og »Vis i
// præsensliste« — står på personsiden (projektejeren 12/11). Familien ses i selve træet.
import { useState } from 'react';
import { T } from '../theme';
import { radius } from '@daa/theme';
import { bogensNummer } from '@daa/core';
import { Link } from '../Link';
import { personPath, slaegtskabPath, findSlaegt, STANDARD_SLAEGT } from '../data/nav';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { usePersonVisning } from './personVisning';
import { SignedImg } from './SignedImg';

const GODSER_I_RESUME = 3;

// »Godser: Rixdorf, Schönweide, Stocksee og 3 flere.« — tom, når personen ingen godser har.
export function godsResume(navne: string[], n = GODSER_I_RESUME): string {
  if (!navne.length) return '';
  const viste = navne.slice(0, n);
  const rest = navne.length - viste.length;
  if (rest > 0) return `Besiddelser: ${viste.join(', ')} og ${rest} ${rest === 1 ? 'mere' : 'flere'}.`;
  if (viste.length === 1) return `Besiddelse: ${viste[0]}.`;
  return `Besiddelser: ${viste.slice(0, -1).join(', ')} og ${viste[viste.length - 1]}.`;
}

export function DetailPanel({ model, focusId, detail, backName, onBack, onClose, onRelate }: {
  model: Model; focusId: string; detail: PersonDetailData | null;
  backName: string | null; onBack: () => void; onClose?: () => void;
  onRelate: () => void;
}) {
  const v = usePersonVisning(model, focusId, detail);
  const [billedFejl, setBilledFejl] = useState<string | null>(null);
  const p = v.p;
  if (!p) return null;
  // Etiket som på personsiden: slægt · bogens nummer, ellers linjernes navne.
  const slaegt = v.linjer.length ? findSlaegt(STANDARD_SLAEGT) : null;
  const nr = bogensNummer(model.sourcesBy, focusId);
  const linjeNavne = v.hovedLinjer;
  const etiket = [slaegt?.navn, ...(nr ? [nr] : linjeNavne)].filter(Boolean).join(' · ');
  const portraet = v.portrait?.url && billedFejl !== v.portrait.id ? v.portrait : null;
  const resume = [p.title ? `${p.title}.` : '', detail ? godsResume(v.godser.map((g) => g.navn)) : ''].filter(Boolean).join(' ');

  return (
    <aside aria-label={`Kort om ${p.name}`} data-scroll
      style={{ flex: 'none', width: 'clamp(300px, 28vw, 380px)', borderLeft: `1px solid ${T.line}`, background: T.surfaceRaised, overflowY: 'auto' }}>
      <div style={{ padding: 20, display: 'flex', flexDirection: 'column', gap: 14 }}>
        {(backName || onClose) && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
            {backName ? (
              <button type="button" onClick={onBack} style={tekstKnap}>‹ Tilbage til {backName}</button>
            ) : <span />}
            {/* Luk: navigerer til stamtræet uden fokus → fuldt træ, samme centrum (også med Esc). */}
            {onClose && (
              <button type="button" onClick={onClose} title="Luk (Esc)"
                style={{ ...tekstKnap, color: T.inkMuted, padding: '4px 10px', borderRadius: radius.badge, background: T.surfaceGround, border: `1px solid ${T.line}` }}>Luk</button>
            )}
          </div>
        )}

        {portraet ? (
          <SignedImg src={portraet.thumbUrl ?? portraet.url ?? undefined} alt={portraet.altTekst || `Portræt af ${p.name}`} onError={() => setBilledFejl(portraet.id)}
            style={{ display: 'block', width: '100%', aspectRatio: '4 / 3', objectFit: 'cover', borderRadius: radius.field, border: `1px solid ${T.line}` }} />
        ) : (
          <div role="img" aria-label="Intet portræt" style={{ aspectRatio: '4 / 3', borderRadius: radius.field, background: `repeating-linear-gradient(135deg, ${T.surfaceSunken} 0 10px, ${T.surfaceGround} 10px 20px)` }} />
        )}

        {etiket && <p style={{ margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldInk }}>{etiket}</p>}
        <h2 style={{ margin: 0, fontFamily: T.serif, fontSize: 28, fontWeight: 600, lineHeight: 1.1, color: T.ink }}>{p.name}</h2>
        {p.years && <p style={{ margin: 0, fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{p.years}</p>}
        {resume && <p style={{ margin: 0, fontFamily: T.sans, fontSize: 14, lineHeight: '21px', color: T.inkSecondary }}>{resume}</p>}
        {detail === null && <p role="status" style={{ margin: 0, fontSize: 13, color: T.inkMuted }}>Henter …</p>}

        <Link href={personPath(focusId)}
          style={{ display: 'flex', justifyContent: 'center', fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '12px 18px', borderRadius: radius.field, background: T.bordeaux, color: T.onBordeaux, textDecoration: 'none' }}>
          Åbn personsiden
        </Link>
        {/* Ikke »… med <fornavn>«: navnet kan begynde med en titel (»Lensgreve Cay Friedrich …«). */}
        <Link href={slaegtskabPath(focusId)} onNavigate={onRelate} style={{ ...tekstKnap, alignSelf: 'flex-start', textDecoration: 'none' }}>Find slægtskab</Link>
      </div>
    </aside>
  );
}

const tekstKnap = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer', textAlign: 'left' } as const;
