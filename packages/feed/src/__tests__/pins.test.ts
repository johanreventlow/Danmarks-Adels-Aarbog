import { describe, expect, it } from 'vitest';
import { buildFeedPins } from '../pins';

describe('buildFeedPins', () => {
  it('sorterer oprettet_naar stigende med kort_noegle som tiebreak', () => {
    const out = buildFeedPins([
      { kort_noegle: 'portrait:9', handling: 'pin', oprettet_naar: '2026-07-02T10:00:00Z' },
      { kort_noegle: 'story:2', handling: 'skjul', oprettet_naar: '2026-07-01T10:00:00Z' },
      { kort_noegle: 'arkiv:5', handling: 'pin', oprettet_naar: '2026-07-02T10:00:00Z' },
    ]);
    expect(out).toEqual([
      { kortNoegle: 'story:2', handling: 'skjul' },
      { kortNoegle: 'arkiv:5', handling: 'pin' },
      { kortNoegle: 'portrait:9', handling: 'pin' },
    ]);
  });

  it('NULL-tidsstempel sorteres sidst', () => {
    const out = buildFeedPins([
      { kort_noegle: 'a', handling: 'pin', oprettet_naar: null },
      { kort_noegle: 'b', handling: 'pin', oprettet_naar: '2026-07-01T00:00:00Z' },
    ]);
    expect(out.map((pin) => pin.kortNoegle)).toEqual(['b', 'a']);
  });

  it('ukendt handling filtreres; tomme input giver []', () => {
    expect(buildFeedPins([{ kort_noegle: 'x', handling: 'fremhaev', oprettet_naar: null }])).toEqual([]);
    expect(buildFeedPins([])).toEqual([]);
  });
});
