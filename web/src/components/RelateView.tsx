// ---- Er vi i familie? (webredesign fase 6a, tegningen »Er vi i familie? (web)«) ----
// De to valgte personer ligger i adressen (/slaegtskab?a=&b=), så resultatet kan deles og åbnes direkte.
// Hver plads har sin egen personvælger (combobox); vejen er en liste af links til personsiderne.
import { useId, useMemo, useState, type CSSProperties, type KeyboardEvent } from 'react';
import { computeRelationship, type RelationLine } from '@daa/core';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath, slaegtskabPath, stamtraePath } from '../data/nav';
import { faellesAneTekst, personForslag, slaegtledTekst, vejTrin, type PersonForslag } from '../data/slaegtskab';
import type { Model } from '../data/types';
import { useSmalSkaerm } from '../useSmalSkaerm';
import { delLink, type DelUdfald } from '../data/delLink';

const etiket: CSSProperties = { margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '0.16em', textTransform: 'uppercase' };
const knap: CSSProperties = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '10px 16px', borderRadius: 11, cursor: 'pointer', textDecoration: 'none' };

export function RelateView({ model, relA: relAUrl, relB, meId, slug, onVaelg }: {
  model: Model | null;
  relA: string | null; relB: string | null; // kanoniske id'er fra adressen (kan pege på en person, der ikke findes)
  meId: string | null;
  slug: string;
  onVaelg: (a: string | null, b: string | null) => void;
}) {
  const smal = useSmalSkaerm();
  // Mobiltegningen: på smal skærm er »Det er mig« første person, når adressen ikke selv har valgt nogen.
  // Et delt link (a eller b sat) overstyres aldrig.
  const relA = relAUrl ?? (smal && !relB && meId ? meId : null);
  const a = relA && model ? model.byId[relA] ?? null : null;
  const b = relB && model ? model.byId[relB] ?? null : null;
  const me = meId && model ? model.byId[meId] ?? null : null;
  const rel = useMemo(() => (model && a && b ? computeRelationship(model, a.id, b.id) : null), [model, a, b]);

  return (
    <main style={{ maxWidth: 1240, margin: '0 auto', padding: smal ? '24px 16px 48px' : '40px 24px 64px', display: 'flex', flexDirection: 'column', gap: smal ? 24 : 32, fontFamily: T.sans, color: T.ink }}>
      <header style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <p style={{ ...etiket, color: T.goldInk }}>På tværs af slægterne</p>
        <h1 style={{ margin: 0, fontFamily: T.serif, fontSize: smal ? 36 : 48, lineHeight: 1.05, fontWeight: 500 }}>Er vi i familie?</h1>
      </header>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div role="group" aria-label="Vælg to personer" style={{ display: 'grid', gridTemplateColumns: smal ? 'minmax(0, 1fr)' : 'minmax(0, 1fr) auto minmax(0, 1fr)', gap: smal ? 10 : 16, alignItems: 'start' }}>
          <PersonVaelger label="Første person" smal={smal} model={model} valgtId={relA} valgt={a} onVaelg={(id) => onVaelg(id, relB)} />
          <button type="button" aria-label="Byt om på de to personer" title="Byt om" disabled={!relA && !relB} onClick={() => onVaelg(relB, relA)}
            style={{ width: 44, height: 44, marginTop: smal ? 0 : 22, justifySelf: 'center', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width={18} height={18} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke={T.ink} strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round" style={smal ? { transform: 'rotate(90deg)' } : undefined}><path d="M4 7h12l-3-3M16 13H4l3 3" /></svg>
          </button>
          <PersonVaelger label="Anden person" smal={smal} model={model} valgtId={relB} valgt={b} onVaelg={(id) => onVaelg(relA, id)} />
        </div>
        {me && relA !== me.id && (
          <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkMuted }}>
            <button type="button" onClick={() => onVaelg(me.id, relB === me.id ? null : relB)}
              style={{ font: 'inherit', fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer', textDecoration: 'underline' }}>
              Brug »Det er mig« ({me.name}) som første person
            </button>
          </p>
        )}
      </div>

      {!model ? <p style={{ margin: 0, fontSize: 15, color: T.inkMuted }}>Henter Aarbogen …</p>
        : !a || !b ? <p style={{ margin: 0, fontSize: 15, lineHeight: '24px', color: T.inkSecondary, maxWidth: '52em' }}>Vælg to personer for at se, om og hvordan Aarbogen forbinder dem.</p>
        : rel && <Resultat key={`${a.id}|${b.id}`} lines={rel.lines} found={rel.found}
          aNavn={a.name} bNavn={b.name} delSti={slaegtskabPath(a.id, b.id)} slug={slug} smal={smal} />}
    </main>
  );
}

// Personvælger: et søgefelt med forslag (ARIA combobox). Feltet viser den valgte person, til man skriver.
// Smal skærm (fase 9): feltet viser kun navnet, og leveårene står under det — ellers skæres de af midt i datoen.
function PersonVaelger({ label, smal, model, valgtId, valgt, onVaelg }: {
  label: string; smal: boolean; model: Model | null; valgtId: string | null; valgt: Model['persons'][number] | null;
  onVaelg: (id: string) => void;
}) {
  const id = useId();
  const [tekst, setTekst] = useState<string | null>(null); // null = vis den valgte person
  const [aktiv, setAktiv] = useState(0);
  const forslag = useMemo(() => (model && tekst ? personForslag(model, tekst) : []), [model, tekst]);
  const aaben = tekst !== null && tekst.trim() !== '';
  const vist = tekst ?? (valgt ? `${valgt.name}${valgt.years && !smal ? ` (${valgt.years})` : ''}` : '');
  const aarUnder = smal && tekst === null && valgt?.years ? valgt.years : null;
  const vaelg = (f: PersonForslag) => { onVaelg(f.id); setTekst(null); setAktiv(0); };
  const tast = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown' && forslag.length) { e.preventDefault(); setAktiv((i) => (i + 1) % forslag.length); }
    else if (e.key === 'ArrowUp' && forslag.length) { e.preventDefault(); setAktiv((i) => (i - 1 + forslag.length) % forslag.length); }
    else if (e.key === 'Enter' && aaben && forslag[aktiv]) { e.preventDefault(); vaelg(forslag[aktiv]); }
    else if (e.key === 'Escape' && tekst !== null) { e.preventDefault(); setTekst(null); }
  };
  return (
    <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      <label htmlFor={`${id}-felt`} style={{ ...etiket, color: T.inkMuted }}>{label}</label>
      <input id={`${id}-felt`} type="text" role="combobox" autoComplete="off" aria-autocomplete="list"
        aria-expanded={aaben} aria-controls={`${id}-liste`}
        aria-activedescendant={aaben && forslag[aktiv] ? `${id}-f${aktiv}` : undefined}
        aria-describedby={aarUnder ? `${id}-aar` : undefined}
        value={vist} placeholder="Skriv et navn" disabled={!model}
        // Feltet viser »Navn (leveår)«, til man skriver. Fokus markerer teksten, så det første tegn erstatter den;
        // står markøren alligevel efter navnet, tæller kun det nye.
        onFocus={(e) => e.currentTarget.select()}
        onChange={(e) => { const v = e.target.value; setTekst(tekst === null && vist && v.startsWith(vist) ? v.slice(vist.length) : v); setAktiv(0); }}
        onKeyDown={tast} onBlur={() => setTekst(null)}
        style={{ fontFamily: T.sans, fontSize: 16, lineHeight: '22px', padding: '12px 16px', borderRadius: 11, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, minWidth: 0 }} />
      {aarUnder && <span id={`${id}-aar`} style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{aarUnder}</span>}
      {valgtId && model && !valgt && tekst === null && (
        <p role="note" style={{ margin: 0, fontSize: 13, color: T.danger }}>Personen i linket findes ikke i Aarbogen. Vælg en anden.</p>
      )}
      <ul id={`${id}-liste`} role="listbox" aria-label={`Forslag til ${label.toLowerCase()}`} hidden={!aaben}
        style={{ position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 20, margin: '4px 0 0', padding: 4, listStyle: 'none', background: T.surfaceRaised, border: `1px solid ${T.lineStrong}`, borderRadius: 11, boxShadow: '0 12px 30px rgba(20,17,13,.14)', maxHeight: 360, overflowY: 'auto' }}>
        {forslag.map((f, i) => (
          <li key={f.id} id={`${id}-f${i}`} role="option" aria-selected={i === aktiv}
            onMouseDown={(e) => e.preventDefault()} onClick={() => vaelg(f)} onMouseEnter={() => setAktiv(i)}
            style={{ padding: '9px 12px', borderRadius: 8, cursor: 'pointer', background: i === aktiv ? T.bordeauxTint : 'transparent', display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, lineHeight: '22px' }}>{f.name}</span>
            <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{[f.years, f.linje].filter(Boolean).join(' · ')}</span>
          </li>
        ))}
        {aaben && forslag.length === 0 && (
          <li role="option" aria-disabled="true" aria-selected={false} style={{ padding: '9px 12px', fontSize: 14, color: T.inkMuted }}>Ingen i Aarbogen hedder »{tekst!.trim()}«</li>
        )}
      </ul>
    </div>
  );
}

function Resultat({ lines, found, aNavn, bNavn, delSti, slug, smal }: {
  lines: RelationLine[]; found: boolean;
  aNavn: string; bNavn: string; delSti: string; slug: string; smal: boolean;
}) {
  const [vej, setVej] = useState(0);
  const [kopieret, setKopieret] = useState<DelUdfald | null>(null);
  // Telefonen deler med sin egen delemenu; bred skærm kopierer (fase 9).
  const kopier = async () => { setKopieret(await delLink(`${window.location.origin}${delSti}`, document.title, smal)); };
  if (!found) {
    return (
      <section aria-label="Resultat" style={{ background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 22, padding: smal ? 22 : 32, maxWidth: 720 }}>
        <p style={{ ...etiket, color: T.inkMuted }}>Slægtskab</p>
        <h2 style={{ margin: '10px 0 0', fontFamily: T.serif, fontSize: smal ? 28 : 34, lineHeight: 1.1, fontWeight: 500 }}>Aarbogen viser ingen forbindelse</h2>
        <p style={{ margin: '10px 0 0', fontSize: 15, lineHeight: '24px', color: T.inkSecondary }}>
          Aarbogen viser ingen fælles ane for {aNavn} og {bNavn}. Forbindelsen regnes kun gennem forældre og børn, som bogen angiver dem; ægteskab tæller ikke.
        </p>
      </section>
    );
  }
  const valgt = Math.min(vej, lines.length - 1);
  const line = lines[valgt];
  // Kun stier med uangivet/'sikker' på hvert led tæller; uafhaengige kan også dække en anden
  // sti i samme sammenslåede linje. Fravær af usikker-flaget er ikke nok.
  const korrob = line.uafhaengige >= 2 ? `Bekræftet ad ${line.uafhaengige} uafhængige linjer`
    : line.usikker && lines.some((l) => l.uafhaengige > 0) ? 'Bekræftet ad en anden, sikker linje' : '';
  const omstridt = line.weakestKonfidens === 'omstridt';
  const trin = vejTrin(line);
  const samme = line.d1 === 0 && line.d2 === 0;
  return (
    <section aria-label="Resultat" style={{ display: 'flex', flexWrap: 'wrap', gap: smal ? 20 : 32, alignItems: 'flex-start' }}>
      <div style={{ flex: '1 1 420px', minWidth: 0, background: T.surfaceInverse, color: T.inkOnInverse, borderRadius: 22, padding: smal ? 22 : 32, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <p style={{ ...etiket, color: T.goldOnInverse }}>Slægtskab</p>
        <h2 aria-live="polite" style={{ margin: 0, fontFamily: T.serif, fontSize: smal ? 32 : 40, fontWeight: 500, lineHeight: 1.05 }}>
          {line.usikker && <span style={{ display: 'block', fontSize: smal ? 20 : 24, fontStyle: 'italic', color: T.goldOnInverse }}>{omstridt ? 'Omstridt' : 'Sandsynligvis'}</span>}
          {line.label}
        </h2>
        <p style={{ margin: 0, fontSize: 15, lineHeight: '23px', color: T.inkMutedOnInverse }}>
          {samme ? 'Den samme person er valgt to gange.' : `${aNavn} og ${bNavn}. ${faellesAneTekst(line)}. ${slaegtledTekst(line)}.`}
        </p>
        {line.usikker && (
          <p style={{ margin: 0, fontSize: 14, lineHeight: '21px', color: T.goldOnInverse }}>
            {omstridt ? 'Vejen går gennem et omstridt led: kilderne er uenige om det.'
              : line.weakestKonfidens === 'sandsynlig' ? 'Vejen går gennem et sandsynligt led, så slægtskabet er sandsynligt, ikke sikkert.'
                : 'Vejen går gennem et formodet led, så slægtskabet er sandsynligt, ikke sikkert.'}
          </p>
        )}
        {korrob && <p style={{ margin: 0, fontSize: 14, lineHeight: '21px', color: T.inkMutedOnInverse }}>✓ {korrob}</p>}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 6 }}>
          <button type="button" onClick={() => { void kopier(); }} style={{ ...knap, border: 0, background: T.surfaceRaised, color: T.ink }}>{smal ? 'Del resultatet' : 'Kopiér link til resultatet'}</button>
          {!samme && <Link href={stamtraePath(slug, line.lcaId)} style={{ ...knap, border: '1px solid rgba(251,248,241,0.35)', color: T.inkOnInverse }}>Vis fælles ane i stamtræet</Link>}
        </div>
        <p role="status" aria-live="polite" style={{ margin: 0, minHeight: 20, fontSize: 13, color: T.inkMutedOnInverse }}>
          {kopieret === 'kopieret' ? 'Linket er kopieret.' : kopieret === 'fejl' ? 'Linket kunne ikke kopieres. Kopiér adressen fra browserens adresselinje.' : ''}
        </p>
      </div>

      {!samme && (
        <div style={{ flex: '999 1 520px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {lines.length > 1 && (
            <div role="group" aria-label="Veje mellem de to" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <button type="button" disabled={vej === 0} onClick={() => setVej((v) => v - 1)} style={{ ...knap, padding: '8px 12px', border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, opacity: vej === 0 ? 0.5 : 1 }}>‹ Forrige vej</button>
              <span style={{ fontSize: 14, color: T.inkSecondary }}>Vej {vej + 1} af {lines.length}{vej === 0 ? ' · den nærmeste' : ''}</span>
              <button type="button" disabled={vej === lines.length - 1} onClick={() => setVej((v) => v + 1)} style={{ ...knap, padding: '8px 12px', border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, opacity: vej === lines.length - 1 ? 0.5 : 1 }}>Næste vej ›</button>
            </div>
          )}
          <ol aria-label="Vejen, trin for trin" style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column' }}>
            {trin.map((t, i) => {
              const ende = t.foerste || t.anden;
              const maerker = [t.faellesAne && 'Fælles ane', t.foerste && 'Første person', t.anden && 'Anden person'].filter(Boolean).join(' · ');
              return (
                <li key={`${t.id}-${i}`} style={{ display: 'flex', flexDirection: 'column' }}>
                  {i > 0 && (
                    <div style={{ display: 'grid', gridTemplateColumns: '28px minmax(0, 1fr)', gap: 16, alignItems: 'center' }}>
                      <span aria-hidden="true" style={{ justifySelf: 'center', height: 22, borderLeft: `2px ${t.usikkertLed ? 'dashed' : 'solid'} ${t.usikkertLed ? T.danger : T.lineStrong}` }} />
                      {t.usikkertLed && <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '0.1em', textTransform: 'uppercase', color: T.danger }}>{t.usikkertLed === 'sandsynlig' ? 'sandsynligt' : t.usikkertLed} led</span>}
                    </div>
                  )}
                  <div style={{ display: 'grid', gridTemplateColumns: '28px minmax(0, 1fr)', gap: 16, alignItems: 'center' }}>
                    <span aria-hidden="true" style={{ justifySelf: 'center', width: t.faellesAne || ende ? 14 : 12, height: t.faellesAne || ende ? 14 : 12, borderRadius: 9999, background: t.faellesAne ? T.gold : T.bordeaux, boxShadow: ende && !t.faellesAne ? `0 0 0 2px ${T.bordeauxTint}, 0 0 0 3.5px ${T.bordeaux}` : undefined }} />
                    <Link href={personPath(t.id)} style={{ background: t.faellesAne ? T.surfaceRaised : ende ? T.bordeauxTint : T.surfaceRaised, border: t.faellesAne ? `1px solid ${T.gold}` : ende ? `1.5px solid ${T.bordeaux}` : `1px solid ${T.line}`, borderRadius: 14, padding: '14px 18px', textDecoration: 'none', color: T.ink, display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: '4px 12px', alignItems: 'baseline' }}>
                      <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                        <span style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600, lineHeight: '25px' }}>{t.name}</span>
                        {t.years && <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{t.years}</span>}
                      </span>
                      {maerker && <span style={{ fontFamily: T.mono, fontSize: 11, lineHeight: '14px', letterSpacing: '0.14em', textTransform: 'uppercase', color: t.faellesAne ? T.goldInk : T.bordeaux }}>{maerker}</span>}
                    </Link>
                  </div>
                </li>
              );
            })}
          </ol>
          {trin.some((t) => t.usikkertLed) && (
            <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkMuted }}>
              Et sandsynligt, formodet eller omstridt led står med ordet og stiplet streg.
            </p>
          )}
        </div>
      )}
    </section>
  );
}
