import { parseNarrativ, groupBlocks } from '../mentions';

const blocks = (tekst: string) => groupBlocks(parseNarrativ(tekst));

describe('groupBlocks', () => {
  it('bare prosa uden linjeskift bliver ét paragraph-blok', () => {
    expect(blocks('Bare prosa.')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Bare prosa.' }] },
    ]);
  });

  it('tom tekst giver tomt array', () => {
    expect(blocks('')).toEqual([]);
  });

  it('## Overskrift alene bliver et heading-blok (level 2)', () => {
    expect(blocks('## Slægtens oprindelse')).toEqual([
      { kind: 'heading', level: 2, text: 'Slægtens oprindelse' },
    ]);
  });

  it('### bliver level 3', () => {
    expect(blocks('### Under-overskrift')).toEqual([
      { kind: 'heading', level: 3, text: 'Under-overskrift' },
    ]);
  });

  it('overskrift + blank linje + afsnit bliver to blokke', () => {
    expect(blocks('## Titel\n\nNæste afsnit.')).toEqual([
      { kind: 'heading', level: 2, text: 'Titel' },
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Næste afsnit.' }] },
    ]);
  });

  it('to linjer UDEN blank linje imellem forbliver ét afsnit med indlejret linjeskift', () => {
    expect(blocks('Linje1\nLinje2')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Linje1\nLinje2' }] },
    ]);
  });

  it('blank linje adskiller to afsnit', () => {
    expect(blocks('Første.\n\nAnden.')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Første.' }] },
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Anden.' }] },
    ]);
  });

  it('flere blanke linjer i træk giver ikke tomme afsnit', () => {
    expect(blocks('Første.\n\n\n\nAnden.')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Første.' }] },
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Anden.' }] },
    ]);
  });

  it('# uden mellemrum efter er IKKE en overskrift', () => {
    expect(blocks('#nospace er bare tekst')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: '#nospace er bare tekst' }] },
    ]);
  });

  it('media-token bliver sin egen blok og splitter omgivende tekst i to afsnit', () => {
    expect(blocks('Foto: [[media:5|Skjold]] Mere tekst.')).toEqual([
      { kind: 'paragraph', segs: [{ kind: 'text', text: 'Foto: ' }] },
      { kind: 'media', maalId: 5, label: 'Skjold' },
      { kind: 'paragraph', segs: [{ kind: 'text', text: ' Mere tekst.' }] },
    ]);
  });

  it('media-token som det ALLERFØRSTE giver ingen tom leder-paragraph', () => {
    expect(blocks('[[media:5|Skjold]] Tekst efter.')).toEqual([
      { kind: 'media', maalId: 5, label: 'Skjold' },
      { kind: 'paragraph', segs: [{ kind: 'text', text: ' Tekst efter.' }] },
    ]);
  });

  it('overskrift umiddelbart efterfulgt af media-token (ingen mellemliggende paragraph)', () => {
    expect(blocks('## Våben\n[[media:5|Skjold]]')).toEqual([
      { kind: 'heading', level: 2, text: 'Våben' },
      { kind: 'media', maalId: 5, label: 'Skjold' },
    ]);
  });

  it('person-mention (ikke-media) forbliver INLINE i det løbende afsnit', () => {
    expect(blocks('Se [[person:482|Chr. D. R.]] her.')).toEqual([
      { kind: 'paragraph', segs: [
        { kind: 'text', text: 'Se ' },
        { kind: 'link', maalType: 'person', maalId: 482, label: 'Chr. D. R.' },
        { kind: 'text', text: ' her.' },
      ] },
    ]);
  });
});
