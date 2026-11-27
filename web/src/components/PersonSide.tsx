// Personsiden /person/<id> (webredesign fase 3, tegningen »Personside · for alle (valgt)«): en egen side over
// slægterne. Bogark med etiket, navn, livsdatoer og titel, udgavevælger (visning C fra 6e), oplysninger med
// kilde, biografi ordret, familie, embeder, godser, billeder og »Kilde i Aarbogen«; højre spalte med portræt,
// slægten og handlingerne.
//
// Fra stamtræets panel (fase 5b, projektejeren 12/11): livsrejsen (minikort, kun når personen har steder),
// »Det er mig« (lokalt i browseren, intet login) og »Vis i præsensliste« (kun redaktionen).
//
// Medlemslaget (fase 8, tegningen »… lag for indloggede medlemmer«) får faste pladser i samme layout:
// slægtskab som kontekst over navnet (SlaegtskabsLinje, beregnet ud fra »Det er mig« og ikke ud fra login),
// bogmærket i højre spalte og fakta med kilde pr. linje (PersonFakta står på fakta-pladsen). Siden skifter ikke
// layout ved login.
//
// Mangler siges med ord. »i den valgte udgave« bruges kun, hvor vælgeren faktisk filtrerer (biografi, fakta,
// godser); familie og embeder kommer fra den samlede model.
import { Suspense, useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath, estatePath, slaegtPath, stamtraePath, slaegtskabPath, findSlaegt, STANDARD_SLAEGT } from '../data/nav';
import { konfTekst } from '../data/format';
import { kunIAeldreTekst, type KunIAeldreTekst } from '../data/kunIAeldre';
import { mediaCaption, portraetTilpasning, type MediaItem } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { bogensNummer, byggStatuslinje, familieIderForPerson, fmtSkilt, lifeJourney, parSkilsmisse, vielsePraecision, type UdgaveChip } from '@daa/core';
import { hentVielsesDatoer } from '../data/vielser';
import { NarrativRenderer } from './NarrativRenderer';
import { PersonFakta } from './PersonFakta';
import { SlaegtskabsLinje } from './SlaegtskabsLinje';
import { slaegtskabsKontekst } from '../data/slaegtskab';
import { byggFokusRaekker } from '../data/fokusTrae';
import { Lightbox } from './Lightbox';
import { Tilstand, tilstandSekundaer } from './Tilstand';
import { usePersonVisning } from './personVisning';
import { SlaegtsMaerke } from './SlaegtsMaerke';
import { ExpandableMiniMap, MapFallback } from './lazyMaps';
import { radius, shadow } from '@daa/theme';
import { useSmalSkaerm } from '../useSmalSkaerm';
import { delLink, type DelUdfald } from '../data/delLink';
import { SignedImg } from './SignedImg';

const FOERSTE_EMBEDER = 7;
const FOERSTE_GODSER = 6;

export function PersonSide({ model, focusId, detail, detailError, onRetry, onVisPerson, onFindSlaegtskab, onSlaegt,
  loggetInd, onLogin, erBogmaerket, onToggleBogmaerke, geoLoading = false, erMig = false, onToggleMig, onVisPraesens, meId = null }: {
  model: Model; focusId: string; detail: PersonDetailData | null; detailError: string | null; onRetry: () => void;
  onVisPerson: (id: string) => void; // familie og biografiens personlinks (→ /person/<id>)
  onFindSlaegtskab: () => void;
  onSlaegt: (slug: string) => void;
  loggetInd: boolean; onLogin: () => void; erBogmaerket: boolean; onToggleBogmaerke: () => void;
  geoLoading?: boolean; // geo hentes dovent; minikortet vises først, når hentningen er færdig (intet flimmer)
  erMig?: boolean; onToggleMig?: () => void;
  onVisPraesens?: () => void; // kun redaktionen (præsenslisten kræver i dag rollen)
  meId?: string | null; // »Det er mig« (kanonisk); null → ingen slægtskabslinje over navnet
}) {
  const v = usePersonVisning(model, focusId, detail);
  const [visAlleEmbeder, setVisAlleEmbeder] = useState(false);
  const [visAlleGodser, setVisAlleGodser] = useState(false);
  const [lightbox, setLightbox] = useState<number | null>(null);
  const [kopieret, setKopieret] = useState<DelUdfald | null>(null);
  const smal = useSmalSkaerm(); // telefonen: »Del« med telefonens delemenu (fase 9)
  const livsrejse = useMemo(() => (!geoLoading && model.geo ? lifeJourney(model.geo, focusId) : []), [geoLoading, model.geo, focusId]);
  // Før det tidlige return: hooks skal kaldes i samme rækkefølge ved hver render.
  const kontekst = useMemo(() => slaegtskabsKontekst(model, meId, focusId), [model, meId, focusId]);
  // Børn pr. ægteskab i Aarbogens rækkefølge: samme gruppering som stamtræet (fokusTrae), så de to aldrig er uenige.
  const fam = useMemo(() => byggFokusRaekker(model, focusId), [model, focusId]);
  // Vielsesdato pr. ægteskab (»⚭ 21. juli 1667«), nøglet på ægtefællens person-id. Hentes for sig, så siden ikke
  // venter på den; mangler den (ingen vielse, fejl), står der bare ingen ⚭.
  const aegteskaber = useMemo(() => familieIderForPerson(model.indexes, focusId).aegteskaber, [model, focusId]);
  const familieNoegle = aegteskaber.map((a) => a.familyId).sort().join(',');
  const [vielseBySpouse, setVielseBySpouse] = useState<Record<string, string>>({});
  useEffect(() => {
    let aktuel = true;
    setVielseBySpouse({});
    if (!familieNoegle) return;
    void hentVielsesDatoer(familieNoegle.split(',')).then((byFam) => {
      if (!aktuel) return;
      const ud: Record<string, string> = {};
      // Står parret i flere familier (sammenfoldet på tværs af udgaver), vinder den mest præcise dato.
      for (const a of aegteskaber) {
        const t = byFam[a.familyId];
        if (a.spouseId && t && vielsePraecision(t) > vielsePraecision(ud[a.spouseId] ?? '')) ud[a.spouseId] = t;
      }
      setVielseBySpouse(ud);
    });
    return () => { aktuel = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- familieNoegle bærer aegteskaber's familie-id'er
  }, [familieNoegle]);
  // Statuslinjen under årene (spec 2026-11-27): ét sted for titel, adelsnavn og ægteskabstitel. Hof-/rangtitler kommer
  // fra titel-fakta og embedsroller, så de er først med, når detaljerne er hentet (null før). Folgesvend
  // giver kun detaljen videre, når den er hentet for netop focusId. Før det tidlige return (hooks i fast rækkefølge).
  const hofKilder = useMemo(() => detail
    ? [
        ...(detail.faktaInput?.rows ?? []).filter((r) => r.faktatype === 'titel' && r.chosen && r.conclusion_status === 'afklaret').map((r) => r.vaerdi_tekst),
        ...detail.offices.map((o) => o.rolle),
      ].filter((x): x is string => !!x)
    : null, [detail]);
  const p = v.p;
  if (!p) return null;
  const kunI = kunIAeldreTekst(model, focusId);
  // Et barn, der kun står i en anden udgave, er et link, når den udgave er valgt i udgavevælgeren (projektejeren
  // 2026-11-23, valg A); ellers grå tekst med mærket. Kan siden slet ikke vælge barnets udgave (ingen vælger, eller
  // vælgeren har ikke den udgave), forbliver det et link, så barnet aldrig bliver uden adgang.
  const barnErAktivt = (k: KunIAeldreTekst | null): boolean => {
    if (!k || !v.aktivChip) return true;
    if (k.kunISourceIds.includes(v.aktivChip.sourceId)) return true;
    return !v.vaelger.chips.some((c) => k.kunISourceIds.includes(c.sourceId));
  };

  // Slægten: personer med en linje i stamtavlen hører til slægten (i dag kun Reventlow). Ægtefæller uden linje
  // står uden slægt i etiketten, frem for at blive tilskrevet en slægt, de ikke tilhører.
  const slaegt = v.linjer.length ? findSlaegt(STANDARD_SLAEGT) : null;
  const linjeNavne = v.hovedLinjer;
  // Bogens nummer (»V, nr. 1«) kun fra stamtavlens opslag — samme regel som feedets kilde-§ (bogensNummer).
  // Fuldt linjenavn i etiketten (»V. Den grevelige Linje af 1673, nr. 1«, projektejeren 2026-11-19).
  const nr = bogensNummer(model.sourcesBy, focusId, 'fuld');
  const etiket = [slaegt?.navn, ...(nr ? [nr] : linjeNavne)].filter(Boolean).join(' · ');
  const statuslinje = byggStatuslinje(model, focusId, hofKilder);
  const harVaelger = v.vaelger.form === 'chips' || v.vaelger.form === 'skift';
  const skiltTekst = (spId: string) => { const sk = parSkilsmisse(model, focusId, spId); return sk ? fmtSkilt(sk, 'dag') : undefined; };
  const henter = detail === null && !detailError;
  const konfOrd = (barn: string, foraelder: string) => konfTekst(model.indexes.konfByEdge?.[`${barn}|${foraelder}`]);
  const offices = detail?.offices ?? [];
  const visteEmbeder = visAlleEmbeder ? offices : offices.slice(0, FOERSTE_EMBEDER);
  const visteGodser = visAlleGodser ? v.godser : v.godser.slice(0, FOERSTE_GODSER);
  const portrait = v.portrait?.url ? v.portrait : null; // kun et portræt, der kan vises, får billedtekst
  const kopier = async () => {
    setKopieret(await delLink(`${window.location.origin}${personPath(focusId)}`, document.title, smal));
  };

  // Familie på telefonen: én spalte med etiketten over navnene (tegningen), ikke en smal etiketspalte.
  const dtStil: CSSProperties = smal ? { ...etiketStil, color: T.inkMuted, marginTop: 8 } : { color: T.inkMuted };
  const navneblok = (
    <>
      <h1 style={{ margin: 0, fontFamily: T.serif, fontSize: smal ? 32 : 44, lineHeight: 1.05, fontWeight: 500, color: T.ink, textWrap: 'balance' } as CSSProperties}>{p.name}</h1>
      {p.years && <p style={{ margin: 0, fontFamily: T.mono, fontSize: smal ? 13 : 14, lineHeight: '20px', color: T.inkMuted }}>{p.years}</p>}
      {statuslinje && <p style={{ margin: 0, fontSize: 15, color: T.bordeaux, fontWeight: 600 }}>{statuslinje}</p>}
    </>
  );
  // Handlingerne: højre spalte på bred skærm, lige under navnet på telefonen (fase 9, tegningen »Mobil – personside«).
  // Samme knapper begge steder, aldrig to gange — DOM-rækkefølgen er tab-rækkefølgen.
  const handlinger = (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {loggetInd && (
        <button type="button" aria-pressed={erBogmaerket} onClick={onToggleBogmaerke}
          style={{ ...knap, border: `1px solid ${erBogmaerket ? T.bordeaux : T.lineStrong}`, background: erBogmaerket ? T.bordeauxTint : T.surfaceRaised, color: erBogmaerket ? T.bordeaux : T.ink }}>
          {erBogmaerket ? 'Gemt i bogmærker' : 'Gem i bogmærker'}
        </button>
      )}
      <Link href={stamtraePath(slaegt?.slug ?? STANDARD_SLAEGT, focusId)} style={{ ...knap, background: T.bordeaux, color: T.onBordeaux, border: 0, textDecoration: 'none' }}>Vis i stamtræet</Link>
      <div style={{ display: 'flex', gap: 10 }}>
        {/* Knap, ikke link: personen kommer først i slægtskabets adresse i fase 6. */}
        <Link href={slaegtskabPath(focusId)} onNavigate={onFindSlaegtskab} style={{ ...knap, flex: 1, textDecoration: 'none' }}>Find slægtskab</Link>
        <button type="button" onClick={() => { void kopier(); }} style={{ ...knap, flex: 1 }}>{smal ? 'Del' : 'Kopiér link'}</button>
      </div>
      {onToggleMig && (
        <button type="button" aria-pressed={erMig} onClick={onToggleMig}
          title={erMig ? 'Fjern markeringen af dig' : 'Markér denne person som dig (gemmes kun i denne browser)'}
          style={{ ...knap, border: `1px solid ${erMig ? T.bordeaux : T.lineStrong}`, background: erMig ? T.bordeauxTint : T.surfaceRaised, color: erMig ? T.bordeaux : T.ink }}>
          {erMig ? 'Det er dig' : 'Det er mig'}
        </button>
      )}
      {onVisPraesens && (
        <button type="button" onClick={onVisPraesens} style={{ ...tekstKnap, alignSelf: 'flex-start', ...(smal ? { minHeight: 44 } : null) }}>Vis i præsensliste</button>
      )}
      <p role="status" aria-live="polite" style={{ margin: 0, minHeight: 20, fontSize: 13, color: kopieret === 'fejl' ? T.danger : T.inkMuted }}>
        {kopieret === 'kopieret' ? 'Linket er kopieret.' : kopieret === 'fejl' ? 'Linket kunne ikke kopieres. Kopiér adressen fra browserens adresselinje.' : ''}
      </p>
    </div>
  );

  return (
    <main style={{ maxWidth: 1240, margin: '0 auto', padding: smal ? '16px 16px 48px' : '24px 24px 64px', display: 'flex', flexDirection: 'column', gap: smal ? 16 : 24 }}>
      <nav aria-label="Brødkrumme" style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>
        <Link href="/" style={{ color: T.bordeaux }}>Aarbogen</Link>
        {slaegt && <> / <Link href={slaegtPath(slaegt.slug)} onNavigate={() => onSlaegt(slaegt.slug)} style={{ color: T.bordeaux }}>{slaegt.navn}</Link></>}
        {linjeNavne.length > 0 && <> / {linjeNavne.join(', ')}</>}
        {' / '}<span aria-current="page">{p.name}</span>
      </nav>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 40, alignItems: 'flex-start' }}>
        <article style={{ flex: '999 1 640px', minWidth: 0, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 4, boxShadow: shadow.card, padding: smal ? 20 : 'clamp(24px, 5vw, 64px)', display: 'flex', flexDirection: 'column', gap: smal ? 28 : 36 }}>
          <header style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'center' }}>
              {etiket ? <p style={{ ...etiketStil, color: T.goldInk }}>{etiket}</p> : <span />}
              {harVaelger && <Udgavevaelger chips={v.vaelger.chips} valgt={v.valgtIdx} onVaelg={v.vaelgChip} />}
            </div>
            <SlaegtskabsLinje kontekst={kontekst} meId={meId} focusId={focusId} onVisPerson={onVisPerson} />
            {smal && portrait?.url ? (
              <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
                <button type="button" onClick={() => setLightbox(0)} aria-label={`Vis portrættet af ${p.name} større`}
                  style={{ flex: 'none', width: 92, padding: 0, border: 0, background: 'none', cursor: 'zoom-in' }}>
                  <SignedImg src={portrait.url} alt={portrait.altTekst || `Portræt af ${p.name}`}
                    style={{ display: 'block', width: '100%', aspectRatio: '4 / 5', ...portraetTilpasning(portrait), background: T.surfaceSunken, borderRadius: radius.card, border: `1px solid ${T.line}` }} />
                </button>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
                  {navneblok}
                  {/* Billedtekst og kilde (kunstner, år, ejer/institution) — kilder vises også på telefonen. */}
                  {billedtekst(portrait) && <p style={{ margin: 0, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>Portræt: {billedtekst(portrait)}</p>}
                </div>
              </div>
            ) : navneblok}
            {kunI && <p style={{ margin: 0, fontSize: 13.5, color: T.inkMuted }}>{kunI.linje}</p>}
            {v.tidligereUdgave && <p style={{ margin: 0, fontSize: 13, color: T.inkMuted }}>Du ser en tidligere udgave.</p>}
            {v.linjeNoter.map((n) => <p key={n} style={{ margin: 0, fontSize: 13, color: T.inkMuted }}>{n}</p>)}
          </header>
          {smal && handlinger}

          {detailError ? (
            <Tilstand fejl etiket="Kunne ikke hente" titel="Personens oplysninger kunne ikke hentes"
              handlinger={<button type="button" onClick={onRetry} style={tilstandSekundaer}>Prøv igen</button>}>
              Forbindelsen til arkivet svigtede et øjeblik. Familien herunder er hentet; biografi, embeder og besiddelser mangler.
            </Tilstand>
          ) : (
            <>
              {/* Fakta med kilde (6e-1) på medlemslagets fakta-plads. */}
              {detail && (detail.factsError || (v.faktaVisning && (v.faktaVisning.linjer.length > 0 || v.faktaVisning.kunI.length > 0))) && (
                <div><PersonFakta visning={v.faktaVisning} error={detail.factsError} /></div>
              )}
              <Sektion titel="Biografi" vis={henter || v.vaelger.form !== 'skift' && (!!v.bioText || v.vaelger.form === 'chips')}>
                {henter ? <Henter /> : v.bioText ? (
                  <div style={{ maxWidth: '36em', fontSize: 16, lineHeight: '27px', color: T.ink }}>
                    {/* Redaktøren ser levende (decisions 2026-11-13): en kladde, gæster aldrig ser, siges med ord — med
                        kilden, fordi én kladde alene ikke giver nogen udgavevælger. */}
                    {v.aktivChip?.art === 'post' && v.aktivChip.version.kunRedaktion && (
                      <p role="note" style={{ margin: '0 0 12px', fontSize: 13, lineHeight: '18px', color: T.bordeaux, fontWeight: 600 }}>
                        Ikke udgivet — kun synlig for redaktionen. Kilde: {v.aktivChip.version.citationLabel || v.aktivChip.version.sourceLabel}.
                      </p>
                    )}
                    <NarrativRenderer tekst={v.bioText} onPickPerson={onVisPerson} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
                  </div>
                ) : <Mangel>Ingen biografi fra denne udgave.</Mangel>}
              </Sektion>
            </>
          )}

          <Sektion titel="Familie">
            <dl style={{ margin: 0, display: 'grid', gridTemplateColumns: smal ? 'minmax(0, 1fr)' : 'minmax(0, 140px) minmax(0, 1fr)', gap: smal ? '4px 0' : '10px 20px', fontSize: 15, lineHeight: '22px' }}>
              <dt style={dtStil}>Forældre</dt>
              <dd style={{ margin: 0 }}>
                {v.parents.length ? v.parents.map((pa) => (
                  <div key={pa.id}>
                    <PersonLink id={pa.id} navn={pa.name} aar={pa.years} konf={konfOrd(focusId, pa.id)} onVis={onVisPerson} />
                  </div>
                )) : <Mangel>Ikke angivet i Aarbogen.</Mangel>}
              </dd>
              {/* »Gift med« og »Børn« kun, når de har indhold (projektejeren 19/11): et barn, der døde ungt, skal ikke have
                  »Intet ægteskab angivet« eller »Ingen børn angivet«. En gift person uden børn får stadig »Ingen børn«.
                  Ingen kildelinjer i Familie (projektejeren 21/11): som ved fakta står kilden nederst på siden. */}
              {v.spouses.length > 0 && (<>
              <dt style={dtStil}>Gift med</dt>
              <dd style={{ margin: 0 }}>
                {v.spouses.map((sp, i) => (
                  <div key={(sp.id ?? sp.name) + i}>
                    {sp.id ? <PersonLink id={sp.id} navn={sp.name} aar={model.byId[sp.id]?.years} vielse={vielseBySpouse[sp.id]} skilt={skiltTekst(sp.id)} onVis={onVisPerson} /> : <span style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600 }}>{sp.name}</span>}
                  </div>
                ))}
              </dd>
              </>)}
              {(v.spouses.length > 0 || v.children.length > 0) && (<>
              <dt style={dtStil}>Børn</dt>
              <dd style={{ margin: 0 }}>
                {v.children.length ? (
                  <>
                    {(fam?.boerneGrupper ?? []).map((g, gi) => (
                      <div key={g.aegteskab?.unionId ?? g.aegteskab?.navn ?? `uden-${gi}`} style={{ marginTop: gi > 0 ? 10 : 0 }}>
                        {(fam?.aegteskaber.length ?? 0) > 1 && (
                          <p style={{ margin: '0 0 2px', fontFamily: T.serif, fontStyle: 'italic', fontSize: 16, color: T.inkSecondary }}>
                            {g.aegteskab ? `Med ${g.aegteskab.navn}` : 'Ægteskab ikke angivet'}
                          </p>
                        )}
                        {!g.aegteskab && fam?.boerneNote && <Mangel>{fam.boerneNote}</Mangel>}
                        <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
                          {g.boern.map(({ person: c }) => {
                            const barnKunI = kunIAeldreTekst(model, c.id);
                            return <li key={c.id}><PersonLink id={c.id} navn={c.name} aar={c.years} konf={konfOrd(c.id, focusId)} kunI={barnKunI} aktiv={barnErAktivt(barnKunI)} onVis={onVisPerson} /></li>;
                          })}
                        </ul>
                      </div>
                    ))}
                  </>
                ) : <Mangel>Ingen børn angivet i Aarbogen.</Mangel>}
              </dd>
              </>)}
            </dl>
          </Sektion>

          {!detailError && (
            <>
              {/* Embeder, besiddelser og billeder vises kun med indhold (projektejeren 19/11): kun ~8 % har embeder som
                  oplysning, resten står i biografien, så »Ingen … angivet i Aarbogen« var usandt eller bare støj. Skjult
                  under hentning, så en tom boks ikke flimrer ind og ud (samme regel som livsrejsen). */}
              <Sektion titel="Embeder og hverv" vis={!henter && offices.length > 0}>
                  <ol style={{ listStyle: 'none', margin: 0, padding: 0, fontSize: 15, lineHeight: '22px' }}>
                    {visteEmbeder.map((o, i) => (
                      <li key={i} style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 20px', padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <span style={{ flex: 'none', width: smal ? 92 : 140, fontFamily: T.mono, fontSize: 12, lineHeight: '22px', color: T.inkMuted }}>{o.period || '—'}</span>
                        <span style={{ flex: '1 1 240px', minWidth: 0, color: T.ink }}>{o.label}</span>
                      </li>
                    ))}
                    {offices.length > FOERSTE_EMBEDER && (
                      <li style={{ padding: '9px 0', borderTop: `1px solid ${T.line}`, borderBottom: `1px solid ${T.line}` }}>
                        <button type="button" aria-expanded={visAlleEmbeder} onClick={() => setVisAlleEmbeder((x) => !x)} style={tekstKnap}>
                          {visAlleEmbeder ? 'Vis færre' : `Vis alle ${offices.length} embeder og hverv`}
                        </button>
                      </li>
                    )}
                  </ol>
              </Sektion>

              <Sektion titel="Besiddelser" vis={!henter && v.godser.length > 0}>
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 220px), 1fr))', gap: '0 24px', fontSize: 15, lineHeight: '22px' }}>
                    {visteGodser.map((e) => (
                      <li key={e.id} style={{ padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <Link href={estatePath(e.id)} style={{ color: T.bordeaux }}>{e.navn}</Link>
                      </li>
                    ))}
                    {v.godser.length > FOERSTE_GODSER && (
                      <li style={{ padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <button type="button" aria-expanded={visAlleGodser} onClick={() => setVisAlleGodser((x) => !x)} style={tekstKnap}>
                          {visAlleGodser ? 'Vis færre' : `Vis alle ${v.godser.length} besiddelser`}
                        </button>
                      </li>
                    )}
                  </ul>
              </Sektion>

              {/* Livsrejsen vises kun, når personen har steder; de fleste har ingen, og en tom boks ville
                  bare flimre ind og ud, mens geo hentes. */}
              <Sektion titel="Livsrejse" vis={livsrejse.length > 0}>
                <Suspense fallback={<MapFallback />}>
                  <ExpandableMiniMap points={livsrejse} />
                </Suspense>
              </Sektion>

              <Sektion titel="Billeder og dokumenter" vis={!henter && v.gallery.length > 0}>
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 150px), 1fr))', gap: 12 }}>
                    {v.gallery.map((m) => (
                      <li key={m.id}>
                        <figure style={{ margin: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
                          <BilledKnap m={m} onClick={() => setLightbox(v.lightboxItems.findIndex((x) => x.id === m.id))} />
                          <figcaption style={{ fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{billedtekst(m) || m.slags}</figcaption>
                        </figure>
                      </li>
                    ))}
                  </ul>
              </Sektion>
            </>
          )}

          <footer style={{ display: 'flex', flexDirection: 'column', gap: 6, borderTop: `1px solid ${T.line}`, paddingTop: 14 }}>
            <p style={{ ...etiketStil, color: T.inkMuted }}>Kilde i Aarbogen</p>
            {v.sources.length ? v.sources.map((s, i) => (
              <p key={i} style={{ margin: 0, display: 'flex', flexWrap: 'wrap', gap: '4px 12px', alignItems: 'baseline' }}>
                <span aria-hidden="true" style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.bordeaux }}>§</span>
                <span style={{ fontSize: 14, fontWeight: 600, color: T.ink }}>{s.work}</span>
                {s.ref && <span style={{ fontFamily: T.mono, fontSize: 12, color: T.inkMuted }}>{s.ref}</span>}
              </p>
            )) : henter ? <Henter /> : <Mangel>Ingen kildehenvisning registreret.</Mangel>}
          </footer>
        </article>

        <aside style={{ flex: '1 1 300px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 20 }}>
          {/* Telefonen: portrættet står som miniature ved navnet; billedteksten vises i lysboksen. */}
          {!smal && <figure style={{ margin: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
            {portrait?.url ? (
              <button type="button" onClick={() => setLightbox(0)} aria-label={`Vis portrættet af ${p.name} større`}
                style={{ padding: 0, border: 0, background: 'none', cursor: 'zoom-in', display: 'block', width: '100%' }}>
                <SignedImg src={portrait.url} alt={portrait.altTekst || `Portræt af ${p.name}`}
                  style={{ display: 'block', width: '100%', aspectRatio: '4 / 5', ...portraetTilpasning(portrait), background: T.surfaceSunken, borderRadius: radius.card, border: `1px solid ${T.line}` }} />
              </button>
            ) : (
              <div role="img" aria-label="Intet portræt" style={{ aspectRatio: '4 / 5', width: '100%', borderRadius: radius.card, border: `1px solid ${T.line}`, background: `repeating-linear-gradient(135deg, ${T.surfaceSunken} 0 12px, ${T.surfaceGround} 12px 24px)`, display: 'flex', alignItems: 'flex-end', padding: 14 }}>
                <span style={{ ...etiketStil, color: T.inkMuted, background: T.surfaceRaised, padding: '4px 8px', borderRadius: radius.badge }}>Portræt</span>
              </div>
            )}
            <figcaption style={{ fontSize: 13, lineHeight: '19px', color: T.inkMuted }}>
              {henter ? 'Henter billeder …' : portrait ? (billedtekst(portrait) || 'Uden billedtekst.') : 'Intet portræt i Aarbogen.'}
            </figcaption>
          </figure>}

          {slaegt && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: radius.card, padding: 20 }}>
              <SlaegtsMaerke slaegt={slaegt} size={56} monogram={
                <span aria-hidden="true" style={{ width: 40, height: 40, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux }}>{slaegt.navn[0]}</span>
              } />
              <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkSecondary }}>Slægten {slaegt.navn}{linjeNavne.length ? ` · ${linjeNavne.join(', ')}` : ''}</p>
              <Link href={slaegtPath(slaegt.slug)} onNavigate={() => onSlaegt(slaegt.slug)} style={{ fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Til slægtens forside</Link>
            </div>
          )}

          {!smal && handlinger}
          {!loggetInd && (
            <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkMuted }}>
              <button type="button" onClick={onLogin} style={{ ...tekstKnap, fontSize: 13.5 }}>Log ind</button> for at gemme {p.name} under dine bogmærker.
            </p>
          )}
        </aside>
      </div>

      {lightbox != null && (
        <Lightbox items={v.lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </main>
  );
}

const etiketStil = { margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '.16em', textTransform: 'uppercase' } as const;
const tekstKnap = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer' } as const;
const knap = { display: 'flex', justifyContent: 'center', fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '12px 14px', borderRadius: radius.field, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' } as const;

function Sektion({ titel, children, vis = true }: { titel: string; children: ReactNode; vis?: boolean }) {
  if (!vis) return null;
  return (
    <section style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <h2 style={{ ...etiketStil, color: T.inkMuted }}>{titel}</h2>
      {children}
    </section>
  );
}

function Mangel({ children }: { children: ReactNode }) {
  return <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', color: T.inkMuted }}>{children}</p>;
}

function Henter() {
  return <p style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>Henter …</p>;
}

function PersonLink({ id, navn, aar, vielse, skilt, konf, kunI, aktiv = true, onVis }: { id: string; navn: string; aar?: string; vielse?: string; skilt?: string; konf?: string; kunI?: KunIAeldreTekst | null; aktiv?: boolean; onVis: (id: string) => void }) {
  return (
    <span style={{ display: 'inline-flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '2px 10px' }}>
      {aktiv
        ? <Link href={personPath(id)} onNavigate={() => onVis(id)} style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.bordeaux }}>{navn}</Link>
        : <span style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.inkMuted }}>{navn}</span>}
      {/* Vielsen efter ægtefællens livsdatoer, adskilt med komma, så den ikke læses som hendes livsdato, og navnene
          holder linje (projektejeren 2026-11-24; »foran navnet« forskød navnene). */}
      {(aar || vielse || skilt) && <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{[aar, vielse, skilt].filter(Boolean).join(', ')}</span>}
      {/* Usikkert slægtskab vises med ordet, aldrig skjult (invariant 7). */}
      {konf && <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', color: T.danger }}>{konf}</span>}
      {kunI && <span title={kunI.forklaring} style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', color: T.goldInk }}>{kunI.maerke}</span>}
    </span>
  );
}

function BilledKnap({ m, onClick }: { m: MediaItem; onClick: () => void }) {
  if (!m.url) return null;
  return (
    <button type="button" onClick={onClick} aria-label={`Vis ${m.titel || m.slags || 'billedet'} større`}
      style={{ padding: 0, border: 0, background: 'none', cursor: 'zoom-in', display: 'block' }}>
      <SignedImg src={m.thumbUrl ?? m.url} alt={m.altTekst || m.titel || m.slags || 'billede'}
        style={{ display: 'block', width: '100%', aspectRatio: '1', objectFit: 'cover', borderRadius: radius.field, border: `1px solid ${T.line}` }} />
    </button>
  );
}

// Billedtekst: titel · kunstner · datering (mediaCaption; struktureret datering vinder) + kreditlinje/institution.
function billedtekst(m: MediaItem): string {
  return [mediaCaption(m), m.kreditlinje ?? m.kildeInstitution].filter(Boolean).join(' · ');
}

// Udgavevælgeren som segmenteret kontrol (tegningen), med samme chips og valg som panelets knapper.
function Udgavevaelger({ chips, valgt, onVaelg }: { chips: UdgaveChip[]; valgt: number; onVaelg: (idx: number) => void }) {
  return (
    <div role="group" aria-label="Udgave" style={{ display: 'inline-flex', flexWrap: 'wrap', background: T.surfaceSunken, borderRadius: radius.field, padding: 3, gap: 2 }}>
      {chips.map((c, i) => (
        <button key={`${c.art}:${c.sourceId}:${i}`} type="button" aria-pressed={i === valgt} onClick={() => onVaelg(i)}
          style={{ fontFamily: T.sans, fontSize: 13, lineHeight: '18px', fontWeight: 600, padding: '6px 12px', borderRadius: 8, border: 0, cursor: 'pointer',
            background: i === valgt ? T.surfaceRaised : 'transparent', color: i === valgt ? T.bordeaux : T.inkSecondary }}>
          {c.label}
        </button>
      ))}
    </div>
  );
}
