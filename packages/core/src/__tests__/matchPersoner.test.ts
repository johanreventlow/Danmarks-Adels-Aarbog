import { describe, test, expect } from 'vitest';
import {
  buildMatchFrame,
  buildMatchPersoner,
  matchUdgaver,
  parseIkkeSammeSomPar,
} from '../matchUdgaver';

describe('buildMatchPersoner — DB-rækker → MatchFrame-input (§11)', () => {
  const persons = [
    { id: 1, visning_navn: 'Ludvig Alexander Eduard', koen: 'mand', staged: true },
    { id: 2, visning_navn: 'Uden datoer', koen: 'kvinde', staged: false },
  ];
  const facts = [
    { id: 10, subjekt_id: 1, faktatype: 'fødsel' },
    { id: 11, subjekt_id: 1, faktatype: 'død' },
    { id: 12, subjekt_id: 1, faktatype: 'erhverv' }, // ignoreres
    { id: 13, subjekt_id: 2, faktatype: 'fødsel' },
  ];
  const concs = [
    { target_id: 10, valgt_assertion_id: 100 },
    { target_id: 11, valgt_assertion_id: 110 },
    { target_id: 13, valgt_assertion_id: null }, // ingen valgt → intet interval
  ];
  const assertions = [
    { id: 100, date_min: '1848-11-05', date_max: '1848-11-05' },
    { id: 110, date_min: '1916-06-19', date_max: '1916-06-19' },
    { id: 999, date_min: '1700-01-01', date_max: '1700-01-01' }, // ikke valgt → må ikke bruges
  ];
  const extIds = [
    { person_id: 1, source_id: 5 },
    { person_id: 1, source_id: 7 },
  ];

  test('fødsel/død fra VALGT assertions date_min/date_max', () => {
    const p1 = buildMatchPersoner(persons, facts, concs, assertions, extIds).find((x) => x.id === '1')!;
    expect(p1.foedsel).toEqual({ date_min: '1848-11-05', date_max: '1848-11-05' });
    expect(p1.doed).toEqual({ date_min: '1916-06-19', date_max: '1916-06-19' });
  });

  test('erhverv-fakta ignoreres; ikke-valgt assertion bruges aldrig', () => {
    const p1 = buildMatchPersoner(persons, facts, concs, assertions, extIds).find((x) => x.id === '1')!;
    expect(p1.foedsel?.date_min).not.toBe('1700-01-01');
  });

  test('kilde-medlemskab samles pr. person', () => {
    const r = buildMatchPersoner(persons, facts, concs, assertions, extIds);
    expect(r.find((x) => x.id === '1')!.sourceIds).toEqual([5, 7]);
    expect(r.find((x) => x.id === '2')!.sourceIds).toEqual([]);
  });

  test('person uden konkluderet dato → null-intervaller', () => {
    const p2 = buildMatchPersoner(persons, facts, concs, assertions, extIds).find((x) => x.id === '2')!;
    expect(p2.foedsel).toBe(null);
    expect(p2.doed).toBe(null);
  });

  test('staged normaliseres til boolean (§7.20 selektiv publicering)', () => {
    const r = buildMatchPersoner(persons, facts, concs, assertions, extIds);
    expect(r.find((x) => x.id === '1')!.staged).toBe(true);
    expect(r.find((x) => x.id === '2')!.staged).toBe(false);
  });

  test('fuldt navn, valgte titler og kilde-specifik bogreference beriger personen additivt', () => {
    const enrichedPersons = [
      { ...persons[0], visning_fuldt_navn: 'Ludvig Alexander Eduard Reventlow' },
    ];
    const enrichedFacts = [
      ...facts,
      { id: 14, subjekt_id: 1, faktatype: 'titel' },
      { id: 15, subjekt_id: 1, faktatype: 'titel' },
    ];
    const enrichedConcs = [
      ...concs,
      { target_id: 14, valgt_assertion_id: 140 },
      { target_id: 15, valgt_assertion_id: 150 },
    ];
    const enrichedAssertions = [
      ...assertions,
      { id: 140, date_min: null, date_max: null, vaerdi_tekst: 'Amtmand' },
      { id: 150, date_min: null, date_max: null, vaerdi_tekst: 'Oberst' },
    ];
    const enrichedExtIds = [{
      person_id: 1, source_id: 5, linje: 'III', nr: 58,
      slaegtled_lokal: 12, slaegtled_gennem: 12, kuld: 'II',
    }];
    const lineages = [{ source_id: 5, kode: 'III', navn: 'Holstenske linje' }];

    const p1 = buildMatchPersoner(
      enrichedPersons, enrichedFacts, enrichedConcs, enrichedAssertions, enrichedExtIds, lineages,
    )[0];

    expect(p1.navn).toBe('Ludvig Alexander Eduard');
    expect(p1.fuldtNavn).toBe('Ludvig Alexander Eduard Reventlow');
    expect(p1.titel).toBe('Amtmand · Oberst');
    expect(p1.bogReferencer).toEqual([{
      sourceId: 5,
      linje: 'III',
      nr: 58,
      slaegtledLokal: 12,
      slaegtledGennem: 12,
      kuld: 'II',
      grenNavn: 'Holstenske linje',
    }]);
  });

  test('fuldt visningsnavn ændrer ikke matcherens navn, score eller tier', () => {
    const detlevs = buildMatchPersoner(
      [
        {
          id: 1,
          visning_navn: 'Detlev',
          visning_fuldt_navn: 'Detlev Reventlow',
          koen: 'mand',
        },
        {
          id: 2,
          visning_navn: 'Detlev',
          visning_fuldt_navn: 'Detlev',
          koen: 'mand',
        },
      ],
      [
        { id: 20, subjekt_id: 1, faktatype: 'fødsel' },
        { id: 21, subjekt_id: 2, faktatype: 'fødsel' },
      ],
      [
        { target_id: 20, valgt_assertion_id: 200 },
        { target_id: 21, valgt_assertion_id: 210 },
      ],
      [
        { id: 200, date_min: '1660-01-01', date_max: '1660-12-31' },
        { id: 210, date_min: '1660-01-01', date_max: '1660-12-31' },
      ],
      [
        { person_id: 1, source_id: 3 },
        { person_id: 2, source_id: 7 },
      ],
    );

    expect(detlevs.map((p) => p.navn)).toEqual(['Detlev', 'Detlev']);
    expect(detlevs[0].fuldtNavn).toBe('Detlev Reventlow');

    const [pair] = matchUdgaver(
      [buildMatchFrame(detlevs[0])],
      [buildMatchFrame(detlevs[1])],
    );
    expect(pair.nameSim).toBe(1);
    expect(pair.score).toBeCloseTo(0.9);
    expect(pair.tier).toBe('auto');
  });
});

describe('parseIkkeSammeSomPar', () => {
  test('relation-rækker → afvisnings-par som strenge', () => {
    expect(parseIkkeSammeSomPar([{ subjekt_id: 3, objekt_id: 8 }])).toEqual([{ aId: '3', bId: '8' }]);
  });
});
