// "Sammenlign udgaver" — redaktør-flade til tværudgave-identitet (Problem 3 §5).
// Kildevalg → matcher-kørsel (memoiseret, @daa/core) → arbejdsliste → Bekræft/Afvis via
// submitChange (samme dry-run/LIVE-flow som resten af redaktionen). Retning (§5.4):
// eksisterende base = kanonisk (objekt/sink), ny udgaves person = alias (subjekt).
import { useState, useEffect, useMemo, useCallback } from 'react';
import { matchUdgaver, buildMatchFrame, type MatchFrame, type RedMatchPerson } from '@daa/core';
import {
  fetchSources, fetchMatchPersoner, fetchIkkeSammeSomPar, fetchSammeSomPar, type SourceRow,
} from '../data/redaktionRead';
import { submitChange, type Change } from '../data/redaktionWrite';
import { buildArbejdsliste, pairKey, type Kandidat } from '../data/sammenlign';

function visning(p?: RedMatchPerson): string {
  if (!p) return '(ukendt)';
  const fy = p.foedsel?.date_min?.slice(0, 4) ?? '';
  const dy = p.doed?.date_min?.slice(0, 4) ?? '';
  const span = fy || dy ? ` (${fy}–${dy})` : '';
  return `${p.navn}${span}`;
}

export function SammenlignUdgaver({ role }: { role?: string }) {
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [personer, setPersoner] = useState<RedMatchPerson[]>([]);
  const [afviste, setAfviste] = useState<{ aId: string; bId: string }[]>([]);
  const [linkede, setLinkede] = useState<{ aId: string; bId: string }[]>([]);
  const [nyKildeId, setNyKildeId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [fejl, setFejl] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true); setFejl(null);
    Promise.all([fetchSources(), fetchMatchPersoner(), fetchIkkeSammeSomPar(), fetchSammeSomPar()])
      .then(([s, p, afv, lnk]) => {
        if (!alive) return;
        setSources(s); setPersoner(p); setAfviste(afv); setLinkede(lnk);
        setNyKildeId((prev) => prev ?? (
          [...s].filter((x) => x.aar != null).sort((a, b) => (b.aar as number) - (a.aar as number))[0]?.id ?? s[0]?.id ?? null));
      })
      .catch((e) => alive && setFejl(String(e?.message ?? e)))
      .finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [refresh]);

  const byId = useMemo(() => new Map(personer.map((p) => [String(p.id), p])), [personer]);

  const arbejdsliste = useMemo(() => {
    if (nyKildeId == null) return null;
    const framesA: MatchFrame[] = [], framesB: MatchFrame[] = [], aIds: string[] = [];
    for (const p of personer) {
      const f = buildMatchFrame(p);
      if (p.sourceIds.includes(nyKildeId)) { framesA.push(f); aIds.push(String(p.id)); }
      else framesB.push(f);
    }
    const pairs = matchUdgaver(framesA, framesB);
    return buildArbejdsliste(
      pairs, aIds,
      new Set(afviste.map((x) => pairKey(x.aId, x.bId))),
      new Set(linkede.map((x) => pairKey(x.aId, x.bId))),
    );
  }, [personer, nyKildeId, afviste, linkede]);

  const run = useCallback(async (change: Change, key: string) => {
    setBusy(key); setFejl(null);
    try {
      await submitChange(change, { dryRun: false, role });
      setRefresh((r) => r + 1);
    } catch (e) {
      setFejl(String((e as { message?: string })?.message ?? e));
    } finally { setBusy(null); }
  }, [role]);

  const bekraeft = (aId: string, bId: string) => // ny(A)=alias, eksisterende(B)=kanonisk (§5.4)
    run({ art: 'sammeSom', subjektType: 'person', subjektId: aId, payload: { aliasId: aId, objektId: bId } }, `s:${aId}:${bId}`);
  const afvis = (aId: string, bId: string) =>
    run({ art: 'ikkeSammeSom', subjektType: 'person', subjektId: aId, payload: { aId, bId } }, `a:${aId}:${bId}`);
  const markerNy = (kand: Kandidat[]) => { // afvis alle personens ≥review-kandidater
    kand.filter((k) => !k.afvist && !k.linket).forEach((k) => afvis(String(k.aId), String(k.bId)));
  };

  if (loading) return <div className="sammenlign">Indlæser redaktions-datasæt…</div>;

  const f = arbejdsliste?.fremdrift;
  const aabne = arbejdsliste?.personer.filter((p) => p.status === 'aaben') ?? [];
  const formodetNye = arbejdsliste?.personer.filter((p) => p.status === 'formodet_ny') ?? [];

  return (
    <div className="sammenlign" style={{ padding: '1rem', maxWidth: 900 }}>
      <h2>Sammenlign udgaver</h2>
      <label>
        Ny udgave:{' '}
        <select value={nyKildeId ?? ''} onChange={(e) => setNyKildeId(Number(e.target.value))}>
          {[...sources].sort((a, b) => (b.aar ?? 0) - (a.aar ?? 0)).map((s) => (
            <option key={s.id} value={s.id}>{s.udgave ?? s.titel ?? `Kilde ${s.id}`}{s.aar ? ` (${s.aar})` : ''}</option>
          ))}
        </select>
        {' '}mod resten af basen
      </label>

      {fejl && <p style={{ color: '#881A33' }}>Fejl: {fejl}</p>}

      {f && (
        <p style={{ fontSize: '.9em', color: '#6f675b' }}>
          {f.afklaret} af {f.total} afklaret · {f.staerke} stærke kandidater · {f.gennemse} til gennemsyn · {f.formodetNye} formodet nye
        </p>
      )}

      {aabne.map((person) => {
        const a = byId.get(person.aId);
        return (
          <div key={person.aId} style={{ border: '1px solid rgba(34,31,26,.1)', borderRadius: 6, padding: '.6rem .8rem', margin: '.5rem 0' }}>
            <strong>{visning(a)}</strong>
            <button style={{ marginLeft: '.8rem', fontSize: '.85em' }} disabled={!!busy}
              onClick={() => markerNy(person.kandidater)}>Markér som ny person</button>
            {person.kandidater.filter((k) => !k.afvist).map((k) => {
              const b = byId.get(String(k.bId));
              return (
                <div key={String(k.bId)} style={{ marginTop: '.4rem', paddingTop: '.4rem', borderTop: '1px dashed rgba(34,31,26,.1)' }}>
                  <span style={{ fontWeight: 600 }}>{k.tier === 'auto' ? '★ stærk' : 'gennemse'}</span>
                  {' '}<code>{(k.score ?? 0).toFixed(3)}</code> — {visning(b)}
                  <span style={{ fontSize: '.8em', color: '#6f675b', marginLeft: '.5rem' }}>
                    navn {k.nameSim.toFixed(2)} · fødsel {k.birthOverlap ? '✓' : '—'} · død {k.deathOverlap ? '✓' : '—'} · køn {k.sexEq ? '✓' : '✗'}
                  </span>
                  <div style={{ marginTop: '.3rem' }}>
                    <button disabled={!!busy || k.linket}
                      onClick={() => bekraeft(person.aId, String(k.bId))}>
                      {k.linket ? '✓ bekræftet' : 'Bekræft samme person'}
                    </button>
                    {' '}
                    <button disabled={!!busy} onClick={() => afvis(person.aId, String(k.bId))}>Afvis</button>
                  </div>
                </div>
              );
            })}
          </div>
        );
      })}

      {formodetNye.length > 0 && (
        <details style={{ marginTop: '1rem' }}>
          <summary>{formodetNye.length} formodet nye — ingen handling nødvendig</summary>
          <ul style={{ fontSize: '.9em', color: '#6f675b' }}>
            {formodetNye.map((p) => <li key={p.aId}>{visning(byId.get(p.aId))}</li>)}
          </ul>
        </details>
      )}
    </div>
  );
}
