import { act, fireEvent, render, type RenderResult } from '@testing-library/react-native';
import { useCallback } from 'react';
import { Text } from 'react-native';
import { useHentning } from '../useHentning';

type Deferred<T> = { promise: Promise<T>; resolve(v: T): void; reject(e: unknown): void };
function deferred<T>(): Deferred<T> {
  let resolve!: (v: T) => void; let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

// Hver hentning får sit eget løfte, så testen bestemmer rækkefølgen svarene lander i.
let kald: { id: string; d: Deferred<string> }[];
const mockHent = (id: string) => { const d = deferred<string>(); kald.push({ id, d }); return d.promise; };

// Tryk på teksten = genhent (som »Prøv igen« i skærmen).
function Probe({ id }: { id: string | null }) {
  const h = useHentning<string>(id, useCallback(() => mockHent(id!), [id]));
  return <Text testID="probe" onPress={() => { void h.genhent(); }}>{`${h.status}:${h.data ?? '-'}:${h.fejl ?? '-'}`}</Text>;
}
const genhent = (v: RenderResult) => { fireEvent.press(v.getByTestId('probe')); };

const lander = async (i: number, v: string) => { await act(async () => { kald[i].d.resolve(v); await Promise.resolve(); }); };
const fejler = async (i: number, e: unknown) => { await act(async () => { kald[i].d.reject(e); await Promise.resolve(); }); };

beforeEach(() => {
  kald = [];
  jest.spyOn(console, 'warn').mockImplementation(() => undefined);
});
afterEach(() => { jest.restoreAllMocks(); });

describe('useHentning', () => {
  test('henter → ok', async () => {
    const v = render(<Probe id="1" />);
    expect(v.getByText('henter:-:-')).toBeTruthy();
    await lander(0, 'p1');
    expect(v.getByText('ok:p1:-')).toBeTruthy();
  });

  test('en fejl er en fejl — ikke tomme data', async () => {
    const v = render(<Probe id="1" />);
    await fejler(0, { code: '57014', message: 'timeout' });
    expect(v.getByText('fejl:-:timeout')).toBeTruthy();
  });

  test('Prøv igen efter en fejl: henter, og lander', async () => {
    const v = render(<Probe id="1" />);
    await fejler(0, new Error('net'));
    genhent(v);
    expect(v.getByText('henter:-:-')).toBeTruthy();
    await lander(1, 'p1');
    expect(v.getByText('ok:p1:-')).toBeTruthy();
  });

  test('skift af id: det forrige ids sene svar kasseres, og dets data vises aldrig', async () => {
    const v = render(<Probe id="1" />);
    await lander(0, 'p1');
    v.rerender(<Probe id="2" />);
    expect(v.getByText('henter:-:-')).toBeTruthy();
    expect(kald[1].id).toBe('2');
    await lander(1, 'p2');
    expect(v.getByText('ok:p2:-')).toBeTruthy();
  });

  test('skift af id mens det forrige stadig henter: det gamle svar lander ikke', async () => {
    const v = render(<Probe id="1" />);
    v.rerender(<Probe id="2" />);
    await lander(1, 'p2');
    await lander(0, 'p1-sent');
    expect(v.getByText('ok:p2:-')).toBeTruthy();
    await fejler(0, new Error('sen fejl'));
    expect(v.getByText('ok:p2:-')).toBeTruthy();
  });

  test('to genindlæsninger i omvendt rækkefølge: den nyeste vinder', async () => {
    const v = render(<Probe id="1" />);
    await lander(0, 'v0');
    genhent(v); genhent(v);
    await lander(2, 'v2');
    await lander(1, 'v1-gammel');
    expect(v.getByText('ok:v2:-')).toBeTruthy();
  });

  test('fejlet genindlæsning beholder de hidtidige data og viser fejlen', async () => {
    const v = render(<Probe id="1" />);
    await lander(0, 'v0');
    genhent(v);
    await fejler(1, new Error('net'));
    expect(v.getByText('fejl:v0:net')).toBeTruthy();
  });

  test('efter unmount lander en sen fejl ikke', async () => {
    const v = render(<Probe id="1" />);
    v.unmount();
    await act(async () => { kald[0].d.reject(new Error('sen')); await Promise.resolve(); });
    expect(console.warn).not.toHaveBeenCalled();
  });

  test('id null: intet hentes', () => {
    const v = render(<Probe id={null} />);
    expect(kald).toHaveLength(0);
    expect(v.getByText('ok:-:-')).toBeTruthy();
  });
});
