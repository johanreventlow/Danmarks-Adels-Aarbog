// Forside — det levende feed (fase1-design.md). Top-bar (hamburger + brand-på-scroll +
// bogmærke-badge) → kollapsende hero → doseret strøm af feed-kort. Nav-listen bor i
// MenuDrawer. Feed-motoren er @daa/feed (ren, seedet); al tilfældighed/tid samles i
// lib/feedSession.ts ved UI-randen — se kommentarerne der.
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList, type ListRenderItem, Pressable, RefreshControl, View,
  type ViewToken,
} from 'react-native';
import { HomeTopBar } from '../../components/HomeTopBar';
import { LoadGate } from '../../components/LoadGate';
import { MenuDrawer } from '../../components/MenuDrawer';
import { Rise } from '../../components/Rise';
import { SlaegtPicker } from '../../components/SlaegtPicker';
import { FeedCardView } from '../../components/feed/FeedCardView';
import { BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { bookmarkPersonId, createFeedStream, type FeedCard, type FeedStream } from '@daa/feed';
import { counts } from '../../data/selectors';
import { epochDay, newSeed, todayISO } from '../../lib/feedSession';
import { useBookmarks } from '../../lib/bookmarks';
import { createSeenStore, toSeenWeights } from '../../lib/seenCards';
import { selectMeId, useStore } from '../../store/useStore';
import { Border, Colors, Fonts } from '../../theme/tokens';

const SLAEGT = 'Reventlow';
const ROW_STYLE = { paddingHorizontal: 16, paddingTop: 13 } as const;
const PAGE_SIZE = 12;
// Kort af disse kinds er positionslåst (dagensperson/slaegt) eller rent talbaseret uden
// egen identitet (samle) — registreres ikke i set-hukommelsen (spec §5.3).
const SEEN_EXCLUDED_KINDS = new Set<FeedCard['kind']>(['slaegt', 'dagensperson', 'samle']);

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
  const livsdatoBy = useStore((s) => s.livsdatoBy);
  const haendelserBy = useStore((s) => s.haendelserBy);
  const storieBy = useStore((s) => s.storieBy);
  const feedPins = useStore((s) => s.feedPins);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [slaegtOpen, setSlaegtOpen] = useState(false);
  const [showBrand, setShowBrand] = useState(false);

  const bookmarkOwnerId = session?.user?.id ?? null;
  const {
    has, toggle, canSave, count, ready: bookmarksReady,
    hydrationVersion: bookmarkHydrationVersion, ids: bookmarkedIdSet,
  } = useBookmarks(bookmarkOwnerId, canonMap);
  const saveOrPrompt = useCallback(
    (id: string) => { if (canSave) toggle(id); else router.push('/konto'); },
    [canSave, toggle, router],
  );
  const c = counts(model, aux);

  // Bogmærke-id'er indgår som et FASTFROSSET SNAPSHOT (§4.1's "personal"-vægt), ikke en
  // live-reaktiv værdi: en stream må ALDRIG genopbygges bare fordi brugeren toggler et
  // bogmærke midt i scroll — det ville nulstille de allerede viste kort. Snapshottet
  // opdateres kun ved afsluttet repository-/kanon-map-hydrering eller når et NYT seed
  // vælges eksplicit (pull-to-refresh, se handleRefresh).
  const [bookmarkedSnapshot, setBookmarkedSnapshot] = useState<{
    ownerId: string | null;
    hydrationVersion: number;
    ids: string[];
  } | null>(null);
  const bookmarkSnapshotReady = bookmarksReady
    && bookmarkedSnapshot?.ownerId === bookmarkOwnerId
    && bookmarkedSnapshot.hydrationVersion === bookmarkHydrationVersion;
  useEffect(() => {
    if (!bookmarksReady) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- frys ét hydreret snapshot pr. bruger
    setBookmarkedSnapshot((prev) => (
      prev?.ownerId === bookmarkOwnerId && prev.hydrationVersion === bookmarkHydrationVersion
        ? prev
        : {
            ownerId: bookmarkOwnerId,
            hydrationVersion: bookmarkHydrationVersion,
            ids: [...bookmarkedIdSet],
          }
    ));
  }, [bookmarksReady, bookmarkOwnerId, bookmarkHydrationVersion, bookmarkedIdSet]);

  // Set-hukommelse: hentes ÉN gang ved mount og fryses for hele skærmens levetid (spec
  // §5.3) — også på tværs af senere reseeds (pull-to-refresh). null = endnu ikke hydreret.
  const [seenWeights, setSeenWeights] = useState<Record<string, number> | null>(null);
  const seenStoreRef = useRef(createSeenStore());
  useEffect(() => {
    let alive = true;
    void seenStoreRef.current.load().then((seen) => {
      if (alive) setSeenWeights(toSeenWeights(seen, epochDay()));
    });
    return () => { alive = false; };
  }, []);

  // Seed + dagsdato: dagsdatoen hentes ét sted (injicerbar via feedSession.ts); seedet er
  // sessions-lokalt og skifter kun ved mount eller eksplicit pull-to-refresh (§5.2).
  const today = useMemo(() => todayISO(), []);
  const [seed, setSeed] = useState(() => newSeed(today));
  const [refreshing, setRefreshing] = useState(false);

  const stream = useMemo<FeedStream | null>(() => {
    if (!model || !aux || seenWeights === null || !bookmarkSnapshotReady || !bookmarkedSnapshot) return null;
    return createFeedStream(model, aux, {
      seed, todayISO: today, meId, focusId,
      bookmarkedIds: bookmarkedSnapshot.ids,
      seenWeights,
      livsdatoBy,
      haendelserBy,
      storieBy,
      pins: feedPins,
    });
  }, [model, aux, seed, today, meId, focusId, bookmarkSnapshotReady, bookmarkedSnapshot, seenWeights, livsdatoBy, haendelserBy, storieBy, feedPins]);

  const [shown, setShown] = useState<FeedCard[]>([]);
  const appendingRef = useRef(false);
  const [appending, setAppending] = useState(false);

  // Ny strøm (mount ELLER reseed) → nulstil viste kort til strømmens første side. Ægte
  // synkronisering med en ekstern, tilstandsfuld cursor (FeedStream.next() MUTERER —
  // kan ikke udledes rent i render uden at fremrykke cursoren ved hvert (evt. kasserede)
  // render-forsøg) — en effekt er det rigtige værktøj her, ikke en afledt værdi.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setShown(stream ? stream.next(PAGE_SIZE) : []);
    setRefreshing(false);
  }, [stream]);

  const handleEndReached = useCallback(() => {
    if (!stream || appendingRef.current || stream.done()) return;
    appendingRef.current = true;
    setAppending(true);
    // stream.next() er synkron (ordningen er allerede beregnet, spec §3.5) — rAF giver blot
    // UI'et en renderet "henter"-frame frem for et usynligt 0ms-flip.
    requestAnimationFrame(() => {
      setShown((prev) => [...prev, ...stream.next(PAGE_SIZE)]);
      appendingRef.current = false;
      setAppending(false);
    });
  }, [stream]);

  const handleRefresh = useCallback(() => {
    setRefreshing(true);
    setBookmarkedSnapshot({
      ownerId: bookmarkOwnerId,
      hydrationVersion: bookmarkHydrationVersion,
      ids: [...bookmarkedIdSet],
    });
    setSeed(newSeed(today));
  }, [today, bookmarkOwnerId, bookmarkHydrationVersion, bookmarkedIdSet]);

  const openCard = useCallback(
    (card: FeedCard) => {
      switch (card.kind) {
        case 'portrait':
        case 'citat':
        case 'arkiv':
        case 'historie':
        case 'embede':
        case 'jubilaeum':
        case 'paadennedag':
        case 'dagensperson':
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

  // Stabile referencer til FlatList's viewabilityConfig/onViewableItemsChanged-props (RN
  // advarer/degraderer hvis disse skifter identitet mellem renders). useState-lazy-init
  // giver en stabil objekt-reference uden ref-læsning under render; useCallback m. tomme
  // deps giver en stabil funktion — seenStoreRef.current læses inde i callback-kroppen,
  // som kun kører når FlatList selv kalder den (event-kontekst, ikke render).
  const [viewabilityConfig] = useState({ itemVisiblePercentThreshold: 60, minimumViewTime: 500 });
  const onViewableItemsChanged = useCallback(({ viewableItems }: { viewableItems: ViewToken[] }) => {
    const ids = viewableItems
      .map((v) => v.item as FeedCard)
      .filter((card) => !SEEN_EXCLUDED_KINDS.has(card.kind))
      .map((card) => card.id);
    if (ids.length > 0) seenStoreRef.current.markSeen(ids, epochDay());
  }, []);

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
          data={shown}
          keyExtractor={(item) => item.id}
          onScroll={(e) => setShowBrand(e.nativeEvent.contentOffset.y > 120)}
          scrollEventThrottle={32}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={Colors.bordeaux} />}
          onEndReached={handleEndReached}
          onEndReachedThreshold={0.6}
          viewabilityConfig={viewabilityConfig}
          onViewableItemsChanged={onViewableItemsChanged}
          ListHeaderComponent={<Hero counts={c} onSkift={() => setSlaegtOpen(true)} />}
          ListFooterComponent={<Footer state={appending ? 'appending' : stream?.done() ? 'done' : 'more'} />}
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

// Footer med tre reelle tilstande (spec §5.1): 'appending' mens næste side hentes, 'done'
// når strømmen er udtømt (ærligt slutkort — ikke bare et loft), ellers 'more' (der ER mere,
// scroll for at hente det).
function Footer({ state }: { state: 'appending' | 'done' | 'more' }) {
  if (state === 'done') {
    return (
      <View style={{ paddingVertical: 24, paddingHorizontal: 24, alignItems: 'center' }}>
        <Mono size={8.5} color={Colors.textMuted2} style={{ letterSpacing: 8.5 * 0.14, textTransform: 'uppercase', textAlign: 'center' }}>
          Du har mødt hele slægten i dag — udforsk registeret
        </Mono>
      </View>
    );
  }
  return (
    <View style={{ paddingVertical: 24, paddingHorizontal: 24, alignItems: 'center', flexDirection: 'row', justifyContent: 'center', gap: 8 }}>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
      <Mono size={8.5} color={Colors.textMuted2} style={{ letterSpacing: 8.5 * 0.14, textTransform: 'uppercase' }}>
        {state === 'appending' ? 'Henter flere blade …' : 'Henter flere blade fra slægten'}
      </Mono>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
    </View>
  );
}
