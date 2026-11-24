// Strøm-API (spec §4): tynd doserings-cursor over ÉN eager buildFeedOrder-beregning.
// "Uendelig scroll" er dosering af den færdige ordning, ikke løbende genberegning.
import { buildFeedOrder } from './order';
import { bookmarkPersonId } from './types';
import type { FeedAux, FeedCard, FeedInputs, Model } from './types';

export interface FeedStream {
  next(n: number): FeedCard[];
  done(): boolean;
  total(): number;
}

export function createFeedStream(model: Model, aux: FeedAux, inputs: FeedInputs): FeedStream {
  const order = buildFeedOrder(model, aux, inputs);
  let cursor = 0;
  return {
    next(n: number): FeedCard[] {
      const slice = order.slice(cursor, cursor + n);
      cursor += slice.length;
      return slice;
    },
    done(): boolean {
      return cursor >= order.length;
    },
    total(): number {
      return order.length;
    },
  };
}

// Genoptagelse efter pool-udvidelse (web's bio-ankomst, spec §7.3): en ny strøm over den
// SAMME seed vil starte forfra — resumeStream springer id'er der allerede er vist over,
// så allerede-viste kort ikke gentages, og trækker videre fra den underliggende strøm
// indtil `n` nye kort er fundet eller den underliggende strøm er udtømt.
// `shownPersonIds` (forsidens krav om ét kort pr. person): en genopbygget ordning kan vælge et ANDET kort for en person,
// der allerede er vist — det springes også over.
export function resumeStream(
  stream: FeedStream, shownIds: ReadonlySet<string>, shownPersonIds?: ReadonlySet<string>,
): FeedStream {
  return {
    next(n: number): FeedCard[] {
      const out: FeedCard[] = [];
      while (out.length < n && !stream.done()) {
        const batch = stream.next(n - out.length);
        if (batch.length === 0) break;
        for (const card of batch) {
          if (shownIds.has(card.id)) continue;
          const personId = bookmarkPersonId(card);
          if (shownPersonIds && personId != null && shownPersonIds.has(personId)) continue;
          out.push(card);
        }
      }
      return out;
    },
    done: () => stream.done(),
    total: () => stream.total(),
  };
}
