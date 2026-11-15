// Review 36 P11: før/efter-måling af buildFeedOrder på syntetisk input (ingen projektdata).
// Kør fra packages/feed:  npx tsx scripts/maal-order.ts
// »før« = orderReference (ordret kopi af den gamle løkke), »efter« = buildFeedOrder. Begge bygger de samme kort; forskellen
// er trækningsløkken. Hver måling er medianen af 3 kørsler; outputtet sammenlignes også (skal være identisk).
import { buildFeedOrder } from '../src/order';
import { genFeedInput, type GenOpts } from '../src/__tests__/orderGenerator';
import { orderReference } from '../src/__tests__/orderReference';

function median(xs: number[]): number { return [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]; }

function maal(koer: () => unknown): number {
  const tider: number[] = [];
  for (let i = 0; i < 3; i++) {
    const t0 = performance.now();
    koer();
    tider.push(performance.now() - t0);
  }
  return median(tider);
}

const former: [string, Omit<GenOpts, 'persons'>][] = [
  ['alle korttyper', { alleTyper: true, naevntAndel: 0.3, bioAndel: 0.4 }],
  ['web-form (TEMP_DISABLED_KINDS + naevnt)', { webForm: true, naevntAndel: 0.8, bioAndel: 0.1 }],
];
for (const n of [10_000, 50_000]) {
  for (const [navn, opts] of former) {
    const { model, aux, inputs } = genFeedInput(42, { persons: n, ...opts });
    const ny = buildFeedOrder(model, aux, inputs);
    const gammel = orderReference(model, aux, inputs);
    const ens = JSON.stringify(ny) === JSON.stringify(gammel);
    const foer = maal(() => orderReference(model, aux, inputs));
    const efter = maal(() => buildFeedOrder(model, aux, inputs));
    console.log(`n=${n} personer · ${navn}: ${ny.length} kort i feedet · før ${foer.toFixed(0)} ms · efter ${efter.toFixed(0)} ms · ×${(foer / efter).toFixed(1)} · output ens: ${ens}`);
  }
}
