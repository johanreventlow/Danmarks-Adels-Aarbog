// Feed-strøm — web-udgaven (fase1-design.md §7). Monteres under forsidens hero/kuraterede
// sektion (HomeView.tsx). Bygger sin egen FeedAux af estates/arms (allerede hentet af
// Folgesvend.tsx), henter bio + livsdato asynkront ved mount, og doserer via en
// IntersectionObserver-sentinel i bunden. Én kolonne, centreret, ~680px — redaktionel ro,
// ikke et masonry-dashboard.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  bookmarkPersonId, createFeedStream, resumeStream,
  type FeedCard, type FeedStream, type LivsdatoBy,
} from '@daa/feed';
import { buildWebFeedAux, fetchFeedBios, withFeedBios } from '../../data/feedAux';
import { epochDay, newSeed, todayISO } from '../../data/feedSession';
import { loadLivsdatoBy } from '../../data/livsdato';
import { createSeenStore, toSeenWeights } from '../../data/seenCards';
import { T } from '../../theme';
import type { ArmsItem, EstateItem } from '../../data/public';
import type { Model } from '../../data/types';
import { FeedCardView } from './FeedCardView';

const PAGE_SIZE = 12;
const SEEN_EXCLUDED_KINDS = new Set<FeedCard['kind']>(['slaegt', 'dagensperson', 'samle']);

export function FeedStreamView({
  model, estates, arms, meId, focusId, bookmarkedIds,
  hasBookmark, onSaveBookmark,
  onOpenPerson, onOpenEstate, onOpenArms, onOpenSlaegt, onBrowseAll,
}: {
  model: Model;
  estates: EstateItem[] | null;
  arms: ArmsItem[] | null;
  meId: string | null;
  focusId: string | null;
  bookmarkedIds: string[];
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

  // Bio + livsdato hentes ÉN gang ved mount (§7.3) — webbens publikums-model indlæser
  // ikke bio ved cold-start, og livsdato er altid en klient-side ekstra-hentning.
  const [bios, setBios] = useState<Record<string, string> | null>(null);
  const [livsdatoBy, setLivsdatoBy] = useState<LivsdatoBy>({});
  useEffect(() => {
    let alive = true;
    const canon = model.canonicalIdById ?? {};
    void fetchFeedBios(canon).then((b) => { if (alive) setBios(b); });
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
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (seenWeights === null) return; // vent på hydrering — undgår at bygge to gange
    const enrichedModel = bios ? withFeedBios(model, bios) : model;
    const built = createFeedStream(enrichedModel, aux, {
      seed, todayISO: today, meId, focusId, bookmarkedIds, seenWeights, livsdatoBy,
    });
    if (streamRef.current === null) {
      streamRef.current = built;
      setShown(built.next(PAGE_SIZE));
    } else {
      // Rebuild pga. bio/livsdato-ankomst (SAMME seed) — resume, ALDRIG nulstil viste kort.
      streamRef.current = resumeStream(built, new Set(shownRef.current.map((c) => c.id)));
    }
    setDone(streamRef.current.done());
    // bookmarkedIds er BEVIDST ikke i dependency-listen (§4.1): en stream må ikke genopbygges/
    // nulstilles bare fordi brugeren toggler et bogmærke midt i scroll — det ville nulstille de
    // allerede viste kort. shownRef læses via ref, ikke som reaktiv dependency, af samme grund.
  }, [model, bios, aux, seed, today, meId, focusId, seenWeights, livsdatoBy]);

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

  const sentinelRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      (entries) => { if (entries[0]?.isIntersecting) handleEndReached(); },
      { rootMargin: '400px' },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [handleEndReached]);

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
