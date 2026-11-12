// Uddeling af feedet i partier på seks blade (»Vend seks blade mere«), ingen uendelig rulning.
import { NAEVNT_VINDUE, type FeedCard, type FeedStream } from '@daa/feed';

export const BLADE_PR_UDDELING = 6;

// Trækker op til `n` kort fra strømmen. Motoren holder selv loftet over 'naevnt' (højst ét pr.
// NAEVNT_VINDUE kort) inden for én ordning, men efter en genopbygning (resumeStream) mødes to
// ordninger i en søm, hvor loftet ikke er garanteret. Vagten her ser på de faktisk viste kort og
// springer et 'naevnt' over, der ville bryde loftet — det vises så bare ikke i denne visning.
export function delUd(
  stream: FeedStream,
  shown: readonly FeedCard[],
  n: number = BLADE_PR_UDDELING,
): FeedCard[] {
  const ud: FeedCard[] = [];
  while (ud.length < n && !stream.done()) {
    const [card] = stream.next(1);
    if (!card) break;
    if (card.kind === 'naevnt') {
      const seneste = [...shown, ...ud].slice(-(NAEVNT_VINDUE - 1));
      if (seneste.some((c) => c.kind === 'naevnt')) continue;
    }
    ud.push(card);
  }
  return ud;
}

// Visningens blokke: hver uddeling på seks er sin egen blok.
export function iBlokke(shown: readonly FeedCard[], n: number = BLADE_PR_UDDELING): FeedCard[][] {
  const blokke: FeedCard[][] = [];
  for (let i = 0; i < shown.length; i += n) blokke.push(shown.slice(i, i + n));
  return blokke;
}
