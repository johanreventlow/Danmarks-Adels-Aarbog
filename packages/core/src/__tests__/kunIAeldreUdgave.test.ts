import { describe, expect, it } from 'vitest';
import { byggBogNr, kunIAeldreUdgave, type BogNr } from '../index';

const N = (sourceId: string, linje = 'V', nr = 1, stamtavle?: boolean): BogNr =>
  ({ sourceId, linje, nr, nrLabel: null, ...(stamtavle === undefined ? {} : { stamtavle }) });
const udgaver = [{ sourceId: '10', aar: 1939 }, { sourceId: '20', aar: 2018 }];

describe('kunIAeldreUdgave', () => {
  it('Conrad-formen: forælderens legacy-linje behøver ikke matche barnets', () => {
    expect(kunIAeldreUdgave('B', ['F'], {
      F: [N('20', 'V', 1, true), N('10', '1939', 275)], B: [N('10', 'IV', 2)],
    }, udgaver)).toEqual({ kunI: ['10'], ikkeI: '20' });
  });

  it('barn i begge udgaver får intet mærke', () => {
    expect(kunIAeldreUdgave('B', ['F'], { F: [N('20')], B: [N('10'), N('20')] }, udgaver)).toBeNull();
  });

  it('barn kun i nyere udgave end forælderen får intet mærke', () => {
    expect(kunIAeldreUdgave('B', ['F'], { F: [N('10')], B: [N('20')] }, udgaver)).toBeNull();
  });

  it.each([{ foraeldre: [] }, { foraeldre: ['F'] }])('ingen forældre eller forældre uden bognummer: $foraeldre', ({ foraeldre }) => {
    expect(kunIAeldreUdgave('B', foraeldre, { B: [N('10')] }, udgaver)).toBeNull();
  });

  it('forælderens nyere præsensliste tæller ikke som stamtavle', () => {
    expect(kunIAeldreUdgave('B', ['F'], {
      F: [N('20', 'V', 1, false), N('10')], B: [N('10')],
    }, udgaver)).toBeNull();
  });

  it('forælder kun i udgave uden kendt år giver intet mærke', () => {
    expect(kunIAeldreUdgave('B', ['F'], { F: [N('30')], B: [N('10')] }, [
      ...udgaver, { sourceId: '30', aar: null },
    ])).toBeNull();
  });

  it('vælger nyeste udgave blandt begge forældre', () => {
    expect(kunIAeldreUdgave('B', ['F', 'M'], {
      F: [N('10')], M: [N('20')], B: [N('10')],
    }, udgaver)).toEqual({ kunI: ['10'], ikkeI: '20' });
  });

  it('barnets udgaver er unikke og nyeste først, også uden stamtavleflag', () => {
    expect(kunIAeldreUdgave('B', ['F'], {
      F: [N('20')], B: [N('10'), N('15', 'IV', 2, false), N('10', 'VI'), N('30'), N('ukendt')],
    }, [...udgaver, { sourceId: '15', aar: 1982 }, { sourceId: '30', aar: null }]))
      .toEqual({ kunI: ['15', '10'], ikkeI: '20' });
  });

  it('barn i anden udgave fra samme år som N får intet mærke', () => {
    expect(kunIAeldreUdgave('B', ['F'], { F: [N('20')], B: [N('21')] }, [
      ...udgaver, { sourceId: '21', aar: 2018 },
    ])).toBeNull();
  });

  it('barn uden bognumre eller kun uden kendt år får intet mærke', () => {
    for (const B of [[], [N('ukendt')]]) {
      expect(kunIAeldreUdgave('B', ['F'], { F: [N('20')], B }, udgaver)).toBeNull();
    }
  });

  it('manglende indeks eller udgaver giver intet mærke', () => {
    expect(kunIAeldreUdgave('B', ['F'], undefined, udgaver)).toBeNull();
    expect(kunIAeldreUdgave('B', ['F'], { F: [N('20')], B: [N('10')] }, undefined)).toBeNull();
  });
});

describe('byggBogNr stamtavle', () => {
  const extIds = [
    { person_id: 1, source_id: 20, linje: 'V', nr: 1 },
    { person_id: 2, source_id: 20, linje: 'P', nr: 2 },
  ];

  it('sætter prædikatets resultat på hvert kanonisk bognummer', () => {
    expect(byggBogNr(extIds, { '2': '1' }, (sid, linje) => sid === '20' && linje === 'V')).toEqual({
      '1': [N('20', 'V', 1, true), N('20', 'P', 2, false)],
    });
  });

  it('udelader feltet helt uden prædikat', () => {
    const r = byggBogNr(extIds, {});
    expect(r['1'][0]).not.toHaveProperty('stamtavle');
    expect(r['2'][0]).not.toHaveProperty('stamtavle');
  });
});
