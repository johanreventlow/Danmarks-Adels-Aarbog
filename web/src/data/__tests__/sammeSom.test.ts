import { sammeSomEtiket } from '../sammeSom';

describe('sammeSomEtiket', () => {
  // retning er set fra den REDIGEREDE person; etiketten beskriver MODPARTEN, hvis navn står
  // i rækken. Rollerne er derfor byttet om — den nemmeste fejl at lave her, derfor testet.
  it('retning "alias" betyder at modparten er den kanoniske post', () => {
    expect(sammeSomEtiket('alias')).toEqual({
      rolle: 'KANONISK',
      forklaring: 'den post du redigerer er markeret som alias for denne',
    });
  });

  it('retning "kanonisk" betyder at modparten er aliaset', () => {
    expect(sammeSomEtiket('kanonisk')).toEqual({
      rolle: 'ALIAS',
      forklaring: 'markeret som alias for den post du redigerer',
    });
  });

  it('lover ikke en foldning — pre-flight kan afvise den', () => {
    // Regressionsværn: teksten må beskrive relationen, ikke resultatet. Bekræftelsesdialogen kan
    // sige "⚠ Foldes ikke endnu — … Linket oprettes, men personerne vises separat".
    expect(sammeSomEtiket('alias').forklaring).not.toMatch(/foldes/i);
    expect(sammeSomEtiket('kanonisk').forklaring).not.toMatch(/foldes/i);
  });
});
