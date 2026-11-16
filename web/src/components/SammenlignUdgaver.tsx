// "Sammenlign udgaver" — redaktør-flade til tværudgave-identitet (Problem 3 §5).
// Kildevalg → matcher-kørsel (memoiseret, @daa/core) → arbejdsliste → Bekræft/Afvis via
// submitChange (samme dry-run/LIVE-flow som resten af redaktionen). Retning (§5.4):
// eksisterende base = kanonisk (objekt/sink), ny udgaves person = alias (subjekt).
import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  buildMatchFrame, collapseSameAs, previewSammeSom, parseYear, defaultCfg,
  udledKilderForAegtefaeller,
  type MatchFrame, type RedMatchPerson, type ScoredPair, type Db, type SameAsEdge, type Union, type ParentChild,
} from '@daa/core';
import {
  fetchSources, fetchMatchPersoner, fetchIkkeSammeSomPar, fetchSammeSomPar, fetchFamilyGraph,
  fetchKandidatDetalje, fetchMatchAudit,
  type KandidatDetalje, type MatchAuditPost, type MatchRelationPar, type SourceRow,
} from '../data/redaktionRead';
import { describeCall, oversaetFejl, submitChange, type Change } from '../data/redaktionWrite';
import {
  beregnKandidatPar, buildArbejdsliste, byggLinketTil, byggMatchetMed, matcherSoegning, pairKey, sammeSomRetning, scorePersonPar,
  type ArbejdslistePerson, type Kandidat,
} from '../data/sammenlign';
import { KandidatSammenligning } from './KandidatSammenligning';
import {
  MatchOversigt, foraeldreNavne, formatBogReferencer, formatPersonNavn,
} from './MatchOversigt';
import { T } from '../theme';

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
  const [aktivFane, setAktivFane] = useState<'arbejdsliste' | 'bekraeftede' | 'nye' | 'karantaene' | 'historik'>('arbejdsliste');
  const [arbejdslisteSoegning, setArbejdslisteSoegning] = useState('');
  // Personer hvis svage forslag (under tærsklen) er foldet ud.
  const [visSvage, setVisSvage] = useState<Set<string>>(() => new Set());
  // »Find modpart«: hvilken person søgningen er åben for, og søgeteksten.
  const [modpartFor, setModpartFor] = useState<string | null>(null);
  const [modpartSoegning, setModpartSoegning] = useState('');
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

  // Ægtefæller uden eget bog-nummer arver udgaven fra deres partner (entydigt, ellers urørt).
  // Uden det havner de i B-siden uanset udgave — så en 1939-ægtefælle kunne foreslås som match
  // for en 1939-person, og forældrepar kunne aldrig matches færdigt (→ "konkurrerende forældre").
  const personerMedKilde = useMemo(
    () => udledKilderForAegtefaeller(personer, familieGraf.unions),
    [personer, familieGraf.unions],
  );

  const matchCfg = useMemo(() => ({ ...defaultCfg(), evidensNormaliseret: true }), []);
  // Udgavens årstal pr. person (den nyeste, hvis personen står i flere) — afgør retningen af nye
  // links: den ældre udgaves person foldes ind, uanset hvilken udgave der er valgt.
  const udgaveAar = useMemo(() => {
    const aarByKilde = new Map(sources.map((s) => [s.id, s.aar ?? null]));
    const m = new Map<string, number | null>();
    for (const p of personerMedKilde) {
      const aar = p.sourceIds.map((id) => aarByKilde.get(id)).filter((x): x is number => x != null);
      m.set(String(p.id), aar.length ? Math.max(...aar) : null);
    }
    return (id: string) => m.get(id) ?? null;
  }, [sources, personerMedKilde]);
  const linkedeKeys = useMemo(() => new Set(linkede.map((x) => pairKey(x.aId, x.bId))), [linkede]);
  const { matchetMed, linketTil } = useMemo(() => {
    if (nyKildeId == null) return { matchetMed: new Map<string, string>(), linketTil: new Map<string, string>() };
    const aSide = new Set(personerMedKilde.filter((p) => p.sourceIds.includes(nyKildeId)).map((p) => String(p.id)));
    return { matchetMed: byggMatchetMed(linkede, aSide), linketTil: byggLinketTil(linkede, aSide) };
  }, [personerMedKilde, nyKildeId, linkede]);

  const arbejdsliste = useMemo(() => {
    if (nyKildeId == null) return null;
    const framesA: MatchFrame[] = [], framesB: MatchFrame[] = [], aIds: string[] = [];
    for (const p of personerMedKilde) {
      // Linjer uden modpart i den anden udgave holdes helt ude af matchningen — de kan
      // hverken være arbejdsemne eller kandidat. Ellers ville fx DAA 1939s fyenske Linje
      // blive foreslået som match for 2018-20-personer, selvom 2018-20 bevidst udelod den.
      if (p.udenforMatchning) continue;
      const f = buildMatchFrame(p);
      if (p.sourceIds.includes(nyKildeId)) { framesA.push(f); aIds.push(String(p.id)); }
      else framesB.push(f);
    }
    // Evidens-normaliseret score: vægt kun de signaler der faktisk kunne vurderes.
    // Uden den har en person uden årstal et loft på wName + wSex = præcis
    // reviewCutoff — bogens ægtefæller kunne derfor ikke bestå, uanset navnet.
    // Målt mod prod: personer med mindst ét forslag går 442 -> 815 af 835.
    // assignTiers kapper navn-alene-match til "gennemsyn" (måling: 152 -> 0 par
    // markeret stærke uden ét eneste årstal).
    const afvisteKeys = new Set(afviste.map((x) => pairKey(x.aId, x.bId)));
    // Afviste par tages ud før 1:1-tildelingen, så de ikke blokerer de næstbedste forslag.
    const pairs = beregnKandidatPar(framesA, framesB, matchCfg, afvisteKeys);
    return buildArbejdsliste(
      pairs, aIds, afvisteKeys, linkedeKeys,
      { reviewCutoff: matchCfg.reviewCutoff, matchetMed, linketTil },
    );
  }, [personerMedKilde, nyKildeId, afviste, linkedeKeys, matchetMed, linketTil, matchCfg]);

  // »Find modpart«: hele den anden side (alle uden for den valgte udgave), filtreret på søgeteksten
  // og rangeret med samme score som arbejdslisten. Ingen blocking, intet årsvindue, ingen tærskel —
  // det er netop de par, matcheren ikke stiller op, redaktøren skal kunne finde.
  const MAKS_MODPARTER = 25;
  const modpartResultat = useMemo(() => {
    const a = modpartFor != null ? byId.get(modpartFor) : undefined;
    if (!a || nyKildeId == null || !modpartSoegning.trim()) return { hits: [], total: 0 };
    const fa = buildMatchFrame(a);
    const alle = personerMedKilde
      .filter((p) => p.id !== a.id && !p.sourceIds.includes(nyKildeId) && matcherSoegning(modpartSoegning, p))
      .map((p) => ({ p, par: scorePersonPar(fa, buildMatchFrame(p), matchCfg) }))
      .sort((x, y) => (y.par.score ?? 0) - (x.par.score ?? 0));
    return { hits: alle.slice(0, MAKS_MODPARTER), total: alle.length };
  }, [modpartFor, modpartSoegning, byId, personerMedKilde, nyKildeId, matchCfg]);
  const { aabne, afklarede, nye, formodetNye } = useMemo(() => {
    const arbejdspersoner = arbejdsliste?.personer ?? [];
    return {
      aabne: arbejdspersoner.filter((p) => p.status === 'aaben'),
      afklarede: arbejdspersoner.filter((p) => p.status === 'afklaret'),
      nye: arbejdspersoner.filter((p) => p.status === 'ny'),
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

  // Bøttet child->[ParentChild] én gang, så foraeldreNavne() slår O(1) op i stedet for
  // at scanne HELE familieGraf.parentChild (~1500-2000 kanter) for hver kandidat-række.
  // Uden dette kører scanningen 2x pr. synlig række (A-side + B-side) på HVERT klik —
  // ethvert state-skift (aabentPar, busy, søgning) re-kører render-funktionen for
  // samtlige rækker i "aabne", og efter evidensNormaliseret-ændringen (review 304->3229
  // par) blev det tungt nok til at hænge synligt. Målt: ~1800 kanter × 2 kald × op til
  // hundredvis af synlige rækker = millioner af array-operationer pr. klik.
  const parentChildByChild = useMemo(() => {
    const m = new Map<string, ParentChild[]>();
    for (const pc of familieGraf.parentChild) {
      const arr = m.get(pc.child);
      if (arr) arr.push(pc); else m.set(pc.child, [pc]);
    }
    return m;
  }, [familieGraf.parentChild]);
  const foraeldreEdgesFor = useCallback(
    (personId: string) => parentChildByChild.get(personId) ?? [],
    [parentChildByChild],
  );

  const medSvage = useMemo(
    () => formodetNye.filter((p) => p.svageKandidater.some((k) => !k.afvist)).length,
    [formodetNye],
  );

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

  const bekraeft = (aId: string, bId: string) => {
    const { aliasId, objektId } = sammeSomRetning(aId, bId, udgaveAar);
    return run(
      { art: 'sammeSom', subjektType: 'person', subjektId: aliasId, payload: { aliasId, objektId } },
      `s:${aId}:${bId}`,
      async (result) => {
        const relationId = String((result as { result?: unknown }).result ?? '');
        setLinkede((prev) => (prev.some((l) => l.aId === aliasId && l.bId === objektId)
          ? prev
          : [...prev, { relationId, aId: aliasId, bId: objektId }]));
        if (!relationId) return;
        try {
          const audit = await fetchMatchAudit([{ relationId, aId: aliasId, bId: objektId }], []);
          setMatchAudit((prev) => [...prev.filter((p) => p.relationId !== relationId), ...audit]);
        } catch { /* audit display is not critical */ }
      },
    );
  };

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
  // kør previewSammeSom — dovent, kun for par der faktisk vises (åbnet sammenligning), og cachet
  // pr. retning indtil datasættet ændres. Før blev den kørt for ALLE åbne kandidater ved hver
  // ændring. RÅDGIVENDE (offentlig visning kan afvige pga. RLS/completeness) — se
  // sammeSomPreflight.ts-header.
  const foldPreviewCache = useMemo(
    () => new Map<string, { folder: boolean; grund: string | null }>(),
    [rawDb, existingEdges, udgaveAar],
  );
  const foldHint = (aId: string, bId: string, linket: boolean): { folder: boolean; grund: string | null } => {
    if (linket) {
      const grund = karantaeneByPersonId.get(aId) ?? karantaeneByPersonId.get(bId) ?? null;
      return { folder: grund == null, grund };
    }
    const noegle = `${aId}>${bId}`;
    let hint = foldPreviewCache.get(noegle);
    if (!hint) {
      // Samme retning som »Bekræft« vil sende — ellers forudsiger hintet en anden foldning.
      const { aliasId, objektId } = sammeSomRetning(aId, bId, udgaveAar);
      hint = previewSammeSom(rawDb, existingEdges, { alias: aliasId, canonical: objektId });
      foldPreviewCache.set(noegle, hint);
    }
    return hint;
  };

  // Én kandidatrække: navn, signaler, detaljer, Sammenlign/Bekræft og (når åben) sammenligningen.
  // Bruges af arbejdslisten, de svage forslag og »Find modpart«.
  const renderPar = (aId: string, bId: string, info: {
    tierLabel: string;
    signaler: Pick<ScoredPair, 'score' | 'nameSim' | 'birthOverlap' | 'deathOverlap' | 'sexEq'>;
    matchetMed?: string | null;
    linket?: boolean;
  }) => {
    const a = byId.get(aId);
    const b = byId.get(bId);
    const k = info.signaler;
    const linket = !!info.linket;
    const erAabent = aabentPar === pairKey(aId, bId);
    const detaljeA = detaljeCache.get(aId);
    const detaljeB = detaljeCache.get(bId);
    const detaljerIndlaeses = detaljeLoading.has(aId) || detaljeLoading.has(bId);
    const detaljeError = detaljeFejl.get(aId) ?? detaljeFejl.get(bId) ?? null;
    // Fold-preview kører hele collapseSameAs, så den beregnes kun for det åbne par.
    const hint = erAabent ? foldHint(aId, bId, linket) : null;
    const advice = hint?.grund ? foldAdvice(hint.grund) : null;
    const bDetaljer = [
      foraeldreNavne(bId, foraeldreEdgesFor(bId), byId),
      formatBogReferencer(b),
    ].filter(Boolean);
    return (
      <div key={bId} style={{ marginTop: '.4rem', paddingTop: '.4rem', borderTop: `1px dashed ${T.line}` }}>
        <span style={{ fontWeight: 600 }}>{info.tierLabel}</span>
        {' '}<code>{(k.score ?? 0).toFixed(3)}</code> — {visning(b)}
        <span style={{ fontSize: '.8em', color: T.inkMuted, marginLeft: '.5rem' }}>
          navn {k.nameSim.toFixed(2)} · fødsel {k.birthOverlap ? '✓' : '—'} · død {k.deathOverlap ? '✓' : '—'} · køn {k.sexEq ? '✓' : '✗'}
        </span>
        {info.matchetMed && (
          <div style={{ fontSize: '.8em', color: T.bordeaux, marginTop: '.15rem' }}>
            Allerede matchet med {visning(byId.get(info.matchetMed))}
          </div>
        )}
        {bDetaljer.length > 0 && (
          <div style={{ fontSize: '.82em', color: T.inkMuted, marginTop: '.15rem' }}>
            {bDetaljer.join(' · ')}
          </div>
        )}
        <button type="button" style={{ marginTop: '.35rem', fontSize: '.85em' }}
          onClick={() => toggleSammenligning(aId, bId)}>
          {erAabent ? 'Luk sammenligning' : 'Sammenlign'}
        </button>
        <button type="button" style={{ marginTop: '.35rem', marginLeft: '.35rem', fontSize: '.85em' }}
          disabled={linket || busy === `s:${aId}:${bId}`}
          onClick={() => {
            if (window.confirm('Bekræft ' + visning(a) + ' = ' + visning(b) + ' som samme person uden at se sammenligningen?')) {
              bekraeft(aId, bId);
            }
          }}>
          {busy === `s:${aId}:${bId}` ? 'Gemmer…' : '✓ Bekræft'}
        </button>
        {erAabent && hint && (
          detaljeError
            ? <p style={{ color: T.bordeaux }}>Kunne ikke hente kandidatdetaljer: {detaljeError}</p>
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
                  linket={linket}
                  busyAction={busy === `s:${aId}:${bId}`
                    ? 'bekraeft'
                    : busy === `a:${aId}:${bId}` ? 'afvis' : null}
                  onBekraeft={() => bekraeft(aId, bId)}
                  onAfvis={() => afvis(aId, bId)}
                />
              : <p style={{ color: T.inkMuted }}>
                  {detaljerIndlaeses ? 'Indlæser kandidatdetaljer…' : 'Kandidatdetaljer mangler.'}
                </p>
        )}
      </div>
    );
  };

  // Svage forslag (under tærsklen) for en person, foldet ind som standard. Matcheren pålægger dem
  // ikke som arbejde, men det rigtige match ligger ofte her, når navn eller årstal afviger.
  const renderSvage = (person: ArbejdslistePerson) => {
    const svage = person.svageKandidater.filter((k) => !k.afvist);
    if (!svage.length) return null;
    const vis = visSvage.has(person.aId);
    return (
      <div style={{ marginTop: '.4rem' }}>
        <button type="button" style={{ fontSize: '.85em' }} aria-expanded={vis}
          onClick={() => setVisSvage((prev) => {
            const next = new Set(prev);
            if (next.has(person.aId)) next.delete(person.aId); else next.add(person.aId);
            return next;
          })}>
          {vis ? 'Skjul svage forslag' : `Vis ${svage.length} svag${svage.length === 1 ? 't' : 'e'} forslag`}
        </button>
        {vis && svage.map((k) => renderPar(person.aId, String(k.bId), {
          tierLabel: 'svag', signaler: k, matchetMed: k.matchetMed, linket: k.linket,
        }))}
      </div>
    );
  };

  const renderFindModpart = (aId: string) => {
    const aaben = modpartFor === aId;
    return (
      <div style={{ marginTop: '.4rem' }}>
        <button type="button" style={{ fontSize: '.85em' }} aria-expanded={aaben}
          onClick={() => { setModpartFor(aaben ? null : aId); setModpartSoegning(''); }}>
          {aaben ? 'Luk søgning' : 'Find modpart'}
        </button>
        {aaben && (
          <div style={{ marginTop: '.4rem', padding: '.4rem .6rem', background: T.surfaceSunken, borderRadius: 4 }}>
            <input type="search" aria-label="Søg modpart" autoFocus value={modpartSoegning}
              placeholder="Navn, årstal eller bognr., fx »Frederik 1741«"
              onChange={(e) => setModpartSoegning(e.target.value)} style={{ width: '100%', maxWidth: '28rem' }} />
            <div style={{ fontSize: '.8em', color: T.inkMuted, marginTop: '.25rem' }}>
              Søger i alle personer uden for den valgte udgave. Årstal passer på fødsel eller død ±2 år.
            </div>
            {modpartSoegning.trim() && modpartResultat.total === 0 && (
              <p style={{ color: T.inkMuted, margin: '.4rem 0 0' }}>Ingen personer matcher søgningen.</p>
            )}
            {modpartResultat.total > modpartResultat.hits.length && (
              <p style={{ fontSize: '.8em', color: T.inkMuted, margin: '.4rem 0 0' }}>
                Viser de {modpartResultat.hits.length} bedste af {modpartResultat.total} — skriv mere for at indsnævre.
              </p>
            )}
            {modpartResultat.hits.map(({ p, par }) => renderPar(aId, p.id, {
              tierLabel: 'søgning', signaler: par,
              matchetMed: matchetMed.get(p.id) !== aId ? matchetMed.get(p.id) ?? null : null,
              linket: linkedeKeys.has(pairKey(aId, p.id)),
            }))}
          </div>
        )}
      </div>
    );
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
          <span style={{ marginLeft: '.45rem', color: T.inkMuted, fontSize: '.65em', fontWeight: 400 }}>· opdaterer…</span>
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
        <p role="alert" style={{ color: T.bordeaux }}>
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
        <p style={{ fontSize: '.9em', color: T.inkMuted }}>
          {f.afklaret + f.nye} af {f.total} afklaret ({f.afklaret} matchet · {f.nye} nye) · {f.staerke} stærke kandidater · {f.gennemse} til gennemsyn · {f.formodetNye} formodet nye
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
        <button type="button" onClick={() => setAktivFane('nye')}
          aria-current={aktivFane === 'nye' ? 'true' : undefined}
          style={{ fontWeight: aktivFane === 'nye' ? 700 : 400 }}>
          Nye ({nye.length})
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
            <p style={{ color: T.inkMuted }}>Ingen kandidater matcher søgningen.</p>
          )}
          {filtreredeAabne.map((person) => {
        const a = byId.get(person.aId);
        const aDetaljer = [
          foraeldreNavne(person.aId, foraeldreEdgesFor(person.aId), byId),
          formatBogReferencer(a),
        ].filter(Boolean);
        return (
          <div key={person.aId} style={{ border: `1px solid ${T.line}`, borderRadius: 6, padding: '.6rem .8rem', margin: '.5rem 0' }}>
            <strong>{visning(a)}</strong>
            <button style={{ marginLeft: '.8rem', fontSize: '.85em' }} disabled={!!busy}
              onClick={() => markerNy(person.kandidater)}>Markér som ny person</button>
            {aDetaljer.length > 0 && (
              <div style={{ fontSize: '.82em', color: T.inkMuted, marginTop: '.15rem' }}>
                {aDetaljer.join(' · ')}
              </div>
            )}
            {person.kandidater.filter((k) => !k.afvist).map((k) => renderPar(person.aId, String(k.bId), {
              tierLabel: k.tier === 'auto' ? '★ stærk' : 'gennemse', signaler: k,
              matchetMed: k.matchetMed, linket: k.linket,
            }))}
            {renderSvage(person)}
            {renderFindModpart(person.aId)}
          </div>
        );
          })}
        </>
      )}

      {/* Karantæne-oversigt (§7.18): bekræftede samme_som-links der endnu ikke folder offentligt
          — typisk fordi forældrene i de to udgaver ikke selv er matchet endnu. Rådgivende. */}
      {aktivFane === 'karantaene' && (
        <section style={{ marginTop: '.75rem', border: '1px solid rgba(136,26,51,.25)', borderRadius: 6, padding: '.5rem .8rem', background: '#fdf3f5' }}>
          <h3 style={{ color: T.bordeaux }}>
            {foldPreview.quarantined.length} bekræftet link{foldPreview.quarantined.length === 1 ? '' : 's'} folder endnu ikke offentligt
          </h3>
          {foldPreview.quarantined.length === 0
            ? <p style={{ color: T.inkMuted }}>Ingen karantænerede links.</p>
            : (
              <ul style={{ fontSize: '.85em', marginTop: '.4rem', marginBottom: 0 }}>
                {foldPreview.quarantined.map((q, i) => {
                  const advice = foldAdvice(q.reason);
                  return (
                    <li key={i}>
                      {q.members.map((id) => visning(byId.get(id))).join(' = ')} — <em>{q.reason}</em>
                      {advice && <div style={{ color: T.inkMuted }}>{advice}</div>}
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
          øjeblik den har et samme_som-link til den anden side — uanset om linket kom fra et
          forslag, »Find modpart« eller persondetaljen (uanset øvrige kandidaters status). */}
      {aktivFane === 'bekraeftede' && (
        <section style={{ marginTop: '.75rem' }}>
          <h3>
            {afklarede.length} bekræftet{afklarede.length === 1 ? '' : 'e'} match{afklarede.length === 1 ? '' : 'es'}
          </h3>
          {afklarede.length === 0
            ? <p style={{ color: T.inkMuted }}>Ingen bekræftede matches endnu.</p>
            : (
              <>
                <div style={{ margin: '.6rem 0', display: 'flex', alignItems: 'baseline', gap: '.6rem' }}>
                  <button type="button" disabled={!!busy || valgteTilPublicering.size === 0} onClick={publicerValgte}>
                    {busy === 'publicer' ? 'Gemmer…' : `Publicér valgte (${valgteTilPublicering.size})`}
                  </button>
                  <span style={{ fontSize: '.8em', color: T.inkMuted }}>
                    Gør kun de markerede personer synlige for besøgende — resten forbliver skjult, til de er klar.
                  </span>
                  <button type="button" disabled={!!busy || nyKildeId == null} onClick={publicerHeleUdgaven}>
                    {busy === 'publicer-udgave' ? 'Gemmer…' : 'Publicér hele udgaven'}
                  </button>
                  <span style={{ fontSize: '.8em', color: T.inkMuted }}>
                    Gør ALLE resterende skjulte personer fra den valgte udgave offentlige — brug når hele match-gennemgangen er færdig.
                  </span>
                </div>
                <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
                  {afklarede.map((person) => {
                    const a = byId.get(person.aId);
                    const staged = a?.staged ?? false;
                    const bId = person.linketTil;
                    const b = bId ? byId.get(bId) : undefined;
                    const hint = bId ? foldHint(person.aId, bId, true) : { folder: false, grund: null };
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
                        <div style={{ fontSize: '.8em', marginTop: '.15rem', color: hint.folder ? '#3d7a3d' : T.bordeaux }}>
                          {hint.folder ? '✓ foldes offentligt til én person' : `foldes IKKE endnu offentligt: ${hint.grund}`}
                          {!hint.folder && advice && <div style={{ color: T.inkMuted }}>{advice}</div>}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </>
            )}
        </section>
      )}

      {/* Personer hvis kandidater alle er afvist (»Markér som ny person«). Før stod de under
          Bekræftede som "X = (ukendt)". Staged personer kan publiceres herfra som under Bekræftede. */}
      {aktivFane === 'nye' && (
        <section style={{ marginTop: '.75rem' }}>
          <h3>{nye.length} markeret som ny{nye.length === 1 ? '' : 'e'} person{nye.length === 1 ? '' : 'er'}</h3>
          <p style={{ fontSize: '.85em', color: T.inkMuted }}>
            Alle forslag over tærsklen er afvist. Fortryd en afvisning under Historik.
          </p>
          {nye.length === 0
            ? <p style={{ color: T.inkMuted }}>Ingen personer er markeret som nye.</p>
            : (
              <>
                <div style={{ margin: '.6rem 0' }}>
                  <button type="button" disabled={!!busy || valgteTilPublicering.size === 0} onClick={publicerValgte}>
                    {busy === 'publicer' ? 'Gemmer…' : `Publicér valgte (${valgteTilPublicering.size})`}
                  </button>
                </div>
                <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
                  {nye.map((person) => {
                    const a = byId.get(person.aId);
                    const detaljer = [
                      foraeldreNavne(person.aId, foraeldreEdgesFor(person.aId), byId),
                      formatBogReferencer(a),
                    ].filter(Boolean);
                    return (
                      <li key={person.aId} style={{ padding: '.4rem 0', borderBottom: '1px dashed rgba(34,31,26,.08)' }}>
                        {a?.staged ? (
                          <label style={{ cursor: 'pointer' }}>
                            <input type="checkbox" checked={valgteTilPublicering.has(person.aId)}
                              onChange={() => toggleValgtTilPublicering(person.aId)} style={{ marginRight: '.4rem' }} />
                            {visning(a)}
                          </label>
                        ) : (
                          <span>{visning(a)} <span style={{ fontSize: '.8em', color: '#3d7a3d' }}>✓ publiceret</span></span>
                        )}
                        {detaljer.length > 0 && (
                          <div style={{ fontSize: '.8em', color: T.inkMuted, marginTop: '.15rem' }}>{detaljer.join(' · ')}</div>
                        )}
                        {renderSvage(person)}
                        {renderFindModpart(person.aId)}
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
          <summary>
            {formodetNye.length} uden kandidat over tærsklen
            {medSvage > 0 && ` — ${medSvage} har et forslag under tærsklen`}
          </summary>
          {medSvage > 0 && (
            <p style={{ fontSize: '.85em', color: T.inkMuted, margin: '.4rem 0' }}>
              Scoren vægter kun det der kunne vurderes, så et manglende årstal tæller
              hverken for eller imod. Disse forslag nåede alligevel ikke tærsklen — typisk
              fordi navnene afviger, eller fordi et kendt årstal ikke passer. Bedøm dem selv.
            </p>
          )}
          <ul style={{ fontSize: '.9em', color: T.inkMuted }}>
            {formodetNye.map((p) => {
              const svage = p.svageKandidater.filter((k) => !k.afvist).slice(0, 5);
              return (
                <li key={p.aId} style={{ marginBottom: svage.length ? '.5rem' : 0 }}>
                  {visning(byId.get(p.aId))}
                  {svage.map((k) => renderPar(p.aId, String(k.bId), {
                    tierLabel: 'svag', signaler: k, matchetMed: k.matchetMed, linket: k.linket,
                  }))}
                  {renderFindModpart(p.aId)}
                </li>
              );
            })}
          </ul>
        </details>
      )}
    </div>
  );
}
