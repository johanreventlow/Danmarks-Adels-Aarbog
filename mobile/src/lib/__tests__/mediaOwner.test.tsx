import { act, render } from '@testing-library/react-native';
import { Text } from 'react-native';
import type { RawMedia } from '../../data/types';
import { useMediaAndThumbUris } from '../media';

type SignResult = { data: Array<{ path: string; signedUrl: string }>; error: null };
type Deferred<T> = { promise: Promise<T>; resolve(value: T): void };

const mockCreateSignedUrls = jest.fn<Promise<SignResult>, [string[], number]>();

jest.mock('../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: jest.fn(() => ({ data: { subscription: { unsubscribe: jest.fn() } } })) },
    storage: { from: jest.fn(() => ({ createSignedUrls: mockCreateSignedUrls })) },
  },
}));

const mediaFor = (path: string) => [{ id: '1', storage_path: path }] satisfies RawMedia[];

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

function Probe({ ownerId, path }: { ownerId: string; path: string }) {
  const { uris } = useMediaAndThumbUris(mediaFor(path), () => null, ownerId);
  return <Text>{uris['1'] ?? 'tom'}</Text>;
}

describe('useMediaAndThumbUris owner-invalidering', () => {
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

  test('rydder straks den gamle ejers URI og resolvér samme path for den nye ejer', async () => {
    const view = render(<Probe ownerId="ejer-a" path="large/first.jpg" />);
    await act(async () => { requests[0].resolve({ data: [{ path: 'large/first.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('a-url')).toBeTruthy();

    view.rerender(<Probe ownerId="ejer-b" path="large/first.jpg" />);

    expect(view.queryByText('a-url')).toBeNull();
    expect(view.getByText('tom')).toBeTruthy();
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);

    await act(async () => { requests[1].resolve({ data: [{ path: 'large/first.jpg', signedUrl: 'b-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('b-url')).toBeTruthy();
  });

  test('afviser den gamle ejers sene signeringssvar efter ejerskifte', async () => {
    const view = render(<Probe ownerId="ejer-a" path="large/late.jpg" />);

    view.rerender(<Probe ownerId="ejer-b" path="large/late.jpg" />);
    expect(view.getByText('tom')).toBeTruthy();
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);

    await act(async () => { requests[0].resolve({ data: [{ path: 'large/late.jpg', signedUrl: 'a-url' }], error: null }); await Promise.resolve(); });
    expect(view.queryByText('a-url')).toBeNull();
    expect(view.getByText('tom')).toBeTruthy();

    await act(async () => { requests[1].resolve({ data: [{ path: 'large/late.jpg', signedUrl: 'b-url' }], error: null }); await Promise.resolve(); });
    expect(view.getByText('b-url')).toBeTruthy();
  });
});
