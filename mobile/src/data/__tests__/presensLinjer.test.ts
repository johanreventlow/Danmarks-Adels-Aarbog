import { mapPresensLinjer, pickPresensIntro } from '../presensLinjer';

test('mapPresensLinjer: nøgles på presens_kode og kobler våbenets signerede URL', () => {
  const lineageRows = [
    { id: 4, kode: 'IV', navn: 'Den lensgrevelige linje af 1767', slaegtsnavn: 'Reventlou', presens_kode: 'I' },
    { id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', presens_kode: 'II' },
  ];
  const vaabenRel = [{ subjekt_id: 4, objekt_id: 100 }];
  const mediaRel = [{ subjekt_id: 501, objekt_id: 100 }];
  const mediaRows = [{ id: 501, storage_path: 'vaaben/linje-i.png' }];
  const signed = new Map([['vaaben/linje-i.png', 'https://x/linje-i.png']]);

  const result = mapPresensLinjer(lineageRows, vaabenRel, mediaRel, mediaRows, signed);

  expect(result['I']).toEqual({
    titel: 'Den lensgrevelige linje af 1767',
    slaegtsnavn: 'Reventlou',
    vaabenUrl: 'https://x/linje-i.png',
  });
  expect(result['II']).toEqual({
    titel: 'Den grevelige linje af 1673',
    slaegtsnavn: 'Reventlow',
    vaabenUrl: null,
  });
});

test('mapPresensLinjer: usignerbart eller manglende våben giver vaabenUrl=null', () => {
  const lineageRows = [
    { id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', presens_kode: 'II' },
  ];
  const result = mapPresensLinjer(
    lineageRows,
    [{ subjekt_id: 5, objekt_id: 100 }],
    [{ subjekt_id: 501, objekt_id: 100 }],
    [{ id: 501, storage_path: 'vaaben/mangler.png' }],
    new Map(),
  );

  expect(result['II'].vaabenUrl).toBeNull();
});

test('mapPresensLinjer: uddød linje uden presens_kode udelades', () => {
  const lineageRows = [
    { id: 1, kode: 'I', navn: 'Den holstenske linje', slaegtsnavn: null, presens_kode: null },
    { id: 4, kode: 'IV', navn: 'Den lensgrevelige linje af 1767', slaegtsnavn: 'Reventlou', presens_kode: 'I' },
  ];

  const result = mapPresensLinjer(lineageRows, [], [], [], new Map());

  expect(Object.keys(result)).toEqual(['I']);
  expect(result['I'].titel).toBe('Den lensgrevelige linje af 1767');
});

test('pickPresensIntro: filtrerer præsens-intro og vælger seneste id', () => {
  const rows = [
    { id: 1, tekst: 'gammel intro', source: { slags: 'præsens-intro' } },
    { id: 2, tekst: 'ny intro', source: { slags: 'præsens-intro' } },
    { id: 3, tekst: 'anden kilde', source: { slags: 'DAA-udgave' } },
  ];

  expect(pickPresensIntro(rows)).toBe('ny intro');
});

test('pickPresensIntro: ingen gyldig tekst giver null', () => {
  expect(pickPresensIntro([{ id: 1, tekst: 'x', source: { slags: 'DAA-udgave' } }])).toBeNull();
  expect(pickPresensIntro([{ id: 1, tekst: '  ', source: { slags: 'præsens-intro' } }])).toBeNull();
  expect(pickPresensIntro([])).toBeNull();
});

// --- Slægts-rod (B2): slaegtsnavn bor på roden og arves ned til grenene ---

test('mapPresensLinjer: gren uden eget slaegtsnavn arver slægts-rodens', () => {
  const lineageRows = [
    { id: 6, kode: null as never, navn: 'Reventlow', slaegtsnavn: 'Reventlow', presens_kode: null, parent_lineage_id: null },
    { id: 4, kode: 'IV', navn: 'Den lensgrevelige linje af 1767', slaegtsnavn: null, presens_kode: 'I', parent_lineage_id: 6 },
  ];
  const result = mapPresensLinjer(lineageRows, [], [], [], new Map());
  expect(result['I'].slaegtsnavn).toBe('Reventlow');
  expect(Object.keys(result)).toEqual(['I']);
});

test('mapPresensLinjer: gren med EGET slaegtsnavn vinder over rodens', () => {
  const lineageRows = [
    { id: 6, kode: null as never, navn: 'Reventlow', slaegtsnavn: 'Reventlow', presens_kode: null, parent_lineage_id: null },
    { id: 7, kode: 'VI', navn: 'Den grevelige linje', slaegtsnavn: 'Haugwitz-Hardenberg-Reventlow', presens_kode: 'III', parent_lineage_id: 6 },
  ];
  expect(mapPresensLinjer(lineageRows, [], [], [], new Map())['III'].slaegtsnavn)
    .toBe('Haugwitz-Hardenberg-Reventlow');
});
