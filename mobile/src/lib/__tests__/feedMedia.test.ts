import { buildMobileFeedMediaItems, selectMobileFeedMedia } from '../feedMedia';
import type { FeedCard } from '@daa/feed';
import type { RawMedia } from '../../data/types';

const raw = [
  { id: 1, slags: 'segl', storage_path: 'large/1.jpg', medium_storage_path: 'medium/1.jpg' },
  { id: 2, slags: 'maleri', storage_path: 'large/2.jpg', primaer: true },
  { id: 3, slags: 'brev', storage_path: null },
] satisfies RawMedia[];

const card = (id: string, kind: FeedCard['kind']): Pick<FeedCard, 'id' | 'kind'> => ({ id, kind } as Pick<FeedCard, 'id' | 'kind'>);

describe('selectMobileFeedMedia', () => {
  test('vælger primært portræt først og udelader medier uden original sti', () => {
    expect(selectMobileFeedMedia(card('portrait:42', 'portrait'), '42', raw)).toEqual([raw[1], raw[0]]);
  });

  test('vælger stabilt højst fire medier til historie- og arkivkort', () => {
    const media = Array.from({ length: 6 }, (_, index) => ({
      id: index + 1,
      slags: 'foto',
      storage_path: `large/${index + 1}.jpg`,
    } satisfies RawMedia));

    const historie = card('historie:42', 'historie');
    const arkiv = card('arkiv:42', 'arkiv');
    expect(selectMobileFeedMedia(historie, '42', media).map((item) => item.id))
      .toEqual(selectMobileFeedMedia(historie, '42', [...media].reverse()).map((item) => item.id));
    expect(selectMobileFeedMedia(historie, '42', media)).toHaveLength(4);
    expect(selectMobileFeedMedia(arkiv, '42', media).map((item) => item.id))
      .toEqual(selectMobileFeedMedia(arkiv, '42', [...media].reverse()).map((item) => item.id));
    expect(selectMobileFeedMedia(arkiv, '42', media)).toHaveLength(4);
  });

  test('bevarer den primære rå række når et medie-id forekommer flere gange', () => {
    const duplicate = { id: 7, slags: 'maleri', storage_path: 'large/7-primary.jpg', primaer: true } satisfies RawMedia;
    const selected = selectMobileFeedMedia(card('portrait:7', 'portrait'), '7', [
      { id: 7, slags: 'maleri', storage_path: 'large/7.jpg' },
      duplicate,
    ]);

    expect(selected).toEqual([duplicate]);
  });
});

describe('buildMobileFeedMediaItems', () => {
  test('kræver stor URI, bruger medium når den findes og bevarer nullable billedtekster', () => {
    const selected = [
      { id: 1, slags: 'segl', titel: null, kunstner: null, datering: null, storage_path: 'large/1.jpg' },
      { id: 2, slags: 'maleri', titel: 'Portræt', kunstner: 'Maler', datering: '1700', storage_path: 'large/2.jpg' },
    ] satisfies RawMedia[];

    expect(buildMobileFeedMediaItems(selected, {
      '1': 'signed-large-1',
      '2': 'signed-large-2',
    }, {
      '1': 'signed-medium-1',
    })).toEqual([
      {
        id: '1', slags: 'segl', titel: null, kunstner: null, datering: null,
        largeUri: 'signed-large-1', mediumUri: 'signed-medium-1',
      },
      {
        id: '2', slags: 'maleri', titel: 'Portræt', kunstner: 'Maler', datering: '1700',
        largeUri: 'signed-large-2', mediumUri: 'signed-large-2',
      },
    ]);
  });

  test('filtrerer kun mediet der mangler en stor URI', () => {
    const selected = [
      { id: 1, slags: 'segl', storage_path: 'large/1.jpg' },
      { id: 2, slags: 'maleri', storage_path: 'large/2.jpg' },
    ] satisfies RawMedia[];

    expect(buildMobileFeedMediaItems(selected, { '2': 'signed-large-2' }, {})).toEqual([
      {
        id: '2', slags: 'maleri', titel: null, kunstner: null, datering: null,
        largeUri: 'signed-large-2', mediumUri: 'signed-large-2',
      },
    ]);
  });
});
