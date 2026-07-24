// Præsensliste-læsefladen (spec 2026-07-22 §6). Redaktion-gated i v1: klient-gaten er UX —
// RLS er sikkerhedsgrænsen (§8). Beregningen er en ren projektion; ingen skrivninger.
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, kanoniserPresensGrundlag, groupByLinje } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode, PresensLinjeGruppe } from '@daa/core';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
import { fetchPresensLinjer, fetchPresensIntro, type PresensLinjeInfo } from '../data/presensLinjer';
import { currentSession, type RedSession } from '../data/auth';
import { T } from '../theme';

// Ren gren-sektion — eksporteret til test. navnAf/aarAf holder Model ude af renderingen.
export function PresensGrenSektion(props: {
  gren: PresensGren;
  navnAf: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gren, navnAf, aarAf, onPick, fokusId } = props;
  const renderNode = (n: PresensNode, dybde: number) => (
    <div key={n.id} style={{ marginLeft: dybde * 22, marginBottom: 2, fontSize: 14.5, lineHeight: 1.5 }}>
      <span
        data-person-id={n.id}
        onClick={() => onPick(n.id)}
        title={n.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
        style={{
          cursor: 'pointer',
          fontWeight: n.forbindelsesled ? 400 : 600, // bogens fed for levende, normal for forbindelsesled
          fontStyle: n.forbindelsesled ? 'italic' : 'normal', // bogens kursiv for afdøde forbindelsesled
          color: n.forbindelsesled ? T.muted3 : T.ink,
          background: fokusId === n.id ? 'rgba(128,0,32,.08)' : 'transparent',
        }}
      >
        {navnAf(n.id)}
      </span>
      {' '}<span style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2 }}>{aarAf(n.id)}</span>
      {n.usikker ? <span style={{ color: T.gold }}> ⚠</span> : ''}
      {n.krydsReference ? <span style={{ fontSize: 12, color: T.muted2 }}> ↗ vist andetsteds i denne gren</span> : ''}
      {n.partnere.filter((p) => p.levende || !n.forbindelsesled).map((p) => (
        <span key={p.id}>
          <span style={{ color: T.muted2, fontSize: 13.5 }}> · g. m. </span>
          <span data-person-id={p.id} onClick={() => onPick(p.id)} style={{ cursor: 'pointer', color: T.muted, fontSize: 13.5 }}>{navnAf(p.id)}</span>
        </span>
      ))}
      {n.boern.map((b) => renderNode(b, dybde + 1))}
    </div>
  );
  return (
    <section
      id={gren.anker.gren != null ? `${gren.anker.linje.toLowerCase()}-g${gren.anker.gren}` : undefined}
      style={
        gren.anker.gren != null
          ? { marginTop: 34, borderLeft: '2px solid rgba(185,160,106,.45)', paddingLeft: 26 }
          : { marginBottom: 34 }
      }
    >
      {gren.anker.gren != null && (
        // margin:0 — appen har ingen CSS-reset, så <h2> ellers arver browserens UA-standardmargin
        // og lægger uventet luft oveni sektionens egen border-top/padding-top (reviewfund).
        <h2 style={{ margin: 0, fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.22em', textTransform: 'uppercase', color: T.gold, fontWeight: 500 }}>
          {gren.anker.gren}. gren
        </h2>
      )}
      {renderNode(gren.ankerBlok, 0)}
      {gren.grupper.map((gr) => (
        <div key={gr.overskrift + gr.niveau} style={{ marginTop: 26 }}>
          <h3
            title={gr.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
            // margin:0 (samme reviewfund) — kun paddingBottom+marginBottom fra mockuppet skal gælde,
            // ikke <h3>'ens egen UA-standard top-margin oveni det omgivende div's marginTop:26.
            style={{ margin: 0, fontFamily: T.mono, fontSize: 10, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted, borderBottom: '1px solid rgba(34,31,26,.08)', paddingBottom: 6, marginBottom: 10 }}
          >
            {gr.overskrift}{gr.usikker ? ' ⚠' : ''}
          </h3>
          {gr.roedder.map((r) => renderNode(r, 1))}
        </div>
      ))}
    </section>
  );
}

// Pr.-linje sektion: våben + linjenummer + titel (lineage.navn) + navn (lineage.slaegtsnavn),
// derefter dens grene i rækkefølge (eksporteret til test, samme mønster som PresensGrenSektion).
export function PresensLinjeSektion(props: {
  gruppe: PresensLinjeGruppe;
  info: PresensLinjeInfo | undefined;
  navnAf: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gruppe, info, navnAf, aarAf, onPick, fokusId } = props;
  return (
    <div id={`linje-${gruppe.linje.toLowerCase()}`} style={{ marginTop: 52 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 24, borderTop: `1px solid rgba(34,31,26,.14)`, paddingTop: 26 }}>
        {info?.vaaben?.url && (
          <img src={info.vaaben.url} alt="Linjens våben" style={{ width: 92, height: 'auto', display: 'block', flex: 'none' }} />
        )}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, color: T.bordeaux, lineHeight: 1 }}>{gruppe.linje}</span>
            <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.26em', textTransform: 'uppercase', color: T.ink }}>linje</span>
          </div>
          {info?.titel && (
            <div style={{ fontFamily: T.serif, fontSize: 19, fontStyle: 'italic', color: '#3d382f', marginTop: 8 }}>{info.titel}</div>
          )}
          {info?.slaegtsnavn && (
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.3em', textTransform: 'uppercase', color: T.muted2, marginTop: 6 }}>{info.slaegtsnavn}</div>
          )}
        </div>
      </div>
      {gruppe.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} aarAf={aarAf} onPick={onPick} fokusId={fokusId} />
      ))}
    </div>
  );
}

export default function PresensView(props: { model: Model | null; onPickPerson: (id: string) => void }) {
  const { model, onPickPerson } = props;
  const [session, setSession] = useState<RedSession | null | 'henter'>('henter');
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [fejl, setFejl] = useState<string | null>(null);
  const [linjeInfo, setLinjeInfo] = useState<Record<string, PresensLinjeInfo>>({});
  const [intro, setIntro] = useState<string | null>(null);
  const fokusId = (window.history.state as { fokusId?: string } | null)?.fokusId ?? null;

  useEffect(() => { currentSession().then(setSession).catch(() => setSession(null)); }, []);
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
    fetchPresensLinjer().then(setLinjeInfo).catch(() => setLinjeInfo({})); // ikke-kritisk pynt
    fetchPresensIntro().then(setIntro).catch(() => setIntro(null)); // ikke-kritisk pynt
  }, [session]);

  const liste: PresensListe | null = useMemo(() => {
    if (!model || !grundlag) return null;
    const k = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, k.ankre, k.levendeById);
  }, [model, grundlag]);

  const linjer = useMemo(() => (liste ? groupByLinje(liste.grene) : []), [liste]);

  useEffect(() => {
    if (liste && fokusId) document.querySelector(`[data-person-id="${fokusId}"]`)?.scrollIntoView({ block: 'center' });
  }, [liste, fokusId]);

  if (session === 'henter') return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  if (session?.role !== 'redaktion')
    return <div style={{ padding: 40, color: T.muted3, fontFamily: T.sans }}>
      Præsenslisten kræver redaktør-login (v1 er redaktion-only). Log ind via <a href="/redaktion">Redaktion</a> og vend tilbage.
    </div>;
  if (fejl) return <div style={{ padding: 40, color: T.bordeaux }}>Kunne ikke hente grundlaget: {fejl}</div>;
  if (!liste) return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  if (liste.grene.length === 0)
    return <div style={{ padding: 40, color: T.muted3, fontFamily: T.sans }}>
      Ingen overhoveder udpeget endnu. Udpeg et linje-/gren-overhoved via person-editorens felt
      "Overhoved (linje/gren)" (værdi fx "II linje, 1. gren").
      {Object.values(grundlag?.levendeById ?? {}).every((v) => !v) && (
        <div style={{ marginTop: 10 }}>Bemærk: modellen indeholder ingen levende personer — er du logget ind som redaktør, så genindlæs siden, så data hentes med dit login.</div>
      )}
    </div>;

  const navnAf = (id: string) => model!.byId[id]?.name ?? `person ${id}`;
  const aarAf = (id: string) => model!.byId[id]?.years ?? '';
  return (
    <div style={{ maxWidth: 1240, margin: '0 auto', padding: '40px 28px 90px', display: 'grid', gridTemplateColumns: '200px minmax(0,860px)', gap: 36, justifyContent: 'center', alignItems: 'start' }}>
      {/* Venstre sticky-indeks */}
      <nav style={{ position: 'sticky', top: 28, paddingTop: 10 }}>
        <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted2, marginBottom: 14 }}>Indhold</div>
        {linjer.map((lin) => (
          <div key={lin.linje} style={{ marginBottom: 18 }}>
            <a href={`#linje-${lin.linje.toLowerCase()}`} style={{ display: 'flex', alignItems: 'baseline', gap: 8, color: T.ink }}>
              <span style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.bordeaux }}>{lin.linje}</span>
              <span style={{ fontSize: 12.5, fontWeight: 600 }}>linje</span>
            </a>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 5, margin: '8px 0 0 4px', borderLeft: '1px solid rgba(34,31,26,.12)', paddingLeft: 14 }}>
              {lin.grene.filter((g) => g.anker.gren != null).map((g) => (
                <a key={g.anker.personId} href={`#${lin.linje.toLowerCase()}-g${g.anker.gren}`} style={{ fontSize: 12.5, color: T.muted }}>
                  {g.anker.gren}. gren
                </a>
              ))}
            </div>
          </div>
        ))}
        <div style={{ borderTop: '1px solid rgba(34,31,26,.12)', marginTop: 6, paddingTop: 14 }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted2, marginBottom: 10 }}>Signatur</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7, fontSize: 11.5, color: T.muted, lineHeight: 1.45 }}>
            <div><span style={{ fontWeight: 600, color: T.ink }}>Navn</span> — levende person</div>
            <div><span style={{ fontStyle: 'italic', color: T.muted2 }}>Navn</span> — afdød forbindelsesled</div>
            <div><span style={{ color: T.gold }}>⚠</span> usikkert slægtskabsled</div>
            <div><span style={{ color: T.muted2 }}>↗</span> vist andetsteds i grenen</div>
          </div>
        </div>
      </nav>

      {/* Arket */}
      <div style={{ minWidth: 0 }}>
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.12em', color: T.muted2, margin: '0 0 14px 4px' }}>Reventlow / Præsensliste</div>
        <div style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 4, boxShadow: '0 2px 14px rgba(34,31,26,.07)', padding: '56px 72px 64px' }}>
          <div style={{ textAlign: 'center' }}>
            {/* Slægtens grundvåben er bevidst ikke vist her endnu — en linje-specifik
                coat_of_arms-række må ikke fejlagtigt genbruges som "hele slægtens" våben;
                kræver sin egen, adskillelige familie-niveau-række (jf. runbook-mønsteret). */}
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.22em', textTransform: 'uppercase', color: T.muted2 }}>Slægten Reventlow</div>
            <h1 style={{ fontFamily: T.serif, fontSize: 40, fontWeight: 500, lineHeight: 1.08, margin: '12px 0 0' }}>Præsensliste</h1>
            <div style={{ fontSize: 13.5, color: T.muted, marginTop: 10 }}>Slægtens nulevende medlemmer, ordnet efter linje og gren</div>
            <div style={{ width: 44, height: 1.5, background: T.gold, margin: '26px auto 0' }} />
          </div>

          {intro && (
            <div style={{ maxWidth: 640, margin: '34px auto 0' }}>
              {intro.split('\n\n').map((afsnit, i) => (
                <p key={i} style={{ fontFamily: T.serif, fontSize: 17.5, fontStyle: 'italic', lineHeight: 1.65, color: '#3d382f', margin: i === 0 ? 0 : '16px 0 0' }}>{afsnit}</p>
              ))}
            </div>
          )}

          {liste.advarsler.length > 0 && (
            <details style={{ margin: '28px auto 0', maxWidth: 640, background: T.panel, border: '1px solid rgba(185,160,106,.4)', borderRadius: 4, padding: '12px 18px' }}>
              <summary style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.1em', color: T.muted }}>
                {liste.advarsler.length} redaktionelle advarsler — rapportering, udløser aldrig ændringer
              </summary>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12, fontSize: 12.5, color: T.muted, lineHeight: 1.5 }}>
                {liste.advarsler.slice(0, 200).map((a, i) => (
                  <div key={i} style={{ display: 'flex', gap: 10 }}><span style={{ color: T.gold, flex: 'none' }}>▲</span><span>{a.besked}</span></div>
                ))}
              </div>
            </details>
          )}

          {linjer.map((lin) => (
            <PresensLinjeSektion key={lin.linje} gruppe={lin} info={linjeInfo[lin.linje]} navnAf={navnAf} aarAf={aarAf} onPick={onPickPerson} fokusId={fokusId} />
          ))}

          <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.08em', color: T.muted2, marginTop: 52, borderTop: '1px solid rgba(34,31,26,.08)', paddingTop: 14, textAlign: 'center' }}>
            Kun levende personer samt afdøde forbindelsesled medtages.
          </div>
        </div>
      </div>
    </div>
  );
}
