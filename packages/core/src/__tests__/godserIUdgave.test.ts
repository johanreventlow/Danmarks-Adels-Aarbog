// Personsidens godser i den valgte udgave (spec §5.8) — reglen, web's personside og mobilens personskærm deler.
import { describe, expect, it } from 'vitest';
import { godserIUdgave } from '../godserIUdgave';
import type { UdgaveFaktaInput } from '../editionFacts';
import type { PublicPersonFactRow } from '../personFacts';

const udgaver = [{ sourceId: '1', label: 'DAA 1939', aar: 1939 }, { sourceId: '2', label: 'DAA 2018-20', aar: 2018 }];
// Personrække 70 har fakta citeret fra 2018-20 (source 2); 71 kendes kun på sin eksterne nøgle (1939); 72's eksterne nøgle
// peger på en kilde, der ikke er en DAA-udgave; 73 kendes slet ikke.
const input: UdgaveFaktaInput = {
  rows: [{ person_id: 70, source_id: 2 } as PublicPersonFactRow],
  udgaver,
  udgaveForPersonRaekke: { '71': '1', '72': '99' },
  fritekstKilde: {},
};
const g = (id: string, personId: string) => ({ id, navn: `Gods ${id}`, personId });
const alle = [g('a', '70'), g('b', '71'), g('c', '72'), g('d', '73')];

describe('godserIUdgave', () => {
  it('2018-20 valgt: rækken fra 2018-20 og rækkerne uden kendt udgave, ikke 1939-rækken', () => {
    expect(godserIUdgave(alle, input, udgaver, '2').map((e) => e.id)).toEqual(['a', 'c', 'd']);
  });
  it('1939 valgt: 1939-rækken (ekstern nøgle) og rækkerne uden kendt udgave', () => {
    expect(godserIUdgave(alle, input, udgaver, '1').map((e) => e.id)).toEqual(['b', 'c', 'd']);
  });
  it('uden valgt udgave eller uden fakta-input: alle', () => {
    expect(godserIUdgave(alle, input, udgaver, null)).toHaveLength(4);
    expect(godserIUdgave(alle, null, udgaver, '2')).toHaveLength(4);
  });
});
