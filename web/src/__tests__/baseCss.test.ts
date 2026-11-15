// Læserfladens skal (fase 9): 100dvh med 100vh som reserve for browsere uden dvh (Safari før 15.4). Et inline style kan
// kun bære én værdi, så højden skal stå i base.css — og ikke inline på skallen, hvor den ville vinde over reserven.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const css = readFileSync(new URL('../base.css', import.meta.url), 'utf8');
const folgesvend = readFileSync(new URL('../Folgesvend.tsx', import.meta.url), 'utf8');

describe('skallens højde', () => {
  it('base.css giver læserfladen 100vh og derefter 100dvh', () => {
    expect(css).toMatch(/\[data-flade=laeser\]\{height:100vh;height:100dvh\}/);
  });

  it('skallen har ingen inline højde, der ville overstyre reserven', () => {
    const skal = folgesvend.split('\n').find((l) => l.includes('data-flade="laeser"'));
    expect(skal).toBeTruthy();
    expect(skal).not.toMatch(/height:/);
  });
});
