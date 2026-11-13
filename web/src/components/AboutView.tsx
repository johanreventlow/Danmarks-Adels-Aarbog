// Slægtens forside (webredesign fase 5a, tegningen »Slægtens forside · Reventlow«): våben (med
// valgfri note) · indledning med kilde · linjerne · »Redaktionen foreslår« · feedet.
//
// Bevidst anderledes end tegningen:
// - De fire indgangskort udgår; slægtsbjælken erstatter dem (overdragelsen).
// - Ingen »uradel«-etiket og ingen våbennote fra tegningen: intet i data bærer dem.
// - Linjerne linker ikke til linjesider; de er blokeret af åbent punkt 1. Stamfaderen linker til
//   sin personside, og linjernes egne indledninger kan foldes ud her, så ingen tekst fra den
//   tidligere »Om slægten« forsvinder.
// - »Læs hele indledningen« folder teksten ud på stedet i stedet for at føre til en ny side.
// - »Redaktionen foreslår« vises kun, når redaktionen har fastgjort portrætter (redaktionensForslag);
//   uden dem er der intet forslag, og stamfædrene står allerede under linjerne.
// - Feedet er Aarbogens feed, ikke filtreret pr. slægt (kun én slægt i dag); overskriften siger det.
import { useEffect, useId, useMemo, useState, type ComponentProps } from 'react';
import { groupBlocks, parseNarrativ } from '@daa/core';
import { T } from '../theme';
import type { FeedPinInput } from '@daa/feed';
import type { AboutSection } from '../data/public';
import type { Model } from '../data/types';
import { personPath, type Slaegt } from '../data/nav';
import { fetchFeedPins } from '../data/feedPins';
import { redaktionensForslag } from '../data/home';
import { synligeLinjer } from '../data/lineage';
import { Link } from '../Link';
import { NarrativRenderer } from './NarrativRenderer';
import { Avatar } from './primitives';
import { FeedStreamView } from './feed/FeedStreamView';

const etiket = { margin: 0, fontFamily: T.mono, fontSize: 11, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldInk, fontWeight: 400 } as const;
const kildeStil = { margin: 0, fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted } as const;
const h2Stil = { margin: 0, fontFamily: T.serif, fontSize: 30, fontWeight: 600, color: T.ink, borderBottom: `1px solid ${T.line}`, paddingBottom: 12 } as const;

// »Kilde: DAA 2018-20« — udgavens etiket alene, som udgavevælgeren viser den.
export function indledningKilde(s: Pick<AboutSection, 'kilde' | 'aar'>): string {
  if (s.kilde) return `Kilde: ${s.kilde}`;
  return s.aar ? `Kilde: Danmarks Adels Aarbog ${s.aar}` : 'Kilde ikke registreret';
}

// Har indledningen mere end uddraget (første afsnit i rendererens egen blokopdeling)?
export function indledningHarMere(tekst: string): boolean {
  const blokke = groupBlocks(parseNarrativ(tekst));
  const foerste = blokke.findIndex((b) => b.kind === 'paragraph');
  return blokke.length > (foerste >= 0 ? 1 : Math.min(1, blokke.length));
}

type FeedProps = Omit<ComponentProps<typeof FeedStreamView>, 'model' | 'feedPins'>;

export function AboutView({ slaegt, model, about, personCount, estateCount, onPick, feed }: {
  slaegt: Slaegt;
  model: Model | null;
  about: AboutSection[] | null;
  personCount: number;
  estateCount: number | null;
  onPick: (id: string) => void;
  feed: FeedProps;
}) {
  // Pins deles af »Redaktionen foreslår« og feedet; feedet monteres først, når de er hentet,
  // så fastgjorte kort står først (samme regel som hovedsiden).
  const [feedPins, setFeedPins] = useState<FeedPinInput[] | null>(null);
  useEffect(() => {
    let alive = true;
    void fetchFeedPins().then((pins) => { if (alive) setFeedPins(pins); }, () => { if (alive) setFeedPins([]); });
    return () => { alive = false; };
  }, []);
  const [helIndledning, setHelIndledning] = useState(false);
  const indledningId = useId();

  const generelt = about?.find((s) => s.lineageId == null) ?? null;
  const linjeAfsnit = useMemo(() => (about ?? []).filter((s) => s.lineageId != null), [about]);
  // l.linje er en stabil nøgle, ikke bogens kode; den trykte betegnelse er åbent punkt 1, så
  // linjen vises med sit navn. Tekniske nøgler vises aldrig (samme filter som søgningen).
  const linjer = useMemo(() => synligeLinjer(model?.lineage?.list ?? []), [model]);
  const forslag = useMemo(
    () => (model && feedPins ? redaktionensForslag(model, feedPins, 4, new Date().getFullYear()) : []),
    [model, feedPins],
  );
  const kanFoldes = useMemo(() => !!generelt && indledningHarMere(generelt.tekst), [generelt]);

  return (
    <div style={{ padding: 'clamp(24px, 4vw, 40px) clamp(16px, 4vw, 44px) 54px', maxWidth: 1140, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 48 }}>
      <section aria-labelledby="slaegt-titel" style={{ display: 'flex', flexWrap: 'wrap', gap: 'clamp(20px, 4vw, 40px)', alignItems: 'flex-start' }}>
        {slaegt.vaaben && (
          <figure style={{ margin: 0, flex: 'none', width: 'clamp(120px, 28vw, 200px)', display: 'flex', flexDirection: 'column', gap: 8 }}>
            <img src={slaegt.vaaben.src} alt={`${slaegt.navn}s våben`} style={{ display: 'block', width: '100%', height: 'auto' }} />
            {slaegt.vaaben.note && <figcaption style={{ fontFamily: T.sans, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{slaegt.vaaben.note}</figcaption>}
          </figure>
        )}
        <div style={{ flex: '1 1 480px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>
          <p style={etiket}>Slægt i Danmarks Adels Aarbog</p>
          <h1 id="slaegt-titel" style={{ margin: 0, fontFamily: T.serif, fontSize: 'clamp(40px, 7vw, 64px)', lineHeight: 1, fontWeight: 500, color: T.ink }}>{slaegt.navn}</h1>
          <span aria-hidden="true" style={{ display: 'block', width: 44, height: 1.5, background: T.gold }} />
          {model && (
            <p style={{ margin: 0, fontFamily: T.sans, fontSize: 13.5, color: T.inkMuted }}>
              {[`${personCount.toLocaleString('da')} personer`, estateCount != null ? `${estateCount.toLocaleString('da')} besiddelser` : null,
                linjer.length ? `${linjer.length} linjer` : null].filter(Boolean).join(' · ')}
            </p>
          )}
          {!about ? (
            <p role="status" style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>Henter indledningen …</p>
          ) : generelt ? (
            <>
              <div id={indledningId} style={{ maxWidth: '38em', fontFamily: T.serif, fontSize: 19, lineHeight: 1.6, color: T.inkSecondary }}>
                <NarrativRenderer tekst={generelt.tekst} kunFoersteAfsnit={!helIndledning} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
              </div>
              <p style={{ ...kildeStil, display: 'flex', flexWrap: 'wrap', gap: '4px 12px', alignItems: 'baseline' }}>
                <span><span aria-hidden="true" style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, marginRight: 6 }}>§</span>{indledningKilde(generelt)}</span>
                {kanFoldes && (
                  <button type="button" aria-expanded={helIndledning} aria-controls={indledningId} onClick={() => setHelIndledning((v) => !v)}
                    style={{ fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer', textDecoration: 'underline' }}>
                    {helIndledning ? 'Vis kun begyndelsen' : 'Læs hele indledningen'}
                  </button>
                )}
              </p>
            </>
          ) : (
            <p style={{ margin: 0, fontSize: 15, lineHeight: 1.5, color: T.inkSecondary }}>Aarbogen har endnu ingen indledning til slægten.</p>
          )}
        </div>
      </section>

      {(linjer.length > 0 || linjeAfsnit.length > 0) && (
        <section aria-labelledby="slaegt-linjer" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <h2 id="slaegt-linjer" style={h2Stil}>Linjerne</h2>
          {linjer.length > 0 && (
            <ol style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 210px), 1fr))', gap: '0 24px' }}>
              {linjer.map((l) => {
                const stamfader = l.headId ? model?.byId[l.headId] : undefined;
                return (
                  <li key={l.linje} style={{ display: 'flex', flexDirection: 'column', gap: 3, padding: '14px 0', borderBottom: `1px solid ${T.line}`, minWidth: 0 }}>
                    <span style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, lineHeight: 1.15, color: T.bordeaux }}>{l.navn ?? 'Linje uden navn'}</span>
                    <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{l.count.toLocaleString('da')} personer</span>
                    {stamfader && (
                      <span style={{ fontFamily: T.sans, fontSize: 13, color: T.inkSecondary }}>
                        Stamfader:{' '}
                        <Link href={personPath(stamfader.id)} onNavigate={() => onPick(stamfader.id)} style={{ color: T.bordeaux, fontWeight: 600 }}>{stamfader.name}</Link>
                      </span>
                    )}
                  </li>
                );
              })}
            </ol>
          )}
          {linjeAfsnit.length > 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: '44em' }}>
              {linjeAfsnit.map((s) => (
                <details key={s.lineageId} style={{ borderBottom: `1px solid ${T.line}`, padding: '6px 0 10px' }}>
                  <summary style={{ cursor: 'pointer', fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux, padding: '6px 0' }}>Om {s.lineageNavn ?? `linje ${s.lineageKode}`}</summary>
                  <div style={{ fontFamily: T.serif, fontSize: 17, lineHeight: 1.6, color: T.inkSecondary, marginTop: 8 }}>
                    <NarrativRenderer tekst={s.tekst} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
                  </div>
                  <p style={{ ...kildeStil, marginTop: 8 }}><span aria-hidden="true" style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, color: T.bordeaux, marginRight: 6 }}>§</span>{indledningKilde(s)}</p>
                </details>
              ))}
            </div>
          )}
        </section>
      )}

      {forslag.length > 0 && (
        <section aria-labelledby="slaegt-foreslaar" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <h2 id="slaegt-foreslaar" style={etiket}>Redaktionen foreslår</h2>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0, maxWidth: 760 }}>
            {forslag.map((p, i) => (
              <li key={p.id} style={{ borderTop: `1px solid ${T.line}`, borderBottom: i === forslag.length - 1 ? `1px solid ${T.line}` : undefined }}>
                <Link href={personPath(p.id)} onNavigate={() => onPick(p.id)}
                  style={{ display: 'flex', gap: 16, alignItems: 'center', padding: '14px 0', textDecoration: 'none', color: T.ink }}>
                  <Avatar n={p.name} size={44} />
                  <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600 }}>{p.name}</span>
                    {p.title && <span style={{ fontFamily: T.sans, fontSize: 13.5, color: T.bordeaux }}>{p.title}</span>}
                    {p.years && <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted, marginTop: 2 }}>{p.years}</span>}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="slaegt-feed">
        <h2 id="slaegt-feed" style={{ ...etiket, marginBottom: 14 }}>Fra Aarbogen</h2>
        {model && feedPins ? (
          <FeedStreamView model={model} feedPins={feedPins} {...feed} />
        ) : (
          <p role="status" style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>Henter blade fra Aarbogen …</p>
        )}
      </section>
    </div>
  );
}
