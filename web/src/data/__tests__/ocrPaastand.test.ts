// OCR-rettelse af kildepåstand (decisions 2026-11-20): hvilke påstande kan rettes, og hvad sendes til
// red_ret_ocr_paastand. Ren logik, ingen netværk.
import { describe, expect, it, vi } from 'vitest';
import { normaliserOcrDato } from '@daa/core';

// DATE_FELT bor i redaktionWrite, som importerer supabase-klienten; ingen netværk her.
vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } } }));
import { byggOcrPaastand, kanRetteLaesefejl, laesefejlStartvaerdi } from '../ocrPaastand';
import type { FeltEvidens, Oplysning } from '../redaktionRead';

function oplysning(over: Partial<Oplysning> = {}): Oplysning {
  return {
    assertionId: 13833, vaerdi: '25 Marts 157', vaerdiTekst: null, dateRaw: '25 Marts 157',
    kilder: [{ sourceId: 3, sourceTitel: 'Danmarks Adels Aarbog' }], erKonklusion: true, uforanderlig: true,
    ...over,
  };
}

function felt(over: Partial<FeltEvidens> = {}, o: Oplysning = oplysning()): FeltEvidens {
  return {
    felt: 'foedt', faktatype: 'fødsel', factId: 11315, konklusionAssertionId: 13833,
    oplysninger: [o], uenig: false, ...over,
  };
}

describe('kanRetteLaesefejl', () => {
  it('kildepåstand med én kilde kan rettes', () => {
    expect(kanRetteLaesefejl(felt(), oplysning())).toBe(true);
  });
  it('manglende uforanderlig-felt behandles som kildepåstand', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ uforanderlig: undefined }))).toBe(true);
  });
  it('redaktørens egen oplysning kan ikke', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ uforanderlig: false }))).toBe(false);
  });
  it('to kilder kan ikke', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ kilder: [{ sourceId: 3 }, { sourceId: 1 }] }))).toBe(false);
  });
  it('samme kilde citeret to gange tæller som én', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ kilder: [{ sourceId: 3 }, { sourceId: 3 }] }))).toBe(true);
  });
  it('kun fritekst-kilde kan ikke', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ kilder: [{ sourceId: null }] }))).toBe(false);
  });
  it('kilde plus fritekst kan ikke', () => {
    expect(kanRetteLaesefejl(felt(), oplysning({ kilder: [{ sourceId: 3 }, { sourceId: null }] }))).toBe(false);
  });
});

describe('kanRetteLaesefejl — formens kolonne skal findes', () => {
  it('datofelt uden date_raw kan ikke', () => {
    const o = oplysning({ dateRaw: null, vaerdiTekst: 'ukendt' });
    expect(kanRetteLaesefejl(felt({}, o), o)).toBe(false);
  });
  it('tekstfelt uden vaerdi_tekst kan ikke', () => {
    const o = oplysning({ vaerdiTekst: null, dateRaw: '1750' });
    expect(kanRetteLaesefejl(felt({ felt: 'titel', faktatype: 'titel' }, o), o)).toBe(false);
  });
  it('manglende rå kolonner kan ikke', () => {
    const o = oplysning({ vaerdiTekst: undefined, dateRaw: undefined });
    expect(kanRetteLaesefejl(felt({}, o), o)).toBe(false);
  });
});

describe('laesefejlStartvaerdi', () => {
  // 183 titler i prod har både vaerdi_tekst og date_raw (målt 2026-11-20): formen må ikke åbne med datoen.
  it('titel med både tekst og dato starter med teksten', () => {
    const o = oplysning({ vaerdi: 'Kammerjunker', vaerdiTekst: 'Kammerjunker', dateRaw: '1750' });
    const f = felt({ felt: 'titel', faktatype: 'titel' }, o);
    expect(laesefejlStartvaerdi(f, o)).toBe('Kammerjunker');
    expect(byggOcrPaastand(f, o, laesefejlStartvaerdi(f, o), true)).toBeNull();
  });
  it('datofelt starter med date_raw', () => {
    expect(laesefejlStartvaerdi(felt(), oplysning())).toBe('25 Marts 157');
  });
});

describe('byggOcrPaastand', () => {
  it('dato: forventet viser påstanden som editoren så den, ny bærer parserens læsning', () => {
    const r = byggOcrPaastand(felt(), oplysning(), '25 Marts 1578', false);
    const info = normaliserOcrDato('25 Marts 1578');
    expect(r).toEqual({
      p_assertion_id: 13833,
      p_forventet: {
        fact_id: 11315, faktatype: 'fødsel', vaerdi_tekst: null, date_raw: '25 Marts 157',
        valgt_assertion_id: 13833, citation_sources: [3],
      },
      p_ny: {
        date_raw: '25 Marts 1578', date_min: info.min, date_max: info.max,
        date_qualifier: info.qualifier, date_certainty: info.certainty,
      },
    });
    expect(info.min).toBe('1578-01-01');
  });
  it('værdien trimmes', () => {
    expect(byggOcrPaastand(felt(), oplysning(), '  25 Marts 1578 ', false)?.p_ny.date_raw).toBe('25 Marts 1578');
  });
  it('ufortolkelig dato kræver bekræftelse', () => {
    expect(byggOcrPaastand(felt(), oplysning(), '25 Marts 15', false)).toBeNull();
  });
  it('bekræftet ufortolkelig dato sendes uden fortolkning', () => {
    expect(byggOcrPaastand(felt(), oplysning(), '25 Marts 15', true)?.p_ny).toEqual({
      date_raw: '25 Marts 15', date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
    });
  });
  it('tom eller uændret værdi giver intet kald', () => {
    expect(byggOcrPaastand(felt(), oplysning(), '   ', true)).toBeNull();
    expect(byggOcrPaastand(felt(), oplysning(), '25 Marts 157', true)).toBeNull();
  });
  it('tekstfelt sender vaerdi_tekst', () => {
    const o = oplysning({ vaerdi: 'Sophie von Sperlinq', vaerdiTekst: 'Sophie von Sperlinq', dateRaw: null });
    const r = byggOcrPaastand(felt({ felt: 'navn', faktatype: 'navn' }, o), o, 'Sophie von Sperling', false);
    expect(r?.p_ny).toEqual({ vaerdi_tekst: 'Sophie von Sperling' });
    expect(r?.p_forventet).toMatchObject({ vaerdi_tekst: 'Sophie von Sperlinq', date_raw: null });
  });
  it('ikke-valgt påstand: forventet bærer konklusionens valg', () => {
    const r = byggOcrPaastand(felt({ konklusionAssertionId: 99 }), oplysning({ erKonklusion: false }), '25 Marts 1578', false);
    expect(r?.p_forventet.valgt_assertion_id).toBe(99);
  });
  it('kan ikke rettes giver intet kald', () => {
    expect(byggOcrPaastand(felt(), oplysning({ uforanderlig: false }), '25 Marts 1578', false)).toBeNull();
  });
});
