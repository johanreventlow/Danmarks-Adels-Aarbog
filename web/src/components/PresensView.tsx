// Præsensliste-læsefladen (spec 2026-07-22 §6). Redaktion-gated i v1: klient-gaten er UX —
// RLS er sikkerhedsgrænsen (§8). Beregningen er en ren projektion; ingen skrivninger.
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, kanoniserPresensGrundlag } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode } from '@daa/core';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
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
    <section style={{ marginBottom: 34 }}>
      <h2 style={{ fontFamily: T.sans, fontSize: 13, letterSpacing: 1.5, textTransform: 'uppercase', color: T.bordeaux }}>
        {gren.anker.raaVaerdi}
      </h2>
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
