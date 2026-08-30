import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Change } from '../data/redaktionWrite';
import {
  fetchPersonNarrativeRecords,
  type LegacyNarrativePublication,
  type PersonNarrativeRecord,
  type PersonNarrativeRecordRead,
} from '../data/redaktionRead';

type Props = {
  personId: number;
  onChange: (change: Change, title: string) => Promise<boolean>;
};

type Conflict = {
  localText: string;
  serverText: string;
};

const statusLabel: Record<PersonNarrativeRecord['status'], string> = {
  none: 'Intet narrativ',
  draft: 'Kladde',
  published: 'Publiceret',
  stale_published: 'Publicering kræver genvalidering',
  withdrawn: 'Tilbagetrukket',
  blocked: 'Blokeret',
};

function recordId(record: PersonNarrativeRecord): string {
  return `${record.sourceId}:${record.recordKey}`;
}

function pageOrder(record: PersonNarrativeRecord): number {
  const match = record.citationLabel.match(/\bs\.\s*(\d+)/i);
  return match ? Number(match[1]) : Number.POSITIVE_INFINITY;
}

function sortRecords(records: readonly PersonNarrativeRecord[]): PersonNarrativeRecord[] {
  return [...records].sort((a, b) => {
    const aYear = a.sourceYear ?? Number.NEGATIVE_INFINITY;
    const bYear = b.sourceYear ?? Number.NEGATIVE_INFINITY;
    if (aYear !== bYear) return bYear - aYear;
    if (a.sourceId !== b.sourceId) return a.sourceId - b.sourceId;
    const aPage = pageOrder(a);
    const bPage = pageOrder(b);
    if (aPage !== bPage) return aPage - bPage;
    return a.recordKey.localeCompare(b.recordKey, 'da');
  });
}

function changeForRecord(
  personId: number,
  record: PersonNarrativeRecord,
  action: string,
  text?: string,
): Change {
  return {
    art: 'narrativRecord',
    subjektType: 'person',
    subjektId: String(personId),
    payload: {
      action,
      sourceId: record.sourceId,
      recordKey: record.recordKey,
      expectedStateSha256: record.stateSha256,
      ...(text === undefined ? {} : { tekst: text, privat: false }),
    },
  };
}

export function PersonNarrativeRecordEditor({ personId, onChange }: Props) {
  const [read, setRead] = useState<PersonNarrativeRecordRead | null>(null);
  const [readPersonId, setReadPersonId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [texts, setTexts] = useState<Record<string, string>>({});
  const [conflict, setConflict] = useState<Conflict | null>(null);
  const [legacyWithdrawal, setLegacyWithdrawal] = useState<LegacyNarrativePublication | null>(null);
  const [legacyReason, setLegacyReason] = useState('');
  const [legacyConfirmed, setLegacyConfirmed] = useState(false);
  const currentPersonId = useRef(personId);
  currentPersonId.current = personId;

  const load = useCallback(async () => {
    if (currentPersonId.current === personId) setError(null);
    const next = await fetchPersonNarrativeRecords(personId);
    if (currentPersonId.current === personId) {
      setRead(next);
      setReadPersonId(personId);
    }
    return next;
  }, [personId]);

  useEffect(() => {
    let current = true;
    setRead(null);
    setReadPersonId(null);
    setBusy(null);
    setTexts({});
    setConflict(null);
    setLegacyWithdrawal(null);
    setLegacyReason('');
    setLegacyConfirmed(false);
    load().catch((e) => {
      if (current) setError(String((e as Error)?.message ?? e));
    });
    return () => { current = false; };
  }, [load]);

  const records = useMemo(() => sortRecords(read?.records ?? []), [read]);

  const submitRecord = useCallback(async (
    record: PersonNarrativeRecord,
    action: string,
    title: string,
    text?: string,
  ) => {
    const id = recordId(record);
    setBusy(id);
    setError(null);
    try {
      const committed = await onChange(changeForRecord(personId, record, action, text), title);
      if (currentPersonId.current !== personId) return;
      if (!committed) return;
      setTexts((current) => {
        const { [id]: _discarded, ...rest } = current;
        return rest;
      });
      setConflict(null);
      await load();
    } catch (e) {
      if (currentPersonId.current !== personId) return;
      const message = String((e as Error)?.message ?? e);
      if (message.includes('NARRATIVE_RECORD_STATE_STALE')) {
        const localText = text ?? texts[id] ?? record.text;
        try {
          const latest = await fetchPersonNarrativeRecords(personId);
          if (currentPersonId.current === personId) {
            setRead(latest);
            setReadPersonId(personId);
          }
          if (currentPersonId.current === personId) {
            const latestRecord = latest.records.find((candidate) => candidate.sourceId === record.sourceId && candidate.recordKey === record.recordKey);
            setConflict({ localText, serverText: latestRecord?.text ?? '' });
          }
        } catch (reloadError) {
          if (currentPersonId.current === personId) setError(String((reloadError as Error)?.message ?? reloadError));
        }
      } else {
        setError(message);
      }
    } finally {
      if (currentPersonId.current === personId) setBusy(null);
    }
  }, [load, onChange, personId, texts]);

  const openLegacyWithdrawal = (legacy: LegacyNarrativePublication) => {
    setLegacyWithdrawal(legacy);
    setLegacyReason('');
    setLegacyConfirmed(false);
  };

  const submitLegacyWithdrawal = async () => {
    if (!legacyWithdrawal || !legacyReason.trim() || !legacyConfirmed) return;
    setBusy(legacyWithdrawal.legacyPublicationRef);
    setError(null);
    try {
      const committed = await onChange({
        art: 'narrativRecord',
        subjektType: 'person',
        subjektId: String(personId),
        payload: {
          action: 'withdraw_legacy',
          legacyPublicationRef: legacyWithdrawal.legacyPublicationRef,
          expectedStateSha256: legacyWithdrawal.stateSha256,
          begrundelse: legacyReason.trim(),
        },
      }, 'Tag biografi ned');
      if (currentPersonId.current !== personId) return;
      if (!committed) return;
      setLegacyWithdrawal(null);
      await load();
    } catch (e) {
      if (currentPersonId.current === personId) setError(String((e as Error)?.message ?? e));
    } finally {
      if (currentPersonId.current === personId) setBusy(null);
    }
  };

  const copyLocalText = () => {
    if (conflict) void navigator.clipboard?.writeText?.(conflict.localText);
  };

  if (error) return <div role="alert">{error}</div>;
  if (!read || readPersonId !== personId) return <div>Henter kildenarrativer…</div>;

  return (
    <section aria-label="Kildenarrativer">
      <h2>Narrativ · biografi</h2>
      {records.map((record) => {
        const id = recordId(record);
        const text = texts[id] ?? record.text;
        const editable = record.allowedActions.some((action) =>
          action === 'create_draft' || action === 'save_draft' || action === 'publish_revision',
        );
        const isBusy = busy === id;
        return (
          <article key={id} aria-label={`${record.sourceLabel} — ${record.recordLabel}`}>
            <h3>{record.recordLabel}</h3>
            <div>{record.sourceLabel}</div>
            <div>{record.citationLabel}</div>
            <div>{statusLabel[record.status]}</div>
            {record.blockingReason ? <div role="status">{record.blockingReason}</div> : null}
            {editable ? (
              <textarea
                aria-label={`Tekst for ${record.recordLabel}`}
                value={text}
                onChange={(event) => setTexts((current) => ({ ...current, [id]: event.target.value }))}
              />
            ) : record.text ? <p>{record.text}</p> : null}
            {record.status === 'published' && record.allowedActions.includes('publish_revision') && text !== record.text ? <section aria-label="Publiceringskonsekvens">
              <div>Før publicering</div>
              <pre>{record.text}</pre>
              <div>Efter publicering</div>
              <pre>{text}</pre>
            </section> : null}
            <div>
              {record.allowedActions.includes('create_draft') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'create_draft', 'Opret kladde', text)}>Opret kladde</button> : null}
              {record.allowedActions.includes('save_draft') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'save_draft', 'Gem kladde', text)}>Gem kladde</button> : null}
              {record.allowedActions.includes('discard_draft') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'discard_draft', 'Kassér kladde')}>Kassér kladde</button> : null}
              {record.allowedActions.includes('publish') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'publish', 'Publicér')}>Publicér</button> : null}
              {record.allowedActions.includes('publish_revision') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'publish_revision', 'Publicér ændring', text)}>Publicér ændring</button> : null}
              {record.allowedActions.includes('revalidate') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'revalidate', 'Genvalidér publicering')}>Genvalidér publicering</button> : null}
              {record.allowedActions.includes('withdraw') ? <button type="button" disabled={isBusy} onClick={() => submitRecord(record, 'withdraw', 'Træk publicering tilbage')}>Træk publicering tilbage</button> : null}
            </div>
          </article>
        );
      })}

      {read.legacyPublications.length ? <section aria-label="Overgangsdata">
        <h3>Overgangsdata — kildepost ikke fastlagt</h3>
        {read.legacyPublications.map((legacy) => (
          <article key={legacy.legacyPublicationRef} aria-label="Overgangsbiografi">
            <p>{legacy.text}</p>
            <div>{legacy.status === 'legacy_active' ? 'Aktiv overgangsbiografi' : 'Tilbagetrukket overgangsbiografi'}</div>
            {legacy.blockingReason ? <div role="status">{legacy.blockingReason}</div> : null}
            {legacy.allowedActions.includes('withdraw_legacy') ? <button type="button" disabled={busy === legacy.legacyPublicationRef} onClick={() => openLegacyWithdrawal(legacy)}>Tag biografi ned</button> : null}
          </article>
        ))}
      </section> : null}

      {legacyWithdrawal ? <section aria-label="Bekræft nedtagning">
        <p>Dette tager kun den valgte overgangsbiografi ned. Andre biografier for personen ændres ikke.</p>
        <p>Valgt biografi: {legacyWithdrawal.text}</p>
        <label>
          Begrundelse for nedtagning
          <textarea aria-label="Begrundelse for nedtagning" value={legacyReason} onChange={(event) => setLegacyReason(event.target.value)} />
        </label>
        <label>
          <input type="checkbox" checked={legacyConfirmed} onChange={(event) => setLegacyConfirmed(event.target.checked)} />
          Jeg bekræfter nedtagning af netop denne overgangsbiografi
        </label>
        <button type="button" disabled={!legacyReason.trim() || !legacyConfirmed || busy === legacyWithdrawal.legacyPublicationRef} onClick={submitLegacyWithdrawal}>Bekræft nedtagning</button>
      </section> : null}

      {conflict ? <section role="alert" aria-label="Stale konflikt">
        <h3>Tilstanden er ændret på serveren</h3>
        <div>Din lokale tekst</div>
        <pre>{conflict.localText}</pre>
        <div>Seneste servertekst</div>
        <pre>{conflict.serverText}</pre>
        <button type="button" onClick={copyLocalText}>Kopiér lokal tekst</button>
        <button type="button" onClick={() => { setConflict(null); void load().catch((e) => setError(String((e as Error)?.message ?? e))); }}>Genindlæs</button>
      </section> : null}
    </section>
  );
}
