import { describe, expect, it } from 'vitest';
import {
  formatLineageLabel,
  lineageSchemeEntryKey,
  surnameFromSlaegtMembership,
} from '../slaegter';

describe('lineageSchemeEntryKey', () => {
  it('holder samme trykte kode adskilt mellem to slægter og schemes', () => {
    expect(lineageSchemeEntryKey('scheme-reventlow-stamtavle', 'II'))
      .toBe('scheme-reventlow-stamtavle:II');
    expect(lineageSchemeEntryKey('scheme-brahe-stamtavle', 'II'))
      .toBe('scheme-brahe-stamtavle:II');
  });
});

describe('formatLineageLabel', () => {
  it('kvalificerer tvetydig linjeetiket med slægtens navn', () => {
    expect(formatLineageLabel({
      slaegtNavn: 'Reventlow',
      canonicalLabel: 'II. linje',
      ambiguous: true,
    })).toBe('Reventlow · II. linje');
  });

  it('bevarer scheme-label særskilt fra den kanoniske lineage-label', () => {
    expect(formatLineageLabel({
      slaegtNavn: 'Reventlow',
      canonicalLabel: 'Den grevelige linje',
      schemeLabel: 'II. linje i præsenslisten',
      ambiguous: false,
    })).toBe('Den grevelige linje (II. linje i præsenslisten)');
  });
});

describe('surnameFromSlaegtMembership', () => {
  it('giver ikke slægtsnavn uden slægtsmedlemskab', () => {
    expect(surnameFromSlaegtMembership(
      { navn: 'Reventlow' },
      null,
    )).toBeNull();
  });

  it('giver slægtsnavn ved eksplicit agnatisk medlemskab', () => {
    expect(surnameFromSlaegtMembership(
      { navn: 'Reventlow' },
      { membershipKind: 'agnatic' },
    )).toBe('Reventlow');
  });
});
