import { mapPresensLinjer, pickPresensIntro } from '../presensLinjer';

test('mapPresensLinjer: nøgles på presens_kode, ikke kode — kobler til våben-media via relation', () => {
  const lineageRows = [
    { id: 4, kode: 'IV', navn: 'Den lensgrevelige linje af 1767', slaegtsnavn: 'Reventlou', presens_kode: 'I' },
    { id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', presens_kode: 'II' },
  ];
  const vaabenRel = [{ subjekt_id: 4, objekt_id: 100 }];
  const media = { id: 'm1', slags: 'foto', titel: '', kunstner: '', datering: '', url: 'https://x/1.png', thumbUrl: null };
  const mediaByArm = new Map([['100', [media]]]);
  const result = mapPresensLinjer(lineageRows, vaabenRel, mediaByArm);
  expect(result['I']).toEqual({ titel: 'Den lensgrevelige linje af 1767', slaegtsnavn: 'Reventlou', vaaben: media });
  expect(result['II']).toEqual({ titel: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', vaaben: null });
});

test('mapPresensLinjer: linje uden vaaben-relation får vaaben=null', () => {
  const lineageRows = [{ id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', presens_kode: 'II' }];
  const result = mapPresensLinjer(lineageRows, [], new Map());
  expect(result['II'].vaaben).toBeNull();
});

test('mapPresensLinjer: uddød linje uden presens_kode udelades — kollisionsfri selvom kode="I" allerede findes', () => {
  const lineageRows = [
    { id: 1, kode: 'I', navn: 'Den holstenske linje', slaegtsnavn: null, presens_kode: null }, // uddød, ikke i præsenslisten
    { id: 4, kode: 'IV', navn: 'Den lensgrevelige linje af 1767', slaegtsnavn: 'Reventlou', presens_kode: 'I' },
  ];
  const result = mapPresensLinjer(lineageRows, [], new Map());
  expect(Object.keys(result)).toEqual(['I']);
  expect(result['I'].titel).toBe('Den lensgrevelige linje af 1767'); // IKKE den uddøde Holstenske linje
});

test('pickPresensIntro: filtrerer til source.slags=præsens-intro, vælger seneste id', () => {
  const rows = [
    { id: 1, tekst: 'gammel intro', source: { slags: 'præsens-intro' } },
    { id: 2, tekst: 'ny intro', source: { slags: 'præsens-intro' } },
    { id: 3, tekst: 'anden kilde', source: { slags: 'DAA-udgave' } },
  ];
  expect(pickPresensIntro(rows)).toBe('ny intro');
});

test('pickPresensIntro: ingen matchende kilde giver null', () => {
  expect(pickPresensIntro([{ id: 1, tekst: 'x', source: { slags: 'DAA-udgave' } }])).toBeNull();
  expect(pickPresensIntro([])).toBeNull();
});

test('pickPresensIntro: tom tekst tælles ikke som kandidat', () => {
  expect(pickPresensIntro([{ id: 1, tekst: '  ', source: { slags: 'præsens-intro' } }])).toBeNull();
});
