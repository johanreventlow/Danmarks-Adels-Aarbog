import { describe, expect, test } from 'vitest';
import { boernIder, personVisningsnavn, UDEN_NAVN, UNAVNGIVET_BARN } from '../personNavn';

describe('personVisningsnavn', () => {
  test('fuldt navn foran visningsnavn', () => {
    expect(personVisningsnavn({ visning_fuldt_navn: 'Iven Reventlow', visning_navn: 'Iven' }, false)).toBe('Iven Reventlow');
  });
  test('visningsnavn når fuldt navn mangler', () => {
    expect(personVisningsnavn({ visning_fuldt_navn: null, visning_navn: 'Iven' }, false)).toBe('Iven');
  });
  test('tom tekst og blanktegn tæller som manglende navn', () => {
    expect(personVisningsnavn({ visning_fuldt_navn: '', visning_navn: 'Iven' }, false)).toBe('Iven');
    expect(personVisningsnavn({ visning_fuldt_navn: '  ', visning_navn: ' ' }, true)).toBe(UNAVNGIVET_BARN);
  });
  test('barn uden navn (bogens »(?)«, fx 1939 s. 37 nr. 5) vises som »Unavngivet barn«', () => {
    expect(personVisningsnavn({ visning_fuldt_navn: null, visning_navn: null }, true)).toBe('Unavngivet barn');
  });
  test('ikke-barn uden navn beholder »(uden navn)«', () => {
    expect(personVisningsnavn({ visning_navn: null }, false)).toBe(UDEN_NAVN);
  });
});

describe('boernIder', () => {
  test('alle barneroller tæller, partnere ikke; store bogstaver og null tåles', () => {
    const s = boernIder([
      { person_id: 1, rolle: 'barn' }, { person_id: 2, rolle: 'Plejebarn' }, { person_id: 3, rolle: 'adopteret_barn' },
      { person_id: 4, rolle: 'stedbarn' }, { person_id: 5, rolle: 'partner' }, { person_id: 6, rolle: null },
    ]);
    expect([...s].sort()).toEqual(['1', '2', '3', '4']);
  });
});
