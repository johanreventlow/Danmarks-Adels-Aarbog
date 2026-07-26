import { act, render } from '@testing-library/react-native';
import { Text } from 'react-native';
import type { RawMedia } from '../../data/types';
import { signPaths, useMediaAndThumbUris } from '../media';
import { fetchExistingMediaBySha } from '../../data/mediaDedup';

type SignResult = { data: Array<{ path: string; signedUrl: string }>; error: null };
type Deferred<T> = { promise: Promise<T>; resolve(value: T): void };

const mockCreateSignedUrls = jest.fn<Promise<SignResult>, [string[], number]>();
type AuthListener = (event: string, session: { user: { id: string }; access_token: string } | null) => void;

jest.mock('../supabase', () => {
  const auth = { listener: null as AuthListener | null };
  return {
    __mockAuth: auth,
    supabase: {
      auth: { onAuthStateChange: jest.fn((listener) => {
        auth.listener = listener;
        return { data: { subscription: { unsubscribe: jest.fn() } } };
      }) },
      storage: { from: jest.fn(() => ({ createSignedUrls: mockCreateSignedUrls })) },
    },
  };
});

const mediaFor = (path: string) => [{ id: '1', storage_path: path }] satisfies RawMedia[];

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

function Probe({ path }: { path: string }) {
  const { uris } = useMediaAndThumbUris(mediaFor(path), () => null);
  return <Text>{uris['1'] ?? 'tom'}</Text>;
}

function authEvent(userId: string, token: string) {
  const { __mockAuth } = jest.requireMock('../supabase') as { __mockAuth: { listener: AuthListener | null } };
  if (!__mockAuth.listener) throw new Error('auth-listener mangler');
  __mockAuth.listener('TOKEN_REFRESHED', { user: { id: userId }, access_token: token });
}

describe('useMediaAndThumbUris auth-epoch-invalidering', () => {
  let requests: Deferred<SignResult>[];

  beforeEach(() => {
    requests = [];
    mockCreateSignedUrls.mockReset();
    mockCreateSignedUrls.mockImplementation(() => {
      const request = deferred<SignResult>();
      requests.push(request);
      return request.promise;
    });
  });

  test('rydder straks URI og resolvér samme path ved token-refresh for samme bruger', async () => {
    const view = render(<Probe path="large/first.jpg" />);
    await act(async () => { requests[0].resolve({ data: [{ path: 'large/first.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('a-url')).toBeTruthy();

    act(() => { authEvent('ejer-a', 'fornyet-token'); });

    expect(view.queryByText('a-url')).toBeNull();
    expect(view.getByText('tom')).toBeTruthy();
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);

    await act(async () => { requests[1].resolve({ data: [{ path: 'large/first.jpg', signedUrl: 'b-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('b-url')).toBeTruthy();
  });

  test('rydder og resolvér igen når auth-eventet skifter bruger-id', async () => {
    const view = render(<Probe path="large/new-user.jpg" />);
    await act(async () => { requests[0].resolve({ data: [{ path: 'large/new-user.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('a-url')).toBeTruthy();

    act(() => { authEvent('ejer-b', 'nyt-bruger-token'); });
    expect(view.getByText('tom')).toBeTruthy();
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);

    await act(async () => { requests[1].resolve({ data: [{ path: 'large/new-user.jpg', signedUrl: 'b-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('b-url')).toBeTruthy();
  });

  test('afviser den gamle auth-epochs sene signeringssvar', async () => {
    const view = render(<Probe path="large/late.jpg" />);

    act(() => { authEvent('ejer-a', 'fornyet-token'); });
    expect(view.getByText('tom')).toBeTruthy();
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);

    await act(async () => { requests[0].resolve({ data: [{ path: 'large/late.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });
    expect(view.queryByText('a-url')).toBeNull();
    expect(view.getByText('tom')).toBeTruthy();

    await act(async () => { requests[1].resolve({ data: [{ path: 'large/late.jpg', signedUrl: 'b-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('b-url')).toBeTruthy();
  });

  test('skriver ikke efter unmount når et deferred svar lander', async () => {
    const updateError = jest.spyOn(console, 'error').mockImplementation(() => {});
    const view = render(<Probe path="large/unmount.jpg" />);

    view.unmount();
    await act(async () => { requests[0].resolve({ data: [{ path: 'large/unmount.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });

    expect(updateError).not.toHaveBeenCalled();
    updateError.mockRestore();
  });

  test('direkte signPaths fejler sikkert, når auth-epoch skifter under signering', async () => {
    const signed = signPaths(['large/direct.jpg']);
    act(() => { authEvent('ejer-a', 'fornyet-token'); });
    await act(async () => { requests[0].resolve({ data: [{ path: 'large/direct.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });

    await expect(signed).resolves.toEqual(new Map());
  });

  test('dedup-hit med miniature falder bort, når auth-epoch skifter under signering', async () => {
    const hit = fetchExistingMediaBySha('sha', {
      mediaLookup: async () => ({ data: { id: '1', titel: 'Eksisterende', upload_status: 'klar', storage_path: 'large/dedup.jpg' }, error: null }),
      thumbPath: async () => 'thumb/dedup.jpg',
    });
    await act(async () => { await Promise.resolve(); await Promise.resolve(); });
    act(() => { authEvent('ejer-a', 'fornyet-token'); });
    await act(async () => {
      requests[0].resolve({ data: [{ path: 'large/dedup.jpg', signedUrl: 'large-url' }, { path: 'thumb/dedup.jpg', signedUrl: 'thumb-url' }], error: null });
      await Promise.resolve();
    });

    await expect(hit).resolves.toBeNull();
  });
});
