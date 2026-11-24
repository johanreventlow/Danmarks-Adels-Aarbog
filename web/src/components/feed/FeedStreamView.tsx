// Feed-strøm — web-udgaven (fase1-design.md §7, webredesign fase 4). Monteres på hovedsiden
// (HomeView.tsx). Bygger sin egen FeedAux af estates/arms (allerede hentet af Folgesvend.tsx),
// henter bio, livsdato, hændelser, historier og nævnt-grundlag ved mount og deler først ud, når
// alle er afgjort. Ingen uendelig rulning: seks blade ad gangen bag knappen »Vend seks blade
// mere«, hvert parti som egen blok i op til tre spalter.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  bookmarkPersonId, createFeedStream, resumeStream, TEMP_DISABLED_KINDS,
  type FeedCard, type FeedPinInput, type FeedStream, type HaendelserBy, type LivsdatoBy,
  type NaevntGrundlag, type StorieBy,
} from '@daa/feed';
import { radius } from '@daa/theme';
import { buildWebFeedAux, hentFeedBios, withFeedBios } from '../../data/feedAux';
import { hentForsideData } from '../../data/forside/klient';
import { udpakForsideData } from '../../data/forside/udpak';
import { fetchNaevntGrundlag } from '../../data/feedGrundlag';
import { BLADE_PR_UDDELING, delUd, iBlokke } from '../../data/feedUddeling';
import { epochDay, newSeed, todayISO } from '../../data/feedSession';
import { loadLivsdatoBy } from '../../data/livsdato';
import { loadHaendelserBy } from '../../data/haendelser';
import { loadStorieBy } from '../../data/story';
import { preserveShownForResume } from '../../data/feedResume';
import { createSeenStore, toSeenWeights } from '../../data/seenCards';
import {
  fetchFeedMediaCandidates, resolveFeedMediaForCards,
  type FeedMediaCandidatesByPerson, type FeedMediaRequest, type WebFeedMediaByCard,
} from '../../data/feedMedia';
import { T } from '../../theme';
import { personPath, estatePath, pathForMode } from '../../data/nav';
import type { ArmsItem, EstateItem } from '../../data/public';
import type { Model } from '../../data/types';
import { FeedCardView } from './FeedCardView';

const SEEN_EXCLUDED_KINDS = new Set<FeedCard['kind']>(['slaegt', 'dagensperson', 'samle']);
// Loftet for første uddeling: før #421 fejlede biografierne efter gæsternes 3 s-loft, så feedet kom
// reelt frem efter ~3 s. Nu lykkes de, men først efter ~10-12 s — fristen holder den gamle ventetid.
export const FEED_FOERSTE_UDDELING_FRIST_MS = 2500;

// Hvor peger et feed-kort hen, som en adresserbar sti? null = målet ligger bevidst uden for
// URL-grammatikken (Slægtskabsfanens A/B-par, browse-tilstand), og så får kortet intet anker —
// et href ville love en side der ikke findes.
export function hrefForCard(card: FeedCard): string | null {
  switch (card.kind) {
    case 'portrait': case 'citat': case 'arkiv': case 'historie': case 'embede':
    case 'jubilaeum': case 'paadennedag': case 'dagensperson': case 'naevnt':
      return personPath(card.personId);
    case 'gods': return estatePath(card.estateId);
    case 'vaaben': return pathForMode('arms');
    case 'slaegt': case 'forbundet': case 'samle': return null;
  }
}

export function FeedStreamView({
  model, estates, arms, meId, focusId, feedPins, bookmarkedIds,
  bookmarksReady, bookmarkHydrationVersion, bookmarkOwnerId,
  hasBookmark, onSaveBookmark,
  onOpenPerson, onOpenEstate, onOpenArms, onOpenSlaegt, onBrowseAll,
}: {
  model: Model;
  estates: EstateItem[] | null;
  arms: ArmsItem[] | null;
  meId: string | null;
  focusId: string | null;
  feedPins: FeedPinInput[];
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

  // Bio + livsdato + hændelser + stories + nævnt-grundlag hentes ved mount (§7.3). Første
  // uddeling venter, til ALLE er afgjort (hentet eller fejlet) — dog højst FEED_FOERSTE_UDDELING_FRIST_MS:
  // efter #421 tager biografierne ~10-12 s i prod, og gæsten må ikke stirre på »Henter blade« så
  // længe. null = venter. Sene ankomster genopbygger med samme seed og resume-kontrakten nedenfor —
  // viste kort nulstilles aldrig, så de første blade kan mangle biografi; de næste har den.
  const [bios, setBios] = useState<Record<string, string> | null>(null);
  const [bioError, setBioError] = useState<string | null>(null);
  // Falsk, når en bid af biografierne blev ved med at fejle: feedet viser resten uden fejlbanner, men bruger ikke
  // biografierne som bevis for fravær (nævnt-kort).
  const [biosKomplet, setBiosKomplet] = useState(false);
  const [livsdatoBy, setLivsdatoBy] = useState<LivsdatoBy | null>(null);
  const [haendelserBy, setHaendelserBy] = useState<HaendelserBy | null>(null);
  const [storieBy, setStorieBy] = useState<StorieBy | null>(null);
  const [naevntGrundlag, setNaevntGrundlag] = useState<NaevntGrundlag | 'fejlet' | null>(null);
  const [fristUdloebet, setFristUdloebet] = useState(false);
  useEffect(() => {
    let alive = true;
    const canon = model.canonicalIdById ?? {};
    setFristUdloebet(false);
    const frist = setTimeout(() => { if (alive) setFristUdloebet(true); }, FEED_FOERSTE_UDDELING_FRIST_MS);
    setBios(null);
    setBioError(null);
    setBiosKomplet(false);
    setLivsdatoBy(null);
    setHaendelserBy(null);
    setStorieBy(null);
    setNaevntGrundlag(null);
    // Den direkte hentning: i dag kun tilbagefald, når den færdigpakkede fil mangler (kold cache, fejl, for gammel).
    const direkte = () => {
      void hentFeedBios(canon, model.persons.map((p) => p.id)).then(
        (b) => { if (alive) { setBios(b.bioBy); setBiosKomplet(b.komplet); } },
        (e) => { if (alive) { console.warn('[feed] biografier fejlede:', e); setBioError(String((e as Error)?.message ?? e)); } },
      );
      // Loaderne sluger selv deres fejl (tomt = degraderet feed); .catch er kun et værn, så en
      // uventet afvisning aldrig lader første uddeling vente for evigt.
      void loadLivsdatoBy(canon).catch(() => ({})).then((ld) => { if (alive) setLivsdatoBy(ld); });
      void loadHaendelserBy(canon).catch(() => ({})).then((hs) => { if (alive) setHaendelserBy(hs); });
      void loadStorieBy(canon).catch(() => ({})).then((stories) => { if (alive) setStorieBy(stories); });
      void fetchNaevntGrundlag(canon).then(
        (g) => { if (alive) setNaevntGrundlag(g); },
        (e) => { if (alive) { console.warn('[feed] nævnt-grundlag fejlede — ingen nævnt-kort:', e); setNaevntGrundlag('fejlet'); } },
      );
    };
    // Forsidens færdigpakkede fil (spec 2026-11-24-forside-data-cache-design.md): én fil fra Vercels CDN i stedet for
    // 100+ kald. Kommer den inden for 2 s, er alle kilder afgjort med det samme; ellers hentes som før.
    void hentForsideData().then((fd) => {
      if (!alive) return;
      if (!fd) { direkte(); return; }
      let u: ReturnType<typeof udpakForsideData>;
      try {
        u = udpakForsideData(fd, { canonicalIdById: canon, persons: model.persons });
      } catch (e) {
        console.warn('[feed] forside-filen kunne ikke pakkes ud — henter direkte:', e);
        direkte();
        return;
      }
      if (u.bios) { setBios(u.bios.bioBy); setBiosKomplet(u.bios.komplet); } else setBioError('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
      setLivsdatoBy(u.livsdatoBy);
      setHaendelserBy(u.haendelserBy);
      setStorieBy(u.storieBy);
      setNaevntGrundlag(u.naevntGrundlag);
    });
    return () => { alive = false; clearTimeout(frist); };
  }, [model]);
  const alleAfgjort = (bios !== null || bioError !== null)
    && livsdatoBy !== null && haendelserBy !== null && storieBy !== null && naevntGrundlag !== null;
  const dataAfgjort = fristUdloebet || alleAfgjort;
  const alleAfgjortRef = useRef(alleAfgjort);
  alleAfgjortRef.current = alleAfgjort;
  // Nævnt-kort kræver, at hver kilde til fravær er hentet komplet. En tom bio-mængde tæller som
  // fejlet (hentFeedBios kan give {} ved en fejl i den gamle kontrakt), ikke som »ingen har tekst«; det samme gør et
  // ufuldstændigt resultat (en bid ramte gæsteloftet).
  const naevntInput = bios !== null && biosKomplet && Object.keys(bios).length > 0 && naevntGrundlag !== null
    && naevntGrundlag !== 'fejlet'
    ? naevntGrundlag
    : undefined;

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
  const feedMediaRequests = useMemo<FeedMediaRequest[]>(() => shown.flatMap((card) => {
    // Et nævnt-kort er netop personen uden mere end navnet — intet billede på det blad.
    if (!('personId' in card) || card.kind === 'naevnt') return [];
    return [{ cardId: card.id, kind: card.kind, personId: model.canonicalIdById?.[card.personId] ?? card.personId }];
  }), [shown, model.canonicalIdById]);
  const feedMediaPersonIds = useMemo(() => [...new Set(feedMediaRequests.map((request) => request.personId))], [feedMediaRequests]);
  const [mediaCandidatesByPerson, setMediaCandidatesByPerson] = useState<FeedMediaCandidatesByPerson>({});
  const [mediaByCard, setMediaByCard] = useState<WebFeedMediaByCard>({});
  const requestedPersonIdsRef = useRef<Set<string>>(new Set());
  const mediaContextVersionRef = useRef(0);

  // Medier følger den viste side, men må aldrig deltage i streamens opbygning eller resume.
  // Ved ejerskifte nulstilles både cache og allerede reserverede id'er før næste auth-kontekst
  // må hente; hvert asynkront løb annulleres desuden lokalt mod sene svar.
  useEffect(() => {
    const contextVersion = ++mediaContextVersionRef.current;
    setMediaCandidatesByPerson({});
    setMediaByCard({});
    requestedPersonIdsRef.current.clear();
    return () => {
      if (mediaContextVersionRef.current === contextVersion) mediaContextVersionRef.current += 1;
    };
  }, [bookmarkOwnerId]);

  useEffect(() => {
    const missingIds = feedMediaPersonIds.filter((personId) => !requestedPersonIdsRef.current.has(personId));
    if (missingIds.length === 0) return;
    missingIds.forEach((personId) => requestedPersonIdsRef.current.add(personId));
    const contextVersion = mediaContextVersionRef.current;
    void fetchFeedMediaCandidates(missingIds, model.canonicalIdById ?? {}).then((received) => {
      if (mediaContextVersionRef.current === contextVersion) {
        setMediaCandidatesByPerson((current) => ({ ...current, ...received }));
      }
    });
  }, [feedMediaPersonIds, model.canonicalIdById, bookmarkOwnerId]);

  useEffect(() => {
    let alive = true;
    void resolveFeedMediaForCards(feedMediaRequests, mediaCandidatesByPerson).then((resolved) => {
      if (alive) setMediaByCard(resolved);
    });
    return () => { alive = false; };
  }, [feedMediaRequests, mediaCandidatesByPerson, bookmarkOwnerId]);
  const markedIdsRef = useRef<Set<string>>(new Set());
  // streamRef holder DEN STRØM der aktuelt doseres fra — genopbygget (via resumeStream, se
  // nedenfor) ved sene ændringer i input, uden at nulstille viste kort.
  const streamRef = useRef<FeedStream | null>(null);
  const streamOwnerRef = useRef<string | null | undefined>(undefined);
  const [done, setDone] = useState(false);

  // Et blad regnes som set, når mindst halvdelen af det har været på skærmen (observatøren
  // nedenfor) — ikke allerede ved uddelingen, så et feed under skærmkanten ikke markerer noget
  // (projektejerens valg 12/11). Hukommelsen er frosset for denne visning (§5.3), så markeringen
  // påvirker først næste besøg — derfor »fortsætter hvor du slap«.
  const markAsSeen = useCallback((cards: readonly FeedCard[]) => {
    const ids = cards
      .filter((c) => !SEEN_EXCLUDED_KINDS.has(c.kind) && !markedIdsRef.current.has(c.id))
      .map((c) => c.id);
    if (ids.length === 0) return;
    ids.forEach((id) => markedIdsRef.current.add(id));
    seenStoreRef.current.markSeen(ids, epochDay());
  }, []);

  useEffect(() => {
    if (!dataAfgjort || seenWeights === null || !bookmarkSnapshotReady || !bookmarkSnapshot) return;
    const enrichedModel = bios ? withFeedBios(model, bios) : model;
    const built = createFeedStream(enrichedModel, aux, {
      seed, todayISO: today, meId, focusId,
      bookmarkedIds: bookmarkSnapshot.ids,
      seenWeights,
      livsdatoBy: livsdatoBy ?? {}, haendelserBy: haendelserBy ?? {}, storieBy: storieBy ?? {},
      pins: feedPins,
      disabledKinds: TEMP_DISABLED_KINDS,
      naevntGrundlag: naevntInput,
    });
    if (streamRef.current === null || streamOwnerRef.current !== bookmarkSnapshot.ownerId) {
      // En tidlig uddeling (fristen, før alle kilder er afgjort) viser kun egentlige blade. Samlekortet beskriver
      // den endelige pulje og fjernes alligevel ved genopbygningen; er der intet andet, ventes der på næste kilde —
      // ellers står feedet med 0 blade efter genopbygningen (prod 22/11).
      const first = alleAfgjort ? delUd(built, []) : delUd(built, []).filter((c) => c.kind !== 'samle');
      if (first.length === 0 && !alleAfgjort) return;
      streamRef.current = built;
      streamOwnerRef.current = bookmarkSnapshot.ownerId;
      markedIdsRef.current.clear();
      shownRef.current = first;
      setShown(first);
    } else {
      // Rebuild pga. bio/livsdato/hændelses-ankomst (SAMME seed) — resume, aldrig nulstil.
      const preserved = preserveShownForResume(shownRef.current);
      if (preserved.length !== shownRef.current.length) {
        shownRef.current = preserved;
        setShown(preserved);
      }
      streamRef.current = resumeStream(built, new Set(preserved.map((c) => c.id)));
      if (preserved.length < BLADE_PR_UDDELING) {
        // En tidlig uddeling kan have givet færre end en hel portion (puljen var tynd uden biografier og hændelser).
        // Fyld første portion op, når data kommer — ellers bliver gæsten stående med de få blade fra fristen.
        const fyld = delUd(streamRef.current, preserved, BLADE_PR_UDDELING - preserved.length)
          .filter((c) => alleAfgjort || c.kind !== 'samle');
        if (fyld.length > 0) {
          shownRef.current = [...preserved, ...fyld];
          setShown(shownRef.current);
        }
      }
    }
    // »Du har vendt alle dagens blade« først, når alle kilder er afgjort — en tidlig pulje er ikke dagens pulje.
    setDone(alleAfgjort && streamRef.current.done());
    // Live bookmarkedIds er bevidst ikke input her: bookmarkSnapshot fryses efter hydrering,
    // så et toggle midt i læsningen ikke omordner strømmen. shownRef læses tilsvarende via ref.
  }, [model, bios, aux, seed, today, meId, focusId, bookmarkSnapshotReady, bookmarkSnapshot, seenWeights, livsdatoBy, haendelserBy, storieBy, feedPins, dataAfgjort, alleAfgjort, naevntInput, markAsSeen]);

  // »Vend seks blade mere«: næste parti som egen blok; fokus flyttes til den nye blok, så
  // tastatur- og skærmlæserbrugere står ved de nye blade og ikke ved knappen under dem.
  const blokRefs = useRef<Map<number, HTMLElement>>(new Map());
  const [fokusBlok, setFokusBlok] = useState<number | null>(null);
  const vendFlere = useCallback(() => {
    const stream = streamRef.current;
    if (!stream || stream.done()) return;
    // Før alle kilder er afgjort, hører samlekortet ikke hjemme midt i strømmen (se uddelingen ovenfor).
    const next = delUd(stream, shownRef.current).filter((c) => alleAfgjortRef.current || c.kind !== 'samle');
    const blokIndex = Math.ceil(shownRef.current.length / BLADE_PR_UDDELING);
    shownRef.current = [...shownRef.current, ...next];
    setShown(shownRef.current);
    setDone(alleAfgjortRef.current && stream.done());
    if (next.length > 0) setFokusBlok(blokIndex);
  }, []);
  useEffect(() => {
    if (fokusBlok === null) return;
    blokRefs.current.get(fokusBlok)?.focus();
    setFokusBlok(null);
  }, [fokusBlok]);
  const harSetFoer = seenWeights !== null && Object.keys(seenWeights).length > 0;

  // Synligheds-observatør: markerer et blad som set, første gang mindst halvdelen er på skærmen.
  // Den implicitte rod (viewport) tager højde for den indre rulle-containers beskæring. Uden
  // IntersectionObserver (fx jsdom) markeres intet — hellere for lidt »set« end for meget.
  // Genskabes ved ejerskifte, så den nye ejer får sine egne markeringer.
  const feedRef = useRef<HTMLDivElement | null>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);
  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const obs = new IntersectionObserver((entries) => {
      const synlige = entries.filter((e) => e.isIntersecting && e.intersectionRatio >= 0.5);
      if (synlige.length === 0) return;
      const ids = new Set(synlige.map((e) => (e.target as HTMLElement).dataset.kortId));
      synlige.forEach((e) => obs.unobserve(e.target));
      markAsSeen(shownRef.current.filter((c) => ids.has(c.id)));
    }, { threshold: 0.5 });
    observerRef.current = obs;
    feedRef.current?.querySelectorAll('[data-kort-id]').forEach((el) => obs.observe(el));
    return () => { obs.disconnect(); observerRef.current = null; };
  }, [markAsSeen, bookmarkOwnerId]);
  const observerKort = useCallback((el: HTMLDivElement | null) => {
    if (el) observerRef.current?.observe(el);
  }, []);

  const openCard = useCallback((card: FeedCard) => {
    switch (card.kind) {
      case 'portrait': case 'citat': case 'arkiv': case 'historie': case 'embede': case 'jubilaeum': case 'paadennedag': case 'dagensperson': case 'naevnt':
        onOpenPerson(card.personId); break;
      case 'gods': onOpenEstate(card.estateId); break;
      case 'vaaben': onOpenArms(); break;
      case 'slaegt': onOpenSlaegt(card.aId, card.bId); break;
      case 'forbundet': case 'samle': onBrowseAll(); break;
    }
  }, [onOpenPerson, onOpenEstate, onOpenArms, onOpenSlaegt, onBrowseAll]);

  const blokke = iBlokke(shown);
  return (
    <div ref={feedRef}>
      {bioError ? (
        <div role="alert" style={{ marginBottom: 14, padding: 14, color: T.bordeaux, background: T.surfaceRaised, border: '1px solid rgba(136,26,51,.25)' }}>
          <strong>Kunne ikke hente feedets biografier</strong>
          <div style={{ marginTop: 4 }}>Nogle blade vises uden biografi. Prøv at genindlæse siden om lidt.</div>
        </div>
      ) : null}
      {shown.length === 0 && !done ? (
        <p role="status" style={{ margin: '18px 0', fontSize: 14, color: T.inkMuted }}>Henter blade fra Aarbogen …</p>
      ) : null}
      {blokke.map((blok, i) => (
        // Hver uddeling er sin egen blok; spalterne (op til tre) fyldes inden for blokken, så et
        // nyt parti aldrig flytter rundt på de blade, der allerede står ovenover.
        <section
          key={blok[0].id}
          ref={(el) => { if (el) blokRefs.current.set(i, el); else blokRefs.current.delete(i); }}
          tabIndex={-1}
          aria-label={`Blade ${i * BLADE_PR_UDDELING + 1}–${i * BLADE_PR_UDDELING + blok.length}`}
          style={{ columns: '3 260px', columnGap: 18, marginBottom: 18, outline: 'none' }}
        >
          {blok.map((card) => {
            const pid = bookmarkPersonId(card);
            const modelPerson = 'personId' in card ? model.byId[card.personId] : null;
            const fallbackName = 'personId' in card && 'name' in card ? card.name : ('personId' in card ? `#${card.personId}` : '');
            const fallbackYears = 'personId' in card && 'years' in card ? card.years : '';
            return (
              <div key={card.id} ref={observerKort} data-kort-id={card.id} style={{ breakInside: 'avoid', marginBottom: 18 }}>
                <FeedCardView
                  card={card}
                  person={'personId' in card ? {
                    name: modelPerson?.name ?? fallbackName,
                    years: modelPerson?.years ?? fallbackYears,
                  } : undefined}
                  media={mediaByCard[card.id] ?? []}
                  bookmarked={pid ? hasBookmark(pid) : false}
                  onSave={onSaveBookmark}
                  onOpen={openCard}
                  href={hrefForCard(card)}
                />
              </div>
            );
          })}
        </section>
      ))}
      {shown.length > 0 ? (
        <div style={{ padding: '10px 0 28px', textAlign: 'center' }}>
          {done ? (
            <p style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>
              Du har vendt alle dagens blade.{' '}
              <button type="button" onClick={onBrowseAll} style={{ ...tekstKnap }}>Se hele registret</button>
            </p>
          ) : (
            <>
              <button type="button" onClick={vendFlere} style={vendKnap}>Vend seks blade mere</button>
              {harSetFoer ? (
                <p style={{ margin: '8px 0 0', fontSize: 13, color: T.inkMuted }}>Feedet fortsætter, hvor du slap.</p>
              ) : null}
            </>
          )}
        </div>
      ) : null}
    </div>
  );
}

const vendKnap = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '12px 22px', borderRadius: radius.field, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' } as const;
const tekstKnap = { font: 'inherit', padding: 0, border: 0, background: 'none', color: T.bordeaux, textDecoration: 'underline', cursor: 'pointer' } as const;
