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

function viewModel(records: any[]) {
  return {
    schema_version: 1,
    source: {
      edition: '1939', baseline_sha256: 'a'.repeat(64), calamari_sha256: 'b'.repeat(64),
      raw_ocr_sha256: 'c'.repeat(64), pdf_sha256: 'd'.repeat(64), profile_version: '1939-v2',
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

function startReview({ storage, records, download = vi.fn() }: {
  storage: ReturnType<typeof memoryStorage>;
  records: any[];
  download?: ReturnType<typeof vi.fn>;
}) {
  document.body.innerHTML = '<aside data-role="save-state"></aside><main data-role="app"></main>';
  window.eval(uiSource);
  return {
    controller: (window as any).DAA1939Review.init({ data: viewModel(records), storage,
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

  it('supports candidate ids containing quotes and Danish characters', () => {
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

  it('reports a storage read failure without preventing review or export', () => {
    const storage = memoryStorage();
    storage.getItem = () => { throw new Error('security'); };
    const { controller } = startReview({ storage, records: [humanRecord('rk-1', 'c-1')] });

    expect(controller.selectedKey).toBe('rk-1');
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('kunne ikke læses');
    controller.choose('human_selected_candidate', { candidate_id: 'c-1' });
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('kunne ikke læses');
    expect(controller.exportDraft().entries).toHaveLength(1);
  });

  it('visibly rejects a locally cached draft with the wrong schema version', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const { controller } = startReview({ storage, records });
    storage.setItem(controller.storageKey, JSON.stringify({
      schema_version: 99, source: viewModel(records).source, decisions: {},
    }));

    startReview({ storage, records });

    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('kan ikke bruges');
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
});
