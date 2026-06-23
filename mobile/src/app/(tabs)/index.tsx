// Forside — Slægts-portal (README §5.1). Tro port af v2-designet
// (design/design/Reventlow-folgesvend-v2.dc.html, linje 57-145): slægts-chip m. crest-krans,
// hero m. dekorativt skjold-SVG + tæller-dividers, fremhævet person, "din plads", udforsk-liste
// 01–06 m. tællere, footer m. DAF-logo. Live-data fra store.
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Path } from 'react-native-svg';
import { CrestRing } from '../../components/CrestRing';
import { LoadGate } from '../../components/LoadGate';
import { Rise } from '../../components/Rise';
import { Body, BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { counts } from '../../data/selectors';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';

const SLAEGT = 'Reventlow';
const CREST = 'R';
const INTRO =
  'En digital følgesvend til det trykte værk — slå op, følg slægtens grene, og find din egen plads i træet.';

export default function HomeScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const featuredId = useStore((s) => s.focusId);
  const meId = useStore((s) => s.meId);

  const c = counts(model, aux);
  const featured = featuredId && model ? model.byId[featuredId] : null;
  const me = meId && model ? model.byId[meId] : null;

  // Udforsk-liste 01–06 med tællere (jf. v2-logik). ready=false = udskudt skærm.
  const sections = [
    { num: '01', title: 'Stamtræ', sub: 'Naviger op, ned og til siden i slægten', count: `${c.personer} personer`, href: '/tree', ready: true },
    { num: '02', title: 'Om slægten', sub: 'Historisk indledning til stamtavlen', count: '', href: '/about', ready: false },
    { num: '03', title: 'Godser & ejendomme', sub: 'Besiddelser og deres ejere gennem tiden', count: c.godser ? `${c.godser} godser` : '', href: '/estates', ready: false },
    { num: '04', title: 'Slægtens våben', sub: 'Det autoriserede våben og øvrige gengivelser', count: '', href: '/arms', ready: false },
    { num: '05', title: 'Er vi i familie?', sub: 'Find slægtskabet mellem to personer', count: '', href: '/relate', ready: true },
    { num: '06', title: 'Søg', sub: 'Bladr blandt registrerede personer', count: '', href: '/search', ready: true },
  ];

  return (
    <LoadGate>
      <ScrollView
        style={{ backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top, paddingBottom: 40 }}>
        {/* Slægts-chip */}
        <View style={{ padding: 16, paddingBottom: 0 }}>
          <Rise index={0}>
            <Pressable style={styles.slaegtChip} onPress={() => router.push('/search')}>
              <CrestRing letter={CREST} size={31} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <Kicker size={8.5} color={Colors.textMuted2}>Slægt</Kicker>
                <Serif size={18} style={{ lineHeight: 18 }}>{SLAEGT}</Serif>
              </View>
              <BtnLabel color={Colors.bordeaux} size={12}>skift ▾</BtnLabel>
            </Pressable>
          </Rise>
        </View>

        {/* Hero */}
        <View style={{ padding: 22, position: 'relative' }}>
          <Svg
            viewBox="0 0 100 120"
            width={132}
            height={158}
            style={{ position: 'absolute', top: 6, right: -6, opacity: 0.13 }}>
            <Path d="M10,8 H90 V58 C90,90 50,113 50,113 C50,113 10,90 10,58 Z" stroke={Colors.bordeaux} strokeWidth={1.4} fill="none" />
            <Path d="M19,18 H81 V57 C81,82 50,100 50,100 C50,100 19,82 19,57 Z" stroke={Colors.gold} strokeWidth={1} fill="none" />
          </Svg>

          <View style={{ position: 'relative', zIndex: 1 }}>
            <Rise index={0}>
              <Kicker size={9.5} color={Colors.gold} style={{ letterSpacing: 9.5 * 0.22, marginBottom: 9 }}>
                Danmarks Adels Aarbog
              </Kicker>
            </Rise>
            <Rise index={1}>
              <Serif size={46} italic color="#5a5246" style={{ lineHeight: 46 * 0.96, fontFamily: Fonts.serifItalic }}>
                Slægten
              </Serif>
              <Serif size={46} color={Colors.ink} style={{ lineHeight: 46 * 0.96 }}>{SLAEGT}</Serif>
            </Rise>
            <Rise index={2}>
              <View style={styles.rule} />
            </Rise>
            <Rise index={3}>
              <Body size={14} color={Colors.textSecondary2} style={{ maxWidth: 280, marginTop: 14 }}>
                {INTRO}
              </Body>
            </Rise>
            <Rise index={4}>
              <View style={styles.counters}>
                <Counter value={c.personer} label="personer" />
                <View style={styles.divider} />
                <Counter value={c.linjer} label="linjer" />
                <View style={styles.divider} />
                <Counter value={c.godser} label="godser" />
              </View>
            </Rise>
          </View>
        </View>

        {/* Fremhævet person */}
        {featured ? (
          <View style={{ paddingHorizontal: 18, paddingBottom: 4 }}>
            <Pressable style={styles.featured} onPress={() => router.push(`/person/${featured.id}`)}>
              <View style={styles.featuredAvatar}>
                <Serif size={22} color={Colors.bordeaux}>{featured.name[0]?.toUpperCase() ?? '?'}</Serif>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Kicker size={8.5} color={Colors.gold}>Fremhævet</Kicker>
                <Serif size={20} style={{ marginTop: 2, lineHeight: 21 }}>{featured.name}</Serif>
                {featured.title ? (
                  <Body size={12} color={Colors.bordeaux} style={{ marginTop: 3, fontFamily: Fonts.sansMedium }}>
                    {featured.title}
                  </Body>
                ) : null}
              </View>
              <Serif size={22} color={Colors.bordeaux}>›</Serif>
            </Pressable>
          </View>
        ) : null}

        {/* Din plads */}
        <View style={{ paddingHorizontal: 18, paddingTop: 12 }}>
          {me ? (
            <Pressable style={styles.mePlaceFilled} onPress={() => router.push(`/person/${me.id}`)}>
              <View style={styles.meAvatar}>
                <Serif size={18} color={Colors.bordeaux}>{me.name[0]?.toUpperCase()}</Serif>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Kicker size={8.5} color={Colors.bordeaux}>★ Din plads i slægten</Kicker>
                <Serif size={19} style={{ marginTop: 2, lineHeight: 20 }}>{me.name}</Serif>
              </View>
              <Serif size={20} color={Colors.bordeaux}>›</Serif>
            </Pressable>
          ) : (
            <Pressable style={styles.mePlaceDark} onPress={() => router.push('/search')}>
              <View style={styles.meQ}>
                <Serif size={17} color={Colors.goldLight}>?</Serif>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Serif size={18} color={Colors.paperBg} style={{ lineHeight: 20 }}>Hvem er du i slægten?</Serif>
                <Body size={12} color="#cabfa9" style={{ marginTop: 2 }}>Find dig selv i træet og markér din plads</Body>
              </View>
              <Serif size={18} color={Colors.goldLight}>›</Serif>
            </Pressable>
          )}
        </View>

        {/* Udforsk-liste */}
        <Mono size={10} color="#9a8f78" style={{ paddingHorizontal: 18, paddingTop: 20, letterSpacing: 10 * 0.16, textTransform: 'uppercase' }}>
          Udforsk slægten
        </Mono>
        <View style={{ paddingHorizontal: 18, paddingTop: 10 }}>
          {sections.map((row) => (
            <Pressable
              key={row.num}
              style={[styles.exploreRow, !row.ready && { opacity: 0.5 }]}
              disabled={!row.ready}
              onPress={() => router.push(row.href as never)}>
              <Serif size={16} italic color={Colors.gold} style={{ width: 22, fontFamily: Fonts.serifItalic }}>{row.num}</Serif>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Serif size={21} style={{ lineHeight: 22 }}>{row.title}</Serif>
                <Body size={12.5} color={Colors.textSecondary2} style={{ marginTop: 1 }}>
                  {row.ready ? row.sub : 'Kommer snart'}
                </Body>
              </View>
              {row.ready && row.count ? <Mono size={10} color={Colors.textMuted2}>{row.count}</Mono> : null}
              <Serif size={20} color="#bcae93">›</Serif>
            </Pressable>
          ))}
        </View>

        {/* Footer */}
        <View style={styles.footer}>
          <Image source={require('../../../assets/daf-logo.png')} style={{ width: 72, height: 72 }} contentFit="contain" />
          <View style={{ alignItems: 'center' }}>
            <Serif size={21} style={{ lineHeight: 23 }}>Danmarks Adels Aarbog</Serif>
            <Body size={12} color="#8a8170" style={{ marginTop: 4 }}>Udgivet af Dansk Adels Forening</Body>
          </View>
          <Mono size={9.5} color={Colors.textMuted3} style={{ letterSpacing: 9.5 * 0.04, textAlign: 'center' }}>
            Live-data fra Adelsårbogens base · proof of concept
          </Mono>
        </View>
      </ScrollView>
    </LoadGate>
  );
}

function Counter({ value, label }: { value: number; label: string }) {
  return (
    <View>
      <Serif size={27} color={Colors.bordeaux} style={{ lineHeight: 27 }}>{value}</Serif>
      <Mono size={9} color={Colors.textMuted2} style={{ letterSpacing: 9 * 0.08, textTransform: 'uppercase', marginTop: 3 }}>
        {label}
      </Mono>
    </View>
  );
}

const styles = StyleSheet.create({
  slaegtChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 7,
    paddingVertical: 9,
    paddingHorizontal: 13,
    ...Shadow.card,
  },
  rule: { width: 46, height: 1.5, backgroundColor: Colors.bordeaux, marginTop: 16 },
  counters: { flexDirection: 'row', gap: 22, marginTop: 20, alignItems: 'stretch' },
  divider: { width: 1, backgroundColor: Border.medium },
  featured: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: Colors.beige,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(34,31,26,0.09)',
    borderRadius: 15,
    paddingVertical: 14,
    paddingHorizontal: 15,
  },
  featuredAvatar: {
    width: 54,
    height: 54,
    borderRadius: Radius.round,
    backgroundColor: '#f4ece0',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.faint,
    alignItems: 'center',
    justifyContent: 'center',
  },
  mePlaceFilled: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    backgroundColor: Colors.paperCard,
    borderWidth: 1.5,
    borderColor: Colors.bordeaux,
    borderRadius: 15,
    paddingVertical: 13,
    paddingHorizontal: 15,
  },
  meAvatar: {
    width: 46,
    height: 46,
    borderRadius: Radius.round,
    backgroundColor: Colors.bordeauxFillLight,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(136,26,51,0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  mePlaceDark: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    backgroundColor: Colors.ink,
    borderRadius: 15,
    paddingVertical: 14,
    paddingHorizontal: 16,
  },
  meQ: {
    width: 34,
    height: 34,
    borderRadius: Radius.round,
    borderWidth: 1.5,
    borderColor: Colors.goldLight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  exploreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 15,
    paddingHorizontal: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.light,
  },
  footer: {
    marginTop: 14,
    paddingVertical: 26,
    paddingHorizontal: 22,
    paddingBottom: 30,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: Border.light,
    alignItems: 'center',
    gap: 12,
  },
});
