// @vitest-environment jsdom
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { afterEach, describe, expect, it, vi } from 'vitest';

const uiSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/human_review_1939_ui.js',
), 'utf8');
const sharedSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/review_ui_shared.js',
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

function acceptedDecision(recordKey: string, candidateId: string) {
  return {
    baseline_record_key: recordKey,
    review_status: 'accepteret',
    candidate_id: candidateId,
    post_index: 7,
    calamari_span: { char_from: 10, char_to: 20 },
    calamari_verbatim_text: 'Accepteret Calamari-tekst',
    pdf_pages: [700],
    kind: 'manual_cross_page_anchor',
    raw_char_from: 100,
    raw_char_to: 123,
    raw_verbatim_text: 'Accepteret manuel tekst',
    raw_excerpt_sha256: '408adad7923ea0cc08bb5979cbda1a5f727ab5957f69bdf243ddb8394e22c379',
  };
}

function viewModel(records: any[], source = {}, sourceBlocked: any = 0) {
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
      audit: records.filter(r => r.is_audit).length, completed: 0, source_blocked: sourceBlocked },
    views: {
      required: records.filter(r => r.queue_class !== 'auto_resolved').map(r => r.record_key),
      audit: records.filter(r => r.is_audit).map(r => r.record_key),
      completed: [],
    },
    records,
  };
}

function startReview({ storage, records, source, sourceBlocked, download = vi.fn() }: {
  storage: ReturnType<typeof memoryStorage>;
  records: any[];
  source?: Record<string, unknown>;
  sourceBlocked?: any;
  download?: ReturnType<typeof vi.fn>;
}) {
  document.body.innerHTML = '<aside data-mobile-open="false"><p data-role="save-state"></p><button type="button" data-action="toggle-sidebar" aria-expanded="false">Vælg person</button><div data-role="sidebar-navigation"></div></aside><main data-role="app"></main>';
  window.eval(sharedSource);
  window.eval(uiSource);
  return {
    controller: (window as any).DAA1939Review.init({
      data: viewModel(records, source, sourceBlocked), storage,
      now: () => '2026-08-05T12:00:00+02:00', download }),
    download,
  };
}

function sourceBoundSuccessorModel({
  calamari = '### PAGE 1 ###\n1. Volrad\n### PAGE 1 ###\n2. Emeke\n',
  rawOcr = '### PAGE 496 ###\n1. Volrad\nII.\n### PAGE 496 ###\n2. Emeke\n',
}: { calamari?: string; rawOcr?: string } = {}) {
  const script = [
    'import json',
    'from dual_rendition_evidence_1939 import build_source_bound_evidence',
    'from review_queue_1939 import classify_review_entries',
    'from prepare_review_queue_1939 import build_review_view_model',
    'source_baseline = json.dumps([',
    "  {'record_key':'rk-volrad','_v2_lokal_id':'I.1','_narrativ_kilde':'calamari','narrative':'Volrad'},",
    "  {'record_key':'rk-emeke','_v2_lokal_id':'I.2','_narrativ_kilde':'calamari','narrative':'Emeke'},",
    ']).encode()',
    `evidence, _, _ = build_source_bound_evidence(source_baseline, ${JSON.stringify(calamari)}.encode(), ${JSON.stringify(rawOcr)}.encode(), b'%PDF-synthetic', profile_version='1939-v2')`,
    "queue = classify_review_entries(evidence['source'], {'rk-volrad', 'rk-emeke'}, evidence['entries'])",
    "print(json.dumps(build_review_view_model([{'record_key':'rk-volrad','navn':'Volrad','sider':'498','narrative':'Volrad'}, {'record_key':'rk-emeke','navn':'Emeke','sider':'498','narrative':'Emeke'}], queue, {}, [], {})))",
  ].join('\n');
  const result = spawnSync('/usr/bin/python3', ['-c', script], {
    cwd: resolve(process.cwd(), '../.claude/skills/daa-extract/scripts'),
    encoding: 'utf8',
    env: { ...process.env, PYTHONPYCACHEPREFIX: join(tmpdir(), 'daa1939-ui-v2-pycache') },
  });
  expect(result.status, result.stderr).toBe(0);
  return JSON.parse(result.stdout);
}

function startModel(data: any, storage = memoryStorage()) {
  document.body.innerHTML = '<aside data-mobile-open="false"><p data-role="save-state"></p><button type="button" data-action="toggle-sidebar" aria-expanded="false">Vælg person</button><div data-role="sidebar-navigation"></div></aside><main data-role="app"></main>';
  window.eval(sharedSource);
  window.eval(uiSource);
  return (window as any).DAA1939Review.init({
    data, storage, now: () => '2026-08-05T12:00:00+02:00', download: vi.fn(),
  });
}

afterEach(() => {
  document.body.innerHTML = '';
});

describe('human 1939 review controller', () => {
  it('renders navigation in the sidebar and starts main with the selected person', () => {
    startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });

    const sidebar = document.querySelector('[data-role="sidebar-navigation"]')!;
    expect(sidebar.querySelector('[data-role="dashboard"]')).not.toBeNull();
    expect(sidebar.querySelector('[data-role="record-list"]')).not.toBeNull();
    expect(document.querySelector('main > h1')!.textContent).toBe('Navn rk-1');
    expect(document.querySelector('main [data-role="record-list"]')).toBeNull();
  });

  it('shows which names still need processing and updates the missing count', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
    ] });

    const statusFor = (key: string) => document.querySelector(
      `[data-action="select-record"][data-record-key="${key}"] [data-role="record-status"]`,
    )!.textContent;
    expect(document.querySelector('[data-role="missing-count"]')!.textContent)
      .toBe('2 mangler af 2');
    expect(statusFor('rk-1')).toBe('Mangler');
    expect(statusFor('rk-2')).toBe('Mangler');

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(true);

    expect(document.querySelector('[data-role="missing-count"]')!.textContent)
      .toBe('1 mangler af 2');
    expect(statusFor('rk-1')).toBe('Kladde gemt');
    expect(statusFor('rk-2')).toBe('Mangler');
  });

  it('searches names only within the active view and navigation follows the result', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
      automaticRecord('rk-audit', 'c-audit', true),
    ] });
    const search = document.querySelector<HTMLInputElement>('[data-role="record-search"]')!;
    search.value = 'rk-2';
    search.dispatchEvent(new Event('input', { bubbles: true }));

    const list = document.querySelector('[data-role="record-list"]')!;
    expect(list.textContent).toContain('Navn rk-2');
    expect(list.textContent).not.toContain('Navn rk-1');
    expect(list.textContent).not.toContain('Navn rk-audit');
    expect(controller.selectedKey).toBe('rk-2');
    expect(controller.previous()).toBe(false);
    expect(controller.next()).toBe(false);
  });

  it('closes the compact person picker after selecting a name', () => {
    const originalMatchMedia = window.matchMedia;
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        matches: query === '(max-width: 720px)', media: query,
        addEventListener: vi.fn(), removeEventListener: vi.fn(),
      })),
    });
    try {
      startReview({ storage: memoryStorage(), records: [
        humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
      ] });
      const aside = document.querySelector('aside')!;
      const toggle = document.querySelector<HTMLButtonElement>('[data-action="toggle-sidebar"]')!;
      toggle.click();
      expect(aside.getAttribute('data-mobile-open')).toBe('true');

      document.querySelector<HTMLButtonElement>(
        '[data-action="select-record"][data-record-key="rk-2"]',
      )!.click();

      expect(aside.getAttribute('data-mobile-open')).toBe('false');
      expect(toggle.getAttribute('aria-expanded')).toBe('false');
    } finally {
      Object.defineProperty(window, 'matchMedia', {
        configurable: true, value: originalMatchMedia,
      });
    }
  });

  it('keeps the desktop sidebar navigation mounted after switching to audit samples', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-audit', 'c-audit', true),
    ] });
    const navigation = document.querySelector('[data-role="sidebar-navigation"]')!;

    expect(navigation.isConnected).toBe(true);
    controller.setView('audit');

    expect(navigation.isConnected).toBe(true);
    expect(document.querySelector('[data-role="record-list"]')!.textContent)
      .toContain('Navn rk-audit');
  });

  it('opens and closes the separate mobile person menu without native details', () => {
    const originalMatchMedia = window.matchMedia;
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        matches: query === '(max-width: 720px)', media: query,
        addEventListener: vi.fn(), removeEventListener: vi.fn(),
      })),
    });
    try {
      document.body.innerHTML = '<aside data-mobile-open="false"><p data-role="save-state"></p><button type="button" data-action="toggle-sidebar" aria-expanded="false">Vælg person</button><div data-role="sidebar-navigation"></div></aside><main data-role="app"></main>';
      window.eval(sharedSource);
      window.eval(uiSource);
      (window as any).DAA1939Review.init({
        data: viewModel([humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2')]),
        storage: memoryStorage(), now: () => '2026-08-05T12:00:00+02:00', download: vi.fn(),
      });
      const aside = document.querySelector('aside')!;
      const toggle = document.querySelector<HTMLButtonElement>('[data-action="toggle-sidebar"]')!;

      toggle.click();
      expect(aside.getAttribute('data-mobile-open')).toBe('true');
      expect(toggle.getAttribute('aria-expanded')).toBe('true');

      document.querySelector<HTMLButtonElement>(
        '[data-action="select-record"][data-record-key="rk-2"]',
      )!.click();
      expect(aside.getAttribute('data-mobile-open')).toBe('false');
      expect(toggle.getAttribute('aria-expanded')).toBe('false');
    } finally {
      Object.defineProperty(window, 'matchMedia', {
        configurable: true, value: originalMatchMedia,
      });
    }
  });

  it('asks a readable question and shows both OCR renditions before technical ids', () => {
    const record = automaticRecord('rk-otto', 'opaque-candidate-id', true);
    Object.assign(record.candidates[0], {
      calamari_verbatim_text: '3. Greve Otto Carl Ferdinand Christian Gottlieb',
      raw_verbatim_text: '3. Greve O t t o Carl Ferdinand Christian Gottlieb',
      details: { candidate_id: 'opaque-candidate-id', raw_excerpt_sha256: 'a'.repeat(64) },
    });
    startReview({ storage: memoryStorage(), records: [record] }).controller.setView('audit');

    expect(document.querySelector('[data-role="review-question"]')!.textContent)
      .toContain('Er denne kildepost den nævnte person: Navn rk-otto?');
    expect(document.querySelector('[data-role="calamari-source"]')!.textContent)
      .toContain('Otto Carl Ferdinand Christian Gottlieb');
    expect(document.querySelector('[data-role="raw-source"]')!.textContent)
      .toContain('O t t o Carl Ferdinand Christian Gottlieb');
    const summary = document.querySelector('.candidate > summary')!;
    expect(summary.textContent).toBe('Mulig kildepost · PDF s. 498');
    expect(summary.textContent).not.toContain('opaque-candidate-id');
    expect(document.querySelector('[data-role="candidate-details"]')!.textContent)
      .toContain('opaque-candidate-id');
  });

  it('labels an exact text fallback without calling it a parser boundary', () => {
    const record = humanRecord('rk-markvard', 'presentation:1939-v2:text-anchor:abc');
    Object.assign(record.candidates[0], {
      pdf_pages: [580],
      calamari_pages: [85],
      raw_text: 'Markvard sælger 1423 en Rente af 100 Mark Lybsk.',
      rank_reason: 'entydigt_tekstanker_uden_forventet_side',
    });

    startReview({ storage: memoryStorage(), records: [record] });

    expect(document.querySelector('.candidate')!.textContent)
      .toContain('Teksten er fundet entydigt i Calamari-OCR uden for det gamle sidetal.');
    expect(document.querySelector('.candidate')!.textContent)
      .toContain('Calamari-OCR – entydigt tekstfund');
    expect(document.querySelector('.candidate')!.textContent)
      .not.toContain('parserens foreslåede postgrænse');
  });

  it('explains an exact text fallback on the expected page as a parser gap', () => {
    const record = humanRecord('rk-markvard', 'presentation:1939-v2:text-anchor:def');
    Object.assign(record.candidates[0], {
      pdf_pages: [580],
      calamari_pages: [85],
      raw_text: 'Markvard sælger 1423 en Rente af 100 Mark Lybsk.',
      rank_reason: 'entydigt_tekstanker_uden_parserkandidat',
    });

    startReview({ storage: memoryStorage(), records: [record] });

    expect(document.querySelector('.candidate')!.textContent)
      .toContain('Teksten er fundet entydigt i Calamari-OCR, men parseren har ikke afgrænset en post.');
    expect(document.querySelector('.candidate')!.textContent)
      .not.toContain('parserens foreslåede postgrænse');
  });

  it('keeps the selected opaque candidate id out of the ordinary decision status', () => {
    const record = automaticRecord('rk-audit', '1939:dual-v1:opaque', true);
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });
    controller.setView('audit');

    expect(controller.choose('human_selected_candidate', {
      candidate_id: '1939:dual-v1:opaque',
    })).toBe(true);

    const status = document.querySelector('[data-role="decision-state"]')!.textContent!;
    expect(status).toContain('Kildepost valgt');
    expect(status).not.toContain('1939:dual-v1:opaque');
  });

  it('renders the actual source-bound Volrad successor mismatch with Emeke once', () => {
    const controller = startModel(sourceBoundSuccessorModel());

    expect(controller.selectedKey).toBe('rk-volrad');
    const boundaryContext = document.querySelector('[data-role="boundary-context"]')!.textContent!;
    expect(boundaryContext).toContain('Calamari og rå OCR: følgende post');
    expect(boundaryContext.match(/Emeke/g)).toHaveLength(1);
  });

  it('renders different successor excerpts under their own source labels', () => {
    startModel(sourceBoundSuccessorModel({
      rawOcr: '### PAGE 496 ###\n1. Volrad\n### PAGE 496 ###\n3. Emeke\n',
    }));

    const boundaryContext = document.querySelector('[data-role="boundary-context"]')!.textContent!;
    expect(boundaryContext).toContain('Calamari: følgende post');
    expect(boundaryContext).toContain('rå OCR: følgende post');
    expect(boundaryContext.match(/Emeke/g)).toHaveLength(2);
  });

  it('renders the raw OCR neighbor when Calamari lacks the successor', () => {
    const controller = startModel(sourceBoundSuccessorModel({
      calamari: '### PAGE 1 ###\n1. Volrad\n',
      rawOcr: '### PAGE 496 ###\n1. Volrad\n### PAGE 496 ###\n2. Emeke\n',
    }));

    expect(controller.selectedKey).toBe('rk-volrad');
    const boundaryContext = document.querySelector('[data-role="boundary-context"]')!.textContent!;
    expect(boundaryContext).toContain('Calamari: følgende post mangler');
    expect(boundaryContext.match(/Emeke/g)).toHaveLength(1);
  });

  it('renders the Calamari neighbor when raw OCR lacks the successor', () => {
    startModel(sourceBoundSuccessorModel({
      rawOcr: '### PAGE 496 ###\n1. Volrad\n',
    }));

    const boundaryContext = document.querySelector('[data-role="boundary-context"]')!.textContent!;
    expect(boundaryContext).toContain('Calamari: følgende post');
    expect(boundaryContext).toContain('rå OCR: følgende post mangler');
    expect(boundaryContext.match(/Emeke/g)).toHaveLength(1);
  });

  it('starts on exceptions and exposes automatic records only as samples', () => {
    startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-human', 'candidate-human'),
      automaticRecord('rk-audit', 'candidate-audit', true),
      automaticRecord('rk-hidden', 'candidate-hidden'),
    ] });

    expect(document.body.textContent).toContain('rk-human');
    expect(document.body.textContent).not.toContain('rk-audit');
    expect(document.body.textContent).not.toContain('rk-hidden');
    document.querySelector<HTMLButtonElement>('[data-view="audit"]')!.click();
    expect(document.body.textContent).toContain('rk-audit');
    expect(document.body.textContent).not.toContain('rk-hidden');
  });

  it('preserves save, reload, undo and export behavior in V2', () => {
    const storage = memoryStorage();
    const first = startReview({ storage, records: [humanRecord('rk-1', 'candidate-1')] });
    document.querySelector<HTMLButtonElement>('[data-action="select-candidate"]')!.click();
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('gemt lokalt');
    expect(first.controller.undo()).toBe(true);
    expect(first.controller.choose('human_selected_candidate', { candidate_id: 'candidate-1' })).toBe(true);
    document.body.innerHTML = '';
    const second = startReview({ storage, records: [humanRecord('rk-1', 'candidate-1')] });
    expect(document.body.textContent).toContain(
      'Nuværende valg: Kildepost valgt (gemt som observation til efterforankring).',
    );
    expect(first.controller.exportDraft().schema_version).toBe(1);
    second.controller.exportDraft();
  });

  it('renders hostile diagnostics as text and falls back for an unknown reason code', () => {
    const record = humanRecord('rk-[<Volrad>]', 'candidate-1');
    record.reason_code = 'fremtidig_ukendt_kode';
    record.reason_da = 'Før </ScRiPt><img data-injected="reason"> efter';
    startReview({ storage: memoryStorage(), records: [record] });

    expect(document.body.textContent).toContain(record.reason_da);
    expect(document.querySelector('[data-injected="reason"]')).toBeNull();
    expect(document.querySelector('[data-role="boundary-context"]')!.textContent)
      .toBe('Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering.');
  });

  it('keeps an empty audit stratum separate from a source-blocked-only queue', () => {
    const record = humanRecord('rk-blocked', 'candidate-1');
    record.queue_class = 'source_blocked';
    record.reason_code = 'missing_in_raw_ocr';
    record.reason_da = 'Rå OCR mangler for denne post.';
    record.boundary_context = 'Calamari: postgrænse fundet · rå OCR: ingen sikker postgrænse.';
    const { controller } = startReview({ storage: memoryStorage(), records: [record], sourceBlocked: 1 });

    expect(document.body.textContent).toContain('rk-blocked');
    expect(document.body.textContent).toContain(record.boundary_context);
    expect(document.querySelector('[data-view="audit"]')!.textContent).toContain('(0)');
    document.querySelector<HTMLButtonElement>('[data-view="audit"]')!.click();
    expect(document.body.textContent).toContain('Der er ingen poster i denne visning.');
    expect(controller.selectedKey).toBeUndefined();
  });

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
    expect(controller.choose('no_candidate_fits', { reason: 'Ingen af dem matcher kilden.' })).toBe(true);
    expect(controller.choose('possible_duplicate', { duplicate_of_baseline_record_key: 'rk-1' })).toBe(true);
    expect(controller.choose('undecidable', { reason: 'Kilden er tvetydig.' })).toBe(true);

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
      .toContain('Kildepost valgt');
    expect(document.querySelector('[data-action="select-candidate"]')!.getAttribute('aria-pressed'))
      .toBe('true');
  });

  it('sætter en enkelt ugyldig kladdepost i karantæne uden at miste de øvrige', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'shared'), humanRecord('rk-2', 'shared')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: {
        'rk-2': { baseline_record_key: 'rk-2', outcome: 'human_selected_candidate',
          candidate_id: 'shared', decided_at: '2026-08-05T12:01:00+02:00' },
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
          candidate_id: 'shared', decided_at: '2026-08-05T12:00:00+02:00' },
      },
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
    expect(controller.exportDraft().entries).toEqual([
      { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
        candidate_id: 'shared', decided_at: '2026-08-05T12:00:00+02:00' },
      { baseline_record_key: 'rk-2', draft: true },
    ]);
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('Kandidaten er allerede valgt for en anden historisk post');
  });

  it('round-tripper karantænen gennem persist og genindlæsning', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2')];
    const invalid = { baseline_record_key: 'rk-2', outcome: 'no_candidate_fits',
      reason: 17, decided_at: '2026-08-05T12:01:00+02:00' };
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: { 'rk-2': invalid },
    }));

    const first = startReview({ storage, records });
    expect(first.controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(true);
    expect(JSON.parse(storage.getItem(first.controller.storageKey)!).quarantined).toEqual({
      'rk-2': { entry: invalid, reason: 'Skriv en begrundelse for dette udfald' },
    });

    startReview({ storage, records });

    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('Skriv en begrundelse for dette udfald');
    expect(document.querySelector('[data-action="export-quarantine"]')).not.toBeNull();
  });

  it('removes only the selected records quarantine entry after a valid save', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: {},
      quarantined: {
        'rk-1': { entry: { stale: 'one' }, reason: 'Forældet valg.' },
        'rk-2': { entry: { stale: 'two' }, reason: 'Andet forældet valg.' },
      },
    }));
    const { controller } = startReview({ storage, records });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(true);

    expect(JSON.parse(storage.getItem(controller.storageKey)!).quarantined).toEqual({
      'rk-2': { entry: { stale: 'two' }, reason: 'Andet forældet valg.' },
    });
  });

  it('restores the decision and quarantine atomically when persistence fails', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: {},
      quarantined: {
        'rk-1': { entry: { stale: true }, reason: 'Forældet valg.' },
      },
    }));
    storage.setItem = () => { throw new Error('quota'); };
    const { controller } = startReview({ storage, records });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(false);

    expect(controller.exportDraft().entries[0]).toMatchObject({ draft: true });
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('Forældet valg.');
  });

  it('holder hoved-eksporten skemaren og eksporterer karantænen separat', async () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const invalid = { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
      candidate_id: 'missing', decided_at: '2026-08-05T12:00:00+02:00' };
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: { 'rk-1': invalid },
    }));
    const download = vi.fn();
    const createObjectURL = vi.fn(() => 'blob:quarantine');
    Object.defineProperty(URL, 'createObjectURL', { configurable: true, value: createObjectURL });
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    const { controller } = startReview({ storage, records, download });

    document.querySelector<HTMLButtonElement>('[data-action="export-draft"]')!.click();

    expect(Object.keys(download.mock.calls[0][0]).sort()).toEqual([
      'baseline_sha256', 'entries', 'exported_at', 'schema_version', 'source',
    ]);
    expect(controller.exportDraft()).not.toHaveProperty('quarantined');
    const quarantineButton = document.querySelector<HTMLButtonElement>(
      '[data-action="export-quarantine"]',
    );
    expect(quarantineButton).not.toBeNull();
    quarantineButton!.click();
    expect(click).toHaveBeenCalledOnce();
    expect((click.mock.instances[0] as HTMLAnchorElement).download)
      .toBe('1939-review-karantaene.json');
    const blob = createObjectURL.mock.calls[0][0];
    const exported = await new Promise<any>((resolveExport, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolveExport(JSON.parse(String(reader.result)));
      reader.onerror = () => reject(reader.error);
      reader.readAsText(blob);
    });
    expect(exported.quarantined).toEqual({
      'rk-1': { entry: invalid, reason: 'Ugyldigt kandidatvalg' },
    });
  });

  it('mærker læsehjælps-kandidater og forankrede kandidater forskelligt', () => {
    const record = humanRecord('rk-1', 'anchored');
    record.candidates[0].details = { candidate_id: 'anchored', kind: 'line_header' };
    record.candidates.push({
      candidate_id: 'reading-aid', lokal_id: 'reading-aid', pdf_pages: [498], calamari_pages: [3],
      raw_text: 'Ny OCR reading-aid', rank_reason: 'samme_pdf_side',
    });
    record.initial_candidate_ids = ['anchored', 'reading-aid'];
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });
    const candidates = document.querySelectorAll<HTMLElement>('.candidate');

    expect(candidates[0].textContent)
      .toContain('Forankret kildeevidens — kan accepteres direkte.');
    expect(candidates[1].textContent).toContain(
      'Læsehjælp — dit valg gemmes som redaktionel observation og efterforankres maskinelt.',
    );
    expect(controller.choose('human_selected_candidate', { candidate_id: 'reading-aid' })).toBe(true);
    expect(document.querySelector('[data-role="decision-state"]')!.textContent).toBe(
      'Nuværende valg: Kildepost valgt (gemt som observation til efterforankring).',
    );
  });

  it('treats accepted-review-only evidence as anchored in its label and status', () => {
    const record = humanRecord('rk-1', 'accepted-only');
    record.candidates[0].accepted_review_details = {
      baseline_record_key: 'rk-1', review_status: 'accepteret', candidate_id: 'accepted-only',
    };
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    expect(document.querySelector('.candidate')!.textContent)
      .toContain('Forankret kildeevidens — kan accepteres direkte.');
    expect(controller.choose(
      'human_selected_candidate', { candidate_id: 'accepted-only' },
    )).toBe(true);
    expect(document.querySelector('[data-role="decision-state"]')!.textContent)
      .toBe('Nuværende valg: Kildepost valgt.');
  });

  it('blocks an ambiguous current cache with entries and malformed decisions without overwrite', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const probe = startReview({ storage, records });
    const payload = JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      entries: [],
      decisions: {
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
          candidate_id: 'missing', decided_at: '2026-08-05T12:00:00+02:00' },
      },
    });
    storage.setItem(probe.controller.storageKey, payload);
    const originalSetItem = storage.setItem;
    storage.setItem = vi.fn(originalSetItem);

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true, entries: [] });
    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(false);
    expect(storage.setItem).not.toHaveBeenCalled();
    expect(storage.getItem(controller.storageKey)).toBe(payload);
  });

  it.each([
    ['a legacy entries container', { entries: [] }],
    ['no authoritative decisions container', {}],
  ])('blocks current-schema cache with %s', (_label, container) => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1, source: viewModel(records).source, ...container,
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true, entries: [] });
  });

  it('quarantines the later of two non-injective cached decisions deterministically', () => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'shared'), humanRecord('rk-2', 'shared')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: {
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
          candidate_id: 'shared', decided_at: '2026-08-05T12:00:00+02:00' },
        'rk-2': { baseline_record_key: 'rk-2', outcome: 'human_selected_candidate',
          candidate_id: 'shared', decided_at: '2026-08-05T12:01:00+02:00' },
      },
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
    expect(controller.exportDraft().entries).toEqual([
      { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
        candidate_id: 'shared', decided_at: '2026-08-05T12:00:00+02:00' },
      { baseline_record_key: 'rk-2', draft: true },
    ]);
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
  });

  it('preserves completed decisions supplied by the view model', () => {
    const record = humanRecord('rk-1', 'candidate-1');
    record.decision = {
      baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'candidate-1',
      decided_at: '2026-08-05T11:00:00+02:00',
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
    expect(document.querySelector('[data-action="select-candidate"]')).toBeNull();
    expect(document.querySelector('[data-role="decision-controls"]')).toBeNull();
  });

  it('merges a new outcome without discarding review metadata', () => {
    const storage = memoryStorage();
    const record = humanRecord('rk-1', 'candidate-1');
    record.decision = {
      baseline_record_key: 'rk-1', review_status: 'unreviewed',
      baseline_locator: { pages: '498', local_id: 'Stamme.Volrad' },
    };
    const { controller } = startReview({ storage, records: [record] });

    expect(controller.choose('human_selected_candidate', { candidate_id: 'candidate-1' })).toBe(true);

    const persisted = JSON.parse(storage.getItem(controller.storageKey)!).decisions['rk-1'];
    expect(persisted).toMatchObject({ outcome: 'human_selected_candidate', candidate_id: 'candidate-1' });
    expect(persisted).not.toHaveProperty('review_status');
    expect(persisted).not.toHaveProperty('baseline_locator');
    expect(controller.exportDraft().entries[0]).toMatchObject({
      outcome: 'human_selected_candidate', review_status: 'unreviewed',
      baseline_locator: { pages: '498', local_id: 'Stamme.Volrad' },
    });
  });

  it.each(['accepteret', 'eksplicit_dublet', 'menneskeark'])(
    'keeps final legacy status %s read-only for browser choices and cache outcomes', status => {
      const records = [humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2')];
      const decision: any = { baseline_record_key: 'rk-1', review_status: status };
      if (status === 'accepteret') Object.assign(decision, {
        candidate_id: 'c-1', post_index: 0, calamari_span: { char_from: 0, char_to: 1 },
        calamari_verbatim_text: 'A', pdf_pages: [498], kind: 'line_header', raw_char_from: 0,
        raw_char_to: 1, raw_verbatim_text: 'A',
        raw_excerpt_sha256: '559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd',
      });
      if (status === 'eksplicit_dublet') decision.duplicate_of_baseline_record_key = 'rk-2';
      if (status === 'menneskeark') decision.reason = 'Historisk afgørelse.';
      records[0].decision = decision;
      const storage = memoryStorage();
      const initial = startReview({ storage, records });
      storage.setItem(initial.controller.storageKey, JSON.stringify({
        schema_version: 1, source: viewModel(records).source, decisions: {
          'rk-1': { baseline_record_key: 'rk-1', outcome: 'undecidable' },
        },
      }));

      const { controller } = startReview({ storage, records });

      expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
      expect(controller.exportDraft().entries[0]).toMatchObject(decision);
      expect(document.querySelector('[data-role="save-state"]')!.textContent)
        .toContain('1 kladdepost i karantæne');
      expect(controller.choose('undecidable')).toBe(false);
    },
  );

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
    ['an invalid quarantine container', (source: any) => JSON.stringify({
      schema_version: 1, source, decisions: {}, quarantined: [],
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

  it.each([
    ['reason without outcome', { baseline_record_key: 'rk-1', reason: 'løst fragment' }],
    ['draft without outcome', { baseline_record_key: 'rk-1', draft: true }],
    ['timestamp without outcome', {
      baseline_record_key: 'rk-1', decided_at: '2026-08-05T12:00:00+02:00',
    }],
    ['selection with an extraneous reason', {
      baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'c-1',
      reason: 'må ikke være her', decided_at: '2026-08-05T12:00:00+02:00',
    }],
    ['reason outcome with a non-string reason', {
      baseline_record_key: 'rk-1', outcome: 'no_candidate_fits', reason: 17,
      decided_at: '2026-08-05T12:00:00+02:00',
    }],
    ['undecidable without a reason', {
      baseline_record_key: 'rk-1', outcome: 'undecidable',
      decided_at: '2026-08-05T12:00:00+02:00',
    }],
    ['selection with a non-string timestamp', {
      baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'c-1',
      decided_at: 17,
    }],
  ])('quarantines a malformed provisional entry: %s', (_label, cached) => {
    const storage = memoryStorage();
    const records = [humanRecord('rk-1', 'c-1')];
    const probe = startReview({ storage, records });
    storage.setItem(probe.controller.storageKey, JSON.stringify({
      schema_version: 1,
      source: viewModel(records).source,
      decisions: { 'rk-1': cached },
    }));

    const { controller } = startReview({ storage, records });

    expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
    expect(controller.exportDraft().entries).toEqual([
      { baseline_record_key: 'rk-1', draft: true },
    ]);
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
  });

  it('does not count metadata without a provisional outcome or final legacy status as completed', () => {
    const record = humanRecord('rk-1', 'c-1');
    record.decision = { baseline_record_key: 'rk-1' };
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('completed');

    expect(controller.selectedKey).toBeUndefined();
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('Navn rk-1');
  });

  it('fails closed instead of completing an unknown legacy status', () => {
    const record = humanRecord('rk-1', 'c-1');
    record.decision = { baseline_record_key: 'rk-1', review_status: 'ukendt' };

    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true, entries: [] });
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('kan ikke bruges');
  });

  it('fails closed for a non-injective initial decision state', () => {
    const records = [humanRecord('rk-1', 'shared'), humanRecord('rk-2', 'shared')];
    records[0].decision = { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate',
      candidate_id: 'shared', decided_at: '2026-08-05T11:00:00+02:00' };
    records[1].decision = { baseline_record_key: 'rk-2', outcome: 'human_selected_candidate',
      candidate_id: 'shared', decided_at: '2026-08-05T11:01:00+02:00' };
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
        'rk-1': { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'c-1',
          decided_at: '2026-08-05T12:00:00+02:00' },
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

    expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
    expect(controller.exportDraft().entries[0]).toMatchObject(records[0].decision);
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('1 kladdepost i karantæne');
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

  it('handles prototype-like record keys and source own properties without collisions', () => {
    const storage = memoryStorage();
    const records = [humanRecord('__proto__', 'c-proto'), humanRecord('toString', 'c-string')];
    const sourceOne = Object.create(null);
    Object.defineProperty(sourceOne, '__proto__', { value: 'one', enumerable: true });
    const sourceTwo = Object.create(null);
    Object.defineProperty(sourceTwo, '__proto__', { value: 'two', enumerable: true });
    const first = startReview({ storage, records, source: sourceOne });
    expect(first.controller.choose('human_selected_candidate', { candidate_id: 'c-proto' })).toBe(true);
    const persisted = JSON.parse(storage.getItem(first.controller.storageKey)!);

    expect(persisted.decisions['__proto__']).toMatchObject({ candidate_id: 'c-proto' });
    expect(first.controller.exportDraft().entries.find(
      (entry: any) => entry.baseline_record_key === '__proto__',
    )).toMatchObject({ candidate_id: 'c-proto' });
    first.controller.selectRecord('toString');
    expect(first.controller.choose('human_selected_candidate', { candidate_id: 'c-string' })).toBe(true);
    const second = startReview({ storage, records, source: sourceTwo });
    expect(first.controller.storageKey).not.toBe(second.controller.storageKey);
  });

  it('rejects incompatible payload fields for non-selection outcomes', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [humanRecord('rk-1', 'c-1')] });

    expect(controller.choose('no_candidate_fits', { candidate_id: 'c-1' })).toBe(false);
    expect(controller.exportDraft().entries[0]).toMatchObject({ draft: true });
  });

  it.each(['no_candidate_fits', 'undecidable'])(
    'requires a visible non-empty reason for %s and exports it without final acceptance', outcome => {
      const storage = memoryStorage();
      const records = [humanRecord('rk-1', 'c-1')];
      const { controller } = startReview({ storage, records });
      let reason = document.querySelector<HTMLTextAreaElement>('[data-role="decision-reason"]')!;
      expect(reason).not.toBeNull();

      expect(controller.choose(outcome, { reason: '   ' })).toBe(false);
      expect(controller.exportDraft().entries[0]).toEqual({
        baseline_record_key: 'rk-1', draft: true,
      });

      reason = document.querySelector<HTMLTextAreaElement>('[data-role="decision-reason"]')!;
      reason.value = outcome === 'no_candidate_fits'
        ? 'Ingen af sidekandidaterne matcher den historiske post.'
        : 'Kildeteksten er for tvetydig til en sikker afgørelse.';
      document.querySelector<HTMLButtonElement>(
        `[data-action="${outcome === 'no_candidate_fits' ? 'no-candidate-fits' : 'undecidable'}"]`,
      )!.click();

      expect(controller.exportDraft().entries[0]).toMatchObject({
        baseline_record_key: 'rk-1', outcome, reason: reason.value,
        decided_at: '2026-08-05T12:00:00+02:00',
      });
      expect(controller.exportDraft().entries[0]).not.toHaveProperty('review_status');
      expect(document.querySelector<HTMLTextAreaElement>('[data-role="decision-reason"]')!.value)
        .toBe(reason.value);
      startReview({ storage, records });
      expect(document.querySelector<HTMLTextAreaElement>('[data-role="decision-reason"]')!.value)
        .toBe(reason.value);
    },
  );

  it('exports the four provisional outcome shapes expected by the downstream validator', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'),
      humanRecord('rk-3', 'c-3'), humanRecord('rk-4', 'c-4'),
    ] });
    controller.choose('human_selected_candidate', { candidate_id: 'c-1' });
    controller.choose('no_candidate_fits', { reason: 'Ingen kandidat passer.' });
    controller.choose('possible_duplicate', { duplicate_of_baseline_record_key: 'rk-1' });
    controller.choose('undecidable', { reason: 'Tvetydig kilde.' });

    expect(controller.exportDraft().entries).toEqual([
      { baseline_record_key: 'rk-1', outcome: 'human_selected_candidate', candidate_id: 'c-1',
        decided_at: '2026-08-05T12:00:00+02:00' },
      { baseline_record_key: 'rk-2', outcome: 'no_candidate_fits', reason: 'Ingen kandidat passer.',
        decided_at: '2026-08-05T12:00:00+02:00' },
      { baseline_record_key: 'rk-3', outcome: 'possible_duplicate',
        duplicate_of_baseline_record_key: 'rk-1', decided_at: '2026-08-05T12:00:00+02:00' },
      { baseline_record_key: 'rk-4', outcome: 'undecidable', reason: 'Tvetydig kilde.',
        decided_at: '2026-08-05T12:00:00+02:00' },
    ]);
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

  it('undo preserves the audit queue and its selected record', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2', true),
      automaticRecord('rk-3', 'c-3', true),
    ] });
    controller.setView('audit');
    controller.choose('human_selected_candidate', { candidate_id: 'c-2' });

    expect(controller.undo()).toBe(true);

    expect(controller.selectedKey).toBe('rk-2');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('Navn rk-1');
  });

  it('filters deterministic audit records and displays the audit label', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2', true),
    ] });

    controller.setView('audit');
    expect(controller.selectedKey).toBe('rk-2');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).toContain('Navn rk-2');
    expect(document.querySelector('[data-role="audit-label"]')!.textContent).toContain('Kontrolprøve');
  });

  it('keeps non-audit auto-resolved records out of the browser views', () => {
    const records = [automaticRecord('rk-auto', 'c-auto'), automaticRecord('rk-auto-2', 'c-auto-2')];
    const { controller } = startReview({ storage: memoryStorage(), records });

    expect(controller.setView('automatic')).toBe(false);
    expect(controller.selectedKey).toBeUndefined();
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('rk-auto');
  });

  it('fails closed for a provisional choice embedded on a non-audit auto record', () => {
    const record = automaticRecord('rk-auto', 'c-auto');
    record.decision = {
      baseline_record_key: 'rk-auto', outcome: 'human_selected_candidate',
      candidate_id: 'c-auto', decided_at: '2026-08-05T12:00:00+02:00',
    };
    const storage = memoryStorage();
    storage.setItem = vi.fn();
    const { controller } = startReview({ storage, records: [record] });

    expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true, entries: [] });
    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it('keeps audit auto-resolved records actionable', () => {
    const record = automaticRecord('rk-audit', 'c-audit', true);
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('audit');

    expect(document.querySelector('[data-role="decision-controls"]')).not.toBeNull();
    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-audit' })).toBe(true);
  });

  it('renders authoritative accepted cross-page evidence in a collapsed technical disclosure', () => {
    const record = humanRecord('rk-accepted', 'near-page');
    const accepted = acceptedDecision('rk-accepted', 'manual-anchor');
    record.decision = accepted;
    record.candidates.push({
      candidate_id: 'manual-anchor', lokal_id: 'manual-anchor', pdf_pages: [700], calamari_pages: [],
      raw_text: accepted.raw_verbatim_text, rank_reason: 'accepteret_review_evidens',
      accepted_review_details: accepted,
    });
    record.initial_candidate_ids = ['near-page', 'manual-anchor'];
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('completed');

    expect(controller.exportDraft()).not.toHaveProperty('recovery_blocked');
    expect(document.querySelector('[data-role="decision-state"]')!.textContent).toContain('accepteret');
    const details = Array.from(document.querySelectorAll<HTMLDetailsElement>(
      '[data-role="candidate-details"]',
    )).find(node => node.textContent?.includes('manual_cross_page_anchor'))!;
    expect(details).not.toBeUndefined();
    expect(details.open).toBe(false);
    expect(details.textContent).toContain('Accepteret manuel tekst');
  });

  it('initially shows an accepted cross-page candidate after three earlier list candidates', () => {
    const record = humanRecord('rk-accepted', 'near-0');
    const accepted = acceptedDecision('rk-accepted', 'z-manual-anchor');
    record.decision = accepted;
    record.candidates = ['near-0', 'near-1', 'near-2'].map(candidateId => ({
      candidate_id: candidateId, lokal_id: candidateId, pdf_pages: [498], calamari_pages: [3],
      raw_text: candidateId, rank_reason: 'samme_pdf_side',
    }));
    record.candidates.push({
      candidate_id: 'z-manual-anchor', lokal_id: 'z-manual-anchor', pdf_pages: [700],
      calamari_pages: [], raw_text: accepted.raw_verbatim_text,
      rank_reason: 'accepteret_review_evidens', accepted_review_details: accepted,
    });
    record.initial_candidate_ids = ['near-0', 'near-1', 'near-2', 'z-manual-anchor'];
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('completed');

    const acceptedCard = Array.from(document.querySelectorAll<HTMLDetailsElement>('.candidate'))
      .find(node => node.textContent?.includes('z-manual-anchor'))!;
    expect(acceptedCard).not.toBeUndefined();
    expect(acceptedCard.open).toBe(true);
    expect(acceptedCard.querySelector('[data-role="candidate-details"]')!.textContent)
      .toContain('manual_cross_page_anchor');
  });

  it('renders classifier and accepted-review evidence separately for the same audit candidate', () => {
    const record = automaticRecord('rk-audit', 'same-candidate', true);
    const accepted = acceptedDecision('rk-audit', 'same-candidate');
    const classifierEvidence = {
      candidate_id: 'same-candidate', postklasse: 'nummereret',
      rule_id: 'complete_anchor_v1', classifier_only: 'bevar mig',
    };
    record.classification = { queue_class: 'auto_resolved', candidate: classifierEvidence };
    record.decision = accepted;
    record.candidates[0].details = classifierEvidence;
    record.candidates[0].accepted_review_details = accepted;
    const { controller } = startReview({ storage: memoryStorage(), records: [record] });

    controller.setView('completed');

    const classifier = document.querySelector<HTMLDetailsElement>(
      '[data-role="candidate-details"][data-evidence-kind="classifier"]',
    )!;
    const acceptedReview = document.querySelector<HTMLDetailsElement>(
      '[data-role="candidate-details"][data-evidence-kind="accepted-review"]',
    )!;
    expect(classifier).not.toBeNull();
    expect(classifier.querySelector('summary')!.textContent).toBe('Klassifikatorens evidens');
    expect(classifier.textContent).toContain('classifier_only');
    expect(classifier.textContent).toContain('bevar mig');
    expect(acceptedReview).not.toBeNull();
    expect(acceptedReview.querySelector('summary')!.textContent).toBe('Accepteret review-evidens');
    expect(acceptedReview.textContent).toContain('manual_cross_page_anchor');
    expect(acceptedReview.open).toBe(false);
  });

  it('renders every candidate expanded without a reveal button', () => {
    const record = humanRecord('rk-1', 'c-1');
    record.candidates = ['c-1', 'c-2', 'c-3', 'c-4'].map(candidateId => ({
      candidate_id: candidateId, lokal_id: candidateId, pdf_pages: [498], calamari_pages: [3],
      raw_text: candidateId, rank_reason: 'samme_pdf_side',
    }));
    record.initial_candidate_ids = ['c-1', 'c-2', 'c-3'];
    startReview({ storage: memoryStorage(), records: [record] });

    const candidates = Array.from(
      document.querySelectorAll<HTMLDetailsElement>('.candidate'),
    );
    expect(candidates).toHaveLength(4);
    expect(candidates.every(candidate => candidate.open)).toBe(true);
    expect(document.querySelector('[data-action="expand-candidates"]')).toBeNull();
  });

  it('shows the validated source-blocked count in the dashboard', () => {
    startReview({ storage: memoryStorage(), records: [humanRecord('rk-1', 'c-1')],
      sourceBlocked: 2 });

    expect(document.querySelector('[data-role="dashboard"]')!.textContent)
      .toContain('Kildeblokerede: 2');
  });

  it.each([-1, 1.5, '1'])(
    'fails closed for an invalid source-blocked count: %s', sourceBlocked => {
      const { controller } = startReview({ storage: memoryStorage(),
        records: [humanRecord('rk-1', 'c-1')], sourceBlocked });

      expect(controller.exportDraft()).toMatchObject({ recovery_blocked: true, entries: [] });
      expect(document.querySelector('[data-role="save-state"]')!.textContent)
        .toContain('Kildeoptællingen kan ikke bruges sikkert');
      expect(document.querySelector('[data-role="dashboard"]')!.textContent)
        .not.toContain(`Kildeblokerede: ${sourceBlocked}`);
    },
  );

  it('renders every candidate for a prototype-like record key', () => {
    const record = humanRecord('__proto__', 'c-1');
    record.candidates = ['c-1', 'c-2', 'c-3', 'c-4'].map(candidateId => ({
      candidate_id: candidateId, lokal_id: candidateId, pdf_pages: [498], calamari_pages: [3],
      raw_text: candidateId, rank_reason: 'samme_pdf_side',
    }));
    record.initial_candidate_ids = ['c-1', 'c-2', 'c-3'];
    startReview({ storage: memoryStorage(), records: [record] });

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

  it('keeps audit review in its own view after a persisted choice', () => {
    const { controller } = startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), automaticRecord('rk-2', 'c-2', true),
      automaticRecord('rk-3', 'c-3', true),
    ] });
    controller.setView('audit');

    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-2' })).toBe(true);

    expect(controller.selectedKey).toBe('rk-3');
    expect(document.querySelector('[data-role="record-list"]')!.textContent).not.toContain('Navn rk-1');
  });

  it('clears a stale storage error after a later successful save', () => {
    const storage = memoryStorage();
    const realSetItem = storage.setItem;
    let fail = true;
    storage.setItem = (key, value) => {
      if (fail) throw new Error('quota');
      realSetItem(key, value);
    };
    const { controller } = startReview({ storage, records: [humanRecord('rk-1', 'c-1')] });
    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(false);
    expect(document.querySelector('[data-role="save-state"]')!.textContent).toContain('Kunne ikke gemme');

    fail = false;
    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-1' })).toBe(true);

    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('Visuelt spor er gemt lokalt');
    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .not.toContain('Kunne ikke gemme');
  });

  it('filters duplicate targets by the plain-text search', () => {
    startReview({ storage: memoryStorage(), records: [
      humanRecord('rk-1', 'c-1'), humanRecord('rk-2', 'c-2'), humanRecord('rk-3', 'c-3'),
    ] });
    let search = document.querySelector<HTMLInputElement>('[data-role="duplicate-search"]')!;
    search.focus();
    for (const value of ['r', 'rk', 'rk-', 'rk-2']) {
      search.value = value;
      search.dispatchEvent(new Event('input', { bubbles: true }));
      expect(document.activeElement).toBe(search);
      search = document.querySelector<HTMLInputElement>('[data-role="duplicate-search"]')!;
    }

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

  it('roundtrips the actual complete Task4 export through the Task5 CLI', () => {
    const records: any[] = [
      humanRecord('rk-choice', 'c-choice'),
      humanRecord('rk-unreviewed', 'c-unused'),
      humanRecord('rk-final', 'c-final'),
    ];
    records[0].decision = {
      baseline_record_key: 'rk-choice', review_status: 'unreviewed',
      baseline_locator: { pages: '498', local_id: 'Stamme.I.1' },
      review_note: 'læst i originalen',
    };
    records[1].decision = {
      baseline_record_key: 'rk-unreviewed', review_status: 'unreviewed',
      baseline_locator: { pages: null, local_id: null },
    };
    records[2].decision = {
      baseline_record_key: 'rk-final', review_status: 'menneskeark',
      reason: 'Historisk afgørelse.',
    };
    const source = viewModel(records).source;
    const { controller } = startReview({ storage: memoryStorage(), records });
    expect(controller.choose('human_selected_candidate', { candidate_id: 'c-choice' })).toBe(true);
    const exported = controller.exportDraft();
    expect(exported.source).toEqual(source);
    expect(exported.entries).toHaveLength(3);

    const directory = mkdtempSync(join(tmpdir(), 'daa1939-task5-roundtrip-'));
    try {
      const choicesPath = join(directory, 'choices.json');
      const queuePath = join(directory, 'queue.json');
      const candidatesPath = join(directory, 'candidates.json');
      const outPath = join(directory, 'decisions.json');
      writeFileSync(choicesPath, JSON.stringify(exported));
      writeFileSync(queuePath, JSON.stringify({
        schema_version: 1,
        source,
        entries: records.map(record => ({
          baseline_record_key: record.record_key,
          queue_class: 'human_required',
          reason_code: 'multiple_candidates',
          reason_da: 'flere kandidater',
        })),
      }));
      writeFileSync(candidatesPath, JSON.stringify({
        'c-choice': {
          baseline_record_key: 'rk-choice',
          candidate: {
            candidate_id: 'c-choice', postklasse: 'nummereret',
            calamari_span: { char_from: 10, char_to: 20 }, pdf_pages: [498],
            raw_structure_bridge: { kind: 'record_start', raw_char_from: 100,
              raw_char_to: 110, raw_excerpt_sha256: 'e'.repeat(64) },
          },
        },
      }));
      const script = resolve(
        process.cwd(), '../.claude/skills/daa-extract/scripts/prepare_coverage_1939.py',
      );
      const result = spawnSync('/usr/bin/python3', [
        script,
        '--choices-to-decisions', choicesPath,
        '--queue-manifest', queuePath,
        '--anchored-candidates', candidatesPath,
        '--out', outPath,
      ], {
        cwd: resolve(process.cwd(), '..'),
        encoding: 'utf8',
        env: { ...process.env, PYTHONPYCACHEPREFIX: join(directory, 'pycache') },
      });

      expect(result.status, result.stderr).toBe(0);
      expect(JSON.parse(readFileSync(outPath, 'utf8'))).toEqual({
        decisions: [{
          baseline_record_key: 'rk-choice', status: 'accepteret', candidate_id: 'c-choice',
        }],
        audit_results: [],
      });
      expect(JSON.parse(readFileSync(choicesPath, 'utf8')).source).toEqual(source);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
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
    expect(document.querySelector('[data-role="decision-state"]')!.textContent)
      .toBe('Nuværende valg: Kildepost valgt (gemt som observation til efterforankring).');
    expect(document.querySelector('[data-role="decision-state"]')!.textContent)
      .not.toContain(candidateId);
    expect(document.querySelector('[data-action="select-candidate"]')!.getAttribute('aria-pressed')).toBe('true');
  });
});
