import { useState, type ReactNode } from 'react';
import type { RedMatchPerson } from '@daa/core';
import type { KandidatDetalje, Kilde, Oplysning, PersonNarrativ } from '../data/redaktionRead';

type FoldHint = { folder: boolean; grund: string | null };

export type KandidatSammenligningProps = {
  personA: RedMatchPerson;
  personB: RedMatchPerson;
  detaljeA: KandidatDetalje;
  detaljeB: KandidatDetalje;
  kildeA: string;
  kildeB: string;
  /** Retning ved bekræftelse (§5.4: eksisterende base = kanonisk, ny udgaves person = alias).
   *  Udelades (ingen rolle vist) når parret ikke er et samme_som-forhold, fx en ikke_samme_som-afvisning. */
  rolleA?: 'alias' | 'kanonisk';
  rolleB?: 'alias' | 'kanonisk';
  navnById: ReadonlyMap<string, string>;
  foldHint: FoldHint;
  foldAdvice?: string | null;
  linket?: boolean;
  busy?: boolean;
  onBekraeft: () => void;
  onAfvis: () => void;
};

type FeltStatus = 'enig' | 'afvigende' | 'neutral';

function normaliser(value: string): string {
  return value.trim().toLocaleLowerCase('da-DK').replace(/\s+/g, ' ');
}

function feltStatus(a: string, b: string): FeltStatus {
  const na = normaliser(a);
  const nb = normaliser(b);
  if (!na && !nb) return 'neutral';
  return na === nb ? 'enig' : 'afvigende';
}

function navnOgTitel(person: RedMatchPerson): string {
  const navn = person.fuldtNavn ?? person.navn;
  return person.titel ? `${navn} · ${person.titel}` : navn;
}

function bogReferencer(person: RedMatchPerson): string {
  return person.bogReferencer.map((ref) => {
    const bogNr = ref.linje && ref.nr != null
      ? `${ref.linje}-${ref.nr}`
      : ref.linje ?? (ref.nr != null ? `nr. ${ref.nr}` : '');
    return [bogNr, ref.grenNavn].filter(Boolean).join(', ');
  }).filter(Boolean).join(' · ');
}

function valgteOplysninger(detalje: KandidatDetalje, felt: 'foedt' | 'doed'): Oplysning[] {
  return (detalje.evidence.felter[felt] ?? []).flatMap((f) => {
    const valgte = f.oplysninger.filter((o) => o.erKonklusion);
    return valgte.length ? valgte : f.oplysninger.slice(0, 1);
  });
}

function kildeTekst(kilde: Kilde): string {
  const navn = kilde.sourceTitel ?? (kilde.sourceId != null ? `Kilde ${kilde.sourceId}` : 'Ukendt kilde');
  return [`Kilde: ${navn}`, kilde.side ? `s. ${kilde.side}` : ''].filter(Boolean).join(' · ');
}

function oplysningDatoTekst(oplysning: Oplysning): string {
  const raw = oplysning.dato?.raw?.trim();
  if (raw) return raw;
  const vaerdi = oplysning.vaerdi.trim();
  if (vaerdi) return vaerdi;
  const min = oplysning.dato?.min;
  const max = oplysning.dato?.max;
  if (min && max && min !== max) return `${min}–${max}`;
  return min ?? max ?? '';
}

function DatoEvidens({ label, oplysninger }: { label: string; oplysninger: Oplysning[] }) {
  if (!oplysninger.length) return <div><strong>{label}:</strong> —</div>;
  return (
    <div>
      <strong>{label}:</strong>{' '}
      {oplysninger.map((oplysning, index) => (
        <span key={oplysning.assertionId}>
          {index > 0 && '; '}{oplysningDatoTekst(oplysning) || '—'}
          {oplysning.kilder.map((kilde, kildeIndex) => (
            <small key={`${oplysning.assertionId}:${kildeIndex}`} style={{ display: 'block', color: '#6f675b', marginTop: '.15rem' }}>
              {kildeTekst(kilde)}{kilde.citatTekst ? ` — “${kilde.citatTekst}”` : ''}
            </small>
          ))}
        </span>
      ))}
    </div>
  );
}

function datoSammenligning(detalje: KandidatDetalje): string {
  return (['foedt', 'doed'] as const).flatMap((felt) =>
    valgteOplysninger(detalje, felt).map(oplysningDatoTekst),
  ).join(' · ');
}

function familieNavne(
  detalje: KandidatDetalje,
  art: 'foraeldre' | 'partnere' | 'boern',
  navnById: ReadonlyMap<string, string>,
): string {
  const resolve = (personId: string, fallback: string) => navnById.get(personId) ?? fallback;
  const entries = art === 'foraeldre'
    ? detalje.familie.somBarn.flatMap((f) => f.foraeldre.map((p) => resolve(p.personId, p.navn)))
    : art === 'partnere'
      ? detalje.familie.somPartner.flatMap((f) => f.partnere.map((p) => {
        const navn = resolve(p.personId, p.navn);
        return p.aar ? `${navn} (${p.aar})` : navn;
      }))
      : detalje.familie.somPartner.flatMap((f) => f.boern.map((p) => {
        const navn = resolve(p.personId, p.navn);
        return p.aar ? `${navn} (${p.aar})` : navn;
      }));
  return [...new Set(entries)].sort((a, b) => a.localeCompare(b, 'da')).join(' · ');
}

function relationTekst(detalje: KandidatDetalje): string {
  return detalje.relationer
    .filter((relation) => relation.art === 'hverv' || relation.art === 'gods')
    .map((relation) => [relation.navn, relation.rolle, relation.periode].filter(Boolean).join(' · '))
    .sort((a, b) => a.localeCompare(b, 'da'))
    .join('; ');
}

function narrativTekst(narrativer: PersonNarrativ[]): string {
  return narrativer.map((n) => n.tekst).filter(Boolean).join('\n\n');
}

function NarrativCelle({ narrativer, testId }: { narrativer: PersonNarrativ[]; testId: string }) {
  const [visHele, setVisHele] = useState(false);
  if (!narrativer.length) return <div data-testid={testId}>—</div>;
  return (
    <div data-testid={testId} style={{ maxHeight: visHele ? 420 : 220, overflowY: 'auto', whiteSpace: 'pre-wrap' }}>
      {narrativer.map((narrativ) => {
        const lang = narrativ.tekst.length > 400;
        const tekst = !visHele && lang ? `${narrativ.tekst.slice(0, 400)}…` : narrativ.tekst;
        const kilde = narrativ.udgave ?? narrativ.sourceTitel ?? (narrativ.sourceId != null ? `Kilde ${narrativ.sourceId}` : 'Ukendt kilde');
        return (
          <div key={narrativ.id} style={{ marginBottom: '.65rem' }}>
            <strong style={{ display: 'block', fontSize: '.82em' }}>
              {kilde}{narrativ.side ? ` · s. ${narrativ.side}` : ''}
            </strong>
            <span>{tekst || '—'}</span>
          </div>
        );
      })}
      {narrativer.some((n) => n.tekst.length > 400) && (
        <button type="button" onClick={() => setVisHele((value) => !value)} style={{ fontSize: '.82em' }}>
          {visHele ? 'Vis uddrag' : 'Vis hele'}
        </button>
      )}
    </div>
  );
}

function SammenligningsRaekke({
  felt, label, aTekst, bTekst, aIndhold, bIndhold,
}: {
  felt: string; label: string; aTekst: string; bTekst: string; aIndhold?: ReactNode; bIndhold?: ReactNode;
}) {
  const status = feltStatus(aTekst, bTekst);
  const cellStyle = status === 'enig'
    ? { background: '#eef8ee', borderLeft: '3px solid #3d7a3d' }
    : status === 'afvigende'
      ? { background: '#fff7e6', borderLeft: '3px solid #9a4b19' }
      : { background: '#f7f5f1', borderLeft: '3px solid transparent' };
  return (
    <tr data-testid={`felt-${felt}`} data-status={status}>
      <th scope="row" style={{ textAlign: 'left', verticalAlign: 'top', padding: '.55rem', width: '18%' }}>{label}</th>
      <td style={{ ...cellStyle, verticalAlign: 'top', padding: '.55rem', overflowWrap: 'anywhere' }}>{aIndhold ?? (aTekst || '—')}</td>
      <td style={{ ...cellStyle, verticalAlign: 'top', padding: '.55rem', overflowWrap: 'anywhere' }}>{bIndhold ?? (bTekst || '—')}</td>
    </tr>
  );
}

function RolleBadge({ rolle }: { rolle?: 'alias' | 'kanonisk' }) {
  if (!rolle) return null;
  const tekst = rolle === 'kanonisk' ? '→ forbliver synlig (main)' : '→ foldes ind (alias)';
  return (
    <span style={{
      display: 'block', fontSize: '.72em', fontWeight: 600, marginTop: '.1rem',
      color: rolle === 'kanonisk' ? '#2f632f' : '#6f675b',
    }}>
      {tekst}
    </span>
  );
}

export function KandidatSammenligning({
  personA, personB, detaljeA, detaljeB, kildeA, kildeB, rolleA, rolleB, navnById,
  foldHint, foldAdvice, linket = false, busy = false, onBekraeft, onAfvis,
}: KandidatSammenligningProps) {
  const foraeldreA = familieNavne(detaljeA, 'foraeldre', navnById);
  const foraeldreB = familieNavne(detaljeB, 'foraeldre', navnById);
  const partnereA = familieNavne(detaljeA, 'partnere', navnById);
  const partnereB = familieNavne(detaljeB, 'partnere', navnById);
  const boernA = familieNavne(detaljeA, 'boern', navnById);
  const boernB = familieNavne(detaljeB, 'boern', navnById);
  const relationerA = relationTekst(detaljeA);
  const relationerB = relationTekst(detaljeB);
  const narrativerA = narrativTekst(detaljeA.narrativer);
  const narrativerB = narrativTekst(detaljeB.narrativer);

  return (
    <section style={{ marginTop: '.55rem', border: '1px solid rgba(34,31,26,.16)', borderRadius: 6, padding: '.7rem', overflowX: 'auto' }}>
      <div role="alert" style={{
        padding: '.55rem .7rem', marginBottom: '.65rem', borderRadius: 4,
        color: foldHint.folder ? '#2f632f' : '#881A33',
        background: foldHint.folder ? '#eef8ee' : '#fdf3f5',
        border: `1px solid ${foldHint.folder ? 'rgba(61,122,61,.35)' : 'rgba(136,26,51,.35)'}`,
      }}>
        <strong>{foldHint.folder ? '✓ Linket kan folde offentligt' : '⚠ Linket vil ikke folde offentligt endnu'}</strong>
        {foldHint.grund && <div>{foldHint.grund}</div>}
        {!foldHint.folder && foldAdvice && <div style={{ color: '#6f675b', marginTop: '.15rem' }}>{foldAdvice}</div>}
      </div>

      <table style={{ width: '100%', minWidth: 680, borderCollapse: 'separate', borderSpacing: '0 .25rem', tableLayout: 'fixed' }}>
        <thead>
          <tr>
            <th aria-label="Felt" style={{ width: '18%' }} />
            <th scope="col" style={{ textAlign: 'left', padding: '.4rem .55rem' }}>
              Kilde A · {kildeA}
              <RolleBadge rolle={rolleA} />
            </th>
            <th scope="col" style={{ textAlign: 'left', padding: '.4rem .55rem' }}>
              Kilde B · {kildeB}
              <RolleBadge rolle={rolleB} />
            </th>
          </tr>
        </thead>
        <tbody>
          <SammenligningsRaekke felt="navn" label="Navn + titel" aTekst={navnOgTitel(personA)} bTekst={navnOgTitel(personB)} />
          <SammenligningsRaekke
            felt="foedsel-doed" label="Fødsel / død"
            aTekst={datoSammenligning(detaljeA)} bTekst={datoSammenligning(detaljeB)}
            aIndhold={<><DatoEvidens label="Født" oplysninger={valgteOplysninger(detaljeA, 'foedt')} /><DatoEvidens label="Død" oplysninger={valgteOplysninger(detaljeA, 'doed')} /></>}
            bIndhold={<><DatoEvidens label="Født" oplysninger={valgteOplysninger(detaljeB, 'foedt')} /><DatoEvidens label="Død" oplysninger={valgteOplysninger(detaljeB, 'doed')} /></>}
          />
          <SammenligningsRaekke felt="foraeldre" label="Forældre" aTekst={foraeldreA} bTekst={foraeldreB} />
          <SammenligningsRaekke felt="aegteskaber" label="Ægtefælle(r)" aTekst={partnereA} bTekst={partnereB} />
          <SammenligningsRaekke felt="boern" label="Børn" aTekst={boernA} bTekst={boernB} />
          <SammenligningsRaekke felt="bog" label="Linje / gren + bog-nr" aTekst={bogReferencer(personA)} bTekst={bogReferencer(personB)} />
          <SammenligningsRaekke felt="relationer" label="Embeder / godser" aTekst={relationerA} bTekst={relationerB} />
          <SammenligningsRaekke
            felt="narrativ" label="Narrativ" aTekst={narrativerA} bTekst={narrativerB}
            aIndhold={<NarrativCelle narrativer={detaljeA.narrativer} testId="narrativ-a" />}
            bIndhold={<NarrativCelle narrativer={detaljeB.narrativer} testId="narrativ-b" />}
          />
        </tbody>
      </table>

      <div style={{ marginTop: '.65rem' }}>
        <button type="button" disabled={busy || linket} onClick={onBekraeft}>
          {linket ? '✓ bekræftet' : 'Bekræft samme person'}
        </button>{' '}
        <button type="button" disabled={busy} onClick={onAfvis}>Afvis</button>
      </div>
    </section>
  );
}
