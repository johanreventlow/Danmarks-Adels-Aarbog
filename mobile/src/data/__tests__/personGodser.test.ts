// Personskærmens »Besiddelser« (mobil-paritet): udgave-reglen fra @daa/core, samme gods samlet med alle perioder.
import type { UdgaveFaktaInput } from '@daa/core';
import { buildAux } from '../buildAux';
import { godserTilVisning } from '../personGodser';
import { byggUdgaveLag, TOMT_SKEMA } from '../udgaveLag';
import type { EstateRef } from '../types';

const udgaver = [{ sourceId: '1', label: 'DAA 1939', aar: 1939 }, { sourceId: '2', label: 'DAA 2018-20', aar: 2018 }];
// Personen er foldet af to rækker: 80 fra 2018-20 og 81 fra 1939 (eksterne nøgler).
const input: UdgaveFaktaInput = { rows: [], udgaver, udgaveForPersonRaekke: { '80': '2', '81': '1' }, fritekstKilde: {} };
const e = (id: string, navn: string, period: string, personId: string): EstateRef => ({ id, navn, period, personId });
const estates: EstateRef[] = [
  e('1', 'Christianssæde', '1700-10', '80'),
  e('1', 'Christianssæde', '1720-30', '80'),
  e('2', 'Pederstrup', '', '80'),
  e('3', 'Brahetrolleborg', '1730', '81'),
  e('1', 'Christianssæde', '1700-10', '81'),
];

describe('godserTilVisning', () => {
  test('valgt udgave: kun dens godser; samme gods én gang med alle perioder', () => {
    expect(godserTilVisning(estates, input, udgaver, '2')).toEqual([
      { id: '1', navn: 'Christianssæde', perioder: '1700-10, 1720-30' },
      { id: '2', navn: 'Pederstrup', perioder: '' },
    ]);
    expect(godserTilVisning(estates, input, udgaver, '1').map((g) => g.navn)).toEqual(['Brahetrolleborg', 'Christianssæde']);
  });

  test('uden valgt udgave: alle godser, perioder samlet uden dubletter', () => {
    expect(godserTilVisning(estates, input, udgaver, null)).toEqual([
      { id: '1', navn: 'Christianssæde', perioder: '1700-10, 1720-30' },
      { id: '2', navn: 'Pederstrup', perioder: '' },
      { id: '3', navn: 'Brahetrolleborg', perioder: '1730' },
    ]);
  });
});

// Gennem den rigtige indlæsningsvej: buildAux folder relationerne under den kanoniske id, men bevarer relationens rå
// subjekt-id; byggUdgaveLag nøgler udgaveForPersonRaekke på koordinatrækkernes rå person_id. De to id-rum skal være det
// samme, ellers filtrerer godserIUdgave intet for netop de sammenlagte personer.
describe('godserTilVisning gennem buildAux + byggUdgaveLag (sammenlagt person)', () => {
  test('rækken fra 1939 (81, foldet ind i 80) filtreres efter sin egen udgave', () => {
    const canonicalIdById = { '81': '80' };
    const sources = [
      { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', udgave: 'DAA 1939', aar: 1939, ekstern: null },
      { id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null },
    ];
    const lag = byggUdgaveLag({
      extIds: [
        { person_id: 80, source_id: 2, linje: 'V', nr: 1, slaegtled_lokal: 1, provenance: 'placement' },
        { person_id: 81, source_id: 1, linje: 'IV', nr: 1, slaegtled_lokal: 1, provenance: 'placement' },
      ],
      sources, lineageRows: [], schemeRows: TOMT_SKEMA,
    }, canonicalIdById);
    const rel = (subjekt_id: number, objekt_id: number, periode_raw: string) =>
      ({ subjekt_type: 'person', subjekt_id, objekt_type: 'estate', objekt_id, rolle: 'ejer', periode_raw });
    const aux = buildAux({
      sources: [], orgs: [], media: [], arms: [],
      estates: [{ id: 1, navn: 'Christianssæde' }, { id: 3, navn: 'Brahetrolleborg' }],
      relations: [rel(80, 1, '1700-10'), rel(81, 3, '1730')],
    } as never, canonicalIdById);
    const input: UdgaveFaktaInput = { rows: [], udgaver: lag.udgaver, udgaveForPersonRaekke: lag.udgaveForPersonRaekke, fritekstKilde: {} };
    expect(aux.estatesBy['80'].map((e) => e.personId)).toEqual(['80', '81']);
    expect(godserTilVisning(aux.estatesBy['80'], input, lag.udgaver, '2').map((g) => g.navn)).toEqual(['Christianssæde']);
    expect(godserTilVisning(aux.estatesBy['80'], input, lag.udgaver, '1').map((g) => g.navn)).toEqual(['Brahetrolleborg']);
  });
});
