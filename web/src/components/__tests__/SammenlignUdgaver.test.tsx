import { describe, expect, test } from 'vitest';
import type { ParentChild, RedMatchPerson } from '@daa/core';
import {
  foraeldreNavne,
  formatBogReferencer,
  formatPersonNavn,
} from '../SammenlignUdgaver';

function person(overrides: Partial<RedMatchPerson> = {}): RedMatchPerson {
  return {
    id: '1',
    navn: 'Detlev',
    fuldtNavn: 'Detlev Reventlow',
    koen: 'mand',
    foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
    doed: { date_min: '1730-01-01', date_max: '1730-12-31' },
    titel: null,
    bogReferencer: [],
    sourceIds: [3],
    staged: true,
    ...overrides,
  };
}

describe('SammenlignUdgaver kandidat-overblik', () => {
  test('viser fuldt navn, titel og det eksisterende fødsel-død-span', () => {
    expect(formatPersonNavn(person({ titel: 'Amtmand' })))
      .toBe('Detlev Reventlow · Amtmand (1660–1730)');
  });

  test('falder tilbage til matcher-navnet når fuldt navn mangler', () => {
    expect(formatPersonNavn(person({ fuldtNavn: null })))
      .toBe('Detlev (1660–1730)');
  });

  test('udleder unikke forældre-navne fra den allerede hentede parentChild-graf', () => {
    const byId = new Map([
      ['1', person()],
      ['2', person({ id: '2', navn: 'christian d. r.', fuldtNavn: 'Christian Ditlev Reventlow' })],
      ['3', person({ id: '3', navn: 'anna s.', fuldtNavn: 'Anna Sophie Schack' })],
    ]);
    const parentChild: ParentChild[] = [
      { child: '1', parent: '2', union: 'f10' },
      { child: '1', parent: '3', union: 'f10' },
      { child: '1', parent: '2', union: 'f11' },
    ];

    expect(foraeldreNavne('1', parentChild, byId))
      .toBe('f. af Christian Ditlev Reventlow & Anna Sophie Schack');
  });

  test('viser bog-nr og gren og degraderer ved delvise referencer', () => {
    expect(formatBogReferencer(person({
      bogReferencer: [
        { sourceId: 3, linje: 'III', nr: 58, slaegtledLokal: 12, slaegtledGennem: 12, kuld: null, grenNavn: 'Holstenske linje' },
        { sourceId: 7, linje: null, nr: 4, slaegtledLokal: null, slaegtledGennem: null, kuld: null, grenNavn: null },
      ],
    }))).toBe('III-58, Holstenske linje · nr. 4');
  });
});
