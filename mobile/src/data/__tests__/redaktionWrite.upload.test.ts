const events: string[] = [];

jest.mock('../../lib/supabase', () => ({
  supabase: {
    rpc: jest.fn(async (fn: string) => {
      events.push(`rpc:${fn}`);
      return { data: fn === 'red_upload_media' ? 91 : null, error: null };
    }),
  },
}));

import { submitChange } from '../redaktionWrite';

beforeEach(() => { events.length = 0; });

it('holder ny media-række som kladde indtil alle varianter er uploadet og registreret', async () => {
  await submitChange({
    art: 'uploadMedia', subjektType: 'person', subjektId: '42',
    payload: {
      afbildetPersonId: '42', slags: 'foto', titel: 'Portræt',
      localUri: 'file:///large.jpg', storagePath: 'large.jpg', mimeType: 'image/jpeg',
      varianter: [{
        tier: 'thumb', uri: 'file:///thumb.jpg', storagePath: 'thumb.jpg',
        mimeType: 'image/jpeg', byteSize: 5, bredde: 300, hoejde: 200,
      }],
    },
  }, { dryRun: false }, {
    performUpload: async (_uri, path) => { events.push(`upload:${path}`); },
  });

  expect(events).toEqual([
    'upload:large.jpg',
    'rpc:red_upload_media',
    'upload:thumb.jpg',
    'rpc:red_registrer_media_variant',
    'rpc:red_bekraeft_media_upload',
  ]);
});
