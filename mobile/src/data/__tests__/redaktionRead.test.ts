import { joinEvidence, mapKonfliktRow } from '../redaktionRead';

const FACTS = [
  { id: 10, subjekt_type: 'person', subjekt_id: 1, faktatype: 'navn' },
  { id: 11, subjekt_type: 'person', subjekt_id: 1, faktatype: 'fødsel' },
];
const ASSERTS = [
  { id: 100, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Conrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 101, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Konrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 102, target_type: 'fact', target_id: 11, vaerdi_tekst: null, date_min: '1644-01-01', date_max: '1644-12-31', date_qualifier: 'about', date_raw: 'ca. 1644' },
];
const CONCS = [{ target_type: 'fact', target_id: 10, valgt_assertion_id: 100 }];
const CITS = [
  { assertion_id: 100, source_id: 5, side: 's. 12', citat_tekst: 'Conrad', citat_dato: null, source: { titel: 'DAA 2018' } },
];

test('mapKonfliktRow oversætter faktatype → UI-felt', () => {
  expect(mapKonfliktRow({ person_id: 7, faktatype: 'navn', antal_vaerdier: 2 }))
    .toEqual({ personId: '7', felt: 'navn', antalVaerdier: 2 });
});

test('joinEvidence samler felter, markerer konklusion + uenig', () => {
  const ev = joinEvidence({ facts: FACTS, assertions: ASSERTS, conclusions: CONCS, citations: CITS, koen: 'M' });
  expect(ev.koen).toBe('M');
  expect(ev.felter.navn.uenig).toBe(true); // Conrad ≠ Konrad
  expect(ev.felter.navn.konklusionAssertionId).toBe(100);
  expect(ev.felter.navn.oplysninger.find((o) => o.assertionId === 100)?.erKonklusion).toBe(true);
  expect(ev.felter.navn.oplysninger.find((o) => o.assertionId === 100)?.kilder[0].sourceTitel).toBe('DAA 2018');
  expect(ev.felter.foedt.uenig).toBe(false); // kun én oplysning
  expect(ev.felter.foedt.oplysninger[0].dato?.raw).toBe('ca. 1644');
});
