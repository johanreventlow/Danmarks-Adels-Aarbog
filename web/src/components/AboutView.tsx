// ---- Om slægten ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { T } from '../theme';
import type { AboutSection } from '../data/public';
import { NarrativRenderer } from './NarrativRenderer';
import { Counter } from './primitives';

export function AboutView({ about, personCount, estateCount, onPick }: { about: AboutSection[] | null; personCount: number; estateCount: number | null; onPick: (id: string) => void }) {
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 680 }}>
      <div style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, lineHeight: 1.02 }}>Slægten Reventlow</div>
      <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.muted2, marginTop: 8 }}>Indledning til stamtavlen · Danmarks Adels Aarbog</div>
      <div style={{ display: 'flex', gap: 22, marginTop: 16 }}>
        <Counter n={personCount} label="personer" />
        {estateCount != null && <Counter n={estateCount} label="godser" />}
      </div>
      <div style={{ height: 1, background: 'rgba(34,31,26,.12)', margin: '20px 0' }} />
      {/* NarrativRenderer (Slice C4): samme blok-renderer som person-bio/gods-narrativ — understøtter
          nu ##-overskrifter/linjeskift/indlejrede billeder i selve prosaen, ikke kun rå pre-wrap-tekst. */}
      {!about ? <div style={{ color: T.muted3 }}>Henter…</div> : about.length ? about.map((s, i) => (
        <div key={i} style={{ marginBottom: 24 }}>
          {s.lineageNavn && <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, marginBottom: 8, color: T.bordeaux }}>{s.lineageNavn}</div>}
          <div style={{ fontFamily: T.serif, fontSize: 16, lineHeight: 1.6, color: '#3d382f' }}>
            <NarrativRenderer tekst={s.tekst} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} />
          </div>
        </div>
      )) : (
        <div style={{ border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 16, background: T.paper, fontSize: 13, lineHeight: 1.5, color: T.muted }}>
          Ingen slægts-narrativ registreret endnu. Indledningen indlæses fra stamtavlen (narrative · subjekt_type slaegt).
        </div>
      )}
    </div>
  );
}
