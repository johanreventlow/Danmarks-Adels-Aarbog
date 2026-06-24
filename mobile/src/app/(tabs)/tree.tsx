// Stamtræ (README §5.2) — tre varianter + §9.2 linje-hop.
//  A · Fokus     — lodret kort-fokus (bedsteforælder→forælder→søskende→børn).
//  B · Kolonner  — vandret-scrollende drill-down kolonner, én pr. generation.
//  C · Spor      — fuldskærms gestus-navigeret slægtsspor (træk lodret=generation,
//                  vandret=søskende; tærskler 64/44px; haptik pr. spring).
import * as Haptics from 'expo-haptics';
import { useRouter } from 'expo-router';
import { useEffect, useMemo, useRef } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { buildColumns, childrenOf, treeFocusA, wayToMe } from '../../data/selectors';
import type { WayStep } from '../../data/selectors';
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

// ── Variant B · Kolonner ─────────────────────────────────────────────────────
function VariantB({ model, insets }: { model: Model; insets: { bottom: number } }) {
  const router = useRouter();
  const path = useStore((s) => s.path);
  const selectAt = useStore((s) => s.selectAt);
  const scrollRef = useRef<ScrollView>(null);
  const cols = useMemo(() => buildColumns(model, path), [model, path]);

  // Auto-scroll til nyeste kolonne. Keyer på hele stien (ikke kun .length): en re-selektion på
  // samme dybde der afslører en ny børne-kolonne ændrer ikke length, men skal stadig scrolle.
  const pathKey = path.join(',');
  useEffect(() => {
    const t = setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 60);
    return () => clearTimeout(t);
  }, [pathKey]);

  return (
    <View style={{ flex: 1, paddingTop: 8 }}>
      <Mono size={9.5} color={Colors.textMuted} style={{ paddingHorizontal: 16, paddingBottom: 4, letterSpacing: 9.5 * 0.12, textTransform: 'uppercase' }}>
        Træk til siden gennem generationerne ▸
      </Mono>
      <ScrollView ref={scrollRef} horizontal showsHorizontalScrollIndicator={false} style={{ flex: 1 }} contentContainerStyle={{ gap: 10, paddingHorizontal: 16, paddingVertical: 8, alignItems: 'stretch' }}>
        {cols.map((col) => (
          <View key={col.level} style={{ width: 166 }}>
            <Mono size={9} color={Colors.gold} style={{ letterSpacing: 9 * 0.1, textTransform: 'uppercase', paddingBottom: 2, marginBottom: 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light }}>
              Generation {col.level + 1}
            </Mono>
            <ScrollView style={{ flex: 1 }} showsVerticalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingBottom: insets.bottom + 90 }}>
            {col.people.map((p) => {
              const sel = p.id === col.selected;
              const hasKids = childrenOf(model, p.id).length > 0;
              return (
                <Pressable key={p.id} onPress={() => selectAt(col.level, p.id)} style={[styles.bCard, sel ? styles.bCardSelected : styles.bCardIdle]}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                    <View style={styles.bAvatar}><Serif size={15} color={Colors.bordeaux}>{initial(p.name)}</Serif></View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Serif size={16} style={{ lineHeight: 17 }} numberOfLines={2}>{p.name}</Serif>
                      {p.years ? <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{p.years}</Mono> : null}
                    </View>
                    {hasKids ? <Serif size={16} color="#bcae93">›</Serif> : null}
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
const ROWH = 118; // rækkehøjde (fokus-rammens højde)
const CARD_W = 150;
const CARD_H = 104;
const CARD_GAP = 14; // vandret mellemrum mellem søskende-kort
const HTHRESH = 64; // træk-tærskel: søskende
const VTHRESH = 44; // træk-tærskel: generation

function VariantC({ model, activeLinje, linjeByPerson, linjeNavn }: { model: Model; activeLinje: string | null; linjeByPerson: Record<string, string>; linjeNavn: Record<string, string> }) {
  const router = useRouter();
  const snapPath = useStore((s) => s.snapPath);
  const snapDepth = useStore((s) => s.snapDepth);
  const meId = useStore((s) => s.meId);
  const way = useMemo(
    () => (meId ? wayToMe(model, snapPath, snapDepth, meId) : undefined),
    [meId, model, snapPath, snapDepth],
  );
  // Hver generation (depth d) er en vandret række af ALLE søskende, centreret på den valgte
  // via balancerede spacer-pladser (padL/padR) — så søskende peeker i siderne. Port af
  // designets snapRows-logik (v2 linje 1273-1287).
  const rows = useMemo(() => {
    const maxD = snapPath.length - 1;
    const out: { d: number; padL: number; padR: number; sibIds: string[]; selId: string }[] = [];
    for (let d = 0; d <= maxD; d++) {
      const sibIds = d === 0 ? [snapPath[0]] : childrenOf(model, snapPath[d - 1]).map((p) => p.id);
      const selIndex = Math.max(0, sibIds.indexOf(snapPath[d]));
      const leftN = selIndex;
      const rightN = sibIds.length - 1 - selIndex;
      out.push({
        d,
        padL: Math.max(0, rightN - leftN),
        padR: Math.max(0, leftN - rightN),
        sibIds,
        selId: snapPath[d],
      });
    }
    return out;
  }, [model, snapPath]);

  // Stakken er forankret på vertikal midte (top:50%); translateY rykker den fokuserede række
  // til midten: -(snapDepth*STEPY + ROWH/2). Animeres .42s.
  const targetY = -(snapDepth * STEPY + ROWH / 2);
  const ty = useSharedValue(targetY);
  useEffect(() => {
    ty.value = withTiming(targetY, { duration: 420 });
  }, [targetY, ty]);
  const stackStyle = useAnimatedStyle(() => ({ transform: [{ translateY: ty.value }] }));

  // Gesten memoiseres STABILT: store-opdateringer (snapDepth ændres pr. step) re-renderer
  // komponenten, og en ny gesture-instans midt i et træk ville afbryde trækket (kun ét step
  // pr. swipe). Callbacks læser/kalder via useStore.getState() i stedet for closures over
  // skiftende state. Tryk håndteres her (ikke en indlejret Pressable, der ville kapre touch).
  const gesture = useMemo(() => {
    const haptic = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    const g: { x: number; y: number; axis: 'x' | 'y' | null } = { x: 0, y: 0, axis: null };
    const pan = Gesture.Pan()
      .runOnJS(true)
      .onBegin(() => { g.x = 0; g.y = 0; g.axis = null; })
      .onUpdate((e) => {
        const store = useStore.getState();
        if (!g.axis && (Math.abs(e.translationX) > 10 || Math.abs(e.translationY) > 10)) {
          g.axis = Math.abs(e.translationX) >= Math.abs(e.translationY) ? 'x' : 'y';
        }
        if (g.axis === 'x') {
          const dx = e.translationX - g.x;
          if (Math.abs(dx) >= HTHRESH) { store.moveSnapSib(dx < 0 ? 1 : -1); haptic(); g.x = e.translationX; }
        } else if (g.axis === 'y') {
          // Direkte-manipulation: træk fingeren op (dy<0) → stakken op → efterkommere (snapDepth+1).
          const dy = e.translationY - g.y;
          if (Math.abs(dy) >= VTHRESH) { store.moveSnapGen(dy < 0 ? 1 : -1); haptic(); g.y = e.translationY; }
        }
      });
    const tap = Gesture.Tap()
      .runOnJS(true)
      .maxDistance(10)
      .onEnd(() => {
        const { snapPath: sp, snapDepth: sd } = useStore.getState();
        const fid = sp[sd];
        if (fid) router.push(`/person/${fid}`);
      });
    return Gesture.Race(pan, tap);
  }, [router]);

  const focusPerson = snapPath[snapDepth] ? model.byId[snapPath[snapDepth]] : null;
  const gen = snapDepth + 1;
  const linje = focusPerson ? linjeByPerson[focusPerson.id] ?? activeLinje : activeLinje;

  return (
    <GestureDetector gesture={gesture}>
      <View style={styles.snapContainer}>
        {/* Lodret guide-linje — wayfinder mod eget kort */}
        {(meId == null || way) && (
          <View style={[styles.snapGuide, way ? styles.snapGuideLit : null]} pointerEvents="none" />
        )}
        {/* Kort-stak — ikke-interaktiv (pointerEvents none); al input går til gesten. */}
        <Animated.View style={[styles.snapStack, stackStyle]} pointerEvents="none">
          {rows.map((row) => (
            <View key={row.d} style={[styles.snapRow, { top: row.d * STEPY }]}>
              {Array.from({ length: row.padL }).map((_, i) => (
                <View key={`pl-${i}`} style={styles.snapSpacer} />
              ))}
              {row.sibIds.map((id) => {
                const p = model.byId[id];
                if (!p) return <View key={id} style={styles.snapSpacer} />;
                const isFocus = row.d === snapDepth && id === row.selId;
                return (
                  <View key={id} style={[styles.snapCard, { opacity: isFocus ? 1 : 0.55 }]}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 9 }}>
                      <View style={styles.snapAvatar}><Serif size={14} color={Colors.bordeaux}>{initial(p.name)}</Serif></View>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Serif size={17} style={{ lineHeight: 17 }} numberOfLines={1}>{p.name}</Serif>
                        {p.years ? <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{p.years}</Mono> : null}
                      </View>
                    </View>
                    {p.title ? <BtnLabel size={10.5} color={Colors.bordeaux} numberOfLines={1} style={{ marginTop: 7, fontFamily: Fonts.sansMedium }}>{p.title}</BtnLabel> : null}
                  </View>
                );
              })}
              {Array.from({ length: row.padR }).map((_, i) => (
                <View key={`pr-${i}`} style={styles.snapSpacer} />
              ))}
            </View>
          ))}
        </Animated.View>
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
    </GestureDetector>
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
  bAvatar: { width: 34, height: 34, borderRadius: Radius.round, backgroundColor: '#f4ece0', borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  bOpenBtn: { marginTop: 10, backgroundColor: Colors.bordeaux, borderRadius: 8, paddingVertical: 7, alignItems: 'center' },
  // Variant C
  snapContainer: { flex: 1, overflow: 'hidden', backgroundColor: Colors.paperBg },
  snapGuide: { position: 'absolute', left: '50%', top: 0, bottom: 0, width: 2, marginLeft: -1, backgroundColor: 'rgba(136,26,51,0.16)' },
  snapGuideLit: { backgroundColor: 'rgba(136,26,51,0.40)' },
  wayBadge: { position: 'absolute', left: 0, right: 0, top: '50%', marginTop: -94, alignItems: 'center' },
  wayPill: { backgroundColor: Colors.paperCard, borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(136,26,51,0.30)', borderRadius: 14, paddingVertical: 5, paddingHorizontal: 12, ...Shadow.card },
  snapStack: { position: 'absolute', left: 0, right: 0, top: '50%' },
  snapRow: { position: 'absolute', left: 0, right: 0, height: ROWH, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: CARD_GAP },
  snapSpacer: { width: CARD_W, height: CARD_H },
  snapCard: { width: CARD_W, height: CARD_H, backgroundColor: Colors.paperCard, borderWidth: 1.5, borderColor: Border.medium, borderRadius: 15, paddingHorizontal: 14, justifyContent: 'center', ...Shadow.card },
  snapAvatar: { width: 34, height: 34, borderRadius: Radius.round, backgroundColor: Colors.beige2, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center' },
  snapFrame: { position: 'absolute', left: '50%', top: '50%', width: 166, height: 118, marginLeft: -83, marginTop: -59, borderWidth: 1.5, borderColor: Colors.bordeaux, borderRadius: 18 },
  snapTop: { position: 'absolute', top: 0, left: 0, right: 0, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingTop: 9, paddingBottom: 16 },
  snapHint: { position: 'absolute', bottom: 10, left: 0, right: 0, textAlign: 'center', letterSpacing: 8 * 0.08, textTransform: 'uppercase' },
});
