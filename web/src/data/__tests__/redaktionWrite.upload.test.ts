import { beforeEach, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ events: [] as string[] }));

vi.mock('../../supabase', () => ({
  supabase: {
    rpc: vi.fn(async (fn: string) => {
      state.events.push(`rpc:${fn}`);
      return { data: fn === 'red_upload_media' ? 91 : null, error: null };
    }),
  },
}));

vi.mock('../mediaUpload', () => ({
  performUpload: vi.fn(async (_file: Blob, path: string) => {
    state.events.push(`upload:${path}`);
  }),
}));

import { submitChange } from '../redaktionWrite';

beforeEach(() => { state.events = []; });

it('holder ny media-række som kladde indtil alle varianter er uploadet og registreret', async () => {
  await submitChange({
    art: 'uploadMedia', subjektType: 'person', subjektId: '42',
    payload: {
      afbildetPersonId: '42', slags: 'foto', titel: 'Portræt',
      file: new Blob(['large']), storagePath: 'large.jpg', mimeType: 'image/jpeg',
      varianter: [{
        tier: 'thumb', file: new Blob(['thumb']), storagePath: 'thumb.jpg',
        mimeType: 'image/jpeg', byteSize: 5, bredde: 300, hoejde: 200,
      }],
    },
  }, { dryRun: false, role: 'redaktion' });

  expect(state.events).toEqual([
    'upload:large.jpg',
    'rpc:red_upload_media',
    'upload:thumb.jpg',
    'rpc:red_registrer_media_variant',
    'rpc:red_bekraeft_media_upload',
  ]);
});
