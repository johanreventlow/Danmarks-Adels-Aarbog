// "Sammenlign udgaver" — redaktør-flade til tværudgave-identitet (Problem 3 §5). Mobil-spejl
// af web/src/components/SammenlignUdgaver.tsx. Kildevalg → matcher-kørsel (memoiseret, @daa/core)
// → arbejdsliste → Bekræft/Afvis. Retning (§5.4): eksisterende base = kanonisk (objekt/sink),
// ny udgaves person = alias (subjekt).
//
// Divergens fra web (bevidst): writes rutes gennem SkrivePreviewSheet (dry-run/LIVE-flow), ikke
// direkte submitChange — mobil-konvention (direkte kald = tavst no-op i dry-run). Derfor ingen
// batch "Markér som ny" (kan ikke kø'e flere changes i én sheet); per-kandidat Afvis når samme
// slut-tilstand (alle kandidater afvist → status flipper til 'afklaret').
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { matchUdgaver, buildMatchFrame, type MatchFrame, type RedMatchPerson } from '@daa/core';
import { CenterMsg } from '../../components/CenterMsg';
import { TopBar } from '../../components/TopBar';
import { SkrivePreviewSheet } from '../../components/redaktion/SkrivePreviewSheet';
import { Body, BtnLabel, Mono, Serif } from '../../components/Typography';
import {
  fetchSources, fetchMatchPersoner, fetchIkkeSammeSomPar, fetchSammeSomPar, type SourceRow,
} from '../../data/redaktionRead';
import { type Change } from '../../data/redaktionWrite';
import { buildArbejdsliste, pairKey } from '../../data/sammenlign';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

function visning(p?: RedMatchPerson): string {
  if (!p) return '(ukendt)';
  const fy = p.foedsel?.date_min?.slice(0, 4) ?? '';
  const dy = p.doed?.date_min?.slice(0, 4) ?? '';
  const span = fy || dy ? ` (${fy}–${dy})` : '';
  return `${p.navn}${span}`;
}

function kildeLabel(src: SourceRow): string {
  return `${src.udgave ?? src.titel ?? `Kilde ${src.id}`}${src.aar ? ` (${src.aar})` : ''}`;
}

export default function SammenlignUdgaver() {
  const rolle = useStore((s) => s.rolle);
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [personer, setPersoner] = useState<RedMatchPerson[]>([]);
  const [afviste, setAfviste] = useState<{ aId: string; bId: string }[]>([]);
  const [linkede, setLinkede] = useState<{ aId: string; bId: string }[]>([]);
  const [nyKildeId, setNyKildeId] = useState<number | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState<string | null>(null);
  const [pending, setPending] = useState<Change | null>(null);
  const [refresh, setRefresh] = useState(0);

  // Tungt basis-load (kilder + 922-person-matchsæt) kun ved mount — ændres ikke af en
  // Bekræft/Afvis-write, så det skal ikke gen-hentes ved refresh.
  useEffect(() => {
    let alive = true;
    Promise.all([fetchSources(), fetchMatchPersoner()])
      .then(([s, p]) => {
        if (!alive) return;
        setSources(s); setPersoner(p);
        setNyKildeId((prev) => prev ?? (
          s.filter((x) => x.aar != null).sort((a, b) => (b.aar as number) - (a.aar as number))[0]?.id ?? s[0]?.id ?? null));
        setStatus('ready');
      })
      .catch((e) => { if (alive) { setFejl(String(e?.message ?? e)); setStatus('error'); } });
    return () => { alive = false; };
  }, []);

  // Relations-parrene (samme_som/ikke_samme_som) er det eneste en write mutérer — genhent
  // KUN dem ved refresh (to lette queries, ikke det tunge personsæt).
  useEffect(() => {
    let alive = true;
    Promise.all([fetchIkkeSammeSomPar(), fetchSammeSomPar()])
      .then(([afv, lnk]) => { if (alive) { setAfviste(afv); setLinkede(lnk); setFejl(null); } })
      .catch((e) => { if (alive) setFejl(String(e?.message ?? e)); });
    return () => { alive = false; };
  }, [refresh]);

  const byId = useMemo(() => new Map(personer.map((p) => [String(p.id), p])), [personer]);

  // Selve matchen (O(n) over ~922 personer) afhænger kun af personsæt + valgt ny kilde — hold
  // den adskilt fra afviste/linkede, så en afvisning ikke gen-scanner hele matcheren.
  const framed = useMemo(() => {
    if (nyKildeId == null) return null;
    const framesA: MatchFrame[] = [], framesB: MatchFrame[] = [], aIds: string[] = [];
    for (const p of personer) {
      const f = buildMatchFrame(p);
      if (p.sourceIds.includes(nyKildeId)) { framesA.push(f); aIds.push(String(p.id)); }
      else framesB.push(f);
    }
    return { pairs: matchUdgaver(framesA, framesB), aIds };
  }, [personer, nyKildeId]);

  const arbejdsliste = useMemo(() => {
    if (!framed) return null;
    return buildArbejdsliste(
      framed.pairs, framed.aIds,
      new Set(afviste.map((x) => pairKey(x.aId, x.bId))),
      new Set(linkede.map((x) => pairKey(x.aId, x.bId))),
    );
  }, [framed, afviste, linkede]);

  const { aabne, formodetNye } = useMemo(() => ({
    aabne: arbejdsliste?.personer.filter((p) => p.status === 'aaben') ?? [],
    formodetNye: arbejdsliste?.personer.filter((p) => p.status === 'formodet_ny') ?? [],
  }), [arbejdsliste]);

  const bekraeft = useCallback((aId: string, bId: string) => // ny(A)=alias, eksisterende(B)=kanonisk (§5.4)
    setPending({ art: 'sammeSom', subjektType: 'person', subjektId: aId, payload: { aliasId: aId, objektId: bId } }), []);
  const afvis = useCallback((aId: string, bId: string) =>
    setPending({ art: 'ikkeSammeSom', subjektType: 'person', subjektId: aId, payload: { aId, bId } }), []);

  if (rolle !== 'redaktion')
    return <CenterMsg title="Sammenlign udgaver">Kræver redaktør-rolle.</CenterMsg>;

  const f = arbejdsliste?.fremdrift;

  return (
    <View style={s.wrap}>
      <TopBar title="Sammenlign udgaver" />
      {status === 'loading' ? <ActivityIndicator style={{ marginTop: 40 }} /> : null}
      {status === 'error' ? <Body color={Colors.danger} style={{ padding: 24 }}>{fejl}</Body> : null}
      {status === 'ready' ? (
        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 32 }}>
          <Body size={13} color={Colors.textMuted} style={{ marginBottom: 8 }}>Ny udgave (matches mod resten af basen):</Body>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingBottom: 4 }}>
            {[...sources].sort((a, b) => (b.aar ?? 0) - (a.aar ?? 0)).map((src) => {
              const aktiv = src.id === nyKildeId;
              return (
                <Pressable key={src.id} style={[s.chip, aktiv && s.chipAktiv]} onPress={() => setNyKildeId(src.id)}>
                  <Mono size={12} color={aktiv ? '#fff' : Colors.textSecondary}>{kildeLabel(src)}</Mono>
                </Pressable>
              );
            })}
          </ScrollView>

          {fejl ? <Mono size={11} color={Colors.bordeaux} style={{ marginTop: 8 }}>{fejl}</Mono> : null}

          {f ? (
            <Body size={13} color={Colors.textMuted} style={{ marginTop: 12 }}>
              {f.afklaret} af {f.total} afklaret · {f.staerke} stærke · {f.gennemse} til gennemsyn · {f.formodetNye} formodet nye
            </Body>
          ) : null}

          {aabne.map((person) => {
            const a = byId.get(person.aId);
            const aktive = person.kandidater.filter((k) => !k.afvist);
            return (
              <View key={person.aId} style={s.kort}>
                <Serif size={16}>{visning(a)}</Serif>
                {aktive.map((k) => {
                  const b = byId.get(String(k.bId));
                  return (
                    <View key={String(k.bId)} style={s.kand}>
                      <Body size={13}>
                        <Body size={13} color={Colors.bordeaux}>{k.tier === 'auto' ? '★ stærk' : 'gennemse'}</Body>
                        {'  '}{(k.score ?? 0).toFixed(3)} — {visning(b)}
                      </Body>
                      <Mono size={11} color={Colors.textMuted} style={{ marginTop: 3 }}>
                        navn {k.nameSim.toFixed(2)} · fødsel {k.birthOverlap ? '✓' : '—'} · død {k.deathOverlap ? '✓' : '—'} · køn {k.sexEq ? '✓' : '✗'}
                      </Mono>
                      <View style={s.knapper}>
                        <Pressable style={[s.knap, s.knapPrimaer, k.linket && s.knapDisabled]}
                          disabled={k.linket} onPress={() => bekraeft(person.aId, String(k.bId))}>
                          <BtnLabel color="#fff">{k.linket ? '✓ bekræftet' : 'Bekræft samme'}</BtnLabel>
                        </Pressable>
                        <Pressable style={[s.knap, s.knapSekundaer]} onPress={() => afvis(person.aId, String(k.bId))}>
                          <BtnLabel color={Colors.bordeaux}>Afvis</BtnLabel>
                        </Pressable>
                      </View>
                    </View>
                  );
                })}
              </View>
            );
          })}

          {aabne.length === 0 ? (
            <Body color={Colors.textMuted} style={{ marginTop: 16 }}>Ingen åbne kandidater at gennemgå.</Body>
          ) : null}

          {formodetNye.length > 0 ? (
            <View style={s.nyeSektion}>
              <Serif size={15} style={{ marginBottom: 6 }}>{formodetNye.length} formodet nye — ingen handling nødvendig</Serif>
              {formodetNye.map((p) => (
                <Mono key={p.aId} size={11} color={Colors.textMuted} style={{ marginBottom: 3 }}>{visning(byId.get(p.aId))}</Mono>
              ))}
            </View>
          ) : null}
        </ScrollView>
      ) : null}

      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={() => { setPending(null); setRefresh((r) => r + 1); }}
      />
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: Colors.paperBg },
  chip: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.chip, paddingVertical: 7, paddingHorizontal: 12 },
  chipAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  kort: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 14, marginTop: 12 },
  kand: { marginTop: 10, paddingTop: 10, borderTopWidth: 1, borderTopColor: Border.light },
  knapper: { flexDirection: 'row', gap: 8, marginTop: 8 },
  knap: { borderRadius: Radius.field, paddingVertical: 9, paddingHorizontal: 14, alignItems: 'center' },
  knapPrimaer: { backgroundColor: Colors.bordeaux },
  knapSekundaer: { borderWidth: 1, borderColor: Colors.bordeaux },
  knapDisabled: { opacity: 0.5 },
  nyeSektion: { marginTop: 20, paddingTop: 12, borderTopWidth: 1, borderTopColor: Border.light },
});
