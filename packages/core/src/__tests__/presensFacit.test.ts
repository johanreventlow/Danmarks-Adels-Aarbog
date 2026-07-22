import { buildModel } from '../buildModel';
import { buildPresensListe } from '../presensListe';
import { mk, union, pc } from './presensListe.test';
import type { Db } from '../types';

// Facit: DAA 2012-14, II LINJE 1. GREN (PDF s. 362). Anker = Christian Ditlev Ludvig (CDL).
// Bogens grupper: SØSTRE (Alette, Sybille) og FARFARS FARBROR (Ludvig, †1916, hvis
// efterkommere via Iven m.fl. lever). Far og mor er begge døde → ingen MOR-gruppe.
const db: Db = {
  persons: [
    // Blodlinjen op: CDL ← Far (Christian Benedict, †) ← Farfar (†) ← FarfarsFar (†)
    mk('CDL', 'mand', 1950), mk('Far', 'mand', 1915, 1984), mk('Mor', 'kvinde', 1921, 2012),
    mk('Farfar', 'mand', 1885, 1970), mk('FarfarsFar', 'mand', 1855, 1930),
    mk('FFFFar', 'mand', 1820, 1890), // farfars fars far — fælles ane for FARFARS FARBROR-gruppen
    // Ankerets familie
    mk('Anni', 'kvinde', 1951), mk('JohanM', 'mand', 1977), mk('Julie', 'kvinde', 1980), mk('AndreasC', 'mand', 1985),
    mk('FrederikJ', 'mand', 2013),
    // Søstrene
    mk('Alette', 'kvinde', 1946), mk('Sybille', 'kvinde', 1948),
    // FARFARS FARBROR-sidegrenen: Ludvig (†1916) ─ Otto (†) ─ Iven (levende)
    mk('Ludvig', 'mand', 1848, 1916), mk('Otto', 'mand', 1886, 1929), mk('Iven', 'mand', 1926),
  ],
  unions: [
    { id: 'fFFFFar', p1: 'FFFFar', p2: null, p2_name: null, year: null },
    union('fFarfarsFar', 'FarfarsFar'), union('fFarfar', 'Farfar'),
    { id: 'fFar', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
    { id: 'fCDL', p1: 'CDL', p2: 'Anni', p2_name: null, year: null },
    union('fLudvig', 'Ludvig'), union('fOtto', 'Otto'),
  ],
  parentChild: [
    pc('FarfarsFar', 'FFFFar', 'fFFFFar'), pc('Ludvig', 'FFFFar', 'fFFFFar'),
    pc('Farfar', 'FarfarsFar', 'fFarfarsFar'),
    pc('Far', 'Farfar', 'fFarfar'),
    pc('CDL', 'Far', 'fFar'), pc('CDL', 'Mor', 'fFar'),
    pc('Alette', 'Far', 'fFar'), pc('Alette', 'Mor', 'fFar'),
    pc('Sybille', 'Far', 'fFar'), pc('Sybille', 'Mor', 'fFar'),
    pc('JohanM', 'CDL', 'fCDL'), pc('Julie', 'CDL', 'fCDL'), pc('AndreasC', 'CDL', 'fCDL'),
    pc('FrederikJ', 'JohanM', 'fJM'), // union oprettes implicit ikke — se union-listen note nedenfor
    pc('Otto', 'Ludvig', 'fLudvig'), pc('Iven', 'Otto', 'fOtto'),
  ],
};
// NB: 'fJM' skal med i unions-listen for at kanten er gyldig:
db.unions.push(union('fJM', 'JohanM'));

const model = buildModel(db);
const levende = { CDL: true, Anni: true, JohanM: true, Julie: true, AndreasC: true, FrederikJ: true, Alette: true, Sybille: true, Iven: true };

test('facit: II linje 1. gren reproducerer bogens gruppestruktur', () => {
  const liste = buildPresensListe(model, [{ personId: 'CDL', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' }], levende);
  const g = liste.grene[0];
  // Ankerblok: CDL + ægtefælle + tre børn + barnebarn under Johan Martin
  expect(g.ankerBlok.id).toBe('CDL');
  expect(g.ankerBlok.partnere.map((p) => p.id)).toContain('Anni');
  expect(g.ankerBlok.boern.map((b) => b.id)).toEqual(['JohanM', 'Julie', 'AndreasC']);
  expect(g.ankerBlok.boern[0].boern.map((b) => b.id)).toEqual(['FrederikJ']);
  // Bogens grupper, i bogens rækkefølge — og INGEN Mor-gruppe (hun er død):
  expect(g.grupper.map((x) => x.overskrift)).toEqual(['Søstre', 'Farfars farbror']);
  expect(g.grupper[0].roedder.map((r) => r.id)).toEqual(['Alette', 'Sybille']);
  // Ludvig er dødt forbindelsesled; kæden ned til levende Iven bevaret, død-uden-levende beskåret undervejs findes ikke
  const ludvig = g.grupper[1].roedder[0];
  expect(ludvig).toMatchObject({ id: 'Ludvig', forbindelsesled: true });
  expect(ludvig.boern[0].id).toBe('Otto');
  expect(ludvig.boern[0].boern[0]).toMatchObject({ id: 'Iven', levende: true });
  // Ingen advarsler om levende uden gren i denne lukkede fixture
  expect(liste.advarsler.filter((a) => a.art === 'levende_uden_gren')).toHaveLength(0);
});
