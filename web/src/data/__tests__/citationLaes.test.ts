import { afterEach, expect, test, vi } from 'vitest';
import { laesCitationer } from '../citationLaes';
import { citationRowsTilProveniens, type RaaCitationRow } from '@daa/core';

afterEach(() => vi.restoreAllMocks());

test('første kald lykkes: ingen gentagelse', async () => {
  const f = vi.fn().mockResolvedValue({ data: [{ a: 1 }], error: null });
  expect(await laesCitationer(f)).toEqual([{ a: 1 }]);
  expect(f).toHaveBeenCalledTimes(1);
  expect(f).toHaveBeenCalledWith(true);
});

test('første fejler, gentagelsen lykkes: data fra gentagelsen og én warn', async () => {
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const err = vi.spyOn(console, 'error').mockImplementation(() => {});
  const f = vi.fn().mockResolvedValueOnce({ data: null, error: { m: 'x' } }).mockResolvedValueOnce({ data: [{ b: 2 }], error: null });
  expect(await laesCitationer(f)).toEqual([{ b: 2 }]);
  expect(f.mock.calls).toEqual([[true], [false]]);
  expect(warn).toHaveBeenCalledTimes(1);
  expect(err).not.toHaveBeenCalled();
});

test('begge kald fejler: tom liste og én error', async () => {
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  const err = vi.spyOn(console, 'error').mockImplementation(() => {});
  const f = vi.fn().mockResolvedValue({ data: null, error: { m: 'x' } });
  expect(await laesCitationer(f)).toEqual([]);
  expect(err).toHaveBeenCalledTimes(1);
});

test('side_trykt-tilstedeværelse bevares, også når værdien er null', async () => {
  const f = vi.fn().mockResolvedValue({ data: [{ assertion_id: 1, side: '541', side_trykt: null, source: { titel: 'DAA 1939', udgave: null } }], error: null });
  const rows = (await laesCitationer(f)) as RaaCitationRow[];
  expect('side_trykt' in rows[0]).toBe(true);
  expect(citationRowsTilProveniens(rows, new Map([[1, '7']]))[0].side).toBeNull();
});
