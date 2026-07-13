// Forside — redaktionelt feed (v3, spec §4). Top-bar (hamburger + brand-på-scroll + bogmærke-
// badge) → kollapsende hero → FlatList af feed-kort. Nav-listen bor nu i MenuDrawer.
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { FlatList, type ListRenderItem, Pressable, View } from 'react-native';
import { HomeTopBar } from '../../components/HomeTopBar';
import { LoadGate } from '../../components/LoadGate';
import { MenuDrawer } from '../../components/MenuDrawer';
import { Rise } from '../../components/Rise';
import { SlaegtPicker } from '../../components/SlaegtPicker';
import { FeedCardView } from '../../components/feed/FeedCardView';
import { BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { bookmarkPersonId, buildFeed, type FeedCard } from '../../data/buildFeed';
import { counts } from '../../data/selectors';
import { useBookmarks } from '../../lib/bookmarks';
import { selectMeId, useStore } from '../../store/useStore';
import { Border, Colors, Fonts } from '../../theme/tokens';

const SLAEGT = 'Reventlow';
// Aktuelt år som eneste ikke-rene input til buildFeed (jubilæums-beregning). Injiceres eksplicit.
const CURRENT_YEAR = new Date().getFullYear();
const ROW_STYLE = { paddingHorizontal: 16, paddingTop: 13 } as const;

export default function HomeScreen() {
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const meId = useStore(selectMeId);
  const focusId = useStore((s) => s.focusId);
  const canonMap = useStore((s) => s.canonicalIdById);
  const session = useStore((s) => s.session);
  const setRelA = useStore((s) => s.setRelA);
  const setRelB = useStore((s) => s.setRelB);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [slaegtOpen, setSlaegtOpen] = useState(false);
  const [showBrand, setShowBrand] = useState(false);

  const { has, toggle, canSave, count } = useBookmarks(session?.user?.id ?? null, canonMap);
  const saveOrPrompt = useCallback(
    (id: string) => { if (canSave) toggle(id); else router.push('/konto'); },
    [canSave, toggle, router],
  );
  const c = counts(model, aux);
  const feed = useMemo(
    () => (model && aux ? buildFeed(model, aux, { meId, focusId, today: CURRENT_YEAR }) : []),
    [model, aux, meId, focusId],
  );

  const openCard = useCallback(
    (card: FeedCard) => {
      switch (card.kind) {
        case 'portrait':
        case 'citat':
        case 'embede':
        case 'jubilaeum':
          router.push(`/person/${card.personId}`);
          break;
        case 'gods':
          router.push(`/estate/${card.estateId}`);
          break;
        case 'vaaben':
          router.push('/arms');
          break;
        case 'slaegt':
          setRelA(card.aId);
          setRelB(card.bId);
          router.push('/relate');
          break;
        case 'forbundet':
        case 'samle':
          router.push('/search');
          break;
      }
    },
    [router, setRelA, setRelB],
  );

  const renderItem = useCallback<ListRenderItem<FeedCard>>(
    ({ item }) => {
      const pid = bookmarkPersonId(item);
      return (
        <View style={ROW_STYLE}>
          <FeedCardView
            card={item}
            bookmarked={pid ? has(pid) : false}
            onSave={saveOrPrompt}
            onOpen={openCard}
          />
        </View>
      );
    },
    [has, saveOrPrompt, openCard],
  );

  return (
    <LoadGate>
      <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
        <HomeTopBar
          onMenu={() => setDrawerOpen(true)}
          onBookmarks={() => router.push('/bogmaerker')}
          savedCount={count}
          showBrand={showBrand}
        />
        <FlatList
          data={feed}
          keyExtractor={(item) => item.id}
          onScroll={(e) => setShowBrand(e.nativeEvent.contentOffset.y > 120)}
          scrollEventThrottle={32}
          ListHeaderComponent={<Hero counts={c} onSkift={() => setSlaegtOpen(true)} />}
          ListFooterComponent={<Footer />}
          renderItem={renderItem}
        />
        <MenuDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
        <SlaegtPicker visible={slaegtOpen} personCount={c.personer} onClose={() => setSlaegtOpen(false)} />
      </View>
    </LoadGate>
  );
}

function Hero({ counts: c, onSkift }: { counts: ReturnType<typeof counts>; onSkift: () => void }) {
  return (
    <View style={{ padding: 22, paddingBottom: 8, alignItems: 'center' }}>
      <Rise index={0}>
        <Image source={require('../../../assets/daf-logo.png')} style={{ width: 60, height: 60 }} contentFit="contain" />
      </Rise>
      <Rise index={1}>
        <Kicker size={9.5} color={Colors.gold} style={{ letterSpacing: 9.5 * 0.22, marginTop: 12 }}>
          Danmarks Adels Aarbog
        </Kicker>
      </Rise>
      <Rise index={2}>
        <Serif size={40} italic color="#5a5246" style={{ marginTop: 5, lineHeight: 40, fontFamily: Fonts.serifItalic }}>Slægten</Serif>
        <Serif size={40} color={Colors.ink} style={{ lineHeight: 40, textAlign: 'center' }}>{SLAEGT}</Serif>
      </Rise>
      <View style={{ width: 46, height: 1.5, backgroundColor: Colors.bordeaux, marginTop: 15 }} />
      <View style={{ flexDirection: 'row', gap: 22, marginTop: 16, alignItems: 'center' }}>
        <Counter value={c.personer} label="personer" />
        <View style={{ width: 1, height: 26, backgroundColor: Border.medium }} />
        <Counter value={c.linjer} label="linjer" />
        <View style={{ width: 1, height: 26, backgroundColor: Border.medium }} />
        <Counter value={c.godser} label="godser" />
      </View>
      <Pressable onPress={onSkift} style={{ marginTop: 15 }}>
        <BtnLabel size={12} color={Colors.bordeaux}>skift slægt ▾</BtnLabel>
      </Pressable>
    </View>
  );
}

function Counter({ value, label }: { value: number; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Serif size={24} color={Colors.bordeaux} style={{ lineHeight: 24 }}>{value}</Serif>
      <Mono size={8} color={Colors.textMuted2} style={{ letterSpacing: 8 * 0.08, textTransform: 'uppercase', marginTop: 3 }}>{label}</Mono>
    </View>
  );
}

function Footer() {
  return (
    <View style={{ paddingVertical: 24, paddingHorizontal: 24, alignItems: 'center', flexDirection: 'row', justifyContent: 'center', gap: 8 }}>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
      <Mono size={8.5} color={Colors.textMuted2} style={{ letterSpacing: 8.5 * 0.14, textTransform: 'uppercase' }}>
        Henter flere blade fra slægten
      </Mono>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
    </View>
  );
}
