// Præsensliste-læsefladen (spec 2026-07-22 §6). Redaktion-gated i v1: klient-gaten er UX —
// RLS er sikkerhedsgrænsen (§8). Beregningen er en ren projektion; ingen skrivninger.
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, kanoniserPresensGrundlag } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode, PresensLinjeGruppe } from '@daa/core';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
import type { PresensLinjeInfo } from '../data/presensLinjer';
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
    <div key={n.id} style={{ marginLeft: dybde * 18, marginBottom: 2 }}>
      <span
        data-person-id={n.id}
        onClick={() => onPick(n.id)}
        title={n.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
        style={{
          cursor: 'pointer',
          fontStyle: n.forbindelsesled ? 'italic' : 'normal', // bogens kursiv for afdøde forbindelsesled
          color: n.forbindelsesled ? T.muted3 : T.ink,
          background: fokusId === n.id ? 'rgba(128,0,32,.08)' : 'transparent',
        }}
      >
        {navnAf(n.id)} {aarAf(n.id)}{n.usikker ? <span> ⚠</span> : ''}
        {n.krydsReference ? <span style={{ fontStyle: 'normal' }}> (vist andetsteds i denne gren)</span> : ''}
      </span>
      {n.partnere.filter((p) => p.levende || !n.forbindelsesled).map((p) => (
        <span key={p.id} style={{ color: T.muted3 }}>
          {' '}· g. m. <span data-person-id={p.id} onClick={() => onPick(p.id)} style={{ cursor: 'pointer' }}>{navnAf(p.id)}</span>
        </span>
      ))}
      {n.boern.map((b) => renderNode(b, dybde + 1))}
    </div>
  );
  return (
    <section id={gren.anker.gren != null ? `${gren.anker.linje.toLowerCase()}-g${gren.anker.gren}` : undefined} style={{ marginBottom: 34 }}>
      {gren.anker.gren != null && (
        <h2 style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.22em', textTransform: 'uppercase', color: T.gold, fontWeight: 500 }}>
          {gren.anker.gren}. gren
        </h2>
      )}
      {renderNode(gren.ankerBlok, 0)}
      {gren.grupper.map((gr) => (
        <div key={gr.overskrift + gr.niveau} style={{ marginTop: 16 }}>
          <h3
            title={gr.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
            style={{ fontFamily: T.sans, fontSize: 11.5, letterSpacing: 2, textTransform: 'uppercase', color: T.muted3 }}
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
  const fokusId = (window.history.state as { fokusId?: string } | null)?.fokusId ?? null;

  useEffect(() => { currentSession().then(setSession).catch(() => setSession(null)); }, []);
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
  }, [session]);

  const liste: PresensListe | null = useMemo(() => {
    if (!model || !grundlag) return null;
    const k = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, k.ankre, k.levendeById);
  }, [model, grundlag]);

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
    <div style={{ padding: '28px 40px', maxWidth: 780 }}>
      <h1 style={{ fontFamily: T.sans, fontSize: 18 }}>Præsensliste</h1>
      {liste.advarsler.length > 0 && (
        <details style={{ margin: '10px 0 20px', fontFamily: T.sans, fontSize: 12, color: T.muted3 }}>
          <summary>{liste.advarsler.length} redaktionelle advarsler (rapportering — udløser aldrig ændringer)</summary>
          <ul>{liste.advarsler.slice(0, 200).map((a, i) => <li key={i}>{a.besked}</li>)}</ul>
        </details>
      )}
      {liste.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} aarAf={aarAf} onPick={onPickPerson} fokusId={fokusId} />
      ))}
    </div>
  );
}
