import { tilhoererLinje } from '../estateTilhoerer';

test('gård: periode får parentes kun hvis den mangler', () => {
  expect(tilhoererLinje({ omfattede: [], hoererUnder: [{ id: '7', navn: 'Grevskabet', periode: '1700-1800' }] })).toBe('Hørte under Grevskabet (1700-1800)');
  expect(tilhoererLinje({ omfattede: [], hoererUnder: [{ id: '7', navn: 'Grevskabet', periode: '(1700)' }] })).toBe('Hørte under Grevskabet (1700)');
  expect(tilhoererLinje({ omfattede: [], hoererUnder: [{ id: '7', navn: 'Grevskabet', periode: '' }] })).toBe('Hørte under Grevskabet');
});
test('majorat: Omfattede; tom når intet', () => {
  expect(tilhoererLinje({ hoererUnder: [], omfattede: [{ id: '1', navn: 'A' }, { id: '2', navn: 'B' }] })).toBe('Omfattede: A, B');
  expect(tilhoererLinje({ hoererUnder: [], omfattede: [] })).toBe('');
});
