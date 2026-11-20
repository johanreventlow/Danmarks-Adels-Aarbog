// OCR-rettelse af kildepåstand (decisions 2026-11-20): retter en importeret kildepåstand på stedet via
// red_ret_ocr_paastand i stedet for at lægge en ny påstand ved siden af (red_edit_oplysning). Ren logik;
// databasen er den autoritative grænse — dette er kun hvad editoren tilbyder og sender.
import { normaliserOcrDato } from '@daa/core';
import type { FeltEvidens, Oplysning } from './redaktionRead';
import { DATE_FELT } from './redaktionWrite';

export type OcrPaastandArgs = {
  p_assertion_id: number;
  p_forventet: Record<string, unknown>;
  p_ny: Record<string, unknown>;
};

function kildeIds(o: Oplysning): { ids: number[]; fritekst: boolean } {
  const ids = [...new Set(o.kilder.map((k) => k.sourceId).filter((id): id is number => id != null))].sort((a, b) => a - b);
  return { ids, fritekst: o.kilder.some((k) => k.sourceId == null) };
}

// Importeret kildepåstand med præcis én kilde og ingen fritekst-citation (samme regel som RPC'en).
export function kanRetteLaesefejl(o: Oplysning): boolean {
  if (o.uforanderlig === false) return false;
  const { ids, fritekst } = kildeIds(o);
  return ids.length === 1 && !fritekst;
}

// null = intet at sende: kan ikke rettes, mangler rå kolonner, tom/uændret værdi, eller dato der ikke kan fortolkes
// og ikke er bekræftet.
export function byggOcrPaastand(
  f: FeltEvidens, o: Oplysning, ny: string, bekraeftUfortolkelig: boolean,
): OcrPaastandArgs | null {
  if (!kanRetteLaesefejl(o) || o.vaerdiTekst === undefined || o.dateRaw === undefined) return null;
  const vaerdi = ny.trim();
  if (vaerdi === '') return null;
  const p_forventet = {
    fact_id: f.factId, faktatype: f.faktatype, vaerdi_tekst: o.vaerdiTekst, date_raw: o.dateRaw,
    valgt_assertion_id: f.konklusionAssertionId, citation_sources: kildeIds(o).ids,
  };
  if (DATE_FELT.has(f.felt)) {
    if (o.dateRaw == null || vaerdi === o.dateRaw) return null;
    const info = normaliserOcrDato(vaerdi);
    if (!info.understood && !bekraeftUfortolkelig) return null;
    return {
      p_assertion_id: o.assertionId, p_forventet,
      p_ny: {
        date_raw: vaerdi,
        date_min: info.understood ? info.min : null,
        date_max: info.understood ? info.max : null,
        date_qualifier: info.understood ? info.qualifier : null,
        date_certainty: info.understood ? info.certainty : null,
      },
    };
  }
  if (o.vaerdiTekst == null || vaerdi === o.vaerdiTekst) return null;
  return { p_assertion_id: o.assertionId, p_forventet, p_ny: { vaerdi_tekst: vaerdi } };
}
