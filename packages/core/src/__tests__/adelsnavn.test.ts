import { describe, expect, it } from 'vitest';
import {
  adelsnavnForLinjer, byggLinjeAdelsnavne, formelNavneform, lineageIdAfNoegle, personensAdelsnavn,
} from '../adelsnavn';
import { ADELS_TITLER, erAdelsTitel } from '../adelsTitler';
import { lineageContextKey } from '../lineage';
import type { Lineage } from '../types';

describe('formelNavneform — bogens formelle navneform', () => {
  it('V: fornavne + titel med lille + »af Reventlow«', () => {
    expect(formelNavneform({ fornavne: 'Johan Martin', titel: 'Greve', adelsnavn: 'af Reventlow' }))
      .toBe('Johan Martin greve af Reventlow');
  });
  it('IV: »de Reventlou«, også for lensgreve', () => {
    expect(formelNavneform({ fornavne: 'Friedrich', titel: 'Greve', adelsnavn: 'de Reventlou' }))
      .toBe('Friedrich greve de Reventlou');
    expect(formelNavneform({ fornavne: 'Detlef', titel: 'Lensgreve', adelsnavn: 'de Reventlou' }))
      .toBe('Detlef lensgreve de Reventlou');
  });
  it('kvinder: titlen er allerede kønsbøjet', () => {
    expect(formelNavneform({ fornavne: 'Anna', titel: 'Komtesse', adelsnavn: 'af Reventlow' }))
      .toBe('Anna komtesse af Reventlow');
  });
  it('bevarer kaldenavne i parentes, som bogen skriver dem', () => {
    expect(formelNavneform({ fornavne: 'Adelheid (Lilli) Margarethe', titel: 'Komtesse', adelsnavn: 'de Reventlou' }))
      .toBe('Adelheid (Lilli) Margarethe komtesse de Reventlou');
  });
  it('fjerner slægtsnavnet, hvis fornavnene allerede ender på det', () => {
    expect(formelNavneform({ fornavne: 'Johan Martin Reventlow', titel: 'Greve', adelsnavn: 'af Reventlow', slaegtsnavn: 'Reventlow' }))
      .toBe('Johan Martin greve af Reventlow');
  });
  it('trimmer mellemrum i delene', () => {
    expect(formelNavneform({ fornavne: ' Conrad ', titel: ' Greve ', adelsnavn: ' af Reventlow ' }))
      .toBe('Conrad greve af Reventlow');
  });
  it('ingen form uden adelstitel', () => {
    expect(formelNavneform({ fornavne: 'Christian', titel: 'Kammerherre', adelsnavn: 'af Reventlow' })).toBeNull();
    expect(formelNavneform({ fornavne: 'Sophia Hedwig', titel: 'Grevinde (?)', adelsnavn: 'af Reventlow' })).toBeNull();
    expect(formelNavneform({ fornavne: 'Anna Sophia', titel: 'Grevinde, fyrstinde af Slesvig', adelsnavn: 'af Reventlow' })).toBeNull();
    expect(formelNavneform({ fornavne: 'Christian', titel: null, adelsnavn: 'af Reventlow' })).toBeNull();
  });
  it('ingen form uden fornavne eller adelsnavn', () => {
    expect(formelNavneform({ fornavne: '  ', titel: 'Greve', adelsnavn: 'af Reventlow' })).toBeNull();
    expect(formelNavneform({ fornavne: null, titel: 'Greve', adelsnavn: 'af Reventlow' })).toBeNull();
    expect(formelNavneform({ fornavne: 'Conrad', titel: 'Greve', adelsnavn: null })).toBeNull();
    expect(formelNavneform({ fornavne: 'Conrad', titel: 'Greve', adelsnavn: ' ' })).toBeNull();
  });
});

describe('adelsnavnForLinjer — præcis én regel, ellers ingen', () => {
  const regler = { '4': 'de Reventlou', '5': 'af Reventlow' };
  it('én linje med regel', () => {
    expect(adelsnavnForLinjer(['5'], regler)).toBe('af Reventlow');
  });
  it('en linje med og en uden regel → reglen', () => {
    expect(adelsnavnForLinjer(['5', '7'], regler)).toBe('af Reventlow');
  });
  it('samme regel to gange → reglen', () => {
    expect(adelsnavnForLinjer(['5', '5'], regler)).toBe('af Reventlow');
  });
  it('to forskellige regler → ingen (fail-closed)', () => {
    expect(adelsnavnForLinjer(['4', '5'], regler)).toBeNull();
  });
  it('ingen linjer eller ingen regler → ingen', () => {
    expect(adelsnavnForLinjer([], regler)).toBeNull();
    expect(adelsnavnForLinjer(['5'], {})).toBeNull();
  });
  it('linjens stifter får ingen form: hans navn kommer fra hans eget patent', () => {
    expect(adelsnavnForLinjer(['5'], regler, ['5'])).toBeNull();
    expect(adelsnavnForLinjer(['5'], regler, ['7'])).toBe('af Reventlow');
  });
});

describe('lineageIdAfNoegle', () => {
  it('udtrækker lineage-id fra kontekstnøgler', () => {
    expect(lineageIdAfNoegle(lineageContextKey({ slaegtId: '1', lineageId: '5' }))).toBe('5');
    expect(lineageIdAfNoegle(lineageContextKey({ slaegtId: '1', lineageId: '5', schemeId: '2', schemeEntryId: '3' }))).toBe('5');
  });
  it('rå koder og tekniske nøgler har intet id', () => {
    expect(lineageIdAfNoegle('V')).toBeNull();
    expect(lineageIdAfNoegle('legacy-source:3:V')).toBeNull();
  });
});

describe('personensAdelsnavn — fra læserens linjemodel', () => {
  const k4 = lineageContextKey({ slaegtId: '1', lineageId: '4' });
  const k5 = lineageContextKey({ slaegtId: '1', lineageId: '5' });
  const k5Skema1939 = lineageContextKey({ slaegtId: '1', lineageId: '5', schemeId: '9', schemeEntryId: '41' });
  const lineage: Lineage = {
    byPerson: { '392': [k5], '500': [k5Skema1939], '600': [k4, k5], '700': [k5] },
    list: [
      { linje: k4, count: 1, headId: '298', navn: 'IV' },
      { linje: k5, count: 3, headId: '392', navn: 'V' },
    ],
    navn: {},
  };
  const regler = { '4': 'de Reventlou', '5': 'af Reventlow' };
  it('efterkommer i V (også via 1939-skemaets nøgle) får V-reglen', () => {
    expect(personensAdelsnavn('700', lineage, regler)).toBe('af Reventlow');
    expect(personensAdelsnavn('500', lineage, regler)).toBe('af Reventlow');
  });
  it('stifteren af V (Conrad) får ingen', () => {
    expect(personensAdelsnavn('392', lineage, regler)).toBeNull();
  });
  it('person i både IV og V får ingen', () => {
    expect(personensAdelsnavn('600', lineage, regler)).toBeNull();
  });
  it('ukendt person eller ingen regler → ingen', () => {
    expect(personensAdelsnavn('999', lineage, regler)).toBeNull();
    expect(personensAdelsnavn('700', lineage, {})).toBeNull();
  });
});

describe('adelstitler flyttet til core', () => {
  it('samme lukkede liste', () => {
    expect([...ADELS_TITLER].sort()).toEqual([
      'baron', 'baronesse', 'comtesse', 'friherre', 'friherreinde', 'greve', 'grevinde', 'komtesse',
      'lensgreve', 'lensgrevinde', 'rigsgreve', 'rigsgrevinde',
    ]);
    expect(erAdelsTitel(' Greve ')).toBe(true);
    expect(erAdelsTitel('Kammerherre')).toBe(false);
  });
});

describe('byggLinjeAdelsnavne — fact/konklusion/påstand → regel pr. linje', () => {
  const facts = [{ id: 10, subjekt_id: 4 }, { id: 11, subjekt_id: 5 }];
  it('afklarede konklusioner giver reglerne', () => {
    expect(byggLinjeAdelsnavne(facts,
      [{ target_id: 10, valgt_assertion_id: 100 }, { target_id: 11, valgt_assertion_id: 101 }],
      [{ id: 100, vaerdi_tekst: 'de Reventlou' }, { id: 101, vaerdi_tekst: ' af Reventlow ' }],
    )).toEqual({ '4': 'de Reventlou', '5': 'af Reventlow' });
  });
  it('fakta uden konklusion eller med tom værdi giver ingen regel', () => {
    expect(byggLinjeAdelsnavne(facts,
      [{ target_id: 10, valgt_assertion_id: 100 }, { target_id: 11, valgt_assertion_id: null }],
      [{ id: 100, vaerdi_tekst: '  ' }],
    )).toEqual({});
  });
  it('to forskellige afklarede regler på samme linje → ingen (fail-closed)', () => {
    expect(byggLinjeAdelsnavne([{ id: 10, subjekt_id: 4 }, { id: 12, subjekt_id: 4 }],
      [{ target_id: 10, valgt_assertion_id: 100 }, { target_id: 12, valgt_assertion_id: 102 }],
      [{ id: 100, vaerdi_tekst: 'de Reventlou' }, { id: 102, vaerdi_tekst: 'af Reventlow' }],
    )).toEqual({});
  });
});
