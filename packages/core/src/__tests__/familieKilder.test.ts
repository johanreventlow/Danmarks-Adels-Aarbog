import { describe, expect, it } from 'vitest';
import { buildModel } from '../buildModel';
import { bigintTekst, familieIderForPerson, kildeLinje, mapFamilieKilder } from '../familieKilder';
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
