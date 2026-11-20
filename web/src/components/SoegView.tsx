// ---- Søgning (webredesign fase 6b, tegningen »Søgeresultater (web)«) ----
// Søgeord og filtre ligger i adressen (/soeg?q=&type=&linje=&fra=&til=&sort=&bm=), så en søgning kan deles.
// Uden søgeord viser siden alle personer (Personer i hovedmenuen lander her).
import { useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { estatePath, personPath, SLAEGTER } from '../data/nav';
import { initials } from '../data/format';
import { soeg, soegSti, stavemaader, type Maerke, type SoegFiltre, type SoegType } from '../data/soeg';
import type { EstateItem } from '../data/public';
import type { LinjeEntry, Model } from '../data/types';
import { kanoniskLinje } from '../data/lineage';
import { useSmalSkaerm } from '../useSmalSkaerm';

const etiket: CSSProperties = { fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '0.16em', textTransform: 'uppercase', color: T.inkMuted };
const skjult: CSSProperties = { position: 'absolute', left: -9999 };
const SIDE = 25;

// Navnet med de bogstavret genfundne søgeord fremhævet.
function Fremhaev({ tekst, maerker }: { tekst: string; maerker: Maerke[] }) {
  if (!maerker.length) return <>{tekst}</>;
  const dele: ReactNode[] = [];
  let pos = 0;
  maerker.forEach(([a, b], i) => {
    if (a < pos) return;
    if (a > pos) dele.push(tekst.slice(pos, a));
    dele.push(<mark key={i} style={{ background: T.bordeauxTint, color: 'inherit' }}>{tekst.slice(a, b)}</mark>);
    pos = b;
  });
  dele.push(tekst.slice(pos));
  return <>{dele}</>;
}

export function SoegView({ model, estates, filtre: f, linjer, bogmaerker, onFiltre }: {
  model: Model | null;
  estates: EstateItem[] | null;
  filtre: SoegFiltre;
  linjer: LinjeEntry[]; // synlige linjer (ingen tekniske nøgler)
  bogmaerker: ReadonlySet<string> | null; // null = ingen bogmærker at filtrere på
  onFiltre: (sti: string) => void; // navigér (replace) til den nye søgeadresse
}) {
  const smal = useSmalSkaerm();
  const saet = (x: Partial<SoegFiltre>) => onFiltre(soegSti({ ...f, ...x }));
  const res = useMemo(() => (model ? soeg(model, estates ?? [], f, bogmaerker ?? undefined) : null), [model, estates, f, bogmaerker]);
  // Andre stavemåder (Reventlow ↔ Reventlou) med antal træffere under de samme filtre; kun dem, der finder noget.
  const andre = useMemo(() => {
    if (!model || !f.q.trim()) return [];
    return stavemaader([...model.persons.map((p) => p.name), ...(estates ?? []).map((e) => e.navn)], f.q)
      .map((q) => { const r = soeg(model, estates ?? [], { ...f, q }, bogmaerker ?? undefined); return { q, n: r.personer.length + r.godser.length }; })
      .filter((x) => x.n > 0);
  }, [model, estates, f, bogmaerker]);
  const stavLink = (x: { q: string; n: number }, medAntal: boolean) => (
    <Link href={soegSti({ ...f, q: x.q })} onNavigate={() => onFiltre(soegSti({ ...f, q: x.q }))} style={{ fontWeight: 600, color: T.bordeaux }}>
      {x.q}{medAntal ? ` (${x.n})` : ''}
    </Link>
  );
  const [vist, setVist] = useState({ noegle: '', n: SIDE });
  const noegle = soegSti(f);
  const antalVist = vist.noegle === noegle ? vist.n : SIDE;

  const visPersoner = f.type !== 'besiddelser';
  const visGodser = f.type !== 'personer' && !!res?.godser.length;
  const personer = res?.personer ?? [];
  const godser = res?.godser ?? [];
  const aktive = [f.linje, f.fra, f.til, f.bm || null, f.type !== 'alt' || null].filter((x) => x != null).length;

  const afgraens = (
    <aside aria-label="Afgræns" style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      <fieldset style={{ border: 0, margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <legend style={{ ...etiket, marginBottom: 8 }}>Type</legend>
        {([['alt', 'Alt', personer.length + godser.length], ['personer', 'Personer', personer.length], ['besiddelser', 'Besiddelser', godser.length]] as [SoegType, string, number][]).map(([v, navn, n]) => (
          <label key={v} style={{ display: 'flex', gap: 8, fontSize: 14, cursor: 'pointer' }}>
            <input type="radio" name="soeg-type" checked={f.type === v} onChange={() => saet({ type: v })} /> {navn} ({n})
          </label>
        ))}
      </fieldset>
      {linjer.length > 0 && (
        <fieldset style={{ border: 0, margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <legend style={{ ...etiket, marginBottom: 8 }}>Slægt og linje</legend>
          <span style={{ fontSize: 14 }}>{SLAEGTER.map((sl) => sl.navn).join(', ')}</span>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {[{ linje: null as string | null, navn: 'Hele slægten' }, ...linjer.map((l) => ({ linje: l.linje as string | null, navn: l.navn ?? 'Linje uden navn' }))].map((l) => {
              // En ældre udgavenøgle i adressen (delt link fra før slutreview I-1) markerer sin kanoniske chip.
              const on = (f.linje == null ? null : kanoniskLinje(model?.lineage, f.linje)) === l.linje;
              return (
                <button key={l.linje ?? 'alle'} type="button" aria-pressed={on} onClick={() => saet({ linje: l.linje })}
                  style={{ fontFamily: T.sans, fontSize: 12.5, lineHeight: '16px', fontWeight: 600, padding: '5px 11px', borderRadius: 18, border: `1px solid ${on ? T.bordeaux : T.lineStrong}`, background: on ? T.bordeaux : T.surfaceRaised, color: on ? T.onBordeaux : T.inkSecondary, cursor: 'pointer' }}>
                  {l.navn}
                </button>
              );
            })}
          </div>
        </fieldset>
      )}
      <fieldset style={{ border: 0, margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <legend style={{ ...etiket, marginBottom: 8 }}>Levetid</legend>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 14 }}>
          <label htmlFor="soeg-fra" style={skjult}>Fra år</label>
          <AarFelt id="soeg-fra" vaerdi={f.fra} onAar={(fra) => saet({ fra })} pladsholder="fra" />
          <span aria-hidden="true">–</span>
          <label htmlFor="soeg-til" style={skjult}>Til år</label>
          <AarFelt id="soeg-til" vaerdi={f.til} onAar={(til) => saet({ til })} pladsholder="til" />
        </div>
        <p style={{ margin: 0, fontSize: 12.5, lineHeight: '18px', color: T.inkMuted }}>
          En person tæller med, hvis levetiden rører perioden. Mangler fødsels- eller dødsår, regnes 100 år fra det kendte.
        </p>
      </fieldset>
      {bogmaerker && (
        <label style={{ display: 'flex', gap: 8, fontSize: 14, cursor: 'pointer' }}>
          <input type="checkbox" checked={f.bm} onChange={(e) => saet({ bm: e.target.checked })} /> Kun bogmærkede
        </label>
      )}
      {aktive > 0 && (
        <button type="button" onClick={() => onFiltre(soegSti({ q: f.q, sort: f.sort }))}
          style={{ alignSelf: 'flex-start', fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer', textDecoration: 'underline' }}>
          Nulstil afgrænsning
        </button>
      )}
    </aside>
  );

  return (
    <main style={{ maxWidth: 1240, margin: '0 auto', padding: smal ? '24px 16px 48px' : '32px 24px 64px', display: 'flex', flexDirection: 'column', gap: 24, fontFamily: T.sans, color: T.ink }}>
      <h1 style={{ ...skjult }}>Søg i Aarbogen</h1>
      <form role="search" onSubmit={(e) => e.preventDefault()} style={{ display: 'flex', flexWrap: 'wrap', gap: 8, maxWidth: 760 }}>
        <label htmlFor="soegeside-q" style={skjult}>Søgeord</label>
        <input id="soegeside-q" data-felt-stor type="search" value={f.q} placeholder="Søg efter en person eller en besiddelse"
          // Søgeordet skrives i adressen med replace, så tilbage-knappen ikke går ét tastetryk ad gangen.
          onChange={(e) => saet({ q: e.target.value })}
          style={{ flex: '1 1 320px', minWidth: 0, fontFamily: T.sans, fontSize: 18, lineHeight: '24px', padding: '14px 18px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink }} />
      </form>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: smal ? 16 : 32, alignItems: 'flex-start' }}>
        {smal ? (
          <details style={{ flex: '1 1 100%' }}>
            <summary style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux, cursor: 'pointer', padding: '6px 0' }}>
              Afgræns{aktive ? ` (${aktive} valgt)` : ''}
            </summary>
            <div style={{ paddingTop: 12 }}>{afgraens}</div>
          </details>
        ) : <div style={{ flex: '1 1 220px', minWidth: 0 }}>{afgraens}</div>}

        <section aria-label="Resultater" style={{ flex: '999 1 640px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {!res ? <p style={{ margin: 0, color: T.inkMuted }}>Henter Aarbogen …</p> : (
            <>
              <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
                <p role="status" style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>
                  {[visPersoner && (personer.length > 0 || f.type === 'personer') && `${personer.length} ${personer.length === 1 ? 'person' : 'personer'}`,
                    visGodser && `${godser.length} ${godser.length === 1 ? 'besiddelse' : 'besiddelser'}`].filter(Boolean).join(' · ') || 'Ingen resultater'}
                  {res.udenAar > 0 && ` · ${res.udenAar} uden årstal er ikke med`}
                </p>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 14, color: T.inkMuted }}>
                  Sortér
                  <select value={f.sort} onChange={(e) => saet({ sort: e.target.value as SoegFiltre['sort'] })}
                    style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.bordeaux, background: T.surfaceRaised, border: `1px solid ${T.lineStrong}`, borderRadius: 8, padding: '4px 8px' }}>
                    <option value="match">{f.q.trim() ? 'bedste match' : 'navn'}</option>
                    {f.q.trim() && <option value="navn">navn</option>}
                    <option value="foedt">fødeår</option>
                  </select>
                </label>
              </div>

              {andre.length > 0 && (personer.length > 0 || godser.length > 0) && (
                <p style={{ margin: 0, fontSize: 14, lineHeight: '20px', color: T.inkSecondary }}>
                  Andre stavemåder: {andre.map((x, i) => <span key={x.q}>{i > 0 && ' · '}{stavLink(x, true)}</span>)}
                </p>
              )}

              {visPersoner && personer.length > 0 && (
                <>
                  {visGodser && <h2 style={{ ...etiket, margin: '8px 0 0' }}>Personer</h2>}
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 14 }}>
                    {personer.slice(0, antalVist).map((p, i) => (
                      <li key={p.id} style={{ borderTop: i ? `1px solid ${T.line}` : undefined }}>
                        <Link href={personPath(p.id)} style={{ display: 'grid', gridTemplateColumns: smal ? '36px minmax(0, 1fr)' : '44px minmax(0, 1fr) auto', gap: smal ? 12 : 16, alignItems: 'center', padding: smal ? '12px 14px' : '14px 18px', textDecoration: 'none', color: T.ink }}>
                          <span aria-hidden="true" style={{ width: smal ? 36 : 44, height: smal ? 36 : 44, borderRadius: 9999, background: T.surfaceSunken, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: smal ? 15 : 17, fontWeight: 600, color: T.bordeaux }}>{initials(p.name)}</span>
                          <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                            <span style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: '24px' }}><Fremhaev tekst={p.name} maerker={p.maerker} /></span>
                            <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{[p.years, p.title].filter(Boolean).join(' · ')}</span>
                            {smal && p.linje && <span style={{ fontFamily: T.mono, fontSize: 11, lineHeight: '14px', color: T.inkSecondary, marginTop: 2 }}>{p.linje}</span>}
                          </span>
                          {!smal && p.linje && <span style={{ fontFamily: T.mono, fontSize: 11, lineHeight: '14px', padding: '3px 8px', borderRadius: 8, background: T.surfaceSunken, color: T.inkSecondary, whiteSpace: 'nowrap' }}>{p.linje}</span>}
                        </Link>
                      </li>
                    ))}
                  </ul>
                  {personer.length > antalVist && (
                    <button type="button" onClick={() => setVist({ noegle, n: antalVist + SIDE })}
                      style={{ alignSelf: 'flex-start', fontFamily: T.sans, fontSize: 14, fontWeight: 600, padding: '10px 18px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' }}>
                      Vis {Math.min(SIDE, personer.length - antalVist)} mere (af {personer.length - antalVist})
                    </button>
                  )}
                </>
              )}

              {visGodser && (
                <>
                  {f.type === 'alt' && personer.length > 0 && <h2 style={{ ...etiket, margin: '16px 0 0' }}>Besiddelser</h2>}
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 14 }}>
                    {godser.map((g, i) => (
                      <li key={g.id} style={{ borderTop: i ? `1px solid ${T.line}` : undefined }}>
                        <Link href={estatePath(g.id)} style={{ display: 'flex', flexDirection: 'column', padding: '14px 18px', textDecoration: 'none', color: T.ink }}>
                          <span style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: '24px' }}><Fremhaev tekst={g.navn} maerker={g.maerker} /></span>
                          <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{g.ejere ? `${g.ejere} ${g.ejere === 1 ? 'ejer' : 'ejere'} i Aarbogen` : 'Ingen ejere registreret'}</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </>
              )}

              {(visPersoner ? personer.length : 0) + (visGodser ? godser.length : 0) === 0 && (
                <div style={{ padding: '12px 4px' }}>
                  <h2 style={{ margin: 0, fontFamily: T.serif, fontSize: 24, fontWeight: 600 }}>
                    {f.q.trim() ? `${f.type === 'besiddelser' ? 'Ingen besiddelse' : f.type === 'personer' ? 'Ingen person' : 'Ingen'} hedder »${f.q.trim()}«` : 'Ingen passer til afgrænsningen'}
                  </h2>
                  {andre.length > 0 ? (
                    <p style={{ margin: '6px 0 0', fontSize: 15, lineHeight: '24px', color: T.inkSecondary }}>
                      Mente du {andre.map((x, i) => (
                        <span key={x.q}>{i > 0 && (i === andre.length - 1 ? ' eller ' : ', ')}{stavLink(x, false)}</span>
                      ))}? Stavemåder skifter gennem udgaverne.
                    </p>
                  ) : (
                    <p style={{ margin: '6px 0 0', fontSize: 15, lineHeight: '24px', color: T.inkSecondary }}>
                      {f.q.trim() ? 'Prøv en anden stavemåde. Stavemåder skifter gennem udgaverne.' : 'Prøv at fjerne en afgrænsning.'}
                    </p>
                  )}
                </div>
              )}
            </>
          )}
        </section>
      </div>
    </main>
  );
}

// Årstal: skrives frit og sendes først videre, når feltet er tomt eller rummer et helt år.
function AarFelt({ id, vaerdi, onAar, pladsholder }: { id: string; vaerdi: number | null; onAar: (n: number | null) => void; pladsholder: string }) {
  const [tekst, setTekst] = useState<string | null>(null);
  return (
    <input id={id} inputMode="numeric" value={tekst ?? (vaerdi == null ? '' : String(vaerdi))} placeholder={pladsholder}
      onChange={(e) => {
        const v = e.target.value.replace(/[^\d]/g, '').slice(0, 4);
        setTekst(v);
        if (v === '') onAar(null);
        else if (v.length >= 3) onAar(parseInt(v, 10));
      }}
      onBlur={() => setTekst(null)}
      style={{ width: 76, fontFamily: T.mono, fontSize: 14, lineHeight: '20px', padding: 8, borderRadius: 9, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink }} />
  );
}
