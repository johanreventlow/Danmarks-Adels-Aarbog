// Forsiden / landing (brief §6). Logoet fører hertil; fordi detaljen nu er skjult indtil
// valg, er forsiden appens reelle indgang. Form: prominent søge-hero + redaktionelt
// kuraterede startpersoner (så en førstegangsbruger har et meningsfuldt sted at begynde) +
// et roligt "Nyt i arkivet". Port af Reventlow-web-v4.dc.html's isHome-blok, drevet af ægte
// data. Ingen fabrikerede opdaterings-datoer (der findes ingen timestamp-metadata; brief §8.4).
import { useMemo } from 'react';
import { T } from '../theme';
import { PersonCard, SearchIcon, Crest } from './primitives';
import { curatedFounders, pickMaanedensGods } from '../data/home';
import type { Model } from '../data/types';
import type { EstateItem } from '../data/public';

// Kort i "Nyt i arkivet"-kolonnen — samme skabelon, kun tekst/handling varierer.
function NytCard({ kicker, title, sub, onClick }: { kicker: string; title: string; sub: string; onClick?: () => void }) {
  return (
    <div onClick={onClick} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 13, padding: '15px 16px', cursor: onClick ? 'pointer' : 'default' }}>
      <div style={{ fontFamily: T.mono, fontSize: 8.5, letterSpacing: '.1em', textTransform: 'uppercase', color: T.gold }}>{kicker}</div>
      <div style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.ink, marginTop: 4, lineHeight: 1.1 }}>{title}</div>
      <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, marginTop: 4 }}>{sub}</div>
    </div>
  );
}

export function HomeView({ model, personCount, estates, onPickPerson, onOpenSearch, onBrowseAll, onOpenEstate, onGoTree }: {
  model: Model | null;
  personCount: number;
  estates: EstateItem[] | null;
  onPickPerson: (id: string) => void;
  onOpenSearch: () => void;
  onBrowseAll: () => void;
  onOpenEstate: (id: string) => void;
  onGoTree: () => void;
}) {
  const curated = useMemo(() => (model ? curatedFounders(model, 4) : []), [model]);
  const gods = useMemo(() => pickMaanedensGods(estates), [estates]);
  if (!model) return <div style={{ padding: 40, fontFamily: T.sans, color: T.muted3 }}>Henter slægten…</div>;

  return (
    <div style={{ padding: '34px 44px 54px', maxWidth: 1140 }}>
      {/* Hero — søgning som primær indgang (brief §6). */}
      <div style={{ background: T.ink, borderRadius: 18, padding: '36px 40px', position: 'relative', overflow: 'hidden' }}>
        <Crest stroke={T.goldLight} inner={T.gold} opacity={0.16} size={158} style={{ position: 'absolute', top: -12, right: 30 }} />
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.2em', textTransform: 'uppercase', color: T.goldLight }}>Slægten Reventlow · {personCount} personer</div>
        <div style={{ fontFamily: T.serif, fontSize: 40, fontWeight: 600, color: T.panel, lineHeight: 1.03, marginTop: 9, maxWidth: 560 }}>Find din vej ind i slægten</div>
        <div onClick={onOpenSearch} style={{ marginTop: 22, maxWidth: 640, display: 'flex', alignItems: 'center', gap: 11, background: T.paper, borderRadius: 12, padding: '14px 17px', cursor: 'text' }}>
          <SearchIcon size={20} />
          <span style={{ fontFamily: T.sans, fontSize: 15.5, color: T.muted3 }}>Find en person i slægten…</span>
        </div>
      </div>

      {/* Redaktionen foreslår — kuraterede startpersoner (brief §6). */}
      <div style={{ marginTop: 32, display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.16em', textTransform: 'uppercase', color: T.gold }}>Redaktionen foreslår · begynd her</div>
        <span onClick={onBrowseAll} style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>Se alle {personCount} →</span>
      </div>
      <div style={{ display: 'flex', gap: 13, marginTop: 13, flexWrap: 'wrap' }}>
        {curated.map((p) => (
          <div key={p.id} style={{ flex: 1, minWidth: 210 }}>
            <PersonCard p={p} width="100%" onClick={() => onPickPerson(p.id)} />
          </div>
        ))}
      </div>

      {/* Nyt i arkivet — månedens gods (ægte data) + rolige indgange. */}
      <div style={{ marginTop: 34, fontFamily: T.mono, fontSize: 10, letterSpacing: '.16em', textTransform: 'uppercase', color: T.gold }}>Nyt i arkivet</div>
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 16, marginTop: 13 }}>
        <div onClick={gods ? () => onOpenEstate(gods.id) : undefined} style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 15, overflow: 'hidden', cursor: gods ? 'pointer' : 'default' }}>
          <div style={{ height: 160, background: 'repeating-linear-gradient(45deg,#ece4d6 0 12px,#e2d8c8 12px 24px)', borderBottom: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'flex-end', padding: 14 }}>
            <span style={{ fontFamily: T.mono, fontSize: 10, color: T.muted }}>{gods ? `gods · ${gods.navn}` : 'gods'}</span>
          </div>
          <div style={{ padding: '17px 19px' }}>
            <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.12em', textTransform: 'uppercase', color: T.gold }}>Månedens gods</div>
            <div style={{ fontFamily: T.serif, fontSize: 24, fontWeight: 600, color: T.ink, marginTop: 5, lineHeight: 1.08 }}>{gods ? gods.navn : 'Følg ejerrækken gennem slægten'}</div>
            <div style={{ fontFamily: T.sans, fontSize: 13, lineHeight: 1.5, color: T.muted, marginTop: 7 }}>Følg ejerrækken gennem slægten — slægtled for slægtled, fra de tidligste besiddelser til lensafløsningen.</div>
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 13 }}>
          <NytCard kicker="Udforsk" title="Åbn stamtræet" sub="Fokus- og kolonne-visning af hele slægten" onClick={onGoTree} />
          <NytCard kicker="Gennemse" title={`Alle ${personCount} personer`} sub="Søg, sortér og hop gennem alfabetet" onClick={onBrowseAll} />
        </div>
      </div>
    </div>
  );
}
