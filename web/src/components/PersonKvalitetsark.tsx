// Task 8: spreadsheet-grid til personkontrol (præsentationslag —
// docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md "Task 8"). Modtager rows
// via props (task 7's dataadapter henter dem); skriver intet (task 9's sidepanel ejer
// gemning). Bruger @daa/core's rene filterKvalitetsark/sortKvalitetsark — ingen
// reimplementering af filtrering/sortering her.
//
// Én grid-række = én fysisk person.id. Rows løber ALDRIG gennem collapseSameAs —
// samme_som er read-only kontekst (Global Constraints), så to fysiske personer med
// samme kanoniske person vises begge, uafhængigt af hinanden.
import { useMemo, useState, type CSSProperties } from 'react';
import { Link } from '../Link';
import {
  filterKvalitetsark, sortKvalitetsark,
  type KvalitetsarkFilter, type KvalitetsarkPreset, type KvalitetsarkSortKey,
  type OcrFelt, type OcrReviewStatus, type PersonKvalitetsarkRow,
} from '@daa/core';

export type PersonKvalitetsarkProps = {
  rows: PersonKvalitetsarkRow[];
  loading: boolean;
  error: string | null;
  selected: { personId: string; felt: OcrFelt } | null;
  onSelect: (selection: { personId: string; felt: OcrFelt }) => void;
  onOpenPerson: (personId: string) => void;
};

// Smal, lokal kopi af de delte tema-tokens fra web/src/Redaktion.tsx:57 (`const T`) — den
// konstant er ikke exporteret dér, og denne opgave må ikke ændre den fil (Task 9). Kun de
// tokens denne komponent rent faktisk bruger. Task 9 kan hoiste dette til et delt modul
// frem for at holde to kopier.
const T = {
  paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', bordeaux: '#881A33', muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c',
  red: '#8a2b2b',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};

// Danske labels til felt-/reviewstatus-filtrene (samme fire/fem koder som
// EDITABLE_COLUMN_FELT / OcrReviewStatus i @daa/core).
const FELT_LABELS: Record<OcrFelt, string> = {
  navn: 'Navn', foedsel: 'Født', doed: 'Død', koen: 'Køn',
};
const REVIEW_STATUS_LABELS: Record<OcrReviewStatus, string> = {
  aaben: 'Åben', rettet: 'Rettet', godkendt: 'Godkendt', udskudt: 'Udskudt', stale: 'Stale',
};

const PRESETS: { key: KvalitetsarkPreset; label: string }[] = [
  { key: 'alle', label: 'Alle personer' },
  { key: 'aabne', label: 'Åbne OCR-fejl' },
  { key: 'rettede', label: 'Rettede' },
  { key: 'godkendte', label: 'Godkendte' },
  { key: 'udskudte', label: 'Udskudte' },
  { key: 'stale', label: 'Stale' },
];

type ColumnKey =
  | 'qa' | 'navn' | 'foedsel' | 'doed' | 'koen' | 'kilde' | 'linje'
  | 'titler' | 'familier' | 'relationer' | 'levende' | 'privat' | 'staged' | 'status' | 'sammeSom';

type ColumnDef = { key: ColumnKey; label: string; sortKey?: KvalitetsarkSortKey; hideable: boolean };

// "Required columns in the default desktop layout" (plan Task 8) — rækkefølgen her ER
// standard-layoutet. QA + Navn er identitetskolonner: altid synlige, sticky til venstre.
const COLUMNS: ColumnDef[] = [
  { key: 'qa', label: 'QA', sortKey: 'qa_alvor', hideable: false },
  { key: 'navn', label: 'Navn', sortKey: 'navn', hideable: false },
  { key: 'foedsel', label: 'Født', sortKey: 'foedsel', hideable: true },
  { key: 'doed', label: 'Død', sortKey: 'doed', hideable: true },
  { key: 'koen', label: 'Køn', sortKey: 'koen', hideable: true },
  { key: 'kilde', label: 'Kilde/udgave', hideable: true },
  { key: 'linje', label: 'Linje/post', sortKey: 'linje', hideable: true },
  { key: 'titler', label: 'Titler', hideable: true },
  { key: 'familier', label: 'Familier', hideable: true },
  { key: 'relationer', label: 'Relationer', hideable: true },
  { key: 'levende', label: 'levende', hideable: true },
  { key: 'privat', label: 'privat', hideable: true },
  { key: 'staged', label: 'staged', hideable: true },
  { key: 'status', label: 'status', hideable: true },
  { key: 'sammeSom', label: 'samme_som', hideable: true },
];

const QA_WIDTH = 64;
const NAVN_WIDTH = 220;

const QA_ALVOR: Record<'fejl' | 'advarsel' | 'info', { label: string; icon: string }> = {
  fejl: { label: 'Fejl', icon: '⛔' },
  advarsel: { label: 'Advarsel', icon: '⚠' },
  info: { label: 'Info', icon: 'ℹ' },
};

// Blokarsag-koderne kommer fra red_person_grid() (schema.sql field_state.blokarsag) —
// snake_case interne koder, ikke selvforklarende Dansk. Ukendte koder falder tilbage til
// selve koden frem for at forsvinde tavst.
const BLOKARSAG_TEKST: Record<string, string> = {
  ingen_importanker: 'Personen har ingen importanker og kan ikke rettes her.',
  flere_importankre: 'Personen har flere importankre — brug den almindelige editor.',
  import_key_mangler: 'Kildeforankringen mangler en import-nøgle — brug den almindelige editor.',
  record_key_mangler: 'Kildeforankringen mangler en post-nøgle — brug den almindelige editor.',
  ingen_kildebelagt_assertion: 'Feltet har ingen kildebelagt påstand at rette.',
  flere_importerede_facts: 'Feltet peger på flere kildebelagte påstande — brug den almindelige editor.',
};

function blokarsagTekst(kode: string): string {
  return BLOKARSAG_TEKST[kode] ?? kode;
}

function displayEllerStreg(v: string | null): string {
  return v ?? '—';
}

function kildeTekst(row: PersonKvalitetsarkRow): string {
  if (row.sourceTitel === null) return '—';
  return row.sourceUdgave ? `${row.sourceTitel} · ${row.sourceUdgave}` : row.sourceTitel;
}

function linjeTekst(row: PersonKvalitetsarkRow): string {
  if (row.linje === null && row.nr === null) return '—';
  return `${row.linje ?? ''}${row.nr != null ? `-${row.nr}` : ''}`;
}

// De fire redigerbare OCR-felt-kolonner deler samme celle-form (renderEditableCell) og
// varierer kun i hvilket felt de retter og hvordan de læser deres visningsværdi.
const EDITABLE_COLUMN_FELT: Partial<Record<ColumnKey, OcrFelt>> = {
  navn: 'navn', foedsel: 'foedsel', doed: 'doed', koen: 'koen',
};
const EDITABLE_COLUMN_VALUE: Record<OcrFelt, (row: PersonKvalitetsarkRow) => string> = {
  navn: (row) => row.navn,
  foedsel: (row) => displayEllerStreg(row.foedselRaw),
  doed: (row) => displayEllerStreg(row.doedRaw),
  koen: (row) => displayEllerStreg(row.koen),
};

// De tre tælle-kolonner deler samme celle-form (renderCountCell — altid en knap der åbner
// personeditoren) og varierer kun i hvilket antal og hvilken enhedstekst de viser.
const COUNT_COLUMNS: Partial<Record<ColumnKey, { antal: (row: PersonKvalitetsarkRow) => number; enhed: string }>> = {
  titler: { antal: (row) => row.antalTitler, enhed: 'titler' },
  familier: { antal: (row) => row.antalFamilier, enhed: 'familier' },
  relationer: { antal: (row) => row.antalRelationer, enhed: 'relationer' },
};

// Fælles pipeline til filtrenes værdilister (kilde/linje): distinkte, ikke-null-værdier,
// dansk-sorteret.
function uniqueSorted(rows: PersonKvalitetsarkRow[], vaelg: (r: PersonKvalitetsarkRow) => string | null): string[] {
  return Array.from(new Set(rows.map(vaelg).filter((v): v is string => v !== null))).sort();
}

const th_base: CSSProperties = {
  position: 'sticky', top: 0, background: T.panel, zIndex: 2,
  padding: '6px 10px', textAlign: 'left', fontFamily: T.mono, fontSize: 10.5,
  letterSpacing: '.06em', textTransform: 'uppercase', color: T.muted,
  borderBottom: '1px solid rgba(34,31,26,.14)', whiteSpace: 'nowrap',
};

const td_base: CSSProperties = {
  padding: '5px 10px', fontSize: 13.5, color: T.ink,
  borderBottom: '1px solid rgba(34,31,26,.08)', whiteSpace: 'nowrap',
};

// De to permanente identitetskolonner (QA + Navn) er sticky til venstre, i denne
// rækkefølge — `left` er den akkumulerede bredde af foregående sticky-kolonner. Kun disse
// to kan være sticky (hideable kolonner er det aldrig); en tredje sticky-kolonne ville
// kræve at denne tabel blev udledt af akkumulerede bredder frem for faste `left`-værdier.
const STICKY_IDENTITY: Partial<Record<ColumnKey, { left: number; width: number }>> = {
  qa: { left: 0, width: QA_WIDTH },
  navn: { left: QA_WIDTH, width: NAVN_WIDTH },
};
const INGEN_IDENTITY_STYLE: CSSProperties = {};

function identityStyle(col: ColumnKey, isHeader: boolean): CSSProperties {
  const sticky = STICKY_IDENTITY[col];
  if (!sticky) return INGEN_IDENTITY_STYLE;
  return {
    position: 'sticky', left: sticky.left, zIndex: isHeader ? 3 : 1,
    background: isHeader ? T.panel : T.paper, width: sticky.width, minWidth: sticky.width,
  };
}

function editableButtonStyle(selected: boolean): CSSProperties {
  return {
    border: 0, background: selected ? T.beige : 'transparent', borderRadius: 6,
    padding: '3px 6px', font: 'inherit', color: T.ink, cursor: 'pointer', textAlign: 'left',
  };
}

// Delt af "Filtrér på kilde" og "Filtrér på linje" — identisk form, forskellig værdiliste.
function FilterSelect({ label, alleLabel, value, options, onChange }: {
  label: string;
  alleLabel: string;
  value: string | null;
  options: string[];
  onChange: (value: string | null) => void;
}) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', fontSize: 10.5, color: T.muted3, gap: 2 }}>
      {label}
      <select
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value || null)}
        style={{ fontSize: 13, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6 }}
      >
        <option value="">{alleLabel}</option>
        {options.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
    </label>
  );
}

// Delt af "Filtrér på felt" og "Filtrér på reviewstatus" — samme form som FilterSelect,
// men med separate value/label-par (koderne fra @daa/core er ikke selvforklarende Dansk).
function EnumFilterSelect<K extends string>({ label, alleLabel, value, options, onChange }: {
  label: string;
  alleLabel: string;
  value: K | null;
  options: { value: K; label: string }[];
  onChange: (value: K | null) => void;
}) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', fontSize: 10.5, color: T.muted3, gap: 2 }}>
      {label}
      <select
        value={value ?? ''}
        onChange={(e) => onChange((e.target.value || null) as K | null)}
        style={{ fontSize: 13, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6 }}
      >
        <option value="">{alleLabel}</option>
        {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </label>
  );
}

// Delt af "Filtrér på staged" og "Filtrér på samme_som" — tre tilstande (alle / ja / nej)
// over en boolean|null-dimension. HTML-select-værdier er altid strenge, så 'true'/'false'
// koder booleanen og '' koder null (= "alle").
function TriStateFilterSelect({ label, alleLabel, jaLabel, nejLabel, value, onChange }: {
  label: string;
  alleLabel: string;
  jaLabel: string;
  nejLabel: string;
  value: boolean | null;
  onChange: (value: boolean | null) => void;
}) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', fontSize: 10.5, color: T.muted3, gap: 2 }}>
      {label}
      <select
        value={value === null ? '' : value ? 'true' : 'false'}
        onChange={(e) => onChange(e.target.value === '' ? null : e.target.value === 'true')}
        style={{ fontSize: 13, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6 }}
      >
        <option value="">{alleLabel}</option>
        <option value="true">{jaLabel}</option>
        <option value="false">{nejLabel}</option>
      </select>
    </label>
  );
}

export function PersonKvalitetsark({ rows, loading, error, selected, onSelect, onOpenPerson }: PersonKvalitetsarkProps) {
  const [preset, setPreset] = useState<KvalitetsarkPreset>('alle');
  const [query, setQuery] = useState('');
  const [sourceFilter, setSourceFilter] = useState<string | null>(null);
  const [linjeFilter, setLinjeFilter] = useState<string | null>(null);
  const [feltFilter, setFeltFilter] = useState<OcrFelt | null>(null);
  const [reviewStatusFilter, setReviewStatusFilter] = useState<OcrReviewStatus | null>(null);
  const [stagedFilter, setStagedFilter] = useState<boolean | null>(null);
  const [sammeSomFilter, setSammeSomFilter] = useState<boolean | null>(null);
  const [sortKey, setSortKey] = useState<KvalitetsarkSortKey>('navn');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [columnsOpen, setColumnsOpen] = useState(false);
  const [hiddenColumns, setHiddenColumns] = useState<ReadonlySet<ColumnKey>>(new Set());

  const kilder = useMemo(() => uniqueSorted(rows, (r) => r.sourceTitel), [rows]);
  const linjer = useMemo(() => uniqueSorted(rows, (r) => r.linje), [rows]);

  // rows kan være op til ~2000 lange, og sortKvalitetsark sammenligner med en Intl.Collator
  // pr. par — genberegnes derfor kun når filter-/sorteringsinput reelt ændrer sig, ikke ved
  // urelaterede re-renders (fx celle-valg eller åbning af kolonnepanelet).
  const sorted = useMemo(() => {
    const filter: KvalitetsarkFilter = {
      preset, query, source: sourceFilter, linje: linjeFilter,
      felt: feltFilter, reviewStatus: reviewStatusFilter, staged: stagedFilter, sammeSom: sammeSomFilter,
    };
    return sortKvalitetsark(filterKvalitetsark(rows, filter), sortKey, sortDir);
  }, [
    rows, preset, query, sourceFilter, linjeFilter, feltFilter, reviewStatusFilter,
    stagedFilter, sammeSomFilter, sortKey, sortDir,
  ]);

  function handleSort(key: KvalitetsarkSortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir('asc');
    }
  }

  function toggleColumn(key: ColumnKey) {
    setHiddenColumns((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key); else next.add(key);
      return next;
    });
  }

  const visibleColumns = COLUMNS.filter((c) => !c.hideable || !hiddenColumns.has(c.key));

  if (loading) {
    return <div style={{ padding: 18, fontFamily: T.sans, color: T.muted }}>Indlæser personkontrol…</div>;
  }
  if (error) {
    return <div role="alert" style={{ padding: 18, fontFamily: T.sans, color: T.red }}>{error}</div>;
  }

  function renderEditableCell(row: PersonKvalitetsarkRow, felt: OcrFelt, value: string) {
    const kanRettes = row.kanRettes[felt];
    const isSelected = selected !== null && selected.personId === row.personId && selected.felt === felt;
    if (kanRettes) {
      return (
        <button
          type="button"
          aria-pressed={isSelected}
          onClick={() => onSelect({ personId: row.personId, felt })}
          style={editableButtonStyle(isSelected)}
        >
          {value}
        </button>
      );
    }
    const kode = row.blokarsager[felt];
    const reasonText = kode ? blokarsagTekst(kode) : 'Feltet kan ikke rettes her.';
    const reasonId = `kv-reason-${row.personId}-${felt}`;
    return (
      <div>
        <span role="button" tabIndex={0} aria-disabled="true" aria-describedby={reasonId}>
          {value}
        </span>
        <p id={reasonId} style={{ fontSize: 10.5, color: T.muted2, margin: '2px 0 0' }}>{reasonText}</p>
        <Link
          href={`/redaktion/person/${row.personId}`}
          onNavigate={() => onOpenPerson(row.personId)}
          style={{ fontSize: 10.5, color: T.bordeaux, padding: '2px 0', display: 'inline-block' }}
        >
          Åbn person
        </Link>
      </div>
    );
  }

  function renderCountCell(row: PersonKvalitetsarkRow, antal: number, enhed: string) {
    return (
      <Link
        href={`/redaktion/person/${row.personId}`}
        onNavigate={() => onOpenPerson(row.personId)}
        style={{ color: T.ink, display: 'inline-block' }}
      >
        {antal} {enhed}
      </Link>
    );
  }

  function renderCell(row: PersonKvalitetsarkRow, col: ColumnDef) {
    const editableFelt = EDITABLE_COLUMN_FELT[col.key];
    if (editableFelt) {
      return renderEditableCell(row, editableFelt, EDITABLE_COLUMN_VALUE[editableFelt](row));
    }
    const countCol = COUNT_COLUMNS[col.key];
    if (countCol) {
      return renderCountCell(row, countCol.antal(row), countCol.enhed);
    }
    switch (col.key) {
      case 'qa': {
        if (row.qaAlvor === null) return <span>—</span>;
        const alvor = QA_ALVOR[row.qaAlvor];
        return (
          <div>
            <span aria-hidden="true">{alvor.icon}</span> <span>{alvor.label}</span>
            {row.qaKoder.length > 0 && (
              <div style={{ fontSize: 10, color: T.muted2 }}>{row.qaKoder.join(', ')}</div>
            )}
          </div>
        );
      }
      case 'kilde':
        return <span>{kildeTekst(row)}</span>;
      case 'linje':
        return <span>{linjeTekst(row)}</span>;
      case 'levende':
        return <span>{row.levende ? 'Ja' : 'Nej'}</span>;
      case 'privat':
        return <span>{row.privat ? 'Ja' : 'Nej'}</span>;
      case 'staged':
        return <span>{row.staged ? 'Ja' : 'Nej'}</span>;
      case 'status':
        return <span>{displayEllerStreg(row.personStatus)}</span>;
      case 'sammeSom':
        return <span>{displayEllerStreg(row.sammeSomStatus)}</span>;
      default:
        return null;
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', fontFamily: T.sans }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10, padding: '10px 14px', background: T.panel, borderBottom: '1px solid rgba(34,31,26,.1)' }}>
        <div role="group" aria-label="Filtrér efter status" style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {PRESETS.map((p) => (
            <button
              key={p.key}
              type="button"
              aria-pressed={preset === p.key}
              onClick={() => setPreset(p.key)}
              style={{
                border: 0, borderRadius: 6, padding: '5px 10px', cursor: 'pointer',
                background: preset === p.key ? T.bordeaux : T.beige,
                color: preset === p.key ? T.paper : T.muted, fontSize: 12.5, fontWeight: 600,
              }}
            >
              {p.label}
            </button>
          ))}
        </div>

        <label style={{ display: 'flex', flexDirection: 'column', fontSize: 10.5, color: T.muted3, gap: 2 }}>
          Søg
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Navn, post, kilde…"
            style={{ fontSize: 13, padding: '5px 8px', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6 }}
          />
        </label>

        <FilterSelect
          label="Filtrér på kilde" alleLabel="Alle kilder"
          value={sourceFilter} options={kilder} onChange={setSourceFilter}
        />
        <FilterSelect
          label="Filtrér på linje" alleLabel="Alle linjer"
          value={linjeFilter} options={linjer} onChange={setLinjeFilter}
        />
        <EnumFilterSelect
          label="Filtrér på felt" alleLabel="Alle felter"
          value={feltFilter}
          options={(['navn', 'foedsel', 'doed', 'koen'] as const).map((f) => ({ value: f, label: FELT_LABELS[f] }))}
          onChange={setFeltFilter}
        />
        <EnumFilterSelect
          label="Filtrér på reviewstatus" alleLabel="Alle statusser"
          value={reviewStatusFilter}
          options={(['aaben', 'rettet', 'godkendt', 'udskudt', 'stale'] as const).map((s) => ({ value: s, label: REVIEW_STATUS_LABELS[s] }))}
          onChange={setReviewStatusFilter}
        />
        <TriStateFilterSelect
          label="Filtrér på staged" alleLabel="Alle" jaLabel="Kun staged" nejLabel="Kun ikke-staged"
          value={stagedFilter} onChange={setStagedFilter}
        />
        <TriStateFilterSelect
          label="Filtrér på samme_som" alleLabel="Alle" jaLabel="Kun med samme_som" nejLabel="Kun uden samme_som"
          value={sammeSomFilter} onChange={setSammeSomFilter}
        />

        <div style={{ position: 'relative' }}>
          <button
            type="button"
            aria-expanded={columnsOpen}
            onClick={() => setColumnsOpen((v) => !v)}
            style={{ border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, padding: '5px 10px', background: T.paper, cursor: 'pointer', fontSize: 12.5 }}
          >
            Kolonner
          </button>
          {columnsOpen && (
            <div style={{ position: 'absolute', top: '110%', left: 0, background: T.paper, border: '1px solid rgba(34,31,26,.16)', borderRadius: 8, padding: 10, zIndex: 10, minWidth: 200, boxShadow: '0 6px 18px rgba(0,0,0,.15)' }}>
              {COLUMNS.filter((c) => c.hideable).map((c) => (
                <label key={c.key} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, padding: '2px 0' }}>
                  <input type="checkbox" checked={!hiddenColumns.has(c.key)} onChange={() => toggleColumn(c.key)} />
                  {c.label}
                </label>
              ))}
              <button
                type="button"
                onClick={() => setHiddenColumns(new Set())}
                style={{ marginTop: 6, border: 0, background: 'transparent', color: T.bordeaux, cursor: 'pointer', fontSize: 12, padding: 0 }}
              >
                Nulstil kolonner
              </button>
            </div>
          )}
        </div>

        <span aria-live="polite" style={{ marginLeft: 'auto', fontFamily: T.mono, fontSize: 11, color: T.muted2 }}>
          Viser {sorted.length} af {rows.length} personer
        </span>
      </div>

      <div data-testid="kvalitetsark-scroll" style={{ flex: 1, minWidth: 0, overflowX: 'auto', overflowY: 'auto' }}>
        <table style={{ borderCollapse: 'collapse', minWidth: 1400, width: '100%' }}>
          <thead>
            <tr>
              {visibleColumns.map((col) => {
                const identity = identityStyle(col.key, true);
                if (!col.sortKey) {
                  return <th key={col.key} style={{ ...th_base, ...identity }}>{col.label}</th>;
                }
                const active = sortKey === col.sortKey;
                const ariaSort = active ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none';
                return (
                  <th key={col.key} style={{ ...th_base, ...identity }} aria-sort={ariaSort}>
                    <button
                      type="button"
                      onClick={() => handleSort(col.sortKey!)}
                      style={{ border: 0, background: 'transparent', font: 'inherit', color: 'inherit', cursor: 'pointer', padding: 0 }}
                    >
                      {col.label}
                    </button>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {sorted.map((row) => (
              <tr key={row.personId} data-testid={`kv-row-${row.personId}`}>
                {visibleColumns.map((col) => (
                  <td key={col.key} style={{ ...td_base, ...identityStyle(col.key, false) }}>
                    {renderCell(row, col)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
