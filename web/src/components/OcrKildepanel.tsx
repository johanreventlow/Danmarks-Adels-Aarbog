// Task 9 (halvdel A): OCR-kildepanel til feltrettelser (præsentations-lag — se
// docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md "Task 9"). Panelet KALDER
// ikke selv red_ret_ocr_felt/red_ocr_historik — det modtager historik/historikLoading/
// busy/error som props og delegerer selve skrivningen til `onSave`. Integrationslaget
// (Redaktion.tsx, anden halvdel af Task 9) ejer session/dryRun/wiring og kalder den rigtige
// dataadapter (web/src/data/personKvalitetsark.ts's retOcrFelt/fetchOcrHistorik).
//
// Én instans retter ÉT felt for ÉN række — `felt` er fast pr. panel-instans, så
// gem-payloaden kan pr. konstruktion aldrig røre mere end ét felt.
import { useEffect, useMemo, useState, type CSSProperties } from 'react';
import { normaliserOcrDato, type OcrFelt, type PersonKvalitetsarkRow } from '@daa/core';
import type { OcrHistorikEntry } from '../data/personKvalitetsark';

// Struktur-kompatibel med parameter-objektet i personKvalitetsark.ts's retOcrFelt (den type
// er ikke selv exporteret derfra) — bevidst dupliceret her frem for at ændre web/src/data/,
// som er uden for denne opgaves scope. TypeScript's strukturelle typning gør at
// integrationslaget kan sende dette videre til retOcrFelt() uden konvertering.
export type RetOcrFeltInput = {
  personId: string;
  importKey: string;
  recordKey: string;
  felt: OcrFelt;
  inputFingerprint: string;
  korrigeret: Record<string, unknown> | null;
  status: 'rettet' | 'godkendt' | 'udskudt';
  actorNavn?: string;
};

export type OcrKildepanelProps = {
  row: PersonKvalitetsarkRow;
  felt: OcrFelt;
  historik: OcrHistorikEntry[];
  historikLoading: boolean;
  busy: boolean;
  error: string | null;
  // Kontraktfaktum 4: der findes ingen dry-run på red_ret_ocr_felt. Redaktion.tsx's globale
  // prøvekørsels-tilstand (dryRun, default true) skal trædes ind hertil af integrationen —
  // panelet nægter selv at gemme når den er sand, uanset hvad kalderen ellers gør.
  proevekoersel: boolean;
  onSave: (input: RetOcrFeltInput) => Promise<void>;
  onClose: () => void;
  onOpenPerson: (personId: string) => void;
  // Kontraktfaktum 2: ved OCR_FINGERPRINT_STALE skal panelet blive åbent og bede om en frisk
  // række via denne selv-definerede prop, så retry bruger det NYE fingerprint — aldrig det
  // forældede panelet allerede holdt.
  onRefreshRow: (personId: string) => Promise<PersonKvalitetsarkRow>;
};

const T = {
  paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', bordeaux: '#881A33', muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c',
  red: '#8a2b2b', green: '#1f5b3a',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};

const FELT_LABELS: Record<OcrFelt, string> = {
  navn: 'Navn', foedsel: 'Fødselsdato', doed: 'Dødsdato', koen: 'Køn',
};

const BLOKARSAG_TEKST: Record<string, string> = {
  ingen_importanker: 'Personen har ingen importanker og kan ikke rettes her.',
  flere_importankre: 'Personen har flere importankre — brug den almindelige editor.',
  import_key_mangler: 'Kildeforankringen mangler en import-nøgle — brug den almindelige editor.',
  record_key_mangler: 'Kildeforankringen mangler en post-nøgle — brug den almindelige editor.',
  ingen_kildebelagt_assertion: 'Feltet har ingen kildebelagt påstand at rette.',
  flere_importerede_facts: 'Feltet peger på flere kildebelagte påstande — brug den almindelige editor.',
};

function blokarsagTekst(kode: string | undefined): string {
  if (!kode) return 'Feltet kan ikke rettes her.';
  return BLOKARSAG_TEKST[kode] ?? kode;
}

// Kontraktfaktum 2's detektion: `error` her er allerede den danske, oversatte streng fra
// personKvalitetsark.ts's oversaetOcrFejl (OCR_FEJLTEKST.OCR_FINGERPRINT_STALE, verificeret
// i schema.sql/personKvalitetsark.ts). Matcher på den stabile del af den tekst, ikke en
// rå fejlkode — panelet ser aldrig OCR_FINGERPRINT_STALE selv, kun dens oversættelse.
const STALE_FEJL_RE = /kildeteksten er ændret/i;

function erStaleFingerprintFejl(error: string | null): boolean {
  return error !== null && STALE_FEJL_RE.test(error);
}

type ImporteretValue = { value?: string | null };
type ImporteretDato = {
  raw?: string | null; min?: string | null; max?: string | null;
  qualifier?: string | null; calendar?: string | null; certainty?: string | null;
};

function importeretVaerdi(row: PersonKvalitetsarkRow, felt: OcrFelt): string | null {
  const raw = row.importeret[felt] as ImporteretValue | ImporteretDato | undefined;
  if (!raw) return null;
  if (felt === 'foedsel' || felt === 'doed') return (raw as ImporteretDato).raw ?? null;
  return (raw as ImporteretValue).value ?? null;
}

function displayEllerStreg(v: string | null | undefined): string {
  return v ?? '—';
}

function formatTidspunkt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

const inputStyle: CSSProperties = {
  fontSize: 14, padding: '6px 9px', border: '1px solid rgba(34,31,26,.2)', borderRadius: 6,
  width: '100%', boxSizing: 'border-box', font: 'inherit',
};

const primaryButtonStyle = (disabled: boolean): CSSProperties => ({
  border: 0, borderRadius: 6, padding: '7px 14px', fontSize: 13.5, fontWeight: 600,
  cursor: disabled ? 'not-allowed' : 'pointer', background: disabled ? T.beige : T.bordeaux,
  color: disabled ? T.muted2 : T.paper,
});

const secondaryButtonStyle = (disabled: boolean): CSSProperties => ({
  border: '1px solid rgba(34,31,26,.2)', borderRadius: 6, padding: '7px 14px', fontSize: 13.5,
  cursor: disabled ? 'not-allowed' : 'pointer', background: T.paper,
  color: disabled ? T.muted2 : T.ink,
});

export function OcrKildepanel({
  row, felt, historik, historikLoading, busy, error, proevekoersel,
  onSave, onClose, onOpenPerson, onRefreshRow,
}: OcrKildepanelProps) {
  // Kontraktfaktum 2: en vellykket "Genindlæs kilderække" erstatter kun det, retry'et
  // bruger (fingerprint/importeret/ocr-kontekst) — aldrig brugerens allerede indtastede
  // rettelse. Nulstilles når selve valget (person+felt) skifter, dvs. en reel ny celle.
  const [refreshedRow, setRefreshedRow] = useState<PersonKvalitetsarkRow | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const activeRow = refreshedRow ?? row;

  // Kontraktfaktum 1: redigerbarhed kommer KUN fra RPC'en. Læses fra activeRow (row, eller —
  // efter en stale-fingerprint-genindlæsning — den friske række) og aldrig genudledt fra
  // importKey/sourceId client-side. Bruger activeRow (ikke kun `row`) så et kanRettes-skifte
  // en genindlæsning afslører (fx nu ambiguøs/nu entydig) respekteres uden ekstra kilde.
  const kanRettes = activeRow.kanRettes[felt];
  const isDato = felt === 'foedsel' || felt === 'doed';

  const [navnDraft, setNavnDraft] = useState('');
  const [koenDraft, setKoenDraft] = useState('');
  const [datoDraft, setDatoDraft] = useState('');
  const [bekraeftUfortolkelig, setBekraeftUfortolkelig] = useState(false);

  // Ny celle valgt (person eller felt ændret) → nulstil hele formularens lokale tilstand,
  // inkl. en evt. tidligere opfrisket række fra et forrige felts stale-retry.
  useEffect(() => {
    setNavnDraft(row.navn ?? '');
    setKoenDraft(row.koen ?? '');
    setDatoDraft((felt === 'foedsel' ? row.foedselRaw : felt === 'doed' ? row.doedRaw : null) ?? '');
    setBekraeftUfortolkelig(false);
    setRefreshedRow(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.personId, felt]);

  const datoInfo = useMemo(() => (isDato ? normaliserOcrDato(datoDraft) : null), [isDato, datoDraft]);

  const staleFejl = erStaleFingerprintFejl(error);

  async function handleGenindlaes() {
    setRefreshing(true);
    try {
      const fresh = await onRefreshRow(row.personId);
      setRefreshedRow(fresh);
    } catch {
      // Genindlæsningen fejlede — panelet forbliver på den række/det fingerprint det
      // allerede havde. Integrationen kan vise dette via en ny `error`-prop-værdi; her
      // undgås blot en uhåndteret Promise-rejection.
    } finally {
      setRefreshing(false);
    }
  }

  function korrigeretPayload(): Record<string, unknown> {
    if (felt === 'navn') return { value: navnDraft.trim() };
    if (felt === 'koen') return { value: koenDraft };
    const info = datoInfo!;
    return {
      raw: datoDraft.trim(),
      min: info.understood ? info.min : null,
      max: info.understood ? info.max : null,
      qualifier: info.understood ? info.qualifier : null,
      calendar: 'gregoriansk',
      certainty: info.understood ? info.certainty : null,
    };
  }

  function kanGemmeRettelse(): boolean {
    if (proevekoersel || busy || !kanRettes) return false;
    if (felt === 'navn') return navnDraft.trim() !== '';
    if (felt === 'koen') return koenDraft !== '';
    if (datoDraft.trim() === '') return false;
    return datoInfo!.understood || bekraeftUfortolkelig;
  }

  function kanGoedkendeEllerUdskyde(): boolean {
    return !proevekoersel && !busy && Boolean(kanRettes);
  }

  async function gem(status: 'rettet' | 'godkendt' | 'udskudt') {
    const inputFingerprint = activeRow.inputFingerprint[felt];
    // kanRettes=true garanterer (jf. schema.sql's field_state/kan_rettes) at import_key og
    // record_key er sat for denne række — se GRUNDLAG i opgavebeskrivelsen.
    try {
      await onSave({
        personId: activeRow.personId,
        importKey: activeRow.importKey as string,
        recordKey: activeRow.recordKey as string,
        felt,
        inputFingerprint: inputFingerprint as string,
        korrigeret: status === 'rettet' ? korrigeretPayload() : null,
        status,
      });
    } catch {
      // Fejlvisningen ejes af `error`-proppen (integrationen sætter den efter et afvist
      // kald) — panelet skal blot ikke lade afvisningen undslippe som en uhåndteret
      // Promise-rejection. Udkastet forbliver urørt, jf. §14 "fejl bevarer udkastet".
    }
  }

  const kilde = activeRow.sourceUdgave
    ? `${activeRow.sourceTitel ?? '—'} · ${activeRow.sourceUdgave}`
    : (activeRow.sourceTitel ?? '—');
  const side = activeRow.kildeSide[felt];
  const ocrContext = activeRow.ocrContext[felt];

  const historikUtilgaengelig = activeRow.importKey === null || activeRow.recordKey === null;

  return (
    <aside
      aria-label={`OCR-kildepanel — ${FELT_LABELS[felt]}`}
      style={{
        display: 'flex', flexDirection: 'column', gap: 14, padding: 16, width: 360,
        background: T.panel, borderLeft: '1px solid rgba(34,31,26,.14)', fontFamily: T.sans,
        color: T.ink, overflowY: 'auto',
      }}
    >
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h2 style={{ margin: 0, fontFamily: T.serif, fontSize: 20 }}>Ret {FELT_LABELS[felt]}</h2>
          <p style={{ margin: '2px 0 0', fontSize: 12.5, color: T.muted }}>{activeRow.navn}</p>
        </div>
        <button type="button" onClick={onClose} style={secondaryButtonStyle(false)}>
          Annuller
        </button>
      </header>

      {proevekoersel && (
        <p role="note" style={{ margin: 0, fontSize: 13, color: T.red, background: T.beige, borderRadius: 6, padding: '8px 10px' }}>
          Prøvekørsel er slået til. OCR-rettelser kan ikke prøvekøres — slå prøvekørsel fra for at rette dette felt.
        </p>
      )}

      {error && (
        <div role="alert" style={{ fontSize: 13, color: T.red }}>
          <p style={{ margin: 0 }}>{error}</p>
          {staleFejl && (
            <button
              type="button"
              onClick={handleGenindlaes}
              disabled={refreshing}
              style={{ ...secondaryButtonStyle(refreshing), marginTop: 6 }}
            >
              {refreshing ? 'Genindlæser…' : 'Genindlæs kilderække'}
            </button>
          )}
        </div>
      )}

      {!kanRettes && (
        <div>
          <p style={{ margin: 0, fontSize: 13.5, color: T.muted }}>
            {blokarsagTekst(activeRow.blokarsager[felt])}
          </p>
          <button
            type="button"
            onClick={() => onOpenPerson(activeRow.personId)}
            style={{ ...secondaryButtonStyle(false), marginTop: 8 }}
          >
            Åbn person
          </button>
        </div>
      )}

      {kanRettes && (
        <>
          <section>
            <p style={{ margin: '0 0 4px', fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '.06em', color: T.muted3 }}>
              Importeret værdi
            </p>
            <p style={{ margin: 0, fontSize: 14.5 }}>{displayEllerStreg(importeretVaerdi(activeRow, felt))}</p>
          </section>

          <section>
            <p style={{ margin: '0 0 4px', fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '.06em', color: T.muted3 }}>
              Ny værdi
            </p>
            {felt === 'navn' && (
              <input
                aria-label="Ny værdi"
                type="text"
                value={navnDraft}
                onChange={(e) => setNavnDraft(e.target.value)}
                style={inputStyle}
              />
            )}
            {felt === 'koen' && (
              <select aria-label="Nyt køn" value={koenDraft} onChange={(e) => setKoenDraft(e.target.value)} style={inputStyle}>
                <option value="">Vælg…</option>
                <option value="mand">Mand</option>
                <option value="kvinde">Kvinde</option>
                <option value="ukendt">Ukendt</option>
              </select>
            )}
            {isDato && (
              <>
                <input
                  aria-label="Ny rå dato"
                  type="text"
                  value={datoDraft}
                  onChange={(e) => { setDatoDraft(e.target.value); setBekraeftUfortolkelig(false); }}
                  style={inputStyle}
                />
                {datoDraft.trim() !== '' && datoInfo && (
                  datoInfo.understood ? (
                    <p style={{ margin: '6px 0 0', fontSize: 12.5, color: T.green }}>
                      Udledte grænser: {datoInfo.min ?? '?'} – {datoInfo.max ?? '?'}
                      {datoInfo.qualifier ? ` (${datoInfo.qualifier})` : ''}
                    </p>
                  ) : (
                    <div style={{ marginTop: 6 }}>
                      <p style={{ margin: 0, fontSize: 12.5, color: T.red }}>
                        Denne dato kan ikke fortolkes automatisk. Den gemmes som rå tekst uden udledte grænser.
                      </p>
                      <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, fontSize: 12.5 }}>
                        <input
                          type="checkbox"
                          checked={bekraeftUfortolkelig}
                          onChange={(e) => setBekraeftUfortolkelig(e.target.checked)}
                        />
                        Jeg bekræfter at datoen er ufortolkelig og skal gemmes uden udledte grænser
                      </label>
                    </div>
                  )
                )}
              </>
            )}
          </section>

          <section aria-label="OCR-kontekst">
            <h3 style={{ margin: '0 0 4px', fontSize: 14, fontFamily: T.serif }}>OCR-kontekst</h3>
            <p style={{ margin: 0, fontSize: 13.5, whiteSpace: 'pre-wrap' }}>
              {ocrContext ?? 'Ingen bevaret OCR-kontekst for dette felt.'}
            </p>
            <p style={{ margin: '4px 0 0', fontSize: 12, color: T.muted }}>
              Kilde: {kilde}{side ? ` · s. ${side}` : ''}
            </p>
            <p style={{ margin: '6px 0 0', fontSize: 11.5, color: T.muted2, fontStyle: 'italic' }}>
              Konteksten er fra OCR-udtrækket, ikke en gengivelse af den trykte side.
            </p>
          </section>

          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            <button
              type="button"
              onClick={() => gem('rettet')}
              disabled={!kanGemmeRettelse()}
              style={primaryButtonStyle(!kanGemmeRettelse())}
            >
              Gem OCR-rettelse
            </button>
            <button
              type="button"
              onClick={() => gem('godkendt')}
              disabled={!kanGoedkendeEllerUdskyde()}
              style={secondaryButtonStyle(!kanGoedkendeEllerUdskyde())}
            >
              Godkend som korrekt
            </button>
            <button
              type="button"
              onClick={() => gem('udskudt')}
              disabled={!kanGoedkendeEllerUdskyde()}
              style={secondaryButtonStyle(!kanGoedkendeEllerUdskyde())}
            >
              Udskyd
            </button>
          </div>
        </>
      )}

      <section aria-label="Korrektionshistorik">
        <h3 style={{ margin: '0 0 4px', fontSize: 14, fontFamily: T.serif }}>Historik</h3>
        {historikUtilgaengelig ? (
          <p style={{ margin: 0, fontSize: 12.5, color: T.muted }}>
            Historik er ikke tilgængelig for denne post (intet importanker).
          </p>
        ) : historikLoading ? (
          <p style={{ margin: 0, fontSize: 12.5, color: T.muted }}>Henter historik…</p>
        ) : historik.length === 0 ? (
          <p style={{ margin: 0, fontSize: 12.5, color: T.muted }}>Ingen rettelser endnu.</p>
        ) : (
          <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 6 }}>
            {historik.map((entry) => (
              <li key={entry.changeSetId} style={{ fontSize: 12.5 }}>
                <span>{entry.actorNavn ?? 'Ukendt aktør'}</span>{' · '}
                <time dateTime={entry.changedAt}>{formatTidspunkt(entry.changedAt)}</time>
                {entry.operation && <span style={{ color: T.muted2 }}> ({entry.operation})</span>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </aside>
  );
}
