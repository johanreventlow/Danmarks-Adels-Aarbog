// "Sammenlign udgaver" — redaktør-flade til tværudgave-identitet (Problem 3 §5).
// Kildevalg → matcher-kørsel (memoiseret, @daa/core) → arbejdsliste → Bekræft/Afvis via
// submitChange (samme dry-run/LIVE-flow som resten af redaktionen). Retning (§5.4):
// eksisterende base = kanonisk (objekt/sink), ny udgaves person = alias (subjekt).
import { useState, useEffect, useMemo, useCallback } from 'react';
import {
  matchUdgaver, buildMatchFrame, collapseSameAs, previewSammeSom, parseYear,
  type MatchFrame, type RedMatchPerson, type Db, type SameAsEdge, type Union, type ParentChild,
} from '@daa/core';
import {
  fetchSources, fetchMatchPersoner, fetchIkkeSammeSomPar, fetchSammeSomPar, fetchFamilyGraph, type SourceRow,
} from '../data/redaktionRead';
import { submitChange, type Change } from '../data/redaktionWrite';
import { buildArbejdsliste, pairKey, type Kandidat } from '../data/sammenlign';

// Rå person → Koen (samme normalisering som web/src/data/model.ts, men uden 'ukendt'→null-skridtet
// dupliceret via en type-import — feltet er lille nok til at holde lokalt her).
function toKoen(k: string | null): 'mand' | 'kvinde' | null {
  return k === 'mand' || k === 'kvinde' ? k : null;
}

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
  const [familieGraf, setFamilieGraf] = useState<{ unions: Union[]; parentChild: ParentChild[] }>({ unions: [], parentChild: [] });
  const [nyKildeId, setNyKildeId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [fejl, setFejl] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true); setFejl(null);
    Promise.all([fetchSources(), fetchMatchPersoner(), fetchIkkeSammeSomPar(), fetchSammeSomPar(), fetchFamilyGraph()])
      .then(([s, p, afv, lnk, fam]) => {
        if (!alive) return;
        setSources(s); setPersoner(p); setAfviste(afv); setLinkede(lnk); setFamilieGraf(fam);
        setNyKildeId((prev) => prev ?? (
          [...s].filter((x) => x.aar != null).sort((a, b) => (b.aar as number) - (a.aar as number))[0]?.id ?? s[0]?.id ?? null));
      })
      .catch((e) => alive && setFejl(String(e?.message ?? e)))
      .finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [refresh]);

  const byId = useMemo(() => new Map(personer.map((p) => [String(p.id), p])), [personer]);

  // Db til den rådgivende fold-preview (§7.18): rå personer (born/died fra den VALGTE
  // fødsel/død-assertion, samme kilde som matcheren bruger) + hele familie-grafen. IKKE den
  // offentlige, RLS-filtrerede model — dette er redaktionens fulde datasæt, til at forudsige
  // om et bekræftet link ville folde offentligt (rådgivende, kan afvige pga. RLS/completeness).
  const rawDb: Db = useMemo(() => ({
    persons: personer.map((p) => ({
      id: p.id, name: p.navn,
      born: parseYear(p.foedsel?.date_min ?? p.foedsel?.date_max ?? null),
      died: parseYear(p.doed?.date_min ?? p.doed?.date_max ?? null),
      years: '', title: '', bio: '', privat: false, koen: toKoen(p.koen),
    })),
    unions: familieGraf.unions,
    parentChild: familieGraf.parentChild,
  }), [personer, familieGraf]);

  // Eksisterende afklarede samme_som-kanter i SameAsEdge-form (alias=subjekt, kanonisk=objekt —
  // §5.4-retningen; matcher red_samme_som). `linkede` er allerede netop dette par-sæt.
  const existingEdges: SameAsEdge[] = useMemo(
    () => linkede.map((l) => ({ alias: l.aId, canonical: l.bId })),
    [linkede],
  );

  // ÉN collapseSameAs-kørsel over ALLE bekræftede links → grundlaget for BÅDE karantæne-
  // oversigten og "✓ bekræftet"-badgets fold-status nedenfor (ingen grund til at gentage
  // union-find + validering pr. bekræftet kandidat).
  const foldPreview = useMemo(() => collapseSameAs(rawDb, existingEdges, new Map()), [rawDb, existingEdges]);
  const karantaeneByPersonId = useMemo(() => {
    const m = new Map<string, string>();
    for (const q of foldPreview.quarantined) for (const id of q.members) m.set(id, q.reason);
    return m;
  }, [foldPreview]);

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

  // Fold-hint pr. par: for et allerede bekræftet link, slå op om DET par er en af de karantænerede
  // grupper (fra den ÉN kørsel over alle bekræftede kanter ovenfor); for et endnu ubekræftet par,
  // kør previewSammeSom med den hypotetiske kant. RÅDGIVENDE (offentlig visning kan afvige pga.
  // RLS/completeness) — se sammeSomPreflight.ts-header.
  const foldHint = (aId: string, bId: string, linket: boolean): { folder: boolean; grund: string | null } => {
    if (linket) {
      const grund = karantaeneByPersonId.get(aId) ?? karantaeneByPersonId.get(bId) ?? null;
      return { folder: grund == null, grund };
    }
    return previewSammeSom(rawDb, existingEdges, { alias: aId, canonical: bId });
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

      {/* Karantæne-oversigt (§7.18): bekræftede samme_som-links der endnu ikke folder offentligt
          — typisk fordi forældrene i de to udgaver ikke selv er matchet endnu. Rådgivende. */}
      {foldPreview.quarantined.length > 0 && (
        <details open style={{ marginTop: '.75rem', border: '1px solid rgba(136,26,51,.25)', borderRadius: 6, padding: '.5rem .8rem', background: '#fdf3f5' }}>
          <summary style={{ color: '#881A33', fontWeight: 600, cursor: 'pointer' }}>
            {foldPreview.quarantined.length} bekræftet link{foldPreview.quarantined.length === 1 ? '' : 's'} folder endnu ikke offentligt
          </summary>
          <ul style={{ fontSize: '.85em', marginTop: '.4rem', marginBottom: 0 }}>
            {foldPreview.quarantined.map((q, i) => (
              <li key={i}>{q.members.map((id) => visning(byId.get(id))).join(' = ')} — <em>{q.reason}</em></li>
            ))}
          </ul>
        </details>
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
                  {(() => {
                    const hint = foldHint(person.aId, String(k.bId), k.linket);
                    return (
                      <div style={{ fontSize: '.8em', marginTop: '.25rem', color: hint.folder ? '#3d7a3d' : '#881A33' }}>
                        {k.linket
                          ? (hint.folder ? '✓ foldes offentligt til én person' : `✓ bekræftet — foldes IKKE endnu offentligt: ${hint.grund}`)
                          : (hint.folder ? '→ vil folde offentligt til én person' : `→ vil IKKE folde: ${hint.grund}`)}
                      </div>
                    );
                  })()}
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
