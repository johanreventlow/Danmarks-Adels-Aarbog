import { buildModel } from '../buildModel';
import { pruneUndertrae } from '../presensListe';
import { buildPresensListe, kanoniserPresensGrundlag } from '../presensListe';
import { mk, union, pc } from './presensFixtures';
import type { PresensAnker } from '../presensLabels';
import type { Db } from '../types';

describe('pruneUndertrae — bogens s.15-beskæring', () => {
  // A(død) ─ B(død) ─ C(levende);  A ─ D(død, ingen levende under sig)
  const db: Db = {
    persons: [mk('A'), mk('B'), mk('C'), mk('D')],
    unions: [union('fA', 'A'), union('fB', 'B')],
    parentChild: [pc('B', 'A', 'fA'), pc('D', 'A', 'fA'), pc('C', 'B', 'fB')],
  };
  const model = buildModel(db);

  test('afdød med levende barnebarn består som forbindelsesled; gren uden levende beskæres', () => {
    const node = pruneUndertrae(model, { C: true }, 'A');
    expect(node).not.toBeNull();
    expect(node!.forbindelsesled).toBe(true);
    expect(node!.boern.map((b) => b.id)).toEqual(['B']); // D beskåret
    expect(node!.boern[0].boern[0]).toMatchObject({ id: 'C', levende: true, forbindelsesled: false });
  });

  test('afdød uden levende under sig → null', () => {
    expect(pruneUndertrae(model, {}, 'D')).toBeNull();
  });

  test('afdød med efterlevende ægtefælle består (enke-mønstret inline i undertræer)', () => {
    const db2: Db = {
      persons: [mk('X', 'mand'), mk('E', 'kvinde')],
      unions: [{ id: 'fX', p1: 'X', p2: 'E', p2_name: null, year: null }],
      parentChild: [],
    };
    const m2 = buildModel(db2);
    const node = pruneUndertrae(m2, { E: true }, 'X');
    expect(node).not.toBeNull();
    expect(node!.partnere).toEqual([{ id: 'E', levende: true }]);
  });

  test('svag konfidens på kanten markerer barnet usikkert', () => {
    const db3: Db = {
      persons: [mk('A'), mk('B')],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA', 'formodet')],
    };
    const m3 = buildModel(db3);
    const node = pruneUndertrae(m3, { A: true, B: true }, 'A');
    expect(node!.boern[0].usikker).toBe(true);
    expect(node!.usikker).toBe(false); // roden selv har ingen kant op
  });

  test('børn sorteres deterministisk på fødselsår', () => {
    const db4: Db = {
      persons: [mk('A'), mk('B', 'mand', 1980), mk('C', 'kvinde', 1977)],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA'), pc('C', 'A', 'fA')],
    };
    const m4 = buildModel(db4);
    const node = pruneUndertrae(m4, { A: true, B: true, C: true }, 'A');
    expect(node!.boern.map((b) => b.id)).toEqual(['C', 'B']);
  });
});

const anker = (personId: string, linje = 'II', gren: number | null = 1): PresensAnker =>
  ({ personId, linje, gren, raaVaerdi: `${linje} linje${gren != null ? `, ${gren}. gren` : ''}` });

describe('buildPresensListe — klatring og grupper', () => {
  // FF(død) ─┬─ Far(død) ─┬─ ANKER(levende) ─ barn K1(levende)
  //          │            ├─ Søster S1(levende), Søster S2(levende)
  //          │            └─ (Mor(levende) er gift-ind: partner i Fars union, uden op-kobling)
  //          └─ Farbror FB(død) ─ FBdatter(levende)
  const db: Db = {
    persons: [
      mk('FF', 'mand'), mk('Far', 'mand'), mk('Mor', 'kvinde'), mk('ANKER', 'mand'),
      mk('K1', 'kvinde'), mk('S1', 'kvinde', 1946), mk('S2', 'kvinde', 1948),
      mk('FB', 'mand'), mk('FBdatter', 'kvinde'),
    ],
    unions: [
      union('fFF', 'FF'),
      { id: 'fFar', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
      union('fANKER', 'ANKER'), union('fFB', 'FB'),
    ],
    parentChild: [
      pc('Far', 'FF', 'fFF'), pc('FB', 'FF', 'fFF'),
      pc('ANKER', 'Far', 'fFar'), pc('ANKER', 'Mor', 'fFar'),
      pc('S1', 'Far', 'fFar'), pc('S1', 'Mor', 'fFar'),
      pc('S2', 'Far', 'fFar'), pc('S2', 'Mor', 'fFar'),
      pc('K1', 'ANKER', 'fANKER'), pc('FBdatter', 'FB', 'fFB'),
    ],
  };
  const model = buildModel(db);
  const levende = { ANKER: true, K1: true, S1: true, S2: true, Mor: true, FBdatter: true };

  test('ankerblok + SØSTRE + MOR + FARBROR i bogens rækkefølge', () => {
    const liste = buildPresensListe(model, [anker('ANKER')], levende);
    expect(liste.grene).toHaveLength(1);
    const g = liste.grene[0];
    expect(g.ankerBlok.id).toBe('ANKER');
    expect(g.ankerBlok.boern.map((b) => b.id)).toEqual(['K1']);
    expect(g.grupper.map((x) => x.overskrift)).toEqual(['Søstre', 'Mor', 'Farbror']);
    expect(g.grupper.map((x) => x.niveau)).toEqual([1, 1, 2]);
    // FB er død forbindelsesled med levende datter under sig
    const fb = g.grupper[2].roedder[0];
    expect(fb).toMatchObject({ id: 'FB', forbindelsesled: true });
    expect(fb.boern[0].id).toBe('FBdatter');
  });

  test('død mor → ingen MOR-gruppe; levende enke efter far → FARS ENKE', () => {
    // Far død, Mor død, men Far har en efterlevende 2. hustru E2
    const db2: Db = {
      persons: [mk('Far', 'mand'), mk('Mor', 'kvinde'), mk('E2', 'kvinde'), mk('ANKER', 'mand')],
      unions: [
        { id: 'f1', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
        { id: 'f2', p1: 'Far', p2: 'E2', p2_name: null, year: null },
      ],
      parentChild: [pc('ANKER', 'Far', 'f1'), pc('ANKER', 'Mor', 'f1')],
    };
    const m2 = buildModel(db2);
    const g = buildPresensListe(m2, [anker('ANKER')], { ANKER: true, E2: true }).grene[0];
    expect(g.grupper.map((x) => x.overskrift)).toEqual(['Fars enke']);
    expect(g.grupper[0].roedder[0].id).toBe('E2');
  });

  test('anker-partitionering: sidegren med eget anker springes over', () => {
    // FF ─┬─ Far ─ ANKER1;  FF ─┴─ Onkel ─ ANKER2 (eget gren-overhoved)
    const db3: Db = {
      persons: [mk('FF', 'mand'), mk('Far', 'mand'), mk('Onkel', 'mand'), mk('ANKER1', 'mand'), mk('ANKER2', 'mand')],
      unions: [union('fFF', 'FF'), union('fFar', 'Far'), union('fO', 'Onkel')],
      parentChild: [pc('Far', 'FF', 'fFF'), pc('Onkel', 'FF', 'fFF'), pc('ANKER1', 'Far', 'fFar'), pc('ANKER2', 'Onkel', 'fO')],
    };
    const m3 = buildModel(db3);
    const liste = buildPresensListe(m3, [anker('ANKER1', 'II', 1), anker('ANKER2', 'II', 2)], { ANKER1: true, ANKER2: true });
    const g1 = liste.grene[0];
    // Onkel-sidegrenen indeholder ANKER2 → ingen FARBROR-gruppe i gren 1
    expect(g1.grupper).toHaveLength(0);
    expect(liste.grene[1].ankerBlok.id).toBe('ANKER2');
  });

  test('advarsler: levende uden gren + anker-konflikt + dobbelt nået', () => {
    const db4: Db = {
      persons: [mk('A', 'mand'), mk('Loes', 'kvinde')],
      unions: [union('fA', 'A')],
      parentChild: [],
    };
    const m4 = buildModel(db4);
    const liste = buildPresensListe(m4, [anker('A', 'I', 1), anker('A', 'I', 1)], { A: true, Loes: true });
    expect(liste.advarsler.some((x) => x.art === 'anker_konflikt')).toBe(true);
    expect(liste.advarsler.some((x) => x.art === 'levende_uden_gren' && x.personId === 'Loes')).toBe(true);
    expect(liste.advarsler.some((x) => x.art === 'dobbelt_naaet' && x.personId === 'A')).toBe(true);
  });

  test('determinisme: samme input → identisk output', () => {
    const a = buildPresensListe(model, [anker('ANKER')], levende);
    const b = buildPresensListe(model, [anker('ANKER')], levende);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});

describe('kanoniserPresensGrundlag', () => {
  test('alias-id\'er foldes; levende OR-semantik over komponenten', () => {
    const db: Db = { persons: [mk('1'), mk('2')], unions: [], parentChild: [] };
    const model = { ...buildModel(db), canonicalIdById: { '2': '1', '1': '1' } };
    const r = kanoniserPresensGrundlag(model, [anker('2')], { '2': true, '1': false });
    expect(r.ankre[0].personId).toBe('1');
    expect(r.levendeById['1']).toBe(true);
  });
});

describe('pruneUndertrae — krydshenvisning (levende nået ad to veje inden for samme gren)', () => {
  test('ægte cyklus i data (A er sin egen ane) terminerer stadig og fjerner den cykliske gren', () => {
    // Kunstig datafejl: B er registreret som barn af A, OG A som barn af B (parentChild i begge
    // retninger). Uden på-vej-vagten ville dette give uendelig rekursion. A er levende (holder
    // A selv ude af beskæringen uafhængigt af cyklussen); B er død uden andre efterkommere, så
    // B's eneste "barn" er den cykliske gentagelse af A, som den indre på-vej-vagt afviser (null)
    // — B beskæres derfor væk, og A ender med et tomt (ikke uendeligt dybt) børne-sæt.
    const db: Db = { persons: [mk('A'), mk('B')], unions: [union('fA', 'A'), union('fB', 'B')], parentChild: [pc('B', 'A', 'fA'), pc('A', 'B', 'fB')] };
    const model = buildModel(db);
    const resultat = pruneUndertrae(model, { A: true }, 'A');
    expect(resultat).toMatchObject({ id: 'A', levende: true, boern: [] });
  });

  test('delt alleredeVist-sæt: anden forekomst bliver en krydshenvisnings-stub, ikke en duplikeret undertræ eller et stille drop', () => {
    // To UAFHÆNGIGE pruneUndertrae-kald (som to søskende-sidegrene i samme gren ville give),
    // der deler ÉT alleredeVist-sæt — simulerer buildGrens deling på tværs af sidegrene.
    const db: Db = {
      persons: [mk('P', 'kvinde')], unions: [], parentChild: [],
    };
    const model = buildModel(db);
    const alleredeVist = new Set<string>();
    const foerste = pruneUndertrae(model, { P: true }, 'P', null, new Set(), alleredeVist);
    const anden = pruneUndertrae(model, { P: true }, 'P', null, new Set(), alleredeVist);
    expect(foerste).toMatchObject({ id: 'P', levende: true, krydsReference: false });
    expect(anden).toMatchObject({ id: 'P', levende: true, krydsReference: true, boern: [], partnere: [] });
  });

  test('en beskåret (null) forekomst registreres IKKE i alleredeVist — blokerer ikke en senere gyldig forekomst', () => {
    // X er død uden levende efterkommere/enke → beskæres til null ved første forsøg.
    // Et andet, UAFHÆNGIGT senere kald på samme id (fx via en anden sidegren, hvor X's
    // undertræ set fra dén vinkel faktisk indeholder en levende efterkommer) skal stadig
    // kunne bygges fuldt ud — ikke fejlagtigt blive en krydshenvisning til ingenting.
    const db: Db = {
      persons: [mk('X'), mk('Y')], unions: [union('fX', 'X')], parentChild: [pc('Y', 'X', 'fX')],
    };
    const model = buildModel(db);
    const alleredeVist = new Set<string>();
    const foersteForsoeg = pruneUndertrae(model, {}, 'X', null, new Set(), alleredeVist); // ingen levende → null
    expect(foersteForsoeg).toBeNull();
    const andetForsoeg = pruneUndertrae(model, { X: true }, 'X', null, new Set(), alleredeVist); // nu levende
    expect(andetForsoeg).toMatchObject({ id: 'X', levende: true, krydsReference: false });
  });
});

describe('buildPresensListe — krydshenvisning inden for én gren (dobbelt-fætterskab)', () => {
  // ANKER ─┬─ Gren1 ─ Faelles(levende, nået via TO sidegrene)
  //        └─ Gren2 ─ Faelles(samme person, samme id — konvergent slægtskab, ikke datafejl)
  const db: Db = {
    persons: [mk('Bedste', 'mand'), mk('Gren1', 'mand'), mk('Gren2', 'kvinde'), mk('ANKER', 'mand'), mk('Faelles', 'kvinde')],
    unions: [union('fBedste', 'Bedste'), union('fG1', 'Gren1'), { id: 'fG1G2', p1: 'Gren1', p2: 'Gren2', p2_name: null, year: null }],
    parentChild: [
      pc('Gren1', 'Bedste', 'fBedste'), pc('Gren2', 'Bedste', 'fBedste'), pc('ANKER', 'Bedste', 'fBedste'),
      // Faelles er barn af BÅDE Gren1 og Gren2 (som er søskende, gift med hinanden — konvergent
      // slægtskab, ikke en datafejl) — nås derfor ad to veje under ANKERs FARBROR/FARS SØSTER-gruppe.
      pc('Faelles', 'Gren1', 'fG1G2'), pc('Faelles', 'Gren2', 'fG1G2'),
    ],
  };
  const model = buildModel(db);
  const levende = { ANKER: true, Faelles: true };

  test('Faelles vises fuldt ud i den første gruppe, som krydshenvisning i den anden', () => {
    const g = buildPresensListe(model, [{ personId: 'ANKER', linje: 'I', gren: 1, raaVaerdi: 'I linje, 1. gren' }], levende).grene[0];
    // Gren1 og Gren2 er begge ANKERs søskende → begge i SAME søskende-gruppe (niveau 1) som roedder,
    // sorteret på fødselsår (begge null → id-orden: 'Gren1' < 'Gren2').
    const soeskende = g.grupper.find((x) => x.art === 'soeskende')!;
    const [rodGren1, rodGren2] = soeskende.roedder;
    expect(rodGren1.id).toBe('Gren1');
    expect(rodGren2.id).toBe('Gren2');
    // Faelles optræder under BEGGE — én gang fuldt, én gang som krydshenvisning.
    const faellesUnderGren1 = rodGren1.boern.find((b) => b.id === 'Faelles')!;
    const faellesUnderGren2 = rodGren2.boern.find((b) => b.id === 'Faelles')!;
    expect(faellesUnderGren1).toBeDefined();
    expect(faellesUnderGren2).toBeDefined();
    const krydsCount = [faellesUnderGren1, faellesUnderGren2].filter((n) => n.krydsReference).length;
    expect(krydsCount).toBe(1); // netop ÉN af de to er en krydshenvisning, den anden er den fulde node
    const fulde = faellesUnderGren1.krydsReference ? faellesUnderGren2 : faellesUnderGren1;
    expect(fulde.krydsReference).toBe(false);
  });

  test('krydshenvisning ændrer ikke dobbelt_naaet-advarslen (den dækker fortsat kun MELLEM grene)', () => {
    const liste = buildPresensListe(model, [{ personId: 'ANKER', linje: 'I', gren: 1, raaVaerdi: 'I linje, 1. gren' }], levende);
    // Faelles nås to gange INDEN FOR samme (eneste) gren — samlIds bruger et Set pr. gren,
    // så det tæller kun som ÉT gren-medlemskab. Ingen dobbelt_naaet-advarsel skal udløses.
    expect(liste.advarsler.filter((a) => a.art === 'dobbelt_naaet')).toHaveLength(0);
  });
});

// Facitliste for det OPRINDELIGT rapporterede fund (decisions.md, "kendt struktur-begrænsning"):
// ÉT pruneUndertrae-kalds EGEN rekursion (ikke to separate buildGren-sidegren-kald som ovenfor)
// støder på samme levende person ad to veje, fordi to søskende (R's børn) er gift med hinanden
// og har et fælles (levende) barn G. Før rettelsen blev den anden vej stille droppet (G's forælder
// kunne miste sin eneste levende-forbindelse); nu bliver G en krydshenvisning i stedet.
describe('pruneUndertrae — krydshenvisning INDEN FOR samme undertræ (oprindeligt rapporterede fund)', () => {
  test('R ─┬─ A ─┐ giver G som fuld node under A, krydshenvisning under B', () => {
    //    └─ B ─┘→ G (levende, barn af BÅDE A og B)
    const db: Db = {
      persons: [mk('R', 'mand'), mk('A', 'mand'), mk('B', 'kvinde'), mk('G', 'kvinde')],
      unions: [union('fR', 'R'), { id: 'fAB', p1: 'A', p2: 'B', p2_name: null, year: null }],
      parentChild: [pc('A', 'R', 'fR'), pc('B', 'R', 'fR'), pc('G', 'A', 'fAB'), pc('G', 'B', 'fAB')],
    };
    const model = buildModel(db);
    const node = pruneUndertrae(model, { G: true }, 'R'); // ÉT top-niveau-kald, ingen ekstern deling
    expect(node).not.toBeNull();
    const [rodA, rodB] = node!.boern; // sorteret på fødselsår (begge null) → id-orden: 'A' < 'B'
    expect(rodA.id).toBe('A');
    expect(rodB.id).toBe('B');
    const gUnderA = rodA.boern.find((b) => b.id === 'G')!;
    const gUnderB = rodB.boern.find((b) => b.id === 'G')!;
    expect(gUnderA).toBeDefined();
    expect(gUnderB).toBeDefined();
    const krydsCount = [gUnderA, gUnderB].filter((n) => n.krydsReference).length;
    expect(krydsCount).toBe(1);
    const fulde = gUnderA.krydsReference ? gUnderB : gUnderA;
    expect(fulde.krydsReference).toBe(false);
  });
});
