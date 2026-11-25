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
import {
  bookmarkPersonId, createFeedStream, TEMP_DISABLED_KINDS, type FeedCard, type FeedStream,
} from '@daa/feed';
import { counts } from '../../data/selectors';
import { epochDay, newSeed, todayISO } from '../../lib/feedSession';
import { FEED_FOERSTE_UDDELING_FRIST_MS, foersteUddeling, genoptag, naesteSide } from '../../lib/feedUddeling';
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
  // Biografierne hentes i baggrunden efter load (se useStore). Forsidens minimumskrav læser bio, så et feed bygget
  // før de er der, er tyndt — se fristen og genoptagelsen nedenfor.
  const biosStatus = useStore((s) => s.biosStatus);
  const loadEpoch = useStore((s) => s.loadEpoch);

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
  // bogmærke midt i scroll — det ville omordne resten af strømmen. Snapshottet
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

  // Første uddeling venter højst FEED_FOERSTE_UDDELING_FRIST_MS på biografierne (spejl af web bfef23bb): de tager
  // ~10 s i prod efter modellen, og læseren må ikke stirre på en tom forside så længe. Fristen regnes fra, at
  // bio-hentningen starter (biosStatus 'loading'), ikke fra modellen — dens identitet skifter, når biografierne
  // stemples ind. Den nulstilles ikke: efter første uddeling genoptages strømmen alligevel (se nedenfor).
  const alleAfgjort = biosStatus === 'komplet' || biosStatus === 'delvis' || biosStatus === 'fejl';
  // Fristen hører til én indlæsning: efter »Prøv igen« (ny loadEpoch) gælder en ny frist.
  const [fristUdloebetEpoch, setFristUdloebetEpoch] = useState<number | null>(null);
  const fristUdloebet = fristUdloebetEpoch === loadEpoch;
  useEffect(() => {
    if (biosStatus !== 'loading') return;
    const epoch = loadEpoch;
    const t = setTimeout(() => setFristUdloebetEpoch(epoch), FEED_FOERSTE_UDDELING_FRIST_MS);
    return () => clearTimeout(t);
  }, [biosStatus, loadEpoch]);

  // streamRef holder DEN strøm, der doseres fra. FeedStream.next() MUTERER cursoren, så strømmen er en ref, ikke en
  // afledt værdi. Nyt seed (pull-to-refresh) eller ny bogmærke-ejer = ny strøm fra toppen; enhver anden ændring i
  // input (biografierne kommer, pins, fokus, bogmærke-hydrering) genopbygger med SAMME seed og genoptager efter de
  // viste kort — kortene under læserens finger nulstilles aldrig midt i scroll.
  const streamRef = useRef<FeedStream | null>(null);
  const streamNoegleRef = useRef<string | null>(null);
  const shownRef = useRef<readonly FeedCard[]>([]);
  const [shown, setShown] = useState<readonly FeedCard[]>([]);
  const [done, setDone] = useState(false);
  const appendingRef = useRef(false);
  const [appending, setAppending] = useState(false);

  // Modellen ryddes ved logout/brugerskift (review 37 M5): de viste kort hører til den forrige models personer (evt.
  // redaktørens levende) og må ikke stå, til den nye model har biografier nok til en uddeling.
  useEffect(() => {
    if (model) return;
    streamRef.current = null;
    streamNoegleRef.current = null;
    shownRef.current = [];
    // eslint-disable-next-line react-hooks/set-state-in-effect -- ryd de viste kort sammen med den eksterne strøm
    setShown([]);
    setDone(false);
  }, [model]);

  useEffect(() => {
    if (!model || !aux || seenWeights === null || !bookmarkSnapshotReady || !bookmarkedSnapshot) return;
    // Intet at uddele endnu: stop en evt. pull-to-refresh-spinner; de viste kort bliver stående (review fund 2).
    // eslint-disable-next-line react-hooks/set-state-in-effect -- synkronisering med den eksterne strøm, som nedenfor
    if (!alleAfgjort && !fristUdloebet) { setRefreshing(false); return; }
    const built = createFeedStream(model, aux, {
      seed, todayISO: today, meId, focusId,
      bookmarkedIds: bookmarkedSnapshot.ids,
      seenWeights,
      livsdatoBy,
      haendelserBy,
      storieBy,
      pins: feedPins,
      disabledKinds: TEMP_DISABLED_KINDS,
      // Forsidens minimumskrav (spec 2026-11-24-forside-minimumskrav-design.md), samme motor som web.
      forsideKrav: true,
    });
    // loadEpoch i nøglen: en ny indlæsning (fx live efter offline-seed) starter forfra, så eksempelpersonernes kort
    // ikke bliver hængende i det levende feed (review fund 1). Biografierne skifter ikke epoken og genoptager blot.
    const noegle = `${seed}|${bookmarkedSnapshot.ownerId ?? ''}|${loadEpoch}`;
    if (streamRef.current === null || streamNoegleRef.current !== noegle) {
      // Uden biografier kvalificerer få personer sig til forsiden; finder fristen ingen egentlige blade, ventes der
      // på biografierne i stedet for at låse en tom strøm fast (web 79c0adc0).
      const first = foersteUddeling(built, PAGE_SIZE, alleAfgjort);
      if (first === null) { setRefreshing(false); return; }
      streamRef.current = built;
      streamNoegleRef.current = noegle;
      shownRef.current = first;
    } else {
      const r = genoptag(built, shownRef.current, PAGE_SIZE, alleAfgjort, streamRef.current.done());
      streamRef.current = r.stream;
      shownRef.current = r.shown;
    }
    // Ægte synkronisering med en ekstern, tilstandsfuld cursor — en effekt er det rigtige værktøj her.
    setShown(shownRef.current);
    // »Du har mødt hele slægten« først, når biografierne er afgjort — en tidlig pulje er ikke dagens pulje.
    setDone(alleAfgjort && streamRef.current.done());
    setRefreshing(false);
  }, [model, aux, seed, today, meId, focusId, bookmarkSnapshotReady, bookmarkedSnapshot, seenWeights, livsdatoBy, haendelserBy, storieBy, feedPins, alleAfgjort, fristUdloebet, loadEpoch]);

  const handleEndReached = useCallback(() => {
    if (!streamRef.current || appendingRef.current || streamRef.current.done()) return;
    appendingRef.current = true;
    setAppending(true);
    // stream.next() er synkron (ordningen er allerede beregnet, spec §3.5) — rAF giver blot
    // UI'et en renderet "henter"-frame frem for et usynligt 0ms-flip. Strømmen læses først i rAF: en
    // genopbygning imellem har måske skiftet den.
    requestAnimationFrame(() => {
      const stream = streamRef.current;
      if (stream) {
        shownRef.current = [...shownRef.current, ...naesteSide(stream, PAGE_SIZE, alleAfgjort)];
        setShown(shownRef.current);
        setDone(alleAfgjort && stream.done());
      }
      appendingRef.current = false;
      setAppending(false);
    });
  }, [alleAfgjort]);

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
        case 'naevnt':
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
      const person = pid ? model?.byId[pid] : null;
      return (
        <View style={ROW_STYLE}>
          <FeedCardView
            card={item}
            person={person ? { name: person.name, years: person.years } : undefined}
            rawMedia={pid ? aux?.mediaBy[pid] ?? [] : []}
            bookmarked={pid ? has(pid) : false}
            onSave={saveOrPrompt}
            onOpen={openCard}
          />
        </View>
      );
    },
    [model, aux, bookmarkOwnerId, has, saveOrPrompt, openCard],
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
      <View style={{ flex: 1, backgroundColor: Colors.surfaceGround }}>
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
          ListFooterComponent={<Footer state={appending ? 'appending' : done ? 'done' : 'more'} />}
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
        <Kicker size={9.5} color={Colors.goldInk} style={{ letterSpacing: 9.5 * 0.22, marginTop: 12 }}>
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
      <Mono size={8} color={Colors.inkMuted} style={{ letterSpacing: 8 * 0.08, textTransform: 'uppercase', marginTop: 3 }}>{label}</Mono>
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
        <Mono size={8.5} color={Colors.inkMuted} style={{ letterSpacing: 8.5 * 0.14, textTransform: 'uppercase', textAlign: 'center' }}>
          Du har mødt hele slægten i dag — udforsk registeret
        </Mono>
      </View>
    );
  }
  return (
    <View style={{ paddingVertical: 24, paddingHorizontal: 24, alignItems: 'center', flexDirection: 'row', justifyContent: 'center', gap: 8 }}>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
      <Mono size={8.5} color={Colors.inkMuted} style={{ letterSpacing: 8.5 * 0.14, textTransform: 'uppercase' }}>
        {state === 'appending' ? 'Henter flere blade …' : 'Henter flere blade fra slægten'}
      </Mono>
      <View style={{ width: 5, height: 5, borderRadius: 3, backgroundColor: '#c3b79d' }} />
    </View>
  );
}
