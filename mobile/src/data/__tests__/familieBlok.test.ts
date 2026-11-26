// Paritetsplanens batch 6: familieblokken på mobilen, bygget som mobilens indlæsning gør det (mapAppPersons med
// `levende`, buildModel, 6e-laget fra byggUdgaveLag, stemplet som i storen) og projiceret med samme core-funktion
// som web's personside (byggFokusRaekker).
import { buildModel, byggFokusRaekker, kunIAeldreTekst, type Db, type RawLineageContext, type UdgaveChip } from '@daa/core';
import { barnErAktivt } from '../familieBlok';
import { mapAppPersons } from '../load';
import { treeFocusA } from '../selectors';
import type { Model, RawExtId, RawSource } from '../types';
import { byggUdgaveLag } from '../udgaveLag';

const sources: RawSource[] = [
  { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', udgave: 'DAA 1939', aar: 1939, ekstern: null },
  { id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null },
];
const lineageRows: RawLineageContext[] = [
  { id: 50, source_id: 2, kode: 'V', navn: 'Den grevelige Linje af 1673', slaegt_id: 1, slaegtsnavn: 'Reventlow' },
  { id: 51, source_id: 1, kode: 'IV', navn: 'Den grevelige Linje af 1673', slaegt_id: 1, slaegtsnavn: 'Reventlow' },
];
const schemeRows = {
  schemes: [{ id: 10, slaegt_id: 1, source_id: 1, kind: 'stamtavle' }, { id: 20, slaegt_id: 1, source_id: 2, kind: 'stamtavle' }],
  entries: [], mappings: [],
};
const raa = (id: number, navn: string, foedt: string | null, levende = false) =>
  ({ id, visning_navn: navn, visning_fuldt_navn: navn, visning_foedt: foedt, visning_doed: null, visning_titel: null, koen: null, privat: levende, levende });
// Far (10) i begge udgaver med to ægteskaber. Bo, Carl og Anna med Mor1; Dan med Mor2. Carl står kun i 1939
// (nr. 2 dér, mellem Bo og Anna); Lis er levende og står kun i 1939 — hun må aldrig få »Kun i DAA 1939«.
const persons = mapAppPersons([
  raa(10, 'Far', '1660'), raa(11, 'Mor1', '1665'), raa(12, 'Mor2', '1670'),
  raa(20, 'Anna', '1700'), raa(21, 'Bo', '1690'), raa(22, 'Carl', '1695'), raa(23, 'Dan', '1710'), raa(24, 'Lis', '1990', true),
], {}, true);
const db: Db = {
  persons,
  unions: [
    { id: 'f1', p1: '10', p2: '11', p2_name: null, year: null },
    { id: 'f2', p1: '10', p2: '12', p2_name: null, year: null },
  ],
  parentChild: [
    ...['21', '22', '20', '24'].flatMap((c) => [{ child: c, parent: '10', union: 'f1' }, { child: c, parent: '11', union: 'f1' }]),
    { child: '23', parent: '10', union: 'f2' }, { child: '23', parent: '12', union: 'f2' },
  ],
};
const ext = (person_id: number, source_id: number, linje: string, nr: number): RawExtId =>
  ({ person_id, source_id, linje, nr, slaegtled_lokal: 1, provenance: 'placement' });
const extIds: RawExtId[] = [
  ext(10, 2, 'V', 1), ext(10, 1, 'IV', 1),
  ext(21, 2, 'V', 2), ext(21, 1, 'IV', 1),
  ext(22, 1, 'IV', 2),
  ext(20, 2, 'V', 3), ext(20, 1, 'IV', 3),
  ext(23, 2, 'V', 4),
  ext(24, 1, 'IV', 4),
];
const model: Model = {
  ...buildModel(db),
  ...byggUdgaveLag({ extIds, sources, lineageRows, schemeRows }, {}),
  canonicalIdById: {}, parentsUnknownByPerson: {},
};

describe('familieblokken (mobilens model, core-rækkerne)', () => {
  test('levende hentes og mappes (mapAppPersons)', () => {
    expect(model.byId['24'].levende).toBe(true);
    expect(model.byId['22'].levende).toBe(false);
  });

  test('børn pr. ægteskab i bogens rækkefølge; 1939-barnet flettes ind på sin plads', () => {
    const r = byggFokusRaekker(model, '10')!;
    expect(r.boerneGrupper.map((g) => [g.aegteskab?.navn ?? null, g.boern.map((b) => b.person.name)]))
      .toEqual([['Mor1', ['Bo', 'Carl', 'Anna', 'Lis']], ['Mor2', ['Dan']]]);
    expect(r.boerneNote).toBeNull();
  });

  test('»Kun i DAA 1939« på barnet, der kun står i 1939 — aldrig på en levende', () => {
    expect(kunIAeldreTekst(model, '22')?.maerke).toBe('Kun i DAA 1939');
    expect(kunIAeldreTekst(model, '24')).toBeNull();
    expect(kunIAeldreTekst(model, '20')).toBeNull();
  });

  test('stamtræets fokusvisning (variant A): søskende i bogens rækkefølge; børnene pr. ægteskab som personskærmen', () => {
    // Søskende er en flad liste på tværs af ægteskaber: 2018-20's numre (Bo 2, Anna 3, Dan 4), Carl flettet ind før Anna
    // fra 1939, og Lis, som intet 1939-barn efter sig har, sidst. Børnene i variant A kommer fra byggFokusRaekker
    // (testen ovenfor): Mor1-flokken og Mor2-flokken hver for sig.
    expect(treeFocusA(model, '20').siblings.map((c) => c.name)).toEqual(['Bo', 'Carl', 'Anna', 'Dan', 'Lis']);
    expect(byggFokusRaekker(model, '10')!.aegteskaber.map((a) => a.navn)).toEqual(['Mor1', 'Mor2']);
  });
});

describe('barnErAktivt (port af web)', () => {
  const chip = (sourceId: string): UdgaveChip => ({ art: 'udgave', sourceId, label: sourceId === '1' ? 'DAA 1939' : 'DAA 2018-20' });
  const k = kunIAeldreTekst(model, '22');
  test('et link uden mærke eller uden valgt udgave', () => {
    expect(barnErAktivt(null, chip('2'), [chip('2'), chip('1')])).toBe(true);
    expect(barnErAktivt(k, null, [])).toBe(true);
  });
  test('gråt, når en anden udgave er valgt og barnets udgave kan vælges; et link i sin egen udgave', () => {
    expect(barnErAktivt(k, chip('2'), [chip('2'), chip('1')])).toBe(false);
    expect(barnErAktivt(k, chip('1'), [chip('2'), chip('1')])).toBe(true);
  });
  test('et link, når barnets udgave slet ikke kan vælges', () => {
    expect(barnErAktivt(k, chip('2'), [chip('2')])).toBe(true);
  });
});
