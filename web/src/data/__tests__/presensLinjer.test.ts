import { mapPresensLinjer, pickPresensIntro } from '../presensLinjer';

test('mapPresensLinjer: kobler lineage-rækker til deres våben-media via relation', () => {
  const lineageRows = [
    { id: 1, kode: 'I', navn: 'Den holstenske linje', slaegtsnavn: 'Reventlow' },
    { id: 2, kode: 'II', navn: 'Linjen Gallentin', slaegtsnavn: null },
  ];
  const vaabenRel = [{ subjekt_id: 1, objekt_id: 100 }];
  const media = { id: 'm1', slags: 'foto', titel: '', kunstner: '', datering: '', url: 'https://x/1.png', thumbUrl: null };
  const mediaByArm = new Map([['100', [media]]]);
  const result = mapPresensLinjer(lineageRows, vaabenRel, mediaByArm);
  expect(result['I']).toEqual({ titel: 'Den holstenske linje', slaegtsnavn: 'Reventlow', vaaben: media });
  expect(result['II']).toEqual({ titel: 'Linjen Gallentin', slaegtsnavn: null, vaaben: null });
});

test('mapPresensLinjer: linje uden vaaben-relation får vaaben=null', () => {
  const lineageRows = [{ id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow' }];
  const result = mapPresensLinjer(lineageRows, [], new Map());
  expect(result['V'].vaaben).toBeNull();
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
