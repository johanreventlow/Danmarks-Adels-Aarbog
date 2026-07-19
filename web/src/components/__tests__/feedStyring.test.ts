import { describe, expect, it } from 'vitest';
import { bygKortNoegle, pinStatus } from '../FeedStyring';

describe('FeedStyring helpers', () => {
  it('bygger de tre kendte kortnøgler', () => {
    expect(bygKortNoegle('portrait', 7)).toBe('portrait:7');
    expect(bygKortNoegle('story', '9')).toBe('story:9');
    expect(bygKortNoegle('arkiv', 3)).toBe('arkiv:3');
  });

  it('klassificerer kendte og dinglende portrait/story samt ukendt arkiv', () => {
    const persons = new Set(['7']); const stories = new Set(['9']);
    expect(pinStatus('portrait:7', persons, stories)).toBe('ok');
    expect(pinStatus('portrait:8', persons, stories)).toBe('dinglende');
    expect(pinStatus('story:9', persons, stories)).toBe('ok');
    expect(pinStatus('story:10', persons, stories)).toBe('dinglende');
    expect(pinStatus('arkiv:3', persons, stories)).toBe('ukendt');
  });
});
