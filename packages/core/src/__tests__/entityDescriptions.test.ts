import { describe, expect, it } from 'vitest';
import {
  isEntityDescriptionSubject,
  publicDescriptionCitation,
} from '../entityDescriptions';

describe('entity descriptions', () => {
  it('accepts only canonical entities as description subjects', () => {
    expect(isEntityDescriptionSubject('slaegt')).toBe(true);
    expect(isEntityDescriptionSubject('coat_of_arms')).toBe(true);
    expect(isEntityDescriptionSubject('unknown_source_type')).toBe(false);
  });

  it('projects a citation label without exposing private source-record identifiers', () => {
    expect(publicDescriptionCitation({
      sourceLabel: 'Danmarks Adels Aarbog 1939',
      citationLabel: 's. 42',
      sourceRecordId: '8e1f0145-a9ee-4ab3-b036-8e8cffd89304',
    })).toEqual({
      sourceLabel: 'Danmarks Adels Aarbog 1939',
      citationLabel: 's. 42',
    });
  });
});
