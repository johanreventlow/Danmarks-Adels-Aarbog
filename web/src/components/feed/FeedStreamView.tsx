// Feed-strøm — web-udgaven (fase1-design.md §7). Monteres under forsidens hero/kuraterede
// sektion (HomeView.tsx). Bygger sin egen FeedAux af estates/arms (allerede hentet af
// Folgesvend.tsx), henter bio + livsdato asynkront ved mount, og doserer via en sentinel i
// bunden (scroll-lytter på den rigtige scroll-container, se §-note nedenfor — ikke
// IntersectionObserver, jf. §7.4's forslag; se begrundelse ved sentinel-opsætningen). Én
// kolonne, centreret, ~680px — redaktionel ro, ikke et masonry-dashboard.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  bookmarkPersonId, createFeedStream, resumeStream,
  type FeedCard, type FeedStream, type LivsdatoBy,
} from '@daa/feed';
import { buildWebFeedAux, fetchFeedBios, withFeedBios } from '../../data/feedAux';
import { epochDay, newSeed, todayISO } from '../../data/feedSession';
import { loadLivsdatoBy } from '../../data/livsdato';
import { preserveShownForResume } from '../../data/feedResume';
import { createSeenStore, toSeenWeights } from '../../data/seenCards';
import { T } from '../../theme';
import type { ArmsItem, EstateItem } from '../../data/public';
import type { Model } from '../../data/types';
import { FeedCardView } from './FeedCardView';

const PAGE_SIZE = 12;
const SEEN_EXCLUDED_KINDS = new Set<FeedCard['kind']>(['slaegt', 'dagensperson', 'samle']);

export function FeedStreamView({
  model, estates, arms, meId, focusId, bookmarkedIds,
  bookmarksReady, bookmarkHydrationVersion, bookmarkOwnerId,
  hasBookmark, onSaveBookmark,
  onOpenPerson, onOpenEstate, onOpenArms, onOpenSlaegt, onBrowseAll,
}: {
  model: Model;
  estates: EstateItem[] | null;
  arms: ArmsItem[] | null;
  meId: string | null;
  focusId: string | null;
  bookmarkedIds: string[];
  bookmarksReady: boolean;
  bookmarkHydrationVersion: number;
  bookmarkOwnerId: string | null;
  hasBookmark: (id: string) => boolean;
  onSaveBookmark: (id: string) => void;
  onOpenPerson: (id: string) => void;
  onOpenEstate: (id: string) => void;
  onOpenArms: () => void;
  onOpenSlaegt: (aId: string, bId: string) => void;
  onBrowseAll: () => void;
}) {
  const aux = useMemo(() => buildWebFeedAux(estates, arms), [estates, arms]);
  const today = useMemo(() => todayISO(), []);
  const [seed] = useState(() => newSeed(today));

  // Frys bogmærker EFTER repository-hydrering. En live toggle må ikke omordne en igangværende
  // strøm, men et bruger-/login-skift skal have sit eget snapshot og må aldrig genbruge den
  // forrige brugers personalisering.
  const [bookmarkSnapshot, setBookmarkSnapshot] = useState<{
    ownerId: string | null;
    hydrationVersion: number;
    ids: string[];
  } | null>(null);
  const bookmarkSnapshotReady = bookmarksReady
    && bookmarkSnapshot?.ownerId === bookmarkOwnerId
    && bookmarkSnapshot.hydrationVersion === bookmarkHydrationVersion;
  useEffect(() => {
    if (!bookmarksReady) return;
    setBookmarkSnapshot((prev) => (
      prev?.ownerId === bookmarkOwnerId && prev.hydrationVersion === bookmarkHydrationVersion
        ? prev
        : {
            ownerId: bookmarkOwnerId,
            hydrationVersion: bookmarkHydrationVersion,
            ids: [...bookmarkedIds],
          }
    ));
  }, [bookmarksReady, bookmarkOwnerId, bookmarkHydrationVersion, bookmarkedIds]);

  // Bio + livsdato hentes ÉN gang ved mount (§7.3) — webbens publikums-model indlæser
  // ikke bio ved cold-start, og livsdato er altid en klient-side ekstra-hentning.
  const [bios, setBios] = useState<Record<string, string> | null>(null);
  const [livsdatoBy, setLivsdatoBy] = useState<LivsdatoBy>({});
  useEffect(() => {
    let alive = true;
    const canon = model.canonicalIdById ?? {};
    void fetchFeedBios(canon, model.persons.map((p) => p.id)).then((b) => { if (alive) setBios(b); });
    void loadLivsdatoBy(canon).then((ld) => { if (alive) setLivsdatoBy(ld); });
    return () => { alive = false; };
  }, [model]);

  // Set-hukommelse: hentes ÉN gang ved mount og fryses for hele visningens levetid (§5.3).
  const [seenWeights, setSeenWeights] = useState<Record<string, number> | null>(null);
  const seenStoreRef = useRef(createSeenStore());
  useEffect(() => {
    let alive = true;
    void seenStoreRef.current.load().then((seen) => { if (alive) setSeenWeights(toSeenWeights(seen, epochDay())); });
    return () => { alive = false; };
  }, []);

  const [shown, setShown] = useState<FeedCard[]>([]);
  const shownRef = useRef<FeedCard[]>([]);
  useEffect(() => { shownRef.current = shown; }, [shown]);
  const markedIdsRef = useRef<Set<string>>(new Set());
  // streamRef holder DEN STRØM der aktuelt doseres fra — genopbygget (via resumeStream, se
  // nedenfor) hver gang bio/livsdato ankommer, uden at nulstille allerede viste kort.
  const streamRef = useRef<FeedStream | null>(null);
  const streamOwnerRef = useRef<string | null | undefined>(undefined);
  const [done, setDone] = useState(false);

  // Bumpes ved hver (gen)opbygning af streamRef.current (ren ref-mutation, ingen re-render i
  // sig selv) — bruges KUN som et signal til fill-effekten nedenfor om at genvurdere, uden at
  // gøre streamRef selv til reaktiv state.
  const [streamGeneration, setStreamGeneration] = useState(0);

  useEffect(() => {
    if (seenWeights === null || !bookmarkSnapshotReady || !bookmarkSnapshot) return;
    const enrichedModel = bios ? withFeedBios(model, bios) : model;
    const built = createFeedStream(enrichedModel, aux, {
      seed, todayISO: today, meId, focusId,
      bookmarkedIds: bookmarkSnapshot.ids,
      seenWeights, livsdatoBy,
    });
    if (streamRef.current === null || streamOwnerRef.current !== bookmarkSnapshot.ownerId) {
      streamRef.current = built;
      streamOwnerRef.current = bookmarkSnapshot.ownerId;
      const first = built.next(PAGE_SIZE);
      shownRef.current = first;
      markedIdsRef.current.clear();
      setShown(first);
    } else {
      // Rebuild pga. bio/livsdato-ankomst (SAMME seed) — resume, ALDRIG nulstil viste kort.
      const preserved = preserveShownForResume(shownRef.current);
      if (preserved.length !== shownRef.current.length) {
        shownRef.current = preserved;
        setShown(preserved);
      }
      streamRef.current = resumeStream(built, new Set(preserved.map((c) => c.id)));
    }
    setDone(streamRef.current.done());
    setStreamGeneration((g) => g + 1);
    // Live bookmarkedIds er bevidst ikke input her: bookmarkSnapshot fryses efter hydrering,
    // så et toggle midt i scroll ikke omordner strømmen. shownRef læses tilsvarende via ref.
  }, [model, bios, aux, seed, today, meId, focusId, bookmarkSnapshotReady, bookmarkSnapshot, seenWeights, livsdatoBy]);

  const markShownAsSeen = useCallback(() => {
    const ids = shownRef.current
      .filter((c) => !SEEN_EXCLUDED_KINDS.has(c.kind) && !markedIdsRef.current.has(c.id))
      .map((c) => c.id);
    if (ids.length === 0) return;
    ids.forEach((id) => markedIdsRef.current.add(id));
    seenStoreRef.current.markSeen(ids, epochDay());
  }, []);

  const appendingRef = useRef(false);
  const handleEndReached = useCallback(() => {
    const stream = streamRef.current;
    if (!stream || appendingRef.current || stream.done()) return;
    appendingRef.current = true;
    markShownAsSeen(); // det netop udscrollede parti regnes som set (§7-approksimation af viewability)
    const next = stream.next(PAGE_SIZE);
    setShown((prev) => [...prev, ...next]);
    setDone(stream.done());
    appendingRef.current = false;
  }, [markShownAsSeen]);

  // VIGTIGT: siden scroller IKKE i window/body (Folgesvend.tsx's rodlayout er
  // `height:100vh; overflow:hidden`, med den faktiske scroll i en indre
  // `<div data-scroll>`-container). Dosering er derfor bundet til DENNE container, ikke
  // vinduet. To komplementære udløsere holder sentinellen dækket:
  // 1) et 'scroll'-lytter-tjek på selve containeren (synkront, ingen browser-batching) —
  //    dækker ægte brugerscroll.
  // 2) en efterkontrol når `shown`/streamGeneration ændrer sig (§-note nedenfor) — dækker
  //    "kort indhold fylder ikke skærmen" og "en strøm-rebuild uden scroll".
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  const checkAndFill = useCallback(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const scrollEl = el.closest('[data-scroll]');
    const viewportRect = scrollEl ? scrollEl.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
    const rect = el.getBoundingClientRect();
    // 400px margin (spec §7.4): begynd at hente FØR sentinellen er bogstaveligt synlig.
    const inView = rect.top < viewportRect.bottom + 400 && rect.bottom > viewportRect.top - 400;
    if (inView) handleEndReached();
  }, [handleEndReached]);

  useEffect(() => {
    const el = sentinelRef.current;
    const scrollEl = el?.closest('[data-scroll]');
    if (!scrollEl) return;
    scrollEl.addEventListener('scroll', checkAndFill, { passive: true });
    return () => scrollEl.removeEventListener('scroll', checkAndFill);
  }, [checkAndFill]);

  // "Fyld skærmen"-efterkontrol: kører efter hver commit hvor `shown` eller streamGeneration
  // ændrer sig — inkl. efter handleEndReached's egen setShown, hvilket giver en selv-
  // terminerende "fyld indtil enten skærmen er fuld eller strømmen er tom"-løkke ved
  // mount/rebuild, uden at afhænge af at brugeren rent faktisk scroller (fx efter bios
  // ankommer, hvor sentinellen kan stå ubevæget men strømmen nu har mere at give).
  useEffect(() => {
    checkAndFill();
  }, [shown, streamGeneration, checkAndFill]);

  const openCard = useCallback((card: FeedCard) => {
    switch (card.kind) {
      case 'portrait': case 'citat': case 'embede': case 'jubilaeum': case 'paadennedag': case 'dagensperson':
        onOpenPerson(card.personId); break;
      case 'gods': onOpenEstate(card.estateId); break;
      case 'vaaben': onOpenArms(); break;
      case 'slaegt': onOpenSlaegt(card.aId, card.bId); break;
      case 'forbundet': case 'samle': onBrowseAll(); break;
    }
  }, [onOpenPerson, onOpenEstate, onOpenArms, onOpenSlaegt, onBrowseAll]);

  return (
    <div style={{ maxWidth: 680, margin: '0 auto' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        {shown.map((card) => {
          const pid = bookmarkPersonId(card);
          return (
            <FeedCardView
              key={card.id}
              card={card}
              bookmarked={pid ? hasBookmark(pid) : false}
              onSave={onSaveBookmark}
              onOpen={openCard}
            />
          );
        })}
      </div>
      <div ref={sentinelRef} style={{ height: 1 }} />
      <FeedFooter done={done} />
    </div>
  );
}

function FeedFooter({ done }: { done: boolean }) {
  return (
    <div style={{ padding: '28px 0', textAlign: 'center', fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted2 }}>
      {done ? 'Du har mødt hele slægten i dag — udforsk registeret' : 'Henter flere blade fra slægten'}
    </div>
  );
}
