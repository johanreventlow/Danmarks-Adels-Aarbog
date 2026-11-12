// B11 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.4): fakta-sektionen i persondetaljen. Rækkerne kommer fra
// public_person_facts (én pr. påstand og citation); her grupperes de pr. faktum, ordnes og får deres kildevisning:
// bundet til bogens post (trin 4-binding), fra den oprindelige import (citation), eller ingen registreret kilde.
import { visbarPostEtiket } from './recordLabel';

export type PublicPersonFactRow = {
  person_id: number | string;
  fact_id: number | string;
  faktatype: string;
  conclusion_status: 'afklaret' | 'omstridt' | string;
  assertion_id: number | string;
  chosen: boolean;
  vaerdi_tekst: string | null;
  date_raw: string | null;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
  date_certainty: string | null;
  source_id: number | string | null;
  source_label: string | null;
  side: string | null;
  record_ref: string | null;
  record_label: string | null;
  citation_label: string | null;
};

export type PersonFactSource = { kind: 'bundet' | 'import' | 'ingen'; label: string; recordRef: string | null };
export type PersonFactStatement = { assertionId: string; value: string; source: PersonFactSource };
export type PersonFactView = {
  factId: string;
  faktatype: string;
  omstridt: boolean;
  chosen: PersonFactStatement | null;
  others: PersonFactStatement[];
};

// forældrefamilie vises som familie med kildelinje; forældre_ukendt har sin egen markering.
export const FAKTA_UDELADT = ['forældrefamilie', 'forældre_ukendt'];

const FAKTA_RAEKKEFOELGE = ['navn', 'tilnavn', 'fødsel', 'dåb', 'titel', 'dekoration', 'adling', 'floruit',
  'klosterindgang', 'overhoved', 'død', 'dødsårsag', 'begravelse'];

const typeRank = (t: string) => {
  const i = FAKTA_RAEKKEFOELGE.indexOf(t);
  return i === -1 ? FAKTA_RAEKKEFOELGE.length : i;
};

function factValue(r: PublicPersonFactRow): string {
  // date_raw udelades, når den er identisk med vaerdi_tekst (ellers vises samme tekst to gange).
  const dateRaw = r.date_raw && r.vaerdi_tekst && r.date_raw.trim() === r.vaerdi_tekst.trim() ? null : r.date_raw;
  const parts = [r.vaerdi_tekst, dateRaw].filter((x): x is string => !!x && x.trim() !== '');
  return parts.length ? parts.join(', ') : '—';
}

function factSource(r: PublicPersonFactRow): PersonFactSource {
  if (r.record_ref) {
    // citation_label bærer allerede udgave og side (»DAA 2018-20, s. 45«); record_label er posten (»I-32«).
    const label = [r.citation_label || r.source_label, visbarPostEtiket(r.record_label)].filter(Boolean).join(' · ');
    return { kind: 'bundet', label, recordRef: r.record_ref };
  }
  if (r.source_label) {
    return { kind: 'import', label: r.side ? `${r.source_label}, s. ${r.side}` : r.source_label, recordRef: null };
  }
  return { kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null };
}

export function buildPersonFacts(rows: PublicPersonFactRow[]): PersonFactView[] {
  const seen = new Set<string>();
  const byFact = new Map<string, { first: PublicPersonFactRow; rows: PublicPersonFactRow[] }>();
  for (const r of rows) {
    if (FAKTA_UDELADT.includes(r.faktatype)) continue;
    const key = JSON.stringify(r);
    if (seen.has(key)) continue; // samme række fra flere medlems-id'er
    seen.add(key);
    const g = byFact.get(String(r.fact_id));
    if (g) g.rows.push(r);
    else byFact.set(String(r.fact_id), { first: r, rows: [r] });
  }
  const views = [...byFact.values()].map(({ first, rows: rs }) => {
    const statements = rs.map((r) => ({ row: r, st: { assertionId: String(r.assertion_id), value: factValue(r), source: factSource(r) } }));
    const chosenIdx = statements.findIndex((s) => s.row.chosen);
    return {
      view: {
        factId: String(first.fact_id),
        faktatype: first.faktatype,
        omstridt: first.conclusion_status === 'omstridt',
        chosen: chosenIdx === -1 ? null : statements[chosenIdx].st,
        others: statements.filter((_, i) => i !== chosenIdx).map((s) => s.st),
      } satisfies PersonFactView,
      dateMin: first.date_min,
      factNum: Number(first.fact_id),
    };
  });
  views.sort((a, b) =>
    typeRank(a.view.faktatype) - typeRank(b.view.faktatype)
    || (a.dateMin === b.dateMin ? 0 : a.dateMin == null ? 1 : b.dateMin == null ? -1 : a.dateMin < b.dateMin ? -1 : 1)
    || a.factNum - b.factNum);
  return views.map((v) => v.view);
}
