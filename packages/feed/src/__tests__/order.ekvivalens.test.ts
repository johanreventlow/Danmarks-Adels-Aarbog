// Review 36 P11: trækningsløkken i buildFeedOrder er skrevet om fra filter+splice+indexOf pr. træk (O(n²)) til
// rang-ordnede lister (RangPulje). Omskrivningen må ikke ændre ordningen: for mange seedede, tilfældige input skal
// den nye og den gamle implementering (orderReference.ts, ordret kopi) give præcis samme kortliste.
import { describe, expect, it } from 'vitest';
import { buildFeedOrder } from '../order';
import { genFeedInput, type GenOpts } from './orderGenerator';
import { grene, orderReference } from './orderReference';

function sammenlign(seed: number, opts: GenOpts) {
  const { model, aux, inputs } = genFeedInput(seed, opts);
  const ny = buildFeedOrder(model, aux, inputs);
  const gammel = orderReference(model, aux, inputs);
  // Byte-for-byte: samme serialisering, og deep equal for en læsbar diff ved fejl.
  if (JSON.stringify(ny) !== JSON.stringify(gammel)) expect(ny).toEqual(gammel);
  return ny.length;
}

describe('buildFeedOrder = den gamle løkke (orderReference) for seedede, tilfældige input', () => {
  it('tomme og ultrakorte input (0-3 personer), mange seeds', () => {
    for (let seed = 0; seed < 400; seed++) sammenlign(seed, { persons: seed % 4 });
  });

  it('små input (4-40 personer) med blandede korttyper', () => {
    for (let seed = 0; seed < 600; seed++) sammenlign(1000 + seed, { persons: 4 + (seed % 37) });
  });

  it('naevnt-tunge input i web-feedets form (TEMP_DISABLED_KINDS + naevntGrundlag)', () => {
    for (let seed = 0; seed < 300; seed++) {
      sammenlign(5000 + seed, { persons: 5 + (seed % 60), naevntAndel: 0.6 + (seed % 4) * 0.1, bioAndel: (seed % 5) * 0.03, webForm: true });
    }
  });

  it('kun nævnte (ingen portrætter) og kun portrætter', () => {
    for (let seed = 0; seed < 150; seed++) {
      sammenlign(7000 + seed, { persons: 3 + (seed % 30), naevntAndel: 1, bioAndel: 0 });
      sammenlign(8000 + seed, { persons: 3 + (seed % 30), naevntAndel: 0, bioAndel: 1 });
    }
  });

  it('større input (200-600 personer)', () => {
    for (let seed = 0; seed < 25; seed++) sammenlign(9000 + seed, { persons: 200 + seed * 16 });
    for (let seed = 0; seed < 10; seed++) sammenlign(9500 + seed, { persons: 400, webForm: true, naevntAndel: 0.85, bioAndel: 0.05 });
  });

  // Køres sidst: beviser, at generatoren faktisk har ført den gamle løkke gennem hver regel-gren ovenfor — ellers
  // kunne ekvivalensen være tom for netop de grene, omskrivningen rører.
  it('generatoren har ramt hver regel-gren i den gamle løkke', () => {
    for (const gren of [
      'dagens-laas', 'slaegt-laas', 'naevnt-loft', 'naevnt-rest-droppet', 'r3-tvang', 'r3-uden-portraet',
      'r3-slaegt-lookahead', 'dagens-filter-virkede', 'dagens-filter-uden-virkning', 'dagens-filter-tomt', 'relax-r2', 'relax-r1r2', 'valg-ved-loftet',
    ]) {
      expect(grene[gren] ?? 0, gren).toBeGreaterThan(0);
    }
  });
});
