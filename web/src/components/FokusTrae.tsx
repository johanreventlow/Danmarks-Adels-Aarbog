// Stamtræets fokusvisning (webredesign fase 5c, tegningerne »Stamtræ · fokus (web)« og »… (mobil)«).
// Rækker med etiketter: forældre · søskende · gift · børn (data/fokusTrae.ts). Kortene er rigtige links;
// fokuskortet er ikke et link (det er her), men rummer bogmærket og »Åbn personsiden«.
//
// Søskende: på bred skærm rulles hele flokken vandret, og ← / → flytter fokus til forrige/næste søskende.
// På smal skærm viser mobiltegningen kun fokuskortet med synlige pile (»Søskende 2 af 7«). Pile og
// piletaster skifter person uden ny historik (onFocus), så man kan bladre gennem flokken.
import { useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from 'react';
import { T } from '../theme';
import { radius } from '@daa/theme';
import { Link } from '../Link';
import { personPath } from '../data/nav';
import type { Model } from '../data/types';
import { byggFokusRaekker, type FokusRelation, type FokusSoeskende } from '../data/fokusTrae';
import { Avatar, BookmarkFlag } from './primitives';
import { erTekniskLinje } from '../data/lineage';

const BOERN_FOER_VIS_ALLE = 4;

export function FokusTrae({ model, focusId, onPick, onFocus, personHref = personPath, hasBookmark, onToggleBookmark, smal }: {
  model: Model; focusId: string;
  onPick: (id: string) => void; // klik på et kort: nyt fokus med historik
  onFocus: (id: string) => void; // pile og piletaster mellem søskende: nyt fokus uden historik
  personHref?: (id: string) => string;
  hasBookmark: (id: string) => boolean; onToggleBookmark: (id: string) => void;
  smal: boolean;
}) {
  const r = useMemo(() => byggFokusRaekker(model, focusId), [model, focusId]);
  const fokusRef = useRef<HTMLDivElement>(null);
  const fraTast = useRef(false);
  const [alleBoern, setAlleBoern] = useState<string | null>(null); // focusId, hvis »Vis alle« er trykket

  // Rul fokuskortet ind i søskenderækken; efter en piletast får det også tastaturfokus.
  useEffect(() => {
    const el = fokusRef.current;
    if (!el) return;
    const roligt = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    el.scrollIntoView?.({ block: 'nearest', inline: 'center', behavior: roligt ? 'auto' : 'smooth' });
    if (fraTast.current) { el.focus(); fraTast.current = false; }
  }, [focusId]);

  if (!r) return null;
  const idx = r.soeskende.findIndex((s) => s.iFokus);
  const forrige = idx > 0 ? r.soeskende[idx - 1] : null;
  const naeste = idx >= 0 && idx < r.soeskende.length - 1 ? r.soeskende[idx + 1] : null;
  const gaaTil = (s: FokusSoeskende | null, tast: boolean) => { if (!s) return; fraTast.current = tast; onFocus(s.person.id); };
  const piletast = (e: KeyboardEvent) => {
    if (e.key === 'ArrowLeft' && forrige) { e.preventDefault(); gaaTil(forrige, true); }
    if (e.key === 'ArrowRight' && naeste) { e.preventDefault(); gaaTil(naeste, true); }
  };
  const f = model.byId[focusId];
  const linje = (model.lineage?.byPerson[focusId] ?? []).filter((lk) => !erTekniskLinje(lk)).map((lk) => model.lineage?.navn[lk]).find(Boolean);

  const fokusKort = (
    <div ref={fokusRef} tabIndex={-1} aria-current="true"
      style={{ flex: 'none', width: smal ? 'auto' : 220, background: T.bordeauxTint, border: `1.5px solid ${T.bordeaux}`, borderRadius: radius.card, padding: 14, boxShadow: '0 4px 14px rgba(136,26,51,.14)', display: 'flex', gap: 12, alignItems: smal ? 'center' : 'flex-start' }}>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
        <span style={{ ...etiketStil, color: T.bordeaux }}>I fokus{smal && linje ? ` · ${linje}` : ''}</span>
        <span style={{ fontFamily: T.serif, fontSize: smal ? 23 : 22, fontWeight: 600, lineHeight: 1.1, color: T.ink }}>{f.name}</span>
        {f.years && <span style={aarStil}>{f.years}</span>}
        {f.title && <span style={{ fontSize: 13, color: T.bordeaux }}>{f.title}</span>}
        {!smal && <Link href={personPath(focusId)} style={{ marginTop: 4, fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.bordeaux }}>Åbn personsiden</Link>}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 8 }}>
        <BookmarkFlag active={hasBookmark(focusId)} onClick={() => onToggleBookmark(focusId)} />
        {smal && (
          <Link href={personPath(focusId)} aria-label="Åbn personsiden"
            style={{ width: 44, height: 44, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', borderRadius: radius.field, background: T.bordeaux, textDecoration: 'none' }}>
            <Pil retning="hoejre" farve={T.onBordeaux} />
          </Link>
        )}
      </div>
    </div>
  );

  const kort = (rel: FokusRelation, ekstra?: string, bred = 150) => (
    <Link key={rel.person.id} href={personHref(rel.person.id)} onNavigate={() => onPick(rel.person.id)}
      style={{ flex: smal ? undefined : 'none', width: smal ? undefined : bred, minWidth: 0, background: T.surfaceGround, border: rel.konf ? `1.5px dashed ${T.danger}` : `1px solid ${T.line}`, borderRadius: radius.card, padding: '10px 12px', textDecoration: 'none', color: T.ink, display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, lineHeight: 1.15 }}>{rel.person.name}</span>
      {(ekstra || rel.person.years) && <span style={aarStil}>{[ekstra, rel.person.years].filter(Boolean).join(' · ')}</span>}
      {rel.konf && <span style={{ ...etiketStil, color: T.danger }}>{rel.konf}</span>}
    </Link>
  );

  const visAlle = alleBoern === focusId;
  const kanAfkorte = smal && r.antalBoern > BOERN_FOER_VIS_ALLE + 2;
  let tilbage = kanAfkorte && !visAlle ? BOERN_FOER_VIS_ALLE : Infinity;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, background: smal ? 'transparent' : T.surfaceRaised, border: smal ? 0 : `1px solid ${T.line}`, borderRadius: radius.card, padding: smal ? 0 : '24px clamp(16px, 3vw, 32px)' }}>
      {/* Forældre */}
      {smal ? (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center' }}>
          {r.foraeldre.map((p) => (
            <Link key={p.person.id} href={personHref(p.person.id)} onNavigate={() => onPick(p.person.id)}
              style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: T.surfaceRaised, border: p.konf ? `1.5px dashed ${T.danger}` : `1px solid ${T.line}`, borderRadius: 18, padding: '8px 14px', textDecoration: 'none', color: T.ink, fontSize: 14 }}>
              <Pil retning="op" farve={T.bordeaux} />{p.rolle}: <span style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600 }}>{p.person.name}</span>
              {p.konf && <span style={{ ...etiketStil, color: T.danger }}>{p.konf}</span>}
            </Link>
          ))}
          {r.manglendeForaelder && <span style={{ fontSize: 13, color: T.inkMuted, alignSelf: 'center' }}>{r.manglendeForaelder}</span>}
        </div>
      ) : (
        <Raekke smal={smal} etiket="Forældre">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, justifyContent: 'center' }}>
            {r.foraeldre.map((p) => (
              <Link key={p.person.id} href={personHref(p.person.id)} onNavigate={() => onPick(p.person.id)}
                style={{ display: 'flex', alignItems: 'center', gap: 10, background: T.surfaceGround, border: p.konf ? `1.5px dashed ${T.danger}` : `1px solid ${T.line}`, borderRadius: radius.card, padding: '10px 16px 10px 10px', textDecoration: 'none', color: T.ink }}>
                <Avatar n={p.person.name} size={36} />
                <span style={{ display: 'flex', flexDirection: 'column' }}>
                  <span style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600 }}>{p.person.name}</span>
                  <span style={aarStil}>{[p.rolle, p.person.years].filter(Boolean).join(' · ')}</span>
                  {p.konf && <span style={{ ...etiketStil, color: T.danger }}>{p.konf}</span>}
                </span>
              </Link>
            ))}
            {r.manglendeForaelder && (
              <span style={{ display: 'flex', alignItems: 'center', border: `1px dashed ${T.lineStrong}`, borderRadius: radius.card, padding: '10px 16px', fontSize: 13.5, color: T.inkMuted }}>{r.manglendeForaelder}</span>
            )}
          </div>
        </Raekke>
      )}
      <Stamme smal={smal} />

      {/* Søskende og fokus */}
      {smal ? (
        <>
          {fokusKort}
          {r.soeskende.length > 1 && (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
              <button type="button" disabled={!forrige} onClick={() => gaaTil(forrige, false)} aria-label={forrige ? `Forrige søskende: ${forrige.person.name}` : 'Ingen forrige søskende'} style={pilKnap(!forrige)}><Pil retning="venstre" farve={T.ink} /></button>
              <span style={{ fontSize: 13.5, color: T.inkSecondary, textAlign: 'center' }}>
                Søskende {idx + 1} af {r.soeskende.length}
                <br /><span style={aarStil}>{[forrige?.person.name.split(' ')[0], naeste?.person.name.split(' ')[0]].filter(Boolean).join(' ◂ ▸ ')}</span>
              </span>
              <button type="button" disabled={!naeste} onClick={() => gaaTil(naeste, false)} aria-label={naeste ? `Næste søskende: ${naeste.person.name}` : 'Ingen næste søskende'} style={pilKnap(!naeste)}><Pil retning="hoejre" farve={T.ink} /></button>
            </div>
          )}
        </>
      ) : (
        <Raekke smal={smal} etiket={r.soeskende.length > 1 ? `${r.soeskende.length} søskende` : 'Søskende'}>
          {/* Piletasterne virker, mens fokus står i rækken (på et kort eller fokuskortet). */}
          <div onKeyDown={piletast} role="group" aria-label="Søskendeflokken; brug venstre og højre pil til at skifte person"
            style={{ display: 'flex', gap: 10, overflowX: 'auto', padding: '4px 2px 8px', alignItems: 'stretch' }}>
            {r.soeskende.map((s) => s.iFokus ? <div key={s.person.id} style={{ flex: 'none' }}>{fokusKort}</div> : kort(s, s.halv ? 'halvsøskende' : undefined))}
            {r.soeskende.length === 1 && <span style={{ alignSelf: 'center', fontSize: 13.5, color: T.inkMuted, paddingLeft: 6 }}>Ingen søskende angivet i bogen</span>}
          </div>
        </Raekke>
      )}

      {/* Gift */}
      <Raekke smal={smal} etiket="Gift" skjulEtiket={smal}>
        <p style={{ margin: 0, display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', fontFamily: T.serif, fontStyle: 'italic', fontSize: 17, color: T.inkSecondary }}>
          {r.aegteskaber.length ? r.aegteskaber.map((a, i) => (
            <span key={a.unionId ?? a.navn}>
              {i > 0 && <span aria-hidden="true" style={{ marginRight: 8 }}>·</span>}
              ⚭ {a.aegtefaelleId
                ? <Link href={personHref(a.aegtefaelleId)} onNavigate={() => onPick(a.aegtefaelleId!)} style={{ color: T.bordeaux }}>{a.navn}</Link>
                : a.navn}
            </span>
          )) : <span style={{ fontStyle: 'normal', fontFamily: T.sans, fontSize: 13.5, color: T.inkMuted }}>Intet ægteskab angivet i bogen</span>}
        </p>
      </Raekke>
      <Stamme smal={smal} />

      {/* Børn */}
      <Raekke smal={smal} etiket={r.antalBoern ? `${r.antalBoern} ${r.antalBoern === 1 ? 'barn' : 'børn'}` : 'Børn'} alignStart>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
          {r.boerneGrupper.length === 0 && <p style={{ margin: 0, fontSize: 13.5, color: T.inkMuted }}>Ingen børn angivet i bogen</p>}
          {r.boerneGrupper.map((g, gi) => {
            const vis = g.boern.slice(0, Math.max(0, tilbage));
            tilbage -= vis.length;
            if (!vis.length) return null;
            return (
              <div key={g.aegteskab?.unionId ?? `uden-${gi}`} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {r.aegteskaber.length > 1 && (
                  <p style={{ margin: 0, fontFamily: T.serif, fontStyle: 'italic', fontSize: 16, color: T.inkSecondary }}>
                    {g.aegteskab ? `Med ${g.aegteskab.navn}` : 'Ægteskab ikke angivet'}
                  </p>
                )}
                {!g.aegteskab && r.boerneNote && <p style={{ margin: 0, fontSize: 13, lineHeight: '19px', color: T.inkMuted }}>{r.boerneNote}</p>}
                <div style={{ display: 'grid', gridTemplateColumns: smal ? 'repeat(2, minmax(0, 1fr))' : 'repeat(auto-fill, minmax(150px, 1fr))', gap: 10 }}>
                  {vis.map((b) => kort(b))}
                </div>
              </div>
            );
          })}
          {kanAfkorte && (
            <button type="button" aria-expanded={visAlle} onClick={() => setAlleBoern(visAlle ? null : focusId)} style={{ ...tekstKnap, alignSelf: 'center', padding: 10 }}>
              {visAlle ? 'Vis færre børn' : `Vis alle ${r.antalBoern} børn`}
            </button>
          )}
        </div>
      </Raekke>

      {r.harUsikre && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 20, marginTop: 8, paddingTop: 12, borderTop: `1px solid ${T.line}`, fontSize: 13, color: T.inkMuted }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}><span aria-hidden="true" style={{ width: 22, borderTop: `1.5px solid ${T.inkMuted}` }} />sikkert slægtskab</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}><span aria-hidden="true" style={{ width: 22, borderTop: `1.5px dashed ${T.danger}` }} />formodet eller omstridt</span>
        </div>
      )}
    </div>
  );
}

function Raekke({ smal, etiket, children, skjulEtiket = false, alignStart = false }: { smal: boolean; etiket: string; children: ReactNode; skjulEtiket?: boolean; alignStart?: boolean }) {
  if (smal) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {!skjulEtiket && <span style={{ ...etiketStil, color: T.inkMuted }}>{etiket}</span>}
        {children}
      </div>
    );
  }
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '96px minmax(0, 1fr)', gap: 16, alignItems: alignStart ? 'start' : 'center' }}>
      <span style={{ ...etiketStil, color: T.inkMuted, paddingTop: alignStart ? 6 : 0 }}>{etiket}</span>
      {children}
    </div>
  );
}

function Stamme({ smal }: { smal: boolean }) {
  return (
    <div style={smal ? { display: 'flex', justifyContent: 'center' } : { display: 'grid', gridTemplateColumns: '96px minmax(0, 1fr)', gap: 16 }}>
      {!smal && <span />}
      <span aria-hidden="true" style={{ justifySelf: 'center', width: 1.5, height: smal ? 12 : 20, background: T.lineStrong }} />
    </div>
  );
}

function Pil({ retning, farve }: { retning: 'venstre' | 'hoejre' | 'op'; farve: string }) {
  const d = retning === 'venstre' ? 'M12.5 4.5 7 10l5.5 5.5' : retning === 'hoejre' ? 'M7.5 4.5 13 10l-5.5 5.5' : 'M5 12.5 10 7l5 5.5';
  return <svg width={16} height={16} viewBox="0 0 20 20" aria-hidden="true" fill="none" stroke={farve} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>;
}

const etiketStil: CSSProperties = { fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '.14em', textTransform: 'uppercase' };
const aarStil: CSSProperties = { fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted };
const tekstKnap: CSSProperties = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, cursor: 'pointer' };
const pilKnap = (slukket: boolean): CSSProperties => ({ width: 44, height: 44, flex: 'none', borderRadius: radius.field, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, cursor: slukket ? 'default' : 'pointer', opacity: slukket ? 0.4 : 1, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' });
