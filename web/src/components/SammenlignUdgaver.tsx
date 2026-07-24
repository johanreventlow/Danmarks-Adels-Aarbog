// "Sammenlign udgaver" — redaktør-flade til tværudgave-identitet (Problem 3 §5).
// Kildevalg → matcher-kørsel (memoiseret, @daa/core) → arbejdsliste → Bekræft/Afvis via
// submitChange (samme dry-run/LIVE-flow som resten af redaktionen). Retning (§5.4):
// eksisterende base = kanonisk (objekt/sink), ny udgaves person = alias (subjekt).
import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  matchUdgaver, buildMatchFrame, collapseSameAs, previewSammeSom, parseYear,
  type MatchFrame, type RedMatchPerson, type Db, type SameAsEdge, type Union, type ParentChild,
} from '@daa/core';
import {
  fetchSources, fetchMatchPersoner, fetchIkkeSammeSomPar, fetchSammeSomPar, fetchFamilyGraph,
  fetchKandidatDetalje, fetchMatchAudit,
  type KandidatDetalje, type MatchAuditPost, type MatchRelationPar, type SourceRow,
} from '../data/redaktionRead';
import { describeCall, oversaetFejl, submitChange, type Change } from '../data/redaktionWrite';
import { buildArbejdsliste, pairKey, type Kandidat } from '../data/sammenlign';
import { KandidatSammenligning } from './KandidatSammenligning';
import {
  MatchOversigt, foraeldreNavne, formatBogReferencer, formatPersonNavn,
} from './MatchOversigt';

export { foraeldreNavne, formatBogReferencer, formatPersonNavn } from './MatchOversigt';

type SammenlignCache = {
  sources: SourceRow[];
  personer: RedMatchPerson[];
  afviste: MatchRelationPar[];
  linkede: MatchRelationPar[];
  matchAudit: MatchAuditPost[];
  familieGraf: { unions: Union[]; parentChild: ParentChild[] };
};

// Redaktionsfanen unmountes ved faneskift, så seneste komplette læsning holdes her til næste mount.
let senesteDatasaet: SammenlignCache | null = null;

function senesteKildeId(sources: SourceRow[]): number | null {
  return [...sources].filter((x) => x.aar != null).sort((a, b) => (b.aar as number) - (a.aar as number))[0]?.id
    ?? sources[0]?.id
    ?? null;
}

// Rå person → Koen (samme normalisering som web/src/data/model.ts, men uden 'ukendt'→null-skridtet
// dupliceret via en type-import — feltet er lille nok til at holde lokalt her).
function toKoen(k: string | null): 'mand' | 'kvinde' | null {
  return k === 'mand' || k === 'kvinde' ? k : null;
}

const visning = formatPersonNavn;

// Menneskevenlig næste-skridt pr. karantæne-grund (collapseSameAs.ts's groupSameAs/validateGroups
// producerer de rå, tekniske grund-strenge nedenfor — matchet på deres faste præfiks, uanset den
// dynamiske del efter parentesen). Ren UI-tekst, ingen domænelogik — derfor her, ikke i @daa/core.
function foldAdvice(grund: string): string | null {
  if (grund.startsWith('konkurrerende forældre')) return 'Match forældrene i de to udgaver, så foldes denne automatisk.';
  if (grund.startsWith('kendt-forskelligt køn')) return 'Tjek køns-angivelsen i de to udgaver — en fejlregistrering forhindrer foldning.';
  if (grund.startsWith('ikke-overlappende levetider') || grund.startsWith('fødsler for langt fra hinanden'))
    return 'Tjek fødsels-/dødsår i de to udgaver — datoerne passer ikke sammen som samme person.';
  if (grund.startsWith('ingen unik sink')) return 'Der findes modstridende samme_som-links for denne person — ret retningen (fjern og genopret).';
  if (grund.startsWith('ufuldstændig komponent')) return 'En del af gruppen er ikke synlig i det hentede datasæt — prøv at genindlæse.';
  if (grund.startsWith('selv-forælder') || grund.startsWith('selv-ægtefælle') || grund.startsWith('cyklus'))
    return 'Linket skaber en modstridende slægtskabs-kæde — gennemgå forældre/ægtefælle for de involverede personer.';
  return null;
}

export function SammenlignUdgaver({ role, dryRun = true }: { role?: string; dryRun?: boolean }) {
  const [sources, setSources] = useState<SourceRow[]>(() => senesteDatasaet?.sources ?? []);
  const [personer, setPersoner] = useState<RedMatchPerson[]>(() => senesteDatasaet?.personer ?? []);
  const [afviste, setAfviste] = useState<MatchRelationPar[]>(() => senesteDatasaet?.afviste ?? []);
  const [linkede, setLinkede] = useState<MatchRelationPar[]>(() => senesteDatasaet?.linkede ?? []);
  const [matchAudit, setMatchAudit] = useState<MatchAuditPost[]>(() => senesteDatasaet?.matchAudit ?? []);
  const [familieGraf, setFamilieGraf] = useState<{ unions: Union[]; parentChild: ParentChild[] }>(
    () => senesteDatasaet?.familieGraf ?? { unions: [], parentChild: [] },
  );
  const [nyKildeId, setNyKildeId] = useState<number | null>(() => senesteKildeId(senesteDatasaet?.sources ?? []));
  const [loading, setLoading] = useState(true);
  const [fejl, setFejl] = useState<string | null>(null);
  const [dryRunPreview, setDryRunPreview] = useState<{ key: string; text: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [aabentPar, setAabentPar] = useState<string | null>(null);
  const [aktivFane, setAktivFane] = useState<'arbejdsliste' | 'bekraeftede' | 'karantaene' | 'historik'>('arbejdsliste');
  const [arbejdslisteSoegning, setArbejdslisteSoegning] = useState('');
  const [detaljeCache, setDetaljeCache] = useState<Map<string, KandidatDetalje>>(() => new Map());
  const [detaljeLoading, setDetaljeLoading] = useState<Set<string>>(() => new Set());
  const [detaljeFejl, setDetaljeFejl] = useState<Map<string, string>>(() => new Map());
  const detaljeCacheRef = useRef(new Map<string, KandidatDetalje>());
  const detaljePendingRef = useRef(new Map<string, Promise<KandidatDetalje>>());
  // K2 selektiv publicering (§7.20): aId'er markeret til "Publicér valgte" — kun bekræftede
  // matches, kun staged personer (allerede publicerede har ingen afkrydsning at sætte).
  const [valgteTilPublicering, setValgteTilPublicering] = useState<Set<string>>(new Set());

  useEffect(() => {
    let alive = true;
    setLoading(true); setFejl(null);
    Promise.all([
      fetchSources(), fetchMatchPersoner(), fetchIkkeSammeSomPar(), fetchSammeSomPar(),
      fetchFamilyGraph(),
    ])
      .then(async ([s, p, afv, lnk, fam]) => ({
        s, p, afv, lnk, fam, audit: await fetchMatchAudit(lnk, afv),
      }))
      .then(({ s, p, afv, lnk, fam, audit }) => {
        senesteDatasaet = { sources: s, personer: p, afviste: afv, linkede: lnk, familieGraf: fam, matchAudit: audit };
        if (!alive) return;
        setSources(s); setPersoner(p); setAfviste(afv); setLinkede(lnk); setFamilieGraf(fam); setMatchAudit(audit);
        setNyKildeId((prev) => prev ?? senesteKildeId(s));
      })
      .catch((e) => alive && setFejl(String(e?.message ?? e)))
      .finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [refresh]);

  const byId = useMemo(() => new Map(personer.map((p) => [String(p.id), p])), [personer]);
  const navnById = useMemo(
    () => new Map(personer.map((p) => [String(p.id), p.fuldtNavn ?? p.navn])),
    [personer],
  );

  const hentKandidatDetalje = useCallback((personId: string): Promise<KandidatDetalje> => {
    const cached = detaljeCacheRef.current.get(personId);
    if (cached) return Promise.resolve(cached);
    const pending = detaljePendingRef.current.get(personId);
    if (pending) return pending;

    setDetaljeLoading((prev) => new Set(prev).add(personId));
    setDetaljeFejl((prev) => {
      const next = new Map(prev); next.delete(personId); return next;
    });
    const promise = fetchKandidatDetalje(personId)
      .then((detalje) => {
        detaljeCacheRef.current.set(personId, detalje);
        setDetaljeCache(new Map(detaljeCacheRef.current));
        return detalje;
      })
      .catch((error) => {
        setDetaljeFejl((prev) => new Map(prev).set(personId, String(error?.message ?? error)));
        throw error;
      })
      .finally(() => {
        detaljePendingRef.current.delete(personId);
        setDetaljeLoading((prev) => {
          const next = new Set(prev); next.delete(personId); return next;
        });
      });
    detaljePendingRef.current.set(personId, promise);
    return promise;
  }, []);

  const toggleSammenligning = (aId: string, bId: string) => {
    const key = pairKey(aId, bId);
    if (aabentPar === key) {
      setAabentPar(null);
      return;
    }
    setAabentPar(key);
    void Promise.all([hentKandidatDetalje(aId), hentKandidatDetalje(bId)]).catch(() => undefined);
  };

  const kildeLabel = (sourceIds: number[]): string => {
    const labels = sourceIds.map((id) => {
      const source = sources.find((candidate) => candidate.id === id);
      return source?.udgave ?? source?.titel ?? `Kilde ${id}`;
    });
    return labels.length ? labels.join(' · ') : 'Ukendt kilde';
  };

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
  const { aabne, afklarede, formodetNye } = useMemo(() => {
    const arbejdspersoner = arbejdsliste?.personer ?? [];
    return {
      aabne: arbejdspersoner.filter((p) => p.status === 'aaben'),
      afklarede: arbejdspersoner.filter((p) => p.status === 'afklaret'),
      formodetNye: arbejdspersoner.filter((p) => p.status === 'formodet_ny'),
    };
  }, [arbejdsliste]);
  const filtreredeAabne = useMemo(() => {
    const needle = arbejdslisteSoegning.trim().toLocaleLowerCase('da-DK');
    if (!needle) return aabne;
    return aabne.filter((person) => {
      const a = byId.get(person.aId);
      return visning(a).toLocaleLowerCase('da-DK').includes(needle)
        || person.kandidater.some((kandidat) =>
          visning(byId.get(String(kandidat.bId))).toLocaleLowerCase('da-DK').includes(needle));
    });
  }, [aabne, arbejdslisteSoegning, byId]);
  const ubekraeftedeFoldHints = useMemo(() => {
    const hints = new Map<string, { folder: boolean; grund: string | null }>();
    for (const person of aabne) {
      for (const kandidat of person.kandidater) {
        if (kandidat.linket) continue;
        const bId = String(kandidat.bId);
        hints.set(
          pairKey(person.aId, bId),
          previewSammeSom(rawDb, existingEdges, { alias: person.aId, canonical: bId }),
        );
      }
    }
    return hints;
  }, [aabne, rawDb, existingEdges]);

  const run = useCallback(async (
    change: Change,
    key: string,
    onSuccess?: (result: Awaited<ReturnType<typeof submitChange>>) => void | Promise<void>,
  ) => {
    setBusy(key); setFejl(null);
    try {
      const result = await submitChange(change, { dryRun, role });
      if ('dryRun' in result && result.dryRun) {
        setDryRunPreview({ key, text: describeCall(result.call) });
      } else {
        setDryRunPreview((prev) => (prev?.key === key ? null : prev));
        await onSuccess?.(result);
      }
    } catch (e) {
      setFejl(oversaetFejl(String((e as { message?: string })?.message ?? e)));
    } finally { setBusy(null); }
  }, [role, dryRun]);

  const bekraeft = (aId: string, bId: string) => run(
    { art: 'sammeSom', subjektType: 'person', subjektId: aId, payload: { aliasId: aId, objektId: bId } },
    `s:${aId}:${bId}`,
    async (result) => {
      const relationId = String((result as { result?: unknown }).result ?? '');
      setLinkede((prev) => (prev.some((l) => l.aId === aId && l.bId === bId)
        ? prev
        : [...prev, { relationId, aId, bId }]));
      if (!relationId) return;
      try {
        const audit = await fetchMatchAudit([{ relationId, aId, bId }], []);
        setMatchAudit((prev) => [...prev.filter((p) => p.relationId !== relationId), ...audit]);
      } catch { /* audit display is not critical */ }
    },
  );

  const afvis = (aId: string, bId: string) => run(
    { art: 'ikkeSammeSom', subjektType: 'person', subjektId: aId, payload: { aId, bId } },
    `a:${aId}:${bId}`,
    async (result) => {
      const relationId = String((result as { result?: unknown }).result ?? '');
      setAfviste((prev) => (prev.some((x) => x.aId === aId && x.bId === bId)
        ? prev
        : [...prev, { relationId, aId, bId }]));
      if (!relationId) return;
      try {
        const audit = await fetchMatchAudit([], [{ relationId, aId, bId }]);
        setMatchAudit((prev) => [...prev.filter((p) => p.relationId !== relationId), ...audit]);
      } catch { /* audit display is not critical */ }
    },
  );

  const fortrydSammeSom = (relationId: string, aId: string) => run(
    { art: 'fjernSammeSom', subjektType: 'person', subjektId: aId, relationId },
    `f:${relationId}`,
    () => {
      setLinkede((prev) => prev.filter((l) => l.relationId !== relationId));
      setMatchAudit((prev) => prev.filter((p) => p.relationId !== relationId));
    },
  );

  const fortrydIkkeSammeSom = (relationId: string, aId: string) => run(
    { art: 'fjernIkkeSammeSom', subjektType: 'person', subjektId: aId, relationId },
    `fi:${relationId}`,
    () => {
      setAfviste((prev) => prev.filter((l) => l.relationId !== relationId));
      setMatchAudit((prev) => prev.filter((p) => p.relationId !== relationId));
    },
  );

  const markerNy = async (kand: Kandidat[]) => {
    const targets = kand.filter((k) => !k.afvist && !k.linket);
    if (!targets.length) return;
    if (targets.length > 1 && !window.confirm(`Afvis alle ${targets.length} kandidater?`)) return;
    for (const k of targets) await afvis(String(k.aId), String(k.bId));
  };

  const toggleValgtTilPublicering = (aId: string) => setValgteTilPublicering((prev) => {
    const next = new Set(prev);
    if (next.has(aId)) next.delete(aId); else next.add(aId);
    return next;
  });
  // Publicér KUN de valgte person-id'er (§7.20) — ikke hele kilden. Rydder valget efter
  // forsøget, uanset udfald; en fejl vises stadig via `fejl` (sat af run()).
  const publicerValgte = async () => {
    const ids = [...valgteTilPublicering];
    if (!ids.length) return;
    await run({ art: 'publicerPersoner', subjektType: 'person', subjektId: ids[0],
      payload: { personIds: ids } }, 'publicer', () => setRefresh((r) => r + 1));
    setValgteTilPublicering(new Set());
  };

  const publicerHeleUdgaven = () => {
    if (nyKildeId == null) return;
    const antalStaged = personer.filter((p) => p.sourceIds.includes(nyKildeId) && p.staged).length;
    if (!antalStaged) return;
    const kilde = sources.find((s) => s.id === nyKildeId);
    const kildeNavn = kilde?.udgave ?? kilde?.titel ?? `Kilde ${nyKildeId}`;
    if (!window.confirm(
      `Publicér HELE udgaven "${kildeNavn}" (${antalStaged} skjulte personer bliver offentlige)?\n\n`
      + 'Dette gør ALLE endnu skjulte personer fra denne udgave synlige på én gang — også dem der ikke er '
      + 'individuelt bekræftet eller afvist endnu. Brug kun når match-gennemgangen for hele udgaven er afsluttet.',
    )) return;
    run(
      { art: 'publicerUdgave', subjektType: 'source', subjektId: String(nyKildeId) },
      'publicer-udgave',
      () => setRefresh((r) => r + 1),
    );
  };

  // Fold-hint pr. par: for et allerede bekræftet link, slå op om DET par er en af de karantænerede
  // grupper (fra den ÉN kørsel over alle bekræftede kanter ovenfor); for et endnu ubekræftet par,
  // slå den memoiserede previewSammeSom-beregning op. RÅDGIVENDE (offentlig visning kan afvige
  // pga. RLS/completeness) — se sammeSomPreflight.ts-header.
  const foldHint = (aId: string, bId: string, linket: boolean): { folder: boolean; grund: string | null } => {
    if (linket) {
      const grund = karantaeneByPersonId.get(aId) ?? karantaeneByPersonId.get(bId) ?? null;
      return { folder: grund == null, grund };
    }
    return ubekraeftedeFoldHints.get(pairKey(aId, bId)) ?? { folder: false, grund: null };
  };

  if (loading && personer.length === 0) return (
    <div className="sammenlign" data-testid="sammenlign-skeleton" aria-busy="true" style={{ padding: '1rem', maxWidth: 900 }}>
      <div style={{ width: '13rem', height: '1.5rem', marginBottom: '1rem', borderRadius: 3, background: '#e7e2d9' }} />
      {[72, 91, 64, 83, 76, 68].map((width, index) => (
        <div key={width} style={{ width: `${width}%`, height: '2.4rem', marginBottom: '.45rem', borderRadius: 4, background: index % 2 ? '#f1eee8' : '#e7e2d9' }} />
      ))}
    </div>
  );

  const f = arbejdsliste?.fremdrift;

  return (
    <div className="sammenlign" style={{ padding: '1rem', maxWidth: 900 }}>
      <h2>
        Sammenlign udgaver
        {loading && personer.length > 0 && (
          <span style={{ marginLeft: '.45rem', color: '#6f675b', fontSize: '.65em', fontWeight: 400 }}>· opdaterer…</span>
        )}
      </h2>
      <label>
        Ny udgave:{' '}
        <select value={nyKildeId ?? ''} onChange={(e) => setNyKildeId(Number(e.target.value))}>
          {[...sources].sort((a, b) => (b.aar ?? 0) - (a.aar ?? 0)).map((s) => (
            <option key={s.id} value={s.id}>{s.udgave ?? s.titel ?? `Kilde ${s.id}`}{s.aar ? ` (${s.aar})` : ''}</option>
          ))}
        </select>
        {' '}mod resten af basen
      </label>
      {' '}
      <button type="button" onClick={() => setRefresh((r) => r + 1)} disabled={loading}>Genindlæs</button>

      {fejl && (
        <p role="alert" style={{ color: '#881A33' }}>
          Fejl: {fejl} <button type="button" onClick={() => setFejl(null)}>Luk</button>
        </p>
      )}

      {dryRunPreview && (
        <div role="status" style={{ padding: '.55rem .7rem', margin: '.5rem 0', borderRadius: 4,
          background: '#eef3f8', border: '1px solid rgba(47,99,140,.3)', color: '#2f4f6c' }}>
          <strong>Dry-run — intet er gemt.</strong> Dette ville blive sendt:
          <pre style={{ whiteSpace: 'pre-wrap', margin: '.3rem 0 0', fontSize: '.85em' }}>{dryRunPreview.text}</pre>
          <button type="button" onClick={() => setDryRunPreview(null)}>Luk</button>
        </div>
      )}

      {f && (
        <p style={{ fontSize: '.9em', color: '#6f675b' }}>
          {f.afklaret} af {f.total} afklaret · {f.staerke} stærke kandidater · {f.gennemse} til gennemsyn · {f.formodetNye} formodet nye
        </p>
      )}

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '.35rem', margin: '.75rem 0' }}>
        <button type="button" onClick={() => setAktivFane('arbejdsliste')}
          aria-current={aktivFane === 'arbejdsliste' ? 'true' : undefined}
          style={{ fontWeight: aktivFane === 'arbejdsliste' ? 700 : 400 }}>
          Arbejdsliste ({aabne.length})
        </button>
        <button type="button" onClick={() => setAktivFane('bekraeftede')}
          aria-current={aktivFane === 'bekraeftede' ? 'true' : undefined}
          style={{ fontWeight: aktivFane === 'bekraeftede' ? 700 : 400 }}>
          Bekræftede ({afklarede.length})
        </button>
        <button type="button" onClick={() => setAktivFane('karantaene')}
          aria-current={aktivFane === 'karantaene' ? 'true' : undefined}
          style={{ fontWeight: aktivFane === 'karantaene' ? 700 : 400 }}>
          Karantæne ({foldPreview.quarantined.length})
        </button>
        <button type="button" onClick={() => setAktivFane('historik')}
          aria-current={aktivFane === 'historik' ? 'true' : undefined}
          style={{ fontWeight: aktivFane === 'historik' ? 700 : 400 }}>
          Historik ({matchAudit.length})
        </button>
      </div>

      {aktivFane === 'arbejdsliste' && (
        <>
          <label>Søg på navn<br />
            <input value={arbejdslisteSoegning}
              onChange={(event) => setArbejdslisteSoegning(event.target.value)} type="search" />
          </label>
          <h3>Til gennemgang ({aabne.length})</h3>
          {aabne.length === 0 && !loading && (
            <p style={{ color: '#3d7a3d' }}>✓ Alle kandidater for denne udgave er afklaret.</p>
          )}
          {aabne.length > 0 && filtreredeAabne.length === 0 && (
            <p style={{ color: '#6f675b' }}>Ingen kandidater matcher søgningen.</p>
          )}
          {filtreredeAabne.map((person) => {
        const a = byId.get(person.aId);
        const aDetaljer = [
          foraeldreNavne(person.aId, familieGraf.parentChild, byId),
          formatBogReferencer(a),
        ].filter(Boolean);
        return (
          <div key={person.aId} style={{ border: '1px solid rgba(34,31,26,.1)', borderRadius: 6, padding: '.6rem .8rem', margin: '.5rem 0' }}>
            <strong>{visning(a)}</strong>
            <button style={{ marginLeft: '.8rem', fontSize: '.85em' }} disabled={!!busy}
              onClick={() => markerNy(person.kandidater)}>Markér som ny person</button>
            {aDetaljer.length > 0 && (
              <div style={{ fontSize: '.82em', color: '#6f675b', marginTop: '.15rem' }}>
                {aDetaljer.join(' · ')}
              </div>
            )}
            {person.kandidater.filter((k) => !k.afvist).map((k) => {
              const b = byId.get(String(k.bId));
              const bId = String(k.bId);
              const parNoegle = pairKey(person.aId, bId);
              const erAabent = aabentPar === parNoegle;
              const detaljeA = detaljeCache.get(person.aId);
              const detaljeB = detaljeCache.get(bId);
              const detaljerIndlaeses = detaljeLoading.has(person.aId) || detaljeLoading.has(bId);
              const detaljeError = detaljeFejl.get(person.aId) ?? detaljeFejl.get(bId) ?? null;
              const hint = foldHint(person.aId, bId, k.linket);
              const advice = hint.grund ? foldAdvice(hint.grund) : null;
              const bDetaljer = [
                foraeldreNavne(bId, familieGraf.parentChild, byId),
                formatBogReferencer(b),
              ].filter(Boolean);
              return (
                <div key={String(k.bId)} style={{ marginTop: '.4rem', paddingTop: '.4rem', borderTop: '1px dashed rgba(34,31,26,.1)' }}>
                  <span style={{ fontWeight: 600 }}>{k.tier === 'auto' ? '★ stærk' : 'gennemse'}</span>
                  {' '}<code>{(k.score ?? 0).toFixed(3)}</code> — {visning(b)}
                  <span style={{ fontSize: '.8em', color: '#6f675b', marginLeft: '.5rem' }}>
                    navn {k.nameSim.toFixed(2)} · fødsel {k.birthOverlap ? '✓' : '—'} · død {k.deathOverlap ? '✓' : '—'} · køn {k.sexEq ? '✓' : '✗'}
                  </span>
                  {bDetaljer.length > 0 && (
                    <div style={{ fontSize: '.82em', color: '#6f675b', marginTop: '.15rem' }}>
                      {bDetaljer.join(' · ')}
                    </div>
                  )}
                  <button type="button" style={{ marginTop: '.35rem', fontSize: '.85em' }}
                    onClick={() => toggleSammenligning(person.aId, bId)}>
                    {erAabent ? 'Luk sammenligning' : 'Sammenlign'}
                  </button>
                  <button type="button" style={{ marginTop: '.35rem', marginLeft: '.35rem', fontSize: '.85em' }}
                    disabled={!!k.linket || busy === `s:${person.aId}:${bId}`}
                    onClick={() => {
                      if (window.confirm('Bekræft ' + visning(a) + ' = ' + visning(b) + ' som samme person uden at se sammenligningen?')) {
                        bekraeft(person.aId, bId);
                      }
                    }}>
                    {busy === `s:${person.aId}:${bId}` ? 'Gemmer…' : '✓ Bekræft'}
                  </button>
                  {erAabent && (
                    detaljeError
                      ? <p style={{ color: '#881A33' }}>Kunne ikke hente kandidatdetaljer: {detaljeError}</p>
                      : detaljeA && detaljeB && a && b
                        ? <KandidatSammenligning
                            personA={a}
                            personB={b}
                            detaljeA={detaljeA}
                            detaljeB={detaljeB}
                            kildeA={kildeLabel(a.sourceIds)}
                            kildeB={kildeLabel(b.sourceIds)}
                            rolleA="alias"
                            rolleB="kanonisk"
                            navnById={navnById}
                            foldHint={hint}
                            foldAdvice={advice}
                            linket={k.linket}
                            busyAction={busy === `s:${person.aId}:${bId}`
                              ? 'bekraeft'
                              : busy === `a:${person.aId}:${bId}` ? 'afvis' : null}
                            onBekraeft={() => bekraeft(person.aId, bId)}
                            onAfvis={() => afvis(person.aId, bId)}
                          />
                        : <p style={{ color: '#6f675b' }}>
                            {detaljerIndlaeses ? 'Indlæser kandidatdetaljer…' : 'Kandidatdetaljer mangler.'}
                          </p>
                  )}
                </div>
              );
            })}
          </div>
        );
          })}
        </>
      )}

      {/* Karantæne-oversigt (§7.18): bekræftede samme_som-links der endnu ikke folder offentligt
          — typisk fordi forældrene i de to udgaver ikke selv er matchet endnu. Rådgivende. */}
      {aktivFane === 'karantaene' && (
        <section style={{ marginTop: '.75rem', border: '1px solid rgba(136,26,51,.25)', borderRadius: 6, padding: '.5rem .8rem', background: '#fdf3f5' }}>
          <h3 style={{ color: '#881A33' }}>
            {foldPreview.quarantined.length} bekræftet link{foldPreview.quarantined.length === 1 ? '' : 's'} folder endnu ikke offentligt
          </h3>
          {foldPreview.quarantined.length === 0
            ? <p style={{ color: '#6f675b' }}>Ingen karantænerede links.</p>
            : (
              <ul style={{ fontSize: '.85em', marginTop: '.4rem', marginBottom: 0 }}>
                {foldPreview.quarantined.map((q, i) => {
                  const advice = foldAdvice(q.reason);
                  return (
                    <li key={i}>
                      {q.members.map((id) => visning(byId.get(id))).join(' = ')} — <em>{q.reason}</em>
                      {advice && <div style={{ color: '#6f675b' }}>{advice}</div>}
                    </li>
                  );
                })}
              </ul>
            )}
        </section>
      )}

      {/* Bekræftede matches (§7.20): kun HER kan en staged 1939-person vælges til selektiv
          publicering — allerede publicerede vises med et badge i stedet for afkrydsning.
          Adskilt fra `aabne`, fordi buildArbejdsliste flytter en person hertil i samme
          øjeblik ÉT af dens kandidater bekræftes (uanset øvrige kandidaters status). */}
      {aktivFane === 'bekraeftede' && (
        <section style={{ marginTop: '.75rem' }}>
          <h3>
            {afklarede.length} bekræftet{afklarede.length === 1 ? '' : 'e'} match{afklarede.length === 1 ? '' : 'es'}
          </h3>
          {afklarede.length === 0
            ? <p style={{ color: '#6f675b' }}>Ingen bekræftede matches endnu.</p>
            : (
              <>
                <div style={{ margin: '.6rem 0', display: 'flex', alignItems: 'baseline', gap: '.6rem' }}>
                  <button type="button" disabled={!!busy || valgteTilPublicering.size === 0} onClick={publicerValgte}>
                    {busy === 'publicer' ? 'Gemmer…' : `Publicér valgte (${valgteTilPublicering.size})`}
                  </button>
                  <span style={{ fontSize: '.8em', color: '#6f675b' }}>
                    Gør kun de markerede personer synlige for besøgende — resten forbliver skjult, til de er klar.
                  </span>
                  <button type="button" disabled={!!busy || nyKildeId == null} onClick={publicerHeleUdgaven}>
                    {busy === 'publicer-udgave' ? 'Gemmer…' : 'Publicér hele udgaven'}
                  </button>
                  <span style={{ fontSize: '.8em', color: '#6f675b' }}>
                    Gør ALLE resterende skjulte personer fra den valgte udgave offentlige — brug når hele match-gennemgangen er færdig.
                  </span>
                </div>
                <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
                  {afklarede.map((person) => {
                    const a = byId.get(person.aId);
                    const staged = a?.staged ?? false;
                    const linket = person.kandidater.find((k) => k.linket);
                    const b = linket ? byId.get(String(linket.bId)) : undefined;
                    const hint = linket ? foldHint(person.aId, String(linket.bId), true) : { folder: false, grund: null };
                    const advice = hint.grund ? foldAdvice(hint.grund) : null;
                    return (
                      <li key={person.aId} style={{ padding: '.4rem 0', borderBottom: '1px dashed rgba(34,31,26,.08)' }}>
                        {staged ? (
                          <label style={{ cursor: 'pointer' }}>
                            <input type="checkbox" checked={valgteTilPublicering.has(person.aId)}
                              onChange={() => toggleValgtTilPublicering(person.aId)} style={{ marginRight: '.4rem' }} />
                            {visning(a)} = {visning(b)}
                          </label>
                        ) : (
                          <span>{visning(a)} = {visning(b)} <span style={{ fontSize: '.8em', color: '#3d7a3d' }}>✓ publiceret</span></span>
                        )}
                        <div style={{ fontSize: '.8em', marginTop: '.15rem', color: hint.folder ? '#3d7a3d' : '#881A33' }}>
                          {hint.folder ? '✓ foldes offentligt til én person' : `foldes IKKE endnu offentligt: ${hint.grund}`}
                          {!hint.folder && advice && <div style={{ color: '#6f675b' }}>{advice}</div>}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </>
            )}
        </section>
      )}

      {aktivFane === 'historik' && (
        <MatchOversigt
          audit={matchAudit}
          personer={personer}
          sources={sources}
          karantaeneByPersonId={karantaeneByPersonId}
          detaljeCache={detaljeCache}
          busy={!!busy}
          hentKandidatDetalje={hentKandidatDetalje}
          onFortryd={fortrydSammeSom}
          onFortrydAfvisning={fortrydIkkeSammeSom}
        />
      )}

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
