import { describe, expect, it } from 'vitest';
import { visbarPostEtiket } from '../recordLabel';

describe('visbarPostEtiket', () => {
  it('skjuler tekniske nøgler og tomme etiketter', () => {
    expect(visbarPostEtiket('record-07565168-b903-4444-9189-43d62d5c6ed6')).toBeNull();
    expect(visbarPostEtiket('legacy-source:3:II')).toBeNull();
    expect(visbarPostEtiket('')).toBeNull();
    expect(visbarPostEtiket('  ')).toBeNull();
    expect(visbarPostEtiket(null)).toBeNull();
    expect(visbarPostEtiket(undefined)).toBeNull();
  });
  it('bevarer læsbare etiketter trimmet', () => {
    expect(visbarPostEtiket('V-1')).toBe('V-1');
    expect(visbarPostEtiket(' I-32 ')).toBe('I-32');
  });
});
