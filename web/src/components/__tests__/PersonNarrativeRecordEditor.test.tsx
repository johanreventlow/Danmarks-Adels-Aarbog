// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { PersonNarrativeRecordEditor } from '../PersonNarrativeRecordEditor';
import { fetchOverviewMarks, fetchPersonNarrativeRecords } from '../../data/redaktionRead';

vi.mock('../../data/redaktionRead', () => ({ fetchPersonNarrativeRecords: vi.fn(), fetchOverviewMarks: vi.fn() }));

const record = (overrides: Record<string, unknown> = {}) => ({
  sourceId: 2018,
  sourceYear: 2018,
  sourceLabel: 'DAA 2018-20',
  recordKey: 'R-20',
  sourceRecordRef: 'record-20',
  status: 'none',
  stateSha256: 'a'.repeat(64),
  text: '',
  recordLabel: 'Kildepost 20',
  citationLabel: 'DAA 2018-20, s. 20',
  allowedActions: ['create_draft'],
  blockingReason: null,
  ...overrides,
});

const legacy = (overrides: Record<string, unknown> = {}) => ({
  legacyPublicationRef: 'legacy-1',
  sourceId: 19,
  narrativeId: 501,
  status: 'legacy_active',
  stateSha256: 'b'.repeat(64),
  text: 'Bevaret overgangstekst',
  allowedActions: ['withdraw_legacy'],
  blockingReason: null,
  ...overrides,
});

beforeEach(() => {
  vi.clearAllMocks();
  (fetchOverviewMarks as ReturnType<typeof vi.fn>).mockResolvedValue({ bySource: new Map(), byNarrative: new Map() });
});

test('sorterer sources nyeste først og recordkort efter side før record key', async () => {
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({
    records: [
      record({ recordKey: 'R-20', recordLabel: 'Kildepost 20', citationLabel: 'DAA 2018-20, s. 20' }),
      record({ recordKey: 'R-05', recordLabel: 'Kildepost 05', citationLabel: 'DAA 2018-20, s. 5' }),
      record({ sourceId: 1939, sourceYear: 1939, sourceLabel: 'DAA 1939', recordKey: 'A-01', recordLabel: 'Kildepost 01', citationLabel: 'DAA 1939, s. 1' }),
    ],
    legacyPublications: [],
  });

  render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);

  await screen.findByRole('article', { name: /DAA 2018-20.*Kildepost 05/ });
  expect(screen.getAllByRole('article').map((card) => card.getAttribute('aria-label'))).toEqual([
    'DAA 2018-20 — Kildepost 05',
    'DAA 2018-20 — Kildepost 20',
    'DAA 1939 — Kildepost 01',
  ]);
});

test('viser kun autoriserede recordhandlinger og aldrig almindeligt gem for publiceret tekst', async () => {
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({
    records: [
      record({ recordKey: 'draft', recordLabel: 'Kladde', status: 'draft', text: 'Kladde', allowedActions: ['save_draft', 'discard_draft', 'publish'] }),
      record({ recordKey: 'published', recordLabel: 'Publiceret', status: 'published', text: 'Gammel tekst', allowedActions: ['publish_revision', 'withdraw'] }),
      record({ recordKey: 'stale', recordLabel: 'Stale', status: 'stale_published', allowedActions: ['revalidate'] }),
      record({ recordKey: 'withdrawn', recordLabel: 'Tilbagetrukket', status: 'withdrawn', allowedActions: ['create_draft'] }),
      record({ recordKey: 'blocked', recordLabel: 'Blokeret', status: 'blocked', allowedActions: [], blockingReason: 'NARRATIVE_RECORD_IDENTITY_REQUIRED' }),
    ],
    legacyPublications: [legacy(), legacy({ legacyPublicationRef: 'legacy-2', status: 'legacy_withdrawn', allowedActions: [] })],
  });
  const onChange = vi.fn().mockResolvedValue(true);
  render(<PersonNarrativeRecordEditor personId={5} onChange={onChange} />);

  expect(await screen.findByRole('button', { name: 'Gem kladde' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Gem kladde' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Kassér kladde' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Publicér' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Publicér ændring' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Træk publicering tilbage' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Genvalidér publicering' })).toBeTruthy();
  expect(screen.getByText('NARRATIVE_RECORD_IDENTITY_REQUIRED')).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Gem publiceret tekst' })).toBeNull();
  expect(screen.getByLabelText('Tekst for Tilbagetrukket')).toBeTruthy();

  fireEvent.change(screen.getByLabelText('Tekst for Publiceret'), { target: { value: 'Ny publiceret tekst' } });
  expect(screen.getByText('Før publicering')).toBeTruthy();
  expect(screen.getByText('Gammel tekst')).toBeTruthy();
  expect(screen.getByText('Efter publicering')).toBeTruthy();
  expect(screen.getByLabelText('Publiceringskonsekvens').textContent).toContain('Ny publiceret tekst');
  fireEvent.click(screen.getByRole('button', { name: 'Publicér ændring' }));
  await waitFor(() => expect(onChange).toHaveBeenCalledWith(expect.objectContaining({
    art: 'narrativRecord',
    payload: expect.objectContaining({ action: 'publish_revision', recordKey: 'published', tekst: 'Ny publiceret tekst' }),
  }), 'Publicér ændring'));
});

test('tekstfeltet følger serverens autoriserede teksthandlinger', async () => {
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({
    records: [
      record({ recordKey: 'withdraw-only', recordLabel: 'Kun nedtagning', status: 'published', text: 'Offentlig tekst', allowedActions: ['withdraw'] }),
      record({ recordKey: 'withdrawn', recordLabel: 'Tilbagetrukket', status: 'withdrawn', text: 'Gammel kladde', allowedActions: ['create_draft'] }),
    ],
    legacyPublications: [],
  });
  render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);

  await screen.findByText('Kun nedtagning');
  expect(screen.queryByLabelText('Tekst for Kun nedtagning')).toBeNull();
  expect(screen.getByText('Offentlig tekst')).toBeTruthy();
  expect((screen.getByLabelText('Tekst for Tilbagetrukket') as HTMLTextAreaElement).value).toBe('Gammel kladde');
});

test('en vellykket kassering fjerner lokal tekst før den friske servertilstand vises', async () => {
  const fetch = fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>;
  fetch
    .mockResolvedValueOnce({ records: [record({ status: 'draft', text: 'Serverkladde', allowedActions: ['save_draft', 'discard_draft'] })], legacyPublications: [] })
    .mockResolvedValueOnce({ records: [record({ status: 'none', text: '', allowedActions: ['create_draft'] })], legacyPublications: [] });
  const onChange = vi.fn().mockResolvedValue(true);
  render(<PersonNarrativeRecordEditor personId={5} onChange={onChange} />);

  const text = await screen.findByLabelText('Tekst for Kildepost 20');
  fireEvent.change(text, { target: { value: 'Lokal kladde der skal væk' } });
  fireEvent.click(screen.getByRole('button', { name: 'Kassér kladde' }));

  await waitFor(() => expect(fetch).toHaveBeenCalledTimes(2));
  expect((screen.getByLabelText('Tekst for Kildepost 20') as HTMLTextAreaElement).value).toBe('');
});

test('en dry-run beholder lokal tekst og genindlæser ikke uændret servertilstand', async () => {
  const fetch = fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>;
  fetch.mockResolvedValue({ records: [record({ status: 'draft', text: 'Serverkladde', allowedActions: ['save_draft'] })], legacyPublications: [] });
  const onChange = vi.fn().mockResolvedValue(false);
  render(<PersonNarrativeRecordEditor personId={5} onChange={onChange} />);

  const text = await screen.findByLabelText('Tekst for Kildepost 20');
  fireEvent.change(text, { target: { value: 'Lokal dry-run tekst' } });
  fireEvent.click(screen.getByRole('button', { name: 'Gem kladde' }));

  await waitFor(() => expect(onChange).toHaveBeenCalledTimes(1));
  expect((screen.getByLabelText('Tekst for Kildepost 20') as HTMLTextAreaElement).value).toBe('Lokal dry-run tekst');
  expect(fetch).toHaveBeenCalledTimes(1);
});

test('et sent svar fra den tidligere person kan ikke overskrive den nye person', async () => {
  let resolveFirst!: (value: { records: ReturnType<typeof record>[]; legacyPublications: [] }) => void;
  let resolveSecond!: (value: { records: ReturnType<typeof record>[]; legacyPublications: [] }) => void;
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>)
    .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = resolve; }))
    .mockImplementationOnce(() => new Promise((resolve) => { resolveSecond = resolve; }));
  const view = render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);
  view.rerender(<PersonNarrativeRecordEditor personId={6} onChange={vi.fn()} />);
  await waitFor(() => expect(fetchPersonNarrativeRecords).toHaveBeenCalledTimes(2));

  resolveSecond({ records: [record({ recordLabel: 'Person seks' })], legacyPublications: [] });
  expect(await screen.findByText('Person seks')).toBeTruthy();
  resolveFirst({ records: [record({ recordLabel: 'Person fem' })], legacyPublications: [] });

  await waitFor(() => expect(screen.queryByText('Person fem')).toBeNull());
});

test('legacy-nedtagning kræver begrundelse og en bekræftelse af netop den valgte biografi', async () => {
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({ records: [], legacyPublications: [legacy()] });
  const onChange = vi.fn().mockResolvedValue(true);
  render(<PersonNarrativeRecordEditor personId={5} onChange={onChange} />);

  fireEvent.click(await screen.findByRole('button', { name: 'Tag biografi ned' }));
  expect(screen.getByText(/kun den valgte overgangsbiografi/)).toBeTruthy();
  expect(screen.getByText(/Valgt biografi: Bevaret overgangstekst/)).toBeTruthy();
  const confirm = screen.getByRole('checkbox', { name: /Jeg bekræfter/ });
  const submit = screen.getByRole('button', { name: 'Bekræft nedtagning' });
  expect(submit.hasAttribute('disabled')).toBe(true);
  fireEvent.change(screen.getByLabelText('Begrundelse for nedtagning'), { target: { value: 'Samtykke trukket' } });
  fireEvent.click(confirm);
  fireEvent.click(submit);

  await waitFor(() => expect(onChange).toHaveBeenCalledWith(expect.objectContaining({
    art: 'narrativRecord',
    payload: expect.objectContaining({
      action: 'withdraw_legacy', legacyPublicationRef: 'legacy-1', expectedStateSha256: 'b'.repeat(64), begrundelse: 'Samtykke trukket',
    }),
  }), 'Tag biografi ned'));
});

test('stale state beholder lokal tekst og henter ny servertilstand uden automatisk replay', async () => {
  const fetch = fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>;
  const freshRecord = record({ status: 'draft', text: 'Ny servertekst', allowedActions: ['save_draft'], stateSha256: 'c'.repeat(64) });
  fetch
    .mockResolvedValueOnce({ records: [record({ status: 'draft', text: 'Servertekst', allowedActions: ['save_draft'] })], legacyPublications: [] })
    .mockResolvedValue({ records: [freshRecord], legacyPublications: [] });
  const onChange = vi.fn()
    .mockRejectedValueOnce(new Error('NARRATIVE_RECORD_STATE_STALE'))
    .mockResolvedValueOnce(false);
  render(<PersonNarrativeRecordEditor personId={5} onChange={onChange} />);

  fireEvent.change(await screen.findByLabelText('Tekst for Kildepost 20'), { target: { value: 'Min lokale tekst' } });
  fireEvent.click(screen.getByRole('button', { name: 'Gem kladde' }));

  expect(await screen.findByText('Din lokale tekst')).toBeTruthy();
  expect(screen.getByRole('alert').textContent).toContain('Min lokale tekst');
  expect(screen.getByText('Ny servertekst')).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Kopiér lokal tekst' })).toBeTruthy();
  expect(screen.getByRole('button', { name: 'Genindlæs' })).toBeTruthy();
  expect(onChange).toHaveBeenCalledTimes(1);
  expect(fetch).toHaveBeenCalledTimes(2);

  fireEvent.click(screen.getByRole('button', { name: 'Genindlæs' }));
  await waitFor(() => expect((screen.getByLabelText('Tekst for Kildepost 20') as HTMLTextAreaElement).value).toBe('Ny servertekst'));
  fireEvent.click(screen.getByRole('button', { name: 'Gem kladde' }));

  await waitFor(() => expect(onChange).toHaveBeenCalledTimes(2));
  expect(onChange).toHaveBeenNthCalledWith(2, expect.objectContaining({
    art: 'narrativRecord',
    payload: expect.objectContaining({
      action: 'save_draft', tekst: 'Ny servertekst', expectedStateSha256: 'c'.repeat(64),
    }),
  }), 'Gem kladde');
});

test('viser oversigtsmærke kun på kildens markerede narrativ', async () => {
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({
    records: [
      record({ recordKey: 'M', recordLabel: 'Markeret', text: 'Omtale' }),
      record({ sourceId: 1939, sourceYear: 1939, sourceLabel: 'DAA 1939', recordKey: 'A', recordLabel: 'Anden', citationLabel: 'DAA 1939, s. 1' }),
    ],
    legacyPublications: [],
  });
  (fetchOverviewMarks as ReturnType<typeof vi.fn>).mockResolvedValue({ bySource: new Map([[2018, 77]]), byNarrative: new Map([[900, 77]]) });
  render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);
  expect(await screen.findByText('Oversigtsomtale — vises ikke som biografi (detaljepost: person 77)')).toBeTruthy();
  expect(screen.getAllByText(/Oversigtsomtale —/)).toHaveLength(1);
  expect(fetchOverviewMarks).toHaveBeenCalledWith(5);
});

test('RPC-fejl på oversigtsmærket giver intet mærke og editoren vises', async () => {
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({ records: [record({ recordLabel: 'Kildepost 20' })], legacyPublications: [] });
  (fetchOverviewMarks as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('REDAKTION_REQUIRED'));
  render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);
  expect(await screen.findByRole('article', { name: /Kildepost 20/ })).toBeTruthy();
  await waitFor(() => expect(warn).toHaveBeenCalled());
  expect(screen.queryByText(/Oversigtsomtale —/)).toBeNull();
  expect(screen.queryByRole('alert')).toBeNull();
  warn.mockRestore();
});

test('overgangsbiografi får oversigtsmærket på sin egen narrativ, ikke på udgaven', async () => {
  (fetchOverviewMarks as ReturnType<typeof vi.fn>).mockResolvedValue({ bySource: new Map([[19, 7]]), byNarrative: new Map([[501, 7]]) });
  (fetchPersonNarrativeRecords as ReturnType<typeof vi.fn>).mockResolvedValue({
    records: [],
    legacyPublications: [
      legacy(),
      legacy({ legacyPublicationRef: 'legacy-2', sourceId: 20, narrativeId: 502 }),
      legacy({ legacyPublicationRef: 'legacy-3', sourceId: null, narrativeId: 503 }),
      // Samme kilde som den markerede, men en anden narrativ: intet mærke.
      legacy({ legacyPublicationRef: 'legacy-4', sourceId: 19, narrativeId: 504 }),
    ],
  });

  render(<PersonNarrativeRecordEditor personId={5} onChange={vi.fn()} />);

  const cards = await screen.findAllByRole('article', { name: 'Overgangsbiografi' });
  expect(cards).toHaveLength(4);
  expect(within(cards[0]).getByRole('note').textContent).toBe('Oversigtsomtale — vises ikke som biografi (detaljepost: person 7)');
  expect(within(cards[1]).queryByRole('note')).toBeNull();
  expect(within(cards[2]).queryByRole('note')).toBeNull();
  expect(within(cards[3]).queryByRole('note')).toBeNull();
  expect(fetchOverviewMarks).toHaveBeenCalledTimes(1);
});
