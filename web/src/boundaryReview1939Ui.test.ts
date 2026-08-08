// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, it, describe, vi } from 'vitest';

const sharedSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/review_ui_shared.js',
), 'utf8');
const uiSource = readFileSync(resolve(
  process.cwd(), '../.claude/skills/daa-extract/scripts/boundary_review_1939_ui.js',
), 'utf8');

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  };
}

function boundary(id: string, bulk = false) {
  return {
    boundary_id: id, revision: 0,
    before: { baseline_record_key: 'rk-6', candidate_id: 'human:6',
              char_from: 0, char_to: 30 },
    after: { baseline_record_key: 'rk-7', candidate_id: 'human:7',
             char_from: 60, char_to: 90 },
    gap: { char_from: 30, char_to: 60 },
    gap_summary: { tegn: 30, klasser: { record_text: 1, structural_header: 0,
                                        layout: 0, noise: 0 },
                   har_broedtekst: true },
    gap_text: '7 Heinrich til Gottesgabe',
    raw_window: '7. H e i n r i c h til Gottesgabe',
    signals: ['slugt_hoved'],
    bulk_confirmable: bulk,
    before_context: '...s. A. Kapitain ved',
    after_context: 'Prins Georgs Reg., 1703 Sek.major',
    before_navn: 'Christine Augusta',
    after_navn: 'Heinrich',
  };
}

function start(boundaries = [boundary('g-1')], options: any = {}) {
  document.body.innerHTML =
    '<aside><div data-role="sidebar-navigation"></div>'
    + '<p data-role="save-state"></p></aside><main data-role="app"></main>';
  const data = {
    schema_version: 1,
    source: { edition: '1939', profile_version: '1939-v2',
              baseline_sha256: 'a'.repeat(64), calamari_sha256: 'b'.repeat(64),
              raw_ocr_sha256: 'c'.repeat(64), pdf_sha256: 'd'.repeat(64) },
    summary: { graenser: boundaries.length,
               kraever_vurdering: boundaries.filter(b => !b.bulk_confirmable).length,
               hurtig_bekraeftelse: boundaries.filter(b => b.bulk_confirmable).length },
    views: {
      kraever_vurdering: boundaries.filter(b => !b.bulk_confirmable).map(b => b.boundary_id),
      hurtig_bekraeftelse: boundaries.filter(b => b.bulk_confirmable).map(b => b.boundary_id),
    },
    boundaries,
    ...(options.tidligere_domme ? { tidligere_domme: options.tidligere_domme } : {}),
  };
  window.eval(sharedSource);
  window.eval(uiSource);
  return (window as any).DAABoundaryReview.init({
    data, storage: options.storage || memoryStorage(),
    now: () => '2026-08-08T10:00:00.000Z', download: options.download,
  });
}

describe('grænsegennemgang', () => {
  it('viser begge sider af skæringen og hvad der ligger imellem', () => {
    start();

    const text = document.querySelector('[data-role="app"]')!.textContent!;
    expect(text).toContain('Christine Augusta');
    expect(text).toContain('Heinrich');
    expect(text).toContain('7 Heinrich til Gottesgabe');
    expect(text).toContain('slugt_hoved');
  });

  it('viser at rå OCR har et hoved Calamari mangler', () => {
    start();

    expect(document.querySelector('[data-role="raw-window"]')!.textContent)
      .toContain('H e i n r i c h');
  });

  it('gemmer en godkendelse og eksporterer den', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_ok')).toBe(true);
    expect(controller.exportDraft().entries).toEqual([{
      boundary_id: 'g-1', revision: 0, verdict: 'graense_ok',
      decided_at: '2026-08-08T10:00:00.000Z',
    }]);
  });

  it('renderer eksportknappen og sender kladden til download-handleren', () => {
    const download = vi.fn();
    start([boundary('g-1')], { download });

    document.querySelector<HTMLButtonElement>('[data-action="export-draft"]')!.click();

    expect(download).toHaveBeenCalledWith(expect.objectContaining({
      schema_version: 1, entries: [],
    }));
  });

  it('gendanner indlejrede tidligere domme før den lokale kladde lægges ovenpå', () => {
    const tidligere_domme = {
      schema_version: 1, source: { edition: '1939' },
      entries: [{ boundary_id: 'g-1', revision: 0, verdict: 'graense_ok',
                  decided_at: '2026-08-08T08:00:00.000Z' }],
      ocr_noter: [],
    };
    const embedded = start([boundary('g-1')], { tidligere_domme });

    expect(embedded.exportDraft().entries).toEqual([{
      boundary_id: 'g-1', revision: 0, verdict: 'graense_ok',
      decided_at: '2026-08-08T08:00:00.000Z',
    }]);

    const storage = memoryStorage();
    storage.setItem(
      `daa1939-graenser:v1:${JSON.stringify({ edition: '1939', profile_version: '1939-v2',
        baseline_sha256: 'a'.repeat(64), calamari_sha256: 'b'.repeat(64),
        raw_ocr_sha256: 'c'.repeat(64), pdf_sha256: 'd'.repeat(64) })}`,
      JSON.stringify({ verdicts: { 'g-1': {
        boundary_id: 'g-1', revision: 0, verdict: 'hul_ejerloest',
        decided_at: '2026-08-08T09:00:00.000Z',
      } } }),
    );
    const controller = start([boundary('g-1')], {
      storage,
      tidligere_domme,
    });

    expect(controller.exportDraft().entries).toEqual([{
      boundary_id: 'g-1', revision: 0, verdict: 'hul_ejerloest',
      decided_at: '2026-08-08T09:00:00.000Z',
    }]);
  });

  it('afviser graense_forkert uden begrundelse', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_forkert')).toBe(false);
    expect(controller.verdict('g-1', 'graense_forkert', { begrundelse: 'nr. 7 mangler' }))
      .toBe(true);
  });

  it('kender ikke fase 2-dommene', () => {
    const controller = start();

    expect(controller.verdict('g-1', 'graense_flyttet', { punkt: 30 })).toBe(false);
    expect(controller.verdict('g-1', 'hul_lagt_til_post', { post: 'rk-6' })).toBe(false);
  });

  it('hænger en OCR-note på posten, ikke på grænsen', () => {
    const controller = start();

    expect(controller.note('rk-7', { staar: 'Sopliie', burde: 'Sophie',
                                     raa_bekraefter: true })).toBe(true);
    expect(controller.exportDraft().ocr_noter).toEqual([{
      baseline_record_key: 'rk-7', staar: 'Sopliie', burde: 'Sophie',
      raa_bekraefter: true, noted_at: '2026-08-08T10:00:00.000Z',
    }]);
  });

  it('massebekræfter kun grænser der er portet til det', () => {
    const controller = start([boundary('g-1'), boundary('g-2', true)]);

    expect(controller.verdict('g-1', 'hul_ejerloest')).toBe(true);
    document.querySelector<HTMLButtonElement>('[data-action="bulk-confirm"]')!.click();
    const ids = controller.exportDraft().entries.map((e: any) => e.boundary_id);
    expect(ids).toContain('g-2');
    expect(controller.exportDraft().entries
      .find((e: any) => e.boundary_id === 'g-2').verdict).toBe('hul_ejerloest');
  });

  it('sætter en ugyldig gemt dom i karantæne frem for at kassere den', () => {
    const storage = memoryStorage();
    storage.setItem('daa1939-graenser:v1:{"edition":"1939"}',
                    JSON.stringify({ 'g-ukendt': { verdict: 'graense_ok' } }));
    document.body.innerHTML =
      '<aside><div data-role="sidebar-navigation"></div>'
      + '<p data-role="save-state"></p></aside><main data-role="app"></main>';
    window.eval(sharedSource);
    window.eval(uiSource);
    (window as any).DAABoundaryReview.init({
      data: { schema_version: 1, source: { edition: '1939' },
              summary: { graenser: 1, kraever_vurdering: 1, hurtig_bekraeftelse: 0 },
              views: { kraever_vurdering: ['g-1'], hurtig_bekraeftelse: [] },
              boundaries: [boundary('g-1')] },
      storage, now: () => '2026-08-08T10:00:00.000Z',
    });

    expect(document.querySelector('[data-role="save-state"]')!.textContent)
      .toContain('karantæne');
  });
});
