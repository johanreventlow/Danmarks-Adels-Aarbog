import { describe, it, expect } from 'vitest';
import { showSearchResults } from '../data/browse';

describe('showSearchResults', () => {
  const base = { query: '', bmOnly: false, browsing: false };
  it('falsk når intet er aktivt', () => {
    expect(showSearchResults(base)).toBe(false);
  });
  it('whitespace-only query tæller ikke', () => {
    expect(showSearchResults({ ...base, query: '   ' })).toBe(false);
  });
  it('rigtig query → resultater', () => {
    expect(showSearchResults({ ...base, query: 'Chr' })).toBe(true);
  });
  it('bogmærke-filter → resultater uden query', () => {
    expect(showSearchResults({ ...base, bmOnly: true })).toBe(true);
  });
  it('gennemse-tilstand → resultater uden query', () => {
    expect(showSearchResults({ ...base, browsing: true })).toBe(true);
  });
});
