// Stamtræ (README §5.2) — tre varianter + §9.2 linje-hop.
//  A · Fokus     — lodret kort-fokus (bedsteforælder→forælder→søskende→børn).
//  B · Kolonner  — vandret-scrollende drill-down kolonner, én pr. generation.
//  C · Spor      — fuldskærms native snap-scroll-spor (lodret=generation, vandret=søskende;
//                  flydende momentum + snap til midte; haptik pr. landing).
import * as Haptics from 'expo-haptics';
import { useRouter } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { buildBidirectionalColumns, childrenOf, routeToMe, treeFocusA, wayToMe, type WayStep } from '../../data/selectors';
import type { Model, ModelPerson } from '../../data/types';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';

export default function TreeScreen() {
  const insets = useSafeAreaInsets();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const variant = useStore((s) => s.variant);
  const setVariant = useStore((s) => s.setVariant);
  const activeLinje = useStore((s) => s.activeLinje);
  const pickLinje = useStore((s) => s.pickLinje);
  const clearLinje = useStore((s) => s.clearLinje);

  const linjeList = aux?.linjeList ?? [];

  return (
    <LoadGate>
      <View style={{ flex: 1, paddingTop: insets.top }}>
        <View style={styles.head}>
          <View style={styles.segment}>
            <Segment label="Fokus" active={variant === 'A'} onPress={() => setVariant('A')} />
            <Segment label="Kolonner" active={variant === 'B'} onPress={() => setVariant('B')} />
            <Segment label="Spor" active={variant === 'C'} onPress={() => setVariant('C')} />
          </View>
          {linjeList.length ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.linjeRow}>
              <LinjeChip label="Hele slægten" active={!activeLinje} onPress={() => clearLinje()} />
              {linjeList.map((l) => (
                <LinjeChip key={l.linje} label={l.navn ?? `Linje ${l.linje}`} active={activeLinje === l.linje} onPress={() => pickLinje(l.linje, l.headId)} />
              ))}
            </ScrollView>
          ) : null}
        </View>

        {!model ? null : variant === 'B' ? (
          <VariantB model={model} insets={insets} />
        ) : variant === 'C' ? (
          <VariantC model={model} activeLinje={activeLinje} linjeByPerson={aux?.linjeByPerson ?? {}} linjeNavn={aux?.linjeNavn ?? {}} />
        ) : (
          <VariantA model={model} insets={insets} />
        )}
      </View>
    </LoadGate>
  );
}

// ── Variant A · Fokus ────────────────────────────────────────────────────────
function VariantA({ model, insets }: { model: Model; insets: { bottom: number } }) {
  const router = useRouter();
  const focusId = useStore((s) => s.focusId);
  const setFocus = useStore((s) => s.setFocus);
  const view = useMemo(() => (focusId ? treeFocusA(model, focusId) : null), [model, focusId]);
  if (!view || !view.focus) {
    return <View style={{ padding: 24 }}><Kicker color={Colors.textMuted}>Vælg en linje eller person.</Kicker></View>;
  }
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: insets.bottom + 80 }}>
      <CenterKicker text="Aner" style={{ marginTop: 6, marginBottom: 2 }} />
      {view.grandparent ? (
        <>
          <Pressable style={styles.grandPill} onPress={() => setFocus(view.grandparent!.id)}>
            <Mono size={13} color={Colors.textMuted}>▲</Mono>
            <Serif size={15} color="#5a5246">{view.grandparent.name}</Serif>
          </Pressable>
          <Connector height={14} />
        </>
      ) : null}
      {view.parent ? (
        <>
          <Pressable style={styles.parentCard} onPress={() => setFocus(view.parent!.id)}>
            <View style={styles.parentAvatar}><Serif size={18} color={Colors.bordeaux}>{initial(view.parent.name)}</Serif></View>
            <View>
              <Kicker size={8.5} color={Colors.gold} style={{ letterSpacing: 8.5 * 0.12 }}>Forælder ▲</Kicker>
              <Serif size={19} style={{ marginTop: 1, lineHeight: 20 }}>{view.parent.name}</Serif>
              {view.parent.years ? <Mono size={10} color={Colors.textMuted} style={{ marginTop: 2 }}>{view.parent.years}</Mono> : null}
            </View>
          </Pressable>
          <Connector height={18} />
        </>
      ) : null}
      <CenterKicker text="Denne generation ◂ ▸" style={{ marginVertical: 8 }} />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 11, paddingHorizontal: 2, paddingBottom: 6 }}>
        {view.siblings.map((s) => (
          <SiblingCard key={s.id} person={s} childCount={childrenOf(model, s.id).length} selected={s.id === view.focus!.id} onFocus={() => setFocus(s.id)} onOpen={() => router.push(`/person/${s.id}`)} />
        ))}
      </ScrollView>
      {view.spouseName ? (
        <Serif size={15} italic color={Colors.textSecondary2} style={{ textAlign: 'center', marginTop: 10, fontFamily: Fonts.serifItalic }}>⚭ gift med {view.spouseName}</Serif>
      ) : null}
      {view.children.length ? (
        <>
          <Connector height={18} style={{ marginTop: 14 }} />
          <CenterKicker text="Børn & grene ▾" style={{ marginVertical: 8 }} />
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10, paddingHorizontal: 2, paddingBottom: 6 }}>
            {view.children.map((c) => (
              <Pressable key={c.id} style={styles.childCard} onPress={() => setFocus(c.id)}>
                <View style={styles.childAvatar}><Serif size={17} color={Colors.bordeaux}>{initial(c.name)}</Serif></View>
                <Serif size={18} style={{ marginTop: 9, lineHeight: 19 }}>{c.name}</Serif>
                {c.years ? <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 3 }}>{c.years}</Mono> : null}
              </Pressable>
            ))}
          </ScrollView>
        </>
      ) : null}
    </ScrollView>
  );
}

// ── Variant B · Kolonner (bidirektionel: aner venstre · fokus · efterkommere højre) ───────────
const B_STRIDE = 176; // kolonnebredde 166 + gap 10
function VariantB({ model, insets }: { model: Model; insets: { bottom: number } }) {
  const router = useRouter();
  const anchorId = useStore((s) => s.anchorId);
  const up = useStore((s) => s.up);
  const down = useStore((s) => s.down);
  const selectAncestor = useStore((s) => s.selectAncestor);
  const selectDescendant = useStore((s) => s.selectDescendant);
  const setFocus = useStore((s) => s.setFocus);
  const genCoordsByPerson = useStore((s) => s.genCoordsByPerson);
  const scrollRef = useRef<ScrollView>(null);
  const viewW = useRef(0);
  const prevUp = useRef(0), prevDown = useRef(0), prevAnchor = useRef<string | null>(null);
  const cols = useMemo(
    () => (anchorId ? buildBidirectionalColumns(model, anchorId, up, down, genCoordsByPerson) : []),
    [model, anchorId, up, down, genCoordsByPerson],
  );
  const anchorIdx = cols.findIndex((c) => c.kind === 'anchor');

  // Auto-scroll (spec §5.5): centrér anker ved reset; afslør nyeste kolonne ved drill (ned → højre,
  // op → venstre). setTimeout venter på RN-layout (samme mønster som før; verificeres manuelt i Expo).
  useEffect(() => {
    const t = setTimeout(() => {
      const sc = scrollRef.current;
      if (!sc) return;
      if (anchorId !== prevAnchor.current) {
        const x = Math.max(0, anchorIdx * B_STRIDE - Math.max(0, (viewW.current - 166) / 2));
        sc.scrollTo({ x, animated: false });          // centrér anker
      } else if (down.length > prevDown.current) {
        sc.scrollToEnd({ animated: true });           // ny efterkommer → højre
      } else if (up.length > prevUp.current) {
        sc.scrollTo({ x: 0, animated: true });        // ny ane → afslør venstre
      }
      prevUp.current = up.length; prevDown.current = down.length; prevAnchor.current = anchorId;
    }, 60);
    return () => clearTimeout(t);
  }, [anchorId, up.length, down.length, anchorIdx]);

  return (
    <View style={{ flex: 1, paddingTop: 8 }}>
      <Mono size={9.5} color={Colors.textMuted} style={{ paddingHorizontal: 16, paddingBottom: 4, letterSpacing: 9.5 * 0.12, textTransform: 'uppercase' }}>
        ◂ aner · fokus · efterkommere ▸
      </Mono>
      <ScrollView
        ref={scrollRef}
        horizontal
        showsHorizontalScrollIndicator={false}
        style={{ flex: 1 }}
        contentContainerStyle={{ gap: 10, paddingHorizontal: 16, paddingVertical: 8, alignItems: 'stretch' }}
        onLayout={(e) => { viewW.current = e.nativeEvent.layout.width; }}
      >
        {cols.map((col) => (
          <View key={col.key} style={{ width: 166 }}>
            <Mono size={9} color={Colors.gold} style={{ letterSpacing: 9 * 0.1, textTransform: 'uppercase', paddingBottom: 2, marginBottom: col.fallback ? 2 : 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light }}>
              {col.fallback ? col.genLabel : col.label}
            </Mono>
            {col.fallback ? (
              <Mono size={8.5} color={Colors.textMuted2} style={{ marginBottom: 8, lineHeight: 11 }}>
                slægtled-naboer — ingen bevist som forælder
              </Mono>
            ) : null}
            <ScrollView style={{ flex: 1 }} showsVerticalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingBottom: insets.bottom + 90 }}>
            {col.fallback ? (
              Object.entries(col.kuldGroups ?? {}).map(([kuld, people]) => (
                <View key={kuld} style={{ gap: 8 }}>
                  {kuld !== '—' ? (
                    <Mono size={8} color={Colors.textMuted3} style={{ letterSpacing: 8 * 0.08, textTransform: 'uppercase' }}>Kuld {kuld}</Mono>
                  ) : null}
                  {people.map((p) => (
                    <Pressable key={p.id} onPress={() => setFocus(p.id)} style={styles.bCardFallback}>
                      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                        <View style={styles.bAvatar}><Serif size={15} color={Colors.bordeaux}>{initial(p.name)}</Serif></View>
                        <View style={{ flex: 1, minWidth: 0 }}>
                          <Serif size={16} style={{ lineHeight: 17 }} numberOfLines={2}>{p.name}</Serif>
                          {p.years ? <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{p.years}</Mono> : null}
                          <Mono size={8} color={Colors.gold} style={{ letterSpacing: 8 * 0.06, textTransform: 'uppercase', marginTop: 2 }}>muligt slægtled</Mono>
                        </View>
                        {/* (ingen BookmarkFlag her — mobile-bogmærker er endnu ikke designet, jf. CLAUDE.md §9) */}
                      </View>
                    </Pressable>
                  ))}
                </View>
              ))
            ) : col.people.map((p) => {
              const sel = p.id === col.selectedId;
              const canAnc = col.kind === 'ancestor' && (model.indexes.parentsByChild[p.id]?.length ?? 0) > 0;
              const canDesc = col.kind === 'descendant' && childrenOf(model, p.id).length > 0;
              const onPress = col.kind === 'ancestor' ? () => selectAncestor(col.depth, p.id)
                : col.kind === 'descendant' ? () => selectDescendant(col.depth, p.id)
                : undefined;
              return (
                <Pressable key={p.id} onPress={onPress} style={[styles.bCard, sel ? styles.bCardSelected : styles.bCardIdle]}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                    {canAnc ? <Serif size={16} color="#bcae93">‹</Serif> : null}
                    <View style={styles.bAvatar}><Serif size={15} color={Colors.bordeaux}>{initial(p.name)}</Serif></View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Serif size={16} style={{ lineHeight: 17 }} numberOfLines={2}>{p.name}</Serif>
                      {p.years ? <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{p.years}</Mono> : null}
                    </View>
                    {canDesc ? <Serif size={16} color="#bcae93">›</Serif> : null}
                  </View>
                  {sel ? (
                    <Pressable onPress={() => router.push(`/person/${p.id}`)} style={styles.bOpenBtn}>
                      <BtnLabel size={11.5} color={Colors.paperCard}>Åbn profil ›</BtnLabel>
                    </Pressable>
                  ) : null}
                </Pressable>
              );
            })}
            </ScrollView>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

// ── Variant C · Spor (gestus-snap) ───────────────────────────────────────────
const ARROW: Record<Exclude<WayStep, 'arrived'>, string> = { up: '▲', down: '▼', left: '◂', right: '▸' };
const STEPY = 138; // lodret afstand mellem generationer
const CARD_W = 150;
const CARD_H = 104;
const CARD_GAP = 14; // vandret mellemrum mellem søskende-kort
const FRAME_NUDGE = 17; // løfter fokus-ramme + badge så det centrerede kort lander i rammen (juster ved skævhed)
const FRAME_NUDGE_X = 0.5; // skubber fokus-ramme en anelse mod højre (afbalancerer venstre/højre margin)
const GAP_V = STEPY - CARD_H; // tomt lodret mellemrum under et (top-justeret) kort = rygrad-segment-højde

function VariantC({ model, activeLinje, linjeByPerson, linjeNavn }: { model: Model; activeLinje: string | null; linjeByPerson: Record<string, string[]>; linjeNavn: Record<string, string> }) {
  const router = useRouter();
  const snapPath = useStore((s) => s.snapPath);
  const snapDepth = useStore((s) => s.snapDepth);
  const meId = useStore((s) => s.meId);
  const way = useMemo(
    () => (meId ? wayToMe(model, snapPath, snapDepth, meId) : undefined),
    [meId, model, snapPath, snapDepth],
  );
  const moveSnapGen = useStore((s) => s.moveSnapGen);
  const moveSnapSib = useStore((s) => s.moveSnapSib);

  // Hver generation (depth d) = en vandret snap-ScrollView med ALLE søskende; den valgte
  // centreres. d=0 er kun roden. Førstefødt = indeks 0.
  const rows = useMemo(() => {
    const out: { d: number; sibIds: string[]; selIndex: number }[] = [];
    for (let d = 0; d < snapPath.length; d++) {
      const sibIds = d === 0 ? [snapPath[0]] : childrenOf(model, snapPath[d - 1]).map((p) => p.id);
      const selIndex = Math.max(0, sibIds.indexOf(snapPath[d]));
      out.push({ d, sibIds, selIndex });
    }
    return out;
  }, [model, snapPath]);

  // Rute til "mig" → hvilke mellemrum-segmenter farves røde. Følger gestus-planen fra fokus,
  // men STOPPER hvor ruten forlader de synlige rækker (et lodret skridt EFTER et søskendeskift
  // peger på en ikke-renderet gren). Resten kommunikeres af badgen "N spring til dig".
  const route = useMemo(
    () => (meId ? routeToMe(model, snapPath, snapDepth, meId) : null),
    [meId, model, snapPath, snapDepth],
  );
  const red = useMemo(() => {
    const redV = new Set<number>(); // række d hvis bund-segment (gap d→d+1) er rødt
    const redH = new Set<string>(); // `${d}:${gapIndex}` vandret gap rødt
    let exit: { d: number; sib: number } | null = null; // hvor ruten forlader skærmen (off-screen ned)
    if (!route || route.length === 0) return { redV, redH, exit };
    let d = snapDepth;
    let cursor: number | null = null;
    let sawSibling = false;
    for (const step of route) {
      if (step === 'up' || step === 'down') {
        if (sawSibling) { exit = { d, sib: cursor ?? rows[d]?.selIndex ?? 0 }; break; } // lodret efter søskendeskift → off-screen
        if (step === 'up') { redV.add(d - 1); d -= 1; } else { redV.add(d); d += 1; }
        cursor = null;
      } else {
        const row = rows[d];
        if (!row) break;
        if (cursor === null) cursor = row.selIndex;
        if (step === 'right') { redH.add(`${d}:${cursor}`); cursor += 1; }
        else { cursor -= 1; redH.add(`${d}:${cursor}`); }
        sawSibling = true;
      }
    }
    return { redV, redH, exit };
  }, [route, rows, snapDepth]);

  // Native nested snap-scroll: lodret ScrollView = generationer (snap pr. STEPY), hver række =
  // horisontal ScrollView med søskende (snap pr. HSTEP). Centrering bages ind i padding, så
  // contentOffset = indeks*pitch lander kortet i midten. onMomentumScrollEnd → opdater store.
  const [size, setSize] = useState({ w: 0, h: 0 });
  const hRefs = useRef<Record<number, ScrollView | null>>({});
  const HSTEP = CARD_W + CARD_GAP;
  const vPad = Math.max(0, size.h / 2 - STEPY / 2);
  const hPad = Math.max(0, size.w / 2 - CARD_W / 2);
  const haptic = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});

  const onVEnd = (y: number) => {
    const d = Math.round(y / STEPY);
    if (d !== snapDepth && d >= 0 && d < snapPath.length) { moveSnapGen(d - snapDepth); haptic(); }
  };
  const onHEnd = (d: number, selIndex: number, len: number, x: number) => {
    if (d !== snapDepth) return; // kun fokus-rækken styrer valget
    const idx = Math.round(x / HSTEP);
    if (idx !== selIndex && idx >= 0 && idx < len) { moveSnapSib(idx - selIndex); haptic(); }
  };
  const tapCard = (d: number, i: number, selIndex: number, id: string) => {
    if (d !== snapDepth) return;
    if (i === selIndex) { router.push(`/person/${id}`); return; }
    hRefs.current[d]?.scrollTo({ x: i * HSTEP, animated: true });
    moveSnapSib(i - selIndex); haptic();
  };

  const focusPerson = snapPath[snapDepth] ? model.byId[snapPath[snapDepth]] : null;
  const gen = snapDepth + 1;
  const linje = focusPerson ? linjeByPerson[focusPerson.id]?.[0] ?? activeLinje : activeLinje;

  return (
    <View style={styles.snapContainer} onLayout={(e) => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}>
      {size.h > 0 ? (
        <ScrollView
          style={{ flex: 1 }}
          showsVerticalScrollIndicator={false}
          snapToOffsets={rows.map((_, i) => i * STEPY)}
          decelerationRate="fast"
          contentOffset={{ x: 0, y: snapDepth * STEPY }}
          onMomentumScrollEnd={(e) => onVEnd(e.nativeEvent.contentOffset.y)}
          contentContainerStyle={{ paddingTop: vPad, paddingBottom: vPad }}
        >
          {rows.map((r) => {
            const isFocusRow = r.d === snapDepth;
            return (
              <View key={`${r.d}:${r.sibIds[0]}`} style={{ height: STEPY, justifyContent: 'center' }}>
                {/* Lodret rygrad-segment i mellemrummet UNDER kortet (kortet er top-justeret),
                    kun mellem kort der har en efterfølger → ingen gennemskin, intet dingl.
                    Rødt når det er på ruten til "mig". */}
                {r.d < rows.length - 1 && <View pointerEvents="none" style={[styles.spineSeg, red.redV.has(r.d) && styles.routeSeg]} />}
                <ScrollView
                  ref={(el) => { hRefs.current[r.d] = el; }}
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  snapToOffsets={r.sibIds.map((_, i) => i * HSTEP)}
                  decelerationRate="fast"
                  scrollEnabled={isFocusRow}
                  contentOffset={{ x: r.selIndex * HSTEP, y: 0 }}
                  onMomentumScrollEnd={(e) => onHEnd(r.d, r.selIndex, r.sibIds.length, e.nativeEvent.contentOffset.x)}
                  contentContainerStyle={{ paddingHorizontal: hPad, gap: CARD_GAP }}
                >
                  {/* Søskende-forbindelser: ét kort segment i HVERT mellemrum (kant-til-kant),
                      aldrig bag et kort → ingen gennemskin. Følger kortene ved scroll. */}
                  {r.sibIds.slice(1).map((_, i) => {
                    const onRoute = red.redH.has(`${r.d}:${i}`);
                    return (
                      <View key={`bus-${i}`} pointerEvents="none" style={{ position: 'absolute', top: CARD_H / 2 - (onRoute ? 1 : 0.75), left: hPad + i * HSTEP + CARD_W, width: CARD_GAP, height: onRoute ? 2 : 1.5, backgroundColor: onRoute ? Colors.bordeaux : 'rgba(34,31,26,0.13)' }} />
                    );
                  })}
                  {r.sibIds.map((id, i) => {
                    const p = model.byId[id];
                    if (!p) return <View key={id} style={styles.snapSpacer} />;
                    const isSel = isFocusRow && i === r.selIndex;
                    const isMe = id === meId;
                    return (
                      <Pressable key={id} onPress={() => tapCard(r.d, i, r.selIndex, id)} style={[styles.snapCard, isMe && styles.snapCardMe, { opacity: isFocusRow ? (isSel ? 1 : 0.62) : 0.45 }]}>
                        {isMe && <Mono size={7.5} color={Colors.bordeaux} style={{ position: 'absolute', top: 6, right: 9, letterSpacing: 0.8 }}>★ DIG</Mono>}
                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 9 }}>
                          <View style={styles.snapAvatar}><Serif size={14} color={Colors.bordeaux}>{initial(p.name)}</Serif></View>
                          <View style={{ flex: 1, minWidth: 0 }}>
                            <Serif size={17} style={{ lineHeight: 17 }} numberOfLines={1}>{p.name}</Serif>
                            {p.years ? <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{p.years}</Mono> : null}
                          </View>
                        </View>
                        {p.title ? <BtnLabel size={10.5} color={Colors.bordeaux} numberOfLines={1} style={{ marginTop: 7, fontFamily: Fonts.sansMedium }}>{p.title}</BtnLabel> : null}
                      </Pressable>
                    );
                  })}
                  {/* A: rute fortsætter off-screen ned fra dette søskende-kort */}
                  {red.exit && red.exit.d === r.d && (
                    <Mono size={13} color={Colors.bordeaux} style={{ position: 'absolute', top: CARD_H - 17, left: hPad + red.exit.sib * HSTEP, width: CARD_W, textAlign: 'center' }}>▾</Mono>
                  )}
                </ScrollView>
              </View>
            );
          })}
        </ScrollView>
      ) : null}
      {/* Center-fokus-ramme */}
      <View style={styles.snapFrame} pointerEvents="none" />
      {/* Wayfinder-badge på linjen, over fokus-rammen */}
      {meId == null ? (
        <View style={styles.wayBadge} pointerEvents="none">
          <View style={styles.wayPill}>
            <Mono size={8} color={Colors.bordeaux} style={{ letterSpacing: 8 * 0.08, textTransform: 'uppercase' }}>Vælg dig selv i en profil</Mono>
          </View>
        </View>
      ) : way?.step === 'arrived' ? (
        <View style={styles.wayBadge} pointerEvents="none">
          <View style={styles.wayPill}>
            <Mono size={9} color={Colors.bordeaux} style={{ letterSpacing: 9 * 0.08 }}>★ Du er her</Mono>
          </View>
        </View>
      ) : way ? (
        <View style={styles.wayBadge} pointerEvents="none">
          <View style={styles.wayPill}>
            <Mono size={10} color={Colors.bordeaux}>{ARROW[way.step]} {way.remaining} spring til dig</Mono>
          </View>
        </View>
      ) : null}
      {/* Top-overlay */}
      <View style={styles.snapTop} pointerEvents="none">
        <Mono size={9} color={Colors.gold} style={{ letterSpacing: 9 * 0.16, textTransform: 'uppercase' }}>
          Gen {gen}{linje ? ` · ${linjeNavn[linje] ?? `Linje ${linje}`}` : ''}
        </Mono>
        <View style={{ flex: 1 }} />
        {focusPerson ? <Serif size={13} italic color={Colors.textMuted} numberOfLines={1} style={{ maxWidth: 155, fontFamily: Fonts.serifItalic }}>{focusPerson.name}</Serif> : null}
      </View>
      {/* Bund-hjælpetekst */}
      <Mono size={8} color="#bcae93" style={styles.snapHint} pointerEvents="none">
        træk ↕ generationer · ↔ søskende · tryk for profil
      </Mono>
    </View>
  );
}

// ── Delte små komponenter ────────────────────────────────────────────────────
function initial(name: string) { return name?.[0]?.toUpperCase() ?? '?'; }

function Segment({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.seg, active && styles.segActive]}>
      <BtnLabel size={12.5} color={active ? Colors.bordeaux : '#8a8170'}>{label}</BtnLabel>
    </Pressable>
  );
}

function LinjeChip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.linjeChip, active ? styles.linjeChipActive : styles.linjeChipIdle]}>
      <BtnLabel size={12} color={active ? Colors.paperCard : Colors.textSecondary2}>{label}</BtnLabel>
    </Pressable>
  );
}

function CenterKicker({ text, style }: { text: string; style?: object }) {
  return <Kicker size={9.5} color={Colors.textMuted2} style={[{ textAlign: 'center', letterSpacing: 9.5 * 0.14 }, style]}>{text}</Kicker>;
}

function Connector({ height, style }: { height: number; style?: object }) {
  return <View style={[styles.connector, { height }, style]} />;
}

function SiblingCard({ person, childCount, selected, onFocus, onOpen }: { person: ModelPerson; childCount: number; selected: boolean; onFocus: () => void; onOpen: () => void }) {
  return (
    <Pressable onPress={onFocus} style={[styles.sibCard, selected ? styles.sibCardSelected : styles.sibCardIdle]}>
      {selected ? <Mono size={8} color={Colors.bordeaux} style={{ position: 'absolute', top: 11, right: 12, letterSpacing: 0.8 }}>I FOKUS</Mono> : null}
      <View style={styles.sibAvatar}><Serif size={26} color={Colors.bordeaux}>{initial(person.name)}</Serif></View>
      <Serif size={23} style={{ marginTop: 12, lineHeight: 24 }}>{person.name}</Serif>
      {person.years ? <Mono size={10.5} color={Colors.textMuted} style={{ marginTop: 4 }}>{person.years}</Mono> : null}
      {person.title ? <BtnLabel size={12} color={Colors.bordeaux} style={{ marginTop: 6, fontFamily: Fonts.sansMedium }}>{person.title}</BtnLabel> : null}
      {childCount ? <Mono size={11} color={Colors.textSecondary2} style={{ marginTop: 8 }}>↓ {childCount} {childCount === 1 ? 'barn' : 'børn'}</Mono> : null}
      {selected ? <Pressable onPress={onOpen} style={styles.openBtn}><BtnLabel size={12} color={Colors.paperCard}>Åbn profil ›</BtnLabel></Pressable> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  head: { paddingHorizontal: 16, paddingTop: 14, paddingBottom: 4, backgroundColor: Colors.paperBg, zIndex: 20 },
  segment: { flexDirection: 'row', backgroundColor: Colors.beige3, borderRadius: 11, padding: 3, gap: 3 },
  seg: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 8 },
  segActive: { backgroundColor: Colors.paperCard, ...Shadow.card },
  linjeRow: { gap: 7, paddingVertical: 10, paddingRight: 16 },
  linjeChip: { paddingHorizontal: 13, paddingVertical: 6, borderRadius: 16, borderWidth: StyleSheet.hairlineWidth },
  linjeChipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  linjeChipIdle: { backgroundColor: Colors.beige, borderColor: Border.light },
  connector: { width: 1, backgroundColor: 'rgba(34,31,26,0.22)', alignSelf: 'center', marginVertical: 5 },
  grandPill: { alignSelf: 'center', flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: Colors.beige2, borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(34,31,26,0.07)', borderRadius: 20, paddingVertical: 7, paddingHorizontal: 14, opacity: 0.78, marginTop: 6 },
  parentCard: { alignSelf: 'center', maxWidth: '100%', flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: Colors.paperCard, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light, borderRadius: 14, paddingVertical: 11, paddingLeft: 12, paddingRight: 16, ...Shadow.card },
  parentAvatar: { width: 42, height: 42, borderRadius: Radius.round, backgroundColor: Colors.beige2, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  sibCard: { width: 178, borderRadius: 16, paddingVertical: 16, paddingHorizontal: 15, borderWidth: 1.5 },
  sibCardIdle: { backgroundColor: Colors.paperCard, borderColor: Border.light, ...Shadow.card },
  sibCardSelected: { backgroundColor: Colors.paperCard, borderColor: Colors.bordeaux, ...Shadow.cardSelected },
  sibAvatar: { width: 62, height: 62, borderRadius: Radius.round, backgroundColor: '#f4ece0', borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  openBtn: { marginTop: 13, alignSelf: 'flex-start', backgroundColor: Colors.bordeaux, borderRadius: 9, paddingVertical: 8, paddingHorizontal: 14 },
  childCard: { width: 138, backgroundColor: Colors.paperCard, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light, borderRadius: 13, padding: 13, ...Shadow.card },
  childAvatar: { width: 40, height: 40, borderRadius: Radius.round, backgroundColor: Colors.beige2, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  // Variant B
  bCard: { borderRadius: 12, padding: 12, borderWidth: 1.5 },
  bCardIdle: { backgroundColor: Colors.paperCard, borderColor: Border.light, ...Shadow.card },
  bCardSelected: { backgroundColor: Colors.paperCard, borderColor: Colors.bordeaux, ...Shadow.cardSelected },
  // Fallback-ring (ubevist generations-nabo): dæmpet gul kant+baggrund, adskiller sig klart fra
  // bevist parentsOf-kæde (bCardIdle/bCardSelected) — spejler web (Folgesvend.tsx §Kolonner).
  bCardFallback: { borderRadius: 12, padding: 12, borderWidth: 1.5, borderStyle: 'dashed', borderColor: Colors.gold, backgroundColor: '#faf1dc' },
  bAvatar: { width: 34, height: 34, borderRadius: Radius.round, backgroundColor: '#f4ece0', borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  bOpenBtn: { marginTop: 10, backgroundColor: Colors.bordeaux, borderRadius: 8, paddingVertical: 7, alignItems: 'center' },
  // Variant C
  snapContainer: { flex: 1, overflow: 'hidden', backgroundColor: Colors.paperBg },
  spineSeg: { position: 'absolute', left: '50%', marginLeft: -0.75, bottom: 0, width: 1.5, height: GAP_V, backgroundColor: 'rgba(34,31,26,0.13)' },
  routeSeg: { width: 2, marginLeft: -1, backgroundColor: Colors.bordeaux }, // rød rute-tråd-segment
  wayBadge: { position: 'absolute', left: 0, right: 0, top: '50%', marginTop: -94 - FRAME_NUDGE, alignItems: 'center' },
  wayPill: { backgroundColor: Colors.paperCard, borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(136,26,51,0.30)', borderRadius: 14, paddingVertical: 5, paddingHorizontal: 12, ...Shadow.card },
  snapSpacer: { width: CARD_W, height: CARD_H },
  snapCard: { width: CARD_W, height: CARD_H, backgroundColor: Colors.paperCard, borderWidth: 1.5, borderColor: Border.medium, borderRadius: 15, paddingHorizontal: 14, justifyContent: 'center', ...Shadow.card },
  snapCardMe: { borderColor: Colors.bordeaux, borderWidth: 2 }, // mig-kortet: rød ring
  snapAvatar: { width: 34, height: 34, borderRadius: Radius.round, backgroundColor: Colors.beige2, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  // marginTop = -(højde/2) - FRAME_NUDGE; nudge løfter rammen op så det centrerede kort lander inni den.
  snapFrame: { position: 'absolute', left: '50%', top: '50%', width: 166, height: 118, marginLeft: -83 + FRAME_NUDGE_X, marginTop: -59 - FRAME_NUDGE, borderWidth: 1.5, borderColor: Colors.bordeaux, borderRadius: 18 },
  snapTop: { position: 'absolute', top: 0, left: 0, right: 0, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingTop: 9, paddingBottom: 16 },
  snapHint: { position: 'absolute', bottom: 10, left: 0, right: 0, textAlign: 'center', letterSpacing: 8 * 0.08, textTransform: 'uppercase' },
});
