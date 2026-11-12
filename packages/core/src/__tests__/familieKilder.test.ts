import { describe, expect, it } from 'vitest';
import { buildModel } from '../buildModel';
import { aegteskabsKilder, bigintTekst, boerneKilder, familieIderForPerson, foraelderKilder, kildeLinje, mapFamilieKilder,
  type FamilieKilde } from '../familieKilder';
import type { AppPerson } from '../types';

const persons: AppPerson[] = ['1', '2', '3', '4'].map((id) => ({
  id, name: `P${id}`, born: null, died: null, years: '', title: '', bio: '', privat: false,
}));

describe('familieIderForPerson', () => {
  it('giver familie-id pr. ægteskab og fødselsfamilien', () => {
    const m = buildModel({ persons, unions: [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
    ], parentChild: [{ child: '3', parent: '1', union: 'f10' }, { child: '3', parent: '2', union: 'f10' }] });
    expect(familieIderForPerson(m.indexes, '1').aegteskaber).toEqual([{ spouseId: '2', familyId: '10' }]);
    expect(familieIderForPerson(m.indexes, '2').aegteskaber).toEqual([{ spouseId: '1', familyId: '10' }]);
    expect(familieIderForPerson(m.indexes, '3').foraeldreFamilier).toEqual(['10']);
    expect(familieIderForPerson(m.indexes, '4')).toEqual({ aegteskaber: [], foraeldreFamilier: [], boerneFamilier: [] });
  });
  // Trin 5b 2b-iii: børneflokkens kilde hos forælderen — partnerens familier med børn.
  it('boerneFamilier er partnerens familier med børn', () => {
    const m = buildModel({ persons, unions: [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
      { id: 'f20', p1: '1', p2: '4', p2_name: null, year: null },
    ], parentChild: [{ child: '3', parent: '1', union: 'f10' }, { child: '3', parent: '2', union: 'f10' }] });
    expect(familieIderForPerson(m.indexes, '1').boerneFamilier).toEqual(['10']);
    expect(familieIderForPerson(m.indexes, '2').boerneFamilier).toEqual(['10']);
    expect(familieIderForPerson(m.indexes, '4').boerneFamilier).toEqual([]);
    expect(familieIderForPerson(m.indexes, '3').boerneFamilier).toEqual([]);
  });
  // buildModel viser bevidst kun forældrene fra barnets FØRSTE familie (parentsByChild), og »Barn af« i
  // panelet bygger på dem; kilden følger derfor samme familie (ingen forælderkilde uden en vist forælder).
  it('flere forældrepar: følger modellens viste fødselsfamilie', () => {
    const m = buildModel({ persons, unions: [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
      { id: 'f20', p1: '4', p2: null, p2_name: null, year: null },
    ], parentChild: [{ child: '3', parent: '1', union: 'f10' }, { child: '3', parent: '2', union: 'f10' },
      { child: '3', parent: '4', union: 'f20' }] });
    expect(familieIderForPerson(m.indexes, '3').foraeldreFamilier).toEqual(['10']);
  });
  it('to_familier_samme_par: hver familie for sig', () => {
    const m = buildModel({ persons, unions: [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
      { id: 'f11', p1: '1', p2: '2', p2_name: null, year: null },
    ], parentChild: [] });
    expect(familieIderForPerson(m.indexes, '2').aegteskaber.map((a) => a.familyId).sort()).toEqual(['10', '11']);
  });
});

describe('kildeLinje og mapFamilieKilder', () => {
  it('godtager slags boern', () => {
    const rows = mapFamilieKilder([{ family_id: 10, slags: 'boern', counterpart_person_id: 1, source_record_ref: null,
      source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' }]);
    expect(rows).toHaveLength(1);
    expect(rows[0].slags).toBe('boern');
  });
  it('former linjen og dropper ugyldige rækker', () => {
    const rows = mapFamilieKilder([
      { family_id: 10, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: 'r', source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' },
      { family_id: 11, slags: 'noget', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 2', citation_label: 'c' },
      { family_id: '9007199254740993', slags: 'foraelder', counterpart_person_id: '9007199254740995', source_record_ref: null, source_label: 'DAA X', record_label: 'Post 3', citation_label: 'c' },
      // Et tal over 2^53 kan allerede have mistet præcision i JSON.parse ⇒ droppes (fail closed).
      { family_id: 9007199254740993, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 4', citation_label: 'c' },
      { family_id: '10x', slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 5', citation_label: 'c' },
      { family_id: '9999999999999999999', slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 6', citation_label: 'c' },
      null,
    ]);
    expect(rows).toHaveLength(2);
    expect(rows[1].familyId).toBe('9007199254740993');   // strenge bevares; aldrig Number()
    expect(rows[1].counterpartPersonId).toBe('9007199254740995');
    expect(kildeLinje(rows[0])).toBe('Kilde: DAA X · Post 1');
  });
  it('kildeLinje skjuler tekniske postetiketter', () => {
    const k = { familyId: '1', slags: 'aegteskab', counterpartPersonId: '2', sourceRecordRef: null, sourceLabel: 'DAA 1939',
      recordLabel: 'record-07565168-b903-4444-9189-43d62d5c6ed6', citationLabel: '' } as const;
    expect(kildeLinje(k)).toBe('Kilde: DAA 1939');
    expect(kildeLinje({ ...k, sourceLabel: 'DAA 2018-20', recordLabel: 'V-1' })).toBe('Kilde: DAA 2018-20 · V-1');
  });
  it('bigintTekst følger Postgres-bigint-intervallet', () => {
    expect(bigintTekst('9223372036854775807')).toBe('9223372036854775807');
    expect(bigintTekst('9223372036854775808')).toBeNull();
    expect(bigintTekst('-9223372036854775808')).toBe('-9223372036854775808');
    expect(bigintTekst('-9223372036854775809')).toBeNull();
    expect(bigintTekst(42)).toBe('42');
    expect(bigintTekst(1.5)).toBeNull();
    expect(bigintTekst('')).toBeNull();
  });
});

// Trin 6d-3 spor L: modparten i en binding er postens person-id (fx 1939's alias-række); modellen viser kanoniske
// id'er efter samme_som-sammenfoldningen. Filtrene slår modparten op kanonisk (canon[id] ?? id).
describe('kildefiltre med kanonisk modpart', () => {
  const k = (x: Partial<FamilieKilde>): FamilieKilde => ({
    familyId: '10', slags: 'aegteskab', counterpartPersonId: '2', sourceRecordRef: null,
    sourceLabel: 'DAA X', recordLabel: 'Post 1', citationLabel: '', ...x,
  });
  // Kanoniske 1 og 2; -2 er 1939's alias for 2, -1 alias for 1. Familie 10 (2018-20) og 11 (1939) er begge parrets
  // efter sammenfoldningen; 12 er 1's ægteskab med 4.
  const m = buildModel({ persons, unions: [
    { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
    { id: 'f11', p1: '1', p2: '2', p2_name: null, year: null },
    { id: 'f12', p1: '1', p2: '4', p2_name: null, year: null },
    { id: 'f20', p1: '4', p2: null, p2_name: null, year: null },
  ], parentChild: [{ child: '3', parent: '1', union: 'f10' }, { child: '3', parent: '2', union: 'f10' },
    { child: '1', parent: '4', union: 'f20' }] });
  const canon: Record<string, string> = { '-1': '1', '-2': '2', '1': '1', '2': '2' };
  it('aegteskab_alias_modpart: modparten er alias for den viste ægtefælle', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    expect(aegteskabsKilder([k({ familyId: '11', counterpartPersonId: '-2' })], ider, '2', '1', canon)).toHaveLength(1);
  });
  it('aegteskab_alias_to_familier: én kilde pr. udgave under samme kanoniske ægtefælle', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    const kilder = [k({ familyId: '10', counterpartPersonId: '2', sourceLabel: 'DAA 2018-20' }),
      k({ familyId: '11', counterpartPersonId: '-2', sourceLabel: 'DAA 1939' })];
    expect(aegteskabsKilder(kilder, ider, '2', '1', canon).map((x) => x.sourceLabel)).toEqual(['DAA 2018-20', 'DAA 1939']);
    expect(aegteskabsKilder(kilder, ider, '4', '1', canon)).toEqual([]);
  });
  it('aegteskab_anden_families_modpart: kanonisk match, men familien er ikke parrets', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    expect(aegteskabsKilder([k({ familyId: '12', counterpartPersonId: '-2' })], ider, '2', '1', canon)).toEqual([]);
  });
  it('aegteskab_modpart_er_fokus_alias: modparten er alias for personen selv', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    expect(aegteskabsKilder([k({ familyId: '11', counterpartPersonId: '-1' })], ider, '2', '1', canon)).toHaveLength(1);
  });
  it('foraelder_alias: modparten er alias for forælderen', () => {
    const ider = familieIderForPerson(m.indexes, '3');
    expect(foraelderKilder([k({ slags: 'foraelder', counterpartPersonId: '-2' })], ider, '2', canon)).toHaveLength(1);
    expect(foraelderKilder([k({ slags: 'foraelder', counterpartPersonId: '-2' })], ider, '1', canon)).toEqual([]);
  });
  it('boern_alias: modparten er alias for fokuspersonen', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    expect(boerneKilder([k({ slags: 'boern', counterpartPersonId: '-1' })], ider, '1', canon)).toHaveLength(1);
    expect(boerneKilder([k({ slags: 'boern', counterpartPersonId: '-2' })], ider, '1', canon)).toEqual([]);
  });
  it('ukendt_modpart: id uden for canon sammenlignes uændret, ingen fejl', () => {
    const ider = familieIderForPerson(m.indexes, '1');
    expect(aegteskabsKilder([k({ counterpartPersonId: '999' })], ider, '2', '1', {})).toEqual([]);
    expect(aegteskabsKilder([k({ counterpartPersonId: '2' })], ider, '2', '1', {})).toHaveLength(1);
  });
});
