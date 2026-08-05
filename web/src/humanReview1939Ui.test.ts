// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';

const uiSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/human_review_1939_ui.js',
), 'utf8');

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  };
}

function humanRecord(recordKey: string, candidateId: string) {
  return {
    record_key: recordKey,
    navn: `Navn ${recordKey}`,
    sider: '498',
    narrative: `Gammel tekst ${recordKey}`,
    queue_class: 'human_required',
    reason_code: 'no_candidate',
    reason_da: 'Ingen kandidat passer entydigt.',
    is_audit: false,
    is_completed: false,
    initial_candidate_ids: [candidateId],
    candidates: [{
      candidate_id: candidateId,
      lokal_id: candidateId,
      pdf_pages: [498],
      calamari_pages: [3],
      raw_text: `Ny OCR ${candidateId}`,
      rank_reason: 'samme_pdf_side',
    }],
    decision: null,
  };
}

function automaticRecord(recordKey: string, candidateId: string, audit = false) {
  return {
    ...humanRecord(recordKey, candidateId),
    queue_class: 'auto_resolved',
    reason_code: 'exact_anchor',
    reason_da: 'Automatisk afgjort med eksakte ankre.',
    is_audit: audit,
  };
}

function viewModel(records: any[], source = {}) {
  return {
    schema_version: 1,
    source: {
      edition: '1939', baseline_sha256: 'a'.repeat(64), calamari_sha256: 'b'.repeat(64),
      raw_ocr_sha256: 'c'.repeat(64), pdf_sha256: 'd'.repeat(64), profile_version: '1939-v2',
      ...source,
    },
    default_view: 'required',
    summary: { required: records.filter(r => r.queue_class !== 'auto_resolved').length,
      automatic: records.filter(r => r.queue_class === 'auto_resolved').length,
      audit: records.filter(r => r.is_audit).length, completed: 0, source_blocked: 0 },
    views: {
      required: records.filter(r => r.queue_class !== 'auto_resolved').map(r => r.record_key),
      automatic: records.filter(r => r.queue_class === 'auto_resolved').map(r => r.record_key),
      audit: records.filter(r => r.is_audit).map(r => r.record_key),
      completed: [],
    },
    records,
  };
}

function startReview({ storage, records, source, download = vi.fn() }: {
  storage: ReturnType<typeof memoryStorage>;
  records: any[];
  source?: Record<string, unknown>;
  download?: ReturnType<typeof vi.fn>;
}) {
  document.body.innerHTML = '<aside data-role="save-state"></aside><main data-role="app"></main>';
  window.eval(uiSource);
  return {
    controller: (window as any).DAA1939Review.init({ data: viewModel(records, source), storage,
      now: () => '2026-08-05T12:00:00+02:00', download }),
    download,
  };
}

afterEach(() => {
  document.body.innerHTML = '';
});

describe('human 1939 review controller', () => {
  it('records the candidate id, persists it, and confirms success', () => {
    const storage = memoryStorage();
    const { controller } = startReview({ storage, records: [humanRecord('rk-1', 'candidate-1')] });

    document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();

    expect(controller.exportDraft().entries[0]).toMatchObject({
      baseline_record_key: 'rk-1',
      outcome: 'human_selected_candidate',
      candidate_id: 'candidate-1',
    });
    expect(JSON.parse(storage.getItem(controller.storageKey)!)).toBeTruthy();
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain(
      'Visuelt spor er gemt lokalt',
    );
  });

  it('records each of the four review outcomes', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'candidate-1'), humanRecord('rk-2', 'candidate-2'),
      humanRecord('rk-3', 'candidate-3'), humanRecord('rk-4', 'candidate-4'),
    ] });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'candidate-1' })).toBe(true);
    expect(controller.choose('no_candidate_fits')).toBe(true);
    expect(controller.choose('possible_duplicate', { duplicate_of_baseline_record_key: 'rk-1' })).toBe(true);
    expect(controller.choose('undecidable')).toBe(true);

    expect(controller.exportDraft().entries.map((entry: any) => entry.outcome)).toEqual([
      'human_selected_candidate', 'no_candidate_fits', 'possible_duplicate', 'undecidable',
    ]);
  });

  it('preserves a hostile candidate id through click, storage and visible confirmation', () => {
    const storage = memoryStorage();
    const { controller } = startReview({ storage,
      records: [humanRecord('rk-1', 'Volrad "ældre"')] });

    document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();

    expect(controller.exportDraft().entries[0].candidate_id).toBe('Volrad "ældre"');
    expect(JSON.parse(storage.getItem(controller.storageKey)!).decisions['rk-1'].candidate_id)
      .toBe('Volrad "ældre"');
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('Visuelt spor er gemt lokalt');
  });

  it('restores persisted decisions after reload', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'candidate-1')];
    startReview({ storage, records }).controller.choose('human_selected_candidate', { candidate_id: 'candidate-1' });

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft().entries[0]).toMatchObject({
      baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'candidate-1',
    });
    expect(document.querySelector('[data-role="decision-state"]')!.textContent)
      .toContain('human_selected_candidate');
    expect(document.querySelector('[data-action="select-candidate"]')!.getAttribute('aria-pressed'))
      .toBe('true');
  });

  it('preserves completed decisions supplied by the view model', () => {
    const record = humanRecord('rk-1', 'candidate-1');
    record.decision = {
      baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'candidate-1',
    };
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('completed');

    expect(controller.selectedKey).toBe('rk-1');
    expect(controller.exportDraft().entries[0]).toMatchObject(record.decision);
  });

  it('accepts and visibly renders real legacy review-ledger decisions', () => {
    const records = [
      humanRecord('rk-unreviewed', 'c-1'), humanRecord('rk-accepted', 'c-2'),
      humanRecord('rk-duplicate', 'c-3'), humanRecord('rk-human', 'c-4'),
    ];
    records[0].decision = { baseline_record_key: 'rk-unreviewed', review_status: 'unreviewed',
      baseline_locator: { pages: '498', local_id: 'I.1' } };
    records[1].decision = { baseline_record_key: 'rk-accepted', review_status: 'accepteret',
      candidate_id: 'c-2', post_index: 0, calamari_span: { char_from: 0, char_to: 1 },
      calamari_verbatim_text: 'A', pdf_pages: [498], kind: 'line_header', raw_char_from: 0,
      raw_char_to: 1, raw_verbatim_text: 'A',
      raw_excerpt_sha256: '559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd' };
    records[2].decision = { baseline_record_key: 'rk-duplicate', review_status: 'eksplicit_dublet',
      duplicate_of_baseline_record_key: 'rk-unreviewed' };
    records[3].decision = { baseline_record_key: 'rk-human', review_status: 'menneskeark',
      reason: 'Kilden er ikke entydig.' };
    const { controller } = startReview({ storage: memoryStorage(), records });

    controller.setView('completed');

    expect(document.querySelector('[data-role="record-list"]')!.textContent).toContain('Navn rk-accepted');
    controller.selectRecord('rk-accepted');
    expect(document.querySelector('[data-role="decision-state"]')!.textContent).toContain('accepteret');
    expect(document.querySelector('[data-action="select-candidate"]')!.getAttribute('aria-pressed')).toBe('true');
  });

  it('merges a new outcome without discarding review metadata', () => {
    const storage = memoryStorage();
    const record = humanRecord('rk-1', 'candidate-1');
    record.decision = {
      baseline_record_key: 'rk-1', review_status: 'menneskeark',
      baseline_locator: { pages: '498', local_id: 'Stamme.Volrad' }, reason: 'Ikke entydigt anker.',
    };
    const { controller } = startReview({ storage, records: [record] });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'candidate-1' })).toBe(true);

    expect(JSON.parse(storage.getItem(controller.storageKey)!).decisions['rk-1']).toMatchObject({
      outcome: 'human_selected_candidate', review_status: 'menneskeark',
      baseline_locator: { pages: '498', local_id: 'Stamme.Volrad' },
      reason: 'Ikke entydigt anker.',
    });
    expect(controller.exportDraft().entries[0]).toMatchObject({
      outcome: 'human_selected_candidate', review_status: 'menneskeark',
      baseline_locator: { pages: '498', local_id: 'Stamme.Volrad' },
      reason: 'Ikke entydigt anker.',
    });
  });

  it('does not confirm or advance when persistence fails', () => {
    const storage = memoryStorage();
    storage.setItem = () => { throw new Error('quota'); };
    const { controller } = startReview({ storage, records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(false);
    expect(controller.selectedKey).toBe('rk-1');
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('Kunne ikke gemme');
    expect(controller.exportDraft().entries[0].draft).toBe(true);
  });

  it.each([
    ['a read exception', () => { throw new Error('security'); }],
    ['malformed JSON', () => '{not json'],
    ['an incompatible schema', (source: any) => JSON.stringify({ schema_version: 99, source, decisions: {} })],
    ['an invalid candidate decision', (source: any) => JSON.stringify({
      schema_version: 1, source, decisions: {
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'missing' },
      },
    })],
  ])('blocks recovery without overwriting storage after %s', (_label, saved: any) => {
    const records = [humanRecord('rk-1', 'c-1')];
    const storage = memoryStorage();
    const setItem = vi.fn();
    storage.getItem = () => typeof saved === 'function' ? saved(viewModel(records).source) : saved;
    storage.setItem = setItem;
    const { controller, download } = startReview({ storage, records });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(false);
    expect(controller.undo()).toBe(false);
    document.querySelector<HTMLButtonElement>('[data-action="export-draft"]')!.click();
    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true });
    expect(download).toHaveBeenCalledWith(expect.objectContaining({ recovery_blocked: true }));
    expect(setItem).not.toHaveBeenCalled();
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('kan ikke');
  });

  it('fails closed for a non-injective initial decision state', () => {
    const records = [humanRecord('rk-1', 'shared'), humanRecord('rk-2', 'shared')];
    records[0].decision = { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'shared' };
    records[1].decision = { baseline_record_key: 'rk-2', outcome: 'human_selected_candidate', candidate_id: 'shared' };
    const storage = memoryStorage();
    storage.setItem = vi.fn();
    const { controller } = startReview({ storage, records });

    expect(controller.choose('undecidable')).toBe(false);
    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true });
    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it('rejects a human candidate already owned by an auto-resolved classification', () => {
    const auto = automaticRecord('rk-auto', 'auto-candidate');
    auto.classification = { queue_class: 'auto_resolved', candidate: { candidate_id: 'shared' } };
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-human', 'shared'), auto,
    ] });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'shared' })).toBe(false);
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('allerede valgt');
  });

  it('overlays cache outcomes onto current model metadata', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    records[0].decision = { baseline_record_key: 'rk-1', review_status: 'unreviewed',
      baseline_locator: { pages: '498', local_id: 'Stamme.I.1' } };
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1, source: viewModel(records).source, decisions: {
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'c-1' },
      },
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft().entries[0]).toMatchObject({
      review_status: 'unreviewed', baseline_locator: { pages: '498', local_id: 'Stamme.I.1' },
      outcome: 'human_selected_candidate', candidate_id: 'c-1',
    });
  });

  it('rejects a cache whose metadata conflicts with the current model', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    records[0].decision = { baseline_record_key: 'rk-1', review_status: 'menneskeark',
      reason: 'Kildens aktuelle begrundelse.' };
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1, source: viewModel(records).source, decisions: {
        'rk-1': { baseline_record_key: 'rk-1', review_status: 'menneskeark',
          reason: 'Forældet cachebegrundelse.', outcome: 'undecidable' },
      },
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true });
  });

  it('blocks empty-string cache and full-source changes including extra metadata', () => {
    const records = [humanRecord('rk-1', 'c-1')];
    const storage = memoryStorage();
    const setItem = vi.fn();
    storage.getItem = () => '';
    storage.setItem = setItem;
    const { controller } = startReview({ storage, records, source: { import_run: 'run-1' } });
    expect(controller.choose('undecidable')).toBe(false);
    expect(setItem).not.toHaveBeenCalled();

    const sourceOne = viewModel(records, { import_run: 'run-1' }).source;
    const cached = JSON.stringify({ schema_version: 1, source: sourceOne, decisions: {} });
    storage.getItem = () => cached;
    const first = startReview({ storage, records, source: { import_run: 'run-1' } }).controller;
    const changed = startReview({ storage, records, source: { import_run: 'run-2' } }).controller;
    expect(first.storageKey).not.toBe(changed.storageKey);
    expect(changed.exportDraft()).toMatchObject({ recovery_blocked: true });
  });

  it('rejects incompatible payload fields for non-selection outcomes', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [humanRecord('rk-1', 'c-1')] });

    expect(controller.choose('no_candidate_fits', { candidate_id: 'c-1' })).toBe(false);
    expect(controller.exportDraft().entries[0]).toMatchObject({ draft: true });
  });

  it('keeps next and previous within the active view boundaries', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });

    expect(controller.previous()).toBe(false);
    expect(controller.next()).toBe(true);
    expect(controller.selectedKey).toBe('rk-2');
    expect(controller.next()).toBe(false);
    expect(controller.previous()).toBe(true);
    expect(controller.selectedKey).toBe('rk-1');
  });

  it('undoes the previous decision and persists the restored draft', () => {
    const storage = memoryStorage();
    const { controller } = startReview({ storage, records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });
    controller.choose('human_selected_candidate', { candidate_id: 'c-1' });

    expect(controller.undo()).toBe(true);

    expect(controller.selectedKey).toBe('rk-1');
    expect(controller.exportDraft().entries[0].draft).toBe(true);
    expect(JSON.parse(storage.getItem(controller.storageKey)!).decisions).toEqual({});
  });

  it('undo preserves the automatic queue and its selected record', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2'), automaticRecord('rk-3', 'c-3'),
    ] });
    controller.setView('automatic');
    controller.choose('human_selected_candidate', { candidate_id: 'c-2' });

    expect(controller.undo()).toBe(true);

    expect(controller.selectedKey).toBe('rk-2');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('Navn rk-1');
  });

  it('filters automatic and audit records and displays the audit label', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2', true),
    ] });

    controller.setView('automatic');
    expect(controller.selectedKey).toBe('rk-2');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).toContain('Navn rk-2');
    controller.setView('audit');
    expect(document.querySelector('[data-role="audit-label"]')!.textContent).toContain('Kontrolprøve');
  });

  it('shows the initially expanded candidates and expands the remainder on request', () => {
    const record = humanRecord('rk-1', 'c-1');
    record.candidates = ['c-1', 'c-2', 'c-3', 'c-4'].map(candidateId => ({
      candidate_id: candidateId, lokal_id: candidateId, pdf_pages: [498], calamari_pages: [3],
      raw_text: candidateId, rank_reason: 'samme_pdf_side',
    }));
    record.initial_candidate_ids = ['c-1', 'c-2', 'c-3'];
    startReview({ storage: memoryStorage(), records: [record] });

    expect(document.querySelectorAll('.candidate')).toHaveLength(3);
    document.querySelector<HTMLButtonElement>('[data-action="expand-candidates"]')!.click();
    expect(document.querySelectorAll('.candidate')).toHaveLength(4);
  });

  it('uses the selected duplicate target', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });
    const duplicateTarget = document.querySelector<HTMLSelectElement>('[data-role="duplicate-target"]')!;
    duplicateTarget.value = 'rk-2';

    document.querySelector<HTMLButtonElement>('[data-action="possible-duplicate"]')!.click();

    expect(controller.exportDraft().entries[0]).toMatchObject({
      outcome: 'possible_duplicate', duplicate_of_baseline_record_key: 'rk-2',
    });
  });

  it('rejects a candidate already selected for another record', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'shared'), humanRecord('rk-2', 'shared'),
    ] });
    expect(controller.choose('human_selected_candidate', { candidate_id: 'shared' })).toBe(true);

    expect(controller.choose('human_selected_candidate', { candidate_id: 'shared' })).toBe(false);
    expect(controller.selectedKey).toBe('rk-2');
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('allerede valgt');
  });

  it('keeps automatic review in its own view after a persisted choice', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2'), automaticRecord('rk-3', 'c-3'),
    ] });
    controller.setView('automatic');

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-2' })).toBe(true);

    expect(controller.selectedKey).toBe('rk-3');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('Navn rk-1');
  });

  it('filters duplicate targets by the plain-text search', () => {
    startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'), humanRecord('rk-3', 'c-3'),
    ] });
    const search = document.querySelector<HTMLInputElement>('[data-role="duplicate-search"]')!;
    search.value = 'rk-2';
    search.dispatchEvent(new Event('input', { bubbles: true }));

    expect(document.querySelector('[data-role="duplicate-target"]')!.textContent).toContain('Navn rk-2');
    expect(document.querySelector('[data-role="duplicate-target"]')!.textContent).not.toContain('Navn rk-3');
  });

  it('exports the complete draft through the supplied callback', () => {
    const download = vi.fn();
    startReview({ storage: memoryStorage(), records: [humanRecord('rk-1', 'c-1')], download });

    document.querySelector<HTMLButtonElement>('[data-action="export-draft"]')!.click();

    expect(download).toHaveBeenCalledWith(expect.objectContaining({
      baseline_sha256: 'a'.repeat(64), exported_at: '2026-08-05T12:00:00+02:00', entries: expect.any(Array),
    }));
  });

  it('returns deep-cloned drafts to export and download callers', () => {
    const download = vi.fn();
    const { controller } = startReview({ storage: memoryStorage(),
      records: [humanRecord('rk-1', 'c-1')], download });
    controller.choose('human_selected_candidate', { candidate_id: 'c-1' });
    const exported = controller.exportDraft();
    exported.source.edition = 'tampered';
    exported.entries[0].candidate_id = 'tampered';
    document.querySelector<HTMLButtonElement>('[data-action="export-draft"]')!.click();
    const downloaded = download.mock.calls[0][0];
    downloaded.entries[0].candidate_id = 'also-tampered';

    expect(controller.exportDraft().source.edition).toBe('1939');
    expect(controller.exportDraft().entries[0].candidate_id).toBe('c-1');
  });

  it('handles a hostile record key without interpolation through click, persistence and reload', () => {
    const storage = memoryStorage();
    const recordKey = 'Volrad "ældre" / Øst';
    const candidateId = 'kandidat "ældre" / æ';
    const records = [humanRecord(recordKey, candidateId)];
    const { controller } = startReview({ storage, records });

    document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();

    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('Visuelt spor er gemt lokalt');
    expect(JSON.parse(storage.getItem(controller.storageKey)!).decisions[recordKey]).toMatchObject({
      baseline_record_key: recordKey, candidate_id: candidateId,
    });
    startReview({ storage, records });
    expect(document.querySelector('[data-role="decision-state"]')!.textContent).toContain(candidateId);
    expect(document.querySelector('[data-action="select-candidate"]')!.getAttribute('aria-pressed')).toBe('true');
  });
});
