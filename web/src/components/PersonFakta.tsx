// B11 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.4): personens fakta med kilde. Tre kildevisninger, der kan
// skelnes: bundet til bogens post (trin 4-binding), fra den oprindelige import (citation) og ingen registreret kilde.
import type { PersonFactSource, PersonFactStatement, PersonFactView } from '@daa/core';
import { T } from '../theme';
import { Label } from './primitives';

const NAVN: Record<string, string> = {
  navn: 'Navn', tilnavn: 'Tilnavn', fødsel: 'Født', dåb: 'Døbt', titel: 'Titel', dekoration: 'Dekoration',
  adling: 'Adlet', floruit: 'Nævnt', klosterindgang: 'Klosterindgang', overhoved: 'Overhoved', død: 'Død',
  dødsårsag: 'Dødsårsag', begravelse: 'Begravet',
};
const typeNavn = (t: string) => NAVN[t] ?? t.charAt(0).toUpperCase() + t.slice(1);

const MAERKE: Record<PersonFactSource['kind'], string | null> = {
  bundet: 'bundet til bogens post',
  import: 'fra den oprindelige import',
  ingen: null,
};

function Kilde({ source }: { source: PersonFactSource }) {
  const maerke = MAERKE[source.kind];
  return (
    <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 2, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
      {maerke && (
        <span style={{ color: source.kind === 'bundet' ? T.bordeaux : T.muted3 }}>{maerke}</span>
      )}
      <span>{source.label}</span>
    </div>
  );
}

function Udsagn({ st }: { st: PersonFactStatement }) {
  return (
    <div>
      <div style={{ fontSize: 14, color: '#3d382f', lineHeight: 1.3 }}>{st.value}</div>
      <Kilde source={st.source} />
    </div>
  );
}

export function PersonFakta({ facts, error }: { facts: PersonFactView[]; error: boolean }) {
  if (error) {
    return (
      <>
        <Label>Fakta</Label>
        <div style={{ fontSize: 13, color: T.muted3 }}>Fakta kunne ikke hentes</div>
      </>
    );
  }
  if (!facts.length) return null;
  return (
    <>
      <Label>Fakta</Label>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        {facts.map((f) => (
          <div key={f.factId} style={{ display: 'flex', gap: 12, padding: '8px 0', borderBottom: '1px solid rgba(34,31,26,.07)' }}>
            <span style={{ flex: 'none', width: 104, fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.06em', textTransform: 'uppercase', color: T.muted3, paddingTop: 2 }}>
              {typeNavn(f.faktatype)}
            </span>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
              {f.omstridt && (
                <span style={{ alignSelf: 'flex-start', fontFamily: T.mono, fontSize: 10, color: T.bordeaux, border: `1px solid ${T.bordeaux}`, borderRadius: 4, padding: '0 5px' }}>omstridt</span>
              )}
              {f.chosen && <Udsagn st={f.chosen} />}
              {f.others.length > 0 && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <span style={{ fontFamily: T.mono, fontSize: 10, color: T.muted3 }}>Andre udsagn</span>
                  {f.others.map((o, i) => <Udsagn key={`${o.assertionId}:${i}`} st={o} />)}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </>
  );
}
