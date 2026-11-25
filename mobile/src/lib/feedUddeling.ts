// Forsidens uddeling, når biografierne kommer sent (spejl af web's FeedStreamView, bfef23bb + 79c0adc0).
// Modellen er klar efter ~10-12 s i prod, biografierne ~10 s senere. Første uddeling venter derfor højst
// FEED_FOERSTE_UDDELING_FRIST_MS på dem og bygger så strømmen af det, der er. Når biografierne kommer, bygges
// strømmen om med SAMME seed og genoptages efter de viste kort — de kort, læseren allerede ser, nulstilles aldrig.
// Rene funktioner, så forløbet kan testes uden komponenten.
import { bookmarkPersonId, resumeStream, type FeedCard, type FeedStream } from '@daa/feed';

export const FEED_FOERSTE_UDDELING_FRIST_MS = 2500;

// Positionslåste kort, der kun må stå én gang i en visning. Deres id følger personen (dagens person vælges blandt
// forsidens værdige personer, som biografierne ændrer), så en genopbygget ordning kan vælge et andet kort af samme slags.
const EN_PR_VISNING = new Set<FeedCard['kind']>(['dagensperson', 'slaegt']);

// Samlekortet beskriver den endelige rest-pulje og står sidst. Før alle kilder er afgjort, er puljen ikke dagens pulje:
// kortet holdes tilbage, og den genopbyggede strøm leverer sit eget til sidst.
const udenSamle = (cards: readonly FeedCard[]): FeedCard[] => cards.filter((c) => c.kind !== 'samle');

// Næste side fra strømmen. Før kilderne er afgjort deles samlekortet ikke ud.
export function naesteSide(stream: FeedStream, n: number, afgjort: boolean): FeedCard[] {
  const side = stream.next(n);
  return afgjort ? side : udenSamle(side);
}

// Første uddeling. null = vent: fristen fandt ingen egentlige blade (kun samlekortet, eller intet), så strømmen må
// ikke låses fast — ellers står forsiden tom, når genopbygningen fjerner samlekortet (web's fejl i prod 22/11).
export function foersteUddeling(built: FeedStream, n: number, afgjort: boolean): FeedCard[] | null {
  const first = naesteSide(built, n, afgjort);
  if (!afgjort && first.length === 0) return null;
  return first;
}

// Springer positionslåste kort over, hvis slagen allerede er vist (eller er delt ud fra denne strøm).
function enPrVisning(stream: FeedStream, shown: readonly FeedCard[]): FeedStream {
  const vist = new Set(shown.filter((c) => EN_PR_VISNING.has(c.kind)).map((c) => c.kind));
  return {
    next(n: number): FeedCard[] {
      const out: FeedCard[] = [];
      while (out.length < n && !stream.done()) {
        const batch = stream.next(n - out.length);
        if (batch.length === 0) break;
        for (const card of batch) {
          if (EN_PR_VISNING.has(card.kind)) {
            if (vist.has(card.kind)) continue;
            vist.add(card.kind);
          }
          out.push(card);
        }
      }
      return out;
    },
    done: () => stream.done(),
    total: () => stream.total(),
  };
}

// Genoptag efter en genopbygning (biografier kom, pins/fokus/bogmærke-hydrering ændrede input). De viste kort beholdes
// (minus samlekortet); den nye strøm springer viste kort og viste personer over. Er der færre end en side, eller var
// den gamle strøm udtømt, fyldes der straks op: FlatList kalder ikke onEndReached igen, når listen står stille, så
// læseren ville ellers blive stående ved de få kort fra fristen.
// `shown` returneres uændret (samme reference), når intet skal ændres — så kalderen kan springe en render over.
export function genoptag(
  built: FeedStream, shown: readonly FeedCard[], n: number, afgjort: boolean, forrigeUdtoemt: boolean,
): { stream: FeedStream; shown: readonly FeedCard[] } {
  const bevaret = udenSamle(shown);
  const stream = enPrVisning(
    resumeStream(
      built,
      new Set(bevaret.map((c) => c.id)),
      new Set(bevaret.map(bookmarkPersonId).filter((id): id is string => id != null)),
    ),
    bevaret,
  );
  const antal = bevaret.length < n ? n - bevaret.length : forrigeUdtoemt ? n : 0;
  const fyld = antal > 0 ? naesteSide(stream, antal, afgjort) : [];
  if (fyld.length === 0 && bevaret.length === shown.length) return { stream, shown };
  return { stream, shown: [...bevaret, ...fyld] };
}
