import { describe, expect, it } from 'vitest';
import { selectFeedMedia } from '../media';

type FixtureMedia = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  largePath: string;
  mediumPath: string | null;
  primaer?: boolean;
  fixtureOnly: string;
};

function m(id: string, slags: string, primaer = false): FixtureMedia {
  return {
    id,
    slags,
    titel: `Titel ${id}`,
    kunstner: `Kunstner ${id}`,
    datering: `Datering ${id}`,
    largePath: `/large/${id}.jpg`,
    mediumPath: `/medium/${id}.jpg`,
    ...(primaer ? { primaer: true } : {}),
    fixtureOnly: `bevar-${id}`,
  };
}

const media = [
  m('1', 'segl'),
  m('2', 'foto'),
  m('3', 'dokument', true),
  m('4', 'maleri'),
  m('5', 'brev'),
];

describe('selectFeedMedia', () => {
  it('vælger og roterer almindelige kort deterministisk', () => {
    expect(selectFeedMedia('arkiv:a', 'arkiv', 'p1', media).map((item) => item.id))
      .toEqual(['1', '2', '3', '4']);
    expect(selectFeedMedia('historie:b', 'historie', 'p1', media).map((item) => item.id))
      .toEqual(['3', '4', '5', '1']);
  });

  it('sætter valgt portrætmedie først', () => {
    expect(selectFeedMedia('portrait:p1', 'portrait', 'p1', media).map((item) => item.id))
      .toEqual(['3', '4', '5', '1']);
  });

  it('returnerer tomt for tomt input og bevarer ét input', () => {
    expect(selectFeedMedia('tom', 'arkiv', 'p1', [])).toEqual([]);
    expect(selectFeedMedia('enkelt', 'arkiv', 'p1', [media[0]])).toEqual([media[0]]);
  });

  it('lader en primær dublet vinde i begge inputordener', () => {
    const plain = m('5', 'brev');
    const primary = m('5', 'brev', true);

    for (const input of [[plain, primary], [primary, plain]]) {
      const selected = selectFeedMedia('dublet', 'arkiv', 'p1', input);
      expect(selected).toHaveLength(1);
      expect(selected[0].id).toBe('5');
      expect(selected[0].primaer).toBe(true);
    }
  });

  it('foretrækker et normaliseret portræt når ingen eksplicit primær findes', () => {
    const selected = selectFeedMedia('portraet', 'portrait', 'p1', [
      m('1', 'segl'),
      m('2', ' Portræt '),
      m('3', 'brev'),
    ]);

    expect(selected[0].id).toBe('2');
  });

  it('respekterer limit', () => {
    expect(selectFeedMedia('arkiv:a', 'arkiv', 'p1', media, 2).map((item) => item.id))
      .toEqual(['1', '2']);
    expect(selectFeedMedia('arkiv:a', 'arkiv', 'p1', media, 0)).toEqual([]);
  });

  it('giver samme ids for inputpermutationer og bevarer ekstra felter', () => {
    const forward = selectFeedMedia('historie:b', 'historie', 'p1', media);
    const reverse = selectFeedMedia('historie:b', 'historie', 'p1', [...media].reverse());

    expect(forward.map((item) => item.id)).toEqual(reverse.map((item) => item.id));
    expect(forward[0].fixtureOnly).toBe('bevar-3');
  });
});
