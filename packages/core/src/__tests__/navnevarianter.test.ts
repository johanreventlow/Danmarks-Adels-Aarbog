import { describe, test, expect } from 'vitest';
import { foldToken, matchKey } from '../navnevarianter';

describe('foldToken — lag 1 grafem-regler (§3.2)', () => {
  test('c→k foran a/o/u/l/r', () => {
    expect(foldToken('conrad')).toBe(foldToken('konrad'));
    expect(foldToken('claus')).toBe(foldToken('klaus'));
    expect(foldToken('carl')).toBe(foldToken('karl'));
  });

  test('c foran e/i/y foldes IKKE (Cecilie ≠ Kecilie)', () => {
    expect(foldToken('cecilie')).not.toBe(foldToken('kecilie'));
    // c bevares foran blød vokal
    expect(foldToken('cecilie').startsWith('c')).toBe(true);
  });

  test('w→v (tysk↔dansk)', () => {
    expect(foldToken('wilhelm')).toBe(foldToken('vilhelm'));
  });

  test('th→t, ph→f (latinisering)', () => {
    expect(foldToken('thora')).toBe(foldToken('tora'));
    expect(foldToken('adolph')).toBe(foldToken('adolf'));
  });

  test('dobbeltkonsonant → enkelt; ck→k', () => {
    expect(foldToken('frederick')).toBe(foldToken('frederik'));
    expect(foldToken('detleff')).toBe(foldToken('detlef'));
  });

  test('aa→å, ö→ø, ü→y (æ/ø/å røres aldrig)', () => {
    expect(foldToken('kaas')).toBe(foldToken('kås'));
    expect(foldToken('jörgen')).toBe(foldToken('jørgen'));
  });

  test('ord-finalt a→e for token ≥ 4 tegn (Benedicta→Benedicte, Sophia→Sofie-agtigt)', () => {
    expect(foldToken('benedicta')).toBe(foldToken('benedicte'));
    // korte tokens (< 4) røres ikke
    expect(foldToken('ida')).toBe('ida');
  });

  test('idempotens: fold(fold(x)) = fold(x)', () => {
    for (const t of ['cathrina', 'wilhelm', 'gottschalk', 'benedicta', 'frederick', 'jörgen', 'conrad']) {
      expect(foldToken(foldToken(t))).toBe(foldToken(t));
    }
  });
});

describe('foldToken — lag 2 variant-tabel (§3.2)', () => {
  test('kendte fornavns-varianter kollapser til én repræsentant', () => {
    expect(foldToken('detlev')).toBe(foldToken('detlef'));
    expect(foldToken('detlev')).toBe(foldToken('ditlev'));
    expect(foldToken('frederik')).toBe(foldToken('friedrich'));
    expect(foldToken('frederik')).toBe(foldToken('fritz'));
    expect(foldToken('henrik')).toBe(foldToken('heinrich'));
    expect(foldToken('henrik')).toBe(foldToken('hinrich'));
  });

  test('Christian↔Kristian samme nøgle + samme blok (ellers c-blok vs k-blok)', () => {
    expect(foldToken('kristian')).toBe(foldToken('christian'));
    // begge skal have samme initial så blocking sammenligner dem
    expect(matchKey('Kristian')[0]).toBe(matchKey('Christian')[0]);
    // Christian-nøglen er uændret (facit-invariant)
    expect(foldToken('christian')).toBe('christian');
  });
});

describe('matchKey — flagship + facit (§9)', () => {
  test('Cathrina / Catharina / Katharina → én match_key', () => {
    const a = matchKey('Cathrina');
    expect(matchKey('Catharina')).toBe(a);
    expect(matchKey('Katharina')).toBe(a);
  });

  test('facit-varianter fra 1939↔2012-14', () => {
    // Gotskalk (1939) ↔ Gottschalk (2018-20)
    expect(matchKey('Gotskalk')).toBe(matchKey('Gottschalk'));
    // Ditlev ↔ Detlef
    expect(matchKey('Ditlev')).toBe(matchKey('Detlef'));
  });

  test('titel/partikel-strip: Komtesse/Comtesse + navn folder ens', () => {
    expect(matchKey('Komtesse Benedicta')).toBe(matchKey('Comtesse Benedicte'));
    expect(matchKey('greve Carl')).toBe(matchKey('Greve Karl'));
  });

  test('blocking-symmetri: foldning FØR blok — Cathrina og Katharina samme initial', () => {
    expect(matchKey('Cathrina')[0]).toBe(matchKey('Katharina')[0]);
  });

  test('diakritik bevares i input men foldes til match-nøgle (kun scoring)', () => {
    // æ/ø/å røres ikke; men tomt/NN giver tom nøgle
    expect(matchKey('')).toBe('');
    expect(matchKey('   ')).toBe('');
  });
});
