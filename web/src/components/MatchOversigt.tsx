import { useMemo, useState } from 'react';
import {
  buildMatchFrame, defaultCfg, jaroWinkler, overlapEvidence, scorePair,
  type ParentChild, type RedMatchPerson,
} from '@daa/core';
import {
  type KandidatDetalje, type MatchAuditPost, type SourceRow,
} from '../data/redaktionRead';
import { KandidatSammenligning } from './KandidatSammenligning';

export function formatPersonNavn(p?: RedMatchPerson): string {
  if (!p) return '(ukendt)';
  const fy = p.foedsel?.date_min?.slice(0, 4) ?? '';
  const dy = p.doed?.date_min?.slice(0, 4) ?? '';
  const span = fy || dy ? ` (${fy}–${dy})` : '';
  const navn = p.fuldtNavn ?? p.navn;
  const navnOgTitel = p.titel ? `${navn} · ${p.titel}` : navn;
  return `${navnOgTitel}${span}`;
}

export function foraeldreNavne(
  personId: string,
  parentChild: ParentChild[],
  byId: Map<string, RedMatchPerson>,
): string {
  const parentIds = [...new Set(
    parentChild.filter((edge) => edge.child === personId).map((edge) => edge.parent),
  )];
  const navne = parentIds.map((id) => {
    const parent = byId.get(id);
    return parent?.fuldtNavn ?? parent?.navn;
  }).filter((navn): navn is string => Boolean(navn));
  return navne.length ? `f. af ${navne.join(' & ')}` : '';
}

export function formatBogReferencer(p?: RedMatchPerson): string {
  if (!p) return '';
  return p.bogReferencer.map((ref) => {
    const bogNr = ref.linje && ref.nr != null
      ? `${ref.linje}-${ref.nr}`
      : ref.linje ?? (ref.nr != null ? `nr. ${ref.nr}` : '');
    return [bogNr, ref.grenNavn].filter(Boolean).join(', ');
  }).filter(Boolean).join(' · ');
}

export function rekomputerMatchScore(a: RedMatchPerson, b: RedMatchPerson): number {
  const fa = buildMatchFrame(a);
  const fb = buildMatchFrame(b);
  const nameSim = jaroWinkler(fa.nameKey, fb.nameKey);
  const birthOverlap = overlapEvidence(fa.birthMin, fa.birthMax, fb.birthMin, fb.birthMax);
  const deathOverlap = overlapEvidence(fa.deathMin, fa.deathMax, fb.deathMin, fb.deathMax);
  const sexEq = fa.sex === fb.sex && fa.sex !== 'ukendt';
  return scorePair(nameSim, birthOverlap, deathOverlap, sexEq, defaultCfg());
}

export type MatchOversigtProps = {
  audit: MatchAuditPost[];
  personer: RedMatchPerson[];
  sources: SourceRow[];
  karantaeneByPersonId: ReadonlyMap<string, string>;
  detaljeCache: ReadonlyMap<string, KandidatDetalje>;
  busy: boolean;
  hentKandidatDetalje: (personId: string) => Promise<KandidatDetalje>;
  onFortryd: (relationId: string, aId: string) => void;
};

function kildeNavn(source: SourceRow): string {
  return source.udgave ?? source.titel ?? `Kilde ${source.id}`;
}

function auditTid(createdAt: string | null): string {
  if (!createdAt) return 'tidspunkt ukendt';
  const date = new Date(createdAt);
  if (Number.isNaN(date.getTime())) return createdAt;
  return new Intl.DateTimeFormat('da-DK', { dateStyle: 'short', timeStyle: 'short' }).format(date);
}

export function MatchOversigt({
  audit, personer, sources, karantaeneByPersonId, detaljeCache, busy,
  hentKandidatDetalje, onFortryd,
}: MatchOversigtProps) {
  const [soegning, setSoegning] = useState('');
  const [kildeId, setKildeId] = useState('');
  const [linjeGren, setLinjeGren] = useState('');
  const [kunIkkeFoldende, setKunIkkeFoldende] = useState(false);
  const [aabentRelationId, setAabentRelationId] = useState<string | null>(null);
  const [detaljeLoading, setDetaljeLoading] = useState<Set<string>>(() => new Set());
  const [detaljeFejl, setDetaljeFejl] = useState<Map<string, string>>(() => new Map());

  const byId = useMemo(() => new Map(personer.map((person) => [String(person.id), person])), [personer]);
  const navnById = useMemo(
    () => new Map(personer.map((person) => [String(person.id), person.fuldtNavn ?? person.navn])),
    [personer],
  );
  const sourceById = useMemo(() => new Map(sources.map((source) => [source.id, source])), [sources]);
  const linjeGrenValg = useMemo(() => [...new Set(personer.flatMap((person) =>
    person.bogReferencer.flatMap((ref) => [ref.linje, ref.grenNavn].filter((value): value is string => Boolean(value))),
  ))].sort((a, b) => a.localeCompare(b, 'da')), [personer]);

  const hentDetalje = (personId: string): Promise<KandidatDetalje> => {
    setDetaljeLoading((prev) => new Set(prev).add(personId));
    setDetaljeFejl((prev) => {
      const next = new Map(prev); next.delete(personId); return next;
    });
    return hentKandidatDetalje(personId)
      .catch((error) => {
        setDetaljeFejl((prev) => new Map(prev).set(personId, String(error?.message ?? error)));
        throw error;
      })
      .finally(() => {
        setDetaljeLoading((prev) => {
          const next = new Set(prev); next.delete(personId); return next;
        });
      });
  };

  const toggleSammenligning = (post: MatchAuditPost) => {
    if (aabentRelationId === post.relationId) {
      setAabentRelationId(null);
      return;
    }
    setAabentRelationId(post.relationId);
    void Promise.all([hentDetalje(post.aId), hentDetalje(post.bId)]).catch(() => undefined);
  };

  const filtreret = useMemo(() => {
    const needle = soegning.trim().toLocaleLowerCase('da-DK');
    return audit.filter((post) => {
      const a = byId.get(post.aId);
      const b = byId.get(post.bId);
      if (needle && ![a, b].some((person) =>
        (person?.fuldtNavn ?? person?.navn ?? '').toLocaleLowerCase('da-DK').includes(needle))) return false;
      if (kildeId && ![a, b].some((person) => person?.sourceIds.includes(Number(kildeId)))) return false;
      if (linjeGren && ![a, b].some((person) => person?.bogReferencer.some((ref) =>
        ref.linje === linjeGren || ref.grenNavn === linjeGren))) return false;
      if (kunIkkeFoldende && (post.beslutning !== 'samme_som'
        || !(karantaeneByPersonId.has(post.aId) || karantaeneByPersonId.has(post.bId)))) return false;
      return true;
    });
  }, [audit, byId, kildeId, karantaeneByPersonId, kunIkkeFoldende, linjeGren, soegning]);

  return (
    <section aria-label="Trufne matchbeslutninger" style={{ marginTop: '1rem' }}>
      <h3 style={{ marginBottom: '.45rem' }}>Trufne beslutninger ({audit.length})</h3>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '.55rem', alignItems: 'end', marginBottom: '.7rem' }}>
        <label>Søg på navn<br />
          <input value={soegning} onChange={(event) => setSoegning(event.target.value)} type="search" />
        </label>
        <label>Kildeudgave<br />
          <select value={kildeId} onChange={(event) => setKildeId(event.target.value)}>
            <option value="">Alle udgaver</option>
            {[...sources].sort((a, b) => (b.aar ?? 0) - (a.aar ?? 0)).map((source) => (
              <option key={source.id} value={source.id}>{kildeNavn(source)}</option>
            ))}
          </select>
        </label>
        <label>Linje/gren<br />
          <select value={linjeGren} onChange={(event) => setLinjeGren(event.target.value)}>
            <option value="">Alle linjer/grene</option>
            {linjeGrenValg.map((value) => <option key={value} value={value}>{value}</option>)}
          </select>
        </label>
        <label style={{ paddingBottom: '.2rem' }}>
          <input type="checkbox" checked={kunIkkeFoldende}
            onChange={(event) => setKunIkkeFoldende(event.target.checked)} />{' '}
          Vis kun links der ikke folder endnu
        </label>
      </div>

      {filtreret.length === 0 && <p style={{ color: '#6f675b' }}>Ingen beslutninger matcher filtrene.</p>}
      <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
        {filtreret.map((post) => {
          const a = byId.get(post.aId);
          const b = byId.get(post.bId);
          const grund = post.beslutning === 'samme_som'
            ? karantaeneByPersonId.get(post.aId) ?? karantaeneByPersonId.get(post.bId) ?? null
            : null;
          const score = a && b ? rekomputerMatchScore(a, b) : null;
          const erAabent = aabentRelationId === post.relationId;
          const detaljeA = detaljeCache.get(post.aId);
          const detaljeB = detaljeCache.get(post.bId);
          const detaljeError = detaljeFejl.get(post.aId) ?? detaljeFejl.get(post.bId) ?? null;
          const indlaeser = detaljeLoading.has(post.aId) || detaljeLoading.has(post.bId);
          const actor = [post.actorNavn ?? 'Ukendt redaktør', post.actorRolle].filter(Boolean).join(' · ');
          const sourceLabel = (person?: RedMatchPerson) => {
            const labels = person?.sourceIds.map((id) => sourceById.get(id)).filter((source): source is SourceRow => Boolean(source))
              .map(kildeNavn) ?? [];
            return labels.length ? labels.join(' · ') : 'Ukendt kilde';
          };
          return (
            <li key={`${post.beslutning}:${post.relationId}`} data-testid={`audit-post-${post.relationId}`}
              style={{ border: '1px solid rgba(34,31,26,.12)', borderRadius: 6, padding: '.65rem .8rem', margin: '.5rem 0' }}>
              <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: '.4rem' }}>
                <strong style={{ color: post.beslutning === 'samme_som' ? '#3d7a3d' : '#881A33' }}>
                  {post.beslutning === 'samme_som' ? 'Bekræftet samme person' : 'Afvist som forskellige'}
                </strong>
                <span><code>Score {score == null ? '—' : score.toFixed(3)}</code></span>
              </div>
              <div style={{ marginTop: '.25rem' }}>
                {formatPersonNavn(a)} {post.beslutning === 'samme_som' ? '=' : '≠'} {formatPersonNavn(b)}
              </div>
              <div style={{ fontSize: '.82em', color: '#6f675b', marginTop: '.15rem' }}>
                {[formatBogReferencer(a), formatBogReferencer(b)].filter(Boolean).join(' ↔ ') || 'Ingen bogreference'}
              </div>
              <div style={{ fontSize: '.82em', color: '#6f675b', marginTop: '.2rem' }}>
                {actor} · <time dateTime={post.createdAt ?? undefined}>{auditTid(post.createdAt)}</time>
              </div>
              <div style={{ fontSize: '.82em', marginTop: '.2rem', color: grund ? '#881A33' : '#3d7a3d' }}>
                {post.beslutning === 'ikke_samme_som'
                  ? 'Fold-status er ikke relevant for en afvisning.'
                  : grund ? `⚠ Linket folder ikke endnu: ${grund}` : '✓ Linket foldes offentligt til én person.'}
              </div>
              <div style={{ marginTop: '.4rem' }}>
                <button type="button" onClick={() => toggleSammenligning(post)}>
                  {erAabent ? 'Luk sammenligning' : 'Se sammenligning'}
                </button>
                {post.beslutning === 'samme_som' && <>{' '}
                  <button type="button" disabled={busy} onClick={() => onFortryd(post.relationId, post.aId)}>Fortryd</button>
                </>}
              </div>
              {erAabent && (
                detaljeError
                  ? <p style={{ color: '#881A33' }}>Kunne ikke hente kandidatdetaljer: {detaljeError}</p>
                  : detaljeA && detaljeB && a && b
                    ? <KandidatSammenligning
                        personA={a} personB={b} detaljeA={detaljeA} detaljeB={detaljeB}
                        kildeA={sourceLabel(a)} kildeB={sourceLabel(b)}
                        rolleA={post.beslutning === 'samme_som' ? 'alias' : undefined}
                        rolleB={post.beslutning === 'samme_som' ? 'kanonisk' : undefined}
                        navnById={navnById}
                        foldHint={post.beslutning === 'samme_som'
                          ? { folder: grund == null, grund }
                          : { folder: false, grund: 'Parret er markeret som forskellige.' }}
                        linket={post.beslutning === 'samme_som'} busy
                        onBekraeft={() => undefined} onAfvis={() => undefined}
                      />
                    : <p style={{ color: '#6f675b' }}>{indlaeser ? 'Indlæser kandidatdetaljer…' : 'Kandidatdetaljer mangler.'}</p>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
